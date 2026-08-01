# SemOS P4 — Profiles, Review, and Comparison: Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the governed profile and deterministic review runtime needed to review accepted semantic assertions against an immutable, reproducible scope, then use it for the ventilator display-module pilot once authoritative standards are confirmed.

**Architecture:** P4 separates reusable runtime mechanics from normative domain data. `kb.ontology_profiles` and `kb.ontology_profile_rules` are governed module content: a rule is reviewable but cannot produce a finding until included in an activated module release. A review freezes all input facts, active releases, selected profiles, and precedence policy in `kb.ontology_review_scopes`; a rule-kind registry evaluates that frozen scope and records auditable findings. The existing pure DR21 comparator remains the comparison primitive; comparison-run persistence is added only after the scope and review contracts are live.

**Tech Stack:** Go, `database/sql`, PostgreSQL/goose migrations, existing `ontology/modules`, `ontology/terms`, `ontology/assertions`, `ontology/semrules`, and `ontology/comparison` packages; sqlmock/unit tests plus temporary live-Postgres validation against `chenweb_test`.

---

## Scope decision

The P3 keyword lexicon (Track B) remains deferred by the P3 implementation log. P4 proceeds with the generic profile/review runtime and the mechanics of a data-only 4b module.

The selected pilot is the ventilator/display-module domain. Its authority-specific rules, profiles, and release are **not** authored in this plan until a real worked example confirms the governing standard editions, jurisdiction, and values. The generic runtime must not invent normative content from the synthetic gold fixture. The historical pump references in spec §16.4 are treated as a behavioural template; P4's final fixture is renamed to the confirmed ventilator pilot before its release gate is claimed.

## Chunk A — Governed profile schema and module-release visibility

**Files:**

- Create: `ChenWeb/project_migrations/20260801000007_create_kb_ontology_profiles.sql`
- Create: `ChenWeb/project_migrations/20260801000008_create_kb_ontology_profile_rules.sql`
- Create: `ChenWeb/server/api/ontology/profiles/{profiles_store,profile_rules_store,state_machine,nullable}.go`
- Create tests: `ChenWeb/server/api/ontology/profiles/*_test.go`
- Modify: `ChenWeb/server/api/ontology/modules/{validate,releases_store}.go`

- [ ] Write a failing store test proving a draft profile/rule is not returned by active-release queries.
- [ ] Run `go test ./server/api/ontology/profiles/... -run TestActiveProfilesExcludeDraft -count=1`; confirm it fails because the package/query is absent.
- [ ] Add versioned profile and profile-rule tables. Require a rule's profile/version to exist, retain versions, and make a rule immutable once release-linked.
- [ ] Add minimal stores for authoring, listing, and active-release reads. Active reads join `kb.ontology_active_releases` and `kb.ontology_module_releases`; no caller may select by a raw draft profile id.
- [ ] Extend module release validation/snapshotting so approved profile content and rules are checksummed, released, and activated with their module.
- [ ] Re-run the targeted test and `go test ./server/api/ontology/modules/... ./server/api/ontology/profiles/... -count=1`.

Acceptance: a profile/rule cannot produce a normative result unless its containing module release is active; a failed release leaves the previously visible profiles unchanged (spec §16.4.1–3).

## Chunk B — Rule-kind registry and deterministic evaluator

**Files:**

- Create: `ChenWeb/server/api/ontology/profiles/{rule_registry,evaluate,rule_required_assertion_pattern}.go`
- Create tests: `ChenWeb/server/api/ontology/profiles/{rule_registry,evaluate,rule_required_assertion_pattern}_test.go`

- [ ] Write a failing test registering a rule kind with an evaluator and SHACL emitter, then evaluating `required_assertion_pattern` against accepted assertions.
- [ ] Run the exact test and observe the missing registry/evaluator failure.
- [ ] Implement seam 6: registration requires both Go evaluation and SHACL emission functions. Reject a rule that lacks either one.
- [ ] Implement only `required_assertion_pattern` initially, with `exists_conforming`, `all_conforming`, `count_conforming`, and `none_matching` quantifiers. Return the six spec §12.4 categories, preserving candidate ids and reasons.
- [ ] Run focused tests, then `go test ./server/api/ontology/profiles/... -count=1`.

Acceptance: missing occurs only in a closed dimension; unresolved scope yields indeterminate; a non-applicable condition yields inapplicable; exact result behavior follows spec §12.3 and §16.4.4–12.

## Chunk C — Immutable review scopes and findings

**Files:**

- Create: `ChenWeb/project_migrations/20260801000009_create_kb_ontology_review_scopes.sql`
- Create: `ChenWeb/project_migrations/20260801000010_add_ontology_refs_to_doc_review_findings.sql`
- Create: `ChenWeb/server/api/ontology/profiles/{review_scopes_store,review_service}.go`
- Create tests: `ChenWeb/server/api/ontology/profiles/{review_scopes_store,review_service}_test.go`
- Modify: `ChenWeb/server/api/kbhandler/*review*`, `ChenWeb/server/api/routes.go`

- [ ] Write a failing test that creates a deterministic scope, changes current module activation, and confirms rerunning the historical scope retains its pinned release and selected rule set.
- [ ] Run it and confirm the absent scope store/service causes the failure.
- [ ] Persist immutable review inputs: reviewed records, target objects/classes, as-of/jurisdiction/context, selected profile versions/releases, applicability trace, precedence policy, and closed dimensions.
- [ ] Evaluate a scope through the Chunk-B registry and persist links from findings to `review_scope_id`, `profile_rule_id`, and `assertion_id` without overwriting existing document-review fields.
- [ ] Add read APIs that expose a finding's scope, rule, assertion and evidence lineage.
- [ ] Run profile tests and focused handler tests.

Acceptance: historical scopes reproduce after activation changes; unresolved precedence emits an indeterminate `profile_rule_conflict` only for its shared semantic slot; every finding is auditable to scope/rule/assertion/evidence (spec §12.1–12.3, §16.4.10,13).

## Chunk D — Ventilator 4b module and live acceptance fixture (blocked on authority confirmation)

**Files:**

- Create: module/profile content through the DB-native authoring/release flow
- Create: `ChenWeb/server/api/ontology/profiles/p4_exit_test.go`
- Create temporary: `ChenWeb/server/cmd/p4validate/main.go` (delete after live validation)
- Modify: ADR/handoff/implementation log in `KnowledgeStore/doc-repo/`

- [ ] Confirm authoritative source editions, jurisdiction, profile owner, and a real worked example; record them in the pilot-module authoring log.
- [ ] Write failing fixtures for the confirmed display-module profile: complete, missing-in-closed/open dimensions, incompatible unit/value, assertion conflict, quantifier behavior, and rule-precedence conflict.
- [ ] Author the ventilator domain module as data; compile, release, and activate it without Go code or a migration.
- [ ] Run the fixture and live-Postgres validation; update the ADR's old pump wording to point at the actual pilot.

Acceptance: the P4 suite, adapted to the confirmed pilot, passes. This chunk is intentionally blocked until the authority decision is supplied; no synthetic placeholder is promoted as normative content.

## Chunk E — Comparison scopes and cached cells

**Files:**

- Create: comparison migrations/stores under `ChenWeb/server/api/ontology/comparison/`
- Create tests in `ChenWeb/server/api/ontology/comparison/`

- [x] Write failing tests for an immutable comparison scope and directional DR21 cells assembled from accepted assertions.
- [x] Implement persistence for scopes/runs/cells and use the existing `EvaluateFamily` comparator for verdict computation.
- [x] Pin the assertion watermark and module/profile releases; never merge underlying assertions for display equivalence grouping.
- [ ] Run comparison tests and the pilot fixture once Chunk D is unblocked.

Acceptance: DR22 cells retain every assertion/citation, a precedence-selected representative, remainder count, verdict, direction, and rationale; profile/recommendation policy is versioned separately from the verdict.

## Verification and documentation

- [ ] For each production change, follow red → observed failure → minimal green → focused pass.
- [ ] Run `go test ./server/api/ontology/profiles/... ./server/api/ontology/modules/... ./server/api/ontology/comparison/... -count=1`, `go build ./server/...`, and focused `go vet` before completion.
- [ ] Run an explicit live-Postgres validation against `chenweb_test` before claiming any chunk that persists or freezes governed review data.
- [ ] Maintain a P4 implementation log and update the ontology handoff, ADR status annotation, and ontology capsule with implemented/deferred boundaries.
