# KPI-EDGAR: JSON Structure and Suitability for an `extract_metrics` Benchmark

Date: 2026-10-06  
Dataset: [tobideusser/kpi-edgar](https://github.com/tobideusser/kpi-edgar)  
Application specification: [extract-metrics-spec.md](../../../../ChenWeb/KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md)

## 1. Assessment

KPI-EDGAR is a useful starting point for a **financial metric assertion benchmark** for `extract_metrics`. Its entity annotations identify KPI names and monetary values, and its relation annotations connect those names to their values and attributes. These annotations fit the processor's candidate extraction and enrichment passes.

It does not provide complete ground truth for the processor's broader contract. The application also extracts metrics from standards, requirements, policies, tables, formulas, and clauses that delegate measurable requirements to cited documents. It generates categories and other enriched fields that KPI-EDGAR does not directly annotate.

The recommended approach is to use KPI-EDGAR as one benchmark slice and supplement it with manually reviewed examples from the application's actual documents.

## 2. Available Files and Inspection Provenance

The [repository README](https://github.com/tobideusser/kpi-edgar#kpi-edgar-dataset) identifies two dataset representations:

- [`data/kpi_edgar.xlsx`](https://github.com/tobideusser/kpi-edgar/blob/main/data/kpi_edgar.xlsx): the spreadsheet dataset.
- [`data/kpi_edgar.json`](https://github.com/tobideusser/kpi-edgar/blob/main/data/kpi_edgar.json): the preparsed representation, including IOBES labels.

This document describes the JSON downloaded from `main` during the 2026-10-06 inspection. The GitHub contents API reported its Git blob SHA as `171e9fd5dc3c423ceae615b921f710674cb53bad`. This is a file-content identifier, not a repository commit ID. Pin a repository revision and record a checksum when building the benchmark rather than downloading a mutable `main` URL on every run.

Direct inspection produced the following counts:

| Item | Count |
|---|---:|
| Top-level document records | 81 |
| Sentence records | 1,304 |
| Sentences assigned to `train` | 827 |
| Sentences assigned to `valid` | 119 |
| Sentences assigned to `test` | 212 |
| Sentences with `split_type: null` | 146 |
| Primary annotated entities | 4,249 |
| Primary annotated relations | 3,722 |

No document contained more than one non-null split assignment. There were 51 documents with training assignments, 15 with validation assignments, 14 with test assignments, and one with no non-null assignment. Some documents also contained unassigned sentences.

The [paper](https://arxiv.org/html/2210.09163v1#S3) reports a different snapshot: 1,355 sentences, 4,522 entities, and 3,841 relations. Consequently, benchmark reports must identify which release and representation they use.

## 3. JSON Hierarchy

The root is an array of documents:

```text
documents[]
└── document
    ├── id_
    └── segments[]
        ├── id_
        ├── value
        └── sentences[]
            ├── id_
            ├── unique_id
            ├── value
            ├── split_type
            ├── words[]
            ├── entities_anno[]
            ├── relations_anno[]
            ├── entities_anno_iobes[]
            ├── entities_anno_iobes_ids[]
            ├── entities_anno_secondary[]
            └── relations_anno_secondary[]
```

| Level / field | Meaning |
|---|---|
| Document `id_` | Report filename, such as `AAPL_10-K_0000320193-21-000105.txt` |
| Document `segments` | Source segments represented in the release |
| Segment `id_` | Segment identifier |
| Segment `value` | Segment text, providing surrounding context |
| Segment `sentences` | Sentence records in that segment |
| Sentence `id_` | Sentence identifier |
| Sentence `unique_id` | Identifier combining document, segment, and sentence IDs |
| Sentence `value` | Sentence text |
| Sentence `split_type` | `train`, `valid`, `test`, or null |

The sentence is the main annotation unit. Document, segment, and sentence IDs are identifiers; they are not the application's `source_line_spans`. The release should not be assumed to contain a fully annotated copy of every original report. Array-valued fields can be null, so a reader must handle null as well as empty arrays.

## 4. Tokens: `words`

Each sentence contains a token array. Punctuation is tokenized too. Consider this actual sentence from the JSON:

```text
The allowance for credit losses was $ 262 million at December 31, 2020.
```

Its token positions are:

| Position | Token | Position | Token |
|---|---|---|---|
| 0 | The | 8 | million |
| 1 | allowance | 9 | at |
| 2 | for | 10 | December |
| 3 | credit | 11 | 31 |
| 4 | losses | 12 | , |
| 5 | was | 13 | 2020 |
| 6 | $ | 14 | . |
| 7 | 262 | | |

Token records include the following fields:

| Field | Meaning / use |
|---|---|
| `id_` | Token index within the sentence |
| `value` | Original token text |
| `is_numeric` | Preprocessor's numeric classification |
| `value_numeric` | Preprocessed numeric value; requires validation |
| `is_currency` | Preprocessor identifies the token as belonging to a monetary expression |
| `unit` | Detected monetary unit and scale, for example `Billion USD` |
| `multiplier` | Scale factor, for example `1000000000.0` |
| `value_masked` | Preprocessing replacement, such as `<NUM>` or `<NUM_CY>` |
| `prefix`, `suffix`, `info` | Additional preprocessing metadata, often null |

The unit and multiplier may be stored on the numeric token even when the currency symbol and scale occupy neighboring tokens. These fields are preprocessing results, not independently verified numeric ground truth.

## 5. Entities: `entities_anno`

The example sentence has these primary entity annotations, shown with unused fields omitted:

```json
[
  {"type_": "cy", "start": 7, "end": 8},
  {"type_": "kpi", "start": 1, "end": 5}
]
```

Entity boundaries use **zero-based token positions with an inclusive start and exclusive end**. They are not character offsets or source line numbers.

```python
entity_text = " ".join(
    word["value"]
    for word in sentence["words"][entity["start"]:entity["end"]]
)
```

This gives:

- Entity index `0`: `262`, from tokens `[7:8]`.
- Entity index `1`: `allowance for credit losses`, from tokens `[1:5]`.

Joining tokens with spaces is sufficient for inspection. It does not reproduce original punctuation spacing exactly; retain `sentence.value` for source evidence and maintain an explicit alignment when character offsets are needed.

The primary entity types observed in the JSON are:

| Type | Interpretation |
|---|---|
| `kpi` | Metric name |
| `cy` | Current-year monetary value |
| `py` | Prior-year monetary value |
| `py1` | Monetary value from two years earlier |
| `increase`, `decrease` | Change from prior year to current year |
| `increase_py`, `decrease_py` | Change from two years earlier to prior year |
| `thereof` | Subordinate KPI belonging to a broader KPI |
| `attr` | Attribute describing a KPI |
| `kpi_coref` | Reference to a previously mentioned KPI |

The authors' [annotation guidelines](https://arxiv.org/html/2210.09163v1#S3) explain these roles. Some type names use hyphens in the paper and underscores in the JSON. A `cy` label expresses a relative period; it does not itself store a calendar year.

Other entity fields include `_value`, `score`, and `embedding`. They were null in the inspected examples. Recover entity text using the span rather than expecting `_value` to contain it.

## 6. Relations: `relations_anno`

The example sentence has this relation, again with unused fields omitted:

```json
[
  {
    "type_": "matches",
    "head_idx": 1,
    "tail_idx": 0,
    "is_symmetric": true
  }
]
```

`head_idx` and `tail_idx` index **`entities_anno`**, not the token array:

```text
entities_anno[1]                     entities_anno[0]
allowance for credit losses    ↔     262
```

All 3,722 primary relations inspected used the type `matches`. The endpoint entity types determine what a link means: a KPI and its value, a KPI and an attribute, or a broader KPI and a subordinate KPI. Do not assume that every relation creates a separate metric-value assertion.

Because the example relation is symmetric, the adapter must recognize endpoint roles from their entity types rather than assuming the head is always the KPI.

Fields such as `head_entity`, `tail_entity`, `score`, and `embedding` may be null. Resolve endpoints using the indices.

An illustrative conversion of this source into an assertion is:

```json
{
  "metric_name": "allowance for credit losses",
  "metric_value": "262",
  "unit": "Million USD",
  "period": "2020"
}
```

This object is not stored directly in KPI-EDGAR. The unit and period must be recovered from the evidence. `period` is a proposed benchmark qualifier, not a dedicated field in the current application schema; evaluation must define how the processor represents it in its existing fields.

## 7. IOBES Labels and Secondary Annotations

`entities_anno_iobes` represents the entity spans as one label per token:

| Prefix | Meaning |
|---|---|
| `B-` | Beginning of a multi-token entity |
| `I-` | Inside an entity |
| `E-` | End of an entity |
| `S-` | Single-token entity |
| `O` | Outside an entity |

For the example:

```text
allowance   for     credit  losses   ...   262
B-kpi       I-kpi   I-kpi   E-kpi    ...   S-cy
```

`entities_anno_iobes_ids` stores integer encodings of those labels for model training. Do not invent a mapping from integer to label; use the accompanying string labels or the repository's vocabulary. Explicit entity spans and relations are sufficient for a benchmark adapter.

`entities_anno_secondary` and `relations_anno_secondary` contain a second annotation set where available. Keep it separate from the primary annotations. Combining both sets would duplicate or conflate annotation decisions rather than add independent expected metrics.

## 8. Fit to the Application Schema

| Dataset information | Application output | Suitability |
|---|---|---|
| KPI entity | `metric_name_hint`, `metric_name` | Strong, allowing for name-boundary differences |
| Linked monetary value | `value_hint`, `metric_value` | Strong, after source-based validation |
| Currency and scale in source | `unit_hint`, `unit` | Useful, after normalization audit |
| Relative value type and source dates | Period-sensitive context / assertion identity | Requires explicit conversion policy |
| Attributes and subordinate KPIs | Context and qualifiers | Partial; mapping rules required |
| Token spans | `evidence_quote`, `source_line_spans` | Requires source alignment and line mapping |
| Categories, definitions, thresholds, translations | Enrichment fields | No direct gold labels |

Subject attribution may sometimes be recoverable from report metadata or text, but it is not a direct equivalent of a dedicated subject annotation.

There is also a policy mismatch. The paper describes selecting sentences containing monetary values and treating some forecasts as false positives. The application's metric definition is broader. An extraction absent from KPI-EDGAR's labels is therefore not automatically an incorrect application metric. Define the financial slice's scope and review disagreements before counting them as false positives.

## 9. Data-Quality Findings

Two concrete problems were observed in the downloaded JSON:

1. **Numeric preprocessing:** a token with `value: "6.7"` had `value_numeric: 67.0`; another with `value: "7.5"` had `value_numeric: 75.0`. Derive numeric gold from source text and validate scale separately.
2. **Token alignment:** in a sentence beginning `Upon adoption, the Company recorded`, the first `cy` span was `[6:7]`. Token 6 was `$`, while token 7 was `7.5`. The second monetary span in that sentence pointed to `8.1`. Thus, span alignment cannot be assumed correct for every record.

These observations establish that an audit is necessary; they do not establish the overall error rate. Check bounds, label-array lengths, reconstructed entity text, numeric consistency, and relation endpoint validity. Quarantine ambiguous cases for review. Do not silently repair the gold labels using model predictions.

## 10. Recommended Benchmark Design

### 10.1 Prepare and Freeze the Gold Data

- Pin the source revision and checksum; retain attribution and the repository license notice.
- Start with non-null split assignments. Keep unassigned sentences out of evaluation until their role is determined.
- Use training and validation examples for adapter development and prompt tuning; reserve the test set for evaluation.
- Retain document IDs and split boundaries when creating chunks or adding surrounding context.
- Audit entity spans and monetary normalization, recording every correction.
- Create one expected assertion per linked KPI–value pair, preserving period and qualifiers. Multiple years for the same KPI must remain distinguishable.
- Define conversion rules for attributes, subordinate KPIs, change values, and co-reference.
- Generate stable line-based inputs and retain document/segment/sentence/token provenance.
- Score only fields with verified annotations; mark unsupported fields as unscored rather than treating them as empty gold values.

### 10.2 Evaluate the Pipeline at Three Levels

| Evaluation | Input | Main measurements |
|---|---|---|
| Pass 1 candidate extraction | Source text | Candidate recall and evidence coverage |
| Pass 2 enrichment | Verified gold candidates plus source text | KPI–value association, value, unit, and period correctness |
| Full extraction pipeline | Source text through normal chunking and both passes | Assertion precision, recall, F1, duplicates, and unsupported values |

Use one-to-one prediction-to-gold matching so duplicate outputs cannot earn repeated credit. Report strict and tolerant name matching separately. Normalize equivalent monetary representations explicitly, for example `262 Million USD` and `262000000 USD`.

The paper's adjusted relation F1 gives partial credit for overlapping entity boundaries. It can be a supplementary measure when predictions are aligned to source tokens, but it does not evaluate the complete application schema. A converted assertion benchmark should not claim direct comparability with the paper's relation-extraction baselines unless it reproduces their task and scorer.

The production multi-pass pipeline and the older single-pass preview API described in the application spec should be identified separately in results. Database persistence, indexing, logging, and ontology harvesting require their own integration checks; KPI-EDGAR does not supply gold labels for those behaviors.

### 10.3 Add Application-Specific Coverage

Maintain a separate reviewed suite containing:

- English and Chinese standards and requirements.
- Tables with units and periods in headers.
- Inequalities, ranges, thresholds, targets, and formulas.
- Clauses delegating requirements to cited documents without local numbers.
- Non-metric numbers such as identifiers, dates, and section references.
- Chunk overlap, evidence ownership, and duplicate removal.
- Reviewed categories, subjects, and other enrichment fields where these are scored.

KPI-EDGAR can validate financial assertion extraction. The additional suite is needed to validate the broader `extract_metrics` contract.

## 11. References and Scope

- [KPI-EDGAR repository and citation](https://github.com/tobideusser/kpi-edgar)
- [Released JSON](https://github.com/tobideusser/kpi-edgar/blob/main/data/kpi_edgar.json)
- [KPI-EDGAR paper](https://arxiv.org/abs/2210.09163)
- [Repository MIT license](https://github.com/tobideusser/kpi-edgar/blob/main/LICENSE.md)
- [Application extraction specification](../../../../ChenWeb/KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md)

This resource records the dataset assessment, inspected JSON structure, known quality issues, and proposed evaluation approach. It does not change the application specification, implement a benchmark adapter, or establish a model baseline. Existing application documentation remains unchanged; no documentation was made stale by this write-up.
