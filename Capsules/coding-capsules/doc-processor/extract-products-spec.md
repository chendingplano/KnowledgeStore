# Extract Product Relations Processor

This Doc Processor extracts product relations from chunked document input and stores the final normalized rows in `kb.products`.

The processor should use a multiple LLM passes. The first pass focuses on recall, deterministic code handles deduplication and overlap cleanup, and later passes add relation semantics and optional metadata. This reduces prompt overload and improves stability when using smaller models.

## Input

- `record_id`: the value of `kb.inputs.id`, identifies the record to process
- `chunks`: the persisted `.chunks` artifact (chunking must have run first); refer to [2]. Each chunk is adapted to the same `Block`/`BlockLine` processing unit described below (one chunk → one block, via `chunksToBlocks`), so "block" in the rest of this document means one chunk's lines, not a raw re-blocking of the document. This processor previously re-blocked the document directly (Blocks, not Chunks) — changed 2026-09-12 so it shares the one chunk set every other Phase B extractor reads.

## Implementation

- The code is in the `ChenWeb/` repo.
- It may use functions or modules in the `shared/` repo.

## Product Relation ID

Assign a unique Product Relation ID to each final product relation. The ID format is:

```text
<record_id>_prd_<seqno>
```

where `<record_id>` is the record ID and `<seqno>` is a sequence number relative to `<record_id>`, starting from `1`.

## Multiple LLM Passes

### Problems without Multiple LLM Passes

Without multiple LLM rounds, product extraction used a single-pass design. 
One LLM call was expected to do all of the following in one response:

- detect products
- infer relation semantics
- extract requirement details
- translate text into English
- generate category paths
- generate additional metadata such as discriminators

In practice this caused several problems:

- extraction counts were unstable across repeated runs on the same input
- the model sometimes returned only one product and sometimes many more
- the processor mixed recall, reasoning, translation, and taxonomy work in one pass
- prompt/schema complexity was too high for smaller models such as `gpt-5.4-mini`
- malformed or partial outputs were more likely because the requested JSON shape was too large

### Findings About The Causes

During debugging and review, the main causes of the instability were identified as follows:

1. The prompt asked for too much in one pass.
   Mention detection, relation reasoning, translation, and categorization are separate tasks with different failure modes. Combining them overloaded the model.

2. The schema contract was too heavy and partly ambiguous.
   The old design made it unclear whether one row represented:
   - one product
   - one product with many relations
   - one product-relation pair

3. Overlap handling and deduplication were delegated too much to the LLM.
   This made repeated runs sensitive to small wording changes in the model output.

4. Deterministic post-processing was too weak.
   The old flow lacked a clean boundary between:
   - high-recall mention extraction
   - deterministic mention grouping
   - final relation enrichment

5. A post-refactor bug was found in candidate key normalization.
   The first implementation of deterministic candidate grouping kept only ASCII letters and digits, which caused some non-English product names to collapse to an empty key and be dropped before relation enrichment.

### Solution: Multiple LLM Passes

Multiple LLM passes can solve the problems using the following passes:

1. Split the work into multiple passes.
   - Pass 1 extracts product mentions only.
   - Deterministic code merges and deduplicates mentions.
   - Pass 2 enriches candidates into product-relation rows.
   - Optional later passes handle translation and categorization.

2. Define the semantic unit of output explicitly.
   One final row must represent exactly one product-relation pair.

3. Move overlap cleanup and dedup into deterministic code.
   This makes the processing less sensitive to LLM variance and more reproducible.

4. Reduce the amount of JSON each LLM call must produce.
   Smaller schemas improve reliability, especially on small or fast models.

5. Preserve multilingual product names during deterministic grouping.
   Candidate key normalization now keeps Unicode letters and numbers instead of stripping non-English product names.

## Pipeline

The product extraction pipeline should be split into the following passes.

### Pass 1: Extract Product Mentions

For each block, use `EXTRACT_PRODUCT_MENTIONS_MODEL_NAME` with `EXTRACT_PRODUCT_MENTIONS_PROMPT` to extract conservative product mentions from the block. Blocks are processed concurrently (`EXTRACT_PRODUCTS_MAX_TASKS`, default 1 — sequential until raised, same convention as `extract_metrics`' `EXTRACT_METRICS_MAX_TASKS`); no cross-block state, so this is a plain fan-out.

This pass should:

- maximize recall while avoiding hallucinations
- extract only product-like mentions and direct evidence
- avoid translation
- avoid category generation
- avoid discriminators
- avoid deep relation reasoning

**Pass 1 is the pipeline's producthood gate (clarified 2026-09-21).** Pass 2
does not re-decide whether a candidate is a product (it holds only a narrow
veto, below), so a Pass 1 false positive is amplified into one stored row per
relation type plus a `status='proposed'` row in `kb.product_names` that can
never match the catalog. Two exclusions carry most of the weight, both added
to `prompt-extract-product-mentions-v2.md`:

1. **Places, facilities, and works are not products.** The operative test is
   whether the thing is supplied as a movable article or constructed at a
   site. Facilities, plants, stations, depots, collection/storage points,
   bases, buildings, civil-engineering works and projects, and installations
   assembled in place are all excluded; Chinese naming cues are the suffixes
   `站`/`厂`/`场`/`基地`/`中心`/`园`/`区`/`房`/`池`/`工程`/`设施` and
   locational `点`. A `垃圾焚烧炉` is a product; a `生活垃圾焚烧厂` is not.
   `系统` is judged by the same test — a licensed software system is a
   product, a physical system assembled on site is not.

2. **Referenced-document titles are not evidence.** Normative-reference
   lists and citations name other documents. A noun phrase appearing only
   inside a citation line (`NY/T 2371 农村沼气集中供气工程技术规范`) is not
   evidence that this document says anything about that thing, and a citation
   line must never be used as `evidence_quote`. This is an evidence rule, not
   a product rule: a product that also appears in body text is extracted
   normally, quoting the body line.

**Why the gate matters (record 416, 2026-09-20 run, 1219 rows).** Without
these rules, 128 rows across 41 distinct names were facilities typed `system`
(`垃圾转运站`, `生活垃圾焚烧厂`, `生活垃圾卫生填埋场`, `垃圾分类投放点`,
`沼气工程`, `环境卫生设施`, and `物联网`, an abstract technology), and 28 rows
were grounded solely in normative-reference titles — including a
`requirement_text` ("环境卫生设施应符合 CJJ 27…") that Pass 2 fabricated to
justify the row. Note also that `product_type_hint` has no `facility` value,
so facility-shaped mentions are forced into the nearest bucket, `system`;
`system` is therefore a good proxy for this failure mode when auditing.

**Prompt-balance caution.** The first draft of the v2 exclusions
over-corrected: framing Pass 1 as "the only gate" and telling it that
"omitting a non-product is correct, not a recall failure" shifted the model's
posture toward rejection globally rather than toward rejecting facilities.
Measured against v1 on record 416, it dropped 57 distinct mentions where only
~18 were facilities, losing core recyclables (`瓶`, `罐`, `箱`, `袋`,
`易拉罐`, `图书`, `报纸`, `废弃家具`, `旧纺织衣物`, `电器电子产品`). The
shipped v2 keeps the exclusions but restores balance with an explicit
"be thorough about ordinary articles" keep-list and a symmetric Rule 7
("dropping a real product is as much an error as extracting a facility").
Any future tightening of this prompt must be A/B'd on distinct-mention counts
against the previous version, not just spot-checked on the false positives it
was written to fix.

**Measured result of the shipped v2** (record 416, all 10 chunks, same model
`deepseek-v4-flash` at temperature 0, v1 vs v2 in one run): facility-shaped
mentions 13 → 0, while distinct mentions rose 140 → 154. `生物有机肥` and
`微生物肥料` are correctly dropped — both occur *only* in citation lines 28-29
and were v1 false positives. Note the pass is not deterministic even at
temperature 0: two identical v1 runs returned 151 and 140 distinct mentions,
so single-item deltas are noise and only aggregate movements should be read
as signal.

The output of this pass is an intermediate artifact: `product_mentions`.

### Deterministic Step A: Merge And Dedup Mentions

After all blocks are processed:

- remove overlap-only mentions unless the same mention is also supported by normal lines
- normalize casing, punctuation, and whitespace for matching
- merge duplicate mentions across overlapping and adjacent blocks
- preserve provenance, including evidence quotes and line spans

The output of this deterministic step is an intermediate artifact: `product_candidates`.

### Pass 2: Enrich Product Relations

For each deduplicated product candidate, use `ENRICH_PRODUCT_RELATIONS_MODEL_NAME` with `ENRICH_PRODUCT_MENTION_PROMPT` (default `prompt-enrich-product-mention-v4.md`; renamed 2026-09-12 from the misleadingly-named `EXTRACT_PRODUCT_PROMPT`; v3 replaced v2 and v4 replaced v3, both 2026-09-21, see below) to produce normalized product-relation rows. Candidates are processed concurrently (`EXTRACT_PRODUCTS_MAX_TASKS`, shared with Pass 1).

This pass should:

- convert candidates into one or more final product-relation pairs
- assign exactly one `relation_type` per output row
- extract obligation, requirement text, parameters, related products, exceptions, and actor when supported by evidence
- use only the candidate and its supporting evidence

Important semantic rule:

- a "product-relation pair" is (product, relation_type) — the row describes
  how *the document* relates to one product (in scope of / subject to
  testing under / prohibited by, etc.), not a link between two products.
  Only four `relation_type` values are genuinely inter-product
  (`component_of`, `contains_product`, `compatible_with`,
  `replacement_or_alternative`); only for those is the second product
  named, in `relation_details.related_products`. For every other
  `relation_type`, `related_products` stays empty.
- one output row = one product-relation pair
- if the same product has multiple supported relation types, output multiple rows
- include a relation type only when the evidence directly and clearly
  supports it — do not add marginal or loosely-inferred relation types just
  to maximize row count; this is an output-token/cost control as much as a
  precision one (see "Pass 2 Cost" below)

**v3 rewrite (2026-09-21).** `prompt-enrich-product-mention-v2.md` was
cloned from the retired single-pass `prompt-extract-products-v1.md` and
never fully rewritten for its role as candidate-scoped enrichment: its
`## Inputs` section described only the raw document line-array, never
mentioning that a `Candidate:` object naming the one product to enrich is
appended to the task text at call time (`buildProductRelationTaskPrompt`,
`extract-products.go`); its body read as an independent full-document
extraction task ("extract the products... that the input relates to"),
not "enrich this one given candidate." v3 makes the `Candidate:` append
part of the documented contract and reframes the task accordingly. v3 also
drops two output blocks that were pure waste (see "Pass 2 Cost" below):
`discriminators`/`discriminators_en` (never read by any Go code) and every
`_en` field (`product_name_en`, `canonical_name_en`, `product_summary_en`,
`evidence_quote_en`, `requirement_text_en`, `confidence_reason_en` —
unconditionally overwritten by Pass 3a for every row, so Pass 2 was
generating full bilingual output that was always thrown away). Neither
block appeared in this spec's own Pass 2 output schema to begin with — v3
now matches it exactly.

**v4 narrow veto (2026-09-21).** v3 told Pass 2 that "the candidate has
already established that this is a product; you are not re-deciding whether
it qualifies." That made every Pass 1 false positive unrecoverable by design
— and amplified, since one bad candidate yields one row per relation type.
v4 keeps Pass 1 as the real gate but grants Pass 2 a deliberately narrow
veto: when a candidate is *clearly* a place/facility/works, an organization,
person, abstract concept, activity, legal act, document section, or is
supported only by a citation line, Pass 2 returns an empty `products` array
(Enrichment Rule 7). The veto is explicitly not a general confidence filter —
thin evidence is still handled by Rule 3 and the confidence floor — so that
it cannot quietly become a second, uncalibrated recall gate.

### Pass 2 Cost

Pass 2 dominates this processor's LLM cost: it runs once per deduplicated
candidate (not once per block, unlike Pass 1), and a document whose
candidates support many relation types each can produce a large row count
even from a short document — e.g. 12 pages producing 1000+ rows across ~26
candidates was observed before the v3 fixes below. Levers, roughly in order
of leverage:

1. **Prune dead output fields from the prompt** (done in v3, above) — the
   single highest-leverage fix, since it cuts every row's output tokens
   regardless of row count.
2. **Cap row count per candidate** via Enrichment Rule 3 in v3 — discourage
   marginal/inferred relation types rather than rewarding exhaustiveness.
3. **Monitor `output_tokens` on the `"enrich product - end"` log line**
   (`extract-products.go`, added 2026-09-21 alongside `cache_hit`/`cache_miss`)
   to see whether a given run's cost is input-bound (cache misses) or
   output-bound (row count × per-row verbosity) before tuning further.
4. Input tokens are largely cache-hit already (Pass 2 reuses Pass 1's
   canonical chunk text per block, see `extractProductPayloadWithFallback`
   call site), so cache-miss reduction is not the primary lever here —
   confirm via the `output_tokens` counter above before assuming otherwise
   on a given run.

The output of this pass is an intermediate artifact: `product_relations_draft`.

### Thinking Must Stay On For Pass 1

`deepseek-flash` and `deepseek-v4-pro` are hybrid-reasoning models that think
by **default**: sending no `thinking` field leaves reasoning on. Until
2026-09-22 `shared/go`'s `extractTextWithFormat` only ever sent the field when
the configured value was `"enabled"`, so `thinking_type = "disabled"` and
`thinking_type = ""` produced identical wire requests and nothing — including
`forceDisableThinking()` in `extract-metrics.go` — actually disabled anything.
(Recorded as RC-5 in `2026081601-bug-pass2-enrich-merge-resolve-zero-prompt-cache.md`,
fixed 2026-09-22: the field is now sent for any non-empty value.) On run 148,
100,331 of 113,086 Pass 1 output tokens — 88.7% — were reasoning tokens.

Turning it off is nonetheless **wrong for Pass 1**. Replaying all 10 archived
run-148 requests with `thinking:{type:disabled}`: output tokens fell 9.5×
(116,992 → 12,325) but distinct mentions fell from 147 to 118, roughly 20%,
against ~3% run-to-run noise between two thinking-on runs. The losses are not
random — they are the class-level nouns (`可回收物`, `易腐垃圾`, `有害垃圾`,
`废玻璃`, `废旧纺织物`, `废弃电器电子产品`, `废旧家具`) that the v2 rebalance
was written to keep — while the *gains* are exactly the false positives v2 was
written to kill (`分类处理设施`, `生活垃圾分类收集设施`, `农村户用沼气池`,
plus the citation-only `生物有机肥` / `微生物肥料`). Two chunks returned a bare
`{"mentions":[]}`. The reasoning trace is where this prompt's facility and
citation exclusion rules actually get applied; strip it and the model reverts
to surface noun-spotting.

### Reasoning Control (`EXTRACT_PRODUCTS_REASONING`)

`EXTRACT_PRODUCTS_REASONING` (default `true`) governs provider-side reasoning
for this processor's **extraction** models — mention, relation, merged, and
their fallbacks.

- `true` (default): each model keeps whatever `thinking_type` its
  `.models.toml` entry declares. For hybrid-reasoning models that think by
  default, such as DeepSeek's, that means reasoning stays on. This setting
  never *adds* a `thinking` field the model definition did not ask for, so
  endpoints that reject the field keep working.
- `false`: forces `thinking_type = "disabled"` on those models.

An unset or unparseable value resolves to `true`. That default is deliberate:
silently disabling reasoning costs ~20% of distinct mentions on
`deepseek-flash` (above), so it must never happen by accident.

Pass 3a translation is **not** covered by this knob. It has its own
`TRANSLATE_PRODUCTS_THINKING` and defaults to disabled, because translating
five short fields needs no reasoning on any model tested. Setting
`EXTRACT_PRODUCTS_REASONING=false` therefore turns reasoning off everywhere;
setting it to `true` leaves translation disabled unless
`TRANSLATE_PRODUCTS_THINKING` is also changed.

Like the merged-pass switch, this is permanent: it exists so a new model, or
a new version of the same model, can be A/B'd both ways without a code change.

### Merged-Pass Mode (`EXTRACT_PRODUCTS_MERGED_PASS`)

`EXTRACT_PRODUCTS_MERGED_PASS` (default `false`) replaces Pass 1,
Deterministic Step A, and Pass 2 with a single per-chunk call that detects
products and assigns their relations together, using
`EXTRACT_PRODUCT_MERGED_PROMPT` (default
`prompt-extract-products-merged-v1.md`: the v2 producthood gate verbatim, plus
v4's relation-type catalogue and output schema, chunk-scoped). Deterministic
Step B, Pass 3a, Pass 3b, and storage all run unchanged — the merged call
reuses `normalizeProductList`, so its rows are shape-identical to Pass 2's.
It sends the same `canonicalChunkInputText` document Pass 1 would have sent,
so it rides the same cross-processor prompt cache.

The merged pass emits no mentions, so `MentionsCount` is 0 for such a run and
`EXTRACT_PRODUCT_PASS_1_ONLY` is meaningless alongside it: setting both logs a
warning and merged wins. Its LLM calls are logged as `extract_products merged`
/ `extract_products_merged` so a run's `llm_usage_event` rows can be told apart
from a two-pass run's at a glance.

**This is a permanent evaluation control, not a migration flag.** Whether
merging is a win is a property of the model, and every new model or model
version has to be re-measured. The default is `false` because of the
record-416 A/B below, which was run on `deepseek-flash`; it is not a verdict
on models not yet tested.

The cost case for merging is strong:

| | LLM calls | input tokens | output tokens | rows |
|---|---|---|---|---|
| two-pass (P1 recorded + P2 extrapolated from 40/179 candidates) | 189 | 628,863 | 469,766 | 237 |
| merged | 10 | 38,063 | 155,835 | 238 |

Same row yield, ~3× fewer output tokens, ~16× fewer input tokens, 19× fewer
calls — the input saving being mostly the chunk that Pass 2 re-sends once per
candidate. The `relation_type` mix also tracks the two-pass distribution
closely (`scope` 58.0% vs 62.3%), and the merged arm produced **zero**
facility-shaped false positives.

Two findings are why it is off by default on this model:

1. **Detection degrades ~10%, consistently.** Run head-to-head in the same
   harness, three reps each: Pass 1 alone found 176/165/162 distinct mentions;
   the merged prompt found 153/151/151. The loss concentrates in mid-size
   chunks (one chunk: 26/22/16 two-pass vs 16/16/14 merged; another: 10/7/8 vs
   4/6/5) while the two largest chunks come out level — consistent with
   detection and relation reasoning competing for the same attention budget,
   which is the original finding in "Problems without Multiple LLM Passes"
   above. A separate earlier merged rep returned only 102 distinct products,
   a third below its own median, consistent with an oversized/truncated JSON
   response — the same tail failure the multi-pass split was adopted to remove.

2. **Per-row enrichment depth halves.** `requirement_text` was populated on
   47.1% of merged rows vs 96.2% of Pass 2 rows; `conditions` on 8.0% vs
   39.6%. `obligation_level` and `responsible_actor` were unaffected. A merged
   row is therefore a materially thinner `kb.products` row even when the row
   count matches.

A third, smaller integration risk: the merged arm prefers the longer
source-faithful surface (`废弃橡胶及橡胶制品`, `各种包装纸`,
`公共场所收集容器`) where Pass 1 yields the shorter head noun. That changes
the normalization key and so changes tier 0/1/2 hit rates in "Product Name
Resolution", producing more `status='proposed'` rows.

**On `deepseek-flash`, the cost problem is real but the lever is elsewhere.** Nearly all of the
two-pass input cost is the chunk being re-sent per candidate (179 calls ×
~3,356 input tokens). Batching each chunk's candidates into one Pass 2 call
would cut 179 calls to 10 and remove most of that duplication while leaving
detection in its own pass. That has not been built or measured.

### Deterministic Step B: Final Dedup

After relation enrichment:

- merge accidental duplicate rows from adjacent blocks or repeated evidence
- preserve the strongest evidence and combined line spans

Dedup key: `canonical_name + relation_type`, with rows in the same group
merged when their `evidence_lines` overlap (share at least one line) — the
merged row keeps the higher-`confidence` row's `requirement_text` and the
union of `evidence_lines`.

**Bug found and fixed 2026-09-21** (`kb.products` rows `416_prd_37` /
`416_prd_42`): the original implementation additionally required an exact
(case/whitespace-trimmed) match on `requirement_text` as part of the key.
Pass 2 (an LLM call) paraphrases `requirement_text` per row rather than
copying source text verbatim, so two rows enriched from the same or
overlapping evidence — same `canonical_name`, same `relation_type` — could
get differently-worded `requirement_text` and were never merged, leaking
duplicates into `kb.products`. Requiring literal `requirement_text` equality
was too strict to serve as a normalization signal; `evidence_lines` overlap
is the reliable "same underlying fact" signal and is now the sole merge
condition beyond `canonical_name + relation_type`.

### Pass 3a: Translate Product Fields

If bilingual output is needed, use `TRANSLATION_MODEL_NAME` (falls back to `ENRICH_PRODUCT_RELATIONS_MODEL_NAME`, then `EXTRACT_PRODUCT_MODEL_NAME`) with `TRANSLATE_PRODUCTS_PROMPT` to generate the `_en` fields for the final draft rows.

**Thinking disabled (changed 2026-09-22).** `TranslateModelCfg.ThinkingType`
is forced to `disabled` in `NewProductsProcessor` (override with
`TRANSLATE_PRODUCTS_THINKING`; set it to `""` for endpoints that reject the
`thinking` body field, such as local llama.cpp/ollama hosts). Pass 3a is
mechanical — translate five short fields per row — and on a hybrid-reasoning
model that thinks by default it was spending ~78% of its output tokens on
`reasoning_content` that no Go code ever reads. Measured over a 6-call replay
of real `product translation` requests: output tokens fell 81.6% (23,255 →
4,273), every batch's row count was preserved, and the only differences were
wording-level (`"Use"` vs `"Utilizes"`, title-casing). One behavioral note:
with thinking off the model populated `canonical_name_en` with a snake_case
slug where thinking-on returned `null`.

This is deliberately scoped to Pass 3a. The same change applied to Pass 1
cost ~20% of distinct mentions — see "Thinking Must Stay On For Pass 1" below.

**Batched, not one row per call (changed 2026-09-12).** Rows are grouped into
batches of `TRANSLATE_PRODUCTS_BATCH_SIZE` (default 10) and sent as one
`products` array per LLM call — previously one call per row, which was both
slower and wasteful of prompt overhead for a handful of short fields.
Batches run concurrently (`EXTRACT_PRODUCTS_MAX_TASKS`, shared with Pass
1/2). Each request row carries an `idx` (its position within the batch) that
the model must echo back, and returned rows are matched by that `idx` rather
than by array position — so a dropped or reordered row no longer discards the
whole batch, only itself. (This paragraph previously described position-based
mapping; `translateProductRows` in `extract-products.go` has used `idx` since
the batching change.) A batch that fails outright, or a row whose `idx` is
missing or invalid, is logged and left untranslated; this never fails the
whole record, only those rows.

This pass should:

- only translate fields already extracted
- not modify relation semantics
- set `_en` fields to `null` when the source language is already English

### Pass 3b: Resolve Product Names + Assign Categories From the Catalog

**Redesigned 2026-09-12 — no longer an LLM pass.** The old free-form
LLM-generated `category_paths` is replaced by a deterministic lookup against
`kb.product_names` (see "Product Name Resolution" above, which this pass now
performs — resolution was moved here, after Pass 3a, so a newly proposed row
can be enriched with the Pass 3a `product_name_en` too). For each row:

- resolve `product_name` against `kb.product_names` (tiers 0/1/2, tier 5 for
  review-only candidates on a miss) — sets `kb.products.product_name_id`;
- if the matched (or newly proposed) row carries a catalog category
  (`sub_catalog`/`category_l1`/`category_l2`), build `category_paths` as a
  single path node-per-level, `confidence: 1.0` throughout (a catalog lookup,
  not a model guess) — using the *existing* `category_paths` JSON shape
  (`CategoryPathEntry`/`CategoryPathNode`) so `indexProductsInTree` and the
  `.products` artifact need no changes;
- `category_paths_en` is **always cleared**, never populated —
  `kb.product_names` carries no English translation of
  `sub_catalog`/`category_l1`/`category_l2`;
- a newly proposed row (no catalog match) has no category yet, so
  `category_paths` is **cleared** for it. That is the intended signal that the
  product awaits curation, not a failure — no LLM fallback category is
  guessed.

**This pass is authoritative, not additive.** `category_paths`/`category_paths_en`
are unconditionally set or cleared for every row, never left as whatever an
earlier pass happened to put there. This matters concretely: Pass 2's own
prompt (`prompt-enrich-product-mention-v2.md`) originally had its own
"Extract Category Paths" section asking the LLM for free-form
`category_paths`/`category_paths_en` — a leftover from before this pass
existed. Found and fixed 2026-09-12 (bug: `category_paths` was only
overwritten on a catalog hit, so the LLM's free-form guess from Pass 2 leaked
through untouched on a miss, and `category_paths_en` was never touched at
all): the "Extract Category Paths" section and the `category_paths`/
`category_paths_en` output fields were removed from the Pass 2 prompt
entirely (nothing consumes that output once this pass runs, so generating it
was wasted tokens even before the leak), and this pass now clears both
fields unconditionally rather than only overwriting on a hit.

Distinct product names within one record are resolved concurrently
(`EXTRACT_PRODUCTS_MAX_TASKS`); a name repeated across rows resolves once and
is applied to every row sharing it. `CATEGORIZE_PRODUCTS_MODEL_NAME`,
`CATEGORIZE_PRODUCTS_PROMPT`, and `prompt-categorize-products-v1.md` are
retired (no longer read by this processor; the prompt file is left on disk
unused, not deleted).

### Final Storage

After the required passes complete:

- assign `product_rel_id`
- save all final product relation rows to `kb.products`
- save all final product relation rows to the `.products` file
- index `category_paths` and `category_paths_en` if category generation was executed

## Failure Handling

- If primary extraction fails and the fallback model also returns an empty or truncated JSON response for a block, the processor may treat that block as a successful empty extraction rather than a processor failure.
- Deterministic merge and dedup steps must not invent new products or relations.
- Optional passes such as translation and categorization may be skipped if configured off.

## Testing: Pass-1-Only Mode

`EXTRACT_PRODUCT_PASS_1_ONLY` (default `false`). When set to `true`, the
processor runs only Pass 1 (Extract Product Mentions) and Deterministic Step
A (Merge And Dedup Mentions) — Pass 2 (Enrich Product Relations), Deterministic
Step B, Pass 3a (Translate), and Pass 3b (Resolve Names + Categories) are all
skipped. The deduplicated `product_candidates` from Step A are persisted
directly to `kb.products` — dedup is not skipped, only enrichment onward.

Since no relation enrichment ran, persisted rows have no `relation_type`,
`relation_summary`, `obligation_level`, `requirement_text`, `related_products`,
translated `_en` fields, or `category_paths`/`category_paths_en` — only the
fields Pass 1 and Step A populate (`product_name`, `canonical_name`,
`product_type`, evidence, and confidence) are set. `product_rel_id` is still
assigned per persisted row.

It is mutually exclusive with `EXTRACT_PRODUCTS_MERGED_PASS`, which emits no
mentions at all: setting both logs a warning and the merged pass wins.

This mode is for testing only, to isolate and debug Pass 1's mention
extraction and dedup in isolation from Pass 2/3 while investigating
2026092103-bug, 2026092104-bug, and 2026092105-bug. It must never be enabled
in normal/production runs.

## Pass 1 Output: Product Mentions

The LLM output for Pass 1 is:

```json
{
  "mentions": [
    {
      "mention_text": "string",
      "canonical_hint": "string or null",
      "product_type_hint": "specific_product | product_class | component | material | software | system | equipment | consumable | packaging | other | unknown",
      "evidence_quote": "short supporting quote from the input",
      "evidence_lines": ["32", "35-45"],
      "is_explicit": true,
      "confidence": 0.0,
      "confidence_reason": "brief reason"
    }
  ]
}
```

## Deterministic Intermediate: Product Candidates

The normalized candidate structure produced by deterministic code is:

```json
{
  "products": [
    {
      "candidate_id": "string",
      "product_name": "string",
      "canonical_name": "string",
      "product_type_hint": "specific_product | product_class | component | material | software | system | equipment | consumable | packaging | other | unknown",
      "supporting_mentions": [
        {
          "mention_text": "string",
          "evidence_quote": "string",
          "evidence_lines": ["32", "35-45"]
        }
      ]
    }
  ]
}
```

## Pass 2 Output: Product Relations Draft

The LLM output for Pass 2 is:

```json
{
  "products": [
    {
      "product_name": "string",
      "canonical_name": "string",
      "product_type": "specific_product | product_class | component | material | software | system | equipment | consumable | packaging | other",
      "relation_type": "scope | regulated_object | requirement_target | performance_requirement | design_requirement | material_requirement | testing_requirement | certification_requirement | usage_condition | installation_requirement | maintenance_requirement | storage_requirement | prohibited_product | exempted_product | component_of | contains_product | compatible_with | replacement_or_alternative | measurement_object | risk_source | other",
      "product_summary": "one concise sentence describing how the input relates to this product",
      "evidence_quote": "short supporting quote from the input",
      "evidence_lines": ["32", "35-45"],
      "relation_details": {
        "obligation_level": "mandatory | recommended | permitted | prohibited | conditional | descriptive | unknown",
        "requirement_text": "relevant original text or concise paraphrase | null",
        "conditions": ["condition 1"],
        "exceptions": ["exception 1"],
        "thresholds_or_parameters": [
          {
            "name": "string",
            "value": "string",
            "unit": "string or null"
          }
        ],
        "related_products": [
          {
            "product_name": "string",
            "relationship": "component_of | contains_product | compatible_with | replacement_or_alternative | compared_with | other"
          }
        ],
        "responsible_actor": "string or null"
      },
      "confidence": 0.0,
      "confidence_reason": "brief reason"
    }
  ]
}
```

## Pass 3a Output: Translations

The LLM output for Pass 3a is one array entry per input row, same order (see
the batching note above):

```json
{
  "products": [
    {
      "product_name_en": "string or null",
      "canonical_name_en": "string or null",
      "product_summary_en": "string or null",
      "requirement_text_en": "string or null",
      "confidence_reason_en": "string or null"
    }
  ]
}
```

## Pass 3b Output: Category Paths (catalog lookup, not an LLM call)

Pass 3b produces the same `category_paths` shape as before, but deterministically:

```json
{
  "category_paths": [
    {
      "category_path": [
        {"name": "01 有源手术器械", "keywords": [], "confidence": 1.0},
        {"name": "01 超声手术设备及附件", "keywords": [], "confidence": 1.0},
        {"name": "01.1 超声手术设备", "keywords": [], "confidence": 1.0}
      ],
      "path_keywords": [],
      "path_confidence": 1.0
    }
  ]
}
```

`category_path` has one node per non-empty `kb.product_names` catalog level
(`sub_catalog` → `category_l1` → `category_l2`, in that order); a row whose
resolved `kb.product_names` entry has no catalog category (new/proposed
names) gets no `category_paths` entry at all. `category_paths_en` is never
populated (no English translation of the catalog exists).

## Output

### Output Record

Upsert all final product relation records to `kb.products`.

Normalize each final product relation to:

- `product_rel_id`
- `product_name`
- `product_name_en`
- `canonical_name`
- `canonical_name_en`
- `product_type`
- `relation_type`
- `relation_summary`
- `relation_summary_en`
- `evidence_quote`
- `evidence_lines`
- `obligation_level`
- `requirement_text`
- `requirement_text_en`
- `conditions`
- `exceptions`
- `parameters`
- `related_products`
- `responsible_actor`
- `confidence`
- `confidence_reason`
- `confidence_reason_en`
- `category_paths`
- `category_paths_en`
- `status`
- `create_time`
- `modify_time`
- `public_info`
- `private_info`
- `model_name`
- `prompt_name`
- `notes`
- `error_msg`
- `product_name_id` — FK into `kb.product_names`; see "Product Name Resolution" below

### Output File

Save all final product relations in:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.products
```

where:

- `<group_id>` = `floor(record_id / 1000)`
- `<filename_root>` is the root of `kb.inputs.staging_filename`
- `<parser_name>` is `kb.inputs.parser_name`

Add the following to each final product relation:

- `create_time`
- `model_name`
- `prompt_name`

## Product Name Resolution

Added 2026-09-12. Every final row's `product_name` is resolved against
`kb.product_names` before `kb.products` is saved, and `kb.products.product_name_id`
(a foreign key, `ON DELETE SET NULL`) is set to the result. This reuses the
keyword-canonicalization module's tier-ladder *concept*
(`KnowledgeStore/doc-repo/specs/202608/2026080403-spec-keyword-canonicalization-and-reconciliation.md`,
§9.1) against `kb.product_names` instead of `kb.keyword_surfaces` — it is not
a call into that module's own resolver, which operates on different tables
for a different family.

**Normalize first.** The extracted `product_name` is run through the same
shared surface normalizer the keyword module's tiers 0-4 use
(`semid.Normalizer` — NFKC fold, whitespace collapse, case fold, plus the
alnum/sorted/singular alternate keys) before any comparison. `kb.product_names.keywords`
already stores these same derived keys (computed at catalog-import time, or at
row-creation time below) for both a `zh` and, when available, an `en` name.

**Tiers implemented (0, 1, 2, 5 — not the full ladder):**

| Tier | Method | On a hit |
|---|---|---|
| 0 | exact match on `product_name` or `product_name_en` | use that row's id |
| 1 | the extracted name's normalized key equals a stored `keywords.zh.norm` or `keywords.en.norm` | use that row's id |
| 2 | the extracted name's `alnum`/`sorted`/`singular` key equals the corresponding stored key (collapsed into one tier here, unlike the real ladder's separate 0.8-scored trio) | use that row's id |
| 5 | trigram similarity (`pg_trgm`) ≥ 0.3 against `product_name`/`product_name_en`, top 3 | **never** attaches — see below |

Tiers 3 (rewrite rules) and 4 (initials bridge) are not ported: there is no
per-scope rewrite-rule table or initials index for product names. Tier 6
(embedding) is not built: `kb.product_names` stores no embedding column yet.

**On a tier 0/1/2 hit:** if the match was not byte-exact (tier 1 or 2), the
extracted surface string is appended to that row's `aliases` JSONB array
(deduplicated — a string already present is not re-added). `kb.products.product_name_id`
is set to the matched row's id either way.

**On a tier 0-2 miss:** this is a miss regardless of what tier 5 finds — a
"good enough" fuzzy match is never sufficient to attach an extraction to an
existing row (the keyword module's own D10, "bias toward under-merging",
applied here). A new `kb.product_names` row is inserted with `status = 'proposed'`,
`source = 'extract_products'`, `seq_no = 0` (catalog rows use a real sequence
number; proposed rows do not), and its own computed `keywords`. If tier 5 found
any candidate at or above the similarity floor, the top N (default 3) are
recorded on the new row as `extra_info.candidate_matches`, e.g.:

```json
{
  "candidate_matches": [
    {"id": 6279, "product_name": "软组织超声手术仪", "similarity": 0.7}
  ]
}
```

If tier 5 found nothing either, the new row is still created (a true miss is
never silently dropped — the same auto-first reasoning as D11), just without
a `candidate_matches` entry. `kb.products.product_name_id` is set to the new
row's id.

**Concurrency.** Two records processed concurrently that both propose the
same brand-new name converge on one row: a partial unique index on
`product_name` scoped to `WHERE status = 'proposed'` (migration
`20260912000003`) plus `INSERT ... ON CONFLICT DO NOTHING` and a re-select on
conflict. This index is scoped to `status = 'proposed'` specifically so it
does not conflict with the classification catalog import's legitimate
cross-category repeats of the same example name (`status = 'approved'` rows
are exempt).

**`kb.product_names.status`** (migration `20260912000003`): `proposed` (the
D11-style default for a new row — nothing but curation moves a row out of
this state) | `approved` (every catalog-import row, and the only status a
tier 0-2 match is not expected to need touching) | `rejected` (curator
decision; not written by this processor). Every row imported before this
migration (the NMPA classification catalog) was backfilled to `approved`.

Resolution failures (including no database configured) are logged and
skipped — `product_name_id` stays unset. This is enrichment, not core
extraction, and must never block saving the extracted product-relation rows
themselves.

## Status Updates

If failed, upsert the following entry to `kb.inputs.status`:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_products",
  "proc_status": "failed",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "error": "error-msg",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

Otherwise, upsert:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_products",
  "proc_status": "success",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

If a user stop request is detected mid-execution (at an LLM call boundary,
per `CheckAndHandleStop` — refer to [1] §10), upsert instead:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_products",
  "proc_status": "stopped",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

`error` is absent on a clean stop.

## Configuration Override Caution

**Boolean flags must be quoted in `mise.local.toml`.** mise treats a bare TOML
`false` in `[env]` as an instruction to *unset* that variable, so
`EXTRACT_PRODUCTS_REASONING = false` is never exported at all — the process
sees nothing and the Go default (`true`) applies, which is the exact opposite
of what was written. `= true` does export, so the trap is silent and
asymmetric: a flag appears to work until the first time it is turned off.
Write `= "false"` / `= "true"` and confirm with `mise env | grep <VAR>` from
the project directory (mise loads no config from the workspace root). Found
2026-09-22, when `EXTRACT_PRODUCTS_REASONING = false` left reasoning on; every
boolean in `ChenWeb/mise.local.toml` was quoted at the same time.

The prompt defaults in `NewProductsProcessor` (`extract-products.go`) are
**overridden by environment**, and on the development machine
`ChenWeb/mise.local.toml` pins both prompts by filename
(`EXTRACT_PRODUCT_MENTIONS_PROMPT`, `ENRICH_PRODUCT_MENTION_PROMPT`). Bumping
a default in Go therefore changes nothing locally on its own. This is not
hypothetical: the 2026-09-20 run of record 416 recorded
`prompt_name = prompt-enrich-product-mention-v2.md` while the code default
was already v3, because the pin was stale. When changing a prompt version,
update the Go default **and** the `mise.local.toml` pin, and confirm
afterwards via `kb.products.prompt_name` on a fresh run.

## References

[1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`

[2] Chunking Processor Spec: `KnowledgeStore/Capsules/coding-capsules/chunking/+CAPSULE.md`

[3] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md`

[4] `Workspace/KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-products-impl.md`
