# Review of ADR `2026081701` — ontology object classes, metric instances, and semantic relations

Date: 2026-08-18

Status: open — review only, no code changed and no ADR edited in this session. Findings are
numbered from **Issue 16** to continue the ADR's own Issues 01–15 review sequence (change log
entry 2026/08/18).

Scope: ADR `2026081701-adr-canonical-metric-classes-instances-and-semantic-relations.md`, read
against the live `miner` schema and data, the implementation it describes, and its same-day
companion ADR `2026081801` (lossless semantic processing).

Code read: `server/api/ontology/assertions/{metric_normalizer.go,associate_semantics.go,
state_machine.go}`, `server/api/ontology/terms/terms_store.go`, migrations
`20260731000014` (ontology_terms), `20260731000017` (ontology_mappings), `20260801000001/02/03`
(semantic_assertions, assertion_evidence, assertion_relations).

Data read: live read-only queries against `miner` (counts quoted throughout are as of
2026-08-18).

Related: ADR `2026081801` (lossless semantic processing — the Phase-0 dependency that
`2026081701` DR5 requires, written the same day), ADR `2026081201` (auto-promoted governed
terms), ADR `2026081401` (governed metric vocabulary), user manual
`metric-assertion-semantic-processing-v1.2-en.md` §6.11, bug `2026081302`
(metric semantic association does not converge automatically).

---

## Summary

The ADR's diagnosis is accurate and its layering (occurrence → evidence → instance → class) is
the right model. Every factual claim in §2.1 was verified against production and matches exactly.

The findings below are gaps that will surface as data bugs during implementation, not
disagreements with the architecture. Six are specification gaps (Issues 16–21), two are
divergences between this ADR and its same-day companion `2026081801` (Issues 22–23), and one is a
scale assumption that the corpus data contradicts (Issue 24).

The single highest-value finding is **Issue 24**: the entire semantic path has been exercised on
**one document out of 58**, and the design's cost, threshold, and fan-out decisions rest on that
sample.

---

## Verified as correct

The §2.1 production survey is exact. Re-running it today against `kb.ontology_terms` where
`term_kind='metric_definition' AND status='auto-promoted'`:

| §2.1 claim | Live value |
|---|---|
| 182 auto-promoted `metric_definition` terms | 182 |
| 55 completely label-only | 55 |
| 45 with definitions | 45 |
| 7 identifying permitted units | 7 |

(Also: 113 carry `value_type` and 125 carry `range_type`, so "label-only" is the strict
all-four-empty count. 186 `metric_definition` terms exist in total; 4 are `included_in_release`.)

§2.5's diagnosis is confirmed in code: `metric_normalizer.go:118` builds
`metric:<input-record-id>:<metric-id>`, and `associate_semantics.go:385` copies it verbatim into
the assertion. §2.5's claim that the relation table is unpopulated is confirmed —
`kb.assertion_relations` has **0 rows**, and its `relation_kind` CHECK admits only
`conflicts_with`/`supersedes`/`superseded_by`, so DR10's extension is genuinely required.

DR8 is right that a missing-value assertion needs the `chk_semantic_assertions_object_ref_or_literal`
CHECK revised; that constraint exists as described.

---

## Issue 16 — Two competing claim-identity mechanisms; `logical_identity_key` is never mentioned

`kb.semantic_assertions.logical_identity_key` is `NOT NULL` and carries a unique
`(logical_identity_key, revision)` index. It *is* the occurrence-derived identity that §2.5
criticizes — yet the ADR never names the column, in any of its 14 decisions, its migration
section, or its acceptance criteria. ADR `2026081801` does not mention it either.

DR9 introduces `kb.semantic_claim_identities` with `current_assertion_id`. But "latest revision
is current" (the existing unique index, and `terms_store`-style semantics) *also* determines which
row is current. That is two sources of truth for the same question — precisely the anti-pattern
§5.4 invokes when it rejects `kb.ontology_term_instances`.

**Owed.** State explicitly whether `claim_id` becomes the value written to `logical_identity_key`
(making the registry a concurrency guard plus lookup index, with one source of truth), or whether
both persist with a defined precedence. If the former, say that the column's format changes and
that `metric:<record>:<metric-id>` values are migrated.

## Issue 17 — Revision semantics are undefined under find-or-create

DR9 states "New evidence alone does not create an assertion revision." Current behavior is the
opposite: `persistAssertion()` (`associate_semantics.go:449-460`) creates a new revision whenever
the logical identity already exists, and user manual §6.11 documents that as intended
("the old assertion becomes `superseded`, a new revision row is created").

The deeper problem: because DR9's canonical identity covers nearly the whole semantic payload,
any payload change now produces a **different claim**, not a new revision of the same claim. So
the ADR never says what still triggers a revision. The remaining candidates are non-identity-bearing
fields only — confidence, qualifiers, `normalized_against_contract_revision_id`, state-term
changes.

**Owed.** An explicit revision rule. Without one, `revision` becomes vestigial by accident and the
`(logical_identity_key, revision)` index means something different from what it means today.

## Issue 18 — The one-current-evidence-link invariant is asserted three times and mechanized zero times

AC 8.2 requires "One atomic metric occurrence has at most one current supporting instance link."
ADR `2026081801` repeats it in DR5 (with a supersede-then-insert transaction step) and again in
DR7. Neither ADR names an enforcing database constraint.

Production already violates it. Querying `kb.assertion_evidence` for
`deleted=false AND evidence_role='supports'` grouped by `(artifact_type, artifact_id,
input_record_id)`:

```
metric | 416_mtc_30 | 416 | 2
metric | 416_mtc_27 | 416 | 2
metric | 416_mtc_2  | 416 | 2
metric | 416_mtc_8  | 416 | 2
metric | 416_mtc_5  | 416 | 2
```

Only 71 evidence rows exist in total, so this is a high duplicate rate, not a stray. The risk
grows under find-or-create: today duplicates scatter across separate assertion revisions, but
afterwards they accumulate on one shared assertion row, which is exactly the row Review Document
traverses in DR13.

**Owed.** A partial unique index — `(artifact_type, artifact_id, input_record_id, evidence_role)
WHERE NOT deleted` — named in the migration plan, plus a backfill step that resolves the existing
duplicates. Neither ADR's migration section currently mentions cleaning them up.

## Issue 19 — `kb.ontology_term_redirects` is depended on by four decisions but never created

DR7 (resolution inputs), DR9 ("after redirect resolution"), DR11 ("Exact identity additionally
creates `kb.ontology_term_redirects`"), and DR13 (candidate retrieval step 1) all require term
redirects. The table does not exist in `project_migrations/`, and no phase creates it — Phase 1
item 5 creates the claim-identity registry, canonical-key version registry, and *assertion*
redirects only. Phase 3 item 6 ("Repair keyword concepts, term alignments, redirects…") assumes
it already exists.

Every peer table in the ADR gets an inline schema block; this one gets none. The same is true of
"assertion redirects," named in DR9 and Phase 1 but never given a shape.

**Owed.** Schema blocks for both redirect tables and an explicit Phase 1 creation step.

## Issue 20 — DR11's autonomous exact merges collide with `kb.ontology_mappings.approval_status`

`kb.ontology_mappings` (migration `20260731000017`) carries
`approval_status CHECK (approval_status IN ('pending','approved','rejected'))`, and its header
comment records the governing rule: "Exact mappings require explicit approval (approval_status),
per spec §9.1's 'exact mappings require explicit approval'."

DR11 has autonomous exact-identity reconciliation create redirects, and AC 8.6 states "No ordinary
semantic-processing stage requires human approval." §10 supersedes ADR `2026072901`'s generic
"mandatory human activation" wording, but says nothing about this concrete, DB-enforced governance
rule or about spec §9.1.

**Owed.** An explicit statement — most likely that the governed policy actor writes
`approval_status='approved'` with `policy_version` provenance, and that spec §9.1 is amended for
this path. Silence here means the first autonomous merge either violates a documented rule or
writes `pending` and stalls.

## Issue 21 — The assertion `status` lifecycle is unreconciled by either ADR

`kb.semantic_assertions.status` is a governed state machine — `candidate → in_review →
accepted / rejected / deferred`, `accepted → superseded / unsupported` — enforced in
`state_machine.go` and by a DB CHECK.

`2026081701` adds three new state dimensions (DR8) and `2026081801` adds a fourth plus an
execution axis (DR9), but neither says what `status` a raw-preserved instance carries.
`2026081801:363` states "Admission into `kb.semantic_assertions` means the claim is represented,
not accepted as true" — a semantic clarification that does not resolve the column, because the
only path to a live assertion in the existing machine runs through `accepted`.

There is no legal state meaning "persisted but unendorsed." Either `accepted` is redefined (and
every consumer filtering on it changes meaning silently), or a new state is added, or the column is
retired in favour of the new dimensions.

**Owed.** Pick one and say so. This is the state-machine equivalent of Issue 16: a pre-existing
column whose meaning the new model changes without naming it.

**Partly resolved elsewhere:** the fate of live deferred candidates *is* handled — `2026081801`
migration bullet ("Existing failed/deferred candidates remain available until converted to
assertions/outcomes or explicitly retired") and its shadow-mode report covering "how many
previously deferred metrics" now convert. `2026081701`'s own migration section does not
cross-reference this, and should.

## Issue 22 — `2026081701` DR8 and `2026081801` DR6 disagree on the assertion's state field set

Two ADRs written the same day specify the same row differently:

| `2026081701` DR8 | `2026081801` DR6 |
|---|---|
| `instance_of_term_id` | `instance_of_term_id` |
| `normalized_against_contract_revision_id` | *absent* |
| `class_identity_state_term_id` | `class_identity_state_term_id` |
| *absent* | `mapping_resolution_state_term_id` |
| `value_state_term_id` | `value_state_term_id` |
| `conformance_state_term_id` | `conformance_state_term_id` |
| `processing_error_details` | `processing_error_details` or linked outcome IDs |
| *absent* | `raw_text`/`raw_payload`, normalized value fields |

Mapping resolution is a first-class independent dimension in `2026081801` DR9's table and has no
counterpart in `2026081701` DR8 at all.

**Owed.** One normative field list, with the other ADR referencing it. Since `2026081801` is
declared the Phase-0 dependency, it should probably own the list.

## Issue 23 — §3.5's state enumeration mixes four dimensions that DR8 separates

§3.5 says the system "records precise states such as `mapping_unresolved`, `unparsed`,
`datatype_mismatch`, `contract_violation`, `class_provisional`, `class_ambiguous`, and
`source_conflict` rather than applying one global `incorrect` label."

Those seven values span four dimensions that the ADR's own DR8 — and `2026081801` DR9 — insist
are independent: mapping resolution, value, conformance, and class identity. Read literally, §3.5
reintroduces the flat status field that DR8 exists to replace.

**Owed.** Present §3.5's list as a dimension-tagged table, or cross-reference DR8's dimensions
instead of enumerating values inline.

## Issue 24 — The design is validated on one document, and the scale claims follow from that sample

This is the finding I would act on first. Live counts:

| Measure | Value |
|---|---|
| `kb.metrics` rows | 7,074 |
| distinct `input_record_id` in `kb.metrics` | 58 |
| distinct `input_record_id` in `kb.semantic_decision_candidates` | **1** |
| metric rows carrying `metric_definition_term_id` | 89 (1.3%) |
| metric semantic assertions | 71 |
| `kb.assertion_relations` | 0 |

Three consequences the ADR does not draw:

1. **Lossless ingestion is roughly a 100× increase, not "an increase."** §9.2 says "Lossless
   ingestion increases stored assertions." The real figure is ~71 → ~7,000+ metric assertions,
   each additionally carrying a class-resolution decision row, an outcome envelope
   (`2026081801` DR5), and observed-profile updates. Stating the number makes Phase 2 a
   capacity-planned step rather than a surprise.

2. **Provisional classes will be the normal path, not the fallback.** With 98.7% of metrics
   carrying no `metric_definition_term_id`, nearly every metric takes DR11's "create a provisional
   class" branch. That puts duplicate-class reconciliation (DR11 case 2, Phase 3) on the critical
   path. The ADR's tone treats provisional classes as an edge case and reconciliation as cleanup.

3. **The quadratic risk needs a normative bound, not a risk bullet.** Exact-name groups in
   `kb.metrics` already reach 78 (`得分`), 74 (`评价总分值`), 49 (`评价分值`), 29, 21 — and the
   first three are prime merge candidates, so one class plausibly exceeds 200 instances. §9.2
   lists "Pairwise comparison can become quadratic without blocking and incremental updates" as a
   risk, but no decision specifies a blocking key, a per-class instance cap, or a ranking rule.
   DR13 compounds this by retrieving "all current instances of that class" with no cap for the
   Review Document payload.

**Owed.** Make blocking and per-class caps normative in DR10/DR13, and add a Phase 0 gate that
runs the *current* pipeline across all 58 records to produce a real corpus baseline before Phase 1
schema surgery. DR6/DR12's synthesis and adjudication thresholds are otherwise being chosen from a
single document.

## Issue 25 — DR2's `kb.ontology_terms` reshaping is the highest-risk change, and §11 defers the wrong part

28 Go files reference `kb.ontology_terms`. `terms_store.go` embeds the `(term_id, version)` model
directly: `COALESCE(MAX(version), 0) + 1` on insert (`:215`), `ORDER BY version DESC` for current
state (`:312`, `:341`), and `ON CONFLICT (term_id, version) DO NOTHING` (`:288`).

Open Question 1 defers "the migration mechanics from current `(term_id, version)` rows to stable
current headers plus append-only revisions." The mechanics are the tractable part; the risk is the
**consumer read contract** — every caller that today means "current" by "highest version" must
change, and a partial migration silently returns stale terms rather than failing.

**Owed.** A compatibility view (e.g. `kb.ontology_terms_current`) named in Phase 1 so consumers
migrate incrementally behind a stable read shape, and an explicit statement that no consumer reads
the base table directly after cutover.

## Issue 26 — Load-bearing identifiers are used but never defined

* `identity_scope` — appears once, inside the `kb.semantic_claim_identities` schema block, never
  explained. It plausibly participates in claim uniqueness, so its value space matters (per
  module? per artifact family? global?).
* `decision_key` — described as "the same stable `decision_key`" for supersession in DR7, but its
  derivation is never given. Supersession chains key on it.
* `kb.semantic_claim_identities` has **no stated unique constraint**, even though DR9 introduces
  the table specifically to "provide concurrency-safe find-or-create." Presumably
  `(identity_scope, canonical_key_version, canonical_digest)` — but concurrency safety is the
  table's entire purpose, so the constraint belongs in the ADR, not in OpenSpec.

---

## Minor / editorial

* **§4 "Review Decisions Incorporated" duplicates §1's change log** and carries no issue numbers,
  so it cannot be traced back to Issues 01–15. Either map each bullet to its issue or drop the
  section.
* **Metric and provision families will run structurally different pipelines** for an indefinite
  interim: DR4 removes decision candidates from the metric path only, while
  `kb.semantic_decision_candidates` currently holds 222 superseded + 89 deferred provision rows
  against 115 superseded + 48 accepted + 43 deferred metric rows. `2026081801` Phase 4 covers
  migrating further families, but `2026081701` should state that the divergence is expected and
  bounded.
* The 89 deferred provisions are all `no_governed_deontic_predicate`, and 40 of the 43 deferred
  metrics are `no_governed_assertion_kind_term:*` — i.e. the current deferral population is almost
  entirely vocabulary gaps, which is the exact case DR5 converts to persisted instances. Worth
  citing in the ADR as evidence that the lossless change is well-targeted.

---

## Still worth doing

1. Resolve Issues 16, 17, and 21 before any Phase 1 schema work — all three concern pre-existing
   columns whose meaning the new model changes without naming them.
2. Add the Issue 18 unique index and duplicate backfill to the migration plan.
3. Add `kb.ontology_term_redirects` and assertion-redirect schemas to Phase 1 (Issue 19).
4. Reconcile the DR8/DR6 field-set divergence between `2026081701` and `2026081801` (Issue 22).
5. Run the current pipeline across all 58 input records to produce the Phase 0 baseline before
   thresholds are chosen (Issue 24).
6. Decide the `kb.ontology_mappings` approval question with the spec §9.1 owner (Issue 20).
