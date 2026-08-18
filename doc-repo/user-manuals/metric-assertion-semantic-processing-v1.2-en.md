---
title: Metric Assertions and Semantic Processing
language: en
format: markdown
version: 1.2
status: current
author: Not specified
owner: Not specified
audience: SemOS users, metric reviewers, and system operators
create-time: 2026-08-13T06:49:10-05:00
last-modify-time: 2026-08-17T06:27:25-05:00
keywords: metrics, metric assertions, semantic processing, normalize assertions, associate semantics, project semantics, ontology, governed terms, document pipeline, projections, classifications, governed vocabulary, value_range_type, application-ready metrics, assertion acceptance, metric quality
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
| `candidate` | The proposed claim is ready for semantic association. | `normalize_assertions` assigns this status when it creates a valid new candidate. This status means the record is ready for the next move (refer to the next section). |
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

After this stage, the metric has been made more comparable, but it is still a candidate. You should expect all the
records for the metrics with `status` = `candidate`, which means the metric passed this semantic step. 
If it is `deferred`, it means errors, such as the subject, assertion kind, or governed vocabulary is not yet sufficient.
If the same metric is re-extracted, its previous mapped record in this table will change its `status` to `superseded`, 
equivalent to being deleted. Records of this type will be eventually hard deleted.

#### Governed `value_range_type` mapping (added in v1.2)

A metric's `value_range_type` (for example `min`, `at least`, `不低于`) must map to one of a small set of canonical buckets 
(`lower_bound`, `upper_bound`, `exact`, `range`, `qualitative`, `limit_absent`) before it can be classified. This mapping 
is no longer a fixed list built into the code. It lives in a governed, operator-visible table, `kb.metric_value_range_type_map`, 
with one row per raw string seen in production:

| `status` | Meaning |
|---|---|
| `approved` | A human confirmed (or corrected) the bucket. Used to classify the metric. |
| `ambiguous` | A human reviewed the string and decided no bound direction can be inferred from it (for example `threshold`, `target`, `tolerance`). The metric stays unparsed by design — this is an expected, settled outcome, not an error. |
| `proposed` | Nobody has reviewed this string yet. The metric stays unparsed until it is triaged. |

The first time `extract_metrics` sees a `value_range_type` string that has no row yet, it auto-inserts one as `proposed` — every string is recorded and countable, never silently ignored. This check runs immediately after extraction (`extract_metrics`'s own post-processing step), not only later during association, so a new phrasing shows up as soon as it is extracted. If any metric on the record hit a `proposed` string, `extract_metrics` marks that specific `kb.metrics` row's `value_range_type_error` column with a short message and the `extract_metrics` stage itself is reported as failed for that record (see §9). The metric row is still saved exactly as extracted — nothing is dropped, only flagged.

An operator resolves a `proposed` row by setting its `status` to `approved` (confirming or correcting the suggested bucket) or `ambiguous` (recording that no direction can be inferred). There is no dedicated review screen yet; the table is queried directly. Once approved, previously blocked metrics on that string become eligible for the normal retry/backlog mechanisms.

### 5.2 `associate_semantics`: validate and accept candidate claims

`associate_semantics` is the second semantic stage. It processes candidates produced by the first stage and 
decides whether each one can become an accepted assertion.

For metric candidates, it:

- checks that the metric is attached to a subject object;
- checks that the assertion kind is supported by the governed measurement vocabulary;
- checks for required governed terms such as `mea:measured_by` and the relevant assertion-kind term;
- resolves the raw unit to a governed quantity/unit term when possible;
- preserves the metric name, value, unit, condition, and source text as assertion information;
- writes accepted assertions to `kb.semantic_assertions`;
- records evidence in `kb.assertion_evidence`; and
- records status changes and deferrals; the assertion model also supports conflict or supersession relations when those relations are established.

#### Outputs
- writes accepted assertions to `kb.semantic_assertions`;
- records evidence in `kb.assertion_evidence`; and

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

That term is stored in `kb.ontology_terms`. In the current metric association path, the term must be an available 
released term (`status = 'included_in_release'`) before the metric assertion can be accepted. The candidate itself 
remains in `kb.semantic_decision_candidates`; it carries the proposed assertion kind but is not the assertion-kind term.

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

#### Backstop check for ungoverned `value_range_type` vocabulary (added in v1.2)

`associate_semantics` runs after `extract_metrics` and is independently controlled by its own on/off setting, so it can run much later than extraction — or, in a deployment where it is disabled, not run at all. To make sure a `proposed` (unreviewed) `value_range_type` string is never silently invisible just because Phase D happens to be off or delayed, `associate_semantics` performs the same governed-vocabulary check as a backstop: a candidate deferred specifically because its `value_range_type` is still `proposed` also makes `associate_semantics` itself report failed for that record. A candidate deferred for any other reason (unresolved subject, an unreleased governed term, or a `value_range_type` already settled as `ambiguous`) does **not** cause a failure — those are expected, already-modeled outcomes with their own recovery path. Seeing both `extract_metrics` and `associate_semantics` fail on the same record for the same unreviewed string at the same time is expected, not a duplicate bug — approve or correct the string once, and both stages recover on their next run.

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

### 6.1 Layer 1: metric identity

The metric extraction path resolves the name:

```text
"亮度" / "luminance" / "display luminance"
    → keyword concept
    → governed metric_definition term
```

This makes differently worded occurrences recognizable as the same metric identity when the available evidence supports that conclusion.

### 6.2 Layer 2: metric occurrence and value

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

### 6.3 The tables are different roles, not additional ontology layers

The five tables named in this section do not all store ontology terms. They
store different kinds of information around a metric assertion:

| Table | Role in the metric flow | What it is not |
|---|---|---|
| `kb.semantic_decision_candidates` | A proposed interpretation of an extracted metric. `normalize_assertions` writes the candidate; `associate_semantics` validates it, accepts it, defers it, or rejects it. For each metric, there should be one or more records in this table. But only one is active. All others should be 'superseded' and should be eventually removed automatically. | It is not an accepted fact and it is not an ontology term. Its proposed payload may contain names such as `lower_bound_requirement`, but that text is only a proposal until it is checked against governed terms. |
| `kb.ontology_terms` | The governed vocabulary used to validate and describe the claim. Depending on the module and term kind, this can contain a metric definition, predicate, assertion-kind term, quantity-kind term, or unit term. Version and release status determine whether a term is available for association. | It is not the metric occurrence, its numeric value, or the document evidence. A term describes a controlled concept; it does not say that a particular document made a particular claim. |
| `kb.semantic_assertions` | The authoritative accepted claim about a particular subject or object. It stores the normalized assertion shape, such as predicate, assertion kind, value form, bounds, comparator, and resolved term references where available. | It is not a candidate and it is not a rebuildable search or display view. Accepted assertions are the source of truth for semantic claims. |
| `kb.assertion_evidence` | The provenance that supports or contradicts an assertion. It connects the assertion to the source metric artifact, document record, source lines or chunk, and producing run. | It is not a second assertion and it does not turn an unresolved candidate into an accepted one. It answers “where did this claim come from?” |
| `kb.projection_state` | Processing state for a derived projection built from accepted assertions. It records which authoritative assertion and revision support the projection and whether the projection is stale or needs repair. | It is not an ontology term, evidence, or an alternative source of truth. A stale projection does not make the accepted assertion stale. |

The relationship can be summarized as:

```text
extracted metric in kb.metrics
    │
    ├─ metric identity: keyword concept → metric_definition term
    │
    └─ normalize_assertions
          ↓
    kb.semantic_decision_candidates
          │  proposed value, subject, assertion kind, and source information
          │
          ├─ validated against available terms in kb.ontology_terms
          ├─ evidence retained for the source artifact
          ↓
    kb.semantic_assertions  ← authoritative accepted claim
          ├─ kb.assertion_evidence  ← provenance for the claim
          └─ project_semantics
                 ↓
             derived view + kb.projection_state
```

### 6.4 Which ontology terms participate in an assertion?

For a metric occurrence, ontology terms can participate in several different
ways. They should not be read as five separate identities for the metric:

| Ontology role | Example | How it is used |
|---|---|---|
| Metric definition | `measurement:luminance` | Gives the metric property a governed identity. The current accepted assertion path does not store this `metric_definition_term_id` as a direct assertion field; the connection remains through the source metric and its evidence. |
| Predicate | `mea:measured_by` | Describes the relationship expressed by the assertion. |
| Assertion kind | `mea:lower_bound_requirement` | Describes what kind of claim the occurrence makes: for example, a lower bound, upper bound, range, observation, target, reference, or capability. |
| Quantity kind | A governed luminance quantity-kind term | Enriches the meaning of the measured quantity when it can be resolved. |
| Unit | A governed `cd/m²` unit term | Identifies the unit in controlled vocabulary when it can be resolved. |

The candidate may contain a raw or normalized label for one of these roles,
but the accepted assertion uses governed term references only where the
association checks have resolved them. A missing or unreleased required term
can defer the candidate. A unit that cannot be resolved is best-effort
enrichment in the current metric path and does not necessarily prevent
acceptance.

### 6.5 Worked table trace

For this sentence:

```text
The display module shall provide a luminance of not less than 250 cd/m².
```

the records have these meanings:

1. `kb.metrics` preserves the extracted occurrence: `luminance`, the display
   module subject, `250`, `cd/m²`, the lower-bound wording, and the source span.
2. `kb.semantic_decision_candidates` proposes the interpretation
   `lower_bound_requirement`, with comparator `>=` and value `250`.
3. `kb.ontology_terms` supplies the governed terms used to validate the
   predicate and assertion kind, and may supply quantity-kind and unit terms.
4. `kb.semantic_assertions` stores the accepted claim if the subject and
   required governed terms pass validation.
5. `kb.assertion_evidence` connects that accepted claim back to the metric row
   and the document location.
6. `project_semantics` may create or refresh a registered derived view, while
   `kb.projection_state` records which assertion revision produced it and
   whether the view is current.

This is why “the attributes of extracted metrics are normalized” is only part
of the result. Normalization creates a candidate shape; association decides
whether the candidate can become an authoritative claim; evidence makes the
claim traceable; and projection makes selected consequences convenient to
query. The ontology terms govern the vocabulary used during that process, but
they do not replace any of those processing records.

### 6.6 When is a metric good enough for an application to use?

For this manual, a metric is **good** in the ontology sense when the system
has turned its extracted occurrence into a current, authoritative, traceable
semantic claim that an application may use as fact. This is stricter than
“a metric was extracted” and stricter than “a candidate was created.”

The current application-ready baseline is:

1. The source metric exists in `kb.metrics`.
2. Its current decision candidate is `accepted`, rather than `candidate`,
   `in_review`, `deferred`, `rejected`, or `superseded`.
3. That candidate points to a `kb.semantic_assertions` row whose status is
   `accepted`.
4. At least one `kb.assertion_evidence` row traces the assertion back to its
   metric artifact and document location.
5. The association stage has verified the required governed predicate and
   assertion-kind terms as `included_in_release`. It has also verified that
   the metric is attached to a subject object.

An application such as Document Review should treat the accepted assertion
and its evidence as the authoritative semantic result. It should not use a
raw `kb.metrics` row, or a candidate merely marked `candidate`, as though it
were already a governed fact.

The current model has one additional limitation for applications that group
or compare results by governed metric definition. The metric-definition term
is stored on the source metric and carried as qualifier information; it is
not yet a direct reference column on the accepted assertion. Such an
application must follow the assertion's evidence back to the source metric
to obtain `metric_definition_term_id`. Until a deployment adds a direct link,
“accepted assertion” and “directly queryable by metric-definition term” are
related but different levels of readiness.

#### 6.7 Outcomes that are not application-ready

| Candidate status | Meaning for an application | Is the metric good? |
|---|---|---|
| `candidate` | Normalization produced a proposed assertion, but association has not completed. | No, not yet. |
| `in_review` | Association is processing the proposal, or recovering after interruption. It is not a human approval state in this path. | No, not yet. |
| `deferred` | The source occurrence is preserved, but a required dependency is missing or unresolved, such as a subject object, supported assertion kind, or released governed term. | No, not yet; it may become good after the dependency is resolved. |
| `rejected` | The stored proposed payload is structurally unusable. | No. A corrected interpretation requires a new candidate revision. |
| `superseded` | A newer candidate revision replaced this one. | No for this old revision; it is historical rather than an error by itself. |
| `accepted` | Association created an accepted assertion and evidence. | Yes, at the current semantic-assertion level. |

This distinction is intentional. A deferred metric is not silently discarded
or labelled as an extraction error; it is known incomplete semantic work. A
rejected metric is an unusable proposed interpretation. Both must be excluded
from application decisions that require authoritative ontology-backed facts.

#### 6.8 Term status and processor responsibility

`kb.ontology_terms.status` is a governed-vocabulary lifecycle, not the
quality status of an individual metric occurrence. There is no one universal
meaning of “usable”; the required status depends on how a term is being used:

| Concern | Current rule |
|---|---|
| Keyword-concept alignment to a metric definition | The alignment path accepts an `included_in_release` or `auto-promoted` metric-definition term. Auto-promotion can occur during metric-name resolution, before Phase D. |
| Required predicate and assertion-kind terms during association | `associate_semantics` requires `included_in_release`, for example for `mea:measured_by` and `mea:lower_bound_requirement`. Otherwise it defers the candidate. |
| Unit and quantity-kind enrichment | The current path resolves these from `included_in_release` terms when possible, but unresolved units are best-effort enrichment and do not necessarily prevent acceptance. |
| `normalize_assertions` | Reads metric information and writes decision candidates. It does not change any ontology-term status. |
| `associate_semantics` | Reads governed terms to validate candidates, writes assertions and evidence, and changes candidate/assertion statuses. It does not change any ontology-term status. |
| `project_semantics` | Reads accepted assertions and their evidence to build derived views. It does not change any ontology-term status. |

Governed-term authoring, promotion, and release processes are responsible for
changing ontology-term status. They are separate from the three Phase D
semantic processors.

#### 6.9 What `project_semantics` currently does for metrics

`project_semantics` runs after `associate_semantics` for the same input
record. It reads accepted assertions that have evidence from that record and
then invokes each registered projection type.

The only registered projection today is the primary object-class projection:
accepted `core:instance_of` assertions can update
`kb.object_nodes.primary_class_term_id`, with `kb.projection_state` recording
the authoritative assertion and freshness. A normal metric assertion uses
`mea:measured_by`, not `core:instance_of`, so it normally creates no current
projection output. Future metric-specific projections, such as search payloads
or artifact-semantic links, may be registered later without changing the
accepted assertion itself.

#### 6.10 Relations
There are three tables:
- `kb.semantic_decision_candidates`
- `kb.semantic_assertions`
- `kb.assertion_evidence`

They form a pipeline:
```text
source artifact
   ↓
kb.semantic_decision_candidates
   ↓ accepted/adjudicated
kb.semantic_assertions
   ↓ supported or contradicted by
kb.assertion_evidence
```

`kb.semantic_decision_candidates` stores proposals: “this artifact may express this semantic assertion.” 
It supports deduplication, revisioning, resolution, deferral, and review.

`kb.semantic_assertions` stores the authoritative, normalized claim after a candidate is accepted. 
A candidate can link to its produced assertion through the nullable `resulting_assertion_id` foreign key.

`kb.assertion_evidence` stores provenance for an assertion: source artifact, quote/spans, extraction 
metadata, and whether the evidence supports or contradicts it. It links directly to `semantic_assertions.assertion_id`.

They are related through the following foreign keys:
| Source | Target | Foreign Key |
|--------|--------|-------------|
|`kb.semantic_decision_candidates` | `kb.semantic_assertions` | `kb.semantic_decision_candidates.resulting_assertion_id` |
| `kb.assertion_evidence` | `kb.semantic_assertions` | `kb.assertion_evidence.assertion_id` |

**Important distinctions**:

- Candidates are proposals; assertions are governed semantic records.
- Evidence does not point to candidates. It points only to assertions.
- A candidate does not necessarily produce an assertion—only successfully adjudicated assertion candidates do.
- One assertion can have multiple evidence rows, and conflicting assertions remain separate with independent evidence.
- Removing the last active supporting evidence can move an assertion from accepted to unsupported; restoring evidence can reactivate it.

Multiple metrics (occurrence) can point to the same kb.semantic_assertions, right? For instance, if two metrics A and B names map to the same kb.keyword_concepts, which will lead to the same kb.ontology_terms. When normalize_semantics run against A first, it may create the keyword concept, then the term. When it runs against B, it resolves to the same kb.keyword_concepts and kb.ontology_terms. Each run will generate its own kb.semantic_decision_candidates. When running associate_semantics, these two candidates will generate (map) to the same assertion but two difference kb.assertion_evidence. These evidences will point to the same assertion. Is this correct?
What happens if two evidence of the same assertion occurrs? Does it mean it will create two assertions instead of resolving to the same one?

#### 6.11 Relations of Semantically Same Metrics
Identify semantically the same artifacts and merge them to the same ontology term is one of the
most design goals of the ontology system. 

Assume we have two metrics: A and B, They are semantically the same. For instance, they are both for 
device display luminance. They are semantically the same.

Below is what happens in the current implementation:
1. Create assertion. If the same logical identity is processed again, the old assertion becomes `superseded`, a new revision row is created, and the new evidence points to the new revision.
2. Insert evidence pointing to that assertion
3. Transition assertion to accepted
4. Link candidate.resulting_assertion_id

In `associate_semantics`, `persistAssertion(...)` runs before `evStore.AddEvidence(...)`.

This is logical because `assertion_evidence.assertion_id` has a foreign key to an existing `semantic_assertions.id`;
evidence cannot be inserted first.

Metrics A and B use different candidate logical identities:
`metric:<record-id>:<metric-id>`
Those identities are copied directly to the assertions. Therefore A and B will create separate assertion rows,
followed by separate evidence rows:

```text
candidate A → assertion A → evidence A
candidate B → assertion B → evidence B
```

The system currently does not deduplicate assertions by “same keyword concept” or “same ontology term.” 
It only reuses the same assertion identity when the candidates share the same logical_identity_key. 
Thus semantic equivalence at the concept/term level does not currently cause assertion convergence.

If the intended model is:
```text
same canonical claim
├── evidence from metric A
└── evidence from metric B
```

then assertion identity must be computed from the canonical claim—not from the source metric occurrence. 
That would require a separate claim-key/deduplication design in associate_semantics, before creating the 
assertion. Evidence should still be inserted afterward.

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

### If `extract_metrics` or `associate_semantics` shows a failed status (added in v1.2)

Check `kb.metric_value_range_type_map` for rows with `status = 'proposed'` and a high `occurrence_count` — this is the most common cause. The affected `kb.metrics` rows are directly identifiable via their `value_range_type_error` column, and a `kb.doc_proc_logs` row with `entry_type = 'assertion_mapping_miss'` records which record and which strings triggered it. Approving or correcting the `proposed` row (setting `status` to `approved` or `ambiguous`) resolves the failure on the next processing attempt; the failure will recur on a naive retry until the row is triaged, since retrying does not itself change the governed table.

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

- `KnowledgeStore/doc-repo/adrs/202608/2026081401-adr-governed-metric-vocabulary-and-phase-d-failure-reporting.md`
- `KnowledgeStore/doc-repo/adrs/202608/2026081201-adr-auto-promoted-governed-terms.md`
- `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`

The ADR and capsule remain authoritative for implementation status, routing rules, schema details, and future changes.

## Change Log

| Version | Timestamp | Author / responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.2 | 2026-08-17T06:27:25-05:00 | Not specified | Clarification | Defined application-ready “good” metrics as accepted, traceable semantic assertions; distinguished deferred, rejected, superseded, and pending candidates; documented term-status gates, Phase D write boundaries, and the current metric projection limitation. |
| 1.2 | 2026-08-17T05:49:19-05:00 | Not specified | Clarification | Extended Section 6 to explain the distinct roles of `kb.semantic_decision_candidates`, `kb.ontology_terms`, `kb.semantic_assertions`, `kb.assertion_evidence`, and `kb.projection_state`, including their relationships and a worked table trace. |
| 1.2 | 2026-08-14T00:00:00-05:00 | Not specified | New capability | Documented the governed, DB-backed `value_range_type` mapping table (`kb.metric_value_range_type_map`) that replaced the hardcoded synonym list, `extract_metrics`'s extraction-time mapping check and `kb.metrics.value_range_type_error` flag, `associate_semantics`'s backstop check, and the resulting failed-status/retry operator workflow. |
| 1.1 | 2026-08-13T16:35:53-05:00 | Not specified | Clarification | Added the semantic decision-candidate status lifecycle, including how each status is assigned and retry eligibility. |
| 1.1 | 2026-08-13T06:49:10-05:00 | Not specified | Clarification and completion | Defined metric, doc processor, artifacts, and consistent assertion shape; explained assertion-kind terms, convenience classifications, derived edges, projection outputs, and the current implementation boundary. |
| 1.0 | 2026-08-13T06:07:41-05:00 | Not specified | Initial manual | Explained the three semantic processors, their metric relationship, execution status, and the current indirect linkage between metric identities and accepted assertions. |
