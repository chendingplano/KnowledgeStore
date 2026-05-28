# Parallel Doc Processor Pipelines Implementation

## Files Changed

- `ChenWeb/server/api/doc-processing/control.go`
- `ChenWeb/server/cmd/doc-processor/main.go`
- `ChenWeb/server/api/doc-processing/control_test.go`

## Design

`ControlService.HandleJetStreamEvent` now acquires a pipeline slot before launching the goroutine that runs `handleEvent`. The slot is released when that goroutine exits.

This keeps the existing asynchronous pipeline model: each accepted event still runs on a separate goroutine. The difference is that the number of active goroutines running full document pipelines is bounded by the configured limit.

## Configuration

`docprocessing.MaxDocProcessPipelinesFromEnv()` reads `MAX_DOC_PROCESS_PIPELINES`.

Fallback behavior:

- unset: `10`
- invalid integer: `10`
- zero or negative: `10`

`ControlService.MaxDocProcessPipelines` can override the environment value for tests or explicit wiring.

## Backpressure

Slot acquisition happens before the pipeline goroutine starts. When the limit is reached, the JetStream callback waits for a slot instead of spawning another active pipeline. This avoids unbounded active processor chains while keeping the existing subscription flow.

After a slot is acquired, `ControlService` writes a `doc_processing` status entry with `proc_status = "running"` to `kb.inputs.status`. When the pipeline exits, the same entry is replaced with `success` or `failed`. The Doc Processor dashboard uses this marker to show actual active slots instead of newest unfinished records.

## Logging

`server/cmd/doc-processor/main.go` sets `MaxDocProcessPipelines` on the control service and adds `max_doc_process_pipelines` to the startup log.
