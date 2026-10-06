# MeasEval: Dataset Structure and Suitability for an `extract_metrics` Benchmark

Date: 2026-10-06  
Dataset: [harperco/MeasEval](https://github.com/harperco/MeasEval)  
Inspected revision: `1fa738b6bc9b72c84c88a80344ca3ab39a310a44`  
Application specification: [extract-metrics-spec.md](../../../../ChenWeb/KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md)  
Related assessment: [KPI-EDGAR](2026100601-rsc-key-edgar.md)

## 1. Assessment

MeasEval is a strong candidate for benchmarking the measurement-extraction portion of `extract_metrics`. Its annotations connect quantities and units to measured objects, properties, and qualifiers. This provides ground truth for both detecting quantitative assertions and attaching values to the correct subject and property.

In this assessment, MeasEval fits the application's general measurement extraction task better than KPI-EDGAR, whose emphasis is monetary KPI assertions. Neither dataset covers the complete application contract. MeasEval needs an adapter, a documented metric inclusion policy, and additional examples from the application's actual documents.

MeasEval was developed for SemEval-2021 Task 8, addressing counts, measurements, and their related contexts in scientific text. See the [task paper](https://aclanthology.org/2021.semeval-1.38/).

## 2. Annotation Model

The annotations form a small graph:

```text
MeasuredEntity --HasProperty--> MeasuredProperty --HasQuantity--> Quantity
       |                                                            ^
       +------------------------HasQuantity-------------------------+

Qualifier --Qualifies--> MeasuredEntity, MeasuredProperty, or Quantity
```

| Annotation | Role |
|---|---|
| `Quantity` | Count or measurement expression, potentially including modifiers |
| `MeasuredEntity` | Object or entity being measured |
| `MeasuredProperty` | Property of that object associated with the quantity |
| `Qualifier` | Context or conditions affecting interpretation |

Units and quantity modifiers are stored as quantity metadata in the official TSV representation. Properties and qualifiers are optional; quantities may also stand alone. The guidelines cover ranges, approximations, counts, lists, and tolerances. See the [annotation guidelines](https://github.com/harperco/MeasEval/blob/main/annotationGuidelines/README.md).

A relation-aware benchmark can distinguish a correct quantity assigned to the wrong object from a correctly extracted assertion. This is more informative than scoring the presence of metric names and numbers independently.

## 3. File Format

The official format is TSV, with paragraph text in separate `.txt` files. BRAT files support visualization and review. Use the official TSV files as the adapter's annotation input rather than counting duplicated BRAT text files as independent examples.

The TSV columns are:

```text
docId  annotSet  annotType  startOffset  endOffset  annotId  text  other
```

| Column | Meaning |
|---|---|
| `docId` | Paragraph identifier and link to its text file |
| `annotSet` | Logical group centered on one annotated quantity |
| `annotType` | Quantity, measured entity, measured property, or qualifier |
| `startOffset` | Inclusive character offset in the original paragraph |
| `endOffset` | Exclusive character offset |
| `annotId` | Annotation identifier, resolved within its document and annotation set |
| `text` | Annotated source text |
| `other` | JSON containing unit, modifiers, or relation targets |

Offsets are character positions, not token indices or application line numbers. Preserve the original text and Unicode representation so offsets remain valid. See the [repository format description](https://github.com/harperco/MeasEval#data-formats-and-availability).

### 3.1 Example From the Released Data

The evaluation paragraph `S0016236113008041-3257` includes this annotation group, shown with the shared document ID omitted:

| Set | Type | Start | End | ID | Text | `other` |
|---|---|---:|---:|---|---|---|
| 1 | Quantity | 323 | 338 | T1-1 | weight% of 0.34 | `{"unit": "weight%"}` |
| 1 | MeasuredProperty | 276 | 278 | T3-1 | Al | `{"HasQuantity": "T1-1"}` |
| 1 | MeasuredEntity | 301 | 317 | T2-1 | unreacted sample | `{"HasProperty": "T3-1"}` |

The graph connects the unreacted sample to the annotated property `Al`, then to its quantity. The source text supplies the weight-percentage interpretation. An adapter can separate the value `0.34` from the unit while retaining the original expression as evidence.

Do not silently replace the annotated property with a newly generated gold name such as "aluminum concentration." If normalized names are desired, review and record that normalization separately.

The same paragraph also contains an `IsList` quantity for `4.5 kg and 6 kg`. This illustrates why one annotation group cannot always be assumed to equal one scalar-valued application row.

Source: [example TSV](https://github.com/harperco/MeasEval/blob/main/data/eval/tsv/S0016236113008041-3257.tsv) and [paragraph text](https://github.com/harperco/MeasEval/blob/main/data/eval/text/S0016236113008041-3257.txt).

## 4. Inspected Dataset Counts

Direct inspection of revision `1fa738b6bc9b72c84c88a80344ca3ab39a310a44` produced:

| Split | Paragraph text files | Annotation TSV files | Quantities | Measured entities | Measured properties | Qualifiers |
|---|---:|---:|---:|---:|---:|---:|
| Trial | 65 | 65 | 281 | 273 | 179 | 99 |
| Train | 248 | 233 | 883 | 875 | 563 | 210 |
| Evaluation | 135 | 130 | 499 | 499 | 330 | 162 |

These are counts from the inspected repository, not an assumption that every text file has annotations. Training contains 15 text files without corresponding TSV files; evaluation contains five. Verify their intended status before treating them as negative examples.

Every inspected TSV annotation span reproduced its `text` exactly when sliced from the corresponding paragraph with its character offsets. This establishes offset consistency for the inspected files. It does not establish semantic correctness, annotation completeness, or relation validity.

### 4.1 Missing Property Annotations

Of the 499 evaluation quantity groups, 169 had no `MeasuredProperty` annotation. The evaluation groups all had measured entities, but the trial and training data each included eight groups without a measured entity.

Consequently, property-based `metric_name` ground truth is not available for every quantity. Missing annotations should not be replaced with invented gold fields. Either score the available fields independently or add reviewed labels.

### 4.2 Split Overlap

No paragraph identifiers overlapped between trial, training, and evaluation. However, using the portion before the final hyphen in a paragraph ID as its article identifier, the inspection found:

| Split pair | Shared article identifiers |
|---|---:|
| Trial / training | 14 |
| Training / evaluation | 48 |
| Trial / evaluation | 12 |

Preserve the official split when comparing with the published task. For generalization to unseen articles, construct and report an additional split grouped by source article. Do not describe paragraph separation as article separation.

## 5. Mapping to `extract_metrics`

| Dataset information | Application field or behavior | Assessment |
|---|---|---|
| Measured property | `metric_name_hint`, `metric_name` | Strong when explicit |
| Measured entity | `subject_hint`, `subject` | Strong |
| Quantity expression | `value_hint`, `metric_value` | Strong after separating value and unit |
| Quantity unit | `unit_hint`, `unit` | Strong, with a normalization policy |
| Quantity modifiers | `value_range_type`, `value_class`, `reasoning_tags` | Requires explicit mapping |
| Qualifier and its target | `context`, supporting evidence | Useful; retain target association |
| Character spans | `evidence_quote`, `source_line_spans` | Requires character-to-line mapping |
| Relations | Subject–property–value correctness | Particularly useful |
| Categories, translations, definitions | Corresponding enrichment fields | No direct gold labels |

This mapping is a proposed benchmark design, not an existing adapter. It does not imply every application field can be scored automatically.

The application uses a multi-pass production pipeline: candidate extraction, deterministic candidate merging, enrichment, and final deduplication. Its older single-pass preview API should be evaluated separately if included.

## 6. Adaptation Decisions

### 6.1 Measurement Versus Application Metric

MeasEval annotates scientific measurements and counts. Some experimental conditions or incidental quantities may be outside the intended application metric policy. Define the benchmark slice's inclusion rules before scoring. An unconverted annotation is not automatically a processor omission, and an unannotated extraction is not automatically a false positive.

### 6.2 Property-Less Quantities

For groups without a measured property, evaluate subject, quantity, unit, and evidence where annotated. If `metric_name` must be evaluated, add reviewed names or define an explicitly limited naming policy. Do not penalize a valid generated name solely because the dataset has no property label.

### 6.3 Lists, Ranges, and Tolerances

Define whether an `IsList` group maps to one list-valued metric or several assertions. Preserve bounds, inequality direction, approximation, and uncertainty. Use a reviewed mapping to the application's value fields rather than reducing every expression to one scalar.

### 6.4 Observations Versus Requirements

An inequality in a scientific result does not by itself establish a normative threshold. A reported value below a bound must not automatically become a requirement in `threshold_or_target`. Classify assertions using their source context.

### 6.5 Evidence Alignment

Maintain a character-to-line map for each paragraph. Retain source offsets, annotation group IDs, and relation endpoints in benchmark provenance. Exact source-span evaluation also requires aligning predicted names, subjects, and values to the original text; line spans alone are too coarse for the official span scorer.

### 6.6 Unsupported Enrichment Fields

Categories, translations, formulas, definitions, and measurement frequency do not have direct gold labels in this annotation model. Mark them unscored until reviewed ground truth exists. Empty gold placeholders would incorrectly penalize valid enrichment.

## 7. Recommended Evaluation

Evaluate three levels independently:

| Level | Input | Measurements |
|---|---|---|
| Pass 1 | Source paragraph text | Candidate recall and evidence coverage |
| Pass 2 | Verified gold candidates with source text | Subject, property, value, unit, and qualifier correctness |
| Full pipeline | Source text through normal chunking and both passes | Assertion precision, recall, F1, duplicates, and unsupported values |

For complete-assertion matching, compare the subject, property where available, quantity, unit, and essential qualifiers. Use one-to-one prediction-to-gold matching so duplicate predictions cannot earn repeated credit. Report field-level scores alongside complete-assertion scores, and distinguish strict source matching from reviewed semantic normalization.

Pin the source revision, conversion policy, scorer version, and evaluation manifest. Develop the adapter and tune prompts on training or development examples; reserve evaluation examples for measurement. Report failures and empty extraction results as part of the fixed evaluation set.

### 7.1 Official Scorer

The supplied local evaluator reports exact and overlap scores. It aligns contextual annotations with matching quantities, helping avoid credit for a correct object attached to the wrong value. It can be reused as a supplementary measure when processor outputs are converted to its TSV schema.

**The local evaluator ignores gold paragraphs absent from the submission.** Enforce manifest completeness and explicitly account for every missing, failed, or empty result. Otherwise, a partial submission can produce misleading results. Confirm how empty submissions are represented and scored before relying on the evaluator.

The official overlap score is not interchangeable with an application-specific complete-assertion F1. Label the two clearly and claim published-task comparability only when reproducing its task and scorer. See the [evaluation documentation](https://github.com/harperco/MeasEval/blob/main/eval/README.md) and [implementation](https://github.com/harperco/MeasEval/blob/main/eval/measeval-eval.py).

## 8. Complementary Benchmark Slices

| Slice | Main coverage |
|---|---|
| MeasEval | Measurements, counts, units, qualifiers, ranges, and subject association |
| KPI-EDGAR | Financial KPI–value associations and periods |
| Reviewed application documents | Chinese and English requirements, tables, formulas, delegated references, categories, and chunk overlap |

Prioritize MeasEval for the first general measurement benchmark. Start with verified entity–property–quantity groups, then expand to property-less quantities with explicit scoring rules. Keep results for each slice visible so a strong aggregate score cannot hide failures on application-specific requirements.

MeasEval does not provide gold expectations for database persistence, indexing, category governance, logging, ontology harvesting, or cross-document discovery. Those behaviors require separate integration checks.

## 9. Sources and Scope

- [MeasEval repository](https://github.com/harperco/MeasEval)
- [Task paper](https://aclanthology.org/2021.semeval-1.38/)
- [Annotation guidelines](https://github.com/harperco/MeasEval/blob/main/annotationGuidelines/README.md)
- [Evaluation documentation](https://github.com/harperco/MeasEval/blob/main/eval/README.md)
- [Evaluation implementation](https://github.com/harperco/MeasEval/blob/main/eval/measeval-eval.py)
- [Application specification](../../../../ChenWeb/KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md)
- [KPI-EDGAR assessment](2026100601-rsc-key-edgar.md)

This resource records the dataset assessment, inspected counts and alignment checks, schema mapping, and proposed evaluation approach. It does not implement an adapter or establish model performance. Application code and specifications remain unchanged; no existing documentation was made stale by this write-up.
