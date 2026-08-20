# Lossless Semantic Processing (ADR `2026081801`) — Task 7.7 Scoping, Provision Gate Default, Clear Script: Session Handoff

Date: 2026-08-20

## 1. State in one paragraph

This session picked up right after `2026082002` ended (user asked for a handoff, deferring tasks
7.7/8.4 and naming "the frontend page for the dashboard" as future work) and was asked to "continue
the implementation" of task 7.7, explicitly excluding the dashboard frontend page. Investigation
showed task 7.7 covers migrating four large, currently-untouched families (entities 60,679 rows,
relations 24,525, inventory_items 8,578, products 0) — none has a registered normalizer, adapter, or
any row in the new pipeline's tables yet. Scoped this live with the user via `AskUserQuestion`
(matching this ADR's established pattern): **the user redirected away from starting any new family
this session**, choosing instead to verify the **metric** vertical slice is fully implemented before
doing anything else, and separately clarified that "provision" (task 7.6) was already migrated, not
missing from consideration. Confirmed Phase 3 (tasks 6.1–6.12, metric) is 100% complete in
`tasks.md` — no code gap remains for metric itself. The user then described a 7-step manual
verification plan (clear processor-generated data → run `extract_metrics`/`normalize_assertions`/
`associate_semantics`/`project_semantics` against doc 416 → verify → repeat for another document →
repeat for provisions → verify) and asked for a review. That review surfaced two real corrections
(a processor-name typo, and that `LOSSLESS_SEMANTIC_WRITES_PROVISION` needed to be on for the
provision half of the plan to test the real writer instead of just the fallback path) plus a
precise, schema-verified table-clear scope, both confirmed by the user via `AskUserQuestion`. The
user then said explicitly **"we will not go back"** and asked to make the writer gates
default-on-permanently. Investigation showed two of the four named env vars already defaulted on
(tasks 6.9/7.4); the deny-switch the user named would have inverted its own purpose if flipped
(pushed back on this rather than implementing it literally); the one real gap —
`LOSSLESS_SEMANTIC_WRITES_PROVISION` — was flipped via TDD, with two tests fixed that had implicitly
relied on the old default (same class of fix task 6.9 made for the metric gate), full regression
swept clean against the ADR's already-documented pre-existing failure baseline, committed. Finally,
the user asked for (1) this handoff and (2) a SQL script implementing the agreed clear-scope. The
script was **dry-run against real `miner` data inside a rolled-back transaction** before being
handed over, which caught a real, database-enforced append-only/immutable-trigger constraint on
three tables the original plan assumed were clearable — fixed before delivery, not discovered by the
user at runtime.

## 2. Document lineage (read in this order if picking this up cold)

1. **This handoff's predecessor** — `2026082002` (Phase 8 reports/docs closed, task 5.8 dashboard
   fix). Its §9 "where to resume" listed 7.7, 8.4, and "the frontend page for the dashboard" as the
   three open threads; this session addressed only the first, per the user's own redirect mid-session.
2. **`2026082001`, `2026081905`, `2026081904`, `2026081903`, `2026081902`, `2026081901`, `2026081806`**
   — unchanged by this session, still accurate for their own scope.
3. **ADR `2026081801`** — unchanged by this session. `Status: Proposed` is still correct (Phase 4's
   remaining families, task 7.7, are still untouched; only the already-certified provision writer's
   *activation default* changed, not its Phase 3/4 status).
4. **`ChenWeb/openspec/changes/lossless-semantic-processing/tasks.md`** — task 7.6's entry gained a
   dated 2026-08-20 addendum recording the gate-default decision. Tasks 7.7 and 8.4 are unchanged,
   still `[ ]`. Progress unchanged: **70/72**.
5. **`ChenWeb/openspec/changes/lossless-semantic-processing/clear-processor-artifacts.sql`** (new
   this session) — the SQL script requested this session, dry-run-verified against real `miner` data.
6. **`KnowledgeStore/doc-repo/adrs/202608/2026082003-adr-document-processor-dashboard-mapping-triage-navigation.md`**
   — **found this session, not authored by it.** Authored by the user "with Codex" (a different
   agent), sitting uncommitted in the KnowledgeStore working tree. This is very plausibly the
   concrete answer to `2026082002`'s open "which of three things does 'the frontend page for the
   dashboard' mean" question — see §5 item 5 and §8.
7. **`jj log`** in both ChenWeb and KnowledgeStore — see §4 for the exact revisions.

## 3. What was done this session

### Scoping task 7.7 (no commit — a scoping decision, then redirected)

1. Confirmed `jj log`/`jj status` in ChenWeb matched `2026082002`'s end state exactly (clean,
   `mkqz/a4e0` at the tip).
2. `openspec instructions apply` confirmed exactly two pending tasks: 7.7 and 8.4 (8.4 blocked on
   7.7 per ADR §1.2).
3. Investigated task 7.7's actual scope against live `miner` data rather than the task description
   alone: `assertions.RegisteredFamilies()` is still `["metric", "provision"]` — none of
   entities/inventory_items/products/relations has a normalizer, adapter, or any row in
   `kb.semantic_decision_candidates`/`kb.unresolved_semantic_occurrences`/`kb.semantic_assertions`.
   Live row counts: entities 60,679; relations 24,525; inventory_items 8,578; **products 0** (cannot
   be live-validated).
4. Used `AskUserQuestion` (family choice + scope depth) per this workspace's established pattern.
   **User's answers changed the plan on both axes**: (a) corrected that provision is not a candidate
   for "next family" since it's already done (task 7.6) — the confusion was that it wasn't shown in
   the comparison table because it's past that stage, not stuck; (b) explicitly declined to start any
   new family this session at all: **"Let's focus on metric, finish all its implementation... Do not
   expand to other processors until the metric vertical slice is fully implemented and verified."**
5. Verified Phase 3 (metric, tasks 6.1–6.12 in `tasks.md`) is **100% `[x]`** — no code-level gap
   remains for metric's own implementation. Reported two things worth knowing before live
   verification, both already honestly flagged in the existing record rather than newly discovered:
   DR12's "recognized special value" range-type case has no parser support yet (task 6.7's note), and
   only 1 of 56 successfully-processed documents (416) has actually gone through the live DR5 writer
   since the gate flipped on 2026-08-19 (`phase8-precutover-report.md` §0).
6. Reported status: only 7.7 (on hold per the user's own choice) and 8.4 (blocked on 7.7) remain open
   anywhere in `tasks.md`; nothing else is pending or blocked for metric.

### Reviewing the user's 7-step manual verification plan (no commit — a review, then two fixes below)

7. The user described: clear doc-processor-generated data → run
   `extract_metrics`/`normalize_semantics`/`associate_semantics`/`project_semantics` against doc 416
   → verify → repeat for another document → verify → repeat for provisions → verify; asked "is this
   plan okay?"
8. Traced every `INSERT INTO kb.`/`DELETE FROM kb.` call site across
   `ontology/assertions`, `ontology/semantic`, `ontology/classfoundation`,
   `extract-metrics.go`, `extract-provisions.go` to build an accurate, checked table-scope answer
   rather than guessing. Findings surfaced to the user before proceeding:
   - Processor name correction: `normalize_assertions`, not `normalize_semantics`
     (`processor_plan.go:453-455` names the three Phase-C stages exactly).
   - `kb.ontology_term_headers`/`kb.ontology_class_contract_revisions` (+2 capability-tracking
     dependents) mix curated vocabulary (4,213 QUDT terms, 131 `ontology-seed` classes) with
     processor-created provisional classes, distinguishable by `create_by`. Blanket-clearing would
     wipe curated ontology data — confirmed via live query that this is currently a no-op (0
     provisional rows exist today; doc 416's 60 metrics all resolved to existing classes) but the
     rule matters for repeatability.
   - `kb.metric_value_range_type_map` (curated admin mapping decisions) and
     `kb.semantic_adapter_compliance` (certification audit trail) should not be cleared at all.
   - `kb.artifact_objects` self-cleans per `(record, artifact_type)` on every extract run
     (`ReplaceObjectsForRecord`) — no manual clearing needed.
   - Only the 56 `pipeline_state='success'` documents have the upstream chunks/text these processors
     need directly; the other 146 never ran the pipeline at all.
   - `LOSSLESS_SEMANTIC_WRITES_PROVISION` was (at the time) still off by default — without flipping
     it, the provision half of the plan would only exercise the fallback path, not task 7.6's
     certified writer.
9. Confirmed both open items via `AskUserQuestion`: the table-clear scope above (user: "Yes, use that
   scope"), and whether to flip the provision gate first (user redirected this into the broader
   "we will not go back" gate-default request — see next section).

### Gate default flip (commit `zwwr/286f`)

10. The user's literal ask named four env vars to either remove or default-true:
    `LOSSLESS_SEMANTIC_FALLBACK_WRITES`, `LOSSLESS_SEMANTIC_WRITES_METRIC`,
    `LOSSLESS_SEMANTIC_FALLBACK_DENY_PROVISION`, `LOSSLESS_SEMANTIC_WRITES_PROVISION`. Read
    `gates.go` before touching anything and found: the first two already default ON (tasks 6.9/7.4);
    the third is a **subtractive emergency-isolation deny switch** (task 7.4), not an enable switch —
    it already defaults to *not denying*, so flipping its default to `true` would invert it into
    *always denying* provision fallback writes, the opposite of the stated intent. **Surfaced this
    correction to the user rather than implementing it literally**, treating it as a likely wording
    slip. Only `LOSSLESS_SEMANTIC_WRITES_PROVISION` genuinely still defaulted off.
11. Built TDD: extended `TestWriterGatesDefaultOn` to assert the new default (confirmed red), then
    flipped `gates.go`'s `enabled()` special case to include `GateProvisionLosslessWrites` (confirmed
    green). Updated three stale doc comments (`gates.go`, `associate_semantics.go`,
    `provision_adapter.go`) that asserted the old off-by-default behavior.
12. Ran the package suite and found one real regression:
    `TestIntegrationProcessProvisionGateOnWritesFallbackOccurrenceAndOutcome` implicitly relied on
    `LOSSLESS_SEMANTIC_WRITES_PROVISION` defaulting off to isolate the fallback path — with the new
    default it silently started taking `processProvisionLossless`'s branch instead. Fixed by pinning
    `t.Setenv(semantic.GateProvisionLosslessWrites, "false")`, the same fix pattern task 6.9 used for
    the analogous metric-gate tests. Found and fixed the sibling test
    (`TestIntegrationProcessProvisionGateOffWritesNoFallbackRecord`) too, even though it still passed
    numerically — it had started passing for the *wrong reason* (silently exercising the lossless
    writer's own defer path instead of the legacy fallback-off path it claims to test, coincidentally
    producing the same zero counts).
13. Full regression sweep (`ontology/...`, `doc-processing`, `kbhandler`, `dbmainthandler`) against a
    real scratch Postgres (`TEST_DATABASE_URL='host=127.0.0.1 user=cding dbname=postgres
    sslmode=disable'`) showed **the identical pre-existing failure set task 7.4 already documented**
    (`keywords`, `names`, `seed`, `kbhandler`) plus one newly-diagnosed, unrelated pre-existing issue:
    `TestIntegrationPhase1MigrationsRollBackCleanly` hardcodes rolling back "the eight Phase 1
    migrations," but `project_migrations/` now holds 266 files after Phases 2–4's growth, so 8
    `goose.Down` steps no longer undoes the Phase-1-added tables. Not caused by this change, not
    fixed (out of scope) — flagged in `tasks.md`'s addendum and here.
14. Recorded the decision as a dated addendum to task 7.6's (already-`[x]`) entry in `tasks.md`
    (mirroring how task 6.9 accumulated multi-session addenda) rather than opening a new task number,
    since 7.6 is where the activation decision was originally left open. Committed ChenWeb only —
    this session made no KnowledgeStore changes at this point.

### Clear-artifacts SQL script (uncommitted — see §6/§9)

15. Wrote `clear-processor-artifacts.sql` implementing exactly the scope agreed in step 9: Section A
    wholesale-clears pure processor-output tables in FK-dependency order; Section B scopes the
    ontology term/class cleanup to `create_by = 'metric_lossless_writer'` rows only.
16. **Dry-ran the script against real `miner` data inside a transaction ending in `ROLLBACK` instead
    of `COMMIT`** (verification only, zero lasting effect — confirmed by re-checking `kb.metrics`/
    `kb.provisions` row counts unchanged after). This is not a formality: the first dry-run **failed**
    with `class resolution history is append-only`, surfacing a real, previously-undocumented
    database-enforced invariant the original scope missed.
17. Queried `pg_trigger` across every `kb.*` table in one pass rather than discovering constraints one
    failure at a time, and confirmed exactly three tables are genuinely immutable by design (`BEFORE
    DELETE OR UPDATE` triggers that unconditionally raise): `kb.ontology_class_resolution_decisions`,
    `kb.ontology_class_resolution_alternatives`, `kb.semantic_claim_identities`. Two other tables that
    looked similarly risky by name (`semantic_processing_outcomes`, `semantic_processing_findings`)
    turned out to have `AFTER UPDATE`/`AFTER INSERT OR UPDATE` triggers only — not DELETE-blocking —
    confirmed by checking trigger event type directly rather than assuming from the function name.
18. Removed the three immutable tables' deletes from the script; verified the FK from
    `kb.ontology_class_resolution_decisions.source_assertion_id` to `kb.semantic_assertions` (which
    could otherwise block Section A's assertion delete) is currently a non-issue because all 60
    existing rows have that column `NULL` — documented as a live fact checked as of 2026-08-20, not
    an assumption, with an explicit note that a future writer version populating that column could
    reintroduce the block (safely — the transaction would just fail and roll back).
19. Re-ran the dry-run: clean end-to-end, real row counts returned (13,915 provisions/occurrences,
    14,185 decision candidates, 60 metrics, 121 assertions, etc., all matching independently-verified
    counts from the prior turn's investigation), rolled back, `miner` confirmed unchanged.

### Handoff and dashboard-ADR discovery (this document; commit pending — see §9)

20. While gathering `jj status` for this handoff, found KnowledgeStore's working tree carries a
    **second** dirty item beyond the already-known diary file: a new, uncommitted ADR
    (`2026082003-adr-document-processor-dashboard-mapping-triage-navigation.md`) authored by the user
    "with Codex." Read it in full (see §5 item 5) rather than ignoring it. Not touched, not committed
    — it is the user's/Codex's own in-progress work, per the same "investigate before touching
    unfamiliar files" discipline this workspace's sessions have followed throughout.

## 4. Exact revisions this session produced

ChenWeb (`jj log -r 'mkqz..@'` — everything after `2026082002`'s tip):
```
qzmt/3153  (working copy, uncommitted as of this handoff -- adds clear-processor-artifacts.sql)
zwwr/286f  feat(lossless-semantic-processing): default LOSSLESS_SEMANTIC_WRITES_PROVISION on
mkqz/a4e0  feat(doc-processor-dashboard): task 5.8 -- distinguish mapping-triage failures ...  [predecessor's, unchanged]
```

Files touched this session (`jj diff --summary -r 'mkqz..@'`):
```
A openspec/changes/lossless-semantic-processing/clear-processor-artifacts.sql
M openspec/changes/lossless-semantic-processing/tasks.md
M server/api/ontology/assertions/associate_semantics.go
M server/api/ontology/assertions/provision_fallback_writer_integration_test.go
M server/api/ontology/semantic/gates.go
M server/api/ontology/semantic/gates_test.go
M server/api/ontology/semantic/provision_adapter.go
```

KnowledgeStore: **no commits by this session.** `jj status` at handoff time:
```
Working copy changes:
A doc-repo/adrs/202608/2026082003-adr-document-processor-dashboard-mapping-triage-navigation.md  [not this session's -- see §3 item 20]
M doc-repo/diary/202608/20260819-diary.md  [pre-existing, flagged since 2026082001]
```
This handoff document itself will be committed with `jj commit <this-file-path>` immediately after
being written, the same scoped-commit pattern `2026082002` used to avoid touching either unrelated
dirty file.

## 5. Findings and judgment calls not written down anywhere else

1. **A user's literal wording can encode a real inversion bug if implemented without checking the
   code first.** Asked to "make [the deny switch] default to true," which — for a subtractive
   deny-switch rather than an additive enable-switch — would have permanently blocked provision
   fallback writes, the opposite of "we will not go back." Caught by reading `gates.go` before
   writing anything, not by assuming the request was self-consistent. **Lesson for a future session:**
   when a request names a specific mechanism by inferred behavior ("make X default to Y so Z
   happens"), verify the mechanism's actual polarity before implementing, especially for anything
   named "deny"/"block"/"exclude" rather than "enable"/"allow"/"include."
2. **A test that still passes numerically can be passing for the wrong reason after a default flips.**
   `TestIntegrationProcessProvisionGateOffWritesNoFallbackRecord` kept returning the same zero counts
   after the gate flip, but via a completely different code path than the one its name and comment
   describe. Caught by tracing *why* each assertion held, not just whether it held. Worth treating as
   a standing check whenever a default changes: re-read what each passing test's comment claims to
   prove, not just its pass/fail status.
3. **A destructive script's own dry-run is not optional busywork — this one caught a real, undocumented
   database invariant.** `kb.ontology_class_resolution_decisions` and `kb.ontology_class_resolution_alternatives`
   being permanently append-only (and `kb.semantic_claim_identities` likewise) was not written down
   anywhere in `design.md`'s D-decisions, the ADR, or any prior handoff found this session — it exists
   only as a `BEFORE DELETE OR UPDATE` trigger discovered by querying `pg_trigger` after a failed
   dry-run. **This is worth eventually recording in design.md or the ADR itself** (not done this
   session — out of scope for a session that was asked for a script, not a doc audit) since it's a
   real, load-bearing invariant future sessions touching this data should know about without having
   to rediscover it via a failed `DELETE`.
4. **The "clean re-run" the user's verification plan wants is architecturally impossible to make
   fully clean for claim identities and class-resolution history, and that's by design, not a gap.**
   Re-running doc 416 after the clear script will reuse its existing claim IDs and class-resolution
   decisions rather than minting fresh ones (`FindOrCreateShadow`/`RecordIfChanged` are both
   idempotent find-or-reuse operations). This is DR2/DR10's convergence guarantee working as intended
   — a claim registry that let you "start over" on identity would defeat its own purpose — but it
   means the user's step 3/5 "verify the results" should expect to see the *same* claim/class
   identity as any prior run of the same document, not fresh ones, and that is the correct outcome to
   verify for, not a sign the clear didn't work.
5. **The Codex-authored ADR found this session (`2026082003-adr-document-processor-dashboard-mapping-triage-navigation.md`)
   reads as a strong, specific answer to `2026082002`'s open "which of three things does 'the frontend
   page for the dashboard' mean" question** — its own Context section explicitly frames itself as
   "the dashboard follow-up explicitly deferred in handoff `2026082002`" and proposes exactly
   candidate (a) from that handoff's §8 (live navigation wiring from the mapping-triage badge to the
   Resolve Metric Range Types admin page), with a concrete DR1–DR5 decision record. **Not implemented,
   reviewed for correctness, or committed by this session** — it was found while checking repository
   state for this handoff, read in full to understand what it is, and left exactly as found. Whether
   the user wants this ADR taken forward (by this agent, by Codex, or reviewed jointly) is entirely
   their call — flagged here so a future session doesn't rediscover it from scratch or, worse, treat
   the "frontend page for the dashboard" question as still fully open when a concrete proposal already
   exists.

## 6. What was deliberately NOT built

- **No new family (entities/inventory_items/relations/products) was started.** Explicit user
  redirect mid-session: focus stays on metric until the user has personally run and verified it.
- **No fix for `TestIntegrationPhase1MigrationsRollBackCleanly`'s stale hardcoded migration count.**
  Diagnosed as pre-existing and unrelated to this session's diff; fixing it was out of scope for a
  gate-default task. Flagged in `tasks.md` and here for a future session.
- **No edit to `design.md`/the ADR recording the three newly-surfaced immutable-table invariants.**
  Documented in the SQL script's own header comments (where an operator will actually see them before
  running anything destructive) and in this handoff; a more formal ADR-level record was judged out of
  scope for this session's actual ask (a script and a handoff, not a design-doc audit) — worth
  revisiting if a future session is doing broader documentation work.
- **The clear-processor-artifacts.sql script has not been run for real** — only dry-run inside a
  rolled-back transaction. Actually clearing `miner` and running the 7-step verification plan is the
  user's own next action per their stated plan, not something this session executed.
- **The per-family emergency deny switch (`LOSSLESS_SEMANTIC_FALLBACK_DENY_<FAMILY>`) was not
  touched**, despite being named in the user's request — see §3 item 10 and §5 item 1 for why.
- **The Codex-authored dashboard-navigation ADR was not reviewed, implemented, or committed** — see
  §5 item 5. It remains exactly as found.
- **The pre-existing dirty KnowledgeStore diary file was left completely alone**, for the fourth
  consecutive session — see §4.

## 7. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb

# Confirm the commit graph matches this handoff's account
jj log -r 'mkqz..@' --no-pager

# Confirm the working tree has exactly the clear script pending (uncommitted
# until this handoff is also ready to commit alongside it, or commit
# separately -- see §9)
jj status

# Confirm openspec still sees 70/72, with exactly 7.7 and 8.4 pending, and
# task 7.6's entry now carries the 2026-08-20 gate-default addendum
openspec instructions apply --change "lossless-semantic-processing" --json \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['progress']); [print(t['id'], t['description'][:60]) for t in d['tasks'] if not t['done']]"
grep -n "2026-08-20 addendum" openspec/changes/lossless-semantic-processing/tasks.md

# Confirm the provision gate now defaults on
TEST_DATABASE_URL='host=127.0.0.1 user=cding dbname=postgres sslmode=disable' \
  go test ./server/api/ontology/semantic/... -run TestWriterGatesDefaultOn -v

# Confirm the provision fallback-path tests still isolate what they claim to
TEST_DATABASE_URL='host=127.0.0.1 user=cding dbname=postgres sslmode=disable' \
  go test ./server/api/ontology/assertions/... -run TestIntegrationProcessProvisionGate -v

# Confirm the clear script still dry-runs clean against real miner data
# (rolls back -- zero lasting effect)
cd openspec/changes/lossless-semantic-processing
sed 's/^COMMIT;/ROLLBACK;/' clear-processor-artifacts.sql | PGDATABASE=miner psql -X -v ON_ERROR_STOP=1

cd ~/Workspace/KnowledgeStore

# Confirm the commit graph matches this handoff's account
jj log -r 'qpty..@' --no-pager

# Confirm the two dirty items: the diary (pre-existing) and the Codex ADR
# (found, not authored, this session)
jj status
```

## 8. Traps for the next session

- **All traps from `2026082002` and its predecessors not specifically superseded here still apply**:
  `assertions.RegisteredFamilies()` has exactly two families; only one real provision instance exists
  in the corpus (`416_prv_1`); the `kb.metrics` 60-row situation is a well-evidenced theory, not a
  fact — and per §5 item 4 of this handoff, expect it to *stay* 60 rows plus whatever doc 416
  reprocessing naturally regenerates, not to become the historical 7,074-row baseline, since backfill
  remains deliberately out of scope; `jj split` hangs non-interactively; editing files under
  `server/cmd/` or `project_migrations/` triggers `air` to rebuild and auto-apply migrations.
- **`LOSSLESS_SEMANTIC_WRITES_PROVISION` now defaults ON, unlike every handoff before this one says.**
  If reading an older handoff first, do not trust its "provision gate defaults off" statements —
  this session changed that. `2026082002`'s own account (task 7.6) is still correct for *what it
  covered at the time*; the addendum in `tasks.md` is the current source of truth.
- **`kb.ontology_class_resolution_decisions`, `kb.ontology_class_resolution_alternatives`, and
  `kb.semantic_claim_identities` cannot be deleted or updated, ever, by database trigger.** Any future
  script or backfill touching this ADR's data must treat these three as permanent history. Verified
  by direct `pg_trigger` query this session (§3 item 17) — don't rediscover this by hitting the same
  error again.
- **`TestIntegrationPhase1MigrationsRollBackCleanly` in `server/api/ontology/semantic` is currently
  broken** (hardcodes 8 migration-rollback steps against a `project_migrations/` directory that now
  holds 266 files) and will show as `FAIL` in any full-package test run. This is pre-existing and
  unrelated to this session's diff — don't misattribute it to a future session's changes either;
  check `jj diff` against this handoff's revision to confirm it's still untouched before assuming
  otherwise.
- **The full regression sweep's known pre-existing failure baseline is now: `ontology/keywords`,
  `ontology/names`, `ontology/seed`, `kbhandler`, plus `TestIntegrationPhase1MigrationsRollBackCleanly`
  in `ontology/semantic`.** Task 7.4's original baseline (`keywords`, `names`, `seed`, `kbhandler`)
  gained this one addition this session — update this running list again if a future sweep finds yet
  another one, rather than assuming the list is now permanently complete.
- **`clear-processor-artifacts.sql` has never been run for real** — only dry-run-verified. The first
  real run should be watched carefully even though it was dry-run clean, since `miner`'s actual state
  could have changed between the dry-run and the real run if other work happens in between.
- **There is now a SECOND uncommitted item in KnowledgeStore beyond the long-standing diary file**:
  the Codex-authored dashboard-navigation ADR (§3 item 20, §5 item 5). Both are the user's own
  in-progress work, not this session's or any session's to commit or discard without being asked.
  Don't assume the diary file is the *only* pre-existing dirty state to check for now — always run
  `jj status` fresh rather than trusting a prior handoff's snapshot of it.

## 9. Where to resume

**The user's own next action is their 7-step manual verification plan**, now unblocked: run
`clear-processor-artifacts.sql` for real, then `extract_metrics`/`normalize_assertions`/
`associate_semantics`/`project_semantics` against doc 416, verify, repeat for another document,
verify, repeat for provisions (now exercising the real writer since the gate defaults on), verify.
Per §5 item 4, expect claim identities and class-resolution decisions to be *reused*, not
regenerated — that's correct, not a leftover-data problem. No further code work should be started
until the user reports how that verification goes, or asks for something else. When resuming:

1. **If the metric/provision verification passes**, per the user's own framing this closes the metric
   and provision vertical slices as "done." The next decision is which of entities/inventory_items/
   relations to start on for task 7.7 (products is explicitly out of scope per this session's
   discussion — the user confirmed "we are not going to support `products`" in the same message as
   describing the verification plan). Re-scope live with the user rather than assuming which family
   or how deep, the same way this session did before being redirected.
2. **If the verification surfaces a problem**, it is very likely either the DR12 "recognized special
   value" gap or something related to doc 416 being the only document that's gone through the live
   writer so far (§3 item 5 of `2026082002`, unchanged) — check those first before assuming a new bug.
3. **Task 8.4** (ADR status flip) is still correctly blocked on 7.7 closing.
4. **The Codex-authored dashboard-navigation ADR** (`2026082003-adr-...-navigation.md`) is sitting
   ready for a decision — ask the user whether/how they want it taken forward before assuming it's
   either abandoned or ready to implement.
5. No other item from `2026082002`'s or earlier resume lists remains open that this session didn't
   address, beyond what's listed above.
