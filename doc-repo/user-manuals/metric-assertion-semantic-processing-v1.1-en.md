---
title: Metric Assertions and Semantic Processing
language: en
format: markdown
version: 1.1
status: current
author: Not specified
owner: Not specified
audience: SemOS users, metric reviewers, and system operators
create-time: 2026-08-13T06:49:10-05:00
last-modify-time: 2026-08-13T16:35:53-05:00
keywords: metrics, metric assertions, semantic processing, normalize assertions, associate semantics, project semantics, ontology, governed terms, document pipeline, projections, classifications
---

# Metric Assertions and Semantic Processing

## 1. Purpose

This manual explains what happens after SemOS extracts a metric from a document. It focuses on three post-processing stages:

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
normalize_assertions (output: semantic decision candidates)
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

### 4.1 Metric

A **metric** is a measurable property, indicator, or specification value described in a document. Examples include luminance, noise level, response time, temperature, a percentage, a score, or a permitted range.

A metric occurrence normally contains more than a name. It can include:

- the name of the property being measured;
- the object or situation to which it applies;
- a value, range, limit, target, or qualitative result;
- a unit or measurement form;
- a condition or measurement context; and
- source text showing where the information came from.

The extracted metric row is document evidence. It is not automatically an accepted semantic assertion. The later Phase D stages determine how that occurrence should be represented and whether it can be accepted.

### 4.2 Metric name

The metric name is the wording found in the document, such as `luminance`, `亮度`, or `display luminance`. The original wording is retained as source information.

### 4.3 Keyword concept

A keyword concept groups name surfaces that the keyword module considers to be one lexical identity. For example, several spellings, capitalization variants, or approved translations may resolve to one concept.

The keyword concept answers:

> Which names belong together?

It is not itself the complete semantic assertion and is not the numeric value in the document.

### 4.4 Governed metric-definition term

A governed `metric_definition` term gives the metric a controlled ontology identity. A keyword concept can be aligned to such a term through an accepted `aligns_to_term` assertion.

The governed term answers:

> Which approved metric definition does this name represent?

### 4.5 Metric assertion

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

### 4.6 Doc Processor

A **doc processor** is one named stage in the document-processing pipeline. Each processor has one main responsibility and may read the document or an earlier processor's output, then save a result for later stages.

Examples include:

- `extract_metrics`, which extracts measurable values;
- `extract_provisions`, which extracts requirements and rules; and
- the three Phase D processors described in this manual.

The word “processor” describes a pipeline responsibility, not a single database table. One processor can read from one table and write to another, and some processors only create candidates or derived data rather than authoritative facts.

The three semantic processors run after the main extraction processors and are chained in a fixed order:

```text
normalize_assertions → associate_semantics → project_semantics
```

### 4.7 Artifacts

An **artifact** is a structured piece of evidence produced by document extraction. It represents something found in a particular document; it is not automatically a governed ontology term or an accepted assertion.

Examples include:

- a metric row in `kb.metrics`;
- a provision in `kb.provisions`;
- an extracted entity or relation; and
- an inventory or scene record stored by the relevant extraction processor.

Artifacts normally retain source information such as the input document, artifact identifier, source lines, and extracted text. Normalizers read artifacts and use them to propose semantic candidates. This separation lets the system preserve the original extraction even when later semantic interpretation is incomplete or deferred.

### 4.8 Consistent Assertion Shape

A **consistent assertion shape** is the common structure used to express different kinds of claims in a comparable way. It does not mean that every assertion has every field populated. It means that the same kinds of information have predictable places when they are available.

For a metric, the shape can include:

- a subject reference, such as the object being measured;
- a predicate, such as `mea:measured_by`;
- an assertion kind, such as `lower_bound_requirement` or `observed_value`;
- a value form, numeric value, range bounds, and comparator;
- a unit and, when resolved, a quantity-kind term;
- conditions and qualifiers;
- the original raw text; and
- evidence and provenance connecting the claim back to the artifact and source document.

`normalize_assertions` places an artifact into this common shape as a candidate. `associate_semantics` validates the candidate and persists it as an accepted assertion when the required references and governed terms are available.

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

#### Candidate status

`kb.semantic_decision_candidates.status` describes the processing state of a
proposed claim. It does **not** say whether the source metric was extracted
correctly. The source metric remains preserved even when its candidate cannot
yet be accepted.

| Status | What it means | How it is determined |
|---|---|---|
| `candidate` | The proposed claim is ready for semantic association. | `normalize_assertions` assigns this status when it creates a valid new candidate. |
| `in_review` | Association processing has claimed the candidate and is evaluating it. In this path, this is temporary processing state, not a human-review queue. | `associate_semantics` changes an eligible `candidate` to `in_review` before resolving it. A later run may resume a candidate left in this state by an interrupted run. Refer to the next section for `associate_semantics`. |
| `accepted` | The candidate has produced an accepted semantic assertion. | After validation succeeds, `associate_semantics` writes the assertion and its evidence, records the resulting assertion identifier on the candidate, and marks the candidate `accepted`. |
| `deferred` | The candidate is retained, but the system cannot safely accept it yet. | `associate_semantics` assigns this status when required information or governed vocabulary is unavailable, for example an unresolved subject, an unparsed value with no supported assertion kind, or a required term that is not released. The reason is recorded with the candidate. |
| `rejected` | The candidate is unusable because its stored proposal is structurally invalid. | `associate_semantics` assigns this status when it cannot read a malformed proposed payload. |
| `superseded` | An older candidate revision has been replaced by a newer proposal for the same logical identity. | Candidate proposal handling assigns this status when the proposed payload changes and a new revision is created. It is assigned at normalization time. Whenever a new revision (such as the same document re-extracts metrics), is proposed for the same `logical_identity_key, the prior revision is flipped to `supersedded` and given superseded_by = <new row id>. Records in 'superseded' are no longer used in the system.|

Association normally selects only `candidate` and temporary `in_review` rows.
A deferred row is therefore visible as unresolved work; it must be made
eligible for another attempt after the recorded dependency has been resolved.

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
- records status changes and deferrals; the assertion model also supports conflict or supersession relations when those relations are established.

#### What is the assertion-kind term?

The **assertion-kind term** is an ontology term that names the type of claim being made. It is not the candidate row and it is not the candidate table.

For example, if the candidate payload says:

```text
assertion_kind: lower_bound_requirement
```

the association stage looks for the governed ontology term:

```text
mea:lower_bound_requirement
```

That term is stored in `kb.ontology_terms`. In the current metric association path, the term must be an available released term (`status = 'included_in_release'`) before the metric assertion can be accepted. The candidate itself remains in `kb.semantic_decision_candidates`; it carries the proposed assertion kind but is not the assertion-kind term.

The two records have different jobs:

| Item | What it is | Current storage |
|---|---|---|
| Candidate | A proposed claim waiting for validation | `kb.semantic_decision_candidates` |
| Assertion-kind term | A governed vocabulary term describing the claim type | `kb.ontology_terms` |
| Accepted assertion | The validated claim about a particular subject | `kb.semantic_assertions` |

The predicate is a separate governed term. For a metric, the current path commonly checks `mea:measured_by` as the predicate and `mea:<assertion_kind>` as the assertion-kind term.

This stage is conservative. If required context or governed terms are unavailable, it defers the candidate rather than creating a misleading accepted fact.

#### What to expect

An accepted assertion is the authoritative semantic record for the claim. A deferred candidate remains visible as unresolved work and can be retried when its missing dependency becomes available.

### 5.3 `project_semantics`: build derived information

`project_semantics` is the third semantic stage. It reads accepted assertions and builds derived, rebuildable information for efficient use by the application.

It does not normally change the accepted assertion. Instead, it materializes a convenient result elsewhere, records which accepted assertion supports that result, and rebuilds it when the authoritative assertion changes.

#### What “update convenience classifications” means

An object can have one or more accepted classification assertions, for example:

```text
object A  --core:instance_of-->  display_module
```

The assertion in `kb.semantic_assertions` is the authoritative record. A convenience classification is a directly readable field maintained for common lookups, so the application does not need to search all accepted assertions every time it wants an object's primary class.

In the current implementation, `project_semantics`:

1. finds objects whose accepted `core:instance_of` assertions have evidence from the input record;
2. examines all accepted `core:instance_of` assertions for each affected object;
3. chooses the earliest accepted governed classification deterministically as the primary classification;
4. writes that term id to `kb.object_nodes.primary_class_term_id`; and
5. records the source assertion id and revision in `kb.projection_state`.

Several classifications can remain accepted in `kb.semantic_assertions`. `primary_class_term_id` is only a read-optimized pointer to one of them; it is not the authoritative list of all classifications. If no accepted classification remains, the projection clears the convenience field.

#### What “derived edges” means

An edge is a relationship represented as a link between two things, such as:

```text
object A  --instance_of-->  governed term B
artifact X --about------->  object A
```

In the general design, a projection builder would read accepted assertions, select a relationship that is useful for querying, and write a rebuildable link or other derived representation. The derived relationship is calculated from accepted assertions; it is not independently authored and it must not become a second source of truth.

The current implementation does not yet materialize a generic derived-edge table for all semantic relationships. The currently registered projection is the object classification projection described above. A future artifact-to-semantic link projection is expected to use a table such as `kb.artifact_semantic_links` when that family is implemented.

Do not confuse these possible derived edges with `kb.assertion_relations`. `kb.assertion_relations` records relationships between authoritative assertions, such as conflict or supersession, as part of association handling. It is not the current output of `project_semantics`.

#### Current outputs of `project_semantics`

For the current registered classification projection, the outputs are:

| Output | Purpose |
|---|---|
| `kb.object_nodes.primary_class_term_id` | A convenient primary classification for an object |
| `kb.projection_state` | Provenance and freshness information: projection kind, target, authoritative table, assertion id/revision, and stale status |
| stale status on projection state | Records that a rebuild failed and that repair is required later |

The processor also emits a run report containing counts such as targets examined, projections built, projections repaired, and errors. That report is operational telemetry, not semantic source data.

#### Does it only modify the output of `associate_semantics`?

No. It **reads** accepted output from `associate_semantics` and uses it as the authoritative source, but it writes separate derived outputs. It does not normally rewrite:

- `kb.semantic_decision_candidates`;
- accepted rows in `kb.semantic_assertions`; or
- the original extraction rows in `kb.metrics`.

If a projection build fails, the accepted assertion remains authoritative and the projection is marked stale in `kb.projection_state`. A later repair can replay the deterministic projection without re-extracting the document or re-adjudicating the assertion.

The projection registry is designed to support more projection kinds later, including derived search payloads or artifact-semantic links. Those are design extension points, not all current outputs of the present implementation.

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
| 1.1 | 2026-08-13T16:35:53-05:00 | Not specified | Clarification | Added the semantic decision-candidate status lifecycle, including how each status is assigned and retry eligibility. |
| 1.1 | 2026-08-13T06:49:10-05:00 | Not specified | Clarification and completion | Defined metric, doc processor, artifacts, and consistent assertion shape; explained assertion-kind terms, convenience classifications, derived edges, projection outputs, and the current implementation boundary. |
| 1.0 | 2026-08-13T06:07:41-05:00 | Not specified | Initial manual | Explained the three semantic processors, their metric relationship, execution status, and the current indirect linkage between metric identities and accepted assertions. |
