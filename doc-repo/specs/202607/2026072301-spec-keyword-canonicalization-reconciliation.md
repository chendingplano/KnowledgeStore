# Keyword Canonicalization and Reconciliation Module — Design Spec

- **DocID:** `doc-2026072301`
- **Status:** Proposed
- **Date:** 2026-07-23
- **Component:** KnowledgeStore / ChenWeb — keyword resolution, alias management, acronym resolution
- **Authors:** Chen Ding, Codex
- **Tags:** keyword-resolution, canonicalization, aliases, acronyms, entity-resolution, reconciliation, llm

---

## Overview

This spec defines a **Keyword Canonicalization and Reconciliation Module** that
maps arbitrary input keywords to:

1. a **canonical keyword concept**
2. the concept's known **variants** (aliases, acronyms, alternate spellings, translations, abbreviations)
3. a **resolution status** (`resolved`, `ambiguous`, `unresolved`, `rejected`)

The module is intentionally split into two operating modes:

- **Working mode**: synchronous, low-latency, deterministic, **no LLM calls**
- **Reconciliation mode**: asynchronous, batch-oriented, uses **candidate generation + LLM adjudication** to consolidate unresolved or weakly linked variants into the canonical keyword database

This design treats keyword resolution as a specialized form of **entity resolution / record linkage**:
working mode should be cheap and predictable, while reconciliation mode handles the harder long-tail cases.

---

## Motivation

Keywords are fragile retrieval keys. Small variations can fragment recall:

- `Postgres`, `PostgreSQL`, `postgresql`
- `HVAC`, `heating ventilation and air conditioning`
- `GB`, `Guobiao`, `national standard`
- `odor control`, `odour control`, `deodorization`
- Chinese/English mixed forms and punctuation variants

If each surface form is treated as a separate keyword, search, faceting, clustering,
analytics, and downstream reconciliation all degrade.

The system therefore needs:

- a stable **canonical concept** per keyword family
- a growing database of known variants
- a deterministic resolution path for online use
- a delayed, auditable, LLM-assisted path for unresolved cases

This mirrors existing house patterns in the KnowledgeStore object and entity
reconciliation designs: exact/alias/acronym matching first, broader reconciliation second.

---

## Goals

1. Resolve an input keyword to a canonical keyword concept in **working mode** without LLM use.
2. Return all known variants for the resolved concept.
3. Preserve **ambiguity** as a first-class state instead of forcing false merges.
4. Continuously improve the database through **reconciliation mode**.
5. Support aliases, abbreviations, acronyms, alternate spellings, language variants, and noisy formatting variants.
6. Make every merge or alias attachment **auditable and reversible**.
7. Keep the module reusable across search, extraction, enrichment, faceting, and analytics.

## Non-goals

1. This module does not decide full real-world entity identity across arbitrary objects; it resolves **keyword concepts**, not complete business entities.
2. This module does not depend on embeddings in the online path.
3. This module does not require LLMs to create every canonical concept.
4. This module is not a full ontology system; hierarchical broader/narrower-term reasoning is deferred.

---

## Terminology

### Keyword concept

A consolidated semantic keyword family, identified by a stable `keyword_id`.

Examples:

- canonical label: `PostgreSQL`
- canonical label: `odor control`
- canonical label: `heating, ventilation, and air conditioning`

### Variant

A surface form that may point to a keyword concept:

- alias: `postgres`
- acronym: `HVAC`
- abbreviation: `deod.`
- spelling variant: `odour control`
- translation: `除臭`
- formatting variant: `post-gresql`

### Canonical label

The preferred display label for a keyword concept. It is **not** the only valid query form.

### Resolution

The act of mapping an input keyword to zero, one, or multiple candidate keyword concepts.

### Reconciliation

An offline process that reviews unresolved/weakly linked variants and decides whether to:

- attach them to an existing concept
- create a new concept
- mark them ambiguous
- reject them as noise
- merge two existing concepts

---

## Decision Summary

### D1. Use a concept table plus a variant table

The canonical database is modeled as:

- `keyword_concepts`: one row per canonical concept
- `keyword_variants`: one row per known variant string
- `keyword_variant_links`: provenance-rich link from variant to concept

This separates identity (`keyword_concepts`) from surface forms (`keyword_variants`).

### D2. Working mode is deterministic only

Working mode uses:

- Unicode normalization
- case folding
- accent folding
- punctuation/whitespace normalization
- exact and normalized lookup
- acronym/abbreviation tables already stored in the database
- deterministic candidate scoring

If the module is unsure, it returns `ambiguous` or `unresolved`. It does not call an LLM.

### D3. Reconciliation mode is batch-only and candidate-bounded

The LLM never scans the whole database blindly. Reconciliation mode first generates
a small candidate set using deterministic blocking and similarity search, then asks
the LLM to adjudicate only those bounded candidate sets.

### D4. Ambiguity is first-class

Some variants legitimately map to multiple concepts:

- `API` could mean `application programming interface` or `active pharmaceutical ingredient`
- `GB` could mean `gigabyte`, `Guobiao`, or `Great Britain`

The module must preserve such cases explicitly instead of assigning one concept by force.

### D5. Every automated decision is logged and reversible

False merges are more expensive than temporary unresolved terms. All reconciliation
actions therefore require:

- stored method (`exact`, `acronym`, `trigram`, `llm-adjudicated`, `human`)
- confidence
- source/provenance
- run ID
- reversible history

---

## Architecture

```
caller
  -> ResolveKeyword(input, context)
      -> working mode
         1. normalize
         2. exact/raw lookup
         3. normalized lookup
         4. deterministic acronym/alias lookup
         5. candidate scoring
         6. return resolved | ambiguous | unresolved
         7. optionally enqueue unresolved mention

background scheduler / manual run
  -> ReconcileKeywords(batch)
      -> collect unresolved / weak / conflicting variants
      -> build candidate blocks
      -> deterministic prefilter
      -> LLM adjudication
      -> guardrail validation
      -> apply DB updates
      -> log decisions
```

### Module boundary

The module should be implemented as a reusable package and store, not as prompt logic embedded inside one processor.

Suggested locations:

- Go package: `ChenWeb/server/api/keywordresolve`
- DB schema: `kb.keyword_*`
- API handlers: `ChenWeb/server/api/kbhandler/keyword_resolution.go`

---

## Data Model

### Table: `kb.keyword_concepts`

One row per canonical keyword family.

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGSERIAL` | PK |
| `keyword_id` | `TEXT` | Stable canonical ID |
| `canonical_label` | `TEXT` | Preferred display form |
| `canonical_label_norm` | `TEXT` | Deterministic normalized form |
| `language` | `TEXT` | Primary language if known |
| `domain` | `TEXT` | Optional scope: `database`, `tax`, `medical`, etc. |
| `keyword_type` | `TEXT` | `product`, `concept`, `standard`, `unit`, `organization`, etc. |
| `status` | `TEXT` | `active`, `merged`, `deprecated`, `review` |
| `quality_tier` | `TEXT` | `seeded`, `reviewed`, `llm`, `human` |
| `description` | `TEXT` | Optional short definition/disambiguator |
| `ext_info` | `JSONB` | Extra metadata |
| `create_time` | `TIMESTAMPTZ` | default `NOW()` |
| `modify_time` | `TIMESTAMPTZ` | default `NOW()` |

Indexes:

- unique `(keyword_id)`
- unique functional index on canonical uniqueness boundary, e.g.
  `(canonical_label_norm, coalesce(domain,''), coalesce(keyword_type,''))` for active rows
- GIN/trigram index on `canonical_label`

### Table: `kb.keyword_variants`

One row per observed or curated variant string.

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGSERIAL` | PK |
| `variant_text` | `TEXT` | Original surface form |
| `variant_text_norm` | `TEXT` | Deterministic normalized form |
| `variant_kind` | `TEXT` | `alias`, `acronym`, `abbreviation`, `translation`, `spelling`, `formatting`, `unknown` |
| `language` | `TEXT` | Language/script if known |
| `status` | `TEXT` | `resolved`, `ambiguous`, `unresolved`, `rejected` |
| `is_blocklisted` | `BOOLEAN` | stopword/noise guard |
| `first_seen_at` | `TIMESTAMPTZ` | first observed |
| `last_seen_at` | `TIMESTAMPTZ` | last observed |
| `seen_count` | `BIGINT` | usage frequency |
| `source_examples` | `JSONB` | compact examples |
| `ext_info` | `JSONB` | extra metadata |

Indexes:

- unique `(variant_text_norm, coalesce(language,''), coalesce(variant_kind,''))`
- GIN trigram on `variant_text_norm`
- B-tree on `(status, seen_count desc)`

### Table: `kb.keyword_variant_links`

Link table from variant to concept, with provenance.

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGSERIAL` | PK |
| `variant_id` | `BIGINT` | FK to `keyword_variants` |
| `keyword_id` | `TEXT` | FK/logical link to `keyword_concepts.keyword_id` |
| `link_type` | `TEXT` | `exact`, `normalized`, `alias`, `acronym`, `translation`, `llm`, `human` |
| `confidence` | `DOUBLE PRECISION` | 0.0-1.0 |
| `is_primary` | `BOOLEAN` | preferred mapping if non-ambiguous |
| `ambiguity_rank` | `INT` | ranking among competing mappings |
| `evidence_json` | `JSONB` | examples, rationale, source documents |
| `decision_run_id` | `TEXT` | reconciliation or manual run ID |
| `active` | `BOOLEAN` | soft-delete / reversal support |
| `create_time` | `TIMESTAMPTZ` | default `NOW()` |
| `modify_time` | `TIMESTAMPTZ` | default `NOW()` |

Indexes:

- `(variant_id, active)`
- `(keyword_id, active)`
- partial unique index for one active primary mapping when not ambiguous

### Table: `kb.keyword_mentions`

Optional evidence queue for observed uses from documents, prompts, or UI queries.

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGSERIAL` | PK |
| `variant_id` | `BIGINT` | FK |
| `input_record_id` | `BIGINT` | nullable provenance |
| `source_type` | `TEXT` | `document`, `query`, `artifact`, `manual` |
| `source_ref` | `TEXT` | artifact ID / query hash / path |
| `context_text` | `TEXT` | bounded context snippet |
| `domain_hint` | `TEXT` | context hint |
| `create_time` | `TIMESTAMPTZ` | default `NOW()` |

This table improves reconciliation quality without requiring LLM use in working mode.

### Table: `kb.keyword_reconciliation_runs`

Audit and telemetry for offline runs.

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGSERIAL` | PK |
| `run_id` | `TEXT` | stable external ID |
| `trigger` | `TEXT` | `cron`, `manual`, `backfill`, `post-import` |
| `model_name` | `TEXT` | nullable |
| `status` | `TEXT` | `running`, `completed`, `failed`, `partial` |
| `input_count` | `INT` | variants scanned |
| `resolved_count` | `INT` | variants resolved |
| `ambiguous_count` | `INT` | variants left ambiguous |
| `new_concept_count` | `INT` | concepts created |
| `merge_count` | `INT` | concept merges |
| `metadata_json` | `JSONB` | tokens, latency, thresholds |
| `create_time` | `TIMESTAMPTZ` | default `NOW()` |
| `modify_time` | `TIMESTAMPTZ` | default `NOW()` |

### Table: `kb.keyword_resolution_log`

Append-only decision log.

Each row stores:

- target row IDs
- old state
- new state
- actor (`system`, `llm`, `human`)
- run ID
- reason

---

## Normalization Model

Working mode depends on a stable deterministic normalization function:

```text
NormalizeKeyword(s):
  1. Unicode NFKC
  2. trim
  3. collapse internal whitespace
  4. case fold
  5. remove or standardize punctuation classes
  6. accent fold / diacritic removal
  7. preserve token order by default
  8. optionally derive auxiliary keys:
     - alnum_only_key
     - token_set_key
     - initials_key
```

### Why multiple keys

One normalized form is not enough. The module should materialize several deterministic keys:

- `exact_norm`: safest default
- `alnum_norm`: tolerates punctuation differences
- `token_set_norm`: catches `control odor` vs `odor control`
- `initials_key`: supports acronym candidate generation

These keys are lookup aids, not proofs of identity.

### PostgreSQL support

The DB implementation should use PostgreSQL facilities where appropriate:

- `citext` or equivalent case-insensitive comparison support
- `unaccent` for accent folding
- `pg_trgm` for similarity-based candidate generation
- `levenshtein` from `fuzzystrmatch` for short-string distance checks

Do **not** rely on phonetic matching as a primary strategy for multilingual data; keep it optional and low-weight.

---

## Working Mode

### Contract

`ResolveKeyword(input, opts) -> ResolutionResult`

Input:

- raw keyword string
- optional language hint
- optional domain hint
- optional keyword type hint
- optional context ID

Output:

```json
{
  "status": "resolved | ambiguous | unresolved | rejected",
  "keyword_id": "kw-...",
  "canonical_label": "string|null",
  "matched_variant": "string|null",
  "match_method": "exact|normalized|alias|acronym|translation|candidate",
  "confidence": 0.0,
  "variants": ["..."],
  "candidate_keyword_ids": ["..."],
  "explanation": "short deterministic reason"
}
```

### Algorithm

```
1. Validate input
   - empty, punctuation-only, or blocklisted terms -> rejected

2. Normalize input and derive keys

3. Exact raw lookup
   - direct variant match
   - direct canonical label match

4. Deterministic normalized lookup
   - exact_norm
   - alnum_norm
   - token_set_norm, if configured

5. Acronym / abbreviation lookup
   - direct variant_kind = acronym/abbreviation
   - initials_key match to candidate long forms already present in DB

6. Candidate ranking
   - score exactness
   - score type/domain compatibility
   - score language compatibility
   - score historical confidence

7. Decision
   - one strong winner -> resolved
   - multiple plausible winners -> ambiguous
   - none -> unresolved

8. Side effects
   - upsert `keyword_variants`
   - increment observation counters
   - enqueue mention/context if unresolved or ambiguous
```

### Deterministic decision policy

- `exact/raw` match to an active primary link wins immediately
- `exact_norm` wins if it maps to exactly one active concept
- acronym matches require tighter thresholds and context filters
- trigram or edit-distance similarity alone must **not** auto-resolve; it can only propose candidates

This rule keeps working mode cheap and safe.

---

## Reconciliation Mode

### Purpose

Reconciliation mode improves the database by resolving:

- `unresolved` variants
- `ambiguous` variants with strong evidence
- weakly linked variants
- duplicate canonical concepts
- stale low-quality seeded concepts

### Candidate generation before LLM

Reconciliation mode must follow the standard ER pattern:

1. **blocking**
2. **candidate generation**
3. **adjudication**
4. **application**

The LLM only sees candidate sets created by deterministic blocking.

### Blocking keys

Useful blocking dimensions:

- exact normalized form
- same initials/acronym pattern
- same language/script
- same domain/type
- trigram neighborhood
- shared token overlap
- same curated namespace or source system

For example, `HVAC` should be blocked with long forms whose initials are `HVAC`,
not with every keyword in the database.

### Reconciliation work item types

Each batch item should be one of:

- `attach_variant_to_existing_concept`
- `create_new_concept_from_variant`
- `resolve_ambiguous_variant`
- `merge_duplicate_concepts`
- `reject_noise_variant`

### LLM input

The LLM should receive only bounded structured data:

- variant text
- normalized keys
- variant kind guess
- language/domain/type hints
- small context snippets from recent mentions
- top N candidate concepts with:
  - canonical label
  - aliases/acronyms
  - type/domain
  - short description
  - representative contexts

### LLM output

Require strict JSON output:

```json
{
  "action": "attach | create | ambiguous | merge | reject",
  "target_keyword_id": "kw-123|null",
  "secondary_keyword_ids": ["kw-456"],
  "canonical_label_suggestion": "string|null",
  "variant_kind": "alias|acronym|translation|spelling|unknown",
  "confidence": 0.0,
  "reasons": ["..."],
  "needs_human": false
}
```

### Guardrails after LLM

The reconciler must reject or escalate outputs when:

- confidence is below threshold
- the proposed action conflicts with type/domain hard rules
- a merge would create obvious ambiguity
- acronym expansion conflicts with stored long-form evidence
- the LLM proposes a target outside the candidate set

### Decision policy

- `confidence >= 0.90`: auto-apply
- `0.65 <= confidence < 0.90`: mark `review`
- `< 0.65`: keep unresolved/ambiguous

Thresholds should be config-driven.

### Merge policy

When two concepts are merged:

1. elect deterministic survivor
2. redirect losing concept to survivor
3. re-point active variant links
4. keep reversible merge history
5. never delete provenance

Suggested survivor order:

1. `human` over `llm` over `seeded`
2. richer alias set
3. higher usage count
4. lexicographically smaller `keyword_id`

---

## Canonical Label Policy

The canonical label should be stable and human-readable. It is selected by policy, not by arbitrary latest write.

Preferred order:

1. explicitly human-pinned label
2. reviewed seed label
3. most widely used precise long form
4. language/domain-preferred label

Examples:

- prefer `PostgreSQL` over `postgres`
- prefer `heating, ventilation, and air conditioning` as canonical, keep `HVAC` as acronym
- prefer the domain-appropriate label when a short form is ambiguous

The canonical label is a display preference, not a reason to discard variants.

---

## Ambiguity Model

Ambiguity is unavoidable and must be represented explicitly.

### Types of ambiguity

1. **True polysemy**
   - `API`
2. **Insufficient evidence**
   - `GB`
3. **Cross-domain collision**
   - `RT`
4. **Language collision**
   - short terms identical across languages

### Storage rule

Allow multiple active links from one variant to multiple concepts when the variant is ambiguous.

Working mode behavior:

- if caller provides enough context to disambiguate, return one winner
- otherwise return `ambiguous` with ranked candidates

---

## APIs

### Synchronous APIs

- `ResolveKeyword(input, opts)`
- `GetKeywordConcept(keyword_id)`
- `ListKeywordVariants(keyword_id)`
- `CreateKeywordConcept(manual input)`
- `AttachKeywordVariant(keyword_id, variant, metadata)`

### Async / admin APIs

- `EnqueueKeywordMention(input, context)`
- `RunKeywordReconciliation(batch_opts)`
- `ReviewKeywordResolution(item_id, decision)`
- `MergeKeywordConcepts(winner_id, loser_id)`
- `ExportKeywordAliasMap(filters)`

### Bulk utilities

- `ImportSeedKeywords(file)`
- `BackfillKeywordVariants(from artifacts/search tables)`
- `RecomputeNormalizationKeys()`

---

## Search and Indexing

Recommended PostgreSQL indexes:

- B-tree on normalized keys
- GIN/trigram on `variant_text` and `canonical_label`
- partial indexes on unresolved queues
- optional `citext` columns or functional lower-case indexes

The online path should be optimized for:

- point lookup by normalized key
- quick fetch of all variants for one concept
- queue scan of unresolved/ambiguous variants

---

## Seeding Strategy

The module should not start empty.

Seed sources:

1. curated keyword lists already present in KnowledgeStore and prompts
2. existing aliases/acronyms in entities, metrics, provisions, products, objects
3. search analytics / frequent query logs
4. manually curated domain glossaries

Seed import should mark provenance:

- `source = prompt_seed`
- `source = artifact_backfill`
- `source = manual`

This makes later cleanup easier.

---

## Evaluation

### Online metrics

- resolution hit rate
- unresolved rate
- ambiguity rate
- median lookup latency
- top concept variant count

### Reconciliation metrics

- auto-attach precision
- false-merge rate
- backlog burn-down
- concept growth rate
- human-review acceptance rate

### Candidate-generation metrics

Borrow standard entity-resolution blocking evaluation:

- **pair completeness / recall proxy**
- **pairs quality / precision proxy**
- **reduction ratio**

This is the right way to evaluate whether candidate generation is both safe and efficient.

---

## Failure Modes and Safeguards

### Risks

1. False merges caused by short acronyms
2. Cross-domain collisions
3. Over-normalization causing unrelated strings to collapse
4. LLM overconfidence
5. Prompt drift leading to inconsistent reconciliation decisions

### Safeguards

1. Never auto-resolve from fuzzy similarity alone
2. Require hard type/domain compatibility for risky short forms
3. Keep reversible decision logs
4. Use structured outputs with bounded candidate sets
5. Prefer unresolved over wrong
6. Add blocklist support for generic/noisy tokens

---

## Rollout Plan

### Phase 1

- implement schema
- implement normalization library
- implement working mode exact/normalized lookup
- support manual seed import

### Phase 2

- add unresolved mention queue
- add trigram candidate generation
- add admin review APIs/UI

### Phase 3

- add batch reconciliation mode with LLM adjudication
- add merge/reversal logs
- backfill from existing artifact stores

### Phase 4

- integrate with search, extraction, object reconciliation, and analytics
- measure precision/recall and tune thresholds

---

## Recommended Initial Defaults

| Setting | Default |
|---|---|
| `KEYWORD_RESOLUTION_ENABLED` | `true` |
| `KEYWORD_RECONCILIATION_ENABLED` | `false` initially |
| `KEYWORD_RECONCILE_BATCH_SIZE` | `50` variants |
| `KEYWORD_RECONCILE_TOP_N_CANDIDATES` | `8` |
| `KEYWORD_RECONCILE_AUTO_APPLY_MIN` | `0.90` |
| `KEYWORD_RECONCILE_HUMAN_REVIEW_MIN` | `0.65` |
| `KEYWORD_MIN_ACRONYM_LEN` | `2` |
| `KEYWORD_MAX_AUTO_RESOLVE_TRIGRAM_ONLY` | disabled |

---

## Open Questions

1. Should this module live purely in `KnowledgeStore`, or also expose a shared Go package under `shared/go` for reuse across projects?
2. Should keyword concepts eventually support broader/narrower relations, or remain flat for v1?
3. Should domain scoping be mandatory for short forms of length `<= 3`?
4. Should multilingual canonical concepts store one global concept with many labels, or separate per-language concepts linked later?

My recommendation for v1:

- keep concepts flat
- keep one concept with many language-tagged variants
- require stronger review for short ambiguous forms

---

## Decision

Adopt a **two-mode keyword resolution architecture**:

- **working mode** for fast deterministic resolution over a canonical keyword DB
- **reconciliation mode** for batch LLM-assisted consolidation of unresolved or ambiguous variants

The center of gravity is the **canonical keyword concept + variant + provenance link** model.
This gives low token usage online, preserves auditability, and lets the database improve over time without making retrieval depend on live model calls.

---

## References

### Local references

1. `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
2. `KnowledgeStore/doc-repo/adrs/202607/2026070703-adr-object-manager.md`
3. `KnowledgeStore/doc-repo/specs/202606/2026062001-spec-semantic-clustering.md`

### External references

1. Papadakis et al., *Blocking and Filtering Techniques for Entity Resolution: A Survey*, ACM Computing Surveys, 2020.  
   https://helios2.mi.parisdescartes.fr/~themisp/publications/csur20-blockingfiltering.pdf

2. Schwartz and Hearst, *A Simple Algorithm for Identifying Abbreviation Definitions in Biomedical Text*, 2003.  
   https://psb.stanford.edu/psb-online/proceedings/psb03/schwartz.pdf

3. PostgreSQL `citext` documentation.  
   https://www.postgresql.org/docs/current/citext.html

4. PostgreSQL `unaccent` documentation.  
   https://www.postgresql.org/docs/current/unaccent.html

5. PostgreSQL `pg_trgm` documentation.  
   https://www.postgresql.org/docs/current/pgtrgm.html

6. PostgreSQL `fuzzystrmatch` documentation.  
   https://www.postgresql.org/docs/current/fuzzystrmatch.html

7. Huang and Zhao, *Leveraging Large Language Models for Entity Matching*, arXiv, 2024.  
   https://arxiv.org/abs/2405.20624

8. Fan et al., *In-context Clustering-based Entity Resolution with Large Language Models: A Design Space Exploration*, arXiv, 2025.  
   https://arxiv.org/html/2506.02509v1

---

## Documentation Impact

### What knowledge changed?

This spec introduces a formal design for a reusable keyword canonicalization and reconciliation module.

### Which docs/specs/ADRs/tests are affected?

- related KB identity/reconciliation ADRs are now precedent references
- future implementation ADRs and migration specs should reference this document

### Which docs were updated?

- this new spec only

### Which docs are now stale?

- none identified yet, but any future ad hoc keyword-alias logic should be folded into this design

### What was intentionally left undocumented?

- exact Go package API signatures
- exact migration filenames
- UI review workflow details
- prompt text for the LLM adjudicator
