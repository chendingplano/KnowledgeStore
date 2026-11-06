# Document processor isolation — keep concurrent documents' results separate

**Date:** 2026-11-06 \
**Scope:** Concurrent document processing, the onto production incident, and recovery requirements. \
**Code root:** `ChenWeb/server/api/doc-processing/`

## Summary

Each production document-processing run now gets its own processors and model clients.
Documents can still run concurrently, but their chunks, extracted results, current record
IDs, and processing flags cannot overwrite one another. Database connections and the limit
on simultaneous document runs remain shared.

Previously, overlapping runs reused processors that held the current document's state.
An apparently successful run could save no metrics for its document, or save results under
another document. Running one document again later could therefore appear to fix the issue.

## Details

### Ownership and configuration

- `NewProductionRuntime` validates a processor graph at startup and exposes it as the
  configured catalog through `ProductionRuntime.Processors` and `Control.Processors`.
- Its private `ControlService.newRunProcessors` factory creates a fresh graph after a
  document passes peak-hour admission. Automatic events and explicit processor requests
  use that graph through extraction, finalization, and post-processing.
- The blocking processor, the fixed-size chunking service shared *within* a graph, all
  extraction processors, their accumulators and mutexes, and their model clients belong
  to that run. The implementation uses constructors rather than copying mutex-bearing
  structs or copying pointers to clients.
- Required processor names and runtime overrides are copied when the runtime is built.
  Each new graph receives the same selection and overrides, with configuration validation.
  Constructor-loaded prompts/model settings are read again for each graph; this is not a
  mechanism for live configuration changes. Deploy configuration consistently and restart
  the worker after changing it.
- A graph-construction error is logged and returned before any processor executes. Shared
  catalog instances are never used as a fallback.
- Database pools, pipeline admission, stop handling, routing stores, and event/run logging
  remain owned by the shared controller. `MAX_DOC_PROCESS_PIPELINES` continues to control
  document concurrency; concurrency within each document is unchanged.
- Directly constructed `ControlService` values without the production factory continue
  to use their supplied processors. Embedders using that low-level interface must supply
  independent processor instances if they invoke it concurrently. Production callers should
  use `NewProductionRuntime`.

### Production evidence from 2026-11-06

Times below are China time, as recorded in the production journal.

| Record | Observed behavior |
| --- | --- |
| 219 | Automatic metric batch started at 18:02:47. Other documents initialized the same processor before it finished at 18:04:51. Its chunks produced results, but no metrics were saved under 219. The later manual run saved 630 metrics. |
| 218 | Metric batch initialized at 18:05:44; records 214 and 196 initialized before it finished at 18:06:01. It reported success with no metrics. |
| 212 | Repeated finalizations during overlapping runs saved up to 699 metrics under 212. Its rows require a source audit; their count does not demonstrate correctness. |
| 214 | The automatic request ended with failure at 18:06:34, and the database count was zero during the investigation. |

The defect is broader than `extract_metrics_simple`: several processors implement the
same stateful `InitChunkBatch` / `ProcessChunk` / `FinalizeChunkBatch` lifecycle. Isolation
therefore applies to the complete production processor graph.

### Verification

`runtime_isolation_test.go` forces records 218 and 219 to enter the real simple metric
extractor before either call returns. It verifies that each document saves only its own
metric, covering automatic/manual selection and merge/force-clear modes. Before the fix,
the test left 218 empty and saved its metric under 219. Additional tests check independent
chunking services, blocking processors and model clients, retained overrides, and refusal
to process after a graph-construction failure.

### Deployment and recovery

Deploy the rebuilt `doc-processor` binary using the
[onto deployment runbook](../202609/2026090701-devdoc-deploy-start-system-onto.md).
No schema or configuration change is required. The change is effective only after the
worker restarts with the new binary; it does not repair previously stored results.

Before reprocessing affected documents, preserve the original metrics, processing logs,
and run history. Audit the full overlapping batch, including documents with nonzero counts,
for missing or misplaced results. Re-extraction must replace contaminated results rather
than merge them into the corrected extraction. Review dependent indexes and semantic
artifacts when planning that recovery.

## Known limitations

Per-run processor ownership does not serialize two independent requests for the same
record. Operators should avoid submitting overlapping replacement runs for one record.
Existing partial-extraction and model-failure policies are unchanged.
