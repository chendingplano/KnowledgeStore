# Bug: Artifact Categories

**Date:** 2026-06-15 \
**Status:** Active \
**Component:** ChenWeb \
**Tags:** bug, artifact categories
---

## Bug 01
Date: 2026/06/15

### Symptom

There are two entries in `kb.artifact_categories` whose `category_key` are:
* 'seed germination index'
* 'plant seed germination index'

These two entries should be merged.

### Reproduction

Process two artifacts whose extracted category keys are surface-form variants of
the same concept (e.g. one yields `seed germination index`, another yields
`plant seed germination index`). Each variant mints its own category row.

### Root Cause

Category resolution is **exact-match only**. The resolver normalizes the raw key
(lowercase, collapse non-alphanumerics to single spaces — `normalizeCategoryKey`)
and looks it up in the process-wide hashmap (`categoryIndex`). The two keys
normalize to *different* strings (`seed germination index` ≠
`plant seed germination index`), so both miss the index and each triggers a
`CREATE_ARTIFACT_CATEGORY` LLM call that mints a separate row.

There is no automatic semantic/fuzzy dedup in the resolution path: the
embedding/cosine-similarity tier was deliberately removed in the 2026-06-07
"Category Resolution Redesign". The only dedup that exists is:
- **Exact-normalized repeats** — caught by the hashmap / `match_keys`.
- **Known surface forms** — display_names/aliases/acronyms the LLM returns at
  create time, plus the original raw key absorbed as the "translation cache".

A paraphrase the LLM did not list as an alias is invisible to all of these, so it
becomes a new category. This is the case here: neither row carries the other's key
in its `match_keys`.

### Diagnostic evidence (DevTools)

How the hashmap is built and updated (this is what determines whether two keys
collapse to one category):

- **Structure** — `globalCategoryIndex`, a process-wide singleton:
  `map[categoryType]map[normalizedKey]int64`, guarded by a `sync.RWMutex`.
  Files: `categoryIndex` / `loadIntoIndex` in
  `ChenWeb/server/api/doc-processing/artifact_category_registry.go`;
  `categoryResolver` in
  `ChenWeb/server/api/doc-processing/artifact_category_resolver.go`.
- **Built lazily, per `category_type`** — not at startup. The first
  `Resolve`/`ResolveBatch` for a type runs `loadIntoIndex`: query
  `kb.artifact_categories` for that type where
  `status IN ('approved','pending_review')`, `ORDER BY seen_count DESC`, and
  insert every `match_keys` entry (canonical key + display_names + aliases +
  acronyms) → `category_id`. `markLoaded` then prevents re-loading for the
  process's lifetime.
- **Updated at runtime, three ways:**
  1. *On create (miss):* `createAndMint` `put`s the canonical key, all LLM-returned
     surface forms, **and the original raw key** into the index.
  2. *On hit:* the key is already indexed; `absorbAlias` only persists it into the
     DB row's `match_keys` (idempotent) so future process loads see it.
  3. *On conflict (same key → different id):* the higher-`seen_count` entry wins
     (hence the `ORDER BY seen_count DESC` on load); the conflict is logged to
     `kb.category_alias_conflicts`.
- **Limitations relevant to this bug:**
  - *No fuzzy/semantic matching* → paraphrases are not collapsed (the direct cause).
  - *No eviction / no TTL / no live refresh* → once loaded, the index only grows.
  - *`canonical_of` is not followed by the index resolution path* → even a DB-level
    merge is not honored by resolution until process restart, and not at all unless
    the merged form is also added to the survivor's `match_keys`.

### Fix

Two layers — data fix now, prevention later:

1. **Merge the existing rows (data fix).** Keep one canonical row (prefer the one
   with the higher `seen_count` / the more general key) and:
   - add the loser's `category_key` to the survivor's `match_keys` (so future exact
     lookups of either surface form resolve to the survivor), and
   - repoint the loser's `kb.category_instance` rows and any
     `belong-to-category` edges to the survivor, then retire the loser
     (`status = 'merged'`, `canonical_of = <survivor key>`).
   - Restart the affected process (or invalidate the index) so the stale in-memory
     mapping is rebuilt — the index does not refresh live.

2. **Prevention (proposed, not yet implemented).** Resolution is exact-match by
   design; semantic dedup belongs out of the hot path. Options, in order of
   preference:
   - Have the `CREATE_ARTIFACT_CATEGORY` prompt return a richer alias set so common
     paraphrases land in `match_keys` at birth.
   - Add an **offline** near-duplicate sweep over `kb.artifact_categories`
     (embedding/lexical similarity) that proposes merges for human review via
     `kb.category_alias_conflicts`, rather than reintroducing similarity into the
     synchronous resolver.

### Why it is safe

The data fix is additive on the survivor (`match_keys` append is idempotent) and
only retires the loser after its instances/edges are repointed, so no membership is
lost. The prevention options either enrich create-time aliases (no resolution-path
change) or run offline (no latency/cost added to the hot path).

### Verification

Pending — fix not yet applied. After the data fix: resolving either
`seed germination index` or `plant seed germination index` returns the single
survivor `category_id`, and `kb.category_instance` has no rows pointing at the
retired row.

### Related fixes (found while diagnosing; not the cause)

- ADR `2026061502-adr-artifact-categories`: entity names are no longer treated as
  categories; categories now come from `kb.entities.categories` /
  `kb.relations.categories`. Unrelated to this duplication but touches the same
  resolution path.

### Lessons / Notes

- Exact-match resolution trades recall for determinism and zero hot-path LLM/embedding
  cost; the price is paraphrase duplicates like this one. Dedup must be handled either
  at create time (aliases) or offline (review-gated merges), never silently in the
  resolver.
- The in-memory index is per-process and never refreshes after load; any DB-level
  merge/rename requires an index rebuild (restart) to take effect.
