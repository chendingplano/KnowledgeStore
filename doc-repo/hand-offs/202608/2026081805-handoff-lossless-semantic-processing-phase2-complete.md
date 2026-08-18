# Lossless Semantic Processing (ADR `2026081801`) — Phase 2 Complete: Session Handoff

Date: 2026-08-18

## 1. State in one paragraph

ADR `2026081801` Phase 2 is **complete except task 5.8, which is genuinely blocked, not
undone**. Tasks 5.1–5.7 and 5.9 are done and committed. 5.8 ("retrain dashboards and
alerts to stop reading semantic findings as failures") has no live signal to retrain
against yet — every dashboard reads the legacy `proc_status` column, still written
exclusively by the unchanged `associate_semantics.go` writer, and fixing that is Phase 3
task 6.6, deliberately deferred past Phase 2. The separate `canonical-metric-class-foundations`
change (ADR `2026081701`) that Phase 3 depends on was archived earlier the same day in
ChenWeb commit `cae1a23f2756` — see its own handoff, `2026081804`. With this session's
work, **Phase 3's stated prerequisite (Phase 2 reader certification) is now satisfied**,
though certification is currently a process gate a human reads, not one
`AuthorizeWriterActivation` checks in code. No writer gate was enabled; both
`LOSSLESS_SEMANTIC_WRITES_METRIC` and `LOSSLESS_SEMANTIC_FALLBACK_WRITES` remain off.

## 2. Document lineage (read in this order if picking this up cold)

1. **This handoff's predecessor** — `hand-offs/202608/2026081803-handoff-lossless-semantic-processing-phase0-phase1.md`.
   Phase 0/1 state as of this morning; §9 of that doc was the resume point this session
   started from.
2. **ADR `2026081801`** — `adrs/202608/2026081801-adr-lossless-semantic-processing-and-knowledge-preservation.md`.
   The decision. DR1–DR13. **Note:** this file currently has local uncommitted edits in
   the KnowledgeStore working tree, from a source outside this session — see §8.
3. **OpenSpec change** — `ChenWeb/openspec/changes/lossless-semantic-processing/`.
   `tasks.md` now shows 51/72 checked. Two new artifacts this session:
   - `consumer-lifecycle-policy.md` — task 5.1's audit, extended this session with rows
     for retry tooling, observed class profiles, completeness, and a documented-blocked
     section for 5.8.
   - `reader-compatibility-certification.md` — **new this session**, task 5.7's
     certification record. Read this before touching Phase 3 activation (task 6.9); it
     names every consumer, its proof, and three real test gaps that were found and closed.
4. **Sibling handoff** — `hand-offs/202608/2026081804-handoff-canonical-metric-class-foundations-phase3-activation.md`.
   The other ADR's Phase 3 activation handoff, written earlier the same day. Its "Writer-gate
   handoff point" section names `lossless-semantic-processing` Phase 3 as the next owner —
   read it before starting Phase 3 here.
5. **ADR `2026081401`** — governed metric vocabulary. Unchanged this session; still
   authoritative for everything except the DR3/DR6 mapping-miss failure behavior DR12
   supersedes (task 6.6's eventual target).

## 3. What was built this session

All in ChenWeb, jj changes `0de23f5b` through `89be94ac` (five commits, each one Phase 2
task), on top of `f6678780` (this morning's document-scoped diagnostics slice) and
`cae1a23f` (this morning's canonical-foundations archive):

| Commit | Task | Summary |
|---|---|---|
| `0de23f5b` | 5.5 | Review Document "Semantic Diagnostics" tab (`doc-review-semantic-view.svelte`): raw/normalized value, all four independent states, processing errors, class confidence, active evidence, for every lifecycle status. Fixed a `Page`/`PageSize`-sharing-one-`json:"page"`-tag bug in `semantic_assertions_handler.go` that silently dropped both fields from every response. |
| `28a1d065` | 5.2 | Added `RetryQueue.List` (`server/api/ontology/semantic/retry.go`) — the queue had no reader at all before this. Wired through `GET /kb/semantic-retry-queue` and a read-only admin page (Sysadmin → Doc Process → Semantic Retry Queue). Documented why "semantic projection" and "reports" needed no new code (already accepted-only-audited / already dual-read by construction). Fixed the same json-tag bug in two more handlers (`assertion_evidence_handler.go`, `semantic_decision_candidates_handler.go`), found by `go vet` once the first instance was fixed. |
| `b91033e4` | 5.6 | Documentation only. All three sub-requirements (search raw+normalized indexing, observed-profile outliers without promotion, completeness distinguishing absent-vs-missing-value) turned out already satisfied — two of them by `classfoundation.ObservedProfileStore`/`completeness.go`, built for the *other* ADR and never previously credited against this one. |
| `b3b3b3c2` | 5.7 | `reader-compatibility-certification.md`. Found and closed three real test gaps: `HighestAcceptedAssertionID`'s tests matched only a SQL prefix, not the accepted-only WHERE clause; `keywords.AcceptedForConcept`'s test mocked against the same source constant it was meant to be checking; `classification_projection.go` had zero tests. Confirmed assertion redirects have no Phase 2 consumer yet (only the shadow-mode metric foundation comparison uses them). |
| `89be94ac` | 5.8/5.9 | 5.8 documented as blocked (see §1), left unchecked. 5.9 confirmed already correctly implemented in Phase 1 (`Gates.enabled` default-off, `AuthorizeWriterActivation`'s refusal paths) and now backed by 5.7's certification; documented the process-gate caveat. |

## 4. Findings not written down anywhere else

1. **The `Page`/`PageSize` JSON tag bug was real and repo-wide, not hypothetical.**
   `type X struct { Page, PageSize int \`json:"page"\` }` — Go's `encoding/json` treats
   both fields as having the identical tag and drops **both** from every response
   (verified with a standalone repro). Found in three handlers this session
   (`semantic_assertions_handler.go`, `assertion_evidence_handler.go`,
   `semantic_decision_candidates_handler.go`), all now fixed. `go vet ./...` catches this
   class of bug; it was not being run as part of this repo's usual test loop before now
   — worth adding to whatever pre-commit/CI check exists.
2. **`ObservedProfileStore` (the *other* ADR's infrastructure) has zero production
   callers.** `grep -rn "ObservedProfileStore{" server/` outside tests returns nothing.
   The schema/store/reader contract is sound and certified, but nothing populates it
   with real metric data yet. Wiring it into the live pipeline is Phase 3/4 writer-shaped
   work, not a Phase 2 reader task — flagged in `consumer-lifecycle-policy.md` so it
   isn't mistaken for "already working."
3. **Reader certification is a process gate, not a code gate, today.**
   `AuthorizeWriterActivation` checks the environment-variable gate and DR13 adapter
   conformance (`kb.semantic_adapter_compliance`); it has no field or check tied to
   `reader-compatibility-certification.md`. Whoever implements Phase 3 task 6.9 should
   decide whether to formalize this (e.g., a certification-version field checked the same
   way `ConformanceSuiteVersion` is) or keep it a documented human gate.
4. **`search_registry_test.go` and several other kbhandler tests fail in this dev
   environment for reasons unrelated to this ADR** (`arguments do not match: expected 13,
   but got 14`, and similar column-count drift) — confirmed pre-existing via `jj diff`
   (files this session never touched). Same root shape as a stale-column-count issue
   surfaced in `keywords/alignment_test.go`'s `TestAlignmentsStoreEnsureAccepted`. These
   look like fallout from the concurrent canonical-metric-class-foundations work that
   landed the same day (`cae1a23f` and its ~40 ancestor commits) — worth a dedicated pass,
   but out of scope for both ADRs' Phase 2 work.

## 5. What was deliberately NOT built

- **Task 5.8** — see §1. Not a scope choice; there is nothing to retrain against until
  Phase 3 task 6.6 changes the writer.
- **Phase 3** (tasks 6.1–6.12, the metric lossless writer activation) — not started. Its
  stated blocker (Phase 2 certification) is now resolved, but Phase 3 is a materially
  larger and riskier undertaking (the actual writer cutover) and was explicitly held back
  as a separate decision point this session, not attempted opportunistically.
- **No new machine-checked link between `reader-compatibility-certification.md` and
  `AuthorizeWriterActivation`.** Noted as an open question for Phase 3, not resolved.
- **Phases 4+** — untouched, as before.

## 6. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb

# Build + vet the whole workspace
go build ./... && go vet ./...

# Everything touched this session
go test ./server/api/ontology/assertions/... ./server/api/ontology/keywords/... \
        ./server/api/kbhandler/... -run \
        "SemanticAssertion|SemanticRetryQueue|Evidence|DecisionCandidate|HighestAccepted|ListBySubjectObject|PrimaryClassificationFor|AcceptedForConceptSQL"

# Retry queue integration test (needs a live Postgres; creates/drops its own scratch DB)
TEST_DATABASE_URL='host=127.0.0.1 user=cding dbname=postgres sslmode=disable' \
    go test ./server/api/ontology/semantic/ -run TestIntegrationRetryQueueListFiltersAndJoinsOutcomeContext -v

# Frontend: new/changed files
cd web
bun test src/lib/components/home3/semantic-diagnostics-labels.test.ts
bun run build   # full production build
bun run check   # svelte-check; 1 pre-existing error + 16 warnings, none in files this session touched
```

**Known pre-existing failures, unrelated to this session** (all confirmed via `jj diff`
showing no session changes to the files involved): the two named in the phase0/1 handoff
(`ontology/keywords` `TestResolverModeFromUnsetIsOff`, `cmd/qudt-import` TTL parsing),
plus a wider set surfaced this session in `kbhandler` (search registry, ontology
candidate/comparison cell persistence, summary/topic category handlers) and in
`keywords` (`TestAlignmentsStoreEnsureAccepted` and three siblings) — see §4 item 4.
Do not chase these as regressions from this change.

## 7. Traps for the next session

- **Don't restart the ChenWeb `air` dev server against the `miner` database without
  running Phase 3 task 6.2 first.** A second `air` instance started mid-session to verify
  the Review Document tab live crashed on migration `20260818000018`
  (`uq_assertion_evidence_current_metric_support`): 17 metric occurrences already carry
  duplicate current supporting links (Phase 0 finding #2 from the phase0/1 handoff). This
  is not new information, but it is now confirmed to actually block a fresh migration run
  against `miner` today, not just a theoretical future problem. The pre-existing `air`
  process from Sunday is still up but was never observed to be genuinely serving `:8080`
  during this session either.
- **A "golden query-text" sqlmock test only protects if the expected string is typed
  independently of the source.** Three examples this session
  (`reader-compatibility-certification.md` "Gaps closed") where a test referenced the same
  `const` the production code uses, or matched only a prefix — both patterns silently stop
  protecting anything the moment the underlying literal changes, because the test's
  expectation changes right along with the bug. Worth a lint/convention note if this
  pattern shows up again.
- **`go vet ./...` is not part of the usual loop here** and caught a real, silent,
  repo-wide correctness bug (§4 item 1) that unit tests alone did not, because the broken
  responses still returned `200 OK` with valid (just incomplete) JSON. Worth running it
  proactively on any handler-shaped change.

## 8. KnowledgeStore working-tree state — needs your attention, not touched by this session

At the time this handoff was written, `KnowledgeStore`'s jj working copy had two
**unrelated, pre-existing uncommitted changes** this session did not make and did not
commit:

- `doc-repo/adrs/202608/2026081801-adr-lossless-semantic-processing-and-knowledge-preservation.md`
  — modified. The sibling handoff `2026081804` already flagged this exact file as having
  "local uncommitted edits outside this change; review and commit them independently."
  Still true; still not this session's to resolve.
- `doc-repo/diary/202608/20260818-diary.md` — modified. This looks like your own active
  diary entry (you had it open in the editor while this session ran). Not touched.

This handoff file itself was added on top of that same dirty working copy and was
**deliberately left uncommitted** rather than bundling it in with those two unrelated
files. Commit it (and decide what to do with the other two) at your convenience.

## 9. Where to resume

Phase 2 is done modulo 5.8's documented block. The next real decision is whether to start
Phase 3 (tasks 6.1–6.12). Before doing so:

1. Read `reader-compatibility-certification.md` in full — it is the artifact task 6.9
   gates on.
2. Read the sibling handoff `2026081804` — its "Writer-gate handoff point" and "Open
   policy choices" sections are directly relevant to sequencing Phase 3 here.
3. Task 6.2 (duplicate current-metric-support link backfill) should probably run first
   regardless of anything else, since it now demonstrably blocks even a routine migration
   apply against `miner` (§7).
4. Task 6.6 (removing `associate_semantics.Run`'s aggregate mapping-miss error) is what
   would actually unblock task 5.8 retroactively, if that's ever worth reopening as a
   Phase 2 loose end.

Open questions carried forward unresolved (ADR §10, restated in the OpenSpec design.md):
raw-fragment retention/compaction; default Review Document severity filters; the first
non-metric family to migrate; and, new from this session, whether reader certification
should become a machine-checked precondition of `AuthorizeWriterActivation`.
