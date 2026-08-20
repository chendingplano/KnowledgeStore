---
title: Metric Assertions and Semantic Processing
language: en
format: markdown
version: 1.3
status: current
author: Not specified
owner: Not specified
audience: SemOS users, metric reviewers, and system operators
create-time: 2026-08-13T06:49:10-05:00
last-modify-time: 2026-08-20T07:55:00-05:00
keywords: metrics, metric assertions, semantic processing, normalize assertions, associate semantics, project semantics, ontology, governed terms, document pipeline, projections, classifications, governed vocabulary, value_range_type, application-ready metrics, assertion acceptance, metric quality, represented, lossless, raw-preserved, unsupported, semantic processing outcomes, findings, unresolved semantic occurrences
---

# Metric Assertions and Semantic Processing

## 1. Purpose

This manual explains what happens after SemOS extracts a metric from a document. It focuses on three post-processing stages:

- `normalize_assertions`
- `associate_semantics`
- `project_semantics`

It also explains how these stages relate to metric-name resolution through keyword concepts and governed ontology terms, and how they implement the **lossless semantic processing** model (ADR `2026081801`): a metric occurrence is never silently dropped just because it cannot yet be fully validated.

The short version is:

> Metric-name resolution identifies the metric. Semantic processing identifies the claim made about that metric, preserves it durably even when incomplete, and — separately — decides whether it is governance-endorsed and ready for use in searches and other views.

**This version (1.3) is a substantial update from v1.2.** The single biggest change: association no longer produces only "accepted" or "nothing." A candidate that clears normalization now almost always becomes a durable, visible `represented` semantic assertion — even when its value is unparsed, its mapping is unresolved, or its value is missing — instead of failing the pipeline or leaving the document silently incomplete. Read §5.2 and §6.6–§6.7 first if you already know v1.2.

## 2. Who this is for

This manual is for people who:

- review extracted metrics;
- operate or configure the document-processing pipeline; or
- need to understand why an extracted metric is present but has not yet become a comparable, governance-endorsed semantic fact.

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
represented semantic assertion  (durable, visible, not yet governance-endorsed)
    ↓  (separate governance step, optional and independently timed)
accepted semantic assertion
    ↓
project_semantics  (reads accepted assertions only)
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
| Can that claim be durably represented, and with what caveats? | `associate_semantics` |
| Is that represented claim endorsed as governance fact? | A separate governance decision, not automatic |
| What derived data should be built for efficient use? | `project_semantics` (accepted claims only) |

**Why the extra step matters:** under the pre-lossless model, a metric whose value could not be parsed, or whose `value_range_type` mapping was still unreviewed, simply had no path forward — the pipeline stage itself could fail, and no assertion existed for that occurrence at all. Under the current model, that same metric gets a `represented` assertion recording exactly what is known and what is not (§5.2, §6.7). Nothing that extraction identified is allowed to become invisible to semantic processing (ADR `2026081801` DR1).

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

The extracted metric row is document evidence. It is not automatically a governance-endorsed semantic assertion. The later Phase D stages determine how that occurrence should be represented and whether it is ever endorsed.

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
- the source text and evidence location; and
- four independent state dimensions describing exactly what is and is not yet known (§6.7): class identity, mapping resolution, value, and conformance.

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

An assertion's **lifecycle status** (`represented`, `accepted`, `rejected`, `deferred`, `superseded`, `unsupported`) is a separate concern from these value/class/mapping/conformance states. §6.7 explains why both exist and how to read them together.

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

**Metrics are not the only family this framework covers.** As of this version, `provision` (requirement/prohibition/permission clauses) is also wired into the same lossless framework, with its own, structurally simpler writer (provisions have no cross-document convergence, so they skip several mechanisms metrics use — see §6.9). This manual stays focused on metrics; provisions and future families (entities, inventory items, relations) will get their own manuals or manual sections as they mature. See ADR `2026081801` Appendix C.4 for the current scoping decision.

### 4.7 Artifacts

An **artifact** is a structured piece of evidence produced by document extraction. It represents something found in a particular document; it is not automatically a governed ontology term or a governance-endorsed assertion.

Examples include:

- a metric row in `kb.metrics`;
- a provision in `kb.provisions`;
- an extracted entity or relation; and
- an inventory or scene record stored by the relevant extraction processor.

Artifacts normally retain source information such as the input document, artifact identifier, source lines, and extracted text. Normalizers read artifacts and use them to propose semantic candidates. This separation lets the system preserve the original extraction even when later semantic interpretation is incomplete, deferred, or cannot yet be resolved.

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

`normalize_assertions` places an artifact into this common shape as a candidate. `associate_semantics` durably persists that candidate as a `represented` assertion whenever a subject can be resolved, recording explicitly whichever of the shape's fields could and could not be determined — it is no longer all-or-nothing (§5.2).

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

It does not directly persist a semantic assertion.

#### Candidate status

`kb.semantic_decision_candidates.status` describes the processing state of a
proposed claim. It does **not** say whether the source metric was extracted
correctly, and — since this version — it does **not** say whether the
resulting assertion is governance-endorsed. The source metric remains
preserved even when its candidate cannot yet produce a claim.

| Status | What it means | How it is determined |
|---|---|---|
| `candidate` | The proposed claim is ready for semantic association. | `normalize_assertions` assigns this status when it creates a valid new candidate. This status means the record is ready for the next move (refer to the next section). |
| `in_review` | Association processing has claimed the candidate and is evaluating it. In this path, this is temporary processing state, not a human-review queue. | `associate_semantics` changes an eligible `candidate` to `in_review` before resolving it. A later run may resume a candidate left in this state by an interrupted run. Refer to the next section for `associate_semantics`. |
| `accepted` | The candidate produced a persisted semantic assertion — normalized or raw-preserved. **This does not mean the assertion itself is governance-accepted** (§5.2, §6.7). Read the linked assertion's own `status` column for that. | After the atomic write succeeds, `associate_semantics` writes the assertion, evidence, and processing outcome, records the resulting assertion identifier on the candidate, and marks the candidate `accepted`. |
| `deferred` | The candidate is retained, but the system cannot yet persist any assertion for it — most commonly because the subject cannot be resolved. | `associate_semantics` assigns this status only when a required dependency genuinely blocks any persistence, for example an unresolved subject/referent. A merely unparsed value, an unresolved mapping, or a missing value no longer defers the candidate by themselves — those now produce a `represented` assertion recording that exact state (§5.2). |
| `rejected` | The candidate is unusable because its stored proposal is structurally invalid. | `associate_semantics` assigns this status when it cannot read a malformed proposed payload. |
| `superseded` | An older candidate revision has been replaced by a newer proposal for the same logical identity. | Candidate proposal handling assigns this status when the proposed payload changes and a new revision is created. It is assigned at normalization time. Whenever a new revision (such as the same document re-extracts metrics) is proposed for the same `logical_identity_key`, the prior revision is flipped to `superseded` and given `superseded_by = <new row id>`. Records in `superseded` are no longer used in the system. |

Association normally selects only `candidate` and temporary `in_review` rows.
A deferred row is therefore visible as unresolved work; it must be made
eligible for another attempt after the recorded dependency has been resolved.

**Important:** the set of things that now cause `deferred` is much smaller than it was in v1.2. In v1.2, an unparsed value, an unresolved mapping, or a missing value were the primary causes of deferral. As of this version, all three of those cases persist a `represented` assertion instead — deferral is now reserved for cases where no assertion can be written at all (chiefly an unresolved subject). See §5.2's disposition table.

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
If it is `deferred`, it means the subject could not be resolved, or the assertion kind is not one the governed measurement vocabulary supports at all — a smaller set of causes than before this version (see the note above).
If the same metric is re-extracted, its previous mapped record in this table will change its `status` to `superseded`, 
equivalent to being deleted. Records of this type will be eventually hard deleted.

#### Governed `value_range_type` mapping

A metric's `value_range_type` (for example `min`, `at least`, `不低于`) must map to one of a small set of canonical buckets 
(`lower_bound`, `upper_bound`, `exact`, `range`, `qualitative`, `limit_absent`) before it can be classified with an authoritative bucket. This mapping 
lives in a governed, operator-visible table, `kb.metric_value_range_type_map`, 
with one row per raw string seen in production:

| `status` | Meaning |
|---|---|
| `approved` | A human confirmed (or corrected) the bucket. Used to classify the metric. |
| `ambiguous` | A human reviewed the string and decided no bound direction can be inferred from it (for example `threshold`, `target`, `tolerance`). The metric's mapping stays unresolved by design — this is an expected, settled outcome, not an error. |
| `proposed` | Nobody has reviewed this string yet. The metric's mapping stays unresolved until it is triaged. |

The first time `extract_metrics` sees a `value_range_type` string that has no row yet, it auto-inserts one as `proposed` — every string is recorded and countable, never silently ignored. This check runs immediately after extraction (`extract_metrics`'s own post-processing step), not only later during association, so a new phrasing shows up as soon as it is extracted. If any metric on the record hit a `proposed` string, `extract_metrics` marks that specific `kb.metrics` row's `value_range_type_error` column with a short message; **`extract_metrics` itself is still reported as failed for that record** (this genuine execution-status behavior is unchanged by this version — DR12 supersedes the failure only for `associate_semantics`, not extraction; see §9). The metric row is still saved exactly as extracted — nothing is dropped, only flagged.

An operator resolves a `proposed` row by setting its `status` to `approved` (confirming or correcting the suggested bucket) or `ambiguous` (recording that no direction can be inferred) via **System Admin → Database Maintenance → Resolve Metric Range Types**. There is no dedicated review screen beyond that page. Once approved, previously blocked metrics on that string become eligible on their next processing attempt — approving a mapping does not itself retroactively reprocess existing `kb.metrics` rows (see §9's note on this).

### 5.2 `associate_semantics`: durably represent, then separately govern

`associate_semantics` is the second semantic stage. It processes candidates produced by the first stage and durably persists what can be determined about each one — even when that is incomplete — as a `represented` semantic assertion. This is the central behavior change from v1.2, implementing ADR `2026081801`'s lossless invariant (DR1).

For metric candidates, it:

- checks that the metric is attached to a subject object (this is the one thing that still defers, rather than represents, a candidate);
- resolves the governed measurement predicate (`mea:measured_by`) and, when the assertion kind is governed, the assertion-kind term;
- resolves the raw unit to a governed quantity/unit term when possible (best-effort; does not block persistence);
- classifies the metric's identity against a governed or provisional class and records `instance_of_term_id` on the assertion (§6.4);
- looks up the metric's `value_range_type` mapping (§5.1) and records the outcome as an independent **mapping resolution state**, whether or not it resolved;
- records an independent **value state** for the literal itself (present, unparsed, missing, datatype-mismatched), separately from mapping resolution;
- preserves the metric name, value, unit, condition, and source text as assertion information;
- writes the assertion to `kb.semantic_assertions` with lifecycle status `represented` (never `accepted` directly — see below);
- records a mandatory processing-outcome envelope and any findings to `kb.semantic_processing_outcomes` / `kb.semantic_processing_findings` (§5.2.2), one per required stage, whether the attempt found a problem or not;
- records evidence in `kb.assertion_evidence`; and
- records status changes and deferrals; the assertion model also supports conflict or supersession relations when those relations are established.

**`represented` is not `accepted`.** Lossless ingestion never writes `accepted` merely because a value parsed or a mapping resolved. `represented` means: *this is what the source expressed, and this is what the system could determine about it* — not *this claim is endorsed as true, valid, or ready for governance-gated use*. A claim moves from `represented` toward `accepted` only through the existing, separate governance review path (`represented → candidate → in_review → accepted`), which is not automatic and is not part of what `associate_semantics` does on ingestion.

#### 5.2.1 The four independent states on a `represented` assertion

Every assertion carries four state dimensions that can vary independently — a metric can be, for example, `resolved_existing` in class identity while `unparsed` in value:

| Dimension | Column | Example values |
|---|---|---|
| Class identity | `class_identity_state_term_id` | `resolved_existing`, `provisional_new`, `ambiguous_candidates`, `candidate_evidence_conflict` |
| Mapping resolution | `mapping_resolution_state_term_id` | `mapping_resolved`, `mapping_state_unresolved`, `mapping_state_ambiguous`, `mapping_not_required` |
| Value | `value_state_term_id` | `value_present`, `value_state_unparsed`, `value_state_missing`, `value_state_datatype_mismatch`, `value_state_unknown`, `value_state_not_applicable` |
| Conformance | `conformance_state_term_id` | `conforms`, `conformance_contract_violation`, `not_evaluated` |

None of these four states, by themselves, block the assertion from being written and made visible. This is a deliberate design choice (ADR `2026081801` DR9) so that "we don't yet know" and "we know and it's a problem" and "we know and it's fine" are always distinguishable, instead of being compressed into one pass/fail flag.

**A legacy note:** the 60 assertions written before this framework's gate went live (all with lifecycle status `accepted`) do not have these four columns populated — they predate DR6. This is expected, not a data-quality bug; those rows were never in scope for a retroactive backfill (ADR `2026081801` DR2: corrections are new revisions, never silent rewrites of history).

#### 5.2.2 The disposition table: what happens to each range-type mapping state

This is the direct replacement for v1.2's "backstop check" section. Every one of these outcomes produces a `represented` assertion — none of them fail `associate_semantics`:

| Mapping state | Assertion outcome |
|---|---|
| Approved mapping | Mapping resolved; authoritative bucket populated; disposition `normalized`. |
| Proposed (unreviewed) mapping | Mapping `unresolved`; parsed literal stays `present` if it parsed; disposition `raw_preserved`; finding `mapping_unresolved`. |
| Ambiguous mapping | Mapping `ambiguous`; candidate buckets recorded but non-authoritative; disposition `raw_preserved`; finding `mapping_ambiguous`. |
| Absent range-type field | Mapping `not_required` when inapplicable, otherwise `unresolved`; value handled independently. |
| Malformed/unparseable literal | Value `unparsed`, exact raw literal retained; disposition `raw_preserved`; finding `unparsed`. |

A metric with a `proposed` or `ambiguous` mapping, or an unparsed value, is therefore **visible today as a `represented` assertion with explicit findings** — not absent, not silently dropped, and not blocking the pipeline. Compare this with `extract_metrics`'s own, separate, still-unchanged failure behavior for a `proposed` string (§5.1, §9): the two stages can legitimately disagree about whether the record "failed," because they are answering different questions (execution health vs. semantic completeness — ADR `2026081801` DR3).

#### 5.2.3 Processing outcomes and findings

Every stage attempt — including a clean, uneventful one — records exactly one outcome envelope in `kb.semantic_processing_outcomes`, with zero or more typed findings in `kb.semantic_processing_findings` when something is worth flagging. This is what makes "was this ever processed, and what happened" answerable without reading log text: a missing outcome row means the attempt genuinely never happened; a present one with `finding_count = 0` means it ran clean.

This is operator/diagnostic infrastructure, not something most metric reviewers need to query directly — the Semantic Diagnostics tab in the doc-review UI (§6.7) already surfaces the states these outcomes determine. It matters mainly for troubleshooting "why does this metric look the way it does" beyond what the UI shows.

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
released term (`status = 'included_in_release'`) for the assertion to record it as governed. The candidate itself 
remains in `kb.semantic_decision_candidates`; it carries the proposed assertion kind but is not the assertion-kind term.

The two records have different jobs:

| Item | What it is | Current storage |
|---|---|---|
| Candidate | A proposed claim waiting for processing | `kb.semantic_decision_candidates` |
| Assertion-kind term | A governed vocabulary term describing the claim type | `kb.ontology_terms` |
| Represented / accepted assertion | The durably persisted claim about a particular subject | `kb.semantic_assertions` |

The predicate is a separate governed term. For a metric, the current path commonly checks `mea:measured_by` as the predicate and `mea:<assertion_kind>` as the assertion-kind term.

This stage still defers the candidate — rather than writing anything — when the subject itself cannot be resolved, since there is no artifact identity to attach a raw-preserved assertion to.

#### What to expect

A `represented` assertion is the durable record of what the source expressed and what the system could determine, whether or not it is governance-endorsed. A `deferred` candidate remains visible as unresolved work and can be retried when its missing dependency (almost always an unresolved subject) becomes available.

### 5.3 `project_semantics`: build derived information

`project_semantics` is the third semantic stage. It reads **accepted** assertions only and builds derived, rebuildable information for efficient use by the application. It does not read `represented` assertions — that is a deliberate, unchanged boundary (ADR `2026081801` DR6/DR8: governance-gated projections stay accepted-only, distinct from diagnostic/search consumers that may show represented claims with warnings).

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

No. It **reads** accepted output from `associate_semantics` and uses it as the authoritative source — never `represented` — but it writes separate derived outputs. It does not normally rewrite:

- `kb.semantic_decision_candidates`;
- assertions in `kb.semantic_assertions`, `represented` or `accepted`; or
- the original extraction rows in `kb.metrics`.

If a projection build fails, the accepted assertion remains authoritative and the projection is marked stale in `kb.projection_state`. A later repair can replay the deterministic projection without re-extracting the document or re-adjudicating the assertion.

The projection registry is designed to support more projection kinds later, including derived search payloads or artifact-semantic links. Those are design extension points, not all current outputs of the present implementation.

#### What to expect

Projection results may be delayed or marked stale even when the underlying assertion has already been accepted. This means the authoritative fact exists, but a derived view needs to be rebuilt. A `represented` (not yet accepted) assertion never has a projection at all — that is expected, not a bug to chase.

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
| `kb.semantic_decision_candidates` | A proposed interpretation of an extracted metric. `normalize_assertions` writes the candidate; `associate_semantics` persists it (`accepted` on the candidate row — meaning "produced an assertion", §5.1), defers it, or rejects it. For each metric, there should be one or more records in this table, but only one is active — all others are `superseded` and are eventually removed automatically. | It is not a governance-endorsed fact and it is not an ontology term. Its proposed payload may contain names such as `lower_bound_requirement`, but that text is only a proposal until it is checked against governed terms. |
| `kb.ontology_terms` | The governed vocabulary used to validate and describe the claim. Depending on the module and term kind, this can contain a metric definition, predicate, assertion-kind term, quantity-kind term, or unit term. Version and release status determine whether a term is available for association. | It is not the metric occurrence, its numeric value, or the document evidence. A term describes a controlled concept; it does not say that a particular document made a particular claim. |
| `kb.semantic_assertions` | The durable, normalized claim about a particular subject or object — `represented` by default, `accepted` only after separate governance review. It stores the normalized assertion shape, such as predicate, assertion kind, value form, bounds, comparator, resolved term references, and the four independent state dimensions (§5.2.1). | It is not a candidate and it is not a rebuildable search or display view. It is the source of truth for what was determined about a claim, whether or not that claim is yet governance-endorsed. |
| `kb.assertion_evidence` | The provenance that supports or contradicts an assertion. It connects the assertion to the source metric artifact, document record, source lines or chunk, and producing run. | It is not a second assertion and it does not turn an unresolved candidate into a persisted one. It answers “where did this claim come from?” |
| `kb.projection_state` | Processing state for a derived projection built from **accepted** assertions only. It records which authoritative assertion and revision support the projection and whether the projection is stale or needs repair. | It is not an ontology term, evidence, or an alternative source of truth. A stale projection does not make the accepted assertion stale, and a `represented`-only assertion never has one. |

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
    kb.semantic_assertions  ← represented (durable, may carry findings)
          │        ↓ separate governance decision
          │   kb.semantic_assertions  ← accepted
          ├─ kb.assertion_evidence  ← provenance for the claim
          ├─ kb.semantic_processing_outcomes / findings  ← what associate_semantics determined, stage by stage
          └─ project_semantics  (reads accepted only)
                 ↓
             derived view + kb.projection_state
```

### 6.4 Which ontology terms participate in an assertion?

For a metric occurrence, ontology terms can participate in several different
ways. They should not be read as five separate identities for the metric:

| Ontology role | Example | How it is used |
|---|---|---|
| Metric definition / class identity | `measurement:kwc_...` (a keyword-concept-derived class term) | Recorded directly as `instance_of_term_id` on the assertion since this version — resolved via `associate_semantics`'s class-resolution step (§5.2), no longer only indirect through the source metric and evidence (this replaces the "important current limitation" in earlier versions — see §7). |
| Predicate | `mea:measured_by` | Describes the relationship expressed by the assertion. |
| Assertion kind | `mea:lower_bound_requirement` | Describes what kind of claim the occurrence makes: for example, a lower bound, upper bound, range, observation, target, reference, or capability. |
| Quantity kind | A governed luminance quantity-kind term | Enriches the meaning of the measured quantity when it can be resolved. |
| Unit | A governed `cd/m²` unit term | Identifies the unit in controlled vocabulary when it can be resolved. |

The candidate may contain a raw or normalized label for one of these roles,
but the represented/accepted assertion uses governed term references only where
association has resolved them. A missing subject can still defer the candidate
entirely (§5.1); a missing or unreleased assertion-kind/predicate term is
recorded as an explicit finding rather than blocking persistence. A unit that
cannot be resolved is best-effort enrichment and does not affect persistence.

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
4. `kb.semantic_assertions` stores a `represented` claim once the subject
   resolves — whether or not every governed term or the range-type mapping
   also resolved.
5. `kb.assertion_evidence` connects that claim back to the metric row
   and the document location.
6. `kb.semantic_processing_outcomes`/`findings` record exactly what
   `associate_semantics` determined for each required stage, including a
   clean run with zero findings.
7. If and when a separate governance step promotes the claim to `accepted`,
   `project_semantics` may then create or refresh a registered derived view,
   while `kb.projection_state` records which assertion revision produced it
   and whether the view is current.

This is why “the attributes of extracted metrics are normalized” is only part
of the result. Normalization creates a candidate shape; association durably
represents whatever can be determined, whether complete or not; evidence
makes the claim traceable; governance separately decides endorsement; and
projection makes selected accepted consequences convenient to query. The
ontology terms govern the vocabulary used during that process, but they do
not replace any of those processing records.

### 6.6 When is a metric ready for what?

**This is the section that changed most since v1.2.** Under this version, "is this metric good?" is no longer one yes/no question — it is at least two different questions, and different applications should ask different ones.

**Is the metric durably represented?** (i.e., will a reviewer see it, with its raw value, normalized value if any, and explicit states, instead of it looking absent?)

1. The source metric exists in `kb.metrics`.
2. Its current decision candidate is `accepted` (meaning: produced a persisted assertion — §5.1), not `candidate`, `in_review`, `deferred`, `rejected`, or `superseded`.
3. That candidate points to a `kb.semantic_assertions` row whose lifecycle status is `represented` or later (`candidate`, `in_review`, `accepted`).
4. At least one `kb.assertion_evidence` row traces the assertion back to its metric artifact and document location.

This bar is met for the overwhelming majority of metrics that reach association today — including ones with an unresolved mapping or an unparsed value. **This is the bar the Semantic Diagnostics tab (doc-review UI) uses**: it shows every lifecycle status, including `represented`, with no default filter (ADR `2026081801` Appendix C.3).

**Is the metric governance-endorsed, ready for accepted-only consumers (governance decisions, profile-rule evaluation)?**

1. All four criteria above; and
2. The assertion's lifecycle `status` is specifically `accepted` — not merely `represented`.
3. Association verified the required governed predicate and assertion-kind terms as `included_in_release`.

Only assertions meeting this second, stricter bar should be used by an application that requires endorsed truth — governance workflows, profile-rule evaluation, and `project_semantics`'s own accepted-only read all draw this exact line. A `represented` assertion is not silently equivalent to an `accepted` one merely because it parsed cleanly; endorsement is always a separate step (§5.2).

Applications that are not making a governance decision — search, semantic discovery, diagnostics, Review Document — are expected to show `represented` assertions too, with their warnings visible, rather than hiding them (ADR `2026081801` DR8). Which bar to use is a per-consumer policy choice, not a single universal answer.

The current model still has one narrower limitation for applications that group or compare results by governed metric definition specifically (as opposed to the class term now on `instance_of_term_id`, §6.4): the original `metric_definition_term_id` used for keyword-concept alignment is stored on the source metric and carried as qualifier information, not as a second, separate column on the assertion. An application needing that specific field should follow the assertion's evidence back to the source metric.

#### 6.7 Reading assertion outcomes

Two different tables answer two different questions, and they must not be conflated:

**Is there a claim at all, and what happened while producing it?** — read the candidate's `status` (§5.1) plus, if you need the detail, the linked `kb.semantic_processing_outcomes`/`findings` rows.

**What is known about the claim itself, right now?** — read the assertion's own `status` (lifecycle) together with its four independent state columns (§5.2.1). A `represented` assertion with `value_state = value_state_unparsed` is a complete, correct answer to "what does the system currently know" — it is not an error state to be resolved before the metric "counts."

| Assertion lifecycle `status` | Meaning for an application |
|---|---|
| `represented` | Durably persisted from source, with explicit states for whatever could and could not be determined. Not yet governance-endorsed. Visible to diagnostic/search consumers; not to accepted-only consumers. |
| `candidate` / `in_review` | Selected for governance review; decision pending. |
| `accepted` | Governance-endorsed. Usable by any consumer, including `project_semantics`. |
| `rejected` | A governance decision determined the claim is not usable. |
| `deferred` (assertion-level; distinct from candidate-level `deferred`) | A governance review explicitly deferred a decision. |
| `superseded` | A newer revision under the same claim replaced this one. Historical, not an error by itself. |
| `unsupported` | The last active supporting evidence link was removed. The prior status is recorded (`unsupported_prior_status`) so restoring evidence returns to exactly that status rather than guessing or re-promoting it. |

This distinction is intentional. A `represented` metric with findings is not silently discarded or labelled as an extraction error; it is known, visible, incomplete semantic work — and that incompleteness is itself durable, structured information, not a placeholder to be cleaned up.

#### 6.8 Term status and processor responsibility

`kb.ontology_terms.status` is a governed-vocabulary lifecycle, not the
quality status of an individual metric occurrence. There is no one universal
meaning of “usable”; the required status depends on how a term is being used:

| Concern | Current rule |
|---|---|
| Keyword-concept alignment to a metric definition | The alignment path accepts an `included_in_release` or `auto-promoted` metric-definition term. Auto-promotion can occur during metric-name resolution, before Phase D. |
| Class identity resolution during association | `associate_semantics` resolves or provisionally creates a class term for `instance_of_term_id`; an unreleased or ambiguous case is recorded as an explicit class-identity state (§5.2.1), not a block on persistence. |
| Required predicate and assertion-kind terms during association | `associate_semantics` looks for `included_in_release`, for example for `mea:measured_by` and `mea:lower_bound_requirement`. An unreleased term is recorded as a finding on the `represented` assertion rather than deferring the candidate. |
| Unit and quantity-kind enrichment | The current path resolves these from `included_in_release` terms when possible, but unresolved units are best-effort enrichment and do not affect persistence. |
| `normalize_assertions` | Reads metric information and writes decision candidates. It does not change any ontology-term status. |
| `associate_semantics` | Reads governed terms to validate candidates, writes assertions/evidence/outcomes, and changes candidate/assertion statuses. It does not change any ontology-term status. |
| `project_semantics` | Reads accepted assertions and their evidence to build derived views. It does not change any ontology-term status. |

Governed-term authoring, promotion, and release processes are responsible for
changing ontology-term status. They are separate from the three Phase D
semantic processors.

#### 6.9 What `project_semantics` currently does for metrics

`project_semantics` runs after `associate_semantics` for the same input
record. It reads **accepted** assertions that have evidence from that record and
then invokes each registered projection type — `represented` assertions are
invisible to it by design (§5.3).

The only registered projection today is the primary object-class projection:
accepted `core:instance_of` assertions can update
`kb.object_nodes.primary_class_term_id`, with `kb.projection_state` recording
the authoritative assertion and freshness. A normal metric assertion uses
`mea:measured_by`, not `core:instance_of`, so it normally creates no current
projection output regardless of lifecycle status. Future metric-specific projections, such as search payloads
or artifact-semantic links, may be registered later without changing the
accepted assertion itself.

**Why provisions don't need everything metrics need:** provisions (the other family currently on this framework) skip the claim-registry/canonical-convergence machinery entirely (§6.10) because a provision clause is already its own atomic, uniquely identified source claim — two provisions are never "the same provision" merely because they share a modality, the way two documents can describe the same physical measurement. Metrics need convergence; provisions structurally don't. Expect each future family (entities, inventory items, relations) to need its own answer to this question rather than assuming either pattern generalizes.

#### 6.10 Assertion identity and convergence

**v1.2 posed this as an open question; it now has a settled answer.** Two metric occurrences that are semantically the same claim (for example, the same physical measurement described in two different source documents) are intended to converge onto one canonical claim, sharing one assertion with multiple evidence rows — not to silently produce two disconnected assertions.

This works through a **canonical claim registry** (`kb.semantic_claim_identities`, from ADR `2026081701`), not through the candidate's own `logical_identity_key` directly:

1. `normalize_assertions` still keys each candidate by its own occurrence-scoped `logical_identity_key` (`metric:<record-id>:<metric-id>`) — this identifies *the occurrence*, not the claim.
2. `associate_semantics` separately computes a **canonical claim key** for the underlying claim itself — derived from the normalized semantic value when one exists, or from a raw-value fingerprint plus class/context when it does not (§3.2 of the ADR). Two occurrences with the same canonical claim key resolve to the same claim.
3. The claim registry finds-or-creates one `kb.semantic_claim_identities` row per canonical claim key, and the assertion's own `logical_identity_key` is claim-registry-backed, not copied straight from the candidate.
4. `persistAssertion(...)` runs before `evStore.AddEvidence(...)` (evidence has a foreign key to an existing assertion, so it must come second) — one assertion, multiple evidence rows, if convergence occurs.

**What to expect in practice today:** in the live corpus as of this version, no two live metric occurrences have actually converged onto one shared assertion yet — every current metric assertion still has exactly one supporting evidence row (see the Phase 8 pre-cutover report, `openspec/changes/lossless-semantic-processing/phase8-precutover-report.md`, §4). This does not mean the mechanism is unused or unproven — it is exercised directly by integration tests — only that the current live corpus (a single pilot document) has not yet produced two occurrences of the same underlying claim to converge.

If you are troubleshooting "why do I have two assertions for what looks like the same fact," first check whether their canonical claim keys genuinely differ (different raw wording of a value that could not be parsed the same way converges differently than two clean parses of the same normalized value — ADR `2026081801` DR2's identity-branch rule) before assuming this is a bug.

#### 6.11 Relations

There are three core tables:
- `kb.semantic_decision_candidates`
- `kb.semantic_assertions`
- `kb.assertion_evidence`

They form a pipeline:
```text
source artifact
   ↓
kb.semantic_decision_candidates
   ↓ persisted (represented, then optionally accepted)
kb.semantic_assertions
   ↓ supported or contradicted by
kb.assertion_evidence
```

`kb.semantic_decision_candidates` stores proposals: “this artifact may express this semantic assertion.” 
It supports deduplication, revisioning, resolution, deferral, and review.

`kb.semantic_assertions` stores the durable, normalized claim once a candidate is persisted — `represented` first, `accepted` only via separate governance.
A candidate can link to its produced assertion through the nullable `resulting_assertion_id` foreign key.

`kb.assertion_evidence` stores provenance for an assertion: source artifact, quote/spans, extraction 
metadata, and whether the evidence supports or contradicts it. It links directly to `semantic_assertions.assertion_id`.

They are related through the following foreign keys:

| Source | Target | Foreign Key |
|--------|--------|-------------|
|`kb.semantic_decision_candidates` | `kb.semantic_assertions` | `kb.semantic_decision_candidates.resulting_assertion_id` |
| `kb.assertion_evidence` | `kb.semantic_assertions` | `kb.assertion_evidence.assertion_id` |

**Important distinctions**:

- Candidates are proposals; assertions are durably persisted records — `represented` or `accepted` are both real, both queryable, and mean different things.
- Evidence does not point to candidates. It points only to assertions.
- A candidate does not necessarily produce an assertion — a genuinely unresolved subject still defers it (§5.1).
- One assertion can have multiple evidence rows when convergence occurs (§6.10); conflicting assertions remain separate with independent evidence.
- Removing the last active supporting evidence can move an assertion from `represented`/`accepted`/etc. to `unsupported`; restoring evidence returns it to its recorded prior status (§6.7), never silently promoting it further.

## 7. Direct governed-term linkage (resolved since v1.2)

Earlier versions of this manual described an "important current limitation": the accepted assertion path did not store a direct reference to the metric's governed identity, so an application had to follow evidence back to the source metric to find `metric_definition_term_id`.

**This is now substantially addressed** for the class-identity dimension: `associate_semantics` resolves and records `instance_of_term_id` directly on the assertion (§6.4), giving a direct governed reference usable for "show every assertion for this class" queries without following evidence back to `kb.metrics`.

One narrower gap remains: the specific `metric_definition_term_id` used during keyword-concept alignment (a slightly different identity than the class term on `instance_of_term_id`) is still not duplicated as its own assertion column. Treat that specific field, and only that field, as still requiring the evidence-back-to-source-metric path described in §6.6.

## 8. When the stages run

The three stages run after the main extraction processors finish. They are chained in this order:

```text
normalize_assertions → associate_semantics → project_semantics
```

They are routed post-process stages, gated in two independent layers:

**Layer 1 — does the stage run at all?** Controlled by `SEMANTIC_ASSOCIATION_ENABLED` (default: `true`). When false, all three stages are inert — no candidates, no assertions of any lifecycle status, no projections.

**Layer 2 — once a stage runs, which write behavior does it use?** This layer did not exist in v1.2 and is new to this version:

| Gate | Default | Effect when on |
|---|---|---|
| `LOSSLESS_SEMANTIC_WRITES_METRIC` | **on** | `associate_semantics` uses the lossless writer described in §5.2 for metrics — `represented` assertions, outcomes, findings. |
| `LOSSLESS_SEMANTIC_WRITES_PROVISION` | off | Would enable the equivalent real writer for provisions. Certified and ready but not yet activated — a deliberate, separately-timed decision (ADR `2026081801` Appendix C.4). |
| `LOSSLESS_SEMANTIC_FALLBACK_WRITES` | on | For a registered family with no real instance writer yet, records a durable `kb.unresolved_semantic_occurrences` row instead of losing the artifact. Currently not exercising the fallback path for either metric or provision, since both have real writers or (for provision) the fallback already ran ahead of the real writer for most of the corpus. |

When `LOSSLESS_SEMANTIC_WRITES_METRIC` is off (an explicit rollback lever, not the default), `associate_semantics` falls back to the pre-lossless legacy write path this manual described in v1.2 — that code path still exists and is byte-for-byte unchanged, but it is not what a deployment running defaults will see.

When enabled, these stages are telemetry-oriented post-processors and do not perform a second document-reading LLM pass.

## 9. What users should expect today

### If semantic processing is disabled

You may still see:

- extracted rows in `kb.metrics`;
- keyword-concept resolution results;
- governed metric-term identifiers where resolution succeeded; and
- no semantic assertion or projection for that metric.

This does not necessarily mean metric extraction failed. It may simply mean `SEMANTIC_ASSOCIATION_ENABLED` is false (§8).

### If normalization ran but no assertion resulted at all

Look for a candidate with `status = deferred`. As of this version, the only common cause is an unresolved subject/referent — an unparsed value, unresolved mapping, or missing value no longer causes this (§5.1). The candidate should remain inspectable rather than disappearing.

### If an assertion exists but looks incomplete

Check the assertion's own `status` and its four independent state columns (§5.2.1, §6.7) — most likely it is `represented`, not yet `accepted`, and one or more of value/mapping/class/conformance state explains exactly what is unresolved. This is expected, durable output, not a processing failure to chase.

### If association accepted the claim but a view is missing

Check projection state. The accepted assertion is authoritative; a missing or stale derived view indicates a projection problem, not necessarily an extraction or association problem.

### If `extract_metrics` shows a failed status

Check `kb.metric_value_range_type_map` for rows with `status = 'proposed'` and a high `occurrence_count` — this is the most common cause. The affected `kb.metrics` rows are directly identifiable via their `value_range_type_error` column, and a `kb.doc_proc_logs` row with `entry_type = 'assertion_mapping_miss'` records which record and which strings triggered it. Approving or correcting the `proposed` row (setting `status` to `approved` or `ambiguous`) via **System Admin → Database Maintenance → Resolve Metric Range Types** resolves the failure — but note that action updates `kb.metrics.value_range_type` directly; it does not itself re-run `associate_semantics`. Whether the semantic assertion picks up the correction depends on the record later flowing through the ordinary document pipeline again (e.g., a normal reprocess), not on the approval action alone.

### If `associate_semantics` shows a failed status

As of this version, `associate_semantics` no longer fails on a proposed/ambiguous mapping, an unparsed value, or a missing value by themselves (§5.2.2) — those all produce a `represented` assertion instead. A genuine `associate_semantics` failure now means a real system-level problem (database, required service, or an invariant that blocks safe persistence), not a semantic finding. Treat it as an operational issue, not a vocabulary-triage task.

## 10. Worked example from document to assertion

Consider this document sentence:

> The display module shall provide a luminance of not less than 250 cd/m².

The expected conceptual processing is:

1. `extract_metrics` records the metric name, value, unit, subject, and source span in `kb.metrics`.
2. The keyword module resolves `luminance` to a keyword concept.
3. The governed-term path resolves that concept to a `metric_definition` term when an accepted alignment exists.
4. `normalize_assertions` interprets “not less than 250” as a lower-bound requirement.
5. `associate_semantics` resolves the subject and persists a `represented` assertion recording the governed measurement terms it could resolve, the mapping/value states it determined, and a mandatory processing outcome — whether or not every check succeeded.
6. A separate governance step may later promote that assertion to `accepted`.
7. `project_semantics` rebuilds any registered derived views affected once (and only once) the assertion is accepted.

The result is not merely “the document contains the word luminance.” It is a traceable claim with a metric identity, a value, a unit, a subject, supporting evidence, and explicit states for whatever could or could not be fully determined.

## 11. Limits and operator guidance

- A metric name and a metric assertion are different records with different purposes.
- Similar names do not automatically prove that two metrics are equivalent.
- A keyword concept does not automatically become a governed ontology term.
- An unparsed value must not be treated as a numeric result — but it is now visible as an explicit `represented` state, not absent.
- `represented` is not `accepted`. Do not treat a `represented` assertion as governance-endorsed fact; check its own lifecycle status.
- A missing governed term is now recorded as a finding on a `represented` assertion, not a silent deferral, except when the subject itself cannot be resolved.
- A projection is derived data and can be rebuilt; it is not the source of truth, and it only ever reflects `accepted` assertions.
- The current metric association path resolves quantity units as best-effort enrichment. A unit that cannot be resolved does not affect persistence.
- The current Phase D implementation has metric and provision normalizers/resolvers, both on the lossless framework (provision's own writer gate is off by deliberate choice — §8). Inventory, entity, and scene families are extension points rather than equivalent fully implemented paths.
- `kb.semantic_retry_queue` (dependency-driven retry for semantic findings) exists in schema but has no automated drain today — nothing currently claims and processes a queued retry job. In practice, re-processing the source document through the ordinary pipeline is what actually picks up a resolved dependency (such as an approved mapping), not this queue. Treat this as a known gap, not a mechanism to rely on (ADR `2026081801` Appendix C.5).

## 12. Writer-gate status (current, supersedes "shadow foundation model")

**This section replaces v1.2's "Shadow foundation model (certified; writers still off)."** That description is no longer accurate: the metric lossless writer is not in shadow mode — it is the live default write path (§8).

Current state, as of this version:

- `LOSSLESS_SEMANTIC_WRITES_METRIC` defaults **on**. Every metric assertion described in §5–§6 of this manual is what a default deployment actually produces today, not a future or shadow behavior.
- `LOSSLESS_SEMANTIC_FALLBACK_WRITES` defaults **on**. A registered family with no real instance writer gets a durable fallback occurrence instead of losing the artifact.
- `LOSSLESS_SEMANTIC_WRITES_PROVISION` defaults **off**. A real, certified, live-validated provision writer exists but activating it corpus-wide is a deliberate, separately-timed decision not yet made (ADR `2026081801` Appendix C.4).
- The class/instance foundation this section used to describe as "shadow" — stable classes, class contracts, canonical claim keys, term redirects, one-active-support-link cardinality — is now the live mechanism behind `instance_of_term_id` (§6.4) and claim convergence (§6.10) for metrics. It remains scoped to metrics only for now, by deliberate choice, not because it does not generalize (ADR `2026081801` Appendix C.4; the underlying architectural question about generalizing it further, Appendix A.3, remains open).
- Rollback lever: setting `LOSSLESS_SEMANTIC_WRITES_METRIC=false` restores the pre-lossless legacy write path exactly, without deleting any already-committed `represented` assertion or outcome history.

Operators should no longer read anything in this manual as describing a future or shadow state for metrics. For provisions, treat the writer as real and certified but not yet corpus-activated — see the Phase 8 pre-cutover report referenced in §6.10 for current corpus-wide numbers.

## 13. Reference documents

This manual is based on:

- `KnowledgeStore/doc-repo/adrs/202608/2026081801-adr-lossless-semantic-processing-and-knowledge-preservation.md` — the primary source for this version's changes: the `represented` lifecycle, the four independent state dimensions, processing outcomes/findings, the generic fallback mechanism, and the writer-gate model in §8/§12.
- `KnowledgeStore/doc-repo/adrs/202608/2026081401-adr-governed-metric-vocabulary-and-phase-d-failure-reporting.md`
- `KnowledgeStore/doc-repo/adrs/202608/2026081201-adr-auto-promoted-governed-terms.md`
- `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`
- `KnowledgeStore/doc-repo/adrs/202608/2026081701-adr-canonical-metric-classes-instances-and-semantic-relations.md` — owns the class/instance/claim-registry mechanism referenced in §6.4 and §6.10.
- `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- `ChenWeb/openspec/changes/lossless-semantic-processing/phase8-precutover-report.md` — current live corpus numbers referenced in §6.10 and §12.

The ADRs and capsule remain authoritative for implementation status, routing rules, schema details, and future changes.

## Change Log

| Version | Timestamp | Author / responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.3 | 2026-08-20T07:55:00-05:00 | Claude | ADR 2026081801 Phase 8 task 8.3 | Full rewrite for the lossless semantic processing model: the `represented` lifecycle status and its distinction from `accepted`; the four independent state dimensions (class identity, mapping resolution, value, conformance); the DR12 disposition table replacing most deferral causes; processing outcomes/findings; the layered writer-gate model (§8/§12) replacing the "shadow foundation" description; resolved the direct-governed-term-linkage limitation via `instance_of_term_id`; answered the assertion-convergence/claim-registry question v1.2 left open (§6.10); added the retry-queue known-gap note; added a short pointer to provisions as the framework's second family. |
| 1.2 | 2026-08-17T06:27:25-05:00 | Not specified | Clarification | Defined application-ready “good” metrics as accepted, traceable semantic assertions; distinguished deferred, rejected, superseded, and pending candidates; documented term-status gates, Phase D write boundaries, and the current metric projection limitation. |
| 1.2 | 2026-08-18T14:01:00-05:00 | Codex | Foundation documentation | Documented the certified stable-class, contract, profile, claim, redirect, and metric-support-cardinality shadow foundations; writer gates remain off. |
| 1.2 | 2026-08-17T05:49:19-05:00 | Not specified | Clarification | Extended Section 6 to explain the distinct roles of `kb.semantic_decision_candidates`, `kb.ontology_terms`, `kb.semantic_assertions`, `kb.assertion_evidence`, and `kb.projection_state`, including their relationships and a worked table trace. |
| 1.2 | 2026-08-14T00:00:00-05:00 | Not specified | New capability | Documented the governed, DB-backed `value_range_type` mapping table (`kb.metric_value_range_type_map`) that replaced the hardcoded synonym list, `extract_metrics`'s extraction-time mapping check and `kb.metrics.value_range_type_error` flag, `associate_semantics`'s backstop check, and the resulting failed-status/retry operator workflow. |
| 1.1 | 2026-08-13T16:35:53-05:00 | Not specified | Clarification | Added the semantic decision-candidate status lifecycle, including how each status is assigned and retry eligibility. |
| 1.1 | 2026-08-13T06:49:10-05:00 | Not specified | Clarification and completion | Defined metric, doc processor, artifacts, and consistent assertion shape; explained assertion-kind terms, convenience classifications, derived edges, projection outputs, and the current implementation boundary. |
