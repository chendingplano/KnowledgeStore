# Concurrent Artifact Category Resolution — Implementation

> Implements `category-concurrent-resolution-design.md` for the **metric** path.
> Inventory will be ported to the same resolver later (same code, different
> `category_type`). This document describes the code as built.

## 1. Where the code lives

All in package `docprocessing` (`ChenWeb/server/api/doc-processing/`):

| File | Role |
|---|---|
| `artifact_category_resolver.go` | `categoryResolver`: single-key `Resolve` + batched `ResolveBatch`, `createAndMint`, `embedKeys`, `clusterCategoryMisses`, and the process-wide `categoryCreateGroup`. |
| `artifact_category_registry.go` | `artifactCategoryRegistry`: DB upserts (`mintCategory`), alias absorption (`absorbAlias`), snapshot load (`loadActiveCategories`), and the in-memory match helpers. Unchanged by this work except as a dependency. |
| `artifact_category_wiring.go` | Real LLM creator + embedder wiring; `categoryMatchMinCosine()` and the new `categoryResolveMaxConcurrency()`. |
| `metric_indexing.go` | Caller: `upsertMetricCategoryInstances` gathers one batch per record and calls `ResolveBatch`. |
| `artifact_category_batch_test.go` | Tests for clustering, batch dedup, synonym collapse, existing-match. |

Dependency added: `golang.org/x/sync/singleflight` (already in `go.sum`, promoted to a
direct require in `go.mod`).

## 2. Public surface

```go
// One raw key to resolve, with optional evidence passed to the create LLM on a miss.
type categoryRequest struct {
    RawKey   string
    Evidence map[string]any
}

// Resolves many keys of one category_type in a single concurrent pass.
// Returns normalizedKey -> category_id; unresolved keys are absent from ids and
// present in errs.
func (cr *categoryResolver) ResolveBatch(
    ctx context.Context,
    categoryType string,
    reqs []categoryRequest,
    maxConcurrency int,
) (ids map[string]int64, errs map[string]error)
```

The single-key `Resolve(ctx, rawKey, categoryType, evidence) (int64, error)` is
retained (it now delegates creation to `createAndMint`), so older call sites and the
existing resolver unit tests keep working. The metric caller uses only `ResolveBatch`.

The caller-facing interface in `metric_indexing.go` is narrowed to the batch method:

```go
type metricCategoryResolver interface {
    ResolveBatch(ctx context.Context, categoryType string, reqs []categoryRequest, maxConcurrency int) (map[string]int64, map[string]error)
}
```

## 3. Resolution pipeline (`ResolveBatch`)

Maps 1:1 onto the design's Phases 0–4.

1. **Phase 0 — normalize + dedup.** Each `RawKey` is run through
   `normalizeCategoryKey`; the distinct set is built preserving first-seen order and
   first-seen `Evidence`. Empty keys are dropped.

2. **Load snapshot once.** `ensureLoaded(categoryType)` populates the per-type
   in-memory snapshot (`approved ∪ pending_review`) via
   `artifactCategoryRegistry.loadActiveCategories`. A load error is reported against
   every key in the batch and `ResolveBatch` returns.

3. **Phase 1/2 — match existing.** `embedKeys` embeds all distinct keys through a
   bounded worker pool (`maxConcurrency`). Each key is then matched against the
   snapshot with `matchCategoryInSnapshot` (exact/alias via `match_keys`, then
   semantic cosine ≥ `cosineThreshold`). A hit is canonicalized
   (`resolveCanonicalCategory`, following `canonical_of` for `merged` rows), the new
   surface form is absorbed (`absorbAlias`), and the key maps to that id. Everything
   else becomes a **miss**.

4. **Phase 3a — cluster misses.** `clusterCategoryMisses(missVecs, cosineThreshold)`
   greedily groups misses whose embeddings are within `cosineThreshold` of a cluster
   representative (first member). Keys with no usable embedding each form their own
   cluster. This is what makes two *novel* synonyms in one batch collapse to a single
   create instead of two rows.

5. **Phase 3b — create per cluster, concurrently.** One goroutine per cluster, bounded
   by a `maxConcurrency` semaphore under a `sync.WaitGroup`. Each goroutine calls
   `createAndMint` for the representative, then `absorbAlias` for the remaining cluster
   members and maps them to the same id. Writes into the shared `ids`/`errs` maps are
   guarded by a local mutex. A create failure is recorded against every member of that
   cluster; sibling clusters are unaffected.

Canonicalization (design Phase 4) happens inline in step 3 for matches; created rows
are canonical by construction. `seen_count`/`last_seen_at` are bumped by
`mintCategory`'s `ON CONFLICT … DO UPDATE` (see §5).

## 4. Coalescing: `createAndMint` + `categoryCreateGroup`

```go
var categoryCreateGroup singleflight.Group // package-level, process-wide
```

`createAndMint` wraps **create → embed search_document → mint → addToSnapshot** in
`categoryCreateGroup.DoChan(categoryType+"\x00"+normKey, …)`:

- **One LLM call per novel key per process.** Concurrent callers for the same
  `(categoryType, normKey)` — across the metrics and (future) inventory processors and
  across concurrently-running pipelines — share a single flight. This is the
  cross-pipeline win the bare DB upsert cannot give.
- **Detached work context.** Inside the flight, work runs on
  `context.WithoutCancel(ctx)` so one caller abandoning its wait (e.g. a pipeline stop)
  does not cancel a create another pipeline is awaiting.
- **Per-caller cancellation preserved.** The outer `select` waits on the caller's own
  `ctx.Done()` vs the result channel, so each caller still honors its own deadline.
- **`addToSnapshot`** (mutex-guarded) makes a freshly minted category matchable by
  later keys reusing the same resolver instance.

`doc-processor` is single-instance, so the singleflight covers all concurrency that
exists today. For a future multi-replica deployment, add a Postgres advisory lock
around the mint (see design §6); correctness does not depend on it because of §5.

## 5. Idempotency / no-overwrite (unchanged, relied upon)

`artifactCategoryRegistry.mintCategory` is an upsert:

```sql
INSERT INTO kb.artifact_categories (...) VALUES (...)
ON CONFLICT (category_type, category_key) DO UPDATE SET
    seen_count = kb.artifact_categories.seen_count + 1,
    last_seen_at = NOW()
RETURNING category_id;
```

The conflict path **does not rewrite the category body** — it only bumps counters and
returns the surviving `category_id`. So a second writer (another process, or a race the
singleflight cannot see) converges on the first writer's row; the later LLM body is
discarded, never clobbering the earlier one. `absorbAlias` is additive and conditional
(`WHERE NOT (match_keys @> …)`), so concurrent absorbs are no-ops. Reprocessing a record
is therefore safe.

## 6. Configuration

| Env var | Default | Effect |
|---|---|---|
| `CATEGORY_RESOLVE_MAX_CONCURRENCY` | `8` | Bounds concurrent embeds + LLM creates per `ResolveBatch`. `1` = fully serial (debugging / rate-limited endpoints). |
| `CATEGORY_MATCH_MIN_COSINE` | `0.80` | Existing semantic accept threshold; **reused** as the Phase 3a clustering threshold. |
| `CREATE_ARTIFACT_CATEGORY_MODEL_NAME` / `_FALLBACK` / `_PROMPT` | — | Unchanged; the per-cluster create call. |

Helper: `categoryResolveMaxConcurrency()` in `artifact_category_wiring.go`.

## 7. Caller integration (`upsertMetricCategoryInstances`)

Per record, in Phase C:

1. Gather one `[]categoryRequest` across **all** metrics (`RawKey` = each
   `metric_categories` entry, `Evidence` = `{artifact_kind:"metric", search_document}`);
   metrics with empty `metric_categories` are logged and skipped.
2. `ids, errs := resolver.ResolveBatch(ctx, "metric", reqs, categoryResolveMaxConcurrency())`.
   Per-key errors are logged once.
3. For each metric, for each of its keys, look up `ids[normalizeCategoryKey(key)]` and
   upsert one `kb.category_instance` row (`ON CONFLICT (category_id, artifact_id)`).
   Unresolved keys are skipped (already surfaced via `errs`).

When inventory is ported, it contributes `(k, "inventory_item")` requests to the same
per-record Phase C batch using the identical `ResolveBatch` call.

## 8. Tests

`artifact_category_batch_test.go` (run with `-race`):

- `TestClusterCategoryMisses` — neighbors group; orthogonal vector stays separate;
  un-embeddable key gets its own cluster.
- `TestResolveBatchDedupCreatesOnce` — `Throughput` / `throughput` / `  THROUGHPUT `
  across metrics ⇒ exactly one create, all mapped to the minted id.
- `TestResolveBatchClustersSynonymsIntoOneCreate` — two novel near-neighbor keys ⇒ one
  create + one `absorbAlias`, both keys mapped to the same id (`maxConcurrency=1` keeps
  the single cluster's create→absorb order deterministic for sqlmock).
- `TestResolveBatchMatchesExistingWithoutCreate` — pre-existing snapshot row
  short-circuits create.

Test doubles: `programmableCategoryEmbedder` (per-text vectors), reused
`fakeCategoryCreator` / `fakeCategoryEmbedder`, and `sqlmock` for the registry.
`fakeMetricCategoryResolver` in `metric_indexing_test.go` implements `ResolveBatch`.

## 9. Known-unrelated test failures

Running the whole package also surfaces 4 failures in `doc_proc_log_store_test.go` and
the topics/summaries/chunking summary-log tests (`entry_type is not allowed`, from
`doc_proc_log_store.go`). Those source files are unmodified vs HEAD and reference no
category code — pre-existing breakage in the working tree, independent of this work.

## 10. References

- `category-concurrent-resolution-design.md` — the design this implements
- `category-mgmt-spec.md` — §3 Identify, §4 Create, §"Idempotency & Concurrency"
- `doc-processor/extract-metrics-spec.md` — §"Metric and Artifact Categories", §Indexing
