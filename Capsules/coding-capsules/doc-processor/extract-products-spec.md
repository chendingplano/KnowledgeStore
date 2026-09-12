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

The output of this pass is an intermediate artifact: `product_mentions`.

### Deterministic Step A: Merge And Dedup Mentions

After all blocks are processed:

- remove overlap-only mentions unless the same mention is also supported by normal lines
- normalize casing, punctuation, and whitespace for matching
- merge duplicate mentions across overlapping and adjacent blocks
- preserve provenance, including evidence quotes and line spans

The output of this deterministic step is an intermediate artifact: `product_candidates`.

### Pass 2: Enrich Product Relations

For each deduplicated product candidate, use `ENRICH_PRODUCT_RELATIONS_MODEL_NAME` with `ENRICH_PRODUCT_MENTION_PROMPT` (default `prompt-enrich-product-mention-v2.md`; renamed 2026-09-12 from the misleadingly-named `EXTRACT_PRODUCT_PROMPT`) to produce normalized product-relation rows. Candidates are processed concurrently (`EXTRACT_PRODUCTS_MAX_TASKS`, shared with Pass 1).

This pass should:

- convert candidates into one or more final product-relation pairs
- assign exactly one `relation_type` per output row
- extract obligation, requirement text, parameters, related products, exceptions, and actor when supported by evidence
- use only the candidate and its supporting evidence

Important semantic rule:

- one output row = one product-relation pair
- if the same product has multiple supported relation types, output multiple rows

The output of this pass is an intermediate artifact: `product_relations_draft`.

### Deterministic Step B: Final Dedup

After relation enrichment:

- merge accidental duplicate rows from adjacent blocks or repeated evidence
- preserve the strongest evidence and combined line spans

Suggested dedup key:

```text
canonical_name + relation_type + normalized requirement_text + evidence span cluster
```

### Pass 3a: Translate Product Fields

If bilingual output is needed, use `TRANSLATION_MODEL_NAME` (falls back to `ENRICH_PRODUCT_RELATIONS_MODEL_NAME`, then `EXTRACT_PRODUCT_MODEL_NAME`) with `TRANSLATE_PRODUCTS_PROMPT` to generate the `_en` fields for the final draft rows.

**Batched, not one row per call (changed 2026-09-12).** Rows are grouped into
batches of `TRANSLATE_PRODUCTS_BATCH_SIZE` (default 10) and sent as one
`products` array per LLM call — previously one call per row, which was both
slower and wasteful of prompt overhead for a handful of short fields.
Batches run concurrently (`EXTRACT_PRODUCTS_MAX_TASKS`, shared with Pass
1/2). The output array's length must equal that batch's input length, in the
same order — the caller maps translated fields back to rows by position, not
by any id in the payload. A batch whose returned array is empty, malformed,
or the wrong length is logged and left untranslated; this never fails the
whole record, only that batch's rows.

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

## References

[1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`

[2] Chunking Processor Spec: `KnowledgeStore/Capsules/coding-capsules/chunking/+CAPSULE.md`

[3] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md`

[4] `Workspace/KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-products-impl.md`
