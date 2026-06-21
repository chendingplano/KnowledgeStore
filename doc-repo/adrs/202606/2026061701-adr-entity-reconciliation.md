# ADR 2026061701 — Corpus-Level Entity Reconciliation (Provisional Hygiene & Cross-Document Merge)

**Date:** 2026-06-17 \
**Status:** Accepted — schema landed, **online entity semantic clustering implemented** (P1), batch reconciler scheduling pending \
**Component:** Doc Processor — Entities & Relations \
**Authors:** chending \
**Tags:** entity-resolution, knowledge-graph, reconciliation, provisional-entities

---

## Change Logs
* 2026/06/17, ADR Created. Resolves ADR 2026061302 Open Question #3.
* 2026/06/20, Added the detailed **Adjudicator Method** (R5 design) — the LLM
  identity-decision step that was previously only an unimplemented interface. See
  [Adjudicator Method (R5 — Detailed Design)](#adjudicator-method-r5--detailed-design).
* 2026/06/20, **P1 (entity semantic clustering) implemented** — the
  `MergeAdjudicator` seam now has a real LLM caller (`callAdjudicator` in
  `semantic_clustering.go` with `prompt-entity-adjudicate-v1.md`), the hybrid-
  search blocking (hybrid-search proposal, 2026061303 Change 04) is wired, and
  the merge-apply machinery (`ApplyMerge`, `MarkClustered`, reversible
  `kb.entity_merges` provenance) is reused from this ADR's store. See
  [2026062001-spec-semantic-clustering.md](../specs/202606/2026062001-spec-semantic-clustering.md)
  for the full design and implementation status. The batch `Reconciler.Run`
  scheduling, the lexical `BlockCandidates` path, and Stage 2 (deferred context
  escalation) remain pending.
* 2026/06/20, **P2 (inventory item semantic clustering) implemented** — mirrors
  the entity clustering pattern (`semClusterInventoryItems` in
  `inventory_item_semantic_clustering.go`) with `InventoryItemClusterStore`,
  inventory-specific identity signature (item name, categories, manufacturer,
  brand, model/part numbers, aliases, standards), and dedicated
  `SEMCLUSTER_INVITEM_ADJ_*` env vars. Schema: migration
  `20260620000002_add_kb_inventory_item_reconciliation.sql` adds
  `canonical_item_id`, `reconcile_status` to `kb.inventory_items` and creates
  `kb.inventory_item_merges`. Wired into
  `InventoryItemsProcessor.PostProcessIndex` after search registry reindex.

---

## Context

ADR 2026061302 (D1–D6) made relations entity-linked and introduced **provisional
entities**: when a relation endpoint resolves to no extracted entity, a
provisional row is minted (`entity_status='provisional'`) so the edge still
points at a real `entity_id`. That ADR explicitly deferred one question:

> **Open Question #3 — Provisional-entity hygiene:** should provisional rows be
> periodically re-checked against the consolidated set (e.g. a later doc revision
> adds the missing alias), and merged?

Two structural gaps motivate resolving it now:

1. **Consolidation is per-document.** `consolidateEntities` (Phase 1.5) assigns a
   canonical `entity_id` *within one document*. The same real-world entity in two
   different documents gets two different `entity_id`s. Nothing merges them.
2. **Provisionals are never revisited.** A provisional minted because Phase 1
   missed an alias stays provisional forever, even after a later document extracts
   that entity properly. `backfillProvisionalEntitySpans` grounds them but never
   promotes or merges them.

Both are **corpus-level** problems that cannot be solved inside per-document
extraction. The decoupled extract-entities / extract-relations design (free-form
relations anchored by line spans, matched afterward) deliberately pushes identity
resolution downstream — so a downstream identity layer is required, not optional.

A whole-corpus pairwise comparison is O(n²) and cannot call an LLM per pair. The
design must block cheaply first and adjudicate selectively.

---

## Decision

Add a **corpus-level identity layer** maintained by a periodic, incremental
**reconciliation job**, separate from extraction. Four-phase loop:
**block → adjudicate → apply → enrich**, driven by a watermark over
`kb.entities.modify_time`.

### R1 — Canonical identity is self-referential on `kb.entities`

Reuse the existing invariant that `entity_id` is the graph edge
(`relations.subject_entity_id` / `object_entity_id`). Add `canonical_entity_id`:
the surviving `entity_id` a row folds into (NULL or self ⇒ the row is its own
canonical head). The canonical entity is simply the head row; no separate
entity-shaped table to keep in sync.

*Alternative considered:* a dedicated `kb.entity_clusters` table. Rejected for
now — it is only justified when a cluster needs attributes no member has (e.g. a
curated canonical description). The merge audit (R3) makes a later migration to
that model reconstructable.

### R2 — Two independent status axes

`entity_status` stays **provenance** (`extracted` | `provisional`). A new
`reconcile_status` (`pending` | `clustered` | `merged` | `held`) tracks the dedup
lifecycle. Overloading one column with two state machines was rejected.
Promotion of a provisional = `entity_status` flips to `extracted` **and**
`reconcile_status='merged'` (or `clustered`) once it links to a real head.

### R3 — Merges are recorded and reversible; never hard-delete

Every applied merge writes an immutable `kb.entity_merges` row (from/into,
method, confidence, evidence, relations_repointed, undo fields). The absorbed
row remains in `kb.entities` with `reconcile_status='merged'`. This preserves
provenance and lets a bad LLM merge be undone.

### R4 — Blocking precedes any LLM call

`kb.entity_merge_candidates` holds blocked pairs with a `signals` JSONB and a
`score`. Blocking uses only cheap signals — `kb.entity_names.name_key` equality,
`pg_trgm` similarity on `entity_en`, alias overlap, type/category match, shared
docs, and the existing `search_vector` full-text rank. **No pgvector** (the
codebase has none; all "vector" usage is `tsvector`). `UNIQUE(lo,hi)` with
`lo < hi` makes re-runs idempotent.

### R5 — Tiered adjudication; humans are a bounded queue

Rule thresholds auto-decide the high- and low-score tails (`auto_merge` /
`auto_reject`). Only the ambiguous middle band is sent to the LLM, as *clustered
candidate groups*, which canonicalizes and emits `auto_merge` or `needs_human`.
`needs_human` is the only thing humans review — keeping human effort bounded as
the corpus grows. Humans assist; they are not the engine.

### R6 — Incremental via watermark

`kb.reconcile_runs` records each run's `watermark_from` / `watermark_to` over
`kb.entities.modify_time`. `watermark_to` advances only on `status='ok'`, so a
failed run safely re-processes the same slice. Re-extracted/edited entities are
re-queued via a `content_fingerprint` change resetting `reconcile_status` to
`pending`.

### R7 — Relations resolve through canonical, with a view safety net

`kb.relations_resolved` exposes `subject_canonical_id` / `object_canonical_id`
via the canonical hop. The Apply phase also physically re-points
`subject_entity_id` / `object_entity_id` for index/perf; the view covers the
window between decision and physical update, and survives un-merges.

### R8 — `kb.entity_names` stays the name dictionary, not identity

`entity_names` remains the normalized-English-name dictionary (a strong blocking
signal, R4). It is **not** identity: two distinct entities can share a name and
one entity can carry several names. Identity lives in `canonical_entity_id`. The
Apply phase syncs survivors into `entity_names` (bump `seen_count`, advance
`status` past `pending_review`).

---

## Adjudicator Method (R5 — Detailed Design)

This section specifies *how* the LLM adjudicator reconciles entities. It fills in
the `MergeAdjudicator` seam (`Adjudicate(ctx, cluster) (AdjudicationResult, error)`)
that R5 names. The online entity semantic clustering path implements this via
`callAdjudicator` / `callAdjudicatorWithModel` in `semantic_clustering.go` (P1,
2026-06-20); the batch reconciler's `r.llm` path reuses the same method design.

**Division of labour (why the LLM is here at all).** Blocking + scoring is a
*recall* device: it answers "which entities *might* be the same?" and produces a
cheap scalar `score`. That scalar can confidently decide only the **tails**
(`score ≥ AUTO_MERGE_MIN` ⇒ same; `score ≤ AUTO_REJECT_MAX` ⇒ different). It
**cannot** decide the **middle band**, because a high score is raised equally by
*identity* and by mere *closeness* — siblings, parent/child, whole/part, and
same-type-different-instance ("Pump A" vs "Pump B"; "Sodium Hydroxide" vs "Sodium
Hypochlorite") all score high. Deciding *identity* in that band requires reasoning
over structured attributes and world knowledge, which is the adjudicator's job.
The adjudicator is **blocking-source-agnostic**: whether candidates come from
lexical blocking (R4 today) or hybrid/semantic blocking (the proposal in
2026061303 Change 04), the method below is identical — semantic blocking simply
feeds it richer, more cross-lingual groups.

### Principle: identity is decided on document-independent attributes

An entity is *extracted from* a document but is conceptually a
**document-independent node** — the same real-world entity recurs across many
documents. Identity must therefore be judged on the entity's **own intrinsic
attributes**, never on the source document's text. Concretely, the **primary**
adjudication input is the entity's *identity signature*:

> `entity` (+`_en`), `aliases` (+`_en`), `entity_type` (+`_en`), `desc` (+`_en`),
> `keywords` (+`_en`), `categories`, `entity_status`.

The source `doc_name` / `input_record_id` are carried only as **provenance labels**
(for the audit trail and survivor election), **not** as evidence. Document blocks,
chunks, line spans, and `entity_context` are **deliberately excluded** from the
primary pass. Two reasons: (a) feeding document text re-couples a document-
independent node to one arbitrary document — an entity seen in N documents has N
contexts, and there is no principled "the" context to use; (b) it re-introduces the
prompt-bloat failure mode that 2026061303 Change 01 removed. Context is brought in
*only* as a bounded, on-demand escalation for the residual the attributes cannot
settle (see [Stage 2 — deferred context escalation](#stage-2--deferred-context-escalation)).

**Is name + description + keywords enough?** For the large majority, yes — those
fields (with type, aliases, categories) *are* the document-independent identity
signature, and attribute comparison is the standard basis for entity resolution.
The known limit: these fields are themselves LLM-generated per document, so they
vary in richness and can be terse, generic, or divergent across documents. So they
are *sufficient for most* pairs, not *all* — the adjudicator must be allowed to say
"cannot tell from attributes alone," which is exactly what Stage 2 exists for.

### A. Form work units: cluster the middle band (pairs → groups)

1. Take every middle-band candidate pair (those the rule tier left `pending`) and
   treat it as an undirected edge `(lo_entity_id, hi_entity_id)`.
2. Compute **connected components** over those edges → *candidate groups*. A group
   is a set of entities transitively linked by "might be the same."
3. A component is a **work unit, not a merge.** Single-link chaining is *contained*
   here, never trusted: the LLM decides the true partition inside the component, so
   a chained blob (A~B~C~D) can be split back into the distinct entities it really
   is. This is the structural answer to the over-merge risk a pairwise threshold
   creates.
4. **Bound group size** by `RECONCILE_MAX_CLUSTER_SIZE` (default 20). If a component
   is larger, split it (keep the highest-scoring edges / sub-cluster by score) so
   every LLM call stays small and needle-rich.

### A.1 Packing: one group vs. many groups per LLM call

**Key fact: groups are disjoint by construction.** Entities in different connected
components were never blocked as candidates, so a merge *across* groups is never
wanted. Batching is therefore a pure cost optimization whose only real risk is the
model doing something we never want (a cross-group merge). The population is bimodal:
a few large components and a long tail of size-2 pairs.

Trade-off:

- **One group per call** — maximum precision (the model only ever sees genuine
  candidates, so it cannot fabricate cross-group merges), focused attention, clean
  per-group failure isolation / idempotency, simple output mapping, easy concurrency.
  Cost: the system prompt + few-shot block is re-sent every call, so for the pair-
  heavy tail token cost is dominated by boilerplate, not data.
- **Many groups per call** — amortizes that fixed overhead (the dominant win because
  pairs are so numerous) and uses the window better. Cost: cross-group contamination
  risk, attention dilution (longer prompt → lower per-group recall), coupled failure,
  group-id-keyed output + validation, and reproducibility sensitivity to batch
  composition.

**Decision — bounded, deterministic batching of small groups, solo for large:**

1. **Solo-call large groups** (near `RECONCILE_MAX_CLUSTER_SIZE`) — precision matters
   most there and they already fill the prompt.
2. **Batch the small (≈ size-2) tail** up to a token/entity budget
   (`RECONCILE_ADJ_BATCH_MAX_ENTITIES`, default e.g. 60), **never** an unbounded
   count — this captures the amortization where boilerplate dominates while bounding
   dilution.
3. **Guardrails on every batch:** each group is labelled with an id; the prompt
   states groups are independent and entities in different groups are known-distinct;
   output is keyed by group id; and the reconciler **deterministically discards any
   returned merge whose members span two input group-ids** (the validation layer, not
   the prompt, is the real safety net) and checks every input group got exactly one
   verdict.
4. **Deterministic batch composition** (sort groups by a stable key, greedy-fill) so
   re-runs batch identically and decisions are reproducible.
5. **Stage 2 stays solo / tiny-batch:** per-candidate context is token-heavy, so
   amortization matters less and dilution matters more.

### B. Hydrate each member (identity signature only)

For each entity in a group, load the **document-independent identity signature**
defined in the Principle above: `entity_id` (key), `entity` (+`_en`),
`aliases` (+`_en`), `entity_type` (+`_en`), `desc` (+`_en`), `keywords` (+`_en`),
`categories`, `entity_status`. Carry `doc_name` / `input_record_id` as a provenance
label only, and each pair's blocking `signals` + `score` as a *why-grouped* hint.
**Do not** load `entity_context`, line spans, chunks, or document blocks in this
(Stage 1) pass.

### C. Prompt contract (Stage 1 — attributes only)

The model is asked to **partition the group into identity sets** — not to re-score
pairs. The prompt (`RECONCILE_ADJ_PROMPT`, e.g. `prompt-entity-adjudicate-v1.md`)
states:

- **Definition of "same entity":** refers to the *same real-world thing* (same
  organization / specific facility / standard / person / component instance).
  Translations, transliterations, and abbreviations of one name **are** the same.
- **Decide from the identity signature only** (name / aliases / type / description /
  keywords / categories). No document text is provided; do not assume facts beyond
  the signature.
- **Identity ≠ relatedness (explicit negative guidance):** do **not** merge
  siblings, parent/child, whole/part, generic/specific, or same-type-different-
  instance. A **type conflict is a strong signal *against* identity.** Include 3–5
  few-shot examples covering a cross-lingual merge, an abbreviation merge, and two
  near-miss *non*-merges (sibling, parent/child).
- **When the signatures are too thin/generic/divergent to decide, do not guess —
  emit `defer`** (it will be revisited with context in Stage 2). Reserve `uncertain`
  (→ human) for genuinely contested cases, not merely under-described ones.
- Emit a **calibrated `confidence`**, a short `rationale`, and the `evidence` used.
- **Deterministic:** temperature 0, stable input ordering, pinned prompt version.

### D. Output schema (`AdjudicationResult` wire contract)

```json
{
  "groups": [
    {
      "member_entity_ids": ["<id>", "<id>", "..."],   // >= 2 members ⇒ a proposed merge
      "canonical_name": "…",                           // suggested display name only
      "confidence": 0.0,                               // 0.0–1.0, calibrated
      "rationale": "…",
      "evidence": { "shared_aliases": [], "type_agree": true, "...": "…" }
    }
  ],
  "keep_separate": [ ["<id>", "<id>"] ],               // judged distinct from attributes
  "defer":         [ ["<id>", "<id>"] ],               // attributes too thin — needs context (Stage 2)
  "uncertain":     [ ["<id>", "<id>"] ]                // genuinely contested — needs human
}
```

Mapping to the Go seam: `groups` → `AdjudicationResult.Merges`
(one `MergeDecision` per absorbed member), `keep_separate` → `auto_reject`,
`defer` → a new `reconcile`/candidate decision `deferred` (revisited in Stage 2),
`uncertain` → `AdjudicationResult.NeedsHuman`.

### E. Decision policy (LLM output → actions)

- For each `group` with ≥ 2 members:
  - `confidence ≥ RECONCILE_ADJ_MERGE_MIN` (default **0.90**) → **apply merge** (F).
  - `RECONCILE_ADJ_HUMAN_MIN` (default **0.60**) ≤ `confidence` < merge-min →
    **`needs_human`**.
  - below human-min → treat as keep-separate (no merge).
- `keep_separate` pairs → record an `auto_reject` decision so they are not
  re-adjudicated every run (until a `content_fingerprint` change re-queues them, R6).
- `defer` pairs → record decision **`deferred`** (the safe "not the same *for now*"
  state). They are **not** merged and **not** rejected; they remain queued for the
  Stage 2 context pass. Defaulting to not-merge here is deliberate: a false split is
  cheap and recoverable (both nodes survive, and Stage 2 / a later run can still
  merge them), whereas a false merge corrupts the graph.
- `uncertain` pairs → `needs_human`.
- **Survivor election stays deterministic in the reconciler, not the LLM.** Reuse
  `electSurvivor` (extracted > provisional, then richer surface set, then
  lexicographically smaller `entity_id`). The LLM's `canonical_name` is kept **only**
  as an enrichment suggestion, so identity is reproducible and not hostage to LLM
  tie-breaking.

### F. Apply (reuse R3 / R7)

For each confirmed group, fold every non-survivor into the survivor head:

- set the absorbed row's `canonical_entity_id` = survivor;
- union `aliases` / `aliases_en` / `keywords` / `line_spans` / `categories` onto the
  head;
- re-point `kb.relations.subject_entity_id` / `object_entity_id` to the survivor
  (R7; the `kb.relations_resolved` view covers the decision→update window);
- write one **reversible** `kb.entity_merges` row per absorbed entity
  (`from`, `into`, `method='llm'`, `confidence`, `evidence` = rationale + signals +
  `prompt_name` + `model_name`, `run_id`, undo fields);
- set absorbed `reconcile_status='merged'`; **promote provisionals** — if a
  `provisional` row folds into an `extracted` head, flip its `entity_status` to
  `extracted` (ADR 2026061302 D4 / Open Question #3).

### Stage 2 — deferred context escalation

Stage 1 (above) decides identity from document-independent attributes alone and
resolves the large majority of groups. The residue it marks `deferred` — pairs whose
signatures are too thin/generic/divergent to settle — is handled by a **separate,
lower-frequency, higher-cost pass** that is the *only* place document context enters:

1. Select `deferred` candidate pairs (optionally bounded by
   `RECONCILE_STAGE2_MAX_GROUPS_PER_RUN`, default small).
2. For **each candidate entity**, retrieve *its own* supporting context from *its own*
   provenance — e.g. `entity_context`, or the line evidence / chunk for that entity's
   `line_spans` in its source document. Each entity brings its own context; nothing is
   shared across documents, so document-independence at the node level is preserved —
   context is treated as per-candidate *supporting evidence*, not as the identity key.
3. Re-adjudicate the group with a context-augmented prompt
   (`RECONCILE_ADJ_CONTEXT_PROMPT`): same partition task and output schema as Stage 1,
   now with each member's context block attached.
4. Apply the same decision policy (E). A Stage 2 `defer` (still undecidable even with
   context) escalates to `needs_human` rather than looping.

This keeps the common path cheap and strictly document-independent, spends context
(and tokens) only on the hard minority, and never blocks the pipeline: an entity that
is genuinely the same but under-described simply stays unmerged until Stage 2 (or a
later run after its attributes are enriched) resolves it. Stage 2 may be deferred as a
*follow-on* implementation — Stage 1 alone is a correct, shippable reconciler; the
`deferred` state just accumulates harmlessly until Stage 2 exists.

### G. Cost, idempotency, and failure

- `RECONCILE_MAX_LLM_GROUPS_PER_RUN` caps LLM groups per run; overflow waits for the
  next run (its candidates stay `pending`).
- A group whose candidates are no longer `pending` is **skipped** → re-runs are
  idempotent.
- An LLM error on one group **skips that group only** (leave its candidates
  `pending`, log it); it does not fail the run, so sibling groups still progress and
  the watermark logic (R6) re-queues the skipped slice next run.

### H. Guardrails against over-merge

- **Type-conflict gate** (`RECONCILE_BLOCK_TYPE_CONFLICT`, default on): the LLM may
  never auto-apply a cross-`entity_type` merge at high confidence unless its
  rationale explicitly justifies the type difference; otherwise force `needs_human`.
- **Conservative early defaults:** start with a high `RECONCILE_ADJ_MERGE_MIN` and
  prefer `needs_human` over `auto_merge`. R3 reversibility is a *safety net*, not a
  license to merge loosely.
- **Optional self-consistency:** for high-stakes groups, require two temperature-0
  samples to agree before applying.

### I. Worked example

Middle band contains pairs `{A=Odor Treatment Facility, B=Malodour Control Unit}`
(cosine 0.83, type match), `{A, C=Wastewater Treatment Plant}` (cosine 0.79, type
match), and `{A, D="Treatment Facility"}` (cosine 0.80, type match, but D has an
empty description and generic keywords). Connected component = `{A, B, C, D}`.

Stage 1 (attributes only) returns:
`groups:[{member_entity_ids:[A,B], confidence:0.93, rationale:"both described as
odour-control facilities; keywords overlap (odor/malodour, exhaust scrubbing)"}]`,
`keep_separate:[[A,C],[B,C]]` ("C's description/keywords are about wastewater
treatment — a different facility"), `defer:[[A,D]]` ("D has no description and only
the generic keyword 'treatment' — cannot decide from attributes").

Result: A+B merge now (survivor by `electSurvivor`); C kept separate; A–D recorded
`deferred`. Stage 2 later pulls D's own line context, finds it is the same
odour-control facility, and merges it — or, if still undecidable, escalates A–D to
`needs_human`. The component is split and resolved in cost order, never collapsed.

---

### Database Migrations

**Entity reconciliation:** `project_migrations/20260617000004_create_kb_entity_reconciliation_tables.sql`:

- **`kb.entities`** adds `canonical_entity_id`, `reconcile_status` (default
  `pending`), `reconciled_at`, `modify_time` (default `now()`, with a
  `BEFORE UPDATE` touch trigger), `content_fingerprint`; plus supporting indexes.
- **`kb.entity_merge_candidates`** — blocking queue, `UNIQUE(lo,hi)`,
  `CHECK(lo < hi)`. The `decision` domain gains **`deferred`** (Stage 1 could not
  decide from attributes; awaits the Stage 2 context pass) alongside
  `pending` / `auto_merge` / `auto_reject` / `needs_human` / `applied`.
- **`kb.entity_merges`** — reversible merge provenance.
- **`kb.reconcile_runs`** — watermark + per-run audit.
- **`kb.relations_resolved`** — canonical-resolving view.

**Inventory item reconciliation:** `project_migrations/20260620000002_add_kb_inventory_item_reconciliation.sql` (parallel
schema following the same pattern):

- **`kb.inventory_items`** adds `canonical_item_id`, `reconcile_status` (default `pending`), `reconciled_at`; plus supporting indexes.
- **`kb.inventory_item_merges`** — reversible merge provenance (analogous to `kb.entity_merges`, no relation re-pointing needed).

Existing rows get defaults (`reconcile_status='pending'`) and are picked up by the first inventory item semantic clustering run.

### Environment Variables (proposed, tuning)

- `RECONCILE_ENABLED` (default off until validated)
- `RECONCILE_BLOCK_TRGM_MIN`, `RECONCILE_AUTO_MERGE_MIN`, `RECONCILE_AUTO_REJECT_MAX`
- `RECONCILE_BATCH_SIZE`, `RECONCILE_MAX_LLM_GROUPS_PER_RUN`

Adjudicator-specific (Adjudicator Method §C–§H):
- `RECONCILE_ADJ_MODEL_NAME` (LLM for adjudication; resolved via `MODEL_DEF_FILE`)
- `RECONCILE_ADJ_PROMPT` (Stage 1 attribute-only prompt, e.g. `prompt-entity-adjudicate-v1.md`)
- `RECONCILE_MAX_CLUSTER_SIZE` (default 20) — max members per LLM work unit
- `RECONCILE_ADJ_BATCH_MAX_ENTITIES` (default ~60) — token/entity budget for packing
  several small independent groups into one call (A.1); large groups go solo
- `RECONCILE_ADJ_MERGE_MIN` (default 0.90) — confidence to auto-apply a merge
- `RECONCILE_ADJ_HUMAN_MIN` (default 0.60) — confidence floor below which a group is dropped, above which it goes to `needs_human`
- `RECONCILE_BLOCK_TYPE_CONFLICT` (default true) — forbid high-confidence cross-type auto-merge

Stage 2 deferred-context escalation (optional follow-on):
- `RECONCILE_ADJ_CONTEXT_PROMPT` (context-augmented prompt for `deferred` pairs)
- `RECONCILE_STAGE2_MAX_GROUPS_PER_RUN` (default small) — bounds the costly context pass

---

## Consequences

- The same real-world entity across documents becomes a single canonical node;
  provisional entities get a promotion path instead of calcifying.
- New cost: a periodic job (blocking is SQL-cheap; LLM cost bounded to the
  ambiguous middle band by R5). Human review bounded to `needs_human`.
- Risk: an incorrect auto-merge collapses two distinct entities. Mitigated by
  R3 reversibility and the `held`/`needs_human` tiers; tune thresholds
  conservatively (prefer `needs_human` over `auto_merge` early).
- A high provisional count remains the quality signal ADR 2026061302 D4 called
  out — reconciliation reports it per run in `reconcile_runs.stats`.

## Tests

- Blocking idempotency (re-run produces no duplicate candidates).
- Merge apply: survivor election, alias/span union, relation re-point count,
  `entity_merges` row, provisional promotion.
- Un-merge restores prior `canonical_entity_id` and re-points relations back.
- Watermark: failed run does not advance `watermark_to`.
- Adjudicator clustering: middle-band pairs collapse to the correct connected
  components; an oversized component is split at `RECONCILE_MAX_CLUSTER_SIZE`.
- Adjudicator decision policy (with a stub `MergeAdjudicator`): a `group` ≥
  merge-min applies a merge; a mid-confidence group → `needs_human`; `keep_separate`
  → `auto_reject`; `defer` → `deferred`; the worked-example component `{A,B,C,D}`
  yields A+B merged, C kept separate, A–D `deferred`.
- Stage 1 input carries **only** the identity signature — no `entity_context` /
  line spans / chunks are passed to the Stage 1 adjudicator.
- Batching (A.1): large groups go solo; small groups pack up to
  `RECONCILE_ADJ_BATCH_MAX_ENTITIES`; batch composition is deterministic; and a
  returned merge spanning two input group-ids is **discarded** (cross-group guard).
- Survivor election is taken from `electSurvivor`, not the LLM's `canonical_name`.
- Type-conflict gate: a high-confidence cross-type group is forced to `needs_human`.
- Per-group LLM failure skips only that group and leaves its candidates `pending`.
- Stage 2: a `deferred` pair is re-adjudicated with per-candidate context and either
  merges or escalates to `needs_human`; it is never silently re-`deferred` forever.

## Documentation Impact

- ADR 2026061302 Open Question #3 → **Resolved** (link here).
- `ChenWeb/docs` entity/relation processing doc: add the reconciliation phase.
- Relation prompt `prompt-extract-relations-v2.md` §3.4 (consistent endpoint
  naming) is the upstream signal-quality dependency for R4 blocking.

## References

[1] 2026061303-ard-extract-entity-relation-amend.md — ADR 2026061302, entity-linked relations (D1–D6) + Open Question #3.

[2] 2026061207-spec-extract-entities-relations.md — Extraction spec.

[3] project_migrations/20260614000005_create_kb_entity_names.sql — entity-name dictionary.

[4] 2026062001-spec-semantic-clustering.md — Semantic Clustering design and
    implementation (P1, 2026-06-20).

[5] Code: `server/api/doc-processing/semantic_clustering.go` —
    `semClusterEntities`, `callAdjudicator`, `batchAdjudicateAndApply`.

[6] `prompts/prompt-entity-adjudicate-v1.md` — entity adjudication prompt.

[7] Code: `server/api/doc-processing/inventory_item_semantic_clustering.go` —
    `semClusterInventoryItems`, `InventoryItemClusterStore`.

[8] project_migrations/20260620000002_add_kb_inventory_item_reconciliation.sql —
    Inventory item reconciliation schema (canonical_item_id, reconcile_status,
    kb.inventory_item_merges).
