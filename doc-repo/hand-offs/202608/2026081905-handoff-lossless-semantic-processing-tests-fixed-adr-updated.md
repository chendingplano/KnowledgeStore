# Lossless Semantic Processing (ADR `2026081801`) — Regression Fixed, ADR Reconciled, kb.metrics Mystery Narrowed: Session Handoff

Date: 2026-08-19

## 1. State in one paragraph

This session picked up `2026081904`'s "where to resume" list in priority order and closed the
first two items outright, then investigated (rather than fully resolved) the remaining two. **Item
1 — the 3 broken `ontology/assertions` tests**: confirmed, via the ADR's own DR12 disposition table
(§3.12) and Phase 3 implementation step 5 ("stop returning processor errors solely for semantic
mapping/normalization findings"), that the gate-on default behavior is a genuine, ADR-documented
redesign — not a lost invariant — and that it is already proven end-to-end by the existing
`TestIntegrationWriteMetricLosslessMaterializesRawPreservedRepresentedAssertion` integration test.
Fixed the 3 unit tests by pinning them to explicit gate-off (`t.Setenv`), since they were written to
lock in the legacy/rollback path specifically and `processMetric` has no dependency-injection seam
for `Gates` (it calls `semantic.NewGates()` directly) — adding one purely to enable
`NewGatesFromMap` pinning would have been unwarranted scope creep. **Item 2 — the ADR's stale
claim**: added ADR `2026081801` §1.2 documenting the actual code-level gate default and explicitly
choosing to leave the ADR's `Status: Proposed` field alone (Phase 3 is done; Phase 4/8 and §10's
open questions are not, and the Status field covers the whole ADR). **Item 3 — the kb.metrics
60-row question**: investigated via live `miner` DB queries; found a plausible, well-evidenced
mechanism (repeated `extract_metrics --force` reprocessing churn during development, not an
accidental wipe) but no definitive who/when audit trail — documented as a finding, not chased
further into log archaeology. **Item 4 — task 5.8**: re-verified and found genuinely narrower now
(6.6 done, gate on by default) but still blocked on real, undone work (dashboard code + Phase 4
family coverage) — updated `consumer-lifecycle-policy.md` accordingly, left unchecked. **Item 5 —
Phase 4/8**: not started; this handoff ends by asking the user whether/where to begin, since it's a
multi-task feature build, not a bounded fix. Also deleted `server/tmp` (tracked junk flagged by
`2026081904`) since this session was already touching the area. Three commits landed in ChenWeb, one
in KnowledgeStore (see §4 for exact revisions); `kb.metrics` is untouched (no reprocessing was run).

## 2. Document lineage (read in this order if picking this up cold)

1. **This handoff's predecessor** — `2026081904` (the undocumented-cutover-commit discovery). Its
   §9 "where to resume" list is what this session executed in order.
2. **`2026081903`, `2026081902`, `2026081901`, `2026081806`** — unchanged by this session, still
   accurate for their own scope (see `2026081904` §2 for how they relate to each other).
3. **ADR `2026081801`** — this session added §1.2 (Phase 3 cutover status). Everything else
   unchanged. DR12 (§3.12) and Phase 3 implementation step 5 (§5) are the two passages that settle
   whether the gate-on default behavior is intentional (it is).
4. **`ChenWeb/openspec/changes/lossless-semantic-processing/tasks.md`** — task 6.9's note now has a
   2026-08-19-later addendum about `b86a`'s code-level default flip and the kb.metrics
   investigation. Task 5.8 is unchanged in `tasks.md` itself (still `[ ]`); its blocking analysis in
   `consumer-lifecycle-policy.md` was updated. 5.9/8.4 unchanged. Phase 4 (7.x) and Phase 8 (8.x)
   entirely unchanged — all still `[ ]`.
5. **`jj log`** in both `ChenWeb` and `KnowledgeStore` — see §4 for the exact revisions this session
   produced.

## 3. What was done this session

1. **Read `2026081904` and, per this workspace's established habit, ran `jj status`/`jj log` in
   `ChenWeb` before touching anything.** Matched the handoff's account exactly: working copy clean,
   `pxyw`/`7b84` empty on top of `xxkt`/`b86a`.
2. **Read the ChenWeb project `CLAUDE.md`** (coding guidelines: think-before-coding, simplicity
   first, surgical changes) before making any code change.
3. **Traced the actual mechanics of the 3 broken tests** by reading `gates.go`, `associate_semantics.go`
   (the gate-check branch at what is now line ~360, and its now-corrected comment at ~354-359),
   `associate_semantics_test.go` in full, `metric_lossless_writer.go`, and
   `metric_lossless_writer_integration_test.go`. Found:
   - `processMetric` reads the gate via `semantic.NewGates()` (env-based) directly — there is no
     `Gates` field on `AssociateSemantics` and no way to inject `NewGatesFromMap` into this call path
     without a production-code signature change.
   - `TestIntegrationWriteMetricLosslessMaterializesRawPreservedRepresentedAssertion` (needs
     `TEST_DATABASE_URL`, not run this session, but read in full) already builds a "proposed" lookup
     candidate, calls `writeMetricLossless` directly, and asserts `outcome == "represented"`,
     `mapping_resolution_state == unresolved` — i.e. the exact scenario the failing unit test
     `TestRunFailsWhenCandidateBlockedOnProposedValueRangeType` used to assert the *opposite* of
     (a hard failure). This is the concrete, already-existing proof that DR12's redesign is real and
     covered, not merely "plausible."
4. **Cross-checked against ADR `2026081801` directly**: DR12's disposition table (§3.12) lists
   "Proposed mapping" → `completed` with `mapping_unresolved` finding, `raw_preserved` disposition —
   matching the code and the integration test exactly. Phase 3 implementation step 5 (§5) says in so
   many words: "Stop returning processor errors solely for semantic mapping/normalization findings."
   This resolves `2026081904`'s open item (§4 finding 3): the redesign is confirmed intentional and
   ADR-documented, not merely "plausibly legitimate."
5. **Fixed the 3 tests** by adding `t.Setenv(semantic.GateMetricLosslessWrites, "false")` to each
   (`TestRunFailsWhenCandidateBlockedOnProposedValueRangeType`,
   `TestRunSucceedsWhenCandidateDeferredForAmbiguousValueRangeType`,
   `TestProcessMetricAcceptedPathPopulatesEvidenceProvenanceFields`), updated their doc comments to
   say explicitly that they now pin the rollback/legacy path rather than relying on an implicit
   default, and corrected the now-stale claim in `associate_semantics.go`'s own comment ("untouched
   when the gate is off (the default)" → "... explicitly turned off (ADR §6's rollback lever; the
   gate defaults ON as of Phase 3 cutover)").
6. **Verified the fix**: `go build ./...` clean; the 3 tests pass individually and as part of the
   full `ontology/assertions` package; re-ran the same package sweep `2026081904` ran
   (`doc-processing`, `ontology/...`, `kbhandler`, `dbmainthandler`) and got the identical
   pre-existing failure set (`keywords`, `names`, `seed`, `kbhandler`) with `ontology/assertions` now
   fully green.
7. **Committed the test fix** in ChenWeb via `jj describe` (revision `ccb4`, see §4) — this is a
   real, tested, verified commit, unlike `b86a`.
8. **Updated ADR `2026081801`**: added §1.2 documenting the code-level gate default, explicitly
   scoping it to Phase 3 (not full production cutover) and explicitly choosing **not** to flip
   `Status: Proposed`, since §10's open questions and Phase 4/8 are still outstanding and the Status
   field represents the whole ADR, not just Phase 3. This is a judgment call, not a mechanical one —
   see §5 for the reasoning spelled out, in case a future session or the user disagrees.
9. **Investigated the kb.metrics 60-row question** (`2026081903 §9.2`, `2026081904 §9` item 4) via
   direct queries against the live `miner` database:
   - `pg_stat_user_tables` for `kb.metrics`: `n_tup_ins=393`, `n_tup_del=7373`, `n_live_tup=60`
     (matches `2026081903`'s numbers exactly).
   - `kb.inputs` holds all 209 corpus documents, not fewer — so the source documents were never
     lost. 146 of them have `pipeline_state='pending'` with `create_time` clustered in a ~2-hour
     window on 2026-06-09 and `modify_time` never advancing past mid-June — a bulk import that never
     ran the processing pipeline at all, not a deletion.
   - Of the 56 documents that reached `pipeline_state='success'`, only doc 416 currently has any
     `kb.metrics` rows.
   - Grepped for every `DELETE`/`TRUNCATE` against `kb.metrics` in the codebase. Found
     `extract-metrics.go`'s `DeleteMetricsByInputRecordID` (line ~2817), called unconditionally when
     `evt.Force` is set (line ~620) as a delete-then-reinsert pattern for reprocessing. This is a
     normal, designed code path, not a bug — but if reprocessing was run broadly across the ~55
     `success`-state documents during iterative pipeline development and the reinsert step didn't
     always complete (superseded by later work, e.g. once doc 416 became the Phase 3 pilot), it
     would produce exactly the observed 7,373-deletes-vs-393-inserts imbalance without any accidental
     wipe. This is a plausible, evidenced mechanism, **not a confirmed one** — no exact who/when
     audit trail exists (`pg_stat_user_tables` counters reflect only activity since the last stats
     reset, whose timing is itself unknown).
   - Explicitly checked whether this matches the known `[[project_chenweb_test_database_url_danger]]`
     incident pattern (tests unconditionally wiping module-scoped rows when `TEST_DATABASE_URL`
     points at `miner`) — it does not: that incident was scoped to `kb.ontology_*` tables on
     2026-08-09, a different table family and date.
   - Documented all of this as an addendum to task 6.9's note in `tasks.md` (see §4 item 2) rather
     than leaving it as a bare "still open" flag, since a future session (or the user) may want to
     revisit the reasoning without re-running the same queries.
10. **Re-verified task 5.8's blocking analysis** (`2026081903 §9.3`, `2026081904 §9` item 4) by
    re-reading `consumer-lifecycle-policy.md`'s existing analysis against the now-current state (6.9
    closed, gate on by default). Found the blocker has narrowed but not closed: the metric family now
    has live outcome/finding signal (6.6 done, gate on), but 5.8's actual scope — the
    `doc-processor-dashboard-view.svelte` / `ListRecordsWithFailedDocProcessors` code switching from
    legacy `proc_status` to `ExecutionStatus`/`FindingSummary.DisplayStatus` — has not been written,
    and every non-metric family (provisions, entities, ...) still runs the pre-DR12 legacy path
    unconditionally (Phase 4 territory), so a full retrain today would only be correct for metrics.
    Updated `consumer-lifecycle-policy.md` with a dated re-verification note; left 5.8 unchecked in
    `tasks.md`, consistent with the existing "genuinely blocked, not merely undocumented" standard.
11. **Deleted `server/tmp`** (the tracked shell-scrollback junk `2026081904` flagged but didn't touch,
    since that session made zero code changes). Confirmed its content matched the description exactly
    before deleting. Verified `go build ./...` still clean afterward.
12. **Committed the docs/cleanup batch** in ChenWeb (revision `d234`) and the ADR update plus
    `2026081904`'s own (previously-uncommitted) handoff file in KnowledgeStore (revision `08bb`).
13. **Did not start Phase 4 (7.x) or Phase 8 (8.x)** — see §5 and §9.
14. **Wrote this handoff.**

## 4. Exact revisions this session produced

ChenWeb (`jj log -n 6` from the tip):
```
vros/5d62  (empty, current working-copy commit)
urrr/d234  docs(lossless-semantic-processing): reconcile task notes with the b86a gate-default cutover
pxyw/ccb4  fix(ontology/assertions): pin DR3 legacy-path tests to explicit gate-off
xxkt/b86a  doc process and ontology bug fixes                [predecessor's finding, unchanged]
uxvs/a762  docs(lossless-semantic-processing): close task 6.9 -- completeness projection now passes
zkzv/7334  feat(doc-proc-logs): add warning entry_type for benign semantic diagnostics
```

KnowledgeStore (`jj log -n 4` from the tip):
```
vvzs/5ad8  (empty, current working-copy commit)
nvrx/08bb  docs(adr-2026081801): document Phase 3 gate-default cutover; keep Status: Proposed
tzmn/6775  daily update - 2026/08/19                          [pre-existing, unchanged]
vpqk/9aca  docs: correct auto-promoted runtime terminology
```

Both `pxyw/ccb4` and `urrr/d234` were built, tested (`go build ./...`, targeted `go test`, and the
same package sweep `2026081904` ran), and verified **before** being described — unlike `b86a`.

## 5. Findings and judgment calls not written down anywhere else

1. **The DR12-supersedes-DR3 question `2026081904` left unverified is now resolved: yes, confirmed.**
   Both the ADR's own DR12 disposition table and Phase 3 implementation step 5's explicit "stop
   returning processor errors solely for semantic mapping/normalization findings" state this in
   normative terms, and `TestIntegrationWriteMetricLosslessMaterializesRawPreservedRepresentedAssertion`
   already proves it end-to-end for the exact "proposed" scenario the broken unit test covered. There
   is no lost invariant here.
2. **Choosing gate-off pinning over a `Gates`-injection seam was a scope judgment, not a forced
   move.** `2026081904`'s §9 item 1 offered both options as live. `NewGatesFromMap` exists and is
   used elsewhere (`FallbackAllowedFor` callers, `gates_test.go`), so it's tempting to think it was
   "meant" to be threaded through `processMetric` too — but it isn't wired there today, and adding
   that wiring (a new `AssociateSemantics.Gates` field, threading it through `Run`/`processOne`/the
   `AssociationResolver` function type) would touch every call site of a widely-used type for the
   sole purpose of these 3 tests. `t.Setenv` achieves the same isolation (Go resets it automatically
   per test, no cross-test leakage) with zero production-code blast radius. If a *second* reason to
   inject `Gates` ever appears, this decision should be revisited.
3. **Deliberately did not flip ADR `2026081801`'s `Status: Proposed` field**, even though task 8.4's
   literal trigger ("once Phase 3 cutover completes") is arguably now satisfied (all of `tasks.md`
   §6 is checked, the gate defaults on). Reasoning: the ADR's own §10 ties "before production
   cutover" to open questions that are Phase 4-scoped (e.g. "the first non-metric family to
   migrate"), and Appendix A's follow-up section explicitly defers resolving those until a second
   family validates the design — none of which has happened. Flipping `Status` now would read as
   "this whole ADR is settled," which overclaims relative to Phase 4/8 being entirely unstarted.
   Left `Status: Proposed` and task 8.4 unchecked; added §1.2 instead so the *current* Phase-3-only
   truth is documented without conflating it with the ADR's overall status. This is a judgment call
   the user or a future session may want to override.
4. **The kb.metrics investigation is evidenced but not proven.** The `--force` reprocessing-churn
   theory fits every fact found (bulk-import docs never ran the pipeline at all; only "success"-state
   docs are missing metrics; the delete/insert imbalance; doc 416 being the one document actively
   worked on today) and requires no incident, but `pg_stat_user_tables` counters only cover activity
   since an unknown stats-reset point, so it cannot be confirmed against an audit log. Did not pursue
   WAL/log archaeology to close this further — disproportionate for a staging environment where
   Appendix B already made backfill unnecessary regardless of the answer.
5. **This session's own housekeeping.** No stray divergent commits produced this time (no `jj new`
   detours were needed — investigation was read-only `psql`/`grep`, not working-copy manipulation).
   `jj status` in both repos shows a single clean empty head at the end.

## 6. What was deliberately NOT built

- **Did not add a `Gates` dependency-injection seam to `AssociateSemantics`/`processMetric`** — see
  §5 item 2.
- **Did not flip ADR `2026081801`'s `Status` field or check task 8.4** — see §5 item 3.
- **Did not pursue the kb.metrics 60-row question past live-DB queries and a codebase grep** — no WAL
  inspection, no server log archaeology, no attempt to identify a specific script/session that ran
  it. See §5 item 4.
- **Did not write or modify any dashboard/alert code for task 5.8** — that is the actual remaining
  work item 5.8 names, not something a "re-verify the analysis" task should silently start.
- **Did not start Phase 4 (7.1–7.7) or Phase 8 (8.1–8.4).** Both are large, multi-task feature builds
  (generic-fallback readers, wiring every extractor, a real backfill/report decision, migrating
  provisions/entities/inventory items/products/relations one at a time, resolving 4 ADR open
  questions). `2026081904`'s recommendation listed this last, after two investigative items this
  session did complete; starting implementation on either phase without checking scope/sequencing
  with the user first would be a bigger unilateral commitment than this session's other items. See §9.
- **Did not reprocess any more of the corpus.** `kb.metrics` is exactly as `2026081904` left it: 60
  rows, all doc 416. No LLM budget was spent this session (this session did no document processing at
  all — investigation was DB reads and a codebase grep).

## 7. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb

# Confirm the commit graph matches this handoff's account
jj log -n 6

# Confirm the working tree is clean
jj status

# Confirm the 3 previously-broken tests now pass
cd server && go test ./api/ontology/assertions/... -v -run \
  'TestRunFailsWhenCandidateBlockedOnProposedValueRangeType|TestRunSucceedsWhenCandidateDeferredForAmbiguousValueRangeType|TestProcessMetricAcceptedPathPopulatesEvidenceProvenanceFields'

# Confirm the full package sweep matches this handoff's account (assertions green,
# keywords/names/seed/kbhandler still red with the same pre-existing failures)
go test ./api/doc-processing/... ./api/ontology/... ./api/kbhandler/... ./api/dbmainthandler/... 2>&1 \
  | grep -E "^(--- FAIL|FAIL|ok)"

# Confirm server/tmp is gone
ls ../server/tmp 2>&1   # expect "No such file or directory"

cd ~/Workspace/KnowledgeStore
jj log -n 4
jj status
grep -n "1.2 Phase 3 cutover status" doc-repo/adrs/202608/2026081801-adr-lossless-semantic-processing-and-knowledge-preservation.md
```

## 8. Traps for the next session

- **All traps from `2026081904` and its predecessors not specifically superseded here still apply**:
  `LOSSLESS_SEMANTIC_WRITES_METRIC` defaults ON in code now (this session did not change that, only
  documented it more precisely); DR7 LLM auto-resolution is on but not exhaustive; `jj split` hangs
  non-interactively; editing files under `server/cmd/` or `project_migrations/` triggers `air` to
  rebuild and auto-apply migrations.
- **`ontology/assertions` is green again but by design now depends on `t.Setenv` gate-pinning.** If a
  future change adds a real `Gates` injection seam to `AssociateSemantics`, these 3 tests' `t.Setenv`
  calls should be revisited — they're a workaround for the seam not existing, not a permanent
  pattern to imitate elsewhere.
- **The kb.metrics 60-row explanation in `tasks.md`/§9 item 9 above is a well-evidenced theory, not a
  fact.** Don't cite it as "confirmed cause" without re-reading the hedging in §5 item 4.
- **ADR `2026081801`'s `Status` is still `Proposed` and task 8.4 is still unchecked — on purpose.**
  Don't treat the ADR as "done" because Phase 3 is; re-read §1.2 for the exact scope line.
- **Task 5.8 is still blocked, but on different grounds than before.** Don't re-derive from
  `consumer-lifecycle-policy.md`'s original text alone — read the 2026-08-19 re-verification note
  appended to it, which narrows the blocker to real remaining work (dashboard code + Phase 4 family
  coverage), not "no signal yet."

## 9. Where to resume

1. **Ask the user where to start on Phase 4/Phase 8** before writing any code for either — this is
   the one item from `2026081904`'s priority list this session did not attempt, and it's large enough
   (7 Phase-4 tasks spanning generic-fallback readers, per-extractor wiring, a backfill/report
   decision, and migrating 5 more artifact families one at a time; 4 Phase-8 tasks including
   resolving 4 ADR open questions) that it likely needs its own scoping conversation, not a
   continuation of this session's investigate-and-document mode.
2. If/when Phase 4 starts, task 7.1 (deploy and certify generic-discovery readers for unresolved
   occurrences) is the first `[ ]` item in dependency order per `tasks.md` §7.
3. Task 5.8 itself (the actual dashboard/alert code change) is now unblocked to *start* for the
   metric family specifically, per this session's re-verification — but doing it now would only be
   partially correct until Phase 4 migrates at least one more family, per §3 item 10 above.
4. No other item from `2026081903`'s or `2026081904`'s original resume lists remains open that this
   session didn't address.
