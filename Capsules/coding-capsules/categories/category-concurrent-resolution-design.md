# Concurrent Artifact Category Resolution — Design Draft

> Status: **proposal**. Extends `category-mgmt-spec.md` (§3 Identify Artifact
> Categories, §4 Create New Artifact Categories). If accepted, fold §§3–5 below
> back into that spec as a new "Concurrent Resolution" section.

## 1. Problem

`Identify Artifact Categories` resolves one `(category_key, category_type)` at a
time. On a true miss it creates the category with an **LLM call** (§4). Callers —
the metrics indexer and the inventory-item curator — loop over their keys and
call the resolver once per key, so every miss is a **sequential** LLM round-trip.
A document with 40 novel categories pays 40 serial LLM latencies inside one
record's Phase C indexing.

Three forms of concurrency already exist and must be handled:

1. **Within a processor** — many keys per record (today: serial).
2. **Within a pipeline** — multiple processors mint categories.
3. **Across pipelines** — one `doc-processor` process handles many documents
   concurrently, with overlapping keys.

**Phase C consolidation (decided).** All `kb.artifact_categories` resolution
happens in **Phase C (post-process), once per record**, after every doc
processor for the record has finished. Metrics already resolves there
(`extract-metrics-spec.md` §Indexing); **inventory items is being ported to
Phase C** as well, replacing the in-Phase-B `CurateObservedCategories` /
`kb.inventory_categories` path with the unified resolver against
`kb.artifact_categories`. Both processors' keys are therefore gathered into a
**single batched `Resolve` call per record**. This collapses concurrency
dimension #2 — the two processors no longer race; their keys arrive in one batch
and are deduped up front (Phase 0). After consolidation, in-process coalescing
(single-flight, §4) only has to handle dimension #3 (cross-pipeline).

The existing upsert (`ON CONFLICT (category_type, category_key) DO NOTHING` +
re-select, spec §"Idempotency & Concurrency") already makes all three **correct**.
What it does *not* do is dedupe the **LLM work**: N workers racing on the same
new key each pay for a full creation call, and all but one are wasted.

The fix therefore needs two things the current design lacks:

- **Parallelism** — fan the per-key creates out across a bounded worker pool
  instead of a serial loop.
- **Coalescing** — collapse duplicate in-flight creates (same `(type, k)`) to a
  single LLM call, across keys-in-a-batch, across processors, and across
  pipelines in the same process.

## 2. Goals / Non-Goals

**Goals**

- Turn the per-record create latency from `Σ keys` into `≈ ceil(misses / W)`
  LLM round-trips (W = worker count).
- Make exactly one LLM call per distinct novel `(type, k)` per process, even when
  many goroutines request it at once.
- Preserve every correctness property already specified: idempotent upsert,
  alias absorption, `merged` canonicalization, reprocess safety.
- No schema changes. This is an in-process restructuring of the resolver plus a
  new batch entry point.

**Non-Goals**

- Cross-replica LLM dedup. `doc-processor` is single-instance today (capsule
  §7.3 "Single-instance constraint"); the DB upsert remains the cross-replica
  safety net. A future multi-replica deployment can add a Postgres advisory lock
  (§6) without changing this design's shape.
- Re-specifying inventory extraction. This document covers only *where and how*
  inventory category resolution runs (Phase C, via the unified resolver). The
  mechanics of porting inventory off `kb.inventory_categories` belong in
  `extract-inventory-items-spec.md`.
- Changing the LLM prompt or category schema. (Micro-batching the LLM call is
  offered as an *optional* enhancement in §7, off by default.)

## 3. Batch Entry Point

Add a batch resolver alongside the existing single-key function. The single-key
function becomes a thin wrapper (`Resolve` with a one-element slice) so existing
callers keep working.

```go
type CategoryRequest struct {
    Type    string            // category_type, e.g. "metric", "inventory_item"
    Key     string            // raw, pre-normalization key
    Context *CategoryContext  // optional disambiguation payload (§4 LLM input)
}

// CatKey is the dedup identity: normalized key within a type.
type CatKey struct{ Type, K string }

type CategoryResolver interface {
    // Resolve returns exactly one resolved (canonical) row per distinct
    // (Type, normalized Key). The map is keyed by CatKey; callers re-expand to
    // their own per-request granularity.
    Resolve(ctx context.Context, reqs []CategoryRequest) (map[CatKey]ArtifactCategory, error)
}
```

**Caller change — one batch per record in Phase C.** The Phase C post-process
step gathers keys from *every* category-minting processor for the record into a
**single** `[]CategoryRequest` and calls `Resolve` once:

- metrics contributes its `(k, "metric")` pairs across all metrics (replacing the
  per-key `Identify` loop at `extract-metrics-spec.md` §"Metric and Artifact
  Categories"),
- inventory contributes its `(k, "inventory_item")` pairs (the ported Phase C
  path).

The resolver returns `map[CatKey]ArtifactCategory`; each processor then re-expands
the map onto its own `kb.category_instance` upserts (metrics keyed on
`metric_id`, inventory on `inventory_item_id`). Because both processors' keys
share one batch, Phase 0 dedup makes them converge with no inter-processor race
(concurrency dimension #2 removed).

## 4. Resolution Pipeline (batched)

`Resolve` runs the same layered logic as spec §3, but batched and with the slow
layer fanned out. Cheapest, most deterministic layers first.

**Phase 0 — Normalize & dedup.** Normalize every `Key` (spec §3.1) to `k`,
producing the distinct set of `CatKey`. Remember the request→CatKey mapping for
re-expansion. All later work is per distinct `CatKey`.

**Phase 1 — Batch exact/alias match (1 query per type).** Group distinct keys by
`Type`. For each type, one query resolves *all* of its keys at once:

```sql
SELECT * FROM kb.artifact_categories
WHERE category_type = $1
  AND match_keys ?| $2;        -- $2 = text[] of all normalized keys for this type
```

`match_keys` already holds the canonical key plus every alias/acronym (spec
§2.1), so this single GIN lookup covers exact and alias hits. Locally intersect
each row's `match_keys` with the batch set to map `k → row`. Keys with a hit are
done (→ Phase 4 canonicalize). This collapses N deterministic lookups into one
query per type.

**Phase 2 — Hybrid semantic match (LLM-free, concurrent).** Remaining keys
(deterministic miss) each run the hybrid lexical+semantic RRF search of spec §3.3.
These are independent and LLM-free, so run them through a bounded worker pool
(`CATEGORY_RESOLVE_MAX_CONCURRENCY`, default `8`). On accept, perform the
idempotent **alias absorption** update (spec §3.3 / §"Idempotency") so the next
lookup hits Phase 1. Map `k → row`; the rest fall through to Phase 3.

**Phase 3a — Intra-batch alias convergence (cluster-before-create).** Before
creating anything, collapse miss-keys that are aliases of *each other*. The
deterministic and hybrid layers (Phases 1–2) only compare against rows that
**already exist**, so two keys that are both novel *and* synonyms (e.g.
`response time` and `response latency` emitted by the same document) would each
miss and mint a separate canonical row — a duplicate the spec's "self-heal" only
fixes *after* one exists. To prevent that:

1. Take the true-miss keys for a given `category_type`.
2. **Embed them in one batch embedding call** — these embeddings are needed for
   the new rows' `search_document`/`embedding` anyway, so this adds no extra
   round-trip beyond the batch embed.
3. **Cluster** by cosine ≥ `CATEGORY_MATCH_MIN_COSINE` (the existing `0.80`
   threshold), union-find over the miss-keys.
4. Per cluster, pick one **representative** key; the other members are recorded
   as **aliases** of it.

Only one LLM create runs per cluster (Phase 3b), and the cluster's other members
are folded into the created row's `match_keys` (the same idempotent alias-absorb
update used in Phase 2). Clustering is done **up front** so creation stays fully
parallel — there is no "k2 waits for k1" serialization. Keys whose alias
relationship falls *below* the cosine threshold are not caught here; they fall
through to the cross-batch reconciliation in §5.

**Phase 3b — Create (LLM), concurrent + single-flight.** This is the slow layer
and the whole point of the redesign. One create per cluster representative from
Phase 3a, fanned out concurrently.

```go
var createGroup singleflight.Group   // process-wide, keyed by Type\x00k

func (r *resolver) createOne(ctx context.Context, ck CatKey, c *CategoryContext) (ArtifactCategory, error) {
    ch := createGroup.DoChan(ck.Type+"\x00"+ck.K, func() (any, error) {
        // Re-check the deterministic layer first: a sibling worker (or another
        // pipeline) may have created it microseconds ago.
        if row, ok := r.exactMatch(r.bgCtx, ck); ok {
            return row, nil
        }
        row, err := r.llmCreateAndUpsert(r.bgCtx, ck, c) // §4 of spec, unchanged
        return row, err
    })
    select {
    case <-ctx.Done():
        return ArtifactCategory{}, ctx.Err() // this caller gave up; work continues for others
    case res := <-ch:
        return res.Val.(ArtifactCategory), res.Err
    }
}
```

Key properties:

- **Bounded fan-out.** The cluster representatives are submitted to the same
  `CATEGORY_RESOLVE_MAX_CONCURRENCY` worker pool, so create latency for the
  record is `≈ ceil(clusters / W)` round-trips instead of `misses`.
- **Single-flight coalescing.** `singleflight.Group` keyed by `(Type, k)`
  guarantees **one** LLM call per distinct novel key *for the whole process* —
  collapsing duplicates across keys-in-batch, across `extract_metrics` /
  `extract_inventory_items`, and across concurrently-running pipelines. This is
  the cross-processor / cross-pipeline win the bare DB upsert cannot give.
- **`DoChan` + per-caller `select`.** The shared work runs under a
  resolver-scoped background context (`r.bgCtx`, derived once, not tied to any
  single caller), so a stop/cancel in *one* pipeline does not poison a create
  shared by another. Each caller still honors its *own* `ctx` for giving up.
- **Re-check before LLM.** Inside the flight, re-run the cheap exact match first;
  this catches the case where another worker just persisted the row.
- **`llmCreateAndUpsert` is unchanged** from spec §4: re-normalize the returned
  key, build `match_keys` / `search_document` / `embedding`, then
  `INSERT … ON CONFLICT (category_type, category_key) DO NOTHING` + re-select.
  The upsert stays as the **last-line** idempotency for any race singleflight
  can't see (future multi-replica).

**No row is ever overwritten.** Create is `DO NOTHING` (not `DO UPDATE`): the
first writer's body wins, and a later concurrent writer's `INSERT` is a silent
no-op whose re-`SELECT` returns the *same surviving row*. Two pipelines minting
the same key therefore converge on one `category_id`; the later pipeline does not
clobber the earlier one, and its LLM body is discarded. The only `UPDATE` in the
flow is alias absorption, which is *additive* (`match_keys` append), never a
replace.

**Phase 4 — Canonicalize & counters.** For every resolved row, follow
`canonical_of` if `status = 'merged'` (spec §3.5) so instances never point at a
retired category. Bump `seen_count` / `last_seen_at` best-effort in **one**
batched statement:

```sql
UPDATE kb.artifact_categories
SET seen_count = seen_count + 1, last_seen_at = now()
WHERE category_id = ANY($1);
```

**Phase 5 — Re-expand.** Build `map[CatKey]ArtifactCategory` and return; callers
fan it back out to their per-metric / per-item `kb.category_instance` upserts
(unchanged, still keyed on `(category_id, artifact_id)`).

## 5. Concurrency & Idempotency Summary

| Race | Mechanism |
|---|---|
| Same key twice in one batch | Phase 0 dedup |
| Two *novel synonym* keys in one batch | Phase 3a cluster-before-create (one create per cluster) |
| Same key from two processors in one pipeline | one Phase C batch → Phase 0 dedup (no race) |
| Same key from two concurrent pipelines (same process) | process-wide `singleflight` (Phase 3b) |
| Same key from two processes / replicas | DB upsert `ON CONFLICT DO NOTHING` + re-select (first-write-wins, no overwrite) |
| Two *novel synonym* keys across batches/pipelines | not coalesced; reconciled by alias-absorb on next lookup or offline merge (`status='merged'` + `canonical_of`) |
| Alias re-observed | conditional idempotent `match_keys` update (Phase 2 / 3a) |
| Reprocess same record | all writes are upserts → no duplicates |

The only behavior change versus today is **ordering and parallelism**; every
write remains an upsert (create is `DO NOTHING`, alias-absorb is additive), so
the spec's "Reprocessing a record is safe" guarantee holds unchanged, and a later
writer never overwrites an earlier category body.

**Cross-batch synonym tail.** Two *different* novel surface forms that are
synonyms but land in *separate* concurrent batches (e.g. one per pipeline) are
not coalesced — each mints its own row in the rare simultaneous-miss window.
This is reconciled after the fact: once one row is canonical, the other is
absorbed as an alias on its next lookup (Phase 2), or an offline merge sets
`status='merged'` + `canonical_of`, which Phase 4 redirects through. Categories
are usable the moment they exist regardless of duplication (spec §3 status note),
so this is a quality nuisance, not a correctness defect.

## 6. Configuration

| Env var | Default | Purpose |
|---|---|---|
| `CATEGORY_RESOLVE_MAX_CONCURRENCY` | `8` | Max concurrent hybrid searches + LLM creates across the whole resolver. |
| `CATEGORY_MATCH_MIN_COSINE` | `0.80` (existing) | Reused as the Phase 3a intra-batch clustering threshold, so synonym detection within a batch matches the existing-row accept threshold. |
| `CREATE_ARTIFACT_CATEGORY_MODEL_NAME` / `_FALLBACK` / `_PROMPT` | (existing) | Unchanged — the per-cluster create call. |
| `CATEGORY_CREATE_BATCH_SIZE` | `1` (off) | Optional micro-batching (§7). `1` = one key per LLM call. |

Set `CATEGORY_RESOLVE_MAX_CONCURRENCY = 1` to fall back to fully serial behavior
(useful for debugging or rate-limited model endpoints), mirroring the
`RUN_DOC_PROCESSOR_CONCURRENT=false` escape hatch in the capsule.

**Multi-replica note.** If `doc-processor` is ever scaled out, add a Postgres
transaction-level advisory lock keyed on `hashtext(category_type || '\x00' || k)`
around `llmCreateAndUpsert` so cross-replica creates also coalesce to one LLM
call. Until then the in-process `singleflight` + DB upsert is sufficient, and the
correctness guarantees do not depend on it.

## 7. Optional Enhancement — Micro-Batched LLM Create

The §3–§5 design keeps **one key per LLM call** but runs them concurrently. A
further latency/cost lever is to send several missing keys to **one** LLM call
that returns an array of category definitions, gated by
`CATEGORY_CREATE_BATCH_SIZE` (e.g. `5`). This trades round-trips for prompt size.

Recommendation: ship §3–§5 first (concurrent fan-out + single-flight) and keep
micro-batching off by default. The metrics multi-pass spec already documents the
failure modes of overloading a single LLM call (partial JSON, schema overload on
smaller models); only enable batching after measuring that creation round-trips —
not per-call latency — are the dominant cost, and keep the per-key path as the
fallback when a batch response is malformed.

## 8. Rollout

1. Implement `Resolve` (batch) + Phase 3a clustering + single-flight; keep the
   single-key function as a one-element wrapper so nothing breaks.
2. Move the metrics indexer to gather keys and call `Resolve` once in Phase C.
3. **Port inventory category admission to Phase C**: drop the in-Phase-B
   `CurateObservedCategories` / `kb.inventory_categories` path and contribute
   `(k, "inventory_item")` keys to the same per-record Phase C batch. (Tracked in
   `extract-inventory-items-spec.md`.)
4. Default `CATEGORY_RESOLVE_MAX_CONCURRENCY=8`; verify against a document with
   many novel categories that (a) LLM creates now overlap, (b) intra-batch
   synonyms collapse to one row (Phase 3a), and (c) re-running the record — and
   running two pipelines that share keys — produces zero duplicate
   `kb.artifact_categories` rows.
5. (Optional, later) Evaluate `CATEGORY_CREATE_BATCH_SIZE` and the multi-replica
   advisory lock.

## 9. Implementations
Refer to KnowledgeStore/Capsules/coding-capsules/categories/category-concurrent-resolution-impl.md
for its implementations.

## References

- `category-mgmt-spec.md` — §3 Identify, §4 Create, §"Idempotency & Concurrency"
- `doc-processor/+CAPSULE.md` — §7.3 Pipeline Execution Model, single-instance note
- `doc-processor/extract-metrics-spec.md` §"Metric and Artifact Categories"
- `doc-processor/extract-inventory-items-spec.md` §"Automatic Category Admission"
- `golang.org/x/sync/singleflight`
