# Category Management Implementation

## Overview

Implementation of the **Identify Artifact Categories** procedure defined in
`category-mgmt-spec.md`. The code lives in `ChenWeb/server/api/doc-processing/`.

## New Files

### `artifact_category_registry.go`

Pure helpers and the DB layer.

**Pure helpers:**

| Function | Purpose |
|---|---|
| `normalizeCategoryKey(raw)` | Lowercase, collapse non-alphanumeric runs to single space, trim. Unicode-safe (CJK preserved). |
| `buildArtifactMatchKeys(key, displayNames, aliases, acronyms)` | Builds the deterministic GIN-indexed lookup set. Normalizes each token, dedupes, key-first order. |
| `buildCategorySearchDocument(key, displayNames, aliases, acronyms, keywords, desc)` | Assembles dense search text for hybrid match. Case-insensitive dedup; key first. |
| `parseCreateCategoryResponse(payload)` | Parses LLM JSON into `createdCategory`. Requires non-empty `category_key`. |
| `matchCategoryInSnapshot(normKey, queryVec, snapshot, cosineThreshold)` | Tier 1/2: exact key or alias match in `match_keys`. Tier 3: cosine similarity above threshold. |
| `resolveCanonicalCategory(rec, byKey)` | Follows `canonical_of` chain for `merged` categories; cycle-safe via visited set. |
| `categoryCosine(a, b)` | Local cosine similarity for snapshot matching. |

**Types:**

```go
type createdCategory struct {
    CategoryKey, Description, SearchDocument string
    DisplayNames, Aliases, Acronyms, Keywords, RequiredAttrs []string
    Specs, PlausibleRanges map[string]any
}

type artifactCategoryRecord struct {
    CategoryID   int64
    CategoryKey  string
    CategoryType string
    Status       string
    CanonicalOf  string
    MatchKeys    []string
    Embedding    []float64
}
```

**DB layer — `artifactCategoryRegistry{DB}`:**

| Method | SQL behavior |
|---|---|
| `loadActiveCategories(ctx, categoryType)` | Loads `approved ∪ pending_review` rows into in-memory snapshot. |
| `mintCategory(ctx, c, categoryType, embedding)` | `INSERT … ON CONFLICT (category_type, category_key) DO UPDATE seen_count+1 RETURNING category_id`. Idempotent under concurrency. |
| `absorbAlias(ctx, categoryID, alias)` | `UPDATE … WHERE NOT (match_keys @> to_jsonb($alias))` — conditional, idempotent alias append. |

### `artifact_category_resolver.go`

Implements the full *Identify Artifact Categories* resolution loop.

```
Resolve(rawKey, categoryType, evidence):
  1. Normalize rawKey → normKey
  2. Ensure snapshot loaded (cached per type for the pass)
  3. Embed normKey (semantic channel, best-effort)
  4. matchCategoryInSnapshot → tier 1/2 alias, tier 3 cosine
     ON HIT:  resolveCanonicalCategory → absorbAlias → return category_id
     ON MISS: creator.CreateCategory (LLM) → mintCategory → add to snapshot → return category_id
```

**Interfaces (inject in tests):**

```go
type categoryCreator interface {
    CreateCategory(ctx, rawKey, categoryType string, evidence map[string]any) (createdCategory, error)
}

type categoryEmbedder interface {
    EmbedCategory(ctx context.Context, text string) ([]float64, bool)
}
```

**Nil-creator guard:** if no LLM creator is configured and the category is missing,
`Resolve` returns a descriptive error instead of panicking.

**Snapshot caching:** `loadActiveCategories` is called once per `categoryType` per
resolver instance; newly minted categories are added to the in-memory snapshot so
subsequent keys in the same indexing pass resolve without re-querying the DB.

### `artifact_category_wiring.go`

Wires the real LLM creator and embedder from environment config.

**`newMetricCategoryResolver(db, logger)`** — called from `IndexMetricsForRecord`;
builds a `categoryResolver` with:

- `llmCategoryCreator` — calls `CREATE_ARTIFACT_CATEGORY_MODEL_NAME` (with
  `CREATE_ARTIFACT_CATEGORY_FALLBACK`) using prompt `CREATE_ARTIFACT_CATEGORY_PROMPT`.
  Thinking is forced off (`ThinkingType = "disabled"`). Builds the LLM input as
  `{category_type, raw_category_key, context: evidence}`.
- `searchCategoryEmbedder` — reuses `newSearchEmbedder()` and
  `kbsearch.SemanticSearchEnabled()`. Returns `ok=false` (lexical-only) when
  unconfigured or dimension mismatches.
- Cosine threshold from `CATEGORY_MATCH_MIN_COSINE` (default `0.80`).

**`llmCategoryCreator`** tries the primary model first, falls back to
`CREATE_ARTIFACT_CATEGORY_FALLBACK` on error (mirrors the metric enrichment pattern).

## Changed Files

### `metric_indexing.go`

- Removed `upsertMetricArtifactCategory` (old bare `ON CONFLICT (category_key)`
  insert — broken after the migration swaps to `UNIQUE(category_type, category_key)`).
- Added `metricCategoryResolver` interface so tests inject a fake without hitting
  the DB or LLM.
- `upsertMetricCategoryInstances` signature changed:
  ```go
  // before
  func upsertMetricCategoryInstances(ctx, db, recordID, metrics, logger)
  // after
  func upsertMetricCategoryInstances(ctx, db, recordID, metrics, resolver, logger)
  ```
- `IndexMetricsForRecord` now builds a real resolver via
  `newMetricCategoryResolver(db, logger)` before calling `upsertMetricCategoryInstances`.
- Each metric's `SearchDocument` is passed as `evidence["search_document"]` to the
  resolver, giving the LLM create call disambiguation context.

## Tests

| File | Tests | What they cover |
|---|---|---|
| `artifact_category_registry_test.go` | 10 | All pure helpers (normalize, match-keys, search-doc, parse, snapshot match tiers, canonical resolution) |
| `artifact_category_registry_db_test.go` | 3 | `loadActiveCategories`, `mintCategory`, `absorbAlias` (sqlmock) |
| `artifact_category_resolver_test.go` | 4 | Resolver: existing-hit (no LLM), create-on-miss, nil-creator guard, snapshot cache |
| `metric_indexing_test.go` | updated | `TestUpsertMetricCategoryInstancesResolvesAndUpserts` — verifies resolver is called with key and category_instance is upserted |

All 20 new/updated tests are green. The 4 pre-existing failures in the package
(`*SummaryLog`, `*InsertsMSUsed`) are unrelated (`entry_type` constraint issue)
and fail identically on baseline.

## Required Migration

`project_migrations/20260605000004_evolve_kb_artifact_categories_resolution.sql`
must run before the doc processor is started. It applies automatically via
`RunProjectMigrations` on startup. Key schema changes:

- Drops PK on `category_key`; adds `PRIMARY KEY (category_id)`.
- Adds `UNIQUE (category_type, category_key)` — the upsert conflict target.
- Adds columns: `aliases`, `acronyms`, `category_desc`, `category_keywords`,
  `match_keys`, `search_document` (already existed from migration 007).
- Adds GIN indexes on `match_keys` (containment) and
  `to_tsvector('simple', search_document)` (FTS).
- Backfills `match_keys` from `category_key` for existing rows.

## Environment Variables

| Var | Required | Default | Purpose |
|---|---|---|---|
| `CREATE_ARTIFACT_CATEGORY_PROMPT` | Yes | — | Path to `prompts/prompt-create-artifact-category-v1.md` |
| `CREATE_ARTIFACT_CATEGORY_MODEL_NAME` | Yes | — | Primary LLM for category creation |
| `CREATE_ARTIFACT_CATEGORY_FALLBACK` | No | — | Fallback model on primary failure |
| `CATEGORY_MATCH_MIN_COSINE` | No | `0.80` | Semantic acceptance threshold |
| `EMBEDDING_MODEL_NAME` | No | — | Enables tier-3 semantic matching |

When `CREATE_ARTIFACT_CATEGORY_MODEL_NAME` is missing, the resolver logs a warning
and returns an error for any category that is not already in the DB (no panic).

## Known Caveats

- **Inventory extraction is broken** until its `ON CONFLICT (category_key)` sites in
  `inventory_category_registry.go` are updated to `ON CONFLICT (category_type, category_key)`.
  Do not run inventory item extraction after applying the migration until that is done.
- The new LLM-create and embedder calls are unit-tested via fakes; a live end-to-end
  metric extraction run is the real first integration test.

## References

- [category-mgmt-spec.md](category-mgmt-spec.md) — canonical spec
- [extract-metrics-spec.md](../doc-processor/extract-metrics-spec.md) — how metrics delegate to Identify
- [prompts/prompt-create-artifact-category-v1.md](../../../ChenWeb/prompts/prompt-create-artifact-category-v1.md) — LLM prompt
