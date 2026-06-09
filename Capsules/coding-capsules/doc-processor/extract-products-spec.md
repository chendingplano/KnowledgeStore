# Extract Product Relations Processor

This Doc Processor extracts product relations from blocked document input and stores the final normalized rows in `kb.products`.

The processor should use a multiple LLM passes. The first pass focuses on recall, deterministic code handles deduplication and overlap cleanup, and later passes add relation semantics and optional metadata. This reduces prompt overload and improves stability when using smaller models.

## Input

- `record_id`: the value of `kb.inputs.id`, identifies the record to process
- `blocks`: refer to [2] for blocks

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

For each block, use `EXTRACT_PRODUCT_MENTIONS_MODEL_NAME` with `EXTRACT_PRODUCT_MENTIONS_PROMPT` to extract conservative product mentions from the block.

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

For each deduplicated product candidate, use `ENRICH_PRODUCT_RELATIONS_MODEL_NAME` with `ENRICH_PRODUCT_RELATIONS_PROMPT` to produce normalized product-relation rows.

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

If bilingual output is needed, use `TRANSLATE_PRODUCTS_MODEL_NAME` with `TRANSLATE_PRODUCTS_PROMPT` to generate the `_en` fields for the final draft rows.

This pass should:

- only translate fields already extracted
- not modify relation semantics
- set `_en` fields to `null` when the source language is already English

### Pass 3b: Categorize Product Relations

If category indexing is needed, use `CATEGORIZE_PRODUCTS_MODEL_NAME` with `CATEGORIZE_PRODUCTS_PROMPT` to generate `category_paths` and `category_paths_en`.

This pass should:

- focus only on category assignment
- avoid changing any extracted relation fields
- output a small number of stable, retrieval-friendly paths

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

The LLM output for Pass 3a is:

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

## Pass 3b Output: Category Paths

The LLM output for Pass 3b is:

```json
{
  "products": [
    {
      "category_paths": [
        {
          "category_path": [
            {
              "name": "category-name",
              "keywords": ["keyword"],
              "confidence": 0.0
            }
          ],
          "path_keywords": ["keyword"],
          "path_confidence": 0.0
        }
      ],
      "category_paths_en": [
        {
          "category_path": [
            {
              "name": "category-name",
              "keywords": ["keyword"],
              "confidence": 0.0
            }
          ],
          "path_keywords": ["keyword"],
          "path_confidence": 0.0
        }
      ]
    }
  ]
}
```

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
- `product_summary`
- `product_summary_en`
- `evidence_quote`
- `evidence_quote_en`
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

## References

[1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`

[2] `KnowledgeStore/Capsules/coding-capsules/doc-processor/blocking-spec.md`

[3] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md`

[4] `Workspace/KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-products-impl.md`
