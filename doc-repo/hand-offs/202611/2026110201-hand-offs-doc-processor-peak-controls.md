# Handoff: doc-processor peak-hour controls

**Date:** 2026-11-02  
**Status:** Picked up and implemented the same day (see "Resolution"). The sections after it are the
original hand-off, kept as written.  
**Scope:** `ChenWeb/server/cmd/doc-processor` only. PDF parser and doc-service are not task engines for this work.

## Resolution (2026-11-02)

Implemented under OpenSpec change `ChenWeb/openspec/changes/doc-processor-peak-controls/` (not yet
archived) and committed: shared `mpuk` ("llm: gate every provider request; record usage event
kind"), ChenWeb `uvmv` ("doc-processor: engine-wide peak-hour control with cross-peak rules"). The
current description is the devdoc
`KnowledgeStore/doc-repo/devdocs/202609/2026092802-devdoc-offpeak-only-auto-processing.md`.

| Work item below | Outcome |
|---|---|
| 1. Admission and the per-document mode | The user decided (2026-11-02): a task's own mode wins, and the engine `default_mode` applies only when the task has none. An `auto_offpeak` upload gives its task mode `auto_offpeak`; plain `auto` follows the engine. Admission runs before routing, releases the slot, shows a waiting note, can be stopped, and re-checks after taking a slot back. The old per-processor gate and its 10-minute look-ahead were removed. The upload option and its UI are unchanged. |
| 2. `abort` | Cancels the task with a cause that every existing stop check honours, during routing, processors and Phase C alike. The task ends `stopped` with "aborted at peak-hour boundary" on its status and run row, and is not resumed. |
| 3. `pause-llm` | `llm.RequestGate` in shared is passed by every provider request of the shared clients (text, structured output, embeddings, retries; openai, anthropic, jev, jev_emulated). A request already sent finishes. A held call gives back its model permit. The temporary startup rejection was removed. |
| 4. Hold/resume events | Logged in the doc-processor log and written as `llm_usage_event` rows with new column `event_kind` (`llm_hold`, `llm_resume`, `llm_hold_cancelled`; migration `20261102000001`), paired by `metadata_json.hold_id`. Usage aggregates count only `request` rows. A failed write is logged and never blocks the call. |
| 5. Tests and docs | Unit and integration tests cover the listed cases, including a real `OpenAIJSONClient` against a test server. The startup config path was checked with the local override. The spec, devdoc and `config.toml` were updated, and `pause-exec` is documented as unsupported. |
| 6. Shared-library rules | Shared tests pass and `tax` builds. No dependency changed, so `go work sync` was not needed. The shared commit holds only this feature's hunks. |

**Still open:**
- A live doc-processor run across a real peak boundary has not been observed. Neither have hold/resume rows written by a live run, nor the new labels in a browser.
- The shared working copy still holds unrelated uncommitted work (alert sink, `Host` field, list-form embedding input). Because the commit leaves that work out, hold/resume rows carry no `metadata.host`.
- `TestKBMetricsReadersExcludeResolvedRows` still fails on `kbhandler/question_generator_worker.go`. That failure is unrelated to this work.
- Peak modes for auto-launched tasks were deferred by the user.

## Requested behavior

The doc-processor engine has `default_mode`: `none` (default, peak control disabled), `auto_peak` (work during peak), or `auto_offpeak` (work during off-peak). A waiting task starts when its permitted span returns. The user requested the following `cross_peak_mode` values for active tasks: `ignore` (default, continue), `pause-llm` (continue until an LLM call, then hold it until the span changes), and `abort` (abort tasks). `pause-exec` is not supported for now.

The engine must log task holds and starts/resumes. Each LLM call hold and resume must produce an engine log entry and a corresponding `public.llm_usage_event` entry. The existing per-document upload option and original gate are described in `KnowledgeStore/doc-repo/devdocs/202609/2026092802-devdoc-offpeak-only-auto-processing.md`; update that document and the applicable OpenSpec contract after implementation. Engine mode `none` was interpreted in this work as disabling the old per-document gate too; verify the intended migration of the existing upload option and its UI so it does not promise behavior that no longer occurs.

The user's local `ChenWeb/config.local.toml` now contains valid TOML:

```toml
[[task-engines.doc-processor]]
default_mode = "auto_offpeak"
cross_peak_mode = "ignore"
```

The original block used `:` and a trailing comma; those were corrected. The local file is ignored by version control. The code must use the merged application config, not assume this local setting is present elsewhere.

## Working-tree state

Do not overwrite or commit unrelated work. All work below is uncommitted:

- **ChenWeb:** `server/cmd/config/task_engine.go` and its test parse and validate the singleton array, defaults, and allowed values. `server/api/doc-processing/task_engine_policy.go` and its test implement an initial admission wait and cancellation monitor. `control.go` wires admission before routing and releases the pipeline slot while waiting; `runtime.go` loads the config and constructs the policy. It rejects an enabled `pause-llm` at startup because it is not implemented. `runtime.go` no longer wires the old `OffPeak` gate, so this is a behavior change even for existing uploads. Review these changes before continuing; they are not a complete implementation.
- **shared:** `go/api/llm/request_gate.go` and its test add a context callback. Three calls in `go/api/llm/openai_client.go` invoke it for text and embedding calls. The hook is **not wired to doc-processor**. The shared repository had unrelated uncommitted changes before this work, including changes in the same `openai_client.go` file; preserve those hunks and do not commit the entire working copy as this feature.
- **KnowledgeStore:** `Topics/topic-ontology-SWRL.md` is a pre-existing unrelated uncommitted file. Prior documentation updates are commits `5d6e` and `d6ac`.

## Work remaining

1. Finish and review admission semantics for `none`, `auto_peak`, and `auto_offpeak`, including cancellation, evaluation errors, status, logging, slot release, and rechecking the allowed period after reacquiring a slot. Decide how existing per-document `auto_offpeak`, the old ten-minute lead time, and the engine-level setting interact; do not silently change the upload contract.
2. Complete `abort` for every active task, including work during routing and post-processing. Confirm cancellation reaches in-flight operations, yields an accurate stopped/aborted status, does not resume aborted work, and handles shutdown and concurrent tasks. The current monitor polls and uses the existing `ErrPipelineStopped`; its end-to-end behavior has not been verified.
3. Wire `pause-llm` into all relevant provider calls, including structured output, text, embeddings, retries, and calls made during routing. Ensure context propagation and cancellation work while held, no provider request occurs during the disallowed span, and already in-flight calls have a documented policy. Review whether the partial shared hook is the correct boundary and remove the temporary startup rejection only after this works.
4. Write both hold and resume events to the engine log and `public.llm_usage_event`, with correlation, task/run/user attribution, and a representation that will not incorrectly count the two lifecycle events as billable requests in existing usage reports. Define and test failure handling for event writes. No such event writes exist yet.
5. Add integration and boundary-transition tests, including `ignore`, both directions, mode `none`, active and waiting cancellation, simultaneous tasks, clock/peak-evaluation errors, and real LLM request interception. Validate the configuration and local override through the actual startup path. Update the documentation and spec to reflect the verified implementation and the unsupported `pause-exec` value.
6. Follow workspace rules for shared changes: test `shared/go`, run `go work sync` if shared dependencies change, build/test dependents, and commit shared and ChenWeb separately through `jj`. Preserve all pre-existing changes when isolating the shared commit.

## Verification performed

- Focused tests passed: `go test ./server/cmd/config ./server/api/doc-processing -run '^(TestDocProcessorTaskEngineConfig|TestTaskEngineWaitForAllowed|TestTaskEngineAbortOnBoundary)$'`.
- Shared hook unit test passed: `go test ./go/api/llm -run TestRequestGateReturnsCancellation` from `shared/`.
- The full `go test ./server/api/doc-processing ./server/cmd/config` run failed `TestKBMetricsReadersExcludeResolvedRows`: the guard reported `server/api/kbhandler/question_generator_worker.go:133`, a `kb.metrics` query without the required `ref_mention_id` predicate. This was not investigated against a clean baseline; do not assume its cause or fix it as part of this feature without checking.
- No end-to-end peak transition, actual LLM hold/resume, database lifecycle event, or deployed behavior was verified.
