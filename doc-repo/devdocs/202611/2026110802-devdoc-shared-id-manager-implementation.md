# Shared ID manager implementation plan

**Date:** 2026-11-08
**Design:** [Shared ID Manager](2026110801-devdoc-shared-id-manager.md)

Implement the shared allocator and activity-log replacement in the existing shared
repository, plus the ChenWeb LLM execution cutover. The user confirmed the sequence
names `llm_run_id` and `activity_log_id`. Use existing centralized pools and drivers.

- [x] Add allocator tests for validation, provisioning, caching, cancellation,
  rollback, uncertain commit, exhaustion, reuse and concurrent managers.
- [x] Implement `shared/go/api/idmanager/` with per-sequence cancellable locks,
  row-locked reservations and publication only after commit.
- [x] Add and embed the shared Goose migration; test fresh and legacy schemas,
  repeat application, constraints, and conservative rollback.
- [x] Replace activity-log ID allocation and startup provisioning; remove the
  unused ID store, table creator, types and configuration.
- [x] Migrate ChenWeb numeric LLM run-ID writers to `llm_run_id`, retaining local
  run table identities. Persist queued execution identity for redelivery and resume;
  keep 0 after allocation failure. Check peak-waiting filters and alarm correlation.
- [x] Run isolated PostgreSQL integration tests and race checks, shared tests,
  and ChenWeb/tax builds. Review the diff against the design.
- [x] Reconcile the design, update shared guidance, document and catalogue the
  reusable module, and commit only task changes through `jj`.

Verification uses a disposable local PostgreSQL cluster. Do not migrate the running
application databases: deployment requires stopping old activity-log writers.

## Verification results

- Full shared `go test ./...` and targeted `go vet` pass.
- Shared `go test -race ./api/idmanager ./api/sysdatastores ./api/goose` passes
  with `IDMANAGER_TEST_DSN` pointing at a disposable `idmanager_test_*` database.
  This includes fresh/legacy conversion, Goose Down/Up, concurrency across pools,
  cancellation, cache tails, and rollback induced by a database trigger.
- ChenWeb `go build -buildvcs=false ./server/cmd/...` and tax
  `mise build-server` pass.
- ChenWeb race checks pass for `llmrun` (including isolated PostgreSQL through
  `LLMRUN_TEST_DSN`), reviews, converters, JetStream handlers, and configuration.
  Focused processing and handler tests pass for local/LLM ID separation,
  pause/resume events, peak-wait filtering, scoring repair calls, question
  generation, saved allocation failures and binding-persistence errors.
- Broader affected ChenWeb packages retain six existing failing tests, independently
  reproduced from the parent revision in a separate temporary checkout:
  `TestProvisionsDefaultPromptUsesCompactFormat`,
  `TestKBMetricsReadersExcludeResolvedRows`,
  `TestPlanInputDeletePathsRefusesFolderNotNamedAfterRecord`,
  `TestPlanInputDeletePathsRefusesUnrelatedRecordFolder`,
  `TestMetricScoreScorerParityAndInvalidMatches`, and
  `TestMetricScoreRunnerEndToEnd`. Updated fixtures preserve their baseline
  failure causes rather than hiding new SQL expectation failures.
- Independent review approved the shared implementation and the ChenWeb integration
  after fixing binding-persistence failure paths and preserving the existing
  project-before-shared migration dependency order.

## Knowledge and scope

The design document now describes the implemented API, startup and deployment.
Shared guidance, shared LLM API comments, processing-run ADR clarification,
attribution documentation, search specification/benchmark documentation, and
question-generator documentation were updated. The reusable module document and
catalogue row both identify `20261108-01`, version `1.0.0`.

Historical ADR bodies remain as decision history with clarifications. Existing
unattributed LLM endpoints, historical run-ID collisions, activity-log INTEGER
widening, and asynchronous queue acknowledgement are intentionally outside this
change; the design records these limits. No dependencies changed, so no workspace
dependency synchronization was needed. Deployment was not performed.
