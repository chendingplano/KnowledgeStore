# 1. Overview

Artifact categories are the shared ontology used to group artifacts (metrics,
inventory items, etc.). Every artifact category lives in `kb.artifact_categories`
and is connected to artifacts through `kb.category_instance`.

Callers (e.g. the metric extractor [1]) never insert categories directly. They
pass a `(category_key, category_type)` pair to **Identify Artifact Categories**,
which resolves an existing category or creates a new one via the LLM, and always
returns a single category row.

# 2. Tables
## 2.1 Table `kb.artifact_categories`
This table stores all artifact categories.

```sql
CREATE TABLE kb.artifact_categories (
	category_id int8 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE) NOT NULL,
	category_key text NOT NULL,
	category_type text NOT NULL,
	status text DEFAULT 'pending_review'::text NOT NULL,
	canonical_of text NULL,
	display_names jsonb DEFAULT '[]'::jsonb NOT NULL,
	aliases jsonb DEFAULT '[]'::jsonb NOT NULL,
	acronyms jsonb DEFAULT '[]'::jsonb NOT NULL,
	category_desc text DEFAULT '' NOT NULL,
	category_keywords jsonb DEFAULT '[]'::jsonb NOT NULL,
	match_keys jsonb DEFAULT '[]'::jsonb NOT NULL,
	search_document text DEFAULT '' NOT NULL,
	required_attrs jsonb DEFAULT '[]'::jsonb NOT NULL,
	specs jsonb DEFAULT '{}'::jsonb NOT NULL,
	plausible_ranges jsonb DEFAULT '{}'::jsonb NOT NULL,
	parent_categories jsonb DEFAULT '[]'::jsonb NOT NULL,
	related_categories jsonb DEFAULT '[]'::jsonb NOT NULL,
	embedding jsonb DEFAULT '[]'::jsonb NOT NULL,
	seen_count int8 DEFAULT 0 NOT NULL,
	first_seen_at timestamptz DEFAULT now() NOT NULL,
	last_seen_at timestamptz DEFAULT now() NOT NULL,
	create_time timestamptz DEFAULT now() NOT NULL,
	modify_time timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT artifact_categories_pkey PRIMARY KEY (category_id),
	CONSTRAINT artifact_categories_type_key_uniq UNIQUE (category_type, category_key),
	CONSTRAINT artifact_categories_status_check CHECK ((status = ANY (ARRAY['pending_review'::text, 'approved'::text, 'rejected'::text, 'merged'::text])))
);
CREATE INDEX idx_kb_artifact_categories_canonical_of ON kb.artifact_categories USING btree (canonical_of);
CREATE INDEX idx_kb_artifact_categories_seen_count ON kb.artifact_categories USING btree (seen_count DESC);
CREATE INDEX idx_kb_artifact_categories_status ON kb.artifact_categories USING btree (status);
CREATE INDEX idx_kb_artifact_categories_match_keys ON kb.artifact_categories USING gin (match_keys jsonb_path_ops);
CREATE INDEX idx_kb_artifact_categories_search_fts ON kb.artifact_categories USING gin (to_tsvector('simple', search_document));
```

Notes on the columns added for resolution:

- `category_key` — the canonical, normalized **English** name (lowercase,
  single-space separated). Unique within a `category_type`.
- `display_names` — human-readable surface forms for presentation.
- `aliases` — normalized synonyms / alternate phrasings of the concept.
- `acronyms` — initialisms (e.g. `RT`, `TTFB`).
- `category_desc` — one-line English description of the concept.
- `category_keywords` — salient English keywords for the concept.
- `parent_categories` — JSON array of broader category keys returned by the
  LLM (stored as normalized display strings).
- `related_categories` — JSON array of adjacent/sibling category keys returned
  by the LLM (stored as normalized display strings).
- `match_keys` — a JSON array of normalized lookup strings: the `category_key`
  plus every normalized `display_names` / `aliases` / `acronyms` entry. This is
  the deterministic index used by exact/alias matching (GIN containment).
- `search_document` — dense English text (key + display_names + aliases +
  acronyms + category_keywords + category_desc) used by the hybrid match channel.
- `embedding` — embedding of `search_document`, same model/representation as
  `kb.search_artifacts` [2], used by the semantic match channel.
- The primary key is now `category_id` (the surrogate identity). Uniqueness is
  enforced by `(category_type, category_key)`, which is also the conflict target
  for idempotent upserts. `kb.category_instance` references `category_id`.

## 2.2 Table `kb.category_instance`
This is a relation table that connects artifacts to artifact categories.

```sql
CREATE TABLE kb.category_instance (
	category_id int8 NOT NULL,
	artifact_id text NOT NULL,
	input_record_id int8 NOT NULL,
	extra_info jsonb DEFAULT '{}'::jsonb NOT NULL,
	create_time timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT category_instance_uniq UNIQUE (category_id, artifact_id)
);
```

The `(category_id, artifact_id)` unique constraint is the conflict target that
makes instance writes idempotent (`ON CONFLICT (category_id, artifact_id)`).

# 3. Identify Artifact Categories

**Input:** `(category_key, category_type)`. **Output:** exactly one
`kb.artifact_categories` row (the resolved canonical category).

Both `category_key` and `category_type` participate in resolution — a key is
only meaningful within its type (a `metric` "coverage" and an `inventory_item`
"coverage" are different categories).

Resolution runs in layers, cheapest and most deterministic first. The first
layer that produces a match wins; the LLM is only invoked on a true miss.

1. **Normalize.** Ensure the key is English; if it is not, translate it. Produce
   the normalized form `k`: lowercase, trim, collapse internal whitespace,
   strip surrounding punctuation. `k` is what gets compared everywhere below and,
   on creation, becomes the stored `category_key`.

2. **Exact / alias match (deterministic).** Find a row of the same
   `category_type` whose `match_keys` contains `k`:

   ```sql
   SELECT * FROM kb.artifact_categories
   WHERE category_type = $1 AND match_keys @> jsonb_build_array($2);  -- $2 = k
   ```

   Because `match_keys` holds the canonical key *and* all normalized aliases and
   acronyms, this single query covers both exact-key hits and alias/acronym hits
   (e.g. `rt` → `response time`). On a hit, go to step 5 (canonicalize) and
   return.

3. **Hybrid semantic match (LLM-free).** On a miss, run hybrid search over
   `kb.artifact_categories` of the same `category_type`, reusing the same
   lexical + semantic RRF machinery as the metric search path [2][3]:
   - lexical: `ts_rank_cd` over `to_tsvector('simple', search_document)` with
     the query text `k` (plus any context keywords supplied by the caller),
   - semantic: `pgvector` cosine over `embedding`, gated by the existing
     `SEARCH_SEMANTIC_ENABLED` flag; fall back to lexical-only when disabled or
     when `k` cannot be embedded,
   - fuse with RRF (`rrf_k = 60`).

   Accept the top candidate iff it clears either channel:
   - semantic: `cosine_sim >= CATEGORY_MATCH_MIN_COSINE` (default `0.80`), or
   - lexical: `lexical_score >= CATEGORY_MATCH_MIN_RANK` (default reuses the
     metric search `min_rank`).

   On accept, **absorb the new surface form**: idempotently add `k` to the
   matched row's `match_keys` and refresh its `search_document`/`embedding`
   (see Idempotency below), then go to step 5 and return. This is how the
   ontology self-heals: once "response latency" maps to "response time", the
   next lookup hits the deterministic alias layer.

4. **Create-or-enqueue (LLM off the hot path).** If no layer matched, create or
   find a minimal placeholder row immediately, enqueue it for asynchronous LLM
   enrichment, and return that row. See
   [Create New Artifact Categories](#create-new-artifact-categories).

5. **Canonicalize before returning.** If the resolved row has
   `status = 'merged'`, follow `canonical_of` to its canonical category and
   return that one instead, so instances never point at a retired category.
   Bump `seen_count` and `last_seen_at` on the returned canonical row (best
   effort; not load-bearing — see note below).

**Status note:** newly created categories are `status = 'pending_review'`.
A category is usable for indexing the moment it exists, regardless of status;
gating metric extraction on human review would be too complex. `rejected` and
`merged` only affect resolution via the `canonical_of` redirect in step 5.

**Counters note:** `seen_count` / `last_seen_at` are not used for correctness —
artifact↔category usage is tracked by `kb.category_instance`. They are kept as
cheap observability and may be updated best-effort.

# 4. Create New Artifact Categories

Artifact categories are typed by `kb.artifact_categories.category_type` (such as
`metric`, `inventory_item`). A category is the ontology entry for one concept of
the given type.

## 4.1 Design Goal

Creating a category must not block the caller on an LLM round-trip. Category
resolution sits in the hot path of artifact extraction, and:

- a single pipeline may run multiple doc processors concurrently,
- multiple pipelines may run at the same time (one per document),
- several processors may discover the same missing category concurrently.

Therefore category creation must be globally deduplicated and the LLM work must
be moved to a background stage with bounded parallelism.

## 4.2 Two-Stage Creation Flow

Replace synchronous "miss -> call LLM -> insert" with:

1. **Stage A: fast placeholder upsert (synchronous).**
   On a miss, immediately upsert a minimal row keyed by
   `(category_type, category_key)` and return it to the caller.
2. **Stage B: background enrichment (asynchronous).**
   A shared category-enricher worker pool picks up placeholder rows, calls the
   LLM concurrently, and fills in aliases/description/specs/search fields.

This keeps category identity available immediately for `category_instance` and
other references, while allowing expensive LLM work to happen concurrently and
only once per unique category.

## 4.3 Stage A: Fast Placeholder Upsert

On an Identify miss for normalized key `k`, write a minimal placeholder row and
return it immediately:

```sql
INSERT INTO kb.artifact_categories
  (category_key, category_type, status, display_names, aliases, acronyms,
   category_desc, category_keywords, match_keys, search_document,
   required_attrs, specs, plausible_ranges, parent_categories,
   related_categories, embedding)
VALUES
  ($1, $2, 'pending_review', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
   '', '[]'::jsonb, jsonb_build_array($1), $1,
   '[]'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb,
   '[]'::jsonb, '[]'::jsonb)
ON CONFLICT (category_type, category_key) DO NOTHING;

SELECT * FROM kb.artifact_categories
WHERE category_type = $2 AND category_key = $1;
```

Properties:

- The placeholder row is the canonical identity anchor.
- `match_keys` already contains `k`, so the next lookup for the same key is
  deterministic and LLM-free.
- `search_document` may start as just `category_key`; richer search fields are
  added later by enrichment.
- All concurrent callers for the same `(category_type, category_key)` converge
  on the same row.

## 4.4 Stage B: Background LLM Enrichment

Use the `CREATE_ARTIFACT_CATEGORY_MODEL_NAME` model (fallback
`CREATE_ARTIFACT_CATEGORY_FALLBACK`) with the `CREATE_ARTIFACT_CATEGORY_PROMPT`
prompt in a background worker pool.

**LLM input:** `{ category_type, raw_category_key, context? }`, where
`raw_category_key` is the normalized `k` from Identify and `context` optionally
carries one or more triggering artifacts (name/description/unit/keywords) for
disambiguation only.

**LLM output** (strict JSON, an example): 
```json
{
  "domain": "medical_equipment",
  "aliases": [
    "scale",
    "body weight scale",
    "bathroom scale",
    "medical scale"
  ],
  "summary": "A device used to measure the weight or mass of an object or person, commonly used in medical settings.",
  "examples": [
    "Digital medical scale with BMI calculation",
    "Mechanical beam scale with sliding weights",
    "Portable bathroom scale for home use"
  ],
  "keywords": [
    "weighing scale",
    "medical scale",
    "weight measurement",
    "body scale",
    "digital scale"
  ],
  "confidence": 0.9,
  "ambiguities": [
    "Could refer to laboratory balance scales, but context specifies medical equipment"
  ],
  "description": "A weighing scale is an instrument ...",
  "common_units": [
    "kg",
    "lb",
    "g"
  ],
  "translations": {
    "en": "Weighing Scale",
    "zh": "体重计"
  },
  "canonical_key": "weighing_scale",
  "category_type": "inventory_item",
  "canonical_name": "Weighing Scale",
  "subcategory_of": [
    "medical_device",
    "measuring_instrument"
  ],
  "usage_contexts": [
    "hospitals",
    "clinics",
    "gyms",
    "pharmacies",
    "home health monitoring"
  ],
  "related_categories": [
    "blood pressure monitor",
    "thermometer",
    "height measurement device"
  ],
  "typical_attributes": [
    {
      "name": "type",
      "description": "Digital or analog scale"
    },
    {
      "name": "capacity",
      "description": "Maximum weight the scale can measure"
    },
    {
      "name": "accuracy",
      "description": "Measurement precision, e.g., to 0.1 kg"
    },
    {
      "name": "unit",
      "description": "Measurement units supported, e.g., kg, lb, st"
    },
    {
      "name": "platform",
      "description": "Size and material of the weighing platform"
    }
  ],
  "common_value_ranges": [
    {
      "notes": "Most medical scales cover this range",
      "range": "0-200 kg",
      "context": "human body weight"
    }
  ],
  "interpretation_guidance": [
    "Weight measurements should be taken consistently (e.g., same time of day)",
    "Trends are more important than single readings",
    "Calibrate regularly for accuracy"
  ],
  "selection_considerations": [
    "Required capacity and accuracy",
    "Portability and storage",
    "Digital vs analog display",
    "Connectivity for EHR integration"
  ]
}
```

Populate values based on the following table. If an LLM field is absent, store
the column's empty/default value.

| Attribute from LLM Output | `kb.artifact_categories` Field |
|---------------------------|--------------------------------|
| canonical_key | category_key |
| canonical_name | display_names |
| typical_attributes | required_attrs |
| typical_specs | specs |
| common_value_ranges | plausible_ranges |
| aliases | aliases |
| acronyms | acronyms |
| description | category_desc |
| keywords | category_keywords |
| subcategory_of | parent_categories |
| related_categories | related_categories |

**Deterministic post-processing of the LLM result:**

1. Read the LLM payload using the mapping table above. Treat `canonical_name`,
   `aliases`, `acronyms`, `keywords`, `subcategory_of`, and
   `related_categories` as optional arrays/strings from the JSON output; if a
   mapped field is missing, write the empty default for that column.
2. Re-normalize the returned `canonical_key` (defense against non-conforming
   output). If the LLM drifted to a different concept than `k`, keep `k` as the
   stored canonical `category_key` and fold the normalized LLM
   `canonical_key` into `aliases`.
3. Replace '_' with ' ' (space) for `canonical_key`, each item in
   `subcategory_of`, and each item in `related_categories` before storing them.
4. Store the mapped LLM fields into their own columns: `display_names` (from
   `canonical_name`, as a single-item JSON array when non-empty), `aliases`,
   `acronyms`, `category_desc` (from `description`), `category_keywords` (from
   `keywords`), `required_attrs`, `specs`, `plausible_ranges`,
   `parent_categories`, `related_categories`.
5. Build `match_keys` = the normalized set of
   `{category_key} ∪ display_names ∪ aliases ∪ acronyms ∪ {k}` (deduped).
6. Build `search_document` from `category_key` + `display_names` + `aliases` +
   `acronyms` + `category_keywords` + `category_desc`; compute `embedding` from
   it using the standard embedding model.
7. Update the existing placeholder row in place. Do not create a second row.

## 4.5 Global Claiming and Worker Coordination

The background enricher must work correctly when several processors in one
pipeline, or several pipelines across documents, are trying to create
categories concurrently.

Introduce an enrichment state machine on `kb.artifact_categories`:

- `llm_status`: `pending | processing | ready | failed`
- `llm_claimed_by`: worker id, nullable
- `llm_claimed_at`: timestamptz, nullable
- `llm_attempt_count`: integer
- `llm_error`: text, nullable

The claim protocol is:

1. Stage A inserts the placeholder with `llm_status = 'pending'`.
2. A background worker claims work with `FOR UPDATE SKIP LOCKED`:

   ```sql
   SELECT category_id
   FROM kb.artifact_categories
   WHERE llm_status IN ('pending', 'failed')
   ORDER BY first_seen_at
   FOR UPDATE SKIP LOCKED
   LIMIT $1;
   ```

3. The worker marks claimed rows `processing`, increments
   `llm_attempt_count`, and writes `llm_claimed_by` / `llm_claimed_at`.
4. After successful enrichment, the worker updates the category row and sets
   `llm_status = 'ready'`.
5. On failure, set `llm_status = 'failed'` and retain `llm_error`; later retry
   policy can requeue it.

`FOR UPDATE SKIP LOCKED` gives a database-backed global lease, so this works
correctly even when multiple doc-processor instances are running.

## 4.6 Request-Path Behavior

The request path never waits for enrichment. Once Stage A returns a category
row, the caller may:

- create `category_instance` rows immediately,
- continue artifact indexing,
- finish the doc processor and the pipeline without waiting for the LLM.

This means category metadata becomes **eventually enriched**, not immediately
complete. The system must treat `llm_status != 'ready'` as a normal transient
state, not an error.

## 4.7 Batch and Concurrency Controls

To improve throughput further:

- each doc processor should dedupe missing categories in-memory before Stage A,
  so one processor does not upsert the same key repeatedly in one run;
- processors should batch-enqueue all misses discovered in one artifact pass;
- the background enricher should use a bounded worker pool controlled by an env
  var such as `CREATE_ARTIFACT_CATEGORY_CONCURRENCY`;
- if the LLM/provider supports it later, enrichment may batch multiple category
  prompts in one API request, but batching is optional and not required for the
  first implementation.

## Idempotency & Concurrency

Multiple documents are processed concurrently and the same category key can be
resolved by several workers at once. All writes here must converge.

- **Stage A create is an upsert, not a bare insert.** Insert with the unique
  constraint as the conflict target and re-select to return the surviving row:

  ```sql
  INSERT INTO kb.artifact_categories
    (category_key, category_type, status, display_names, aliases, acronyms,
     category_desc, category_keywords, match_keys, search_document,
     required_attrs, specs, plausible_ranges, parent_categories,
     related_categories, embedding)
  VALUES (...)
  ON CONFLICT (category_type, category_key) DO NOTHING;

  SELECT * FROM kb.artifact_categories
  WHERE category_type = $1 AND category_key = $2;
  ```

  Two workers racing on the same new category therefore both end up returning
  the single placeholder row that won the insert; no PK violation, no
  duplicate.

- **Enrichment updates the existing row in place.** It must never insert a
  second row, even if several workers observed the category before enrichment
  finished. The row lease (`FOR UPDATE SKIP LOCKED`) is the global dedupe
  mechanism for LLM work.

- **Absorbing an alias (step 3) is a conditional, idempotent update** — it only
  writes when the alias is missing, so concurrent absorbs don't duplicate:

  ```sql
  UPDATE kb.artifact_categories
  SET match_keys = match_keys || jsonb_build_array($alias),
      modify_time = now()
  WHERE category_id = $id
    AND NOT (match_keys @> jsonb_build_array($alias));
  ```

  Refreshing `search_document`/`embedding` after absorbing is best-effort and
  may be skipped under contention; the deterministic `match_keys` entry is what
  makes the next lookup hit.

- **Instance writes are upserts** keyed on `(category_id, artifact_id)`:

  ```sql
  INSERT INTO kb.category_instance (category_id, artifact_id, input_record_id, extra_info)
  VALUES (...)
  ON CONFLICT (category_id, artifact_id) DO UPDATE
    SET extra_info = EXCLUDED.extra_info;
  ```

- **Reprocessing a record is safe.** Because placeholder creation, enrichment,
  alias absorption, and instance writes are all idempotent, re-running
  extraction for the same `input_record_id` produces no duplicates.

## 4.8 Optional Optimization: Shared Pending-Category Buffer

If request-path write volume becomes high, add an in-memory or Redis-backed
short-TTL "pending category" buffer keyed by `(category_type, category_key)`.
Its only role is to collapse repeated same-process enqueue attempts over a very
short window; it is an optimization only. Correctness still depends on the
database unique constraint and row-claim protocol above.

All schema changes above are applied through goose migrations (see the
db-migration workflow), not ad-hoc DDL.

## 4.9 Implementations
Refer to [4] and[5] for its implementation.

## References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md \
[2] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[3] KnowledgeStore/Capsules/coding-capsules/llm-wiki/hybrid-search.md \
[4] KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-impl.md \
[5] KnowledgeStore/Capsules/coding-capsules/categories/category-concurrent-resolution-design.md
