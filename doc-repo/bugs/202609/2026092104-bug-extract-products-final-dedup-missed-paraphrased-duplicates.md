# extract_products Deterministic Step B (final dedup) missed duplicate rows when Pass 2 paraphrased requirement_text differently across them

Date: 2026-09-21

Status: root-caused and fixed in the working tree; `go test ./server/api/doc-processing/...`
and `go vet` clean; not committed; existing duplicate rows in `kb.products` for record 416
left untouched at user's request (fix is forward-looking only).

Scope: `ChenWeb/server/api/doc-processing/extract-products.go` (`dedupeFinalProductRows`),
`ChenWeb/server/api/doc-processing/extract-products_test.go` (new regression tests), and
this capsule's spec, `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-products-spec.md`
(Deterministic Step B section).

Reported by: user, via two concrete duplicate rows in `kb.products`:
`product_rel_id = '416_prd_37'` and `'416_prd_42'`.

---

## 1. Summary

`extract_products`'s final dedup step (Deterministic Step B, per this capsule's spec) is
meant to catch accidental duplicate rows before they reach `kb.products`. Its dedup key
required an **exact match** (case/whitespace-trimmed only) on `canonical_name + relation_type
+ requirement_text`. Pass 2 is an LLM call that paraphrases `requirement_text` per row rather
than copying source text verbatim, so two rows enriched from the same or overlapping evidence
— same product, same `relation_type` — could end up with differently-worded
`requirement_text` strings and were never merged. Both landed in `kb.products` as distinct
rows.

## 2. Root cause

Evidence — the two reported rows, `kb.products` (record 416, `std_1503937.pdf`):

| field | `416_prd_37` | `416_prd_42` |
|---|---|---|
| `product_name`/`canonical_name` | 成品肥料 | 成品肥料 |
| `relation_type` | performance_requirement | performance_requirement |
| `product_type` | material | product_class |
| `evidence_lines` | `["123","124"]` | `["123"]` |
| `evidence_quote` | full 3-sentence paragraph (starts "机器成肥、太阳能辅助堆肥产出的成品肥料...") | exact first sentence of `416_prd_37`'s `evidence_quote`, verbatim |
| `requirement_text` | full 3-sentence paragraph | shorter paraphrase covering only the first two clauses |
| `confidence` | 0.95 | 0.90 |
| `create_time` | 2026-09-20 18:24:59.159116 | 2026-09-20 18:24:59.160551 (1.4ms later) |

Both rows trace to the same source sentence (`416_prd_42`'s `evidence_quote` is a byte-exact
substring of `416_prd_37`'s), same product, same `relation_type`, created 1.4ms apart in the
same Pass 2 run — but `requirement_text` differs because Pass 2 (model `deepseek-v4-flash`,
`prompt-enrich-product-mention-v2.md`) produced two different summarizations of the evidence,
one full-paragraph and one abbreviated.

`dedupeFinalProductRows` (`extract-products.go:1340`, before this fix) built its grouping key
as:

```go
key := strings.Join([]string{
    normalizedProductCandidateKey(canonical_name, product_name),
    strings.ToLower(strings.TrimSpace(relation_type)),
    strings.ToLower(strings.TrimSpace(requirement_text)),
}, "|")
```

Since the two rows' `requirement_text` strings differ, their keys differ, and the grouping
map treats them as unrelated rows — no merge, no dedup.

This is a narrower implementation than what this spec already called for at Step B: the
documented suggested key was `canonical_name + relation_type + normalized requirement_text +
evidence span cluster`. The code implemented literal (not truly normalized) `requirement_text`
equality and never used "evidence span cluster" as a signal at all — the one thing that would
actually have caught this pair (their `evidence_lines`, `["123","124"]` and `["123"]`,
overlap on line 123).

## 3. Blast radius

Any `extract_products` run where Pass 2 produces more than one row for the same
(`canonical_name`, `relation_type`) pair from overlapping evidence — e.g. because the
underlying candidate's evidence spans adjacent/overlapping blocks, or the LLM simply
summarizes the same evidence at two granularities within one Pass 2 response — is affected.
Not specific to record 416 or to this particular product; it's a property of Step B's dedup
key being too strict, not of any one document. Scale of the effect across historical runs was
not queried this session (would require scanning `kb.products` for rows sharing
`canonical_name`/`relation_type`/overlapping `evidence_lines` but differing `requirement_text`
across the whole table).

## 4. Fix implemented (uncommitted)

- `dedupeFinalProductRows` (`extract-products.go`) now groups rows by
  `canonical_name + relation_type` only, then clusters rows within a group whose
  `evidence_lines` sets overlap (share at least one line) — `evidence_lines` overlap is the
  reliable "same underlying fact" signal; `requirement_text` equality is not, given Pass 2's
  paraphrasing. On merge: the higher-`confidence` row's `requirement_text` (and
  `confidence`/`confidence_reason`) wins, `evidence_lines` are unioned, and `evidence_quote`
  is backfilled from whichever row has one if the surviving row's is empty.
- Two new tests added, `extract-products_test.go`:
  - `TestDedupeFinalProductRows_MergesOverlappingEvidenceWithDifferentRequirementText` —
    reproduces `416_prd_37`/`416_prd_42` verbatim as a failing case against the old code,
    passes against the fix.
  - `TestDedupeFinalProductRows_KeepsDistinctRelationsForSameProduct` — guards against
    over-merging: same product, different `relation_type`, non-overlapping evidence stays as
    two rows.
- Spec updated (`extract-products-spec.md`, Deterministic Step B section): documents the
  corrected dedup key and this bug.
- `go test ./server/api/doc-processing/...` and `go vet ./server/api/doc-processing/...`
  clean.
- Existing duplicate rows in `kb.products` (including `416_prd_37`/`416_prd_42`) intentionally
  left as-is — user asked not to touch existing records this session.

## 5. Tasks

- [x] Reproduce the reported duplicate with a regression test against the real row data
- [x] Identify the dedup key as the root cause (exact `requirement_text` match, no evidence-span
      signal)
- [x] Fix `dedupeFinalProductRows` to key on `canonical_name + relation_type` + evidence-line
      overlap
- [x] Add regression tests (duplicate-merge case and distinct-relation-type non-merge case)
- [x] Update this spec's Step B section
- [x] `go test`/`go vet` clean on the package
- [ ] Commit the `ChenWeb` code/test changes and the `KnowledgeStore` spec update (two separate
      repos, via `jj`) — user asked not to commit yet
- [ ] Decide whether to clean up existing `kb.products` duplicates (record 416 and any others)
      — deferred by user this session
- [ ] Consider scanning `kb.products` workspace-wide for other rows matching this pattern
      (same `canonical_name`/`relation_type`, overlapping `evidence_lines`, differing
      `requirement_text`) to size the historical blast radius — not done this session

## 6. Open questions / future related activities

- Whether merging on evidence-line overlap alone is ever too aggressive — e.g. a long block
  where two genuinely distinct requirements for the same product/relation_type happen to cite
  overlapping line ranges. Not observed in this session's data; the added
  `TestDedupeFinalProductRows_KeepsDistinctRelationsForSameProduct` only guards the
  non-overlapping case. Worth revisiting if a future report shows legitimate rows being
  over-merged.
- This bug and the one recorded in `2026092103-bug-extract-products-pass2-wasted-output-tokens-and-prompt-drift.md`
  (Pass 2 prompt drift, row-count explosion) both trace back to Pass 2 under
  `prompt-enrich-product-mention-v2.md` producing more output variance than Step B (or the v2
  prompt's own instructions) accounted for; the v3 prompt rewrite referenced there discourages
  padding row count but does not address paraphrase variance on genuinely-duplicate rows,
  which is what this bug's fix addresses at the deterministic-code layer instead.
