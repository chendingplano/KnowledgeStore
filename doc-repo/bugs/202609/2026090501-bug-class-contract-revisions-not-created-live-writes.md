# Class contract revisions are never created by live metric writes, contradicting the code and the class-contracts manual

Date: 2026-09-05

Status: `fixed-verified` (2026-09-05). Root cause: the server process that ran
record 416's Phase D at 09:25 was a **stale binary** compiled before commit
`be4d` (2026-09-04 19:21) wired `ContractStore.EnsureHeader` /
`DeclareCanInstantiate` into `resolveOrCreateMetricClass`. Pre-`be4d`, that
function was only `resolveOrSynthesizeMetricClassTerm` with no contract-header
step, so it committed the represented assertion and its
`kb.ontology_class_resolution_decisions` row and never touched
`kb.ontology_class_contract_revisions` — exactly the observed symptom. The
current source is correct; there is no code defect. See **Resolution** below.

System: `ChenWeb` document processing / class contract mechanism
(openspec change `metric-class-contracts`, commit `be4d`)

Component: `classfoundation.ContractStore.EnsureHeader` /
`AppendContractRevision`, `assertions.resolveOrCreateMetricClass`,
`assertions.writeMetricLossless`, `associate_semantics`

Input record: `416`

Related: [Class Contracts manual](../../user-manuals/class-contracts-v1.0-en.md),
`ChenWeb/openspec/changes/metric-class-contracts/`,
`ChenWeb/server/api/ontology/classfoundation/contracts_store.go`,
`ChenWeb/server/api/ontology/assertions/metric_lossless_writer.go`.

## Summary

The class-contracts manual (§4, §8) states that every class resolved or
created during a metric write is given a contract, starting at
`identity_only`, and that this "happens automatically... nothing separate
needs to be run" — the mechanism is described as "wired into the live write
path." The code matches that description: `resolveOrCreateMetricClass`
(`metric_lossless_writer.go:268-287`) unconditionally calls
`ContractStore.EnsureHeader` for every class it resolves, and `EnsureHeader`
(`contracts_store.go:136-168`) always leaves the class with at least an
`identity_only` revision and a non-null
`kb.ontology_term_headers.current_contract_revision_id`.

In the live `miner` database, this is not happening. After record 416 was
reprocessed through `extract_metrics` → `normalize_assertions` →
`associate_semantics` → `project_semantics` today, all 56 of its metric
classes still have a `NULL` `current_contract_revision_id`, and
`kb.ontology_class_contract_revisions` has **zero rows for the entire
database** — not just for these 56 classes. This matches the manual's own
§8 observation (also zero, timestamped 06:49 today), but that observation
was taken *before* record 416's reprocessing; record 416's run happened
*after* it and still produced zero revisions.

## Expected behavior

Per `EnsureHeader`'s contract and the manual's §4/§9 worked example: the
first time any class is resolved through `resolveOrCreateMetricClass` after
the mechanism activated, it should receive an `identity_only` contract
revision, and its header's `current_contract_revision_id` should point at
that revision. This should happen unconditionally, on every metric write,
regardless of whether the class is newly created or an existing class being
re-resolved.

## Actual behavior and database evidence

```sql
select count(*) from kb.ontology_class_contract_revisions;
--  0

select count(*) from kb.ontology_class_contract_capabilities;
--  0

select a.id, a.instance_of_term_id, a.conformance_state_term_id,
       a.normalized_against_contract_revision_id
from kb.semantic_assertions a
join kb.semantic_decision_candidates dc on dc.resulting_assertion_id = a.id
where dc.input_record_id = 416 and dc.status = 'accepted';
--  56 rows, all conformance_state_term_id = semantic:not_evaluated,
--  all normalized_against_contract_revision_id = NULL
```

All 56 assertions were freshly created today:

```sql
select id, create_time, create_by from kb.semantic_assertions where id = 822;
--  822 | 2026-09-05 09:25:12.453091-05 | metric_lossless_writer
```

Critically, `kb.ontology_class_resolution_decisions` — written by
`RecordIfChanged` in `writeMetricLossless`, strictly *after*
`resolveOrCreateMetricClass` (and therefore `EnsureHeader`) returns, inside
the same transaction — has a row for this exact class at the exact same
microsecond as the assertion:

```sql
select id, selected_class_term_id, identity_state, create_time
from kb.ontology_class_resolution_decisions
where selected_class_term_id = 'measurement:kwc_14c72be88731'
order by create_time desc limit 1;
--  226 | measurement:kwc_14c72be88731 | resolved_existing | 2026-09-05 09:25:12.453091-05
```

This proves `resolveOrCreateMetricClass` executed, inside the transaction
that committed assertion 822, today. It does not explain why no contract
revision resulted.

## What was ruled out

1. **The mechanism itself is broken.** Ruled out. An isolated Go program
   (`server/cmd/debugcontract`, written for this investigation and deleted
   afterward) called `(classfoundation.ContractStore{DB: tx}).EnsureHeader`
   directly against the live `miner` database, in its own transaction, for
   both the exact term `measurement:kwc_14c72be88731` and a fresh, never-seen
   term. Both calls succeeded immediately, creating a correct `identity_only`
   revision and setting the header pointer. `AppendContractRevision`'s SQL
   (`contracts_store.go:101-126`) and `current()`'s lookup join
   (`contracts_store.go:180-194`) are correct.

2. **The writer gate is off.** Ruled out. `LOSSLESS_SEMANTIC_WRITES_METRIC`
   defaults to `true` in code (`semantic/gates.go`) and is confirmed
   explicitly set to `true` in the actual running server process's
   environment (`ps`/`/proc/<pid>/environ` on the live dev-server PID).

3. **A stale server binary.** Ruled out. The running `.cache/server.exe`
   (last successfully built 2026-09-05 07:25, after commit `be4d` at
   2026-09-04 19:21) contains the unique error strings introduced by this
   change (`"ensure class contract header: %w"`,
   `"declare can_instantiate capability: %w"`), confirmed via `strings` on
   the binary.

4. **Wrong target database.** Ruled out. The running server's `PG_DB_NAME`
   is `miner`, matching every query above.

5. **A second, older write path setting the same fields.** Ruled out. The
   literal `create_by` string `"metric_lossless_writer"` and the resolution
   method `"deterministic_definition_term"` only appear in
   `metric_lossless_writer.go`; no other function in the codebase writes
   them. A repo-wide search also confirms no code outside
   `contracts_store.go` ever writes to `kb.ontology_class_contract_revisions`
   or updates `current_contract_revision_id`.

None of these explain the gap. The isolated reproduction (item 1) and the
live evidence (record 416) used the same function, against the same
database, with the same inputs, and got different results.

## Diagnostic side effect (reverted)

The isolated test in item 1 above briefly wrote real rows into the live
database: one `identity_only` revision for the real, in-use class
`measurement:kwc_14c72be88731` (one of record 416's own classes) and one for
a throwaway test term. Both were reverted in the same session — the revision
rows deleted, `measurement:kwc_14c72be88731`'s header pointer restored to
`NULL`, and the throwaway term's header row deleted. `kb.ontology_class_contract_revisions`
was confirmed back at 0 rows afterward. No trace of this test should remain,
but it is recorded here for completeness since it touched the exact table
this bug is about.

## Required remediation

1. Reproduce with runtime visibility: add temporary logging (or attach a
   debugger) around `EnsureHeader`'s call site in `resolveOrCreateMetricClass`
   (`metric_lossless_writer.go:277-285`) inside the live dev server, then
   reprocess a record's metrics through `associate_semantics` and observe
   directly whether `EnsureHeader` is reached, what it returns, and whether
   the surrounding transaction really commits those writes.
2. Once the divergence point is found, add a regression test that exercises
   the real, live-server code path end-to-end (a sqlmock-level unit test of
   `contracts_store.go` already passes and would not have caught this).
3. Re-run this investigation's evidence queries (see above) after the fix to
   confirm `kb.ontology_class_contract_revisions` gains rows on the next
   reprocessing run.
4. Revisit the class-contracts manual's §8 claim that the mechanism is
   "wired into the live write path" — as of this bug, that claim is not
   supported by observed behavior in this deployment, independent of the
   zero-revisions count the manual itself already flags as expected-for-now.

## Acceptance criteria

- Reprocessing record 416 (or any record) through `associate_semantics` with
  `LOSSLESS_SEMANTIC_WRITES_METRIC=true` produces at least one row in
  `kb.ontology_class_contract_revisions` per distinct class touched, and each
  such class's `kb.ontology_term_headers.current_contract_revision_id` is
  non-null immediately after.
- The specific reason `EnsureHeader`'s effects were not observed in the live
  run (while working correctly in isolation) is identified and explained,
  not just worked around.
- The class-contracts manual's operational claims are re-verified against a
  real post-fix observation before being treated as accurate again.

## Resolution (2026-09-05)

### What was wrong

Nothing in the source. `resolveOrCreateMetricClass`
(`metric_lossless_writer.go`) calls `ContractStore.EnsureHeader`
unconditionally, and `writeMetricLossless` runs the whole thing in one
transaction, so `EnsureHeader` failing would roll back the assertion and the
resolution-decision row too. The only way 09:25 produced 56 assertions + 56
`kb.ontology_class_resolution_decisions` rows with **zero** contract
revisions is that the running binary's `resolveOrCreateMetricClass` did not
contain the `EnsureHeader` call at all — i.e. it predated commit `be4d`
(2026-09-04 19:21), which added it (verified against `be4d`'s own diff:
`resolveOrCreateMetricClass`'s former body was renamed to
`resolveOrSynthesizeMetricClassTerm` and the `EnsureHeader` /
`DeclareCanInstantiate` lines were added around it). "Stale binary" was
listed as ruled-out in this report via a `strings` check on the on-disk
`.cache/server.exe`; that check was not decisive because the process actually
serving requests at 09:25 was not necessarily that build (an `air` rebuild
that fails or races leaves the prior process running).

### How it was confirmed

A throwaway harness (`server/cmd/repro416`, since deleted) built from current
source, importing `keywords` so its `init()` registers the class synthesizer
exactly as the server does transitively, flipped record 416's 56 latest
metric decision candidates back to `in_review` and ran the real
`assertions.AssociateSemantics{DB}.Run(ctx, 416)`. Temporary `log.Printf`
tracing (since reverted) in `resolveOrCreateMetricClass`, `EnsureHeader`,
`AppendContractRevision` and `writeMetricLossless` showed, for every one of
the 56 classes: `EnsureHeader` → `AppendContractRevision` inserts a revision,
header-pointer `UPDATE rows=1`, `tx.Commit OK`. Result:
`kb.ontology_class_contract_revisions` went `0 → 58` (56 metric classes +
`semantic:can_instantiate` + `semantic:can_validate_value`), and all 56 of
record 416's classes ended with a non-null `current_contract_revision_id`.

### Data repair

Record 416 was the **only** record ever processed through the lossless metric
writer (`create_by = 'metric_lossless_writer'`: 168 assertion rows, 56
distinct classes, all record 416). The `repro416` run above went through the
real write path and therefore already backfilled it: post-run,
`0` `metric_lossless_writer` assertions have a null class header pointer, all
56 current (`represented`) assertions carry a
`normalized_against_contract_revision_id`, conformance is
`semantic:not_evaluated` for all 56 (correct — every contract is
`identity_only`), and 56 `semantic:can_instantiate` capability rows are
`enabled`. No separate backfill command was needed.

### Regression coverage

Already present and passing on current source (run with a scratch Postgres
via `TEST_DATABASE_URL`):
`TestIntegrationWriteMetricLosslessCreatesContractHeaderForNewClass`,
`TestIntegrationWriteMetricLosslessReusedClassGetsOneContractRevision`,
`TestIntegrationWriteMetricLosslessBackfillsContractForPreExistingClass` in
`server/api/ontology/assertions/metric_lossless_writer_integration_test.go`.
These call the real `writeMetricLossless` and assert exactly one
`identity_only` revision plus a set header pointer. The sqlmock-level
`contracts_store_test.go` this report flagged is a separate, weaker layer;
the integration layer already covers the live path.

### Operational follow-up

Do a clean `mise build-doc-processor` (the Phase D stages run in
`server/cmd/doc-processor`, not the main `deepdoc` server) and confirm the
served process is the new build whenever a semantic-pipeline change lands.
The class-contracts manual's §8 "wired into the live write path" claim is
accurate against a current build.

### Adjacent fix: doc-processor "Force Run" now reaches Phase D

Found while trying to re-run the evidence queries via the GUI: the Manual
Launch "Force Run" flag never reached `normalize_assertions` /
`associate_semantics` / `project_semantics`. `handleEvent` parses
`evt.Force`/`evt.ForceClear`, and Phase A/B processors re-parse the payload
they are handed, but Phase C/D `PostProcessIndexer`s are called as
`PostProcessIndex(ctx, recordID)` with no payload, and `control.go` never
put the flags on that context (unlike the chunk-batch coordinator). So a
forced re-run of an already-processed record was always an idempotent no-op
— which is exactly why re-running record 416 through the GUI did nothing.

Fixed (ChenWeb, same session):

- `control.go` wraps the Phase C context with
  `withDocProcessorFlags(ctx, evt.Force, evt.ForceClear)`.
- `assertions.WithForceReprocess(ctx, force)` / `forceReprocess(ctx)`
  (new `reprocess_context.go`) thread the intent into the `assertions`
  package without signature churn; `phase_d.go` sets it for the normalize
  and associate stages (project already rebuilds unconditionally).
- `DecisionCandidateStore.Propose` under force does not reuse an
  identical-payload candidate that has already been decided
  (`accepted`/`rejected`/`deferred`) — it opens a fresh `candidate`
  revision so the downstream stages re-adjudicate. A still-open
  (`candidate`/`in_review`) prior is still reused (no churn).
- `AssociateSemantics.Run` under force re-normalizes before selecting
  candidates, so a standalone `associate_semantics` force run reprocesses a
  record whose candidates are all `accepted`.
- `classfoundation.contract_synthesis.observedValueGroups` now counts
  DISTINCT source documents from the per-document distribution rows instead
  of summing `attribute_observations.document_count` (a naive per-write
  counter). Without this, a Force Run — which re-observes the same document
  — would inflate the count past `minSynthesisDocuments` and spuriously
  promote every touched class's contract from `identity_only` to
  `partially_defined` off one document counted twice.
- Regression test:
  `TestIntegrationAssociateSemanticsForceReprocessesDecidedCandidate`.

With this in place, a GUI Force Run of any record re-fires
`writeMetricLossless` → `EnsureHeader` and creates the contract revisions;
"Run Unfinished Only" / "Run Failed Only" (which send `force:false`) keep the
skip-if-current behavior.
