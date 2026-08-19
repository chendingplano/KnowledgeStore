# Lossless Semantic Processing (ADR `2026081801`) — Phase 3 Near-Complete: Session Handoff

Date: 2026-08-18

## 1. State in one paragraph

Phase 3 is **11 of 12 tasks complete**. Tasks 6.1–6.8 and 6.10–6.12 are done, tested, and working
against real Postgres. Task 6.9 (actually enabling `LOSSLESS_SEMANTIC_WRITES_METRIC`) is **correctly
left off**, not blocked by a defect: the readiness check shows code-level authorization now passes,
but the completeness projection honestly reports the corpus has never been processed by the new
writer (nothing has run it against real data yet). Per a decision this session recorded as ADR
Appendix B, closing that gap is **deferred to the next live document-processing run**, not done via
a dedicated backfill of the existing 7,074 metrics — consistent with this session's earlier "no
backfill against current `miner` data" policy. **Nothing from this session is committed in ChenWeb
yet** — see §7 and §9.

## 2. Document lineage (read in this order if picking this up cold)

1. **This handoff's predecessor** — `hand-offs/202608/2026081805-handoff-lossless-semantic-processing-phase2-complete.md`.
   Phase 2 completion state; this session started from its §9 resume point ("the next real decision
   is whether to start Phase 3").
2. **ADR `2026081801`** — `adrs/202608/2026081801-adr-lossless-semantic-processing-and-knowledge-preservation.md`.
   The decision. DR1–DR13, Phase 3 sequence in §5, and **new this session: Appendix B**, recording
   the decision described in §1 above. This file has a real, intentional modification in the working
   tree (the Appendix B addition) — not a stray edit from elsewhere this time, see §8.
3. **OpenSpec change** — `ChenWeb/openspec/changes/lossless-semantic-processing/`. `tasks.md` now
   shows 63/72 checked (up from 51/72). New artifacts this session:
   - `foundation-shadow-confirmation.md` — task 6.1's confirmation record. Read this for the
     corpus-scale finding that shapes everything else: only 89 of 7,074 metrics (1.3%) resolve to an
     existing class; the other 98.7% exercise the provisional-class path.
   - `phase3-writer-readiness.md` — tasks 6.9/6.10's readiness report and corpus reports. Read this
     before touching the writer gate; it has the exact steps for what enabling it actually requires,
     updated to match Appendix B.
4. **This session's mid-session AskUserQuestion answers** (not separately documented elsewhere,
   recorded here for completeness):
   - Provisional class scope: **one provisional class per distinct `metric_definition_term_id`
     string**, falling back to a hash of the normalized metric name when that field is empty (true
     for 6,985 of 7,074 metrics). Confirmed acceptable to generate many provisional classes.
   - Backfill policy: **do not invest in backfill work against current `miner` data** since it is
     expected to be deleted/reloaded; a general-purpose, reusable, idempotent tool is fine to build,
     a one-shot data massage is not.
   - Cutover verification: **defer to live pipeline runs, not a backfill** (this is Appendix B).

## 3. What was built this session

All in ChenWeb, **uncommitted** in one jj working-copy change (`91ff61e2e9a0`) on top of `89be94ac89f8`
(Phase 2's last commit) — see §7 and §9 for why and what to do about it.

| Area | Summary |
|---|---|
| Task 6.1 | `server/cmd/metric-foundation-shadow-report` — first-ever run of `MetricAdapter.RunShadow` against real data (previously test-only). Confirmed the shadow path is genuinely write-free (zero row drift across every foundation table) and surfaced the 89/7,074 class-resolution finding. |
| Tasks 6.2–6.3 | `server/cmd/metric-support-cleanup` — resolved all 17 duplicate current metric-supporting links via the sibling ADR's pre-built audited soft-delete. `uq_assertion_evidence_current_metric_support` (already checked in by the sibling change) then applied cleanly. Both already covered in the predecessor session's own handoff addendum, restated here for the task-count total. |
| Tasks 6.4–6.7 | `server/api/ontology/assertions/metric_lossless_writer.go` (new, ~430 lines) — the DR5 atomic metric semantic transaction and DR12 disposition table in one. One `*sql.Tx` covers: deterministic class resolve-or-create, class-resolution decision recording, canonical claim find-or-create (registers `kb.semantic_claim_identities` for the first time ever), assertion creation with `status='represented'`, evidence supersession scoped to the metric occurrence, and all 3 required stage outcome envelopes (normalize/class_resolution/associate) with their findings. Wired into `associate_semantics.go`'s metric resolver as a **fully separate early-return branch** gated on `semantic.NewGates().MetricLosslessWritesEnabled()`, specifically to avoid perturbing the legacy path's query order (see §4 item 3 for why that mattered). |
| Task 6.8 | Wired `RetryQueue` into `UpsertValueRangeTypeMapEntry` (the mapping-approval admin handler). Added a **new** `RetryQueue.ScheduleForKeyedDependencyChange` because the existing `ScheduleForDependencyChange` matches "anything not yet at target" — which would sweep every other raw value's still-unresolved findings into the retry queue on every single approval, not just the one that changed. Threaded a new `ValueRangeTypeRaw` field through `metricCandidatePayload` (from `metric_normalizer.go`) so the mapping finding's dependency fingerprint can be scoped per raw value via `Dependencies.Extra`. |
| Task 6.9 | `server/cmd/metric-writer-readiness` — runs the conformance suite (recording `kb.semantic_adapter_compliance` for the metric adapter for the first time ever — it was empty before this), the completeness projection, and `AuthorizeWriterActivation` as if the gate were on. Reports readiness without touching the gate. Currently: conformance passes, completeness does not (expected — see §1). |
| Task 6.10 | Corpus reports produced by the tools above; written up in `phase3-writer-readiness.md`. |
| Tasks 6.11–6.12 | `metric_lossless_writer_integration_test.go` (new) — 4 tests against a real scratch Postgres database (goose migrations applied fresh each run): idempotent replay + full materialization, rollback-on-late-failure (nothing survives: no assertion, evidence, outcomes, claim, or provisional class), convergence across differing raw wording onto one claim, and non-convergence of distinct unparsed raw fingerprints. |
| Two real bugs found and fixed | `AssertionStore.CreateAssertion`/`CreateRevision` (`assertions_store.go`) never wrote 9 of the Phase 1 state columns (`value_state_term_id`, `class_identity_state_term_id`, etc.) — present in the struct and migrated into the schema, silently dropped on every insert since Phase 1 shipped. `instance_of_term_id` — added to the DB by the sibling ADR's migration 14 — was never added to the Go `Assertion` struct or its read/write paths at all. Both fixed; all pre-existing tests still pass (they never exercised these columns). |
| New migration | `project_migrations/20260818000019_seed_metric_canonical_key_version.sql` — seeds `kb.semantic_canonical_key_versions` with `identity/v1` (`status='active'`). Without it, `ClaimIdentityStore.FindOrCreateShadow`'s insert fails its FK to that table — found by running the writer for real, not by inspection. **Already applied to `miner`** (via `air`'s own migration-on-startup, triggered incidentally by editing files under `server/cmd/`; confirmed via `SELECT * FROM kb.semantic_canonical_key_versions`). |

## 4. Findings not written down anywhere else

1. **The metric-definition-term identity story is more skewed than task 6.1's report alone
   suggested.** Of the 89 metrics with a non-empty `metric_definition_term_id`, all 89 are distinct
   auto-promoted `measurement:auto:kwc_*` values (one metric each) — there is no meaningful reuse
   even within that 1.3%. The remaining 6,985 fall back to a name-derived hash; among those, 5,258
   distinct normalized names exist (some genuine reuse, e.g. "得分" appears 78 times). Net: expect on
   the order of 5,300+ provisional classes once the writer runs for real, not a handful.
2. **`kb.ontology_term_headers` is populated from `kb.ontology_terms` via a sync trigger**
   (migration `20260818000009`), so it is the *same* namespace as the legacy governed-term table, not
   a parallel one — `mea:observed_value` (the fallback assertion-kind term used for unparsed/missing
   values) is a real, already-released `term_kind='property'` term there, confirmed by querying
   `miner` directly rather than assumed.
3. **Reordering the gate check in `processMetric` initially broke two existing gate-off tests** by
   changing query order/count relative to the original code (`TestRunFailsWhenCandidateBlockedOnProposedValueRangeType`,
   `TestRunSucceedsWhenCandidateDeferredForAmbiguousValueRangeType`). Fixed by making the new
   gate-on path a fully separate early-return branch that does its own `termExists` check, rather
   than sharing/reordering any check with the legacy path below it. Worth remembering as a pattern:
   when adding a gated branch to existing sqlmock-tested code, don't touch the existing code's
   statement order at all, even for checks that look shareable.
4. **`ScheduleForDependencyChange`'s existing design (Phase 1) is for a single global target
   fingerprint, not a keyed dependency.** It was fine for its original use (nothing called it in
   production before this session either — confirmed via grep), but using it directly for
   per-raw-value mapping approvals would have been a real "retry storm" bug at this corpus's scale
   (629 ambiguous + 803 unresolved mapping findings). `ScheduleForKeyedDependencyChange` is the fix;
   the original method is untouched and still used nowhere in production.
5. **`kb.semantic_adapter_compliance` and `kb.semantic_canonical_key_versions` were both completely
   empty in `miner`** before this session, despite Phase 1 (tasks 3.9, and the sibling ADR's own
   migrations) having shipped weeks earlier. Nothing had ever actually run the conformance suite or
   registered a claim identity against real infrastructure — both were exercised only by unit/shadow
   tests before now. This is the same "confirmed active in shadow mode" versus "actually dormant"
   distinction task 6.1's report already flagged for other pieces; it turned out to extend further
   than that report alone showed.

## 5. What was deliberately NOT built

- **Task 6.9's actual gate flip.** See §1 and ADR Appendix B. Readiness tooling exists and runs
  clean on the code side; the data side is intentionally left to accumulate naturally rather than
  via backfill.
- **DR12's "recognized special value" row of the disposition table.** `metric_normalizer.go` has no
  parser support for a distinct "special value" case today (only present/unparsed/missing paths
  exist), so there was nothing real to wire up. Flagged in `tasks.md` 6.7 rather than fabricated.
- **Phase 4** (tasks 7.1–7.7, generic fallback + non-metric families) and **Phase 4 pre-cutover
  reports** (tasks 8.1–8.4) — untouched, as they were before. Explicitly out of scope for "complete
  Phase 3."
- **Any commit.** See §7.

## 6. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb

# Build + vet the whole workspace
go build ./... && go vet ./...

# Everything touched this session (unit tests, no live DB needed)
go test ./server/api/ontology/assertions/... ./server/api/ontology/semantic/... \
        ./server/api/ontology/classfoundation/... ./server/api/kbhandler/...

# The DR5 atomic transaction's integration tests (needs a live Postgres;
# creates/drops its own scratch DB per run)
TEST_DATABASE_URL='host=127.0.0.1 user=admin dbname=postgres sslmode=disable' \
    go test ./server/api/ontology/assertions/ -run Integration -v

# Re-run the readiness check against miner
PG_DB_NAME=miner PG_USER_NAME=admin go run ./server/cmd/metric-writer-readiness/

# Re-confirm zero duplicate current metric supporting links
PG_DB_NAME=miner PG_USER_NAME=admin go run ./server/cmd/metric-support-cleanup/
```

**Known pre-existing failures, unrelated to this session** (all in packages this session did not
touch, or — for the last one — confirmed via an A/B test with the new migration file physically
removed and restored): the set already named in the phase0/1 and phase2 handoffs (`kbhandler` search
registry/summary/topic handlers, `ontology/keywords` `TestAlignmentsStoreEnsureAccepted` and
siblings plus `TestResolverModeFromUnsetIsOff`, `ontology/names` `TestResolveAndObserveAutoAlignsOnExactLabel`,
`ontology/seed` author-module tests, `cmd/qudt-import`), **plus one newly surfaced this session**:
`ontology/semantic`'s `TestIntegrationPhase1MigrationsRollBackCleanly` hardcodes "roll back exactly
the eight Phase 1 migrations" (`for i := 0; i < 8; i++`) — stale since the sibling ADR's migrations
9–18 were added; rolling back 8 from a fully-migrated state no longer targets migrations 1–8 at all.
Confirmed independent of this session's own migration 19 by temporarily removing it and re-running
the test (still fails identically). Not fixed — out of scope, but the loop bound should become
dynamic (e.g. roll back to a named version) rather than a literal count.

## 7. Traps for the next session

- **Nothing from this session (or the "read handoff and start Phase 3" work before it) is committed
  in ChenWeb.** `jj st` shows 19 files (10 new, 9 modified) as one uncommitted working-copy change on
  top of `89be94ac89f8`. Decide a commit breakdown before doing more work on top of it — the natural
  split mirrors §3's table (6.1 shadow-report tool; 6.2–6.3 restated/no new commit needed since
  already covered; 6.4 the two bug fixes as their own commit since they're general-purpose, not
  metric-writer-specific; 6.5–6.7 the writer itself + its tests; 6.8 the retry-scheduling fix + its
  new `ScheduleForKeyedDependencyChange` primitive; 6.9–6.10 the readiness/report tooling and docs) —
  but that's a suggestion, not a decision made this session. Remember: `jj commit`, never
  `git commit`, per workspace CLAUDE.md.
- **`kb.metric_value_range_type_map` approvals now enqueue retry jobs.** `UpsertValueRangeTypeMapEntry`
  calls `ScheduleForKeyedDependencyChange` twice per approval (once for `mapping_unresolved`, once for
  `mapping_ambiguous`). This is inert today (no outcomes exist yet for it to match against — the
  writer gate is off), but once 6.9 closes, every mapping approval will start enqueueing real retry
  work. Worth watching the first few approvals after cutover.
- **Editing files under `server/cmd/` or `project_migrations/` triggers `air` to rebuild and apply
  pending migrations automatically**, confirmed twice this session (once intentionally, once as a
  side effect of adding a scratch tool). `air` is up and healthy (`curl localhost:8080` → 200) as of
  this handoff. This is convenient but means a stray file under those paths is not fully inert.
- **The `CreateAssertion`/`CreateRevision` bug fix (§3) has a blast radius beyond this ADR.** Every
  existing caller of these two functions now persists 9 columns it silently didn't before. All
  existing tests still pass (they never asserted on these columns), and this is very likely a strict
  improvement, but it's worth being aware the fix isn't scoped to just the new writer.
- **`metric-support-cleanup`, `metric-foundation-shadow-report`, and `metric-writer-readiness` are
  reusable ops tools, not throwaway scripts** — all three are safe to re-run (report-only by default
  or fully idempotent) and worth keeping in the normal toolkit rather than deleting after this
  session.

## 8. KnowledgeStore working-tree state

At the time this handoff was written, `KnowledgeStore`'s git working tree (currently on a detached
HEAD) has exactly one modification, and it **is** this session's own work, not a stray edit from
elsewhere:

- `doc-repo/adrs/202608/2026081801-adr-lossless-semantic-processing-and-knowledge-preservation.md`
  — Appendix B added this session (see §2 item 2, §1). Intentional; not yet committed. Decide
  whether to commit it standalone or alongside this handoff file.

This handoff file itself is also new and uncommitted. No other unrelated dirty files were found this
time (the predecessor handoff's §8 diary-file note no longer applies — that file is clean now).

## 9. Where to resume

Phase 3 is done except 6.9, which has no fixed timeline by design (ADR Appendix B). Before doing
anything else:

1. **Decide on ChenWeb's commit strategy for this session's uncommitted work** (§7) — this is the
   most time-sensitive item, since further uncommitted work would compound an already-large diff.
2. Decide whether to commit the KnowledgeStore ADR Appendix B change (§8) and this handoff.
3. Continuing to watch for 6.9 to close naturally requires no action — just re-run
   `metric-writer-readiness` periodically, or after any known batch of document processing, and
   check `completeness projection: complete=true`.
4. If/when 6.9 closes, the next real body of work is Phase 4 (tasks 7.1–7.7: generic fallback,
   migrating a second family) and the pre-cutover reports (tasks 8.1–8.4) — neither started, per
   §5.
5. The still-open Appendix A concern from the predecessor session ("the current design of the
   ontology object-class apparatus... is not correct as specified... objection not yet articulated")
   remains exactly as open as it was; nothing this session bore on it either way.
