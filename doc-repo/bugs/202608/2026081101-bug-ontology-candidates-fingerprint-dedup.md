# `kb.ontology_candidates` fingerprint dedup is exact-match only — near-duplicate term candidates accumulate silently

Date: 2026-08-11

Status: fixed-unverified — root-caused and reviewed 2026-08-11; fix designed and implemented the
same day as ChenWeb openspec change `ontology-candidate-dedup`
(`ChenWeb/openspec/changes/ontology-candidate-dedup/`), migration
`20260811000005_add_identity_key_to_ontology_candidates.sql` applied live to the dev DB, unit
tests passing. Not yet verified against a real duplicate scenario end-to-end (see "Still owed").

Scope: `kb.ontology_candidates`, its `fingerprint` uniqueness mechanism, the writers that feed it
(`extract_metric_definitions`, `extract_metrics`'s inline harvest, `extract_test_methods`), and
its only consumer (the candidate review/promote API — no automated downstream processor and no
frontend currently touch this table).

Code read: `server/api/ontology/candidates/{fingerprint.go,candidates_store.go,promote.go}`,
`server/api/doc-processing/{extract-metric-definitions.go,extract-metrics.go,
extract-test-methods.go,ontology_candidate_harvest.go,control.go,phase_d.go,processor_plan.go}`,
`server/api/ontology/semid/termfamily.go`, `server/api/ontology/assertions/
decision_candidates_store.go`, `server/api/kbhandler/ontology_candidates_handler.go`, migrations
`20260731000018_create_kb_ontology_candidates.sql`,
`20260731000019_add_superseded_to_ontology_candidates.sql`. Related:
[[project_ontology_candidates_harvest_mechanics]] (memory, same investigation, earlier session
today), `KnowledgeStore/doc-repo/user-manuals/doc-processsors.md` §9.1, ADR
`202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` §A.1–A.2.

---

## Summary

Reprocessing document `input_record_id=416` produced two `kb.ontology_candidates` rows (id 16,
17) for what is clearly the same real-world metric ("种子发芽指数" / seed germination index) —
same `definition`, same `permitted_units`, same `applies_to`, overlapping `description`. They were
not deduped because **`label` and the sole `alias` swapped between the two extraction passes**
(run 1: label=种子发芽指数, alias=发芽指数; run 2: label=发芽指数, alias=种子发芽指数). The only
dedup mechanism on this table is an exact SHA-256 hash over the full canonicalized payload, so any
wording difference — including a label/alias swap that leaves the *set* of names unchanged —
produces a new row instead of being recognized as the same candidate.

Investigated whether this is dangerous. Conclusion: **not urgent today**, because nothing
automated reads this table and no reviewer UI exists yet to even display the duplication — but it
is a real landmine for the human-review/promotion step once one exists, and it will get worse as
document volume grows (see "Impact" below).

---

## Root cause

**Mechanism** — `Fingerprint(payload, sourceType, sourceRef, moduleID)`
(`fingerprint.go:17-29`): SHA-256 over the canonicalized (key-order-independent) full
`proposed_payload` JSON, NUL-joined with `source_type`, `source_ref` (`input_record:416` for both
rows here), and `proposed_module_id`. Enforced by `UNIQUE INDEX
uq_kb_ontology_candidates_fingerprint (fingerprint)` with `CreateCandidate` doing
`INSERT ... ON CONFLICT (fingerprint) DO NOTHING` (`candidates_store.go:141-207`). Pure exact-match,
additive-only — no delete, no update, no supersede anywhere in this code path.

No writer performs any semantic pre-check. `buildMetricDefinitionCandidate`
(`ontology_candidate_harvest.go:211-254`) and its callers in `extract-metric-definitions.go:106`
and `extract-metrics.go:664` call `CreateCandidate` directly with no prior lookup by `term_id` or
`label` against existing rows.

**Why the label/alias swap specifically defeats it:** `term_id` is deterministically slugified
from `label` (`candidateIdentifier`, `ontology_candidate_harvest.go:286-308`). Since `label` itself
differed between the two runs (发芽指数 vs 种子发芽指数), the two rows also got different
`term_id`s (`measurement:种子发芽指数` vs `measurement:发芽指数`) — so even a naive "same
`term_id`" pre-check would have missed this case. The one thing invariant across both runs is the
**set** `{label} ∪ aliases` = `{种子发芽指数, 发芽指数}` in both payloads.

**Contributing factor, not this bug's cause but worth flagging:** two independent code paths can
both write metric-definition candidates for the same document in the same pipeline run —
`extract_metrics`'s inline auto-harvest (`extract-metrics.go:664`, added 2026-08-01, commit
`5c0caf66b5b9`) and the separate routed `extract_metric_definitions` processor — and
`buildMetricDefinitionCandidate` hardcodes `ProposedBy: "extract_metric_definitions"` regardless of
which path called it, so `proposed_by` on a row cannot tell you which one produced it. Rows 16/17
were **not** distinguished this way in this investigation (their `discovery_method`/timestamps
weren't compared) — worth checking before assuming "reran the same processor twice" is the actual
mechanism versus "two writers fired once each in one run."

---

## Impact — does this reach `normalize_assertions`/`associate_semantics`/`project_semantics`?

**No.** Traced the full pipeline this session. Those three processors never read
`kb.ontology_candidates` at all — they're a structurally separate pipeline
(`extract_metrics`/`extract_provisions` → `kb.metrics`/`kb.provisions` →
`normalize_assertions` [reads `kb.metrics`/`kb.provisions` directly] →
`kb.semantic_decision_candidates` → `associate_semantics` → `kb.semantic_assertions` →
`project_semantics`), gated by `SEMANTIC_ASSOCIATION_ENABLED` (default true) and unrelated to the
term/definition candidates this table holds.

**Where duplication does matter:** the promotion step, human-driven. `promoteTerm`
(`promote.go:68-99`) checks idempotency only by `source_candidate_id`; `TermStore.CreateTerm` does
a plain `INSERT` against `UNIQUE(term_id, version)`. Two outcomes depending on whether the
duplicate pair's `term_id`s collide:
- **Same `term_id`:** second promotion fails with a Postgres unique-violation, surfaced as HTTP 400
  (`CWB_KB_OC_603`). Annoying but loud — a curator would notice.
- **Different `term_id`s** (the actual situation for rows 16/17, since label/alias swapped → the
  slugs differ): **both promote cleanly into two separate `kb.ontology_terms` rows.** Silent
  duplicate governed vocabulary, no error, no flag. This is the outcome this bug's example would
  actually produce if both candidates were independently approved today.

**Also found: no consumer currently exists to even surface the problem.** Grepped the whole repo —
no frontend (`.svelte`/`.ts`) calls the ontology-candidates API at all, and the one built-in
matching mechanism, `semid.TermFamily.ResolveCandidate` (`termfamily.go:103-158`, populates the
existing-but-unused `candidate_matches` column), has zero callers repo-wide. So today, duplicate
candidates sit invisibly until/unless someone lists them via the raw API and manually compares.

---

## Existing precedents in the codebase (not currently applied here)

- `candidate_matches` JSONB column already exists on `kb.ontology_candidates` for exactly this
  purpose ("possible match"), but is only written by the dead `TermFamily.ResolveCandidate`, and
  even that only matches against already-*released* governed terms, not other pending candidates.
- The same `semid` kernel, extended with pgvector embedding similarity, is fully wired for a
  sibling family, `keywords` (`server/api/ontology/keywords/{keywordfamily.go,reconcile.go}`).
- `kb.inventory_item_duplicates` has an explicit `duplicate_of`/`dedupe_key` design, wired for
  `extract_inventory_items`.
- Pipeline B's `DecisionCandidateStore.Propose` (`decision_candidates_store.go:217-294`) uses a
  deterministic `logical_identity_key` decoupled from the full-payload hash, with
  revision-supersede semantics when the payload for that key changes.

None of these are applied to `kb.ontology_candidates` today. A design for closing this gap
(deterministic identity key over the normalized `{label} ∪ aliases` set, surfaced via the existing
`candidate_matches` column rather than auto-merged) is being scoped as a follow-up openspec change.

---

## Still owed

- ~~Decide and build the identity-key + `candidate_matches`-surfacing fix~~ — done: see
  `ChenWeb/openspec/changes/ontology-candidate-dedup/` (proposal/design/specs/tasks all complete,
  all 17 implementation tasks checked off in `tasks.md`). `candidates.IdentityKey` computes a
  module + term_kind + normalized-{label}∪aliases key for `candidate_kind='term'` rows;
  `CandidateStore.CreateCandidate` records soft matches into `candidate_matches` for any
  non-terminal-status row sharing that key, never blocking the insert. Unit-tested (sqlmock) for
  the exact label/alias-swap reproduction below, plus the term_kind-collision, terminal-status,
  fingerprint-reuse, and non-term-candidate-kind edge cases.
- **Live end-to-end verification not yet done.** What would confirm this is genuinely fixed:
  reprocess a document that previously produced a label/alias-swapped duplicate pair (or
  synthesize one via the API) against the live/dev DB and confirm the second candidate's
  `candidate_matches` actually references the first, not just the sqlmock-level unit tests. Rows
  16/17 themselves predate this column and were not backfilled (`identity_key` is computed at
  insert time only — see design.md's Migration Plan) — they will not retroactively show a match
  against each other unless a backfill is run separately.
- Determine whether rows 16/17 came from two runs of the same processor or from
  `extract_metrics`'s inline harvest + `extract_metric_definitions` firing once each in a single
  run — check `discovery_method`/`create_time` on both rows. Affects whether there's a *second*,
  independent bug (unnecessary duplicate writers) beyond the dedup-key gap this fix addresses.
- No reviewer UI exists for `kb.ontology_candidates` at all (confirmed this session) — out of scope
  for this bug and for `ontology-candidate-dedup`, but the fix's value is capped until a human can
  actually see `candidate_matches` surfaced somewhere.
