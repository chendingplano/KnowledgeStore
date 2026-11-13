# Extract Products User Manual

- **title:** Extract Products User Manual
- **language:** en
- **format:** markdown
- **version:** 1.0
- **status:** Draft
- **author:** Codex
- **owner:** Not specified
- **audience:** Document-processing users, reviewers, and operators
- **create-time:** 2026-11-13T04:57:48-06:00
- **last-modify-time:** 2026-11-13T05:42:13-06:00
- **keywords:** extract_products, product extraction, product relations, document processing, evidence, product review, knowledge base, product catalog, categories, translation

## What Extract Products does

`extract_products` finds products named in a processed document and records how the document relates to them. It is useful when reviewing a standard, regulation, or other document for the articles, materials, equipment, or product classes it discusses and the requirements or other statements associated with them.

The processor uses an AI model, so its output is a starting point for review. Check important findings against the source document; a model can miss products, assign an incorrect relationship, or misunderstand a passage.

A product can be a physical article, equipment, a material, a component, a product class, software, or a waste category or stream. The extraction instructions distinguish movable articles from places and facilities: for example, a waste container is a product, while a waste collection site is a location. A product mentioned only in the title of a referenced document is not sufficient evidence that the processed document discusses it.

## What a result means

Each result represents a product and a relationship between that product and the document. A product can therefore have several rows when the document relates to it in different ways. A row can contain:

- The product name, a normalized name, product type, and category information.
- The relationship type and a summary of what the document says.
- Supporting evidence, including a quotation or source lines when available.
- A requirement, its obligation level, conditions, exceptions, parameters, and responsible actor when identified.
- A confidence value and explanation, when provided. Confidence is a model-generated assessment, not proof that the result is correct.
- English text for supported fields when translation is enabled.

For example, if a document defines a container and also states a storage requirement for it, the results may include separate relationships for the definition and the requirement. Review the evidence and the wording of each row in context; an empty field means no value was recorded and does not prove that the document contains none.

### Product categories

Categories come from the product-name catalog, not from an AI category guess. When a product name matches a catalog entry that has a category, the processor copies that category into the result. When no name matches, it proposes a name for review without a category. A result can also lack a category if its matched catalog entry has none or name resolution could not run. An empty category therefore does not mean that the product cannot be categorized.

The `category_paths` field holds the catalog category when one is available. `category_paths_en` is left empty because the catalog does not provide English category labels. Translating product text does not translate categories.

## Processing phases

Chunking must complete before product extraction. “Required” below describes the normal full extraction workflow; the testing-only first-pass mode stops early.

| Phase | What it produces | Required or optional | Related environment variables |
| --- | --- | --- | --- |
| Pass 1: product mentions | Product names, type hints, evidence, and confidence from each document chunk. | Required in the standard workflow; replaced by the merged pass when enabled. | `EXTRACT_PRODUCT_MENTIONS_PROMPT`, `EXTRACT_PRODUCT_MENTIONS_MODEL_NAME`, `EXTRACT_PRODUCT_MODEL_NAME` |
| Step A: merge mentions | Deduplicated product candidates assembled from the mentions; no LLM call. | Required in the standard workflow, including first-pass-only testing; replaced by the merged pass when enabled. | `EXTRACT_PRODUCTS_MERGED_PASS`, `EXTRACT_PRODUCT_PASS_1_ONLY` |
| Pass 2: relationship enrichment | Product–document relationships, summaries, evidence, requirements, conditions, exceptions, parameters and actors when found. | Required in the standard full workflow; replaced by the merged pass, or skipped in first-pass-only testing. | `ENRICH_PRODUCT_MENTION_PROMPT`, `ENRICH_PRODUCT_RELATIONS_MODEL_NAME`, `EXTRACT_PRODUCT_MODEL_NAME` |
| Merged pass | Product mentions and their relationships together, with evidence and other supported details. | Optional alternative to Pass 1, Step A and Pass 2. | `EXTRACT_PRODUCTS_MERGED_PASS`, `EXTRACT_PRODUCT_MERGED_PROMPT`, `EXTRACT_PRODUCT_MENTIONS_MODEL_NAME`, `EXTRACT_PRODUCT_MODEL_NAME` |
| Step B: final deduplication | Removes duplicate product–relationship rows; no LLM call. | Runs after relationship extraction in a full standard or merged run. | `EXTRACT_PRODUCT_PASS_1_ONLY` skips it in testing mode. |
| Pass 3a: translation | English versions of supported extracted text fields. | On by default when the translation prompt and a usable translation model are available; can be switched off. Individual failed batches or rows can remain untranslated. | `EXTRACT_PRODUCT_TRANSLATION`, `TRANSLATE_PRODUCTS_PROMPT`, `TRANSLATION_MODEL_NAME`, `ENRICH_PRODUCT_RELATIONS_MODEL_NAME`, `EXTRACT_PRODUCT_MODEL_NAME`, `TRANSLATE_PRODUCTS_BATCH_SIZE`, `TRANSLATE_PRODUCTS_THINKING` |
| Pass 3b: name and category resolution | Matches names to the product catalog and copies available catalog categories; proposes unmatched names for review. No LLM call. | Runs in a full standard or merged run; skipped in first-pass-only testing. Unmatched names may have no category. | `EXTRACT_PRODUCTS_MAX_TASKS`; `CATEGORIZE_PRODUCTS_MODEL_NAME` is retired and is not used. |
| Storage and indexing | Saves rows in `kb.products`, writes a `.products` artifact and updates product indexes. | Part of a normal completed full run. First-pass-only testing saves incomplete candidate rows. | `ARTIFACT_DIR` |

Yes: when `EXTRACT_PRODUCTS_MERGED_PASS=true`, one LLM call **per document chunk** detects products and extracts their relationships together. It replaces Pass 1, Step A and Pass 2, not the later deduplication, optional translation, catalog resolution or storage. Additional calls can occur for retries or translation. The merged pass uses the mention model and `EXTRACT_PRODUCT_MERGED_PROMPT`. With the flag unset or `false`, the standard separate passes run. If both merged and first-pass-only modes are enabled, merged mode takes precedence.

`EXTRACT_PRODUCTS_MAX_TASKS` controls concurrency across extraction tasks and is also used in translation and catalog resolution. `EXTRACT_PRODUCTS_REASONING` and `EXTRACT_PRODUCT_MODEL_FALLBACK` apply to extraction calls as described below.

The resulting records are saved in `kb.products`. A product name proposed for catalog review is not the same as an approved catalog entry.

## Run and review

1. Select the document in the document-processing workflow and make sure chunking is included or has already completed. Select `extract_products` among the processors for the run.
2. Start processing and check the document's processing status for `extract_products`. If it fails, inspect the reported error or ask an operator to check the processor logs.
3. Open the Products view and locate the document's extracted records. Review each product, relationship, and supporting evidence against the original passage. Pay particular attention to conditions, exceptions, and who is responsible.
4. If completeness matters, compare the results with a reviewed product benchmark when one is available. A benchmark and its score are separate from the production extraction results.

The exact controls available depend on the configured document-processing workflow. If `extract_products` is unavailable, ask an operator to check the selected pipeline and configuration.

## Rerunning a document

When product rows already exist, an ordinary run skips extraction for that document. To regenerate them, use the workflow's force option. A forced run replaces existing product rows for the document; review or preserve results you need before running it. Processing can fail, so check the resulting status and rows rather than assuming the replacement succeeded.

## Operator settings and troubleshooting

The model, prompts, and operational settings are configured in the processor's environment. Operators should verify the configuration used by the running service, especially when comparing environments. Model references are resolved through `MODEL_DEF_FILE`.

| Setting | Purpose |
| --- | --- |
| `EXTRACT_PRODUCT_MENTIONS_PROMPT` | Prompt for Pass 1; defaults to `prompt-extract-product-mentions-v2.md`. |
| `EXTRACT_PRODUCT_MENTIONS_MODEL_NAME` | Model for Pass 1 and the merged pass; falls back to `EXTRACT_PRODUCT_MODEL_NAME`. |
| `ENRICH_PRODUCT_MENTION_PROMPT` | Prompt for Pass 2; defaults to `prompt-enrich-product-mention-v4.md`. |
| `ENRICH_PRODUCT_RELATIONS_MODEL_NAME` | Model for Pass 2; falls back to `EXTRACT_PRODUCT_MODEL_NAME`. It is also a translation-model fallback. |
| `EXTRACT_PRODUCT_MODEL_NAME` | Common fallback model reference when a phase-specific mention or relation model is not set; also the last translation-model fallback. This is distinct from the retry model below. |
| `EXTRACT_PRODUCT_MODEL_FALLBACK` | Optional retry model reference for extraction calls when the primary call fails. Some legacy empty-response cases are treated as empty results without a retry. |
| `EXTRACT_PRODUCT_MERGED_PROMPT` | Prompt used in merged mode; defaults to `prompt-extract-products-merged-v3.md`. |
| `EXTRACT_PRODUCTS_MERGED_PASS` | Enables the combined per-chunk extraction call; defaults to `false`. |
| `EXTRACT_PRODUCTS_REASONING` | Controls provider-side thinking for mention, relation, merged and fallback extraction models. Default `true` preserves each model's configured thinking setting; `false` forces it off. It does not govern translation and can affect extraction quality. |
| `EXTRACT_PRODUCTS_MAX_TASKS` | Maximum concurrent tasks for supported phases; default 1. |
| `EXTRACT_PRODUCT_TRANSLATION` | Set to `on` to enable translation or `off` to skip it; default `on`. A usable prompt and translation model are also required. Restart the processor after changing it. Category resolution still runs when translation is off. |
| `TRANSLATE_PRODUCTS_PROMPT` | Translation prompt; defaults to `prompt-translate-products-v2.md`. |
| `TRANSLATION_MODEL_NAME` | Translation model; falls back to `ENRICH_PRODUCT_RELATIONS_MODEL_NAME`, then `EXTRACT_PRODUCT_MODEL_NAME`. |
| `TRANSLATE_PRODUCTS_BATCH_SIZE` | Number of product rows per translation call; default 10. |
| `TRANSLATE_PRODUCTS_THINKING` | Translation thinking setting, separate from extraction reasoning; defaults to disabled. |
| `CATEGORIZE_PRODUCTS_MODEL_NAME` | Retired: this processor does not read it. Categories come from the product catalog, not an LLM categorization pass. |
| `EXTRACT_PRODUCT_PASS_1_ONLY` | Testing only: saves deduplicated mention candidates without relationship enrichment, translation, or name and category resolution. Default `false`; do not enable in production. Merged mode takes precedence. |
| `ARTIFACT_DIR` | Base directory for the normal `.products` output artifact. |

For boolean values in `mise.local.toml`, use quoted strings such as `"false"`; a bare TOML `false` unsets the variable, which can cause the processor's default to apply. Prompt and model settings in the launch environment can override defaults.

If no results appear, check that chunking succeeded, that the correct document was selected, and that the processor was included and completed. Existing results cause an ordinary run to skip extraction. If a run reports a model, prompt, or artifact error, an operator should check the service configuration and logs. If results lack relationships or categories, check whether the testing-only first-pass setting was enabled. For missing categories in a full run, check the linked catalog entry and processor logs; newly proposed names have no category until curated. A translated field may be empty because translation is off, its prompt or model is unavailable, its batch or row failed, the source content is missing, or the source is already English.

## Further information

- The [product extraction specification](../../Capsules/coding-capsules/doc-processor/extract-products-spec.md) describes processing, configuration, failure handling, and output fields in detail.
- The [products benchmark developer document](../devdocs/202611/2026110803-devdoc-products-benchmark.md) explains reviewed benchmarks and scoring.

## Change Log

| Version | Timestamp | Author | Reason | Summary |
| --- | --- | --- | --- | --- |
| 1.0 | 2026-11-13T05:42:13-06:00 | Codex | Document translation control and clarify categories | Added the translation switch, catalog category behavior, and guidance for empty fields. |
| 1.0 | 2026-11-13T05:19:26-06:00 | Codex | Clarify processing and configuration | Added phase requirements, merged-call behavior, and environment settings. |
| 1.0 | 2026-11-13T04:57:48-06:00 | Codex | Initial manual | Described product extraction, reviewing results, reruns, and operator settings. |
