# SemOS P4 Implementation Review — Completeness, Correctness, Tests

**Date:** 2026-08-01
**Status:** Review record. Supersedes the "generic runtime built" framing in the P4 foundation
checkpoint (`2026080104-devdoc-semos-p4-foundation-checkpoint.md`) for the items below; that
checkpoint's schema/migration claims stand.

**Scope reviewed:** migrations `20260801000007`–`20260801000011`; `ChenWeb/server/api/ontology/profiles/`;
`ChenWeb/server/api/ontology/comparison/`; the module-compiler snapshot/release changes in
`ChenWeb/server/api/ontology/modules/`; the five P4 `kbhandler` endpoints; the four ADR §8.2 Chunk-F
processors under `ChenWeb/server/api/doc-processing/`. `go test ./server/api/ontology/... -count=1`
passes as of this review.

## Summary

The persistence layer (schema, governed-content lifecycle, module-release tagging) is sound. The
review and comparison **runtime** built on top of it is largely a shell: the two evaluators that are
supposed to be the point of P4 (`required_assertion_pattern` native evaluation, `EvaluateDirectionalCell`)
are not actually invoked by the production code paths that persist findings and cells. Four concrete
bugs will surface immediately against the real (Chinese-language) pilot corpus.

## 1. Completeness

**The review runtime does not consume its own frozen scope.** `ReviewService.EvaluatePinnedScope`
(`ChenWeb/server/api/ontology/profiles/review_service.go:26`) takes `assertions []ReviewAssertion` as
a parameter, and `ExecuteOntologyReviewScope`
(`ChenWeb/server/api/kbhandler/ontology_review_scopes_handler.go:42`) fills it straight from the HTTP
request body. Nothing loads assertions from `kb.semantic_assertions`; nothing checks they belong to
the scope's `reviewed_document_ids` / `target_object_ids`, or that `status='accepted'` is real.
`ReviewAssertion.SubjectObjectID` is declared and never read, so rules do not scope to review targets
either. Consequences:

- The scope is not reproducible — the same scope id with a different request body produces different
  findings. Chunk C's stated acceptance ("historical scopes reproduce after activation changes") is
  not demonstrated by any test; the scope-pinning test passes `nil` assertions.
- The audit trail is client-forgeable: a caller can POST invented `accepted` assertions and get
  `satisfied` findings persisted into `kb.doc_review_findings` carrying a real scope/rule id.
- Review scopes carry no assertion watermark, unlike `kb.ontology_comparison_runs`, which does. That
  asymmetry looks like an oversight rather than a decision.

**Applicability and precedence are dead fields.** `Profile.Applicability`, `ProfileRule.Applicability`,
and `ReviewScope.PrecedencePolicy` / `ComparisonScope.PrecedencePolicy` are stored, scanned, and never
evaluated anywhere. CQ-R01 (which profile applies to a document, and why — full applicability trace)
is not implemented, and Chunk C's `profile_rule_conflict` → indeterminate acceptance criterion has zero
matches in the codebase.

**Two of the six §12.4 result categories are unreachable.** `ResultConflicting` and `ResultInapplicable`
(`rule_registry.go:16-18`) are never returned by any code path. `NonconformingIDs` is declared and never
populated or read. 4 of 6 declared result categories are implemented.

**Profiles and rules can never reach version 2.** Both `ProfileStore.CreateProfile`
(`profiles_store.go:98`) and `ProfileRuleStore.CreateProfileRule` (`profile_rules_store.go:100`)
hardcode `VALUES ($1, 1, ...)`. There is no `CreateProfileVersion` analogous to
`terms.TermStore.CreateTermVersion`, and no route for one. `UNIQUE (profile_id, version)` then blocks
re-creation. "Versioned governed content" is single-version-only today — a released profile is
permanently frozen with no revision path.

**Neither evaluator is wired to production.** `EvaluateDirectionalCell`
(`ChenWeb/server/api/ontology/comparison/evaluate_cell.go:31`) is called only from its own test.
`CreateOntologyComparisonCell` (`ChenWeb/server/api/kbhandler/ontology_comparison_cells_handler.go:15`)
accepts the verdict and rationale **from the client request body** and persists them directly. DR22's
"comparison runtime" is currently a table plus an unused pure function. Likewise, `EmitSHACL` is
required at rule-kind registration (to guarantee P7 parity) but is never invoked anywhere outside its
own test — no endpoint, no caller, no parity gate.

**Missing:** no `p4_exit_test.go`, unlike the precedent set by `candidates/p2_exit_test.go` and
`assertions/p3_exit_test.go`. The generic §16.4.4–12 acceptance criteria are behavioral, not pilot
data, so nothing about the authority-confirmation gate should have blocked writing them.

## 2. Correctness

Ranked by likelihood of surfacing against the real pilot corpus.

**a. `candidateIdentifier` silently destroys non-ASCII (Chinese) names.**
`ChenWeb/server/api/doc-processing/ontology_candidate_harvest.go:263` accepts a rune only if
`unicode.IsLetter(r) && r <= unicode.MaxASCII`; non-ASCII letters hit `continue` without even emitting
a separator. `"触摸响应时间"` → empty string → falls back to `measurement:term_<8 hex>`; `"A触摸B"` →
`"ab"`, silently colliding with a term literally named `"AB"`. The P3 implementation log already
recorded that this corpus's provision/metric text is predominantly Chinese. Every
`extract_test_methods` and `extract_metric_definitions` candidate against the real pilot will get an
opaque hash id or a false collision.

**b. Product-structure candidates always lose their line spans.**
`ChenWeb/server/api/doc-processing/product_structure_harvest.go:40-41` does
`json.Unmarshal(spans, &lines)` into `[]int`, but `kb.relations.line_spans` is persisted as a JSON
array of **strings** (`relationSpansFromEndpoints` → `sortedUniqueSpans` → `[]string`, marshalled at
`extract-entity-relation.go:1855`). The unmarshal error is discarded with `_ =`, so `SourceLineSpans`
is empty for every real candidate — contradicting the "evidence-bearing… with source provenance"
requirement. The unit test masks this because its sqlmock fixture returns `[51]` (numbers), not the
production `["51"]` (strings).

**c. Phase C race between product-structure harvesting and entity reconciliation.**
`runPostProcessIndexing` (`ChenWeb/server/api/doc-processing/control.go:885`) runs every
`PostProcessIndexer` concurrently, one goroutine per processor, with no ordering guarantee.
`ProductStructureProcessor.PostProcessIndex` inner-joins `kb.artifact_objects` for
`artifact_type='entity'`, which is written by `ReconcileEntityObjectsForRecord`, itself called from
`EntityRelationProcessor.PostProcessIndex` (`artifact_postprocess_indexing.go:268`) — a sibling
goroutine, not an upstream dependency. The P4 checkpoint states product structure "runs after
entity-object reconciliation and relation endpoint linking"; nothing in the scheduler enforces that.
Losing the race silently yields zero harvested candidates, non-deterministically per run.

**d. The SHACL emitter is wrong for `none_matching`.**
`rule_required_assertion_pattern.go:90` special-cases only `exists_conforming` (`min := 1` when
`cfg.Minimum == 0`). A `none_matching` (prohibition) rule with the default `Minimum: 0` emits
`sh:minCount 0` and no `sh:maxCount` — a shape that permits *any* count, the exact inverse of what the
native evaluator does (which flags nonconforming when even one match exists). The emitted shape also
omits `dimension`, `assertion_kind_term_id`, and `quantity_kind_term_id` entirely, so SQL/Go-vs-SHACL
parity would fail for every rule that constrains on those fields. `RegisterRuleKind` requires an
emitter specifically to prevent this drift, and the one built-in emitter doesn't satisfy it.

**e. Released rule content is never reference-validated.**
`validateAndBuildSnapshot` (`ChenWeb/server/api/ontology/modules/validate.go:172`) runs the
dangling-reference guard over axioms and mappings only. A rule's `rule_config` fields
(`predicate_term_id`, `assertion_kind_term_id`, `quantity_kind_term_id`) get no such check at release
time, and `rule_kind` registration is checked only at `CreateProfileRule` time. A released rule can
reference a nonexistent term and will emit `missing` findings forever, or carry a config that errors at
evaluation time — and since `ReviewService.EvaluateAndPersist` returns on the first evaluator error, one
bad rule aborts the entire scope run and persists nothing for the rest.

**f. `all_conforming` behaves identically to `exists_conforming`.**
`rule_required_assertion_pattern.go:68` treats both quantifiers the same way: one matching assertion is
enough to return `satisfied`, regardless of whether *other* matching assertions conflict.
`NumericValue`/`UnitTermID` are collected on `ReviewAssertion` but never compared against anything, so
there is no actual conformance check anywhere in the evaluator — only presence/absence and cardinality.

**g. An unrecognized quantifier silently produces `missing` instead of an error.**
With zero matches, the empty-match branch (`rule_required_assertion_pattern.go:52`) runs before the
`default:` error case is ever reached. A misspelled or unsupported `quantifier` value in `rule_config`
produces an authoritative `missing` finding in a closed dimension rather than a configuration error.

**h. Review execution is non-idempotent and non-transactional.** No run row exists for review
executions (unlike comparison runs), no uniqueness constraint on `(review_scope_id, profile_rule_id,
run_id)`, and no transaction wraps `EvaluateAndPersist`. Re-POSTing `/execute` duplicates every finding;
a mid-run error leaves a partially-reviewed scope with no marker that it's incomplete. `run_id` is
client-supplied with no FK to any run table.

**i. `processor_plan.go:309` misdescribes `extract_product_structure`.** It's registered as
`Phase: "B", DependsOn: ["chunking"], Class: "routed", Cost: "cheap_llm"`, but the actual implementation
is a Phase-C, no-LLM post-processor that depends on relation extraction and entity-object
reconciliation. Currently inert (the DR5 stage-DAG planner that would read this isn't built yet), but
wrong once it is.

**Minor:**
- `ProfileStore.TransitionStatus` / `ProfileRuleStore.TransitionStatus` are non-transactional
  read-then-write (TOCTOU window between the status check and the `UPDATE`).
- `RegisterRuleKind` silently replaces an existing registration for the same kind string with no
  warning or error.
- `ProductStructureProcessor.HandleEvent` returns `nil` unconditionally where the sibling
  `TestMethodsProcessor.HandleEvent` correctly errors ("requires chunk batching") — an inconsistent
  contract across processors that both claim to require batching/post-processing only.
- No DB-level enforcement (trigger, or absence of any UPDATE grant) backs the "immutable" claim on
  `kb.ontology_review_scopes` / `kb.ontology_comparison_scopes` — immutability currently just means "no
  Go method exists to update it."

## 3. Tests

The unit tests are honest about shape and misleading about behavior.

- **The two headline "excludes draft" tests don't test exclusion.** `TestActiveProfilesExcludeDraft`
  and `TestActiveProfileRulesExcludeDraft` are sqlmock tests that stub one canned
  `included_in_release` row for the query and assert the code parses that row correctly. Nothing
  verifies the `WHERE status = 'included_in_release'` clause or the release-activation join actually
  filters anything — deleting either from the real SQL would leave both tests green. The checkpoint's
  claim that "focused red-green tests cover draft exclusion from active profile/rule reads" is not
  supported by what these tests actually exercise.
- **Evaluator coverage is 1 of 4 quantifiers.** Only `exists_conforming` has a behavioral test.
  `all_conforming`, `none_matching`, and `count_conforming` have no evaluator test at all — which is
  exactly why (d), (f), and (g) above went uncaught. The SHACL emitter test covers only
  `count_conforming`, the one quantifier the emitter actually handles correctly.
- **Fixtures are shaped to match the code, not the database.** The product-structure sqlmock row uses
  `[51]` (numeric JSON array); production data is `["51"]` (string JSON array) per (b) above. This is
  the same failure mode the P1/P2/P3 implementation logs each independently record ("real, load-bearing
  gaps that sqlmock-only or synthetic-fixture-only testing structurally cannot catch") — reintroduced
  here rather than avoided.
- **No test exists for:** a draft/non-released rule reaching the evaluator through any production path;
  review-scope immutability; a malformed `rule_config` at evaluation time; duplicate `/execute` calls;
  or `EvaluateAndPersist` dropping every assertion ID but `AssertionIDs[0]` when persisting a finding.
- **No live-Postgres proof exists for the load-bearing path.** The P4 checkpoint states explicitly that
  "a live Go-store/release transaction proof is still pending" — the store→release→activate→active-
  visibility chain, the central claim of Chunk A, has never been run end-to-end against real Postgres.
  Every prior phase (P1, P2, P3) found real, previously-invisible bugs at exactly this step.

## Recommendation / next steps

The schema and governance/lifecycle model are worth keeping as-is. What needs to stop being described
as "built" is the runtime layer on top of it. Two changes are load-bearing before P4's generic layer can
be re-claimed:

1. Move assertion selection **inside** scope execution: load from `kb.semantic_assertions` filtered by
   the scope's documents/targets/as-of date, record an assertion watermark on the scope (mirroring
   `kb.ontology_comparison_runs`), and drop the client-supplied `assertions` field from the execute
   request body entirely.
2. Perform the deferred live Go-store/release transaction validation, after first fixing (a) `candidateIdentifier`
   non-ASCII handling, (b) the `line_spans` string/int mismatch, and (c) the Phase-C ordering race —
   all three will otherwise surface immediately once that validation runs against real Chinese-language
   pilot data.

Then close (d) the SHACL emitter and (e) release-time rule reference validation, and add evaluator tests
for `all_conforming`, `none_matching`, and `count_conforming` before describing any of them as
implemented.

## Addendum (2026-08-01, same day — fixes (a)/(b)/(c) landed)

Three of the correctness findings above are fixed in `ChenWeb` (uncommitted, pending user review):

- **(a) `candidateIdentifier` non-ASCII handling** — `ontology_candidate_harvest.go`'s slug builder now
  retains CJK runes (U+4E00–U+9FFF), matching the existing precedent in
  `slugifyClusterLabel` (`chunk_summary_shared.go:912`), instead of silently dropping every non-ASCII
  letter and falling back to an opaque `term_<hash>` id or colliding across different Chinese labels.
  Tests: `TestCandidateIdentifierPreservesCJKRunes`, `TestCandidateIdentifierDistinguishesMixedScriptLabels`.
- **(b) `line_spans` string/int mismatch** — `HarvestProductStructureFromRelations`
  (`product_structure_harvest.go`) now unmarshals `kb.relations.line_spans` as `[]string` (its real
  stored type) and expands each entry through the existing `parseLineSpanRange` helper (already used
  elsewhere for the same "N" / "N-M" / "N:M" span grammar), instead of unmarshalling into `[]int` and
  discarding the resulting error. Every product-structure candidate now carries real source line spans.
  Tests: `TestHarvestProductStructureFromRelationsUsesReconciledEndpoints` (fixture corrected from
  `[51]` to `["51"]` to match production), `TestLineNumbersFromSpanStringsExpandsRanges`.
- **(c) Phase C ordering race** — added a new, generic `PostProcessDependent` interface
  (`control.go`) that lets a Phase C processor declare `PostProcessDependsOn() []string`; the Phase C
  scheduler (`runPostProcessIndexing`) now gives every invoked indexer a completion channel and makes
  dependents wait on named dependencies (only those actually invoked in the current run) before
  starting, while still running independent processors concurrently. `ProductStructureProcessor` now
  declares `PostProcessDependsOn() -> ["extract_entity_relation"]`, closing the race against
  `EntityRelationProcessor`'s entity-object reconciliation step. Tests (race-clean):
  `TestRunPostProcessIndexingRunsDependentAfterItsDependency`,
  `TestRunPostProcessIndexingSkipsAbsentDependencyWithoutHanging`.

Verification: `go build ./server/...`, `go vet ./server/api/doc-processing/... ./server/api/ontology/...`,
and `go test ./server/api/doc-processing/... ./server/api/ontology/... -count=1` (plus a `-race` pass
on the new/changed tests) — no regressions against the pre-existing baseline (21 unrelated failures in
`doc-processing`, all environment/config-dependent, e.g. missing `SHARED_LIB_CONFIG_DIR`, and present
identically before this change).

**Remaining from the findings above, not yet started:** (d) SHACL emitter correctness for
`none_matching`, (e) release-time reference validation for `rule_config` term ids, evaluator tests for
`all_conforming`/`none_matching`/`count_conforming`, and the review-scope reproducibility fix (loading
assertions from `kb.semantic_assertions` inside scope execution instead of the request body) — the
single highest-priority item left, per the Recommendation section above.

## Addendum 2 (2026-08-01, same day — remaining findings closed)

The remaining items from the original review are now fixed (uncommitted at review time, since
committed as part of this same session's work):

- **(f)/(g) evaluator correctness** — `evaluateRequiredAssertionPattern`
  (`rule_required_assertion_pattern.go`) now validates `cfg.Quantifier` against a fixed set
  (`exists_conforming`/`all_conforming`/`none_matching`/`count_conforming`) before any matching runs,
  so an unrecognized quantifier always errors instead of silently resolving to `missing`/`indeterminate`
  when the zero-match branch happened to run first. `all_conforming` now actually differs from
  `exists_conforming`: it requires every matched assertion to agree on unit and numeric value (new
  `assertionsAgree` helper), returning the previously-unreachable `ResultConflicting` category when they
  disagree — this also makes `ReviewAssertion.NumericValue`/`UnitTermID` load-bearing instead of dead
  fields. Tests: seven new cases in `rule_required_assertion_pattern_test.go` covering all four
  quantifiers plus the unsupported-quantifier-with-and-without-matches cases.
- **(d) SHACL emitter parity** — `emitRequiredAssertionPatternSHACL` now emits
  `sh:qualifiedValueShape`/`sh:qualifiedMinCount`/`sh:qualifiedMaxCount` around a compound value shape
  (status + predicate + optional assertion-kind + optional quantity-kind), instead of a bare
  `sh:property`/`sh:minCount`/`sh:maxCount` that could only constrain a single property and, for
  `none_matching`, was emitting the literal inverse of the native evaluator (`sh:minCount 0` with no
  max, i.e. "any count is fine"). `none_matching` now emits `qualifiedMinCount 0` +
  `qualifiedMaxCount 0`. Documented, not fixed: `all_conforming`'s cross-assertion agreement check has
  no compact SHACL cardinality equivalent, so the shape still only captures its presence requirement —
  called out in the function's doc comment as the remaining parity gap for P7. Tests: rewrote the
  existing shape test for the new predicate names, added dedicated `none_matching`-inversion and
  assertion/quantity-kind-inclusion tests.
- **(e) release-time rule reference validation** — added an optional
  `ReferencedTermIDs func(ProfileRule) ([]string, error)` field to the `RuleKind` registration struct
  (`rule_registry.go`; optional so a rule kind with no term references isn't forced to implement a
  no-op), implemented it for `required_assertion_pattern`, and wired a new
  `validateProfileRuleReferences` into `ReleaseStore.validateAndBuildSnapshot`
  (`modules/validate.go`) alongside the existing axiom/mapping dangling-reference guard. A release now
  rejects a rule referencing a nonexistent governed term, and separately rejects a rule whose
  `rule_kind` isn't registered at all (a config/deployment inconsistency that would otherwise release
  an unevaluatable rule). Tests: `TestRequiredAssertionPatternReferencedTermIDs*` (extractor) and
  `TestValidateProfileRuleReferences*` (release-gate wiring, as pure-function tests mirroring the
  existing `validateDeps` test pattern — the axiom/mapping dangling-reference guard itself has no
  equivalent unit test to follow, only live validation).
- **Review-scope reproducibility (the highest-priority item)** — `ReviewService.EvaluatePinnedScope`
  (`review_service.go`) no longer takes an `assertions []ReviewAssertion` parameter. It now derives the
  assertion set itself from the scope's own pinned `target_object_ids`, via a new required
  `AssertionLoader` interface (`LoadAcceptedAssertions(ctx, objectID) ([]ReviewAssertion, error)`).
  `ExecuteOntologyReviewScope` (`kbhandler/ontology_review_scopes_handler.go`) no longer decodes an
  `assertions` field from the request body at all. Production wiring is a new
  `reviewAssertionLoader` adapter (`kbhandler/ontology_review_assertion_loader.go`) over
  `assertions.AssertionStore.ListBySubjectObject(ctx, objectID, "accepted")` — an existing store method
  that already resolves to the latest revision per logical identity key. This closes both the
  forgeability gap (a caller could previously inject arbitrary `accepted` assertions and get real
  findings persisted) and the reproducibility gap (the same scope id now always evaluates against
  governed state, not whatever a request body happened to contain).
  **Deliberately not done in this pass:** an assertion watermark column on `kb.ontology_review_scopes`
  (mirroring `kb.ontology_comparison_runs.assertion_watermark`) and `reviewed_document_ids`-based
  filtering (would require a join through `kb.assertion_evidence.input_record_id`, which P3 chunk E
  only recently started populating). Both remain real gaps — a scope's result can still drift over time
  as new assertions are accepted for the same target objects — but adding a watermark schema change was
  judged separate, deferrable scope from closing the client-forgeability hole, which was the acute
  correctness/security issue. Recorded here so it isn't lost.

Verification: `go build ./server/...`, `go vet ./server/...`, and
`go test ./server/api/ontology/... ./server/api/kbhandler/... ./server/api/doc-processing/... -count=1`
— no new failures against the baseline (`kbhandler` has 14 pre-existing unrelated failures in
search/registry/topic code; `doc-processing` has the same 21 pre-existing unrelated failures noted in
Addendum 1; both confirmed present identically on the unmodified baseline commit).

**Still open, not addressed in this session:** document-scoped filtering (join through
`kb.assertion_evidence.input_record_id`) — see Addendum 3 for the watermark piece, now closed;
`Profile`/`ProfileRule` versioning (`CreateProfile`/`CreateProfileRule` still hardcode version 1, so a
released profile cannot be revised); applicability/precedence fields remain unevaluated (dead data);
no `p4_exit_test.go`. The comparison-run watermark forgeability noted here is now closed — see
Addendum 4. Comparison **cells** (verdict/rationale) remain client-supplied and unevaluated by
`EvaluateDirectionalCell` in production — a materially larger, separate piece of work, not addressed.

## Addendum 3 (2026-08-01, same day — assertion-watermark gap closed)

Per user direction to close the "deliberately not done" gap from Addendum 2, added a real review-run
concept (the design mirrors `kb.ontology_comparison_runs`/`ComparisonStore`, per user's selected option
of three presented). Document-scoped filtering (the other half of that gap) was explicitly **not**
included — see the option comparison below for why.

- **`kb.ontology_review_runs`** (migration `20260801000012`) — `id`, `review_scope_id` (FK to
  `kb.ontology_review_scopes`), `input_record_id` (FK to `kb.inputs`, using the correct target from
  the start — the P4 checkpoint records that `kb.ontology_comparison_runs` initially pointed at the
  wrong table, `kb.input_records`, and had to be corrected after a live-validation failure),
  `assertion_watermark`, `create_time`. The scope stays reusable; each `/execute` call now creates a
  new run row pinning the assertion state at that moment, so a **historical run** (not just the scope)
  is now reproducible even as new assertions get accepted later for the same target objects.
- **`kb.doc_review_findings.review_run_id`** (migration `20260801000013`) — a new, FK-integrous column
  distinct from the pre-existing, client-supplied `run_id` (which remains untouched: it's a broader,
  cross-pass concept shared with LLM-based review findings elsewhere in `doc-reviews`, out of scope for
  this fix). `review_run_id` is ontology-specific and always server-generated.
- **`ReviewRunStore.CreateRun`** (`review_runs_store.go`) — same shape/validation pattern as
  `ComparisonStore.CreateRun`.
- **Watermark computation** — `ReviewService.EvaluatePinnedScope` (`review_service.go`) now tracks the
  highest `AssertionID` returned by `AssertionLoader.LoadAcceptedAssertions` across every target object
  in the scope, formats it as `"assertion:<id>"` (or `"none"` if nothing was loaded), and creates the
  run via a new required `Runs ReviewRunWriter` seam **before** evaluating rules — the watermark is
  computed server-side from what was actually loaded, never client-supplied. `EvaluatePinnedScope` now
  returns `([]RuleEvaluationResult, ReviewRun, error)` instead of just the results, so callers (and the
  HTTP response) can see which run produced a given set of findings.
- **Handler + read-back** — `ExecuteOntologyReviewScope` wires `Runs: profiles.ReviewRunStore{DB: db}`
  and returns the created `ReviewRun` in its response (`ontologyReviewExecutionResponse.Run`), mirroring
  how `CreateOntologyComparisonRun` returns its created record. `GetOntologyReviewFinding` now also
  reads back `review_run_id`, extending the existing provenance response (`review_scope_id`,
  `profile_rule_id`, `assertion_id`) to include which run.
- Tests: `review_runs_store_test.go` (2 cases), 3 new `ReviewService` watermark-computation tests
  (zero-assertions → `"none"`; single target → `"assertion:<id>"`; watermark tracks the **highest** id
  across multiple targets, not just the last one processed), updated `FindingStore`/handler/finding
  read-back tests for the new column and INSERT shape.

**Why document-scoped filtering was left out of this addendum, per the option comparison presented to
and selected by the user:** it would additionally join through `kb.assertion_evidence.input_record_id`
to restrict assertions to ones evidenced within `reviewed_document_ids`, not just matching
`target_object_ids`. The P3 implementation log recorded that `input_record_id` population on evidence
rows was only fixed as a chunk-E prerequisite (2026-08-01) — so older assertions/evidence predating
that fix may not join cleanly, making this a real, separate, higher-risk piece of work than the
watermark fix. Still open.

Verification: `go build ./server/...`, `go vet ./server/...`, and
`go test ./server/api/ontology/... ./server/api/kbhandler/... -race -count=1` — no new failures against
the same pre-existing baseline (14 unrelated `kbhandler` search/registry/topic failures) noted in
Addendum 2.

## Addendum 4 (2026-08-01, same day — comparison-run watermark forgeability closed)

Per user follow-up, closed the analogous forgeability gap on the comparison side flagged at the end of
Addendum 3: `CreateOntologyComparisonRun` accepted an arbitrary `assertion_watermark` string directly
from the request body with no server-side computation, the same shape as the review-run bug Addendum 3
fixed.

- **`AssertionStore.HighestAcceptedAssertionID`** (`assertions/assertions_store.go`) — new method
  returning `MAX(id)` (0 if none) among the latest-revision, `accepted` assertions for one subject
  object, via a single aggregate query rather than loading full rows. Reuses the exact
  latest-revision-per-`logical_identity_key` filtering `ListBySubjectObject` already used.
- **`comparison.ComputeAssertionWatermark`** (new file `comparison/watermark.go`) — takes a
  `ComparisonScope` and a minimal `AssertionWatermarkLoader` interface
  (`HighestAcceptedAssertionID(ctx, objectID) (int64, error)`), parses the scope's own
  `target_object_ids`, and returns `"assertion:<max id across all targets>"` or `"none"`. Same
  computation shape as the review-run watermark (Addendum 3), implemented separately in the
  `comparison` package to preserve the existing clean separation from `profiles`/`assertions` (neither
  package imports the other) rather than force a shared cross-package abstraction for ~15 lines of
  logic.
- **`CreateOntologyComparisonRun`** (`kbhandler/ontology_comparison_runs_handler.go`) — no longer
  decodes `assertion_watermark` from the request body at all (only `input_record_id` and
  `comparator_version`, which remain legitimately caller-supplied: an association tag and a
  comparator-implementation version tag, not governed state). It now loads the scope via the existing
  `ComparisonStore.GetScope`, computes the watermark server-side via `ComputeAssertionWatermark` against
  `assertions.AssertionStore` (which satisfies the new interface structurally — no adapter type needed,
  unlike the review-side `reviewAssertionLoader` bridge, because the method signatures already match
  exactly), and only then creates the run. A request to a nonexistent scope now correctly 404s instead
  of silently persisting a run against a scope id that was never validated.
- Tests: `HighestAcceptedAssertionID` (2 cases), `ComputeAssertionWatermark` (2 cases, including
  multi-target max), and 3 handler-level tests — the existing pinned-provenance test (updated for the
  new scope-lookup + watermark-query mocks), a new test proving a forged `assertion_watermark` in the
  request body is ignored (the INSERT only matches the server-computed value), and a new
  scope-not-found → 404 test.
- `ComparatorVersion` was deliberately left client-supplied: unlike an assertion watermark, it doesn't
  represent governed data freshness — it's closer to a software/build version tag the caller (the
  orchestrating comparator invocation) legitimately owns.

Verification: `go build ./server/...`, `go vet ./server/...`, and
`go test ./server/api/ontology/... ./server/api/kbhandler/... -race -count=1` — no new failures against
the same pre-existing baseline noted in Addenda 2–3.

**Still not addressed** (explicitly out of scope for this addendum, larger separate work): comparison
**cells** — `CreateOntologyComparisonCell` still accepts verdict/rationale directly from the request
body; `EvaluateDirectionalCell`, the actual DR21 comparator, is still invoked only by its own test and
not wired into any production code path. See the decision record in Addendum 5.

## Addendum 5 (2026-08-01, same day — comparison-cell forgeability: deliberately deferred)

**Decision:** leave `CreateOntologyComparisonCell` as-is (client-supplied verdict/rationale, no
server-side evaluation) rather than fix it now. Documenting the gap and the reasoning per user request,
so it isn't silently lost.

**What's wrong:** `CreateOntologyComparisonCell`
(`kbhandler/ontology_comparison_cells_handler.go`) decodes a full `comparison.ComparisonCell` —
including `Verdict`, `Rationale`, both sides' `RepresentativeAssertionID`s, and both evidence lists —
directly from the request body and persists it unchanged. `EvaluateDirectionalCell`
(`comparison/evaluate_cell.go`), the actual DR21/DR22 comparator built and tested this same day, is
invoked only from its own test (`store_test.go`) — no production code path calls it. A caller can POST
any verdict for any target/metric/authority combination and have it persisted as a real, citable
comparison result, the same forgeability shape the run-watermark fixes (Addenda 3–4) closed for
`assertion_watermark`.

**Why not fixed now:** unlike the watermark (a single derived scalar computed from data already fully
available — `target_object_ids` → accepted assertions → max id), wiring the real comparator into
production requires two pieces of governed logic that don't exist anywhere in the codebase yet:

1. **Family grouping** — deciding which accepted assertions belong to the `subject_family` (e.g. the
   reviewed enterprise) versus each `authority_family` (e.g. a specific standard) for a given
   `target_object_id`/`metric_key`. Nothing today classifies an assertion by "family."
2. **Precedence-based representative selection** — when multiple non-conflicting assertions exist on
   one side, choosing the one `EvaluateFamily` compares against (and computing the correct
   `remainder_count` for the rest). The `precedence_policy` field on `ComparisonScope` is stored but,
   like the review-side `PrecedencePolicy`/`Applicability` fields flagged in the original review, is
   never evaluated by any code.

Both of these are exactly the kind of design work the ADR/P4 plan explicitly gates on the pilot
ventilator domain module and a domain-owner-confirmed authority standard — "the pilot domain module
supplies one part class, its metric definitions, and its expected-metric profile, so the first
comparison matrix is real rather than a mock" (P4 checkpoint, §8.3.7). Building family-grouping and
precedence-selection logic against synthetic or guessed rules risks having to redesign it once real
pilot content lands, which is the same trap the ADR's "no synthetic placeholder is promoted as
normative content" rule exists to avoid for profiles and rules.

**Bounded alternative considered and declined for now:** validate that client-supplied representative
assertion IDs exist and are `accepted`, and compute the verdict server-side via the existing
`EvaluateFamily`/`EvaluateDirectionalCell` from those real records — closing "declare any verdict" while
leaving family-grouping/precedence-selection as still caller-directed. User chose to leave the whole
thing deferred rather than take this partial step.

**What would need to happen to close this:** (1) the pilot module/profile/authority confirmation this
P4 plan already blocks Chunk D on, since family definitions are domain content, not generic runtime;
then (2) a family-classification mechanism (likely rule-kind-registry-shaped, mirroring seam 6) and a
precedence evaluator consuming `precedence_policy`; then (3) wire `EvaluateDirectionalCell` into
`CreateOntologyComparisonCell` (or a new `ComparisonService`, mirroring `ReviewService`) instead of
accepting a pre-computed cell.

## Documentation impact

**What knowledge changed?** P4's "generic runtime built" status is downgraded: the schema/lifecycle
layer stands, the review/comparison evaluation runtime does not yet meet its own stated acceptance
criteria (scope reproducibility, evaluator wiring, SHACL parity).

**Which docs/specs/ADRs/tests are affected?** The P4 foundation checkpoint
(`2026080104-devdoc-semos-p4-foundation-checkpoint.md`) and the ontology handoff's P4 status line.
`p4_exit_test.go` does not yet exist and should be added per the pattern in `p2_exit_test.go` /
`p3_exit_test.go`.

**Which docs were updated?** This devdoc. The P4 checkpoint's "Remaining P4 work" section should be
expanded once fixes land; not yet done as of this review.

**Which docs are stale?** The P4 checkpoint's framing of the runtime pieces (Chunk B/C rule-kind
registry, comparison evaluator) as delivered/complete is stale relative to the findings above; its
schema/migration claims are not stale.

**What was intentionally left undocumented?** None — this review is itself the record of what was
found undocumented (dead applicability/precedence fields, unreachable result categories) in the prior
checkpoint.
