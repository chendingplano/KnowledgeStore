# Lossless Semantic Processing (ADR `2026081801`) — Phase 8 Reports/Docs Closed, Task 5.8 Dashboard Fix: Session Handoff

Date: 2026-08-20

## 1. State in one paragraph

This session picked up right after `2026082001` ended (user explicitly stopped there for review)
and, given a choice between three independent next steps (task 7.7, flipping
`LOSSLESS_SEMANTIC_WRITES_PROVISION`, or Phase 8), the user chose **Phase 8**. Four tasks closed,
each scoped live with the user first, continuing the pattern every recent session in this ADR has
used: **Task 8.2** resolved all five of ADR §10's/design.md's open questions — three (physical
schema split, `raw_fragment` retention, Review Document filters) closed by pointing at schema/UI
already shipped in earlier sessions; item 4 ("first non-metric family") closed as "provision" only
after confirming with the user that Appendix A.4's blocking condition doesn't actually describe what
task 7.6 built (provisions never touch the ADR-2026081701 four-table class/instance apparatus); the
retry-worker-pool question was **left explicitly open** per the user's choice, after investigation
turned up something concrete: `kb.semantic_retry_queue` gets real production enqueues (task 6.8's
mapping-approval action) but has **zero production callers of `RetryQueue.Claim`** anywhere — nothing
has ever drained it. Recorded as ADR `2026081801` Appendix C. **Task 8.1** produced the full
pre-cutover report the user asked for as an honest current-state baseline (not deferred to a cleaner
corpus): every completeness/constraint check passes, but it surfaces two real, unresolved things
plainly — `kb.metrics` is 60 rows/1 record against the ADR's own 7,074-row/58-record Phase 0
baseline (previously investigated, not new), and the retry queue is empty and unexercised.
**Task 8.3** found `ChenWeb/docs` had nothing stale, but the KnowledgeStore user manual
(`metric-assertion-semantic-processing-v1.2-en.md`) predated almost this whole ADR — full rewrite
as v1.3 per the user's choice. **Task 5.8** (carried over from Phase 2, not mentioned in `2026082001`
at all) turned out to have almost nothing left to do — `associate_semantics`'s own false-failure case
was already fixed at the source by task 6.6 two sessions ago — except one concrete, live gap: the
doc-processor dashboard's "Failed Pipelines" panel showed `extract_metrics`'s still-intentional
DR12 failure (an unreviewed `value_range_type` string) identically to a genuine crash, with a
"Restart" button that cannot fix it. Built and TDD'd a narrow, frontend-only fix, scoped live with
the user first. **The user then asked for this handoff, explicitly deferring task 7.7 and 8.4 (still
blocked on 7.7) to a future session, and specifically naming "the frontend page for the dashboard"
as something to pick up in another session too** — see §9.

## 2. Document lineage (read in this order if picking this up cold)

1. **This handoff's predecessor** — `2026082001` (tasks 7.2–7.6 closed: generic fallback adapter,
   historical-skip coverage, real fallback wiring with the gate flipped on, gap closed to zero, and a
   real, live-validated provision instance adapter/writer). Its §9 "where to resume" listed three
   independent options; this session's first action was asking the user which to pursue (see §5
   item 1).
2. **`2026081905`, `2026081904`, `2026081903`, `2026081902`, `2026081901`, `2026081806`** —
   unchanged by this session, still accurate for their own scope.
3. **ADR `2026081801`** — Appendix C added this session (§10 items 1–5 resolved/recorded). §1.2
   (Phase 3 cutover status) is unchanged and still accurate. `Status: Proposed` is unchanged —
   correctly so, since Phase 4's remaining families (task 7.7) are still untouched.
4. **`ChenWeb/openspec/changes/lossless-semantic-processing/tasks.md`** — tasks 5.8, 8.1, 8.2, 8.3
   are now `[x]` with dated, detailed notes. Tasks 7.7 and 8.4 are unchanged, still `[ ]`. Progress:
   **70/72**.
5. **`generic-fallback-coverage.md`, `phase3-writer-readiness.md`** — unchanged by this session, still
   the correct historical baselines they were before.
6. **`phase8-precutover-report.md`** (new this session, in the openspec change directory) — task
   8.1's full report against live `miner` data.
7. **`KnowledgeStore/doc-repo/user-manuals/metric-assertion-semantic-processing-v1.3-en.md`** (new
   this session) — supersedes v1.2 as the current user-facing manual. v1.0–v1.2 left untouched,
   matching this workspace's version-per-file convention.
8. **`jj log`** in both ChenWeb and KnowledgeStore — see §4 for the exact revisions.

## 3. What was done this session

### Choosing Phase 8 (no commit — a scoping decision)

1. Confirmed `jj log`/`jj status` in ChenWeb matched `2026082001`'s end state exactly (clean,
   `llvx`/`1d9c` at the tip).
2. `openspec status`/`instructions apply` showed 66/72 complete, 6 pending: 5.8, 7.7, 8.1–8.4.
3. Per this workspace's established pattern (`[[project_chenweb_openspec_workflow]]`), used
   `AskUserQuestion` rather than guessing which of the six to pick up. **User chose Phase 8
   (8.1–8.4).**

### Task 8.2 — resolve ADR §10 / design.md open questions (commits `qsnu/4051` ChenWeb,
`kyzy/f42b` KnowledgeStore)

4. Investigated each of the five questions against the actual shipped schema/code rather than
   designing new architecture for already-solved problems:
   - **Item 1** (physical split): `unsupported_prior_status` is a column on
     `kb.semantic_assertions` (migration `20260818000006`); `kb.semantic_processing_outcomes`/
     `kb.semantic_processing_findings` are DR4's entire validation-result layer. Already shipped —
     closed by citation, no new decision.
   - **Item 2** (`raw_fragment` retention): grepped every production call site; found **zero**
     populate `Outcome.RawFragment` for either metric or provision, because DR2 routes raw
     preservation to each family's own raw table instead. Moot in practice; no policy adopted.
   - **Item 3** (Review Document filters): task 5.5's Semantic Diagnostics tab already shows every
     lifecycle state unfiltered, severity as color badges. Known gap flagged, not a blocker:
     assertion-scoped, not outcome/finding-scoped.
   - **Item 4** (first non-metric family): surfaced to the user that provision's writer never
     touches `kb.semantic_claim_identities`/`kb.ontology_class_contract_revisions`/
     `kb.ontology_term_redirects` — the four-table apparatus Appendix A.4 said must not be
     committed to a second family before A.3's concern resolves. **User confirmed**: closes as
     "provision"; the apparatus itself stays metrics-only until the metric vertical slice's full
     cutover completes, by deliberate choice, not because task 7.6 accidentally satisfied A.4's
     gate.
   - **Item 5** (retry-worker-pool): found `kb.semantic_retry_queue` gets real enqueues (task 6.8)
     but `RetryQueue.Claim` has zero production callers. Surfaced this concretely to the user, who
     clarified their actual operating model (admins reprocess documents manually, not
     auto-retry) and **chose to leave it flagged as a known gap**, not resolved.
5. Wrote up all five as ADR `2026081801` Appendix C, dated, matching the existing Appendix A/B
   style. Updated design.md's "Open Questions" section with `Resolved`/`Left open` annotations
   pointing at the appendix. Marked task 8.2 `[x]` with a dated note.
6. Committed ChenWeb and KnowledgeStore **separately**, using `jj commit <path>` in KnowledgeStore
   to include only the ADR file — the pre-existing, unrelated dirty diary file (flagged since
   `2026082001`) was left untouched, confirmed via `jj status` before and after.

### Task 8.1 — pre-cutover report against live `miner` data (commit `xytx/62e0`)

7. Confirmed scope with the user first (`AskUserQuestion`): full report now, as an honest
   current-state baseline, not deferred. **User chose that (Recommended option).**
8. Ran `cmd/semantic-baseline`, `cmd/metric-writer-readiness`, `cmd/provision-writer-readiness`,
   `cmd/fallback-conformance` against `PG_DB_NAME=miner`, plus direct `psql` queries for
   row/storage projections, mapping-proposal breakdowns, lifecycle counts, constraint-violation
   checks (all zero), `no_verdict` findings (zero — capability exists, never exercised against real
   data), and decision-candidate deferral-reason breakdowns.
9. Wrote `phase8-precutover-report.md` covering every item task 8.1 lists. Led with a **§0** calling
   out the `kb.metrics` 60-row-vs-7,074-row discrepancy up front rather than burying it, citing
   `2026081905`'s own prior investigation instead of re-investigating from scratch.
10. Marked task 8.1 `[x]` with a dated note; committed.

### Task 8.3 — user manual rewrite (commit `okvs/9155` ChenWeb, `vmrl/eaf3` KnowledgeStore)

11. Grepped `ChenWeb/docs` for every schema/processor term this ADR touches — zero hits outside the
    openspec change directory. Nothing stale there.
12. Read the full 844-line `metric-assertion-semantic-processing-v1.2-en.md`. Found it built
    entirely around the pre-lossless model: no `represented` status, no DR9 independent state
    dimensions, no raw-preserved instances, an "important current limitation" that turned out to
    already be resolved (`instance_of_term_id` now exists), and an open Q&A-style discussion
    (§6.10/6.11) asking exactly the assertion-convergence question the claim registry has since
    answered.
13. Surfaced the size of the gap to the user via `AskUserQuestion` before starting (full rewrite vs.
    targeted patch vs. just recording staleness). **User chose full rewrite as v1.3.**
14. Wrote `metric-assertion-semantic-processing-v1.3-en.md` (kept the version-per-file convention —
    v1.0–v1.2 untouched, matching how v1.2 itself left v1.1 unchanged). Verified every referenced
    ADR file path actually exists before citing it (caught and fixed one wrong guessed filename for
    ADR `2026081701`).
15. Marked task 8.3 `[x]` in ChenWeb; committed both repos.

### Task 5.8 — dashboard fix (commit `mkqz/a4e0`)

16. Investigated what "dashboards and alerts" actually refers to in this codebase (not named or
    scoped anywhere in `2026082001` or earlier handoffs). Found: no Slack/email/webhook alerting
    exists anywhere. The one real dashboard is `doc-processor-dashboard-view.svelte`'s "Failed
    Pipelines" panel.
17. Confirmed `associate_semantics`'s own false-failure case (a semantic finding making the whole
    record look "failed") was already fixed at the data source by task 6.6, two sessions ago —
    this dashboard reads that same status data, so nothing further was needed there.
18. Found the one live remaining gap: `extract_metrics` still legitimately fails a record for an
    unreviewed `value_range_type` string (DR12 explicitly keeps this — a real, useful signal, not a
    semantic finding), but the panel showed it identically to a genuine crash, with a "Restart"
    button that reproduces the identical failure rather than fixing anything.
19. Surfaced this concretely to the user with three options via `AskUserQuestion`. **User chose the
    narrow, frontend-only fix** (distinguish the label/color; point at the mapping-triage admin
    page instead of/alongside Restart — not a broader aggregate findings dashboard, and not just
    documenting the finding without a fix).
20. TDD: added `isMappingTriageFailure` to `doc-processor-dashboard-state.ts`, matching the one
    place this error text is generated (`extract-metrics.go`'s `checkValueRangeTypeMappings`) via a
    stable substring. Four new tests in `doc-processor-dashboard-state.test.ts`
    (`node --experimental-strip-types --test`, 22/22 passing including the new ones).
21. Wired it into `doc-processor-dashboard-view.svelte`: a mapping-triage failure now renders as a
    distinct amber badge (`(mapping triage)`, reusing the same amber convention task 5.5's Semantic
    Diagnostics tab already established) with an explanatory tooltip; the row's action column shows
    "Needs mapping triage, not restart" instead of the Restart button when every failed step on that
    record is this case.
22. Deliberately did **not** wire live cross-panel navigation to the "Resolve Metric Range Types"
    admin page — traced the component hierarchy (`dashboard.svelte` owns `activeMenu` state,
    `content-panel.svelte` passes only `{darkMode}` to this component today) and judged plumbing a
    navigation callback through both layers to be outside the approved narrow scope. Used static
    tooltip/label text naming the exact admin path instead.
23. Verified via `svelte-check --tsconfig ./tsconfig.json` (clean on both edited files; the one
    error `svelte-check` reported anywhere is a pre-existing, unrelated `.ts`-extension import lint
    in the test file that predates this session — confirmed via `jj diff` that the flagged line
    was untouched) and `eslint` (21 pre-existing errors scattered across unrelated lines in the
    2000+-line view file — Set usage, unused `_` vars, missing each-block keys elsewhere — none
    introduced by this diff, confirmed by checking each flagged line against the actual diff).
24. **Could not complete a live authenticated browser check.** Found the dev server already running
    (`vite` on 5173, `air`/`mise dev` in the background) and attempted Playwright verification, but
    the app requires login (Kratos-backed) and no dev/test credentials were discoverable in `.env`
    or anywhere else searched. Reported this limitation to the user explicitly rather than silently
    skipping it or guessing credentials.
25. Marked task 5.8 `[x]` with a dated note explaining exactly what was and wasn't verified;
    committed.

### After task 5.8

26. Reported final status: 70/72 complete, only 7.7 and 8.4 (blocked on 7.7) remaining. **User asked
    for this handoff, explicitly stating they will "handle the remaining" in other sessions and
    specifically naming "the frontend page for the dashboard" as something to include in a future
    session** — see §9 for what this most plausibly refers to.

## 4. Exact revisions this session produced

ChenWeb (`jj log -r 'llvx..@'` — everything after `2026082001`'s tip):
```
mkqz/a4e0  feat(doc-processor-dashboard): task 5.8 -- distinguish mapping-triage failures from real ones
okvs/9155  docs(lossless-semantic-processing): task 8.3 -- ChenWeb/docs clean, user manual rewritten as v1.3
xytx/62e0  docs(lossless-semantic-processing): task 8.1 pre-cutover report against live miner data
qsnu/4051  docs(lossless-semantic-processing): resolve ADR §10 items 1–4 and record the retry-worker-pool gap
llvx/1d9c  feat(ontology): certify a real provision instance adapter and writer  [predecessor's, unchanged]
```

Files touched this session (`jj diff --summary -r 'llvx..@'`) — confirms **no Go files were changed
this session**, only openspec docs and the three dashboard frontend files:
```
M openspec/changes/lossless-semantic-processing/design.md
A openspec/changes/lossless-semantic-processing/phase8-precutover-report.md
M openspec/changes/lossless-semantic-processing/tasks.md
M web/src/lib/components/home3/doc-processor-dashboard-state.test.ts
M web/src/lib/components/home3/doc-processor-dashboard-state.ts
M web/src/lib/components/home3/doc-processor-dashboard-view.svelte
```

KnowledgeStore (`jj log -r 'nkws..@'` — everything after `2026082001`'s own commit):
```
vmrl/eaf3  docs: metric-assertion-semantic-processing v1.3 -- rewrite for the lossless state model
kyzy/f42b  docs: ADR 2026081801 Appendix C -- resolve §10 items 1-5
nkws/709a  docs: add session handoff 2026082001 -- ...  [predecessor's, unchanged]
```

Every one of `qsnu/4051`, `xytx/62e0`, `okvs/9155`, `mkqz/a4e0` (ChenWeb) and `kyzy/f42b`,
`vmrl/eaf3` (KnowledgeStore) was scoped live with the user before being built, and — for the code
change — tested (`node --test`, `svelte-check`) before being described, continuing this ADR's
established "real, tested, verified commit" standard.

## 5. Findings and judgment calls not written down anywhere else

1. **A "Phase" grouping in `tasks.md` is not a session boundary.** Task 5.8 lives under "Phase 2" in
   the file, sandwiched between otherwise-all-`[x]` items, and was never mentioned once in
   `2026082001` (which closed out Phase 4). It sat open, easy to overlook, until the user typed
   "5.8" directly. **Lesson for a future session:** don't assume a phase is "done" just because the
   session working on it moved on — re-check `openspec status`'s actual pending-task list rather
   than trusting a phase label.
2. **Appendix A.4's blocking condition can be checked mechanically, not just argued about.** Rather
   than treating "has the class/instance apparatus been committed to a second family" as a matter of
   interpretation, it was answered by grepping `provision_lossless_writer.go` for the three
   apparatus table names and finding zero hits. When a similar "is X gate satisfied" question comes
   up again (e.g., for task 7.7's next family), check the actual write paths before asking the user
   to adjudicate — but still confirm the conclusion with them, since the user's own explicit gate
   (A.4) deserves their sign-off, not a unilateral close.
3. **The retry-queue investigation (task 8.2 item 5, and independently task 5.8) both found the same
   underlying shape of gap: something is wired to write, nothing is wired to read/act.** This is
   now the second time this exact pattern has surfaced in this ADR (`kb.semantic_retry_queue`
   enqueues with no `Claim` caller; and separately, before this session, task 7.4's discovery that
   the fallback gate had nothing calling `Upsert`). **This is worth treating as a standing question
   for the whole codebase, not two isolated findings**: are there other `*Queue`/`*Store` types with
   a real `Enqueue`/write path and zero real drain? Not investigated further this session — flagged
   here as a pattern, not chased down.
4. **`ApplyValueRangeTypeMapEntry` (the "Resolve Metric Range Types" button's actual apply action)
   does not call `associate_semantics` or the retry queue.** It directly `UPDATE`s
   `kb.metrics.value_range_type`. The user's own mental model was that this button "re-processes"
   the affected metrics; investigation showed it only corrects the raw table — whether the semantic
   assertion picks up the correction depends on the record later flowing through the ordinary
   pipeline again. This is now documented in ADR Appendix C.5, the user manual §9, and (implicitly)
   task 5.8's tooltip text, but it was not something the user was aware of before this session
   surfaced it, and it may be worth a dedicated look in a future session if it turns out to matter
   operationally (e.g., if approved mappings are *not* actually getting picked up in practice).
5. **The doc-processor dashboard component (`doc-processor-dashboard-view.svelte`) is over 2,000
   lines with pre-existing lint debt (21 eslint errors) scattered throughout, unrelated to this ADR.**
   None of it was touched or fixed this session, per "surgical changes" — but a future session
   doing more work in this file should expect to see that pre-existing debt in `eslint` output and
   not mistake it for something they introduced. Cross-referenced each flagged line against the
   diff before concluding this.
6. **No dev/test login credentials exist anywhere discoverable in this repo for automated browser
   testing.** `.env` was checked for a bypass flag or seeded admin account; found none. No Playwright
   test infrastructure with a login helper exists either. This blocked visual verification of task
   5.8's UI change. **If a future session needs to do real browser-based verification of this app,
   it will need the user to either provide credentials or set up a documented dev-auth bypass** —
   this is a standing gap, not specific to this session's change.

## 6. What was deliberately NOT built

- **No corpus-wide reprocessing or backfill of any kind.** Task 8.1's report is a measurement of
  current state, not a data-changing action. Consistent with the "Note on backfills" policy this
  ADR has followed throughout.
- **No live navigation wiring from the dashboard's mapping-triage badge to the "Resolve Metric Range
  Types" admin page.** The component hierarchy (`dashboard.svelte` → `content-panel.svelte` →
  `doc-processor-dashboard-view.svelte`) has no navigation-callback prop reaching this component
  today; adding one was judged outside the user's approved narrow scope for task 5.8. Static text
  names the path instead. **This is very plausibly what the user means by "the frontend page for
  the dashboard" in their handoff request** — see §9.
- **No fix for `kb.semantic_retry_queue`'s missing drain**, and no decision to retire the enqueue
  call either — left genuinely open per the user's explicit choice (ADR Appendix C.5).
- **`LOSSLESS_SEMANTIC_WRITES_PROVISION` was not touched** — untouched by this session, exactly as
  `2026082001` left it (off, by deliberate choice, still authorized-if-flipped per
  `provision-writer-readiness`).
- **Task 7.7 (migrating entities/inventory items/products/relations) and task 8.4 (ADR status flip)
  remain untouched.** 8.4 is correctly blocked — the ADR's own §1.2 ties the status flip to Phase 4
  closing, and 7.7 (Phase 4's remaining work) hasn't started.
- **No live authenticated browser verification of the task 5.8 UI change** — see §5 item 6. Relied
  on `node --test` (22/22 passing) and `svelte-check` (clean) instead.
- **The KnowledgeStore diary file's uncommitted change was left completely alone**, for the third
  consecutive session — see §8.

## 7. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb

# Confirm the commit graph matches this handoff's account
jj log -r 'llvx..@' --no-pager

# Confirm the working tree is clean
jj status

# Confirm openspec sees 70/72 tasks complete, with exactly 7.7 and 8.4 pending
openspec instructions apply --change "lossless-semantic-processing" --json \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['progress']); [print(t['id'], t['description'][:60]) for t in d['tasks'] if not t['done']]"

cd web

# Confirm the new dashboard-state tests pass (22/22, including the 4 new ones)
node --experimental-strip-types --test src/lib/components/home3/doc-processor-dashboard-state.test.ts

# Confirm svelte-check is clean on the edited files (ignore the one pre-existing
# .ts-extension import error in the test file -- unrelated to this session)
npx svelte-check --tsconfig ./tsconfig.json 2>&1 | grep -A3 "doc-processor-dashboard"

cd ~/Workspace/KnowledgeStore

# Confirm the commit graph matches this handoff's account
jj log -r 'nkws..@' --no-pager

jj status   # expect: doc-repo/diary/202608/20260819-diary.md modified, unrelated to this session

# Confirm the ADR appendix and the new manual version both exist
grep -n "Appendix C" doc-repo/adrs/202608/2026081801-adr-lossless-semantic-processing-and-knowledge-preservation.md | head -1
head -20 doc-repo/user-manuals/metric-assertion-semantic-processing-v1.3-en.md
```

## 8. Traps for the next session

- **All traps from `2026082001` and its predecessors not specifically superseded here still apply**:
  `LOSSLESS_SEMANTIC_WRITES_METRIC` defaults ON; `LOSSLESS_SEMANTIC_WRITES_PROVISION` defaults OFF
  on purpose; `assertions.RegisteredFamilies()` has exactly two families, both with real adapters
  (don't expect `fallback-conformance` to do anything until a third family gets a normalizer without
  a real adapter); only one real provision instance exists in the corpus (`416_prv_1`); the
  `kb.metrics` 60-row situation is a well-evidenced theory, not a fact; `jj split` hangs
  non-interactively; editing files under `server/cmd/` or `project_migrations/` triggers `air` to
  rebuild and auto-apply migrations.
- **§10's five open questions are now all closed or explicitly, deliberately left open — don't
  re-litigate them from scratch.** Read ADR `2026081801` Appendix C first. In particular: item 4
  ("first non-metric family") is closed as "provision," but the ADR-2026081701 four-table apparatus
  itself is still metrics-only by choice — don't read task 7.6's existence as having already
  "generalized" that apparatus.
- **`kb.semantic_retry_queue` still has no drain.** This was investigated twice this session (task
  8.2 and, independently, task 5.8) and both times confirmed the same fact: `RetryQueue.Claim` has
  zero production callers. Don't assume this changed unless a future session specifically built one.
- **The three v1.2 user-manual sections that were most substantively wrong** — the pipeline diagram
  in old §3, the "when is a metric good" bar in old §6.6, and the open Q&A in old §6.10/6.11 — are
  now answered in v1.3. If anything in v1.3 turns out to be wrong once task 7.7 lands (e.g., if a
  future family *does* need the claim registry, contradicting v1.3 §6.9's provisions-vs-metrics
  framing), update v1.3 in place — don't create v1.4 for a small correction; this workspace's
  version-bump convention has so far been used for substantive rewrites, not patches (though there
  is no hard rule recorded anywhere that says so).
- **The user explicitly asked for "the frontend page for the dashboard" to be picked up in another
  session.** The most likely candidates, in order of how directly they were flagged this session:
  (a) wiring real navigation from the mapping-triage badge to the "Resolve Metric Range Types" admin
  page (§6, deliberately deferred, needs a navigation-callback prop plumbed through
  `content-panel.svelte`/`dashboard.svelte`); (b) getting real browser-based visual verification of
  the task 5.8 change, which needs dev login credentials that don't currently exist anywhere
  discoverable (§5 item 6); (c) possibly a broader aggregate findings/diagnostics view on this same
  dashboard (the "add a findings summary too" option the user did *not* pick this session, but which
  remains a legitimate larger-scope future direction). **Don't assume which of these the user means
  without asking** — the request was made in the same breath as "handle the remaining" (7.7/8.4), so
  it may be one combined future session or a separate, dashboard-focused one; that wasn't specified.
- **There is still a pre-existing, uncommitted change in `KnowledgeStore` unrelated to any of these
  sessions**: `doc-repo/diary/202608/20260819-diary.md`, flagged in `2026082001` and left untouched
  again this session, for the same reason — it is not this session's to commit or discard. Ask the
  user before touching it.

## 9. Where to resume

**The user explicitly said they will handle task 7.7 and task 8.4 (still blocked on 7.7) in other
sessions, and separately named "the frontend page for the dashboard" as something to include in
future work too.** No further code work should be started until the user gives direction on which
of these to pick up, and in what order. When resuming:

1. **Task 7.7** ("factor proven metric behavior into the shared adapter framework, then migrate
   provisions, entities, inventory items, products, and relations one vertical slice at a time") is
   the next `[ ]` item in `tasks.md` §7. Per `2026082001` §5 item 3 (still accurate, unchanged this
   session): check per-family whether a claim registry is actually needed before assuming
   provisions' simpler, apparatus-free shape generalizes — entities in particular look like they
   might need it, the same way metrics do.
2. **Task 8.4** (ADR status flip) is correctly blocked on 7.7 closing — don't attempt it before then;
   ADR §1.2 is explicit about this.
3. **"The frontend page for the dashboard"** — clarify with the user which of §8's three candidates
   (live navigation wiring, browser-verified visual check with real credentials, or a broader
   aggregate findings view) they mean before starting, since all three are plausible readings of
   what was said and they have different scopes.
4. No other item from `2026082001`'s or earlier resume lists remains open that this session didn't
   address, beyond 7.7/8.4 themselves.
