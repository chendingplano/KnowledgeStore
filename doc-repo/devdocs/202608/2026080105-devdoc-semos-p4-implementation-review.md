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
