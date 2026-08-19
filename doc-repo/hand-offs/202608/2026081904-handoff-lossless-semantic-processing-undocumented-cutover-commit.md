# Lossless Semantic Processing (ADR `2026081801`) — Undocumented Cutover Commit Found and Documented: Session Handoff

Date: 2026-08-19

## 1. State in one paragraph

This session did not write any new production code. It picked up the prior handoff
(`2026081903`) and, before acting on its "where to resume" list, ran `jj status`/`jj log` per
that handoff's own trap warning — and found a **fourth, undocumented commit** already sitting on
top of the handoff's own two commits: `b86a "doc process and ontology bug fixes"`, created ~5
minutes after the `2026081903` handoff file's mtime, by a `jj describe` directly on the
accumulated working-copy snapshot (not a fresh session with its own handoff). This commit
actually **implements `2026081903`'s §9.1 recommendation** (the durable `reconcile_object`-based
ambiguous-tie logging, extended to the no-LLM path, with tests) and commits the rest of that
handoff's known WIP. It also contains something none of the prior handoffs mention: **`gates.go`
now defaults `LOSSLESS_SEMANTIC_WRITES_METRIC` to `true`** when unset, i.e. the actual Phase 3
writer cutover — not just "enabled locally via gitignored `mise.local.toml`" as `2026081903`
described, but baked into the code's own default for every environment. This is a substantially
bigger fact than its commit message suggests, and it left **3 tests in `ontology/assertions`
broken** (confirmed not pre-existing by diffing against the pre-`b86a` commit) because they
implicitly relied on the gate defaulting off. This session verified `go build ./...` passes, that
every *other* test failure in the repo is pre-existing (present before `b86a` too), and narrowed
the 3 new failures to one root cause — but deliberately did not fix them (see §5, §9). The user
explicitly chose "document, don't reprocess the corpus" for this session (asked via
`AskUserQuestion`); no LLM budget was spent and `kb.metrics` is untouched.

## 2. Document lineage (read in this order if picking this up cold)

1. **This handoff's predecessor** —
   `hand-offs/202608/2026081903-handoff-lossless-semantic-processing-phase3-completeness-achieved.md`.
   Ran the live doc-416 processing pass, closed task 6.9, left substantial other WIP in the tree
   uncommitted, and explicitly deferred deciding between two ambiguous-tie logging mechanisms to a
   future session (its §9.1).
2. **That session's predecessors** — `2026081902` (gate enabled locally only),
   `2026081901` (jj bookkeeping), `2026081806` (full Phase 3 build account) — unchanged by this
   session, still accurate for their own scope.
3. **ADR `2026081801`**, Phase 3 section and Appendix B — the writer-gate default this session
   found flipped is exactly the "Phase 3 cutover" the ADR's task 8.4 ("Update ADR status from
   Proposed once Phase 3 cutover completes") anticipates, but 8.4 is still unchecked and the ADR
   file itself was not touched by `b86a`. **The ADR's own text still says both gates default off.**
4. **ADR `2026070701`** — unchanged; still governs the ambiguous-tie mechanism `b86a` extended.
5. **`ChenWeb/openspec/changes/lossless-semantic-processing/tasks.md`** — unchanged by this
   session. 6.9 is `[x]`; 5.8 and all of Phase 4 (7.x)/Phase 8 (8.x) remain `[ ]`, exactly as
   `2026081903` left them.
6. **`jj op log`** — the primary source for this handoff's central claim; see §4 item 1 for the
   exact operation IDs.

## 3. What was done this session

1. **Read `2026081903` and, per its own trap list, ran `jj status`/`jj log` before touching
   anything.** Working tree was clean (`jj status`: "no changes"), but `jj log` showed a commit
   (`b86a`) beyond the two (`zkzv`, `uxvs`) the handoff described as this-session's-own.
2. **Diffed `b86a` in full** (`jj diff -r b86a --git`, 25 files, 656 insertions / 67 deletions) and
   read every hunk. Confirmed it:
   - Implements `2026081903 §9.1`: `object_nodes.go`/`object_ambiguous_llm.go` now call the
     existing `objectReconcileLogSink`/`reconcile_object` log path for the no-LLM
     unresolved-ambiguity branch too (previously only the LLM-adjudicated branches logged),
     carrying a `CandidateDisplay` field through so the DB row has the same candidate list the
     `logger.Warn` text does. New regression test:
     `TestReconcileArtifactObjectsLogsAmbiguousCandidateList`.
   - Fixes a real bug in `server/api/dbmainthandler/handler.go`: `ListOrphanedLabels`'s query
     selected `l.create_by`/`l.modify_by` without `COALESCE`, which panics/errors on legacy rows
     where those columns are NULL. New test:
     `TestListOrphanedLabelsAcceptsNullableAuditFields`.
   - Fixes a real bug in `server/api/ontology/modules/releases_store.go`: tagging a release
     updated the legacy `kb.ontology_terms` row's status to `included_in_release` but never
     synced the mirrored `kb.ontology_term_revisions` row, so `kb.ontology_terms_current` (the
     view several tests and, per finding 4 below, **production code now also reads live**)
     kept reporting the pre-release status. Added `syncTaggedTermRevisions`.
   - Fixes a real bug in `server/api/doc-processing/processor_plan.go`: `normalize_assertions`,
     `associate_semantics`, and `project_semantics` had `Requires`/`DependsOn` declared as if they
     needed their producer selected in the *same* pipeline version, which wrongly rejected the
     legitimate use case of re-running only these data-driven stages against already-persisted
     rows. Removed the declarations; `PostProcessDependsOn` in `phase_d.go` still orders them
     correctly when more than one is selected together.
   - Fixes a real bug in `server/api/ontology/assertions/assertions_store.go`: `CreateAssertion`'s
     validation required `ObjectRefID` or `ObjectLiteral` to be non-empty even when
     `ValueStateTermID == semantic.ValueMissing` (a value-state payload the schema explicitly
     allows to have neither — see Phase 1 task 2.9's constraint). Added the `ValueMissing`
     exemption plus `nullableObjectLiteral`, which preserves SQL NULL (not JSON `null`) for that
     case.
   - Adds error-path logging to `phase_d.go`'s `AssociateSemanticsProcessor`/
     `ProjectSemanticsProcessor`: a `processMetric` panic/error that isn't a `MappingMiss`, a
     `project_semantics` failure, an `association-run report` build failure, and a
     high-deferred-candidate-rate condition (>50%) now all write an `entry_type='error'` row to
     `kb.doc_proc_logs` via a new `logPhaseDError` helper, in addition to the existing in-process
     `Logger.Error` call. New tests: `phase_d_logging_test.go` (3 tests).
   - Includes the two migrations `2026081903 §5` listed as pre-existing uncommitted:
     `20260819000001_sync_ontology_term_revision_release_state.sql` (one-time backfill for the
     `releases_store.go` bug above) and `20260819000002_add_error_doc_proc_log_entry_type.sql`
     (adds `'error'` to the `doc_proc_logs` entry-type CHECK — the same-day sibling of this
     session's-predecessor's own `'warning'` migration).
   - **Changes `server/api/ontology/semantic/gates.go`**: `Gates.value()`'s "unset env var" branch
     changed from `return false` (both gates off) to `return name == GateMetricLosslessWrites`
     (metric gate on, fallback gate still off). `gates_test.go`'s
     `TestWriterGatesDefaultOff` was renamed to `TestMetricWriterGateDefaultsOn` and its assertion
     inverted to match. This is a genuine, deliberate, tested change — not an accident — but see
     §4 item 2 for why it is far more consequential than the commit message suggests.
   - Two cosmetic/drift items: renamed a test in `pipelines_handler_test.go` and
     `p5_exit_test.go`'s comment-referenced test name to match an already-renamed test elsewhere
     (no behavior change); added `user-select:text` CSS to `resolve-orphaned-labels-view.svelte`.
   - **Committed one stray file, `server/tmp`**, containing a single line of leftover shell
     history (a `vi <files...>` command) — almost certainly an accidental `jj commit`/snapshot of
     an untracked scratch file, not intentional content. See §4 item 5.
3. **Ran `go build ./...`** from `ChenWeb/server` — clean, no errors.
4. **Ran the full test suite** (`go test ./api/doc-processing/... ./api/ontology/...
   ./api/kbhandler/... ./api/dbmainthandler/...`) and got failures in `kbhandler`,
   `ontology/names`, `ontology/keywords`, `ontology/seed`, and — critically —
   `ontology/assertions` (3 tests).
5. **Isolated which failures `b86a` actually introduced.** Created a throwaway `jj new` on top of
   `uxvs` (the commit immediately before `b86a`), reran the same test packages, and diff'd the
   failure sets:
   - `kbhandler`, `ontology/names`, `ontology/keywords`, `ontology/seed`: **identical failure set
     before and after `b86a`** — pre-existing debt, unrelated to this work (search-registry column
     counts, a missing `ARTIFACT_WEB_DIR` env var, topic-resolution mismatches, an
     `ontology_terms_current` SQL-shape mismatch, `AlignmentsStore`/resolver-mode-gate tests). Not
     investigated further; out of scope.
   - `ontology/assertions`: **passed cleanly before `b86a`, fails after.** This is the one real
     regression this session found. See §4 item 2 for root cause. Abandoned the throwaway commit
     afterward (`jj abandon`) and returned cleanly to `b86a`'s tip — confirmed via `jj status`
     ("no changes") that this investigation left no trace in the working tree.
6. **Traced the `ontology/assertions` regression to its exact cause** (§4 item 2) by reading
   `associate_semantics.go`'s `processMetric` and the new `gates.go` default together, then
   spot-checked whether the invariant the broken tests assert (DR3: "proposed" vocabulary →
   `MappingMiss` → `Run` fails) has a DR12-era equivalent in the gate-on path by reading
   `metric_lossless_writer.go`'s `resolveMetricMappingState`. Confirmed DR12 does have an
   equivalent disposition (`"proposed" → MappingUnresolved state + FindingMappingUnresolved`) —
   but did **not** confirm end-to-end that it's actually equivalent in effect (a `represented`
   assertion with a finding, vs. the old world's outright `Run` failure), nor did it re-run
   `metric_lossless_writer_test.go`'s own suite to see whether *that* file already has a passing
   test for this exact case. That confirmation is left for whoever fixes §4 item 2.
7. **Read `jj op log`** and found the exact operation that turned the accumulated working-copy
   changes into `b86a`: `jj describe -m 'doc process and ontology bug fixes'` run directly against
   a `jj status`-snapshotted working copy, with no intervening test run visible in the op log
   between the snapshot and the describe. This is the evidentiary basis for §1's claim that this
   commit was never verified before being described.
8. **Confirmed the KnowledgeStore hand-offs directory** had no doc newer than `2026081903` before
   writing this one, and no existing file with the `2026081904` prefix (per this workspace's
   documented naming convention).
9. **Wrote this handoff.** No other files were touched this session — no code, no migrations, no
   task/ADR file edits.

## 4. Findings not written down anywhere else

1. **`b86a` was never tested before being committed.** `jj op log` shows: `jj status` (snapshot) →
   immediately `jj describe -m 'doc process and ontology bug fixes'`. No `go build`/`go test`
   invocation appears between them in the op log (op log only records jj operations, not shell
   commands, but the absence of any further jj activity in that window — no amend, no fixup commit
   — combined with the 3 broken tests found this session, is strong circumstantial evidence).
   Whoever/whatever produced `b86a` bundled several days' worth of accumulated, previously-reviewed
   individual features (orphaned-label maintenance, ambiguous-tie reconciliation, phase_d error
   logging, several bug fixes) under one generic message and one commit, without the verification
   pass each of `2026081903`'s and its predecessors' own commits got.
2. **The `gates.go` default flip is the actual Phase 3 writer cutover, and it is currently
   inconsistently documented and only 90%-verified.**
   - `2026081903 §3 item 3` / `2026081902` describe the gate as "enabled" only via
     `mise.local.toml` (gitignored, machine-local) — i.e., a config fact true only on this one
     dev machine. `b86a` changes the *code's own default*, which is a fact true on every machine
     and every deployment, including production, the moment this commit ships. These are
     categorically different levels of "on," and no document until this one says the second,
     bigger thing happened.
   - ADR `2026081801`'s own text (not touched by `b86a`) still states both gates default off, and
     task 8.4 ("update ADR status once Phase 3 cutover completes") is still `[ ]` — so the ADR is
     now stale relative to the code.
   - The change is deliberate and tested at the unit level (`gates_test.go` was updated in
     lockstep), so this is not an accident — but its blast radius (every consumer of
     `AssociateSemantics.Run`/`processMetric` that doesn't explicitly pin the gate) was evidently
     not checked against the existing test suite before commit, per finding 1.
3. **The regression: 3 tests in `server/api/ontology/assertions` broke, and the fix is a design
   decision, not a mechanical one.**
   - `TestRunFailsWhenCandidateBlockedOnProposedValueRangeType`,
     `TestRunSucceedsWhenCandidateDeferredForAmbiguousValueRangeType`, and
     `TestProcessMetricAcceptedPathPopulatesEvidenceProvenanceFields` (all in
     `associate_semantics_test.go`) call `AssociateSemantics.Run`/rely on `processMetric` without
     ever pinning `semantic.NewGatesFromMap(...)` to force the gate off. Before `b86a` this didn't
     matter (env unset → gate off → legacy path, which is what their `sqlmock` expectations are
     written against). After `b86a`, the same unset env now means gate **on**, so `processMetric`
     takes the early-return branch at `associate_semantics.go:360` straight into
     `a.writeMetricLossless(...)` — a completely different code path issuing different SQL — and
     every one of these tests fails on an unexpected-query mismatch (see exact error text in §6).
   - The code's own comment at `associate_semantics.go:354-359` says the legacy branch below the
     gate check is kept "untouched when the gate is off (the default), which is what every
     existing gate-off test depends on" — a comment that is now literally false, since the gate is
     no longer off by default, yet nothing was updated to keep that promise (either by pinning
     these tests to force gate-off, since they are deliberately testing legacy-only behavior, or
     by rewriting them against the new path).
   - This session traced far enough to find that DR12's `resolveMetricMappingState` in
     `metric_lossless_writer.go` **does** have an analogous disposition for the `"proposed"` case
     (`MappingUnresolved` state + `FindingMappingUnresolved` finding, rather than the old world's
     `Run`-level `MappingMiss` counter/aggregate error) — so this is **plausibly a legitimate,
     intentional redesign that the tests simply never got updated for**, not necessarily a lost
     invariant. But this was not confirmed end-to-end (no read of `metric_lossless_writer_test.go`
     to check whether an equivalent case is already covered there, and no live/integration check
     that a `"proposed"`-tagged metric candidate run through the gate-on path today actually
     produces the finding DR12 promises). Treat as **unverified, not as "probably fine."**
4. **`kb.ontology_terms_current` is now load-bearing for both writes and reads on the same
   invariant, and until this session's `releases_store.go` fix it could disagree with itself.**
   `termExists` (`associate_semantics.go:232`, used by both the legacy and now-default DR5 path)
   reads `kb.ontology_terms.status = 'included_in_release'` directly — a different source than the
   `_current` view several other tests/queries use (per finding in `2026081903`'s own predecessor
   about `ontology/seed`'s test failures reading `_current`). The new `syncTaggedTermRevisions`
   fix in `b86a` narrows but does not eliminate this two-sources-of-truth shape; worth a future
   session's attention if more `_current` vs. legacy-table drift surfaces.
5. **`server/tmp` is committed junk, not a real artifact.** Its entire content is the single line
   `vi api/ontology/assertions/metric_lossless_writer.go api/ontology/assertions/associate_semantics.go api/ontology/semantic/gates_test.go api/ontology/semantic/gates.go cmd/metric-writer-readiness/main.go`
   — almost certainly a shell scrollback artifact (someone's `vi <tab-completed file list>`
   invocation) accidentally left as an untracked file and swept into `b86a`'s `jj describe` along
   with everything else. Harmless but should be deleted in a future commit; not deleted this
   session since this session made no code changes at all (see §5).
6. **This session's own housekeeping.** Investigating the regression required temporarily moving
   the working copy off `b86a` (`jj new uxvs`) and back (`jj new b86a`), which — because `jj new`
   from a non-head revision creates a new child rather than reusing the existing head — produced
   several short-lived divergent empty commits (`vstn`, `uszs`, `tzmy`, `pptv`, `nxyq`, ...). Each
   was `jj abandon`ed immediately after use. Final state: `jj status` reports "no changes" and `jj
   log` shows a single head (an empty, undescribed working-copy commit) directly on top of `b86a`,
   identical in shape to the state this session found at the start. Confirmed via `jj log -n 5` and
   `jj status` before writing this handoff.

## 5. What was deliberately NOT built

- **Did not fix the 3 broken `ontology/assertions` tests.** Root cause is understood (§4 item 3)
  but the correct fix depends on a design decision (rewrite against the new default path vs.
  explicitly pin these specific tests to gate-off to keep testing legacy behavior on purpose) that
  this session judged should not be made silently while only asked to write a handoff.
- **Did not touch ADR `2026081801`** to reflect that its Phase 3 gate now defaults on in code (task
  8.4 remains open) — flagging only.
- **Did not delete `server/tmp`** — mentioned per this workspace's "notice dead code, don't delete
  it" convention, especially since this session made zero code changes.
- **Did not reprocess any more of the corpus.** The user was asked explicitly (`AskUserQuestion`)
  whether to spend LLM budget reprocessing a second document now that the gate defaults on, and
  chose to hold off. `kb.metrics` remains exactly as `2026081903` left it: 60 rows, all doc 416.
- **Did not investigate the `kb.metrics` reduction-to-60-rows question** (`2026081903 §9.2`) — the
  user chose to prioritize this handoff over that investigation this session; still open.
- **Did not re-verify task 5.8's blocking analysis** (`2026081903 §9.3`) — same reason, still open.
- **Did not start Phase 4 (7.1–7.7) or Phase 8 (8.1–8.4)** — unchanged from `2026081903`.
- **Did not investigate the pre-existing, `b86a`-unrelated test failures** in `kbhandler`,
  `ontology/names`, `ontology/keywords`, `ontology/seed` beyond confirming they predate `b86a`.

## 6. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb

# Confirm the commit graph matches this handoff's account
jj log -n 6

# Confirm the working tree is clean
jj status

# See exactly what b86a changed
jj diff -r b86a --git --stat

# Reproduce the gate default flip
grep -n "GateMetricLosslessWrites" server/api/ontology/semantic/gates.go

# Reproduce the 3 broken tests (expect all 3 to fail)
cd server && go test ./api/ontology/assertions/... \
  -run 'TestRunFailsWhenCandidateBlockedOnProposedValueRangeType|TestRunSucceedsWhenCandidateDeferredForAmbiguousValueRangeType|TestProcessMetricAcceptedPathPopulatesEvidenceProvenanceFields' \
  -v

# Confirm every OTHER failing package fails identically with or without b86a
# (swap `xxkt`/b86a for the revision your `jj log` shows if change IDs differ)
jj new uxvs -m ""   # temporary
go test ./api/kbhandler/... ./api/ontology/names/... ./api/ontology/keywords/... ./api/ontology/seed/... 2>&1 | grep -E "^(--- FAIL|FAIL|ok)"
cd .. && jj log -n 1   # note the empty commit's change id, then:
jj abandon <that-change-id>
jj new b86a -m ""   # return to tip; abandon this empty commit too when done exploring
```

## 7. Traps for the next session

- **`LOSSLESS_SEMANTIC_WRITES_METRIC` now defaults ON in code, not just via local `mise.local.toml`.**
  Any ad-hoc script or test that assumes the gate is off unless explicitly set (a documented trap
  from `2026081903 §7` for *scripts*) must now assume the opposite for anything running against
  this commit or later. The inverse trap from `2026081903` still applies too: always export the
  gate explicitly rather than relying on any default, in either direction.
- **`ontology/assertions`'s test suite is currently red** (3 tests) and must not be treated as a
  pre-existing/ignorable failure — it's a direct, traced consequence of the gate default flip and
  needs a real decision (§4 item 3), not a blind mock-patch.
- **ADR `2026081801` is now stale**: it still documents both gates as default-off. Task 8.4 exists
  precisely for this moment and is still unchecked.
- **`b86a`'s commit message ("doc process and ontology bug fixes") undersells its content.** Don't
  assume from the message that this was a routine cleanup commit — it contains the actual Phase 3
  writer-gate cutover. Read the diff (§3 item 2 / §6) before building on top of it.
- **`server/tmp` is tracked garbage**, not a real file with meaning — don't try to interpret it.
- All traps from `2026081903` and its predecessors not specifically superseded here still apply:
  `kb.metrics` still reflects only doc 416 (60 rows); DR7 LLM auto-resolution is on but not
  exhaustive; `jj split` hangs non-interactively (use `jj commit <paths> -m`); `git
  status`/`git diff HEAD` are unreliable in these colocated jj repos; editing files under
  `server/cmd/` or `project_migrations/` triggers `air` to rebuild and auto-apply migrations.

## 8. KnowledgeStore working-tree state

This handoff document is the only new file this session adds to `doc-repo/`.

## 9. Where to resume

1. **Decide and fix the `ontology/assertions` regression** (§4 item 3) — either rewrite
   `TestRunFailsWhenCandidateBlockedOnProposedValueRangeType`,
   `TestRunSucceedsWhenCandidateDeferredForAmbiguousValueRangeType`, and
   `TestProcessMetricAcceptedPathPopulatesEvidenceProvenanceFields` against the now-default DR5
   path (checking `metric_lossless_writer_test.go` first for whether an equivalent case is already
   covered there), or explicitly pin them to `NewGatesFromMap` with the gate forced off if they're
   meant to keep proving legacy-path behavior on purpose. This should happen before anyone trusts
   `go test ./...` as green for this package again.
2. **Update ADR `2026081801`** to reflect the actual current gate defaults, and consider whether
   task 8.4 should now be checked (or whether cutover isn't "complete" enough for that yet, given
   finding 3 is still open).
3. **Delete `server/tmp`** in whatever commit next touches that area.
4. Every item `2026081903 §9` listed as unresolved and this session didn't touch remains open in
   the same order it left them: confirm the `kb.metrics` 60-row reduction was intentional (§9.2 →
   this doc's item), re-verify task 5.8 (§9.3), decide on reprocessing more of the corpus now that
   the gate is default-on (§9.4 — the user held off this session), and Phase 4/Phase 8 (§9.5).
