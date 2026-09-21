# extract_products Pass 2 prompt generated two fully-discarded output blocks per row, and had drifted from a dead single-pass prompt file

Date: 2026-09-21

Status: root-caused and fixed in the working tree for the confirmed part (wasted output
fields); `go build`/`go test` clean; not committed; not live-verified against a real rerun,
so the actual token/cost savings are not yet measured. A second, related contributor
(row-count explosion) is flagged but not root-caused.

Scope: `ChenWeb/server/api/doc-processing/extract-products.go`,
`ChenWeb/server/api/doc-processing/cache_log.go`, `ChenWeb/prompts/prompt-enrich-product-mention-v2.md`
(retired) → `prompt-enrich-product-mention-v3.md` (new default), and this capsule's own spec,
`KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-products-spec.md`.

Code read: `extract-products.go` in full (Pass 1/Pass 2/Pass 3a/Pass 3b pipeline,
`enrichProductCandidatesWithLLM`, `buildProductRelationTaskPrompt`/`buildProductRelationUserPrompt`,
`normalizeProductList`, the Pass 3a translation batch loop, `resolveProductNamesAndCategories`);
`cache_log.go` (`cacheTokenCounts`/`extractorCacheTokens`); `shared/go/api/llm/types.go`'s `Usage`
struct; every prompt file under `ChenWeb/prompts/` whose name starts `prompt-*product*`
(`prompt-extract-products-v1.md` — deleted this session, `prompt-extract-product-mentions-v1.md`,
`prompt-enrich-product-mention-v2.md`/`-v3.md`, `prompt-enrich-product-relations-v1.md`,
`prompt-categorize-products-v1.md`).

Evidence: user ran `extract_metrics` + `extract_products` on record 416 (a 12-page document)
and reported 3,310,666 total output tokens, ~¥14 cost — attributed mainly to `extract_products`.
Cited log line from that run:

```
2026-09-20 18:22:47 INFO [req=e-43996ef7] enrich product - end
  candidate_id="cand_26" rows="14" products_so_far="1011"
  cache_hit="2816" cache_miss="358" ms_used="54359"
```

i.e. by the 26th deduplicated product candidate alone, Pass 2 had already produced 1011 output
rows (average ~39 rows/candidate), with cache_hit >> cache_miss confirming input tokens were
not the driver — output-side generation was.

Related: this capsule's spec (`extract-products-spec.md:202-215`) already documents one
instance of the same defect class, found and fixed 2026-09-12: Pass 2's prompt had originally
carried a stale free-form `category_paths`/`category_paths_en` section left over from a
dead-code clone, removed once Pass 3b's deterministic catalog lookup made it redundant. This
bug report is the same defect recurring in two output fields that fix missed.

---

## 1. Summary

Two separate things were found while chasing down why `extract_products` was so expensive
on a 12-page document:

1. **Prompt/spec drift, harmless on its own but confusing.** The prompt file the user first
   compared against Pass 2 (`prompt-extract-products-v1.md`) turned out to be dead code — a
   leftover from the pre-2026-09-12 single-pass design, never wired into the live pipeline —
   which made the two-pass split look broken when it wasn't. The user deleted that file this
   session. Its sibling, `prompt-enrich-product-relations-v1.md`, is the same kind of orphan
   and is still on disk, undecided.
2. **The real cost driver.** The *actually live* Pass 2 prompt (`prompt-enrich-product-mention-v2.md`)
   had, in turn, been cloned from that same dead single-pass prompt rather than authored
   against this spec's Pass 2 contract. Two of its output blocks — generated fresh for every
   one of 1011+ rows on this one document — are never used by anything downstream:
   `discriminators`/`discriminators_en`, and every `_en` field.

## 2. Root cause

**2a. The dead file that looked like the smoking gun.** `ChenWeb/prompts/prompt-extract-products-v1.md`
had `relation_type`, `relation_details`, `discriminators`, and `category_paths` in its output
schema — i.e. it looked like it was already doing everything Pass 2 does, which is what
prompted the original "why do we even need Pass 2" question. Tracing the actual Go wiring
(`extract-products.go:151-156`, `NewProductsProcessor`) showed the live Pass 1 default is a
different file, `prompt-extract-product-mentions-v1.md` — lean, recall-only, matching this
spec's Pass 1 contract exactly (no `relation_type`, no `relation_details`, no summaries, no
discriminators). `prompt-extract-products-v1.md`'s filename appeared nowhere in any `.go`
file; its sibling `prompt-enrich-product-relations-v1.md` appeared only inside a
commented-out function (`extract-products.go:2087-2091`, wrapped in `/* */`). Both are
pre-refactor leftovers, the same pattern this spec already notes for
`prompt-categorize-products-v1.md` (left on disk unused, not deleted, after Pass 3b's
2026-09-12 redesign).

**2b. The live Pass 2 prompt's own drift.** With the dead file out of the picture,
`prompt-enrich-product-mention-v2.md` (the real Pass 2 prompt) still didn't read like
candidate-scoped enrichment: its `## Inputs` section described only the raw document
line-array, never mentioning that a `Candidate:` object (the one product to enrich) is
appended to the task text at call time (`buildProductRelationTaskPrompt`,
`extract-products.go:1111-1134`); its body read as an independent "extract every product in
this document" task, word-for-word close to the dead v1 file. This is consistent with v2
having been produced by copying the old single-pass prompt and trimming only the
already-known `category_paths` leak on 2026-09-12, without a full rewrite for its actual
Pass 2 role.

**2c. The concrete cost bug.** Two output blocks in v2's schema are pure waste, confirmed by
reading what the Go code does with the payload:

- `discriminators`/`discriminators_en` — `grep discriminator ChenWeb/server/api/doc-processing/extract-products.go`
  returns zero matches. Nothing ever reads this field. Yet the prompt asked, per row, for an
  `intent` string, a `domain[]` array, a nested `discriminators[]` array (each entry with
  `category`/`value`/`confidence`/`reason`, the `reason` being open-ended LLM prose), and an
  `exploration_plan[]` array — then the same structure again for `discriminators_en`.
- `product_name_en`, `canonical_name_en`, `product_summary_en`, `evidence_quote_en`,
  `requirement_text_en`, `confidence_reason_en` — these are read into the normalized row
  (`normalizeProductList`, `extract-products.go:1408-1434`), but Pass 3a's own translation
  call then **unconditionally overwrites every one of them for every row**
  (`extract-products.go:1648-1655`: `row[key] = strings.TrimSpace(asString(first[key]))`, no
  "only if empty" guard). So Pass 2 generated full bilingual translations of every field, and
  Pass 3a discarded them and retranslated from scratch regardless.

Neither block appears in this spec's own documented Pass 2 output schema
(`extract-products-spec.md:288-324`) — they were never part of the design, just never pruned
from the prompt file when the multi-pass pipeline made them dead weight.

**2d. Row-count explosion — flagged, not root-caused.** The cited log line shows candidate
#26 alone producing 14 rows (`relation_type` variants for one product), with 1011 total rows
already accumulated after only 26 candidates on a 12-page document — roughly 39 rows/candidate
on average. This multiplies whatever per-row output cost exists, independent of the fields
in 2c. Whether this reflects genuinely distinct, evidence-supported relation types per
product, or the prompt/model over-generating marginal ones, was not investigated this
session. The fix below adds a discouraging instruction but this is a mitigation, not a
diagnosis.

## 3. Blast radius

Every document processed through `extract_products` since Pass 2's v2 prompt became the
default (per this spec, 2026-09-12) has paid to generate two always-discarded output blocks
on every Pass 2 row — not specific to record 416. Cost scales with row count (see 2d) times
the discriminator block's free-text verbosity; on record 416, `extract_metrics` +
`extract_products` combined totaled 3,310,666 output tokens (~¥14) for a 12-page input, with
the user attributing the larger share to `extract_products`. `extract_metrics` was not
examined for an analogous defect this session — it was not cleared, just out of scope.

## 4. Fix implemented (uncommitted)

- **Instrumentation** (`cache_log.go`, `extract-products.go`): added `outputTokenCount()`
  alongside the existing `cacheTokenCounts()`, and added `output_tokens` to the
  `"enrich product - end"` log line, so future runs can directly attribute cost to output
  volume instead of inferring it from row counts.
- **New prompt** `prompt-enrich-product-mention-v3.md`, now the default in
  `NewProductsProcessor` (v2 kept on disk unused, per this repo's existing convention for
  prior prompt version bumps). Changes from v2:
  - Documents the appended `Candidate:` block explicitly and reframes the task as enriching
    one given candidate, not independently re-extracting the document.
  - Removes `discriminators`/`discriminators_en` and every `_en` field entirely (schema now
    matches this spec's Pass 2 output exactly).
  - Adds the rule that `relation_details.related_products` is populated only for the four
    genuinely inter-product `relation_type` values (`component_of`, `contains_product`,
    `compatible_with`, `replacement_or_alternative`) — a gap surfaced during the
    clarification discussion that preceded the cost investigation, not itself a cost fix.
  - Adds an explicit instruction against padding row count with marginal/loosely-inferred
    relation types (targets 2d, unverified).
- **Spec updated** (`extract-products-spec.md`): points at v3, records the rationale, adds a
  "Pass 2 Cost" section listing these levers in order of expected leverage.
- `go build ./...` and `go test ./server/api/doc-processing/... -run Product` both clean; no
  test in the package referenced `discriminators`.
- Nothing committed in either repo (`ChenWeb` or `KnowledgeStore`) this session.

## 5. Tasks

- [x] Trace why `prompt-extract-products-v1.md` looked like it duplicated Pass 2 — confirmed
      dead code, not live-wired; user deleted the file
- [x] Identify concrete, code-confirmed sources of wasted Pass 2 output tokens
- [x] Add `output_tokens` instrumentation to Pass 2's per-candidate log line
- [x] Rewrite the Pass 2 prompt (v3): drop dead fields, document the `Candidate:`-append
      contract, add the `related_products` scoping rule, discourage relation-type padding
- [x] Update this spec to match
- [x] `go build ./...` and product-scoped `go test` clean
- [ ] Commit the `ChenWeb` code/prompt changes and the `KnowledgeStore` spec update (two
      separate repos, via `jj`)
- [ ] Re-run `extract_products` on record 416 (or another real record) and compare total
      `output_tokens`/cost against the ¥14 baseline to confirm the fix's actual savings —
      nothing above is verified against a live call yet
- [ ] Decide on `prompt-enrich-product-relations-v1.md` (the other orphaned dead-code prompt
      file, same shape as the one already deleted) — leave or delete
- [ ] Investigate whether the row-count explosion (2d) is expected recall or a genuine
      over-generation defect, once the output_tokens field gives real per-run numbers to look at

## 6. Open questions / future related activities

- Whether v3's "don't pad relation types" instruction meaningfully reduces row count without
  losing real recall — needs the same live re-run to answer; currently untested against any
  real document.
- Whether `extract_metrics` (the other cost contributor named in this session, run on the same
  record 416) has an analogous discarded-output-field defect — not investigated here.
- `prompt-enrich-product-relations-v1.md` disposition (see Tasks).
- The terminology clarification reached in this session — a `kb.products` row is
  (product, relation_type), not a two-product graph edge; `related_products` is a conditional
  nested detail, not the row's primary structure — is now encoded in v3's prompt and the spec
  update, but hasn't been checked against any frontend surface that might display these rows
  as "relations" in a way that assumes the graph-edge reading.
