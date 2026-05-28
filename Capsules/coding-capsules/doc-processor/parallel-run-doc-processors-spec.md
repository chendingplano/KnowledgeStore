# Parallel Doc Processor Pipelines Spec

## Goal

The doc processor must run multiple document-processing pipelines in parallel while preserving a configurable upper bound on active pipelines.

## Requirements

- `MAX_DOC_PROCESS_PIPELINES` defines the maximum number of active doc-processing pipelines in one doc-processor process.
- Each accepted pipeline runs in its own goroutine.
- When the cap is reached, new JetStream events wait before a pipeline goroutine starts.
- If `MAX_DOC_PROCESS_PIPELINES` is unset, invalid, or less than one, the process uses a default of `10`.
- The cap applies to whole document pipelines, not to individual processors inside one document pipeline.
- Existing processor ordering inside a single pipeline remains unchanged:
  - blocking processor first
  - selected or configured processors afterward

## Non-Goals

- Do not parallelize processors within a single document pipeline.
- Do not change JetStream stream, durable, or subject configuration.
- Do not change database schema.

## Operational Notes

The doc-processor startup log includes `max_doc_process_pipelines` so operators can confirm the effective concurrency cap.
