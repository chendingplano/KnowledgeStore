# Parallel Doc Processor Pipelines Test Notes

## Automated Test

`TestControlService_HandleJetStreamEvent_RespectsMaxDocProcessPipelines` covers the new concurrency cap.

Test behavior:

- sets `MAX_DOC_PROCESS_PIPELINES=2`
- launches four JetStream events
- blocks the first two processor calls
- verifies a third pipeline does not start before one slot is released
- releases the processors and verifies observed concurrency never exceeds two

## Red-Green Evidence

Initial red run:

```text
go test ./server/api/doc-processing -run 'TestControlService_HandleJetStreamEvent_RespectsMaxDocProcessPipelines|TestControlService_HandleJetStreamEvent_DoesNotFailWhenEventInsertFails'
--- FAIL: TestControlService_HandleJetStreamEvent_RespectsMaxDocProcessPipelines
    control_test.go:210: third pipeline started before a pipeline slot was released
```

Green run after implementation:

```text
go test ./server/api/doc-processing -run 'TestControlService_HandleJetStreamEvent_RespectsMaxDocProcessPipelines|TestControlService_HandleJetStreamEvent_DoesNotFailWhenEventInsertFails'
ok  	github.com/chendingplano/deepdoc/server/api/doc-processing	0.063s
```

## Manual Check

Start the doc processor with a larger cap:

```bash
MAX_DOC_PROCESS_PIPELINES=4 go run ./server/cmd/doc-processor
```

The startup log should include:

```text
max_doc_process_pipelines=4
```
