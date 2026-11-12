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
- **last-modify-time:** 2026-11-13T04:57:48-06:00
- **keywords:** extract_products, product extraction, product relations, document processing, evidence, product review, knowledge base

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

## How processing works

The document must first be processed into chunks. In the standard workflow, the processor finds product mentions in those chunks, combines duplicate candidates, and then identifies their relationships to the document. It removes duplicate result rows, optionally translates fields, and resolves product names and categories against the product catalog. An alternative merged mode combines mention detection and relationship extraction into one step; its results still go through later processing.

The resulting records are saved in `kb.products`. A normal completed run also writes a `.products` artifact and updates product indexes. Product names that do not match an existing catalog entry can be proposed for later catalog review; a proposed name is not the same as an approved catalog entry.

## Run and review

1. Select the document in the document-processing workflow and make sure chunking is included or has already completed. Select `extract_products` among the processors for the run.
2. Start processing and check the document's processing status for `extract_products`. If it fails, inspect the reported error or ask an operator to check the processor logs.
3. Open the Products view and locate the document's extracted records. Review each product, relationship, and supporting evidence against the original passage. Pay particular attention to conditions, exceptions, and who is responsible.
4. If completeness matters, compare the results with a reviewed product benchmark when one is available. A benchmark and its score are separate from the production extraction results.

The exact controls available depend on the configured document-processing workflow. If `extract_products` is unavailable, ask an operator to check the selected pipeline and configuration.

## Rerunning a document

When product rows already exist, an ordinary run skips extraction for that document. To regenerate them, use the workflow's force option. A forced run replaces existing product rows for the document; review or preserve results you need before running it. Processing can fail, so check the resulting status and rows rather than assuming the replacement succeeded.

## Operator settings and troubleshooting

The model, prompts, and operational settings are configured in the processor's environment. Operators should verify the configuration used by the running service, especially when comparing environments. The main choices are:

| Setting | Purpose |
| --- | --- |
| `EXTRACT_PRODUCT_MENTIONS_MODEL_NAME` | Model used to find product mentions; `EXTRACT_PRODUCT_MODEL_NAME` is a fallback. |
| `ENRICH_PRODUCT_RELATIONS_MODEL_NAME` | Model used to enrich product relationships; `EXTRACT_PRODUCT_MODEL_NAME` is a fallback. |
| `EXTRACT_PRODUCTS_MAX_TASKS` | Maximum concurrent extraction tasks; the default is 1. |
| `EXTRACT_PRODUCTS_MERGED_PASS` | When enabled, combines product detection and relationship extraction for each chunk. |
| `EXTRACT_PRODUCT_PASS_1_ONLY` | Testing only: saves deduplicated mention candidates without relationship enrichment, translation, or name and category resolution. Default is `false`; do not enable in production. If merged mode is enabled, merged mode takes precedence and this setting is ignored. |

If no results appear, check that chunking succeeded, that the correct document was selected, and that the processor was included and completed. Existing results cause an ordinary run to skip extraction. If a run reports a model, prompt, or artifact error, an operator should check the service configuration and logs. If results lack relationships or categories, check whether the testing-only first-pass setting was enabled. Absence of a translated field may also reflect disabled translation or missing source content.

## Further information

- The [product extraction specification](../../Capsules/coding-capsules/doc-processor/extract-products-spec.md) describes processing, configuration, failure handling, and output fields in detail.
- The [products benchmark developer document](../devdocs/202611/2026110803-devdoc-products-benchmark.md) explains reviewed benchmarks and scoring.

## Change Log

| Version | Timestamp | Author | Reason | Summary |
| --- | --- | --- | --- | --- |
| 1.0 | 2026-11-13T04:57:48-06:00 | Codex | Initial manual | Described product extraction, reviewing results, reruns, and operator settings. |
