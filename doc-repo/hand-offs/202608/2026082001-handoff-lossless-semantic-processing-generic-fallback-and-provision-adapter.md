# Lossless Semantic Processing (ADR `2026081801`) — Generic Fallback Wired, Real Provision Adapter Certified: Session Handoff

Date: 2026-08-20

## 1. State in one paragraph

This session picked up `2026081905`'s resume point (task 7.2, "wire every registered
extractor to generic fallback persistence") and closed five consecutive Phase 4 tasks —
7.2 through 7.6 — each scoped live with the user before implementation, since every one
of them turned out underspecified or blocked in a way `2026081905`'s own task 7.1 had
already established the pattern for. **Task 7.2**: "every registered extractor" turned
out to mean `assertions.RegisteredFamilies()` (the DR11 seam-5 normalizer registry,
`["metric", "provision"]`), not the unrelated doc-processing `ProcessorRegistry`; built a
generic `semantic.FallbackAdapter` and wired "provision" (the one family lacking a real
adapter) into the shared conformance suite, registry-only — no runtime call site added.
**Task 7.3**: ran the real completeness projection and found **100% of provisions
(13,915/13,915) were historically unreachable** — worse than metrics' pre-ADR 99.2%
unreachable. **Task 7.4**: the fallback gate had nothing to enable until a real call site
existed, so wired `processProvision` to actually write occurrence+outcome rows when
gated, then flipped `LOSSLESS_SEMANTIC_FALLBACK_WRITES` to default-on (tested first this
time, unlike the `b86a` incident two sessions ago). **Task 7.5**: ran the real pipeline
across all 61 provision-bearing records and closed the historical gap to **exactly
0/13,915 unreachable**. **Task 7.6**: certifying a real (`SupportsInstances()==true`)
non-metric adapter was blocked on a genuine, pre-existing content gap — no core ontology
term represented a deontic (required/prohibited/permitted) predicate at all — so, per the
user's explicit choice, added a new governed `prov:` ontology module, built a real
(if deliberately smaller than metric's) writer, certified it live against real `miner`
data, and fixed a genuine DR13 bug the live run surfaced (a pre-existing fallback
occurrence left stale-active instead of superseded). Six commits landed in ChenWeb, all
tested and verified before being described. `LOSSLESS_SEMANTIC_WRITES_PROVISION` — the
gate that would activate the new provision writer for real — was deliberately left off;
that activation, and building out the other four Phase 4 families, are explicitly
not started and were declined for this session (see §9). This document itself is the one
KnowledgeStore change this session made, and there is a **pre-existing, unrelated dirty
file** in this repo you should know about before touching anything here (§8 last item).

## 2. Document lineage (read in this order if picking this up cold)

1. **This handoff's predecessor** — `2026081905` (tests fixed, ADR §1.2 added, task 7.1
   scoped down and completed). Its §9 "where to resume" list named task 7.2 as the next
   item; this session executed 7.2 through 7.6 in order.
2. **`2026081904`, `2026081903`, `2026081902`, `2026081901`, `2026081806`** — unchanged by
   this session, still accurate for their own scope.
3. **ADR `2026081801`** — unchanged by this session. §1.2 (added by `2026081905`) is still
   the accurate Phase-3-cutover-scope statement; this session's work is Phase 4, which the
   ADR's own migration plan already anticipated ("Phase 4 — enable
   `LOSSLESS_SEMANTIC_FALLBACK_WRITES`, then migrate one family per slice").
4. **`ChenWeb/openspec/changes/lossless-semantic-processing/tasks.md`** — tasks 7.2, 7.3,
   7.4, 7.5, 7.6 are now `[x]` with dated, detailed notes (each is long; they were written
   as the durable record of a live-scoped decision, matching this workspace's established
   style). Tasks 7.7, 8.1–8.4 are unchanged, still `[ ]`.
5. **`generic-fallback-coverage.md`** (new this session, in the openspec change
   directory) — task 7.3's original report plus a 2026-08-19-later update recording task
   7.5's gap closure to zero.
6. **`jj log`** in ChenWeb — see §4 for the exact six revisions.

## 3. What was done this session

### Task 7.2 — generic fallback adapter (commit `slrm/6c07`)

1. Read the ChenWeb project `CLAUDE.md` and re-confirmed `jj status`/`jj log` matched
   `2026081905`'s account exactly (clean, `qmuv`/`84e4` empty on top of `mksm`/`7655`...
   wait — matched the *predecessor's* end state, `qlvr`/`6cc4`'s parent, before this
   session's own commits existed yet).
2. Investigated what "every registered extractor" means: checked
   `docprocessing.ProcessorRegistry` (15+ processors, DAG-orchestration concept, wrong
   layer) versus `assertions.AssertionNormalizerRegistry`/`RegisteredFamilies()` (DR11
   seam 5, exactly `["metric", "provision"]` today) — the latter is what DR13's adapters
   actually plug into. "metric" already has a real adapter; "provision" has none.
3. Surfaced the scope question to the user via `AskUserQuestion` (mirroring `2026081905`'s
   own pattern for task 7.1): registry+conformance only, vs. real call-site wiring in
   every extractor file. **User picked registry+conformance only.**
4. Built `semantic.FallbackAdapter` (`fallback_adapter.go`): a minimal, honest DR13
   stand-in declaration for a family with a normalizer but no compliant instance adapter —
   `SupportsInstances()==false`, raw identity limited to what
   `kb.unresolved_semantic_occurrences` itself requires, value/conformance states limited
   to governed "unknown"/"not_evaluated", required stages reuse the shared
   `StageNormalize`/`StageClassResolution`/`StageAssociate` vocabulary restricted to
   `raw_preserved`/`no_result` dispositions.
5. Built `assertions.EnsureGenericFallbackAdapters()` (registers a `FallbackAdapter` for
   every normalizer-registered family without an existing `semantic` adapter; idempotent,
   no automatic `init()`-time side effect) and `cmd/fallback-conformance` (runs
   `semantic.VerifyAndRecord` for each wired family, recording `writer_mode='fallback'` in
   `kb.semantic_adapter_compliance`).
6. TDD throughout (`fallback_adapter_test.go`, `fallback_wiring_test.go`), then ran the
   real binary against `miner`: `provision` got a `passed=true` fallback-mode compliance
   row; `metric`'s own row untouched. No extractor `.go` file was touched; no call to
   `OccurrenceStore.Upsert` was added anywhere yet.

### Task 7.3 — historical-skip coverage report (commit `qlvr/6cc4`)

7. Read the "Note on backfills" policy in `foundation-shadow-confirmation.md`: task 7.3's
   backfill half is deliberately deprioritized; its "explicitly report" half is not.
8. Extended `cmd/fallback-conformance` to run `semantic.CompletenessChecker` (the same
   projection `metric-writer-readiness` already uses) against every wired family with a
   known artifact-source query (added one for `provision`, mirroring
   `MetricArtifactSourceSQL`).
9. Result, cross-checked directly against `miner` independent of the command: **13,915 of
   13,915 provisions (100%) had neither a supporting assertion nor an active unresolved
   occurrence** — total, not partial, loss. Written up in the new
   `generic-fallback-coverage.md`.

### Task 7.4 — real fallback wiring, gate enabled (commit `mksm/7655`)

10. Before touching this task, flagged a real blocker to the user: the fallback gate
    (`LOSSLESS_SEMANTIC_FALLBACK_WRITES`) had **nothing to enable** — no production code
    called `OccurrenceStore.Upsert` anywhere, by the user's own explicit choice in task
    7.2. Offered three options via `AskUserQuestion`. **User chose to add real runtime
    wiring now.**
11. Traced why `processProvision` always defers: `associate_semantics.go`'s own comment —
    "No core module term yet represents a deontic (required/prohibited/permitted)
    predicate... a real, documented content gap." Every provision candidate defers for the
    identical reason, always.
12. Wired `processProvision` (new `writeProvisionFallbackOccurrence`,
    `provision_fallback_writer.go`) to persist one active `kb.unresolved_semantic_occurrences`
    row plus one `kb.semantic_processing_outcomes` envelope (stage=`semantic:stage_associate`,
    disposition=`semantic:raw_preserved`, one `semantic:mapping_unresolved` finding) when
    `Gates.FallbackAllowedFor("provision")`, before deferring exactly as before — gate-off
    behavior byte-identical.
13. TDD: two new integration tests against real Postgres (gate-off no-op; gate-on writes
    the pair, including an idempotent-replay check).
14. Flipped `gates.go`'s own unset-env default to ON for `LOSSLESS_SEMANTIC_FALLBACK_WRITES`
    — **with the full test suite run and green *beforehand* this time**, explicitly unlike
    the `b86a` incident `2026081904`/`2026081905` both flagged. Fixed 2 gate-default unit
    tests and 1 provision integration test whose premises the flip invalidated.
15. Live-validated against real `miner` data: processed input record 395's one, previously
    untouched provision. A real occurrence, outcome, and finding landed; the decision
    candidate's own defer behavior was unchanged. Coverage dropped from 13,915 → 13,914
    accordingly.

### Task 7.5 — closed the historical gap to zero (commit `qmuv/c920`)

16. Interpreted "confirm completeness reports show every new identifiable artifact has
    either a compliant instance or exactly one current unresolved occurrence" as calling
    for real evidence, not a one-record proof-of-mechanism. Ran the real, idempotent
    `normalize_assertions`/`associate_semantics` pipeline (**no LLM calls** — pure
    deterministic DB operations) across all 61 provision-bearing input records. Confirmed
    first this carried zero risk of side effects on metric processing (checked: no pending
    metric decision candidates existed for any of those 61 records).
17. First pass covered 13,839 of 13,915 immediately. The remaining 76 were all from input
    record 416 (the Phase 3 pilot document) and were already `deferred` from *before* this
    session's fallback code existed — `RetryDeferred` correctly refused to reopen them
    automatically, since their stored dependency fingerprint never encoded "a fallback
    writer is now available" (spec §16.3 item 12: fingerprint must genuinely change).
18. Retried those 76 with a fingerprint reflecting that real, new dependency
    (`<reason>:fallback_writer_available:<version>`) — legitimate use of `RetryDeferred`,
    not a bypass. Re-ran `associate_semantics` for record 416; all 76 got their fallback
    occurrence.
19. **Result: 13,915 of 13,915 provisions (100%) now have an active unresolved
    occurrence.** Independently cross-checked directly against the database. Not a
    backfill-policy violation: both code paths are real, reusable production code, safe to
    re-run after any future corpus reload. Written up as an update to
    `generic-fallback-coverage.md`.

### Task 7.6 — real provision instance adapter and writer (commit `llvx/1d9c`)

20. Before starting, recognized that certifying `ProvisionAdapter.SupportsInstances()==true`
    with no writer behind it would repeat exactly the hollow-certification problem task 7.4
    had just caught and fixed for the gate. Traced the root blocker: **no governed ontology
    term represents a deontic predicate at all** — a real, pre-existing content gap, not
    something to invent unilaterally inside infrastructure code. Surfaced this via
    `AskUserQuestion` with three options. **User chose to add the governed terms now** and
    build a real minimal writer.
21. Studied the existing curated-module machinery (`api/ontology/seed/{content,seed}.go`,
    `cmd/ontology-seed`) in full: modules are Go-defined content, authored/released/activated
    idempotently by `SeedCuratedModules`/`EnsureCuratedModules`, with a content-hash-derived
    release version so any content edit forces a new release automatically.
22. Added a new `provision` curated module (mirroring `measurement`'s shape — a
    family-specific module distinct from `core`'s cross-family predicates, but with no
    external dependency like `measurement`'s on `quantity`/QUDT): `prov:has_provision`
    (the predicate, analogous to `mea:measured_by`) and `prov:required`/`prov:prohibited`/
    `prov:permitted` (the deontic assertion kinds; `provisionAssertionKind` already
    collapses "recommended" onto "permitted", so no fourth term was needed). Registered it
    in `curatedModules` and in `EnsureCuratedModules`'s strict startup batch (it depends
    only on `core`, so — like `semantic-processing` — it has no deferred-dependency
    problem). Updated `cmd/ontology-seed`'s target lists and one `seed_test.go` assertion
    accordingly. Released and activated against `miner` via
    `PG_DB_NAME=miner ontology-seed --module provision` — clean, no warnings; all 4 terms
    confirmed `included_in_release`.
23. Built `semantic.ProvisionAdapter` (`provision_adapter.go`): `SupportsInstances()==true`
    (justified the same way `MetricAdapter`'s own declaration preceded its Phase 3 writer
    by many tasks — DR1's obligation is enforced by the gate + completeness projection at
    activation time, not by the declaration alone), exactly **one** required stage
    (`StageAssociate` only — provisions have no separate normalize/class-resolution phase,
    unlike metrics' three).
24. Built `writeProvisionLossless` (`provision_lossless_writer.go`) — deliberately smaller
    than `writeMetricLossless`: **no claim registry**. A provision clause is already its
    own atomic, uniquely-identified source claim (`prov_id`); metrics need cross-document
    convergence because two documents can describe the "same" physical measurement
    differently, but two provisions are never the "same" provision merely because they
    share a modality. `dc.LogicalIdentityKey` (already `prov_id`-scoped by
    `ProvisionNormalizer`) is the assertion's own logical identity directly — `persistAssertionTx`'s
    existing revision-vs-create logic handles idempotency for free. Reused
    `activeMetricSupportEvidence` directly (already artifact-type-parameterized despite its
    name) for evidence supersession rather than duplicating it.
25. Gated behind a new `LOSSLESS_SEMANTIC_WRITES_PROVISION`, **defaulting off** — mirroring
    `LOSSLESS_SEMANTIC_WRITES_METRIC`'s own Phase 1→Phase 3 staging (certified and ready is
    not the same as activated; that stays a deliberate later decision).
26. Wired into a new `processProvisionLossless` branch in `associate_semantics.go`, entered
    from `processProvision` exactly the way `processMetric` branches on its own gate.
    Unresolved subject defers as `unresolved_referent` — mirroring metrics exactly, and
    critically **never** touching the fallback occurrence store (DR1 forbids fallback for a
    `SupportsInstances` family). An unparseable modality (even with subject resolved and
    terms released) defers as `unparsed_modality` — a new, accurate reason distinct from
    the pre-7.6 `no_governed_deontic_predicate` gap — and still uses the generic fallback
    when its own gate authorizes it. Added a defensive `termExists` check before writing,
    mirroring `processMetric`'s own predicate/kind release check.
27. TDD: 3 new `ProvisionAdapter` unit tests
    (`api/ontology/semantic/provision_adapter_test.go`) plus 4 new integration tests against
    real Postgres in `provision_lossless_writer_integration_test.go` (materializes a
    represented assertion with the right predicate/kind/value-state; defers on unresolved
    subject with no fallback write; defers on unparsed modality with a fallback write; a
    second `Run` does not re-examine an already-`accepted` candidate — the real re-entry
    guarantee, since no metric test calls its own writer twice on one candidate ID either).
28. Fixed `fallback_wiring_test.go`'s task-7.2 test, whose premise `ProvisionAdapter`'s own
    `init()` self-registration invalidated (it now expects "provision" to already have a
    real adapter, not get a `FallbackAdapter`) — renamed and rewrote to assert the new,
    correct invariant.
29. Certified for real: built `cmd/provision-writer-readiness` (mirrors
    `cmd/metric-writer-readiness` exactly) and ran it against `miner`:
    `conformance passed=true`; completeness projection reported `complete=true` *already*
    (the 13,915 fallback occurrences from tasks 7.2–7.5 already satisfy the invariant on
    their own); `AuthorizeWriterActivation` reported the gate WOULD BE AUTHORIZED if flipped
    (informational only — nothing was flipped).
30. Live-validated end to end against real corpus data: retried record 416's `416_prv_1`
    (previously `deferred` since before this session) with a fingerprint reflecting the new
    "provision writer available" dependency (same legitimate `RetryDeferred` pattern as
    task 7.5), then ran the real writer with the gate set only in that one throwaway
    process's own environment. Produced a real `represented` assertion (id 404,
    `prov:has_provision` / `prov:required` / `semantic:value_present`), one supporting
    evidence link, and one outcome envelope — verified directly against the database.
31. **This live run surfaced a genuine DR13 bug**: the pre-existing fallback occurrence for
    `416_prv_1` (from task 7.4/7.5's earlier work) was left `active=true`,
    `resulting_assertion_id=NULL` even after the real assertion existed — violating "a
    crash cannot leave a materialized assertion paired with an active unresolved
    occurrence." `writeProvisionLossless` had no logic to supersede a pre-existing
    occurrence at all. Fixed properly: added `semantic.OccurrenceStore.SupersedeActiveForArtifactTx`
    (a direct-write, same-transaction counterpart to `Claim`/`Materialize`'s lease-based
    worker flow, for a family whose writer runs synchronously), wired it into
    `writeProvisionLossless` right after the outcome envelope is recorded, proved it with a
    5th new integration test, then used the same function directly (via a throwaway script)
    to correct the one stale row the live run had already produced before the fix existed.
32. Ran the full regression sweep after every step (`doc-processing`, `ontology/...`,
    `kbhandler`, `dbmainthandler`): identical pre-existing failure set throughout
    (`keywords`, `names`, `seed`, `kbhandler`) — no new failures at any point in this
    session.

### After task 7.6

33. Reported status to the user and asked whether to continue into task 7.7 (migrate the
    remaining four families) or Phase 8, given 7.7 is a materially larger undertaking than
    7.6 turned out to be (each of entities/inventory_items/products/relations likely needs
    its own governed-vocabulary/adapter/writer build, mirroring what 7.6 needed for
    provisions). **User chose to stop here for review and requested this handoff.**

## 4. Exact revisions this session produced

ChenWeb (`jj log -n 8` from the tip):
```
qsnu/6649  (empty, current working-copy commit)
llvx/1d9c  feat(ontology): certify a real provision instance adapter and writer
qmuv/c920  docs(lossless-semantic-processing): confirm 100% provision fallback coverage
mksm/7655  feat(ontology/semantic): enable LOSSLESS_SEMANTIC_FALLBACK_WRITES with real provision wiring
qlvr/6cc4  docs(lossless-semantic-processing): report provision's total historical-skip coverage
slrm/6c07  feat(ontology/semantic): add generic fallback adapter for non-compliant families
vros/1052  feat(ontology/semantic): add generic-discovery reader for unresolved occurrences  [predecessor's, unchanged]
urrr/d234  docs(lossless-semantic-processing): reconcile task notes with the b86a gate-default cutover  [predecessor's]
```

Every one of `slrm/6c07`, `qlvr/6cc4`, `mksm/7655`, `qmuv/c920`, `llvx/1d9c` was built,
tested (`go build ./...`, `go vet ./...`, targeted `go test`, and for the writer-touching
commits, integration tests against real Postgres), and **live-verified against real
`miner` data** before being described — following `2026081905`'s own explicit standard
("real, tested, verified commit, unlike `b86a`").

KnowledgeStore: this handoff document itself is the only change this session made here.
See §8's last item for a pre-existing, unrelated dirty file you should know about.

## 5. Findings and judgment calls not written down anywhere else

1. **"Registered extractor" (task 7.2) does not mean the doc-processing `ProcessorRegistry`.**
   That registry (15+ Phase A/B/C processors: `extract_metrics`, `generate_summaries`,
   `classify_document`, ...) is a DAG-orchestration concept from a *different* ADR
   (`2026072901`). The registry DR13's adapters actually plug into is
   `assertions.AssertionNormalizerRegistry` (seam 5), currently exactly two families. This
   was non-obvious enough that it needed live investigation, not something a future session
   should re-derive from scratch — see `[[project_...]]`-style memory note below.
2. **A `FamilyAdapter`'s conformance suite is purely declaration-level and never checks
   whether a writer actually exists.** This is *by design* (documented in `conformance.go`'s
   own comment: the suite must be runnable at startup against an empty database) but it
   means "certify an adapter" and "the writer behind it is real" are two different claims —
   task 7.4 and task 7.6 each independently discovered a version of this gap (an "enabled"
   gate with no call site; a `SupportsInstances()==true` declaration with no writer) and
   both times the user chose to close the real gap rather than accept a hollow pass. This
   is now a load-bearing pattern for this ADR, not a one-off: **the next time a gate or
   adapter looks trivially "done," check whether something real is actually behind it
   before marking the task complete.**
3. **Provisions did not need a claim registry, and that was a real design decision, not a
   shortcut.** Metrics need `classfoundation`'s claim/canonical-key machinery because two
   documents can describe the "same" physical measurement in different words, and DR2
   requires those to converge onto one canonical claim. A provision clause has no such
   convergence requirement — `prov_id` already is the atomic source-claim identity, and two
   provisions sharing a modality are never "the same provision." This is why
   `writeProvisionLossless` is a few hundred lines smaller than `writeMetricLossless` and
   why 7.6 was tractable in one session at all. **This will NOT be true for every remaining
   family in task 7.7** — entities in particular are plausibly re-observed across documents
   the same way metrics are (the same named entity mentioned in two different standards),
   so a future session should not assume every family gets to skip the claim registry the
   way provisions did; that needs its own live investigation per family.
4. **The stale-occurrence bug (item 31 above) is the kind of gap that only surfaces under a
   real live run, not under scratch-database integration tests.** The scratch-DB tests
   never had a pre-existing fallback occurrence sitting around from *days* of accumulated
   real corpus state the way `miner` did. This is a concrete argument for keeping the
   "live-validate against real `miner` data" step in this ADR's established workflow (not
   just unit/integration tests against a fresh scratch database) for every future family
   too — it is not redundant with the scratch-DB tests; it catches a different class of bug.
5. **Choosing "registry+conformance only" for 7.2, then discovering in 7.4 that this made
   the fallback gate meaningless, was not a wasted step.** It correctly kept 7.2 minimal and
   surgical per the user's own choice at the time; the *cost* of that choice (a follow-up
   blocker in 7.4) was cheap to discover and fix in the very next task, and the alternative
   (building real call-site wiring speculatively in 7.2 before anyone had decided whether
   the fallback mechanism itself was even wanted) would have been a worse bet. This is
   worth remembering the next time a "minimal, declaration-only" scope is chosen for a task
   whose *point* is eventually to do something real — the smaller scope is still usually
   right, but expect a fast follow-up task to need the real wiring.
6. **`LOSSLESS_SEMANTIC_WRITES_PROVISION` staying off is deliberate, not an oversight.**
   `provision-writer-readiness` reports `AuthorizeWriterActivation` WOULD authorize it right
   now. It was not flipped because (a) that decision was explicitly out of scope for "task
   7.6: certify," mirroring how `LOSSLESS_SEMANTIC_WRITES_METRIC` stayed off from task 3.8
   all the way through task 6.9 — many sessions apart — and (b) flipping a second family's
   writer gate in the same session that just built it, without independent review time in
   between, would repeat exactly the haste `b86a` was flagged for two sessions ago, just
   with a passing test suite this time instead of none. This is a judgment call a future
   session or the user may want to revisit once there has been time to look at the live
   `416_prv_1` result.

## 6. What was deliberately NOT built

- **No real call-site wiring for any family other than "provision."** Entities, inventory
  items, products, and relations have no normalizer at all yet (they are outside
  `assertions.RegisteredFamilies()` entirely) — task 7.7's territory, untouched.
- **No `uq_assertion_evidence_current_provision_support` index** (task 6.3's metric-only
  equivalent). `writeProvisionLossless`'s transaction atomicity is what prevents a
  duplicate today; a schema-level partial index is documented in the writer's own comment
  as a reasonable future hardening step, explicitly deferred as out of scope for "a minimal
  writer."
- **`LOSSLESS_SEMANTIC_WRITES_PROVISION` was not flipped on** — see §5 item 6.
- **No corpus-wide reprocessing of provisions through the new real writer.** Only two
  provisions (`prov-lossless-*` test fixtures aside) were ever processed through
  `writeProvisionLossless` against real `miner` data: `416_prv_1` (task 7.6's live
  validation). The other 13,914 provisions still carry only their task 7.2–7.5 fallback
  occurrence, not a real assertion. This is intentional — a corpus-wide run through an
  uncertified, just-built writer with its gate still off would be exactly the kind of
  premature action this session was careful to avoid throughout.
- **Tasks 7.7 and all of Phase 8 (8.1–8.4) remain untouched**, per the user's explicit
  choice to stop here.
- **The KnowledgeStore diary file's uncommitted change was left completely alone** — see §8.

## 7. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb

# Confirm the commit graph matches this handoff's account
jj log -n 8

# Confirm the working tree is clean
jj status

cd server

# Confirm the full package sweep matches this handoff's account (assertions/semantic
# green, keywords/names/seed/kbhandler still red with the same pre-existing failures)
go build ./... && go vet ./...
go test ./api/doc-processing/... ./api/ontology/... ./api/kbhandler/... ./api/dbmainthandler/... 2>&1 \
  | grep -E "^(--- FAIL|FAIL|ok)"

# Confirm the new provision-family tests specifically (fast, no DB)
go test ./api/ontology/semantic/... -run 'TestFallbackAdapter|TestProvisionAdapter' -v
go test ./api/ontology/assertions/... -run 'TestEnsureGenericFallbackAdapters' -v

# Confirm the new provision-family integration tests (real Postgres)
TEST_DATABASE_URL="host=127.0.0.1 user=admin password=plano4628 dbname=postgres sslmode=disable" \
  go test ./api/ontology/assertions/... -run 'TestIntegrationProcessProvision' -v

# Confirm the fallback-conformance and provision-writer-readiness tools against real data
PG_DB_NAME=miner go run ./cmd/fallback-conformance
PG_DB_NAME=miner go run ./cmd/provision-writer-readiness

# Confirm the live-validated provision assertion (416_prv_1) and its now-superseded
# fallback occurrence
psql "host=127.0.0.1 user=admin password=plano4628 dbname=miner sslmode=disable" -c "
SELECT id, logical_identity_key, status, predicate_term_id, assertion_kind_term_id
FROM kb.semantic_assertions WHERE logical_identity_key='provision:416:416_prv_1';
SELECT id, active, materialization_state, resulting_assertion_id
FROM kb.unresolved_semantic_occurrences WHERE artifact_type='provision' AND artifact_id='416_prv_1';
"

# Confirm openspec sees 66/72 tasks complete
cd ~/Workspace/ChenWeb && openspec instructions apply --change "lossless-semantic-processing" --json \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['progress'])"

cd ~/Workspace/KnowledgeStore
jj status   # expect: doc-repo/diary/202608/20260819-diary.md modified, unrelated to this session
```

## 8. Traps for the next session

- **All traps from `2026081905` and its predecessors not specifically superseded here still
  apply**: `LOSSLESS_SEMANTIC_WRITES_METRIC` defaults ON; `ontology/assertions` depends on
  `t.Setenv` gate-pinning for 3 legacy tests; `jj split` hangs non-interactively; editing
  files under `server/cmd/` or `project_migrations/` triggers `air` to rebuild and
  auto-apply migrations; the kb.metrics 60-row explanation is a well-evidenced theory, not
  a fact; ADR `2026081801`'s `Status` is still `Proposed` on purpose.
- **`assertions.RegisteredFamilies()` now has TWO families, both with real adapters.**
  `cmd/fallback-conformance` will report "no registered family needs the generic fallback
  adapter" and do nothing useful until a *third* family gets a normalizer without yet
  having a real adapter (task 7.7's first move for whichever family goes next). This is
  correct, not a regression — don't "fix" it by making the tool do something when there is
  genuinely nothing to certify.
- **`LOSSLESS_SEMANTIC_WRITES_PROVISION` defaults OFF, on purpose.** `provision-writer-readiness`
  reports activation WOULD be authorized right now — don't read that as "so it should be
  on." Flipping it is a deliberate decision explicitly deferred past this session; see §5
  item 6 for the full reasoning.
- **Only ONE real provision instance exists in the corpus so far** (`416_prv_1`, id 404).
  Every other provision (13,914 of them) still carries only a fallback occurrence, not a
  real assertion. Don't assume "provisions are migrated" from task 7.6 being checked —
  the corpus-wide cutover is explicitly not done; see §6.
- **`writeProvisionLossless` has no claim registry and was never meant to.** Don't add one
  reflexively when building the next family's writer (7.7) — check per-family first
  whether cross-document convergence is actually needed the way it is for metrics, per §5
  item 3. Entities are the most likely next family to actually need it.
- **`OccurrenceStore.SupersedeActiveForArtifactTx` is new and currently has exactly one
  caller** (`writeProvisionLossless`). Any future family's writer that might materialize an
  instance for an artifact with a pre-existing fallback occurrence must call it too — this
  is now the established, tested pattern (see §5 item 4 for why it matters: this exact bug
  was invisible in scratch-DB tests and only surfaced against real corpus state).
- **There is a pre-existing, uncommitted change in `KnowledgeStore` unrelated to this
  session**: `doc-repo/diary/202608/20260819-diary.md` has an added "2026/08/20 - Ontology
  Zero-Short Learning" entry (personal reading notes on the OntoZSL paper), sitting in an
  unnamed working-copy commit (`nkws`, alongside this handoff's own commit before it was
  split out). This was not touched, described, or committed by this session — per this
  workspace's git-workflow instructions ("if the working tree is dirty for reasons
  unrelated to the current session, tell the user before making changes"), it is flagged
  here rather than silently committed or discarded. **Do not assume it is finished or
  intended to be committed as-is** — ask the user, or check with them, before touching it.

## 9. Where to resume

**The user explicitly chose to stop here for review rather than continue into task 7.7 or
Phase 8.** No further code work should be started until the user gives direction. When
resuming:

1. **Task 7.7** ("factor proven metric behavior into the shared adapter framework, then
   migrate provisions, entities, inventory items, products, and relations one vertical
   slice at a time") is the next `[ ]` item in `tasks.md` §7. Given how much larger task
   7.6 turned out to be than 7.2–7.5, expect each of the four remaining families to need
   its own live-scoped investigation the same way provisions did — don't assume any of them
   will be quick. Per §5 item 3, check per-family whether a claim registry is actually
   needed before assuming provisions' simpler shape generalizes.
2. Separately, and not blocked on 7.7: **whether to flip `LOSSLESS_SEMANTIC_WRITES_PROVISION`**
   is now a live, informed decision the user can make at any time —
   `provision-writer-readiness` already proves it would be authorized. This is exactly the
   kind of decision task 6.9 modeled for metrics: a deliberate, separately-timed activation
   step, not something to bundle into whatever task touches this area next.
3. **Phase 8** (8.1 pre-cutover reports, 8.2 open questions, 8.3 docs, 8.4 ADR status) is
   independent of 7.7 and could be picked up first if that is a better use of a future
   session — nothing in Phase 8 depends on the remaining Phase 4 families being built.
4. No other item from `2026081905`'s or earlier resume lists remains open that this session
   didn't address.
