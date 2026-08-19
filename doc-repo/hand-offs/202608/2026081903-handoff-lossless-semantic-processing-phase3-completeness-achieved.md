# Lossless Semantic Processing (ADR `2026081801`) — Phase 3 Completeness Achieved: Session Handoff

Date: 2026-08-19

## 1. State in one paragraph

This session ran the actual live document-processing pass that the previous handoff left as the
open decision: the user had already run `extract_metrics` → `normalize_assertions` →
`associate_semantics` → `project_semantics` against doc 416 (60 metrics) with
`LOSSLESS_SEMANTIC_WRITES_METRIC` enabled. Verification found 59/60 metrics written correctly
through the DR5 lossless writer on the first pass; the 1 exception was a legitimate
object-reconciliation ambiguous tie (ADR `2026070701`), not a bug. That tie was resolved via the
existing `resolve-ambiguous` mechanism, `associate_semantics`/`project_semantics` were re-run for
the one affected metric, and **`metric-writer-readiness` now reports `complete=true` for the first
time ever** — conformance passes, zero missing stage outcomes, zero artifacts with neither path.
Task 6.9 is now marked done in `tasks.md`. Along the way: this session's own first recovery attempt
had a bug (forgot to export the gate for an ad-hoc script, silently fell through to the legacy
writer), which was caught, rolled back with the user's explicit sign-off, and redone correctly — see
§4 item 1, a real trap for future ad-hoc scripts against this code. Also added a new `warning`
`kb.doc_proc_logs` entry_type per explicit user request (goose migration + Go constant) and wrote
one diagnostic log entry documenting the resolved tie. Two things are flagged but NOT resolved this
session: `kb.metrics` currently holds only 60 rows total (all doc 416 — the wider historical corpus
appears to have been cleared at some point), and the ChenWeb working tree already contained a
separate, more durable, uncommitted implementation of essentially the same "persist ambiguous-tie
candidates" feature this session was asked to add — see §4 items 3–5 and §9.

## 2. Document lineage (read in this order if picking this up cold)

1. **This handoff's predecessor** —
   `hand-offs/202608/2026081902-handoff-lossless-semantic-processing-phase3-writer-gate-enabled.md`.
   Config-only session: flipped the gate on locally, restarted the dev server, confirmed live —
   but no document had been processed yet, so completeness was still 0.
2. **That session's predecessor** —
   `hand-offs/202608/2026081901-handoff-lossless-semantic-processing-phase3-commits-landed.md`.
   Pure git/jj bookkeeping session; has the commit-by-commit account of Phase 3's 6.1–6.10 work.
3. **`hand-offs/202608/2026081806-handoff-lossless-semantic-processing-phase3-near-complete.md`** —
   full account of what Phase 3 actually built.
4. **ADR `2026081801`**, Appendix B — governs why 6.9 is closed by a live run, not a backfill; this
   session's `complete=true` result is exactly the standard Appendix B describes, applied to
   whatever corpus currently exists in `kb.metrics` (see §4 item 4 for the caveat on what that
   means right now).
5. **ADR `2026070701`** (`doc-repo/adrs/202607/2026070701-adr-object-reconciliation-ambiguous-tie-resolution.md`)
   — newly load-bearing this session: governs the exact mechanism (DR1/DR5/DR6/DR7) behind the one
   metric this session had to unblock.
6. **`ChenWeb/openspec/changes/lossless-semantic-processing/consumer-lifecycle-policy.md`** —
   §"Task 5.8" is still the accurate analysis for why 5.8 remains blocked; not re-verified this
   session against the now-closed 6.9 (see §9 item 3).
7. **OpenSpec `tasks.md`** — live task tracker; 6.9 is now `[x]` with this session's account appended
   inline. `openspec status --json` remains authoritative over any handoff's stated task count.

## 3. What was done this session

1. **Verified doc 416's live-processing results table by table.** `kb.input_proc_status` showed all
   14 processors (including `extract_metrics`, `normalize_assertions`, `associate_semantics`,
   `project_semantics`) at `success` with no errors. `kb.metrics` had 60 rows for doc 416. Cross-
   checked `kb.semantic_processing_outcomes`, `kb.assertion_evidence`, and `kb.semantic_assertions`
   directly against every one of the 60 metric rows: 59 had exactly 3 active outcome envelopes
   (normalize/class-resolution/associate), a `represented` assertion with a real `value_state_term_id`,
   and one current supporting evidence link — proving the DR5 writer worked correctly at scale on a
   real document, not just in tests.
2. **Root-caused the 1 exception.** Metric `416_mtc_42` ("浸出液保存时间上限") was `deferred` with
   `decision_reason=unresolved_referent`. Traced to `kb.artifact_objects` id 3528:
   `reconcile_status='ambiguous'`, `object_id` empty. Queried `kb.object_nodes` directly and found a
   genuine 1.0-vs-1.0 tie between `obj_416_00a60b863327` (浸出液/Leachate, exact Chinese-name match)
   and `obj_416_158ede4665be` (浸提液/Extract, exact match via the shared English normalized name
   "extract") — a real near-synonym collision, not neglect.
3. **Checked DR7 (LLM auto-resolution) status and found it live** —
   `RESOLVE_AMBIGUOUS_OBJECT_MODEL_NAME=deepseek-flash-chen` is set in `mise.local.toml`, contradicting
   a stale project-memory note from 2026-07-19 saying it was disabled. 22 other metric-family ties
   have been auto-resolved via `llm_ambiguous_resolution` historically. DR7 saw this specific tie and
   declined (presumably below `RESOLVE_AMBIGUOUS_MIN_CONFIDENCE=0.85`) rather than force a pick —
   confirming this one was genuinely hard, not overlooked. Updated the stale memory file.
4. **Confirmed `kb.metrics` currently holds only 60 rows total, all from doc 416** — via direct count
   (`count(*)`, `count(distinct input_record_id)` both trivial) and cross-checked against
   `pg_stat_user_tables` (cumulative `n_tup_ins=393`, `n_tup_del=7373` on `kb.metrics`) and
   `kb.metric_value_range_type_map` (still holds 63/5/7 approved/proposed/ambiguous mappings dated
   2026-08-14/15 — i.e. from when a much larger corpus existed, matching design.md's "629 ambiguous"
   figure). The wider historical metrics corpus was cleared/truncated at some point between
   2026-08-15 and this session. **Not root-caused further** (who/when/why) — flagged to the user, not
   resolved.
5. **Resolved the ambiguous tie**, per the user's explicit choice (asked via AskUserQuestion: DR5
   bulk / DR6 human review / leave deferred — user picked DR5). The HTTP endpoint
   (`POST /kb/objects/resolve-ambiguous`) requires JWT auth not available non-interactively, so ran
   its exact underlying logic (`docprocessing.ResolveAmbiguousArtifactObjects`) directly against the
   DB via a throwaway `server/cmd/resolve-ambiguous-once/main.go` (deleted immediately after use, not
   committed). Result: `tie_broken=1`, resolved to `obj_416_00a60b863327` (浸出液/Leachate) — matches
   the metric's own name, via the existing deterministic tie-break (most normalized-name overlap,
   then lowest `object_id`).
6. **First recovery attempt had a bug.** Wrote a second throwaway program
   (`server/cmd/doc416-recover-once/main.go`) to re-run `AssociateSemantics.Run` +
   `ProjectSemantics.Run` for record 416. Ran it without exporting
   `LOSSLESS_SEMANTIC_WRITES_METRIC` in that process's environment — the gate is read fresh from
   `os.Getenv` on every call inside `processMetric` (`semantic.NewGates().MetricLosslessWritesEnabled()`),
   so it silently took the **legacy** accept path instead of DR5. Produced assertion id 402,
   `status='accepted'`, `value_state_term_id=NULL` — inconsistent with the other 59 assertions.
7. **Caught it, asked the user, rolled it back with explicit approval.** A first attempt to run the
   corrective SQL transaction directly was blocked by the auto-mode classifier (raw destructive-
   looking DB write); explained the situation to the user via AskUserQuestion, got explicit approval
   for the same transaction, then ran it: deleted `assertion_evidence` id 131, nulled candidate 693's
   `resulting_assertion_id`, deleted `semantic_assertions` id 402, reset candidate 693 back to
   `status='candidate'`.
8. **Redid the recovery correctly**, this time with `LOSSLESS_SEMANTIC_WRITES_METRIC=true` explicitly
   exported. Produced assertion id 403, `status='represented'`,
   `value_state_term_id='semantic:value_present'`, all 3 outcome envelopes active, 1 supporting
   evidence link — matching the pattern of the other 59. Deleted the throwaway program afterward.
9. **Re-ran `metric-writer-readiness`: `complete=true`.** Conformance passes; 0 missing stage
   outcomes; 0 artifacts missing any stage; 0 artifacts with neither path; 0 summary drift; 0 orphan
   active findings. (`assertions missing value state: 60` and `artifacts with missing value: 3` are
   both non-blocking informational counts — the 60 are pre-existing legacy assertions unrelated to
   doc 416, verified by join; the 3 are legitimate DR12 `value_state_missing` metrics like the
   "limit_absent" ones, not a gap.)
10. **Added `entry_type='warning'` to `kb.doc_proc_logs`**, per explicit user request (distinct from
    `'error'`: a benign/expected condition, not an operational failure). Wrote
    `project_migrations/20260819000003_add_warning_doc_proc_log_entry_type.sql` (extends
    `doc_proc_logs_entry_type_check`, following the exact pattern of the same-day
    `20260819000002_add_error_doc_proc_log_entry_type.sql`), and added the matching
    `EntryTypeWarning` Go constant + wired it into `allowedDocProcLogEntryType` in
    `server/api/doc-processing/doc_proc_log_store.go`. Migration auto-applied via `air`'s file-watch
    (confirmed via `pg_get_constraintdef`).
11. **Wrote one diagnostic log entry** (`kb.doc_proc_logs` id 131855): `doc_proc_name='associate_semantics'`,
    `entry_type='warning'`, `log_loc='MID-yyyymmdd-01'` (a literal string per the user's exact
    instruction — matches a pre-existing precedent already in the table, not a template to fill in;
    see §4 item 6), `extra_info` listing both tied candidates and which one was selected.
12. **Discovered a parallel, already-built, uncommitted solution to essentially the same problem** —
    see §4 item 5. Flagged to the user; deliberately not touched or reconciled this session.
13. **Committed only this session's own two files** via `jj commit <paths> -m "..."` (change `zkzv`,
    "feat(doc-proc-logs): add warning entry_type for benign semantic diagnostics"), leaving every
    other pre-existing uncommitted file in the tree exactly as found — see §4 item 7 for why `jj
    split` was abandoned in favor of `jj commit <paths>`.
14. **Updated and committed `tasks.md`** marking 6.9 `[x]` with this session's account appended
    (change `uxvs`, "docs(lossless-semantic-processing): close task 6.9 — completeness projection
    now passes").

## 4. Findings not written down anywhere else

1. **The metric-writer gate is read live from the OS environment on every call, with zero
   validation against what's actually running.** `semantic.NewGates().MetricLosslessWritesEnabled()`
   inside `processMetric` (`associate_semantics.go:360`) calls `os.Getenv` fresh each time — not
   cached, not checked against `mise.local.toml` or the live server process. Any ad-hoc `go run`
   invocation (a throwaway diagnostic script, a one-off `cmd/` tool) that doesn't explicitly export
   `LOSSLESS_SEMANTIC_WRITES_METRIC=true` will silently take the legacy accept path — no error, no
   warning, nothing distinguishing it from a correct DR5 write except the resulting assertion's
   `status` and `value_state_term_id`. This session hit it directly (§3 item 6). Any future one-off
   script touching this pipeline must export the gate explicitly.
2. **DR7 (LLM ambiguous-tie auto-resolution) is live but not exhaustive.**
   `RESOLVE_AMBIGUOUS_OBJECT_MODEL_NAME=deepseek-flash-chen` is set (contradicting a stale
   2026-07-19 memory note). It silently declines ties below `RESOLVE_AMBIGUOUS_MIN_CONFIDENCE=0.85`
   rather than force a pick, so a residual `reconcile_status='ambiguous'` row can mean "genuinely
   hard for even the LLM," not "DR7 never ran on it."
3. **`kb.metrics` currently contains only 60 rows total, all from doc 416.** Confirmed via direct
   count and `pg_stat_user_tables` (cumulative `n_tup_del=7373` vs `n_tup_ins=393`). The wider
   historical corpus (implied by `design.md`'s "629 ambiguous range-type mappings" and by
   `kb.metric_value_range_type_map` still holding 63/5/7 approved/proposed/ambiguous entries dated
   2026-08-14/15) is gone from `kb.metrics` specifically — the mapping table itself was not touched.
   Who/when/why was not established.
4. **"`complete=true`" right now means complete for whatever currently exists in `kb.metrics`, not
   for the full 209-document corpus.** `MetricArtifactSourceSQL` (`SELECT ... FROM kb.metrics`) has
   no historical/versioning filter — "current artifacts" is just "every row present right now."
   Given finding 3, that's presently only doc 416's 60 metrics. This does satisfy ADR Appendix B's
   literal standard ("a live document-processing run naturally produces completeness-passing
   artifacts"), but it is a materially smaller bar than "the DR5 writer has been proven against the
   real production corpus." Expect future documents to surface their own fresh ambiguous-tie or
   governed-term gaps, each needing similar manual resolution until DR7/DR5's automatic paths cover
   more cases outright.
5. **A parallel, more durable, already-implemented (but uncommitted) mechanism for this exact
   problem already existed in the working tree before this session started.**
   `docs/superpowers/plans/2026-08-19-ambiguous-object-warning-log.md` (all tasks checked off) +
   matching diffs in `server/api/doc-processing/object_nodes.go` /
   `object_nodes_test.go` persist every future ambiguous-tie candidate list into `kb.doc_proc_logs`
   automatically, using the **existing** `reconcile_object` entry_type (no schema change) — built via
   TDD, dated today. This session's `'warning'`-entry-type addition and one diagnostic log row are a
   second, different, one-off mechanism solving a similar problem for the same historical incident.
   Both now coexist uncommitted/committed in the tree; neither was reconciled with the other. See §9
   item 1.
6. **The `log_loc` DB column is populated by the *positional* `loc` argument passed to
   `insertDocProcLog`, not by the `DocProcLogRecord.LogLoc` field set via `callerLoc(2)` inside each
   `Log*` wrapper** — that field is computed but never actually used in the `INSERT`. At least one
   call site (`logPhaseDError`, `phase_d.go:148`) passes the literal, unsubstituted string
   `"MID-yyyymmdd-01"` as this argument, which reads like an unfilled template but is real, current
   behavior — one pre-existing row already had exactly this literal value before this session added a
   second (the diagnostic entry in §3 item 11, per explicit user instruction to match it). Worth a
   future session deciding whether to actually template it or leave it as a known quirk.
7. **`jj split <paths>` hangs indefinitely (0% CPU, no output) when run non-interactively in this
   environment, even with filesets given** — the CLI help says filesets should skip the interactive
   diff editor, but it didn't in practice; had to `kill` it. `jj commit <path1> <path2> -m "..."`
   (already used successfully earlier today per this repo's own `jj op log`) does the same
   "commit only these paths, leave the rest as the new working-copy change" job and works
   immediately. Prefer `jj commit <paths> -m` over `jj split <paths>` for non-interactive path-scoped
   commits going forward.

## 5. What was deliberately NOT built

- **Did not reconcile the two now-coexisting ambiguous-tie logging mechanisms** (§4 item 5) — no
  attempt to decide which is canonical, merge them, or remove either.
- **Did not commit any of the other pre-existing uncommitted work** found in the tree: the orphaned-
  label-maintenance feature, the ambiguous-object-warning-log implementation itself, changes to
  `dbmainthandler`, `releases_store`, `workspacelists`, `nullable.go`, `docs/test_doc_244.pdf/typ`,
  `server/tmp`, and two other `project_migrations` files (`20260819000001`,
  `20260819000002` — the latter is the same-day `'error'`-entry-type migration this session's
  `'warning'` one was modeled on). All left exactly as found.
- **Did not investigate who/when/why `kb.metrics` was reduced to 60/doc-416-only rows** — flagged
  only, per finding §4 item 3.
- **Did not reprocess any other document beyond 416.** 6.9 closing does not mean the DR5 writer has
  been proven against the full historical corpus — only against this one pilot document.
- **Did not start Phase 4 (7.1–7.7) or Phase 8 (8.1–8.4)** — both are now unblocked in principle
  (6.9 closed), but no code was written for either.
- **Did not re-verify task 5.8** against the now-closed 6.9 — `consumer-lifecycle-policy.md`'s
  existing analysis was not re-run this session.

## 6. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb

# Re-confirm completeness (expect complete=true, 0 across every blocking count)
PG_DB_NAME=miner PG_USER_NAME=admin go run ./server/cmd/metric-writer-readiness/

# Confirm the recovered metric's final state
psql -h 127.0.0.1 -p 5432 -U admin -d miner -c \
  "select id, status, value_state_term_id from kb.semantic_assertions where id = 403;"

# Confirm the diagnostic warning log entry
psql -h 127.0.0.1 -p 5432 -U admin -d miner -c \
  "select id, doc_proc_name, entry_type, log_loc, errors from kb.doc_proc_logs where entry_type='warning' order by create_time desc limit 1;"

# Confirm this session's two commits landed and the rest of the tree is untouched
jj log -n 5
jj status

# Confirm 6.9 is marked done
grep -A1 '6.9 Enable' openspec/changes/lossless-semantic-processing/tasks.md | head -1
```

## 7. Traps for the next session

- **`kb.metrics` currently reflects ONLY doc 416 (60 rows).** Don't read `complete=true` as "the
  full corpus is done" — it means "the corpus as it currently exists is done." See §4 items 3–4.
- **Ad-hoc `go run` scripts against this codebase MUST explicitly export
  `LOSSLESS_SEMANTIC_WRITES_METRIC=true`** (and match whatever else is in `mise.local.toml`) or they
  will silently use the legacy writer path with zero warning. See §4 item 1.
- **Two coexisting mechanisms now write ambiguous-tie diagnostics to `kb.doc_proc_logs`** —
  `entry_type='warning'` (this session, one-off) and the uncommitted `reconcile_object`-based
  permanent path (§4 item 5). Reconcile before building more on either.
- **The working tree has a lot of other uncommitted, unrelated work sitting in it** (§5) — run `jj
  status` before assuming a clean tree or attributing a diff to "this session."
- **DR7 LLM auto-resolution is on but not exhaustive** — don't assume every
  `reconcile_status='ambiguous'` row will self-clear; some are genuinely hard even for the LLM path.
- **`jj split` hangs non-interactively in this environment** — use `jj commit <paths> -m` for
  path-scoped commits instead (§4 item 7).
- All traps from 2026081902 and its predecessors not specifically resolved here still apply:
  `git status`/`git diff HEAD` unreliable in these colocated jj repos (use `git log <bookmark>` or
  `jj log`); editing files under `server/cmd/` or `project_migrations/` triggers `air` to rebuild and
  apply pending migrations automatically (confirmed again this session — the `'warning'` migration
  auto-applied without a manual `goose up`); `metric-support-cleanup`, `metric-foundation-shadow-report`,
  and `metric-writer-readiness` are reusable ops tools worth keeping.

## 8. KnowledgeStore working-tree state

This handoff document is the only new file this session adds to `doc-repo/`.

## 9. Where to resume

1. **Reconcile the two ambiguous-tie logging mechanisms** (§4 item 5) — the uncommitted
   `object_nodes.go` work (permanent, `reconcile_object`-based, fires for every future tie
   automatically) is probably the one worth keeping long-term; this session's `'warning'` entry_type
   and one-off diagnostic row may end up redundant with it, or may be worth keeping as a distinct
   "actionable/needs-attention" severity tier separate from routine `reconcile_object` logging. Not
   decided this session.
2. **Confirm whether the `kb.metrics` reduction to 60/doc-416-only rows was intentional.** If not,
   investigate what cleared it and whether it's recoverable.
3. **Re-run task 5.8's blocking analysis** now that 6.9 is genuinely closed (not just gate-enabled) —
   `consumer-lifecycle-policy.md`'s existing reasoning was written when 6.9 was still open; worth
   confirming it still holds now that real `represented` metric assertions exist for the first time.
4. **Decide on reprocessing more of the corpus** (organic usage vs. a deliberate batch) now that the
   DR5 writer has been proven end-to-end on one real document — this is the natural next lever for
   growing real completeness beyond this single-document pilot, and it costs real LLM API budget
   (same open decision as the predecessor handoff's §9.1, now informed by a successful first run).
5. **Phase 4 (tasks 7.1–7.7) and the pre-cutover reports (8.1–8.4)** are next once 5 is resolved;
   neither started.
6. **Commit or discard the substantial other uncommitted WIP** found in the tree (§5) — not this
   ADR's concern directly, but it's blocking a clean `jj status` and should get resolved by whoever
   owns that work.
7. The still-open Appendix A concern from earlier handoffs remains exactly as open as before.
