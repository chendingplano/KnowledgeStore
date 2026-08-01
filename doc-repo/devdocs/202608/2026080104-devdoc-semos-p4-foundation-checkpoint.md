# SemOS P4 Foundation Checkpoint — Governed Profiles and Rules

**Date:** 2026-08-01  
**Status:** Partial implementation checkpoint; P4 is not complete.

## Delivered in this checkpoint

- Added `kb.ontology_profiles` and `kb.ontology_profile_rules` goose migrations. Both are versioned governed-content tables; a profile rule references an exact profile version and neither table permits release visibility independently of `kb.ontology_module_releases`.
- Added the `ontology/profiles` stores:
  - `ProfileStore.CreateProfile` creates only version-1 `draft` content.
  - `ListApprovedProfiles` exposes staged content solely to the module compiler.
  - `ListActiveProfiles` joins the current activation pointer and returns only `included_in_release` content.
  - `ProfileRuleStore` provides the corresponding active and staged reads, requiring profile and rule to be included in the same active release.
- Extended the module release snapshot/checksum and tagging path to include profiles and profile rules. They therefore ship atomically with their module rather than as free-standing runtime configuration.
- Wrote the P4 plan `2026080104-plan-semos-p4-profiles-review-and-comparison.md`. It keeps the ventilator/display-module normative content blocked until authoritative standard editions and a real worked example are confirmed; no synthetic gold fixture is promoted as a profile.

## Verification

Fresh checks passed:

```text
go test ./server/api/ontology/... -count=1
go build ./server/cmd/ontology-compiler ./server/cmd/deepdoc
```

Focused red-green tests cover draft exclusion from active profile/rule reads, profile collection in the compiler snapshot, profile release tagging, and draft-only profile creation.

### Live migration validation (2026-08-01)

The normal `server/cmd/dataservice` migration path was run successfully against the staging
`miner` database after supplying its required configuration. Goose recorded both migrations in
`project_db_migration`:

```text
20260801000007
20260801000008
```

Direct schema inspection confirmed `kb.ontology_profiles` and `kb.ontology_profile_rules`, their
version and lifecycle `CHECK` constraints, the profile-rule `(profile_id, profile_version)` foreign
key, and both `released_in_release_id` foreign keys to `kb.ontology_module_releases`.

## Not yet complete

- Profile/rule approval transitions and rule-authoring writes beyond initial profile creation.
- The seam-6 rule-kind registry, evaluator, SHACL emitters, immutable review scopes, findings integration, comparison scope persistence, the pilot module, and P4 acceptance fixture.
- A live Go-store/release transaction proof is still pending. The migrations and schema are now
  live-validated; a later Chunk-A validation should create a disposable draft profile/rule through
  the stores, release/activate it, prove active visibility, then roll the disposable data back or
  clean it up through the governed lifecycle.

## Documentation impact

**What knowledge changed?** Profiles/rules now have a concrete governed-content storage and module-release design in code.

**Which docs/specs/ADRs/tests are affected?** P4 planning, the P4 runtime tests, and the module compiler snapshot contract.

**Which docs were updated?** The new P4 implementation plan and this checkpoint.

**Which docs are stale?** The ontology handoff remains accurate: P4 was not previously implemented. It should be updated only after a live-validated P4 chunk is complete.

**What was intentionally left undocumented?** Authority-specific ventilator profile values and standard editions, because they must come from a confirmed real source rather than the synthetic benchmark.
