---
title: Metric Assertions and Semantic Processing
language: en
format: markdown
version: 1.0
status: current
author: Not specified
owner: Not specified
audience: ChenWeb users, metric reviewers, and system operators
create-time: 2026-08-13T06:07:41-05:00
last-modify-time: 2026-08-13T06:07:41-05:00
keywords: metrics, metric assertions, semantic processing, normalize assertions, associate semantics, project semantics, ontology, governed terms, document pipeline
---

# Metric Assertions and Semantic Processing

## 1. Purpose

This manual explains what happens after ChenWeb extracts a metric from a document. It focuses on three post-processing stages:

- `normalize_assertions`
- `associate_semantics`
- `project_semantics`

It also explains how these stages relate to metric-name resolution through keyword concepts and governed ontology terms.

The short version is:

> Metric-name resolution identifies the metric. Semantic processing identifies the claim made about that metric, validates it, and prepares it for use in searches and other views.

## 2. Who this is for

This manual is for people who:

- review extracted metrics;
- operate or configure the document-processing pipeline; or
- need to understand why an extracted metric is present but has not yet become a comparable semantic fact.

No programming knowledge is required. Database table names are included in backticks where they help an operator recognize a result in a diagnostic or review screen.

## 3. The complete metric path

An extracted metric passes through two related paths:

```text
Document text
    ↓
extract_metrics
    ↓
metric name resolution
    ├─ keyword concept
    └─ governed metric-definition term
    ↓
kb.metrics
    ↓
normalize_assertions
    ↓
candidate semantic assertion
    ↓
associate_semantics
    ↓
accepted semantic assertion
    ↓
project_semantics
    ↓
derived and query-optimized information
```

These paths answer different questions:

| Question | Responsible part of the system |
|---|---|
| What metric name did the document use? | `extract_metrics` |
| Which names or aliases represent the same metric identity? | Keyword module |
| Which governed metric definition does that identity refer to? | Ontology-term alignment |
| What value or requirement does this occurrence express? | `normalize_assertions` |
| Can that claim be attached to an object and expressed with valid governed terms? | `associate_semantics` |
| What derived data should be built for efficient use? | `project_semantics` |

## 4. Key concepts

### 4.1 Metric name

The metric name is the wording found in the document, such as `luminance`, `亮度`, or `display luminance`. The original wording is retained as source information.

### 4.2 Keyword concept

A keyword concept groups name surfaces that the keyword module considers to be one lexical identity. For example, several spellings, capitalization variants, or approved translations may resolve to one concept.

The keyword concept answers:

> Which names belong together?

It is not itself the complete semantic assertion and is not the numeric value in the document.

### 4.3 Governed metric-definition term

A governed `metric_definition` term gives the metric a controlled ontology identity. A keyword concept can be aligned to such a term through an accepted `aligns_to_term` assertion.

The governed term answers:

> Which approved metric definition does this name represent?

### 4.4 Metric assertion

A metric assertion is a claim about a particular occurrence of a metric. It combines information such as:

- the object or subject being measured;
- the metric value or range;
- the comparator, such as `>=` or `<=`;
- the unit;
- the assertion kind, such as a requirement, observation, target, or capability;
- the source text and evidence location.

For example:

```text
The display luminance of the module must be at least 250 cd/m².
```

This can become an assertion with:

```text
assertion kind: lower_bound_requirement
value: 250
unit: cd/m²
comparator: >=
```

## 5. The three semantic processors

### 5.1 `normalize_assertions`: turn extracted rows into candidate claims

`normalize_assertions` is the first semantic stage. It reads extracted artifacts and rewrites them into a consistent assertion shape.

For metrics, it currently:

- reads metric rows from `kb.metrics`;
- creates one candidate for each usable metric row;
- uses structured value fields when they are available;
- recognizes lower bounds, upper bounds, exact values, ranges, observations, targets, references, and capabilities where the extracted fields support them;
- falls back to parsing older free-text `threshold_or_target` values when structured fields are absent;
- preserves raw text and source evidence; and
- writes candidates to `kb.semantic_decision_candidates`.

It does not directly create an accepted semantic assertion.

#### Example

Suppose extraction produces:

```text
metric name: noise level
threshold or target: no more than 85 dB
subject: nighttime operation
```

The normalizer proposes a candidate similar to:

```text
assertion kind: upper_bound_requirement
value: 85
unit: dB
comparator: <=
subject: nighttime operation
```

If the value cannot be interpreted safely, the normalizer keeps the candidate with an `unparsed` value form instead of inventing a number or silently dropping the metric.

#### What to expect

After this stage, the metric has been made more comparable, but it is still a candidate. It may be deferred because the subject, assertion kind, or governed vocabulary is not yet sufficient.

### 5.2 `associate_semantics`: validate and accept candidate claims

`associate_semantics` is the second semantic stage. It processes candidates produced by the first stage and decides whether each one can become an accepted assertion.

For metric candidates, it:

- checks that the metric is attached to a subject object;
- checks that the assertion kind is supported by the governed measurement vocabulary;
- checks for required governed terms such as `mea:measured_by` and the relevant assertion-kind term;
- resolves the raw unit to a governed quantity/unit term when possible;
- preserves the metric name, value, unit, condition, and source text as assertion information;
- writes accepted assertions to `kb.semantic_assertions`;
- records evidence in `kb.assertion_evidence`; and
- records status changes, deferrals, and conflict or supersession information.

This stage is conservative. If required context or governed terms are unavailable, it defers the candidate rather than creating a misleading accepted fact.

#### What to expect

An accepted assertion is the authoritative semantic record for the claim. A deferred candidate remains visible as unresolved work and can be retried when its missing dependency becomes available.

### 5.3 `project_semantics`: build derived information

`project_semantics` is the third semantic stage. It reads accepted assertions and builds derived, rebuildable information for efficient use by the application.

It can:

- update convenience classifications;
- build derived edges and search payloads;
- maintain projection state;
- mark a projection stale when rebuilding fails; and
- repair stale projections later.

It does not replace the accepted assertion. The accepted assertion remains the authoritative record; projections are derived views that can be rebuilt.

The current implementation has a classification projection for object nodes. Additional metric-specific projections can be added as the system grows.

#### What to expect

Projection results may be delayed or marked stale even when the underlying assertion has already been accepted. This means the authoritative fact exists, but a derived view needs to be rebuilt.

## 6. How metrics relate to ontology terms

The relationship has two layers.

### Layer 1: metric identity

The metric extraction path resolves the name:

```text
"亮度" / "luminance" / "display luminance"
    → keyword concept
    → governed metric_definition term
```

This makes differently worded occurrences recognizable as the same metric identity when the available evidence supports that conclusion.

### Layer 2: metric occurrence and value

Semantic processing interprets the individual occurrence:

```text
"luminance must be at least 250 cd/m²"
    → lower-bound requirement
    → value 250
    → unit cd/m²
    → subject object
    → evidence from the document
```

The two layers are complementary:

| Metric-name resolution | Semantic processing |
|---|---|
| Identifies the metric property | Identifies the claim made about one occurrence |
| Groups names and aliases | Structures values, bounds, units, and conditions |
| Connects a concept to a governed `metric_definition` | Creates an assertion about an object or subject |
| Operates on metric identity | Operates on metric evidence and values |

## 7. Important current limitation

The metric identity and the semantic assertion are related, but the current implementation does not yet make the strongest possible direct link between them.

The extracted metric row can contain:

- `keyword_concept_id`; and
- `metric_definition_term_id`.

The metric normalizer currently carries the metric name and value information into the semantic candidate. The association stage validates measurement and assertion-kind terms and stores the metric name as qualifier information, but it does not currently store `metric_definition_term_id` as a direct reference on the accepted assertion.

Therefore, the present relationship is best understood as:

```text
metric identity is stored on kb.metrics
metric assertion is stored on kb.semantic_assertions
the connection is currently indirect through the source metric and evidence
```

This is sufficient for the current processing flow, but a direct governed-metric-term reference would make queries such as “show every assertion for this governed metric definition” more straightforward. Treat that direct linkage as a future enhancement unless the deployment has added it separately.

## 8. When the stages run

The three stages run after the main extraction processors finish. They are chained in this order:

```text
normalize_assertions → associate_semantics → project_semantics
```

They are routed post-process stages and are protected by the `SEMANTIC_ASSOCIATION_ENABLED` setting.

In the documented default configuration:

- semantic association is disabled unless explicitly enabled;
- the three stages are inert when the setting is false; and
- enabling the processors in a policy is not enough if the semantic-association setting remains disabled.

When enabled, these stages are telemetry-oriented post-processors and do not perform a second document-reading LLM pass.

## 9. What users should expect today

### If semantic processing is disabled

You may still see:

- extracted rows in `kb.metrics`;
- keyword-concept resolution results;
- governed metric-term identifiers where resolution succeeded; and
- no semantic assertion or projection for that metric.

This does not necessarily mean metric extraction failed. It may simply mean Phase D is disabled.

### If normalization ran but association did not accept a claim

Look for a candidate with a deferral reason such as:

- unresolved subject or referent;
- no governed assertion-kind term;
- governed measurement term not released; or
- an unparsed value.

The candidate should remain inspectable rather than disappearing.

### If association accepted the claim but a view is missing

Check projection state. The accepted assertion is authoritative; a missing or stale derived view indicates a projection problem, not necessarily an extraction or association problem.

## 10. Worked example from document to assertion

Consider this document sentence:

> The display module shall provide a luminance of not less than 250 cd/m².

The expected conceptual processing is:

1. `extract_metrics` records the metric name, value, unit, subject, and source span in `kb.metrics`.
2. The keyword module resolves `luminance` to a keyword concept.
3. The governed-term path resolves that concept to a `metric_definition` term when an accepted alignment exists.
4. `normalize_assertions` interprets “not less than 250” as a lower-bound requirement.
5. `associate_semantics` checks the subject and governed measurement terms, then persists an accepted assertion if the checks succeed.
6. `project_semantics` rebuilds any registered derived views affected by that accepted assertion.

The result is not merely “the document contains the word luminance.” It is a traceable claim with a metric identity, a value, a unit, a subject, and supporting evidence.

## 11. Limits and operator guidance

- A metric name and a metric assertion are different records with different purposes.
- Similar names do not automatically prove that two metrics are equivalent.
- A keyword concept does not automatically become a governed ontology term.
- An unparsed value must not be treated as a numeric result.
- A missing governed term can cause deferral even when the metric extraction itself is correct.
- A projection is derived data and can be rebuilt; it is not the source of truth.
- The current metric association path resolves quantity units as best-effort enrichment. A unit that cannot be resolved does not necessarily prevent acceptance of the assertion.
- The current Phase D implementation has metric and provision normalizers/resolvers. Inventory, entity, and scene families are extension points rather than equivalent fully implemented metric paths.

## 12. Reference documents

This manual is based on:

- `KnowledgeStore/doc-repo/adrs/202608/2026081201-adr-auto-promoted-governed-terms.md`
- `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`

The ADR and capsule remain authoritative for implementation status, routing rules, schema details, and future changes.

## Change Log

| Version | Timestamp | Author / responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.0 | 2026-08-13T06:07:41-05:00 | Not specified | Initial manual | Explained the three semantic processors, their metric relationship, execution status, and the current indirect linkage between metric identities and accepted assertions. |
