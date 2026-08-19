# Lossless Semantic Processing (ADR `2026081801`) — Phase 3 Commits Landed: Session Handoff

Date: 2026-08-19

## 1. State in one paragraph

This session did no new implementation — it closed out the predecessor handoff's single
time-sensitive trap: **everything that session left uncommitted is now committed**, split into
logical commits in both `ChenWeb` and `KnowledgeStore`, on top of their respective `main`
bookmarks (local only, neither pushed). Build, vet, and the three packages this session's
predecessor touched (`assertions`, `semantic`, `classfoundation`) are green; `kbhandler`'s
failures are the same pre-existing, out-of-scope set the predecessor handoff already documented.
Re-running `metric-writer-readiness` against `miner` shows **zero drift** from the predecessor's
numbers — conformance still passes, completeness is still blocked on the same 21,222 missing
stage-outcome pairs — confirming task 6.9 has not closed and nothing has processed the corpus
since. Phase 3 remains 11 of 12 tasks complete, exactly as the predecessor left it.

## 2. Document lineage (read in this order if picking this up cold)

1. **This handoff's predecessor** —
   `hand-offs/202608/2026081806-handoff-lossless-semantic-processing-phase3-near-complete.md`.
   Has the full account of what Phase 3 tasks 6.1–6.12 actually built, the corpus-scale findings,
   and the four undocumented findings from that session (§4 there). This handoff does not repeat
   any of that — it only records what changed since: commit state, and nothing else.
2. **ADR `2026081801`** — `adrs/202608/2026081801-adr-lossless-semantic-processing-and-knowledge-preservation.md`.
   Unchanged this session. Appendix B (recorded by the predecessor) still governs: closing the
   6.9 completeness gap is deferred to a live document-processing run, not backfill.
3. **OpenSpec change** — `ChenWeb/openspec/changes/lossless-semantic-processing/tasks.md`.
   Unchanged this session, still 63/72.

## 3. What was done this session

Purely git/jj bookkeeping — no source changes. The predecessor handoff's §7 described one jj
working-copy change (19 files, 10 new/9 modified) sitting undescribed on top of `89be94ac89f8` in
ChenWeb, plus two undescribed files in KnowledgeStore. Both are now split and described:

**ChenWeb**, 5 commits on `main` (local; `main@origin` is still at `89be94ac89f8`, 5 commits
behind):

| Commit | Contents |
|---|---|
| `23c47a70` | Phase 3 6.1–6.3: `metric-foundation-shadow-report`, `metric-support-cleanup`, `foundation-shadow-confirmation.md` |
| `46e4c9f7` | Fix: `AssertionStore.CreateAssertion`/`CreateRevision` silently dropped 9 Phase 1 state columns; added `instance_of_term_id` end-to-end |
| `00fb9eaf` | Phase 3 6.4–6.7: `metric_lossless_writer.go` (DR5 transaction), its integration tests, `associate_semantics.go` gate wiring, `class_resolution_decisions_store.go`, `outcomes.RecordTx` extraction, migration 19 |
| `930b333d` | Phase 3 6.8: `RetryQueue.ScheduleForKeyedDependencyChange`, wired into the mapping-approval handler, `ValueRangeTypeRaw` threaded through `metricCandidatePayload` |
| `d97b8496` | Phase 3 6.9–6.10: `metric-writer-readiness` tool, `phase3-writer-readiness.md`, `tasks.md` update to 63/72 |

The one deviation from the predecessor's suggested split: it proposed no new commit for 6.2–6.3
("already covered"), but `metric-support-cleanup/main.go` was in fact never committed anywhere —
only its *result* was documented in an earlier handoff addendum. Folded it into the 6.1 commit
instead of skipping it. Also, `associate_semantics.go` carries both the 6.4–6.7 gate-wiring and
the `ValueRangeTypeRaw` struct field that 6.8 depends on — file-level `jj split` can't separate
the two without an interactive hunk editor, so the whole file went into the 6.4–6.7 commit; this
is cosmetic (both commits build and test fine either way) but worth knowing if the history looks
slightly uneven there.

**KnowledgeStore**, 2 commits on `main` (local; `main@origin` is still at `1d19131`, 2 commits
behind):

| Commit | Contents |
|---|---|
| `4915292` | ADR `2026081801` Appendix B addition |
| `5ea276a` | The predecessor handoff document itself |

Split into two rather than one, matching this repo's existing convention (confirmed via `git log`
on `doc-repo/adrs/` and `doc-repo/hand-offs/`) of never bundling an ADR edit with a handoff in the
same commit.

Verification performed before committing (all against the working tree as it stood, matching the
predecessor's own §6 commands):
- `go build ./...` and `go vet ./...` — clean.
- `go test ./server/api/ontology/assertions/... ./server/api/ontology/semantic/... ./server/api/ontology/classfoundation/...` — all pass.
- `go test ./server/api/kbhandler/...` — same failures as the predecessor's documented
  pre-existing list (search registry, summary, topic handlers); confirmed unrelated, not
  re-investigated.
- `PG_DB_NAME=miner PG_USER_NAME=admin go run ./server/cmd/metric-writer-readiness/` — identical
  output to the predecessor's run: conformance passed, completeness blocked on the same 21,222 /
  7,020 counts. No drift since 2026-08-18.

## 4. Findings not written down anywhere else

1. **`git status`/`git diff HEAD` are unreliable in these colocated jj repos and should not be
   trusted for verification.** After `jj bookmark set main -r <rev>`, git's `refs/heads/main`
   updated correctly and immediately (`git log main` shows the full correct history in both
   repos), but git's detached `HEAD` itself stayed one commit behind the true tip in both repos
   until some later jj operation caught it up — so `git status` reported the last commit's files
   as "changes not staged for commit" even though they were already fully committed. Verify
   commit state with `jj log` / `git log <bookmark-name>`, never bare `git status` or `git diff
   HEAD`, in this workspace.

## 5. What was deliberately NOT built

Nothing new — this was a bookkeeping-only session. All of the predecessor handoff's §5 ("what was
deliberately NOT built") still applies unchanged: task 6.9's gate flip, DR12's recognized-special-
value row, Phase 4, and Phase 4 pre-cutover reports.

## 6. Verification — copy-pasteable

Identical to the predecessor handoff's §6, now runnable directly against `main` in both repos
without any working-copy caveat:

```bash
cd ~/Workspace/ChenWeb

go build ./... && go vet ./...

go test ./server/api/ontology/assertions/... ./server/api/ontology/semantic/... \
        ./server/api/ontology/classfoundation/... ./server/api/kbhandler/...

TEST_DATABASE_URL='host=127.0.0.1 user=admin dbname=postgres sslmode=disable' \
    go test ./server/api/ontology/assertions/ -run Integration -v

PG_DB_NAME=miner PG_USER_NAME=admin go run ./server/cmd/metric-writer-readiness/
PG_DB_NAME=miner PG_USER_NAME=admin go run ./server/cmd/metric-support-cleanup/
```

Known pre-existing `kbhandler` failures: unchanged from the predecessor handoff's §6 list. Not
re-verified line-by-line this session beyond confirming the failure set is the same shape (same
test names, same error signatures).

## 7. Traps for the next session

- **Neither repo's `main` has been pushed.** ChenWeb's local `main` is 5 commits ahead of
  `main@origin` (at `89be94ac89f8`); KnowledgeStore's is 2 ahead of `main@origin` (at `1d19131`).
  Decide whether/when to push — nobody asked for it this session so it was left local, per this
  workspace's standing rule to confirm before actions that touch shared state.
- **KnowledgeStore has an unrelated bookmark** `feature/concurrent-doc-processors` (at `bae4...`,
  a `docs(concurrent-doc-processors): expand status write concurrency safety section` commit) that
  predates this session and was not touched. Not a trap exactly, just noted so it isn't mistaken
  for something this session created.
- **Don't trust `git status` for verification in either repo** — see §4 item 1. Use `jj log` or
  `git log main`.
- All traps from the predecessor handoff's own §7 that aren't specifically about the
  now-resolved "nothing is committed" problem still apply: `kb.metric_value_range_type_map`
  approvals now enqueue real (if currently inert) retry jobs; editing files under `server/cmd/` or
  `project_migrations/` triggers `air` to rebuild and apply pending migrations automatically; the
  `AssertionStore` fix's blast radius extends to every existing caller, not just the new writer;
  `metric-support-cleanup`, `metric-foundation-shadow-report`, and `metric-writer-readiness` are
  reusable ops tools worth keeping.

## 8. KnowledgeStore working-tree state

Clean after this session's own commit. `jj st` / `git status` (via `git log main`, not bare
`git status` — see §4) show no further uncommitted changes in `doc-repo/`.

## 9. Where to resume

Unchanged from the predecessor handoff's §9, items 3–5 — nothing this session bore on them:

1. Decide whether to push ChenWeb's and KnowledgeStore's local `main` commits (§7) — the one new
   decision this session surfaces.
2. Continuing to watch for 6.9 to close naturally requires no action — re-run
   `metric-writer-readiness` periodically, or after any known batch of document processing, and
   check `completeness projection: complete=true`. As of this session, zero drift since
   2026-08-18.
3. If/when 6.9 closes, the next real body of work is Phase 4 (tasks 7.1–7.7: generic fallback,
   migrating a second family) and the pre-cutover reports (tasks 8.1–8.4) — neither started.
4. The still-open Appendix A concern from two sessions ago ("the current design of the ontology
   object-class apparatus... is not correct as specified... objection not yet articulated")
   remains exactly as open as it was.
