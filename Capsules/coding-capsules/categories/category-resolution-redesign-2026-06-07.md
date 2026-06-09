# Category Resolution Redesign — 2026-06-07

## 1. Motivation

The current Identify Artifact Categories implementation has four problems:

1. **Chinese (non-English) keys always fall through to LLM create.** `normalizeCategoryKey` preserves CJK characters; no translation happens before the match attempt. A concept that already exists under its English key (e.g., `modem`) triggers a redundant LLM call when the input key is `调制解调器`.

2. **Per-resolver snapshot means concurrent pipelines waste LLM calls.** Each `categoryResolver` loads an independent snapshot at construction time. Two pipelines running concurrently both miss a novel key and both attempt LLM creation. The DB `ON CONFLICT` prevents duplicate rows but does not prevent duplicate LLM calls.

3. **Alias absorption does not update the in-memory snapshot.** `absorbAlias` writes to the DB but not to `cr.snapshot`, so the same alias encountered twice in one pass re-runs the full match logic instead of hitting the deterministic tier.

4. **Cosine matching compares incompatible vector spaces.** The stored `embedding` is computed from the full `search_document` (key + aliases + keywords + description). The query embedding is computed from a single short phrase. Cosine scores are systematically lower than the 0.80 threshold for valid synonyms, making tier-3 unreliable in practice.

This document describes the redesigned resolution algorithm that fixes all four problems.

## 2. Design Goals

- Exact/alias matching must be O(1) per key, not O(N) scan.
- All pipelines in the same process share one resolution index.
- Non-English keys are handled without a separate translation step on the hot path.
- No embedding or cosine similarity in the resolution path.
- Alias conflicts are detected and logged but never block extraction.
- LLM failures are logged and deferred to a future reconciliation module.

## 3. Algorithm

**Input:** `(rawKey, categoryType, evidence)`
**Output:** `category_id` (or error)

```
1. normKey = normalizeCategoryKey(rawKey)
   Return error if normKey == ""

2. id, status = globalCategoryIndex.lookup(categoryType, normKey)
   → SINGLE MATCH: return id
   → MULTI-MATCH:  pick id with highest seen_count, upsert to kb.category_alias_conflicts, return id
   → MISS:         proceed to step 3

3. via singleflight (categoryCreateGroup, key = categoryType+"\x00"+normKey):
   a. Call LLM: creator.CreateCategory(ctx, normKey, categoryType, evidence)
      → FAILURE: log error, set llm_status='failed', return error
   b. mintCategory(created, categoryType)  — ON CONFLICT (category_type, category_key) DO UPDATE seen_count+1
   c. globalCategoryIndex.put(categoryType, canonical_key, id)
   d. globalCategoryIndex.put(categoryType, normKey, id)        ← rawKey as absorbed alias
   e. globalCategoryIndex.putAll(categoryType, aliases+acronyms+display_names, id)
   f. absorbAlias(db, id, normKey)   ← write rawKey into match_keys in DB
   g. return id
```

Notes:
- Step 3d is the translation mechanism: the LLM returns an English `canonical_key`; the original `normKey` (which may be Chinese) is stored as an alias, so future occurrences hit step 2 directly.
- The `singleflight` callback uses `context.WithoutCancel(ctx)` so one caller cancelling does not abort a create that other callers are waiting on.
- The hashmap entry is written only after `mintCategory` succeeds; a failed LLM call leaves no entry in the hashmap, allowing retry on the next pipeline run.

## 4. Process-Wide Category Index

A package-level singleton in `docprocessing`:

```go
var globalCategoryIndex = newCategoryIndex()

type categoryIndex struct {
    mu     sync.RWMutex
    loaded map[string]bool              // categoryType → loaded from DB
    byType map[string]map[string]int64  // [categoryType][normalizedKey] → categoryID
}
```

### 4.1 Lazy Load

On the first `lookup` for a given `categoryType`, load all `approved ∪ pending_review` rows from `kb.artifact_categories` and populate the inner map from each row's `match_keys` array. If two rows share a `match_keys` entry, record the conflict (see §5) and keep the entry with the higher `seen_count`. The load is protected by the write lock.

### 4.2 Updates

After every successful `mintCategory` or `absorbAlias`, update the hashmap under the write lock. This keeps the in-memory index consistent with the DB without requiring a reload.

### 4.3 Concurrency

Read path (`lookup`) uses `RLock`. Write path (`put`, `putAll`) uses `Lock`. The existing `categoryCreateGroup singleflight.Group` coalesces concurrent goroutines attempting to create the same `(categoryType, normKey)` so only one LLM call is made per novel key per process lifetime.

### 4.4 Cross-Process Behavior

Each process instance has its own `globalCategoryIndex`. Concurrent processes (separate server replicas) may independently create the same novel category; `mintCategory`'s `ON CONFLICT (category_type, category_key) DO UPDATE seen_count+1 RETURNING category_id` returns the surviving row to both, so they converge on the same `category_id` without a DB conflict error. Each process adds the returning `category_id` to its own hashmap.

## 5. Alias Conflict Detection

### 5.1 New Table

```sql
CREATE TABLE kb.category_alias_conflicts (
    alias         text NOT NULL,
    category_type text NOT NULL,
    category_ids  int8[] NOT NULL,
    detected_at   timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT category_alias_conflicts_pkey PRIMARY KEY (category_type, alias)
);
```

### 5.2 Detection Points

Conflicts are detected and logged (upsert on the primary key) at two points:

1. **Hashmap load** (§4.1): two `kb.artifact_categories` rows share a key in their `match_keys` arrays.
2. **Hashmap update** (§4.2): a key being written already maps to a different `category_id`.

At both points: upsert to `kb.category_alias_conflicts` with the full set of conflicting IDs; retain the entry with the highest `seen_count` in the hashmap.

### 5.3 Conflict Resolution

Conflict resolution is deferred to the future background reconciliation module (see §7). During normal operation, the extraction pipeline always resolves a conflict to a single `category_id` (highest `seen_count`) and continues without blocking.

## 6. LLM Failure Handling

If `creator.CreateCategory` returns an error:

- Set `llm_status = 'failed'` and write `llm_error` on the placeholder row (if a placeholder was already inserted by a prior attempt; otherwise no DB write is needed).
- Log the error with `categoryType` and `normKey`.
- Return an error to the caller. The caller (artifact indexing) logs and skips the category for the current artifact — the artifact is still indexed, just without this category instance.
- No hashmap entry is written. The next pipeline run will attempt creation again.

Persistent failures (e.g., model outage, malformed output) accumulate as `llm_status = 'failed'` rows and are handled by the future reconciliation module.

## 7. Future: Background Reconciliation Module

Out of scope for this change. Will handle:

- `llm_status = 'failed'` rows — retry LLM enrichment or escalate to human review.
- `kb.category_alias_conflicts` rows — merge duplicate categories, update `canonical_of`, set `status = 'merged'`.
- Manual review of `status = 'pending_review'` categories.

## 8. Changes to Existing Code

### 8.1 Removals

| Location | What is removed |
|---|---|
| `artifact_category_registry.go` | `matchCategoryInSnapshot` tier-3 cosine branch, `categoryCosine`, `categoryEmbeddingMinDims` |
| `artifact_category_resolver.go` | `clusterCategoryMisses`, `embedKeys`, all `categoryEmbedder` interface usage and fields |
| `artifact_category_wiring.go` | `searchCategoryEmbedder`, `newSearchCategoryEmbedder`, `EmbedCategory` |

The `categoryEmbedder` interface is deleted. `newCategoryResolver` no longer accepts an embedder parameter.

### 8.2 Modifications

| Location | What changes |
|---|---|
| `artifact_category_resolver.go` | Replace `cr.snapshot` / `cr.byKey` / `cr.loaded` fields with a call to `globalCategoryIndex`; update `Resolve` and `ResolveBatch` to use the new lookup; update `createAndMint` to write back to `globalCategoryIndex` after `mintCategory` |
| `artifact_category_registry.go` | Add `categoryIndex` type and `newCategoryIndex()` constructor; add `loadIntoCategoryIndex(ctx, db, categoryType)` |
| `artifact_category_wiring.go` | Remove embedder construction from `newMetricCategoryResolver` |

### 8.3 New Code

| Location | What is added |
|---|---|
| `artifact_category_registry.go` | `categoryIndex` struct and methods: `lookup`, `put`, `putAll`, `ensureLoaded` |
| `artifact_category_registry.go` | `logAliasConflict(ctx, db, categoryType, alias, ids)` — upserts to `kb.category_alias_conflicts` |
| `project_migrations/` | New goose migration: `CREATE TABLE kb.category_alias_conflicts …` |

## 9. Spec Updates Required in category-mgmt-spec.md

| Section | Update needed |
|---|---|
| §3, Step 1 | Remove "translate if not English" as a separate step. Clarify: the rawKey is normalized as-is (CJK preserved); translation is a side-effect of LLM create (§4.3). |
| §3, Step 3 | Replace "Hybrid semantic match" with "Process-wide hashmap lookup" as described in this document. Delete FTS, pgvector, and RRF references from the resolution path. |
| §3, Step 4 | Update "Create-or-enqueue" to reflect the new two-stage flow with rawKey alias absorption. |
| §4.3 | Add rawKey alias absorption to Stage A / Stage B description. |
| New §4.x | Document `globalCategoryIndex` and its lifecycle. |
| New §4.x | Document `kb.category_alias_conflicts` and conflict resolution policy. |

## 10. References

- [category-mgmt-spec.md](category-mgmt-spec.md) — canonical spec (to be updated)
- [category-mgmt-impl.md](category-mgmt-impl.md) — prior implementation notes
- [artifact_category_resolver.go](../../../../ChenWeb/server/api/doc-processing/artifact_category_resolver.go)
- [artifact_category_registry.go](../../../../ChenWeb/server/api/doc-processing/artifact_category_registry.go)
- [artifact_category_wiring.go](../../../../ChenWeb/server/api/doc-processing/artifact_category_wiring.go)
