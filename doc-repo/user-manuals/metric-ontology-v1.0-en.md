---
title: Metric Ontology
language: en
format: markdown
version: 1.1
status: current
author: Not specified
owner: Not specified
audience: ChenWeb and SemOS users, ontology curators, reviewers, analysts, and system operators
create-time: 2026-08-20T16:37:47-05:00
last-modify-time: 2026-08-20T19:20:00-05:00
keywords:
  supplied: Metric Ontology
  generated: metric definition, measurement module, quantity module, QUDT, quantity kind, unit, dimension, observable property, feature of interest, procedure, assertion kind, governed vocabulary, ontology terms, class contract, ontology candidate, auto-promotion, module release, kb.ontology_terms, kb.ontology_modules, measurement:kwc, metric ontology model, metric lifecycle, ontology instance, instance_of, ontology object, object node, keyword concept, semantic assertion, class resolution, canonical claim identity, normalize_assertions, associate_semantics
---

# Metric Ontology

## 1. What this manual is for

A document might say **"Typical luminance: 500 cd/m²."** A second document might say **"亮度 ≥ 250 cd/m²."** A third might say **"Brightness: high."**

A person reading all three understands that they are about the same underlying idea, expressed differently, with different degrees of precision. A system does not understand that on its own. It needs an agreed set of meanings to connect the three statements — and it needs to record honestly when it cannot.

The **Metric Ontology** is that agreed set of meanings for everything the system measures. It supplies stable, reusable identities for the metrics themselves, for what they measure, for the units they are expressed in, and for the kinds of claims documents make about them.

This manual explains what the Metric Ontology contains, how its pieces fit together, how new vocabulary enters it, and what it can and cannot do today. It is written for people who use, curate, or review measurement information. You do not need to write code to use it.

**Scope note.** "Metric Ontology" is a descriptive name for a subject area, not the name of a single component or table. It refers to the parts of the governed ontology that describe measurement — chiefly the `measurement` and `quantity` modules and the metric-related term kinds. You will not find a component called "metric ontology" in the system.

## 2. What the Metric Ontology is — and is not

The Metric Ontology is a **vocabulary of meanings**, not a store of measurements.

For a metric `Display luminance` as an ontology entity:

| It holds | It does not hold |
|---|---|
| The identity of the metric *display luminance* | The observed value `500 cd/m²` from a particular document |
| The measurable quality *luminance* | The sentence a document used to state it |
| The unit *candela per square metre* | Which product passed or failed a threshold |
| The kind of claim *lower-bound requirement* | Whether a claim is true, accepted, or compliant |

The distinction matters constantly in practice. In the phrase "display luminance is at least 250 cd/m²," almost every part belongs to a different place:

| Part of the phrase | Where it belongs |
|---|---|
| "display luminance" — the metric being discussed | Metric Ontology, as a metric definition |
| "luminance" — the measurable quality | Metric Ontology, as a quantity kind |
| "cd/m²" — the unit | Metric Ontology, as a unit |
| "is at least" — the kind of claim | Metric Ontology, as an assertion kind |
| "250" — the value actually stated | The extracted record and its semantic assertion, not the ontology |
| The sentence and its page location | The source artifact and its evidence, not the ontology |

The ontology is reusable across every document. The value and its wording belong to one document and stay with that document. Keeping them apart is what lets the system compare a claim in one standard against a claim in another without pretending the two documents used identical words.

## 3. The building blocks

### 3.1 Modules

Governed vocabulary is organized into **modules**, each owning a coherent area of meaning and declaring which other modules it depends on. Six modules were active in the `miner` database at 2026-08-20:

| Module | Covers | Depends on |
|---|---|---|
| `core` | Shared semantic foundations | — |
| `quantity` | Quantity kinds, units, and dimensions (QUDT) | `core` |
| `measurement` | Metrics, observable properties, procedures, assertion kinds | `core`, `quantity` |
| `document-authority` | The standing and authority of source documents | `core` |
| `semantic-processing` | Processing states, stages, and severities | `core` |
| `provision` | Provisions | `core` |

Two of these carry the Metric Ontology proper: **`measurement`** describes metrics and the claims made about them, and **`quantity`** supplies the measurement science it builds on. The dependency is deliberate — a metric in `measurement` refers to a quantity kind and unit that `quantity` defines, so measurement vocabulary never has to reinvent units.

### 3.2 Terms

The individual entries are **governed terms**, each with a stable namespaced identifier such as `quantity:qk_Luminance` or `mea:has_unit`. The identifier is the identity: it is what other records point at, and it stays fixed even when the term's description is revised. Terms are versioned, carry a lifecycle status, and belong to exactly one module.

Every term has a **kind** that says what sort of thing it is. Eight kinds are permitted:

| Kind | What it identifies | Example |
|---|---|---|
| `metric_definition` | A metric that can be measured, assessed, or compared | Display luminance |
| `quantity_kind` | The measurable quality itself, independent of unit or value | `quantity:qk_Luminance` |
| `unit` | A standardized way of expressing a value | `quantity:unit_CD-PER-M2` |
| `dimension` | The physical dimensional structure of a quantity | Luminous intensity per area |
| `class` | A category whose members share a defined type or role | `mea:feature_of_interest` |
| `property` | A named relationship or attribute connecting things | `mea:has_unit` |
| `concept` | A controlled idea used for organizing or labeling | `semantic:normalized` |
| `individual` | A specific named thing rather than a category | — |

> **Correction to existing documentation.** The *Governed Ontology Terms Guide* (v1.0) states that there are seven kinds and instructs readers to use `quality_kind` rather than `quantity_kind`. The deployed database constraint permits the eight kinds above; it accepts **`quantity_kind`** and rejects `quality_kind`, and it also permits `individual`, which that guide omits. Use the values in this table. The other guide needs correction; that correction is outside the scope of this manual.

Terms are given readable names by separate **label** records rather than by the identifier itself, so one term can be shown as "Luminance" in English and 亮度 in Chinese while remaining a single governed identity. Labels are covered by the *Ontology Labels Guide*.

### 3.3 How much vocabulary exists

Observed in the `miner` database at 2026-08-20, only one document is processed: 4,606 term rows covering 4,404 distinct term identifiers, of which 4,546 rows were `included_in_release` and 60 were `auto-promoted`.

| Module | Kind | Terms |
|---|---|---|
| `quantity` | `unit` | 2,843 |
| `quantity` | `quantity_kind` | 1,125 |
| `quantity` | `dimension` | 245 |
| `measurement` | `metric_definition` | 61 |
| `measurement` | `property` | 51 |
| `measurement` | `class` | 30 |
| `core` | `property` | 66 |
| `core` | `class` | 54 |
| `document-authority` | `concept` | 56 |
| `document-authority` | `class` | 10 |
| `document-authority` | `property` | 10 |
| `semantic-processing` | `concept` | 51 |
| `provision` | `property` | 4 |

The shape of this table is worth reading. The `quantity` module accounts for 4,213 of the terms because measurement science is large, stable, and imported wholesale from QUDT. The `measurement` module is small by comparison because it supplies a compact frame — a handful of classes and properties — that the large quantity vocabulary plugs into. Growth happens mostly in metric definitions, as documents introduce metrics the system has not seen before.

## 4. How the ontology describes a metric

### 4.1 The measurement frame

The `measurement` module provides six classes. Together they answer the questions that make a measurement interpretable:

| Class | Question it answers | Definition as recorded |
|---|---|---|
| `mea:feature_of_interest` | What is this about? | The entity a metric is asserted about, such as a display module. |
| `mea:observable_property` | What is being measured? | The property being measured, such as luminance or response time. |
| `mea:procedure` | How was it measured? | The test method or procedure that produces the value. |
| `mea:condition` | Under what circumstances? | The operating or test conditions under which an assertion applies. |
| `mea:aggregation_window` | Over what span? | The time or count window an aggregated metric covers. |
| `mea:metric_assertion` | What is being claimed? | A normalized assertion assigning a value to a metric for a feature of interest. |

These matter because the same number means different things under different frames. "80 °C" measured on a battery cell is not "80 °C" measured on an enclosure surface; a value averaged over an hour is not the same claim as an instantaneous peak. Recording the feature of interest, the procedure, the conditions, and the window is what makes two claims genuinely comparable rather than superficially similar.

Three properties bind a metric to its measurement science:

| Property | What it binds |
|---|---|
| `mea:has_quantity_kind` | Binds a metric or value to its quantity kind. |
| `mea:has_unit` | Binds a value to its unit term. |
| `mea:measured_by` | Binds a metric to the procedure that measures it. |

### 4.2 The quantity chain

Quantity kind, dimension, and unit form a chain, and each link does a job the others cannot:

```text
quantity_kind    what is measured                  Luminance
      |
dimension        which units are compatible        luminous intensity per area
      |
unit             how a value is written            candela per square metre
```

The dimension is the link people most often overlook, and it is the one that prevents nonsense. It is what allows the system to know that candelas per square metre and nits are interchangeable, while candelas per square metre and degrees Celsius are not — regardless of how similar or dissimilar their names happen to look.

### 4.3 Assertion kinds

Documents do not only report measurements. They set requirements, state targets, cite references, and claim capabilities. The `measurement` module distinguishes eight kinds of claim, each a property:

| Assertion kind | Definition as recorded |
|---|---|
| `mea:observed_value` | Assertion kind: a measured test result. |
| `mea:exact_value` | Assertion kind: an exact required value. |
| `mea:lower_bound_requirement` | Assertion kind: the value must be at least the stated limit. |
| `mea:upper_bound_requirement` | Assertion kind: the value must be at most the stated limit. |
| `mea:interval_requirement` | Assertion kind: the value must fall within the stated interval. |
| `mea:target` | Assertion kind: a design target value. |
| `mea:reference` | Assertion kind: a reference value for comparison. |
| `mea:capability` | Assertion kind: a capability claim of the product. |

This distinction carries real consequences. "Luminance is 300 cd/m²," "luminance must be at least 300 cd/m²," and "luminance is targeted at 300 cd/m²" share a number and a unit but support entirely different conclusions. Only the second can be failed. Treating them as one claim would let a design target be reported as a compliance requirement — which is why the system records the kind of claim as deliberately as it records the value.

## 5. The Metric Ontology model

Sections 3 and 4 describe the vocabulary itself. This section places a metric inside the full set of records that surround it, and marks which of those records are ontology entities and which are not.

The distinction is worth stating explicitly because these entities look alike in a listing and behave nothing alike. A governed term is authored once and reused by every document afterwards. A metric row belongs to one document and is replaced when that document is read again. A keyword concept and an object are neither: they are corpus-level identities that outlive any single document but carry no governance status at all.

### 5.1 Three populations

| Population | Where it comes from | Scope | What reprocessing a document does to it |
|---|---|---|---|
| **Ontology-born** — governed vocabulary | Curation, external import, or auto-promotion | Global; any document may point at it | Nothing. Terms are versioned and superseded, never rewritten in place. |
| **Corpus-level identity** | Resolution and reconciliation across documents | Shared by every document that names the same thing | Nothing, normally. Identities are merged or deprecated with a tombstone, never deleted. |
| **Record-born** | One extraction run over one document | One input record | Replaced. The prior extraction's rows are removed and rewritten. |

A single metric touches all three at once. The metric row is record-born. The metric definition it resolves to is ontology-born. The keyword concept behind its name, and the object it is measured on, are corpus-level.

### 5.2 The ontology-born entities

| Entity | Recorded in | Its role for a metric |
|---|---|---|
| **Module** | `kb.ontology_modules` | Owns an area of meaning and declares its dependencies (§3.1). |
| **Module release** | `kb.ontology_module_releases`, `kb.ontology_active_releases` | Publishes a set of approved terms; one active per module, which is what makes a past interpretation reproducible. |
| **Governed term** | `kb.ontology_terms`, with stable identity in `kb.ontology_term_headers` | The reusable unit of meaning: identifier, kind, module, version, status. |
| **Metric definition** | a term of kind `metric_definition` | The governed identity of the metric — what *display luminance* is, independent of any document. |
| **Quantity kind** | `quantity:qk_*` | The measurable quality (§4.2). |
| **Unit** | `quantity:unit_*` | How a value is written. |
| **Dimension** | the `quantity` module | Which units are mutually compatible. |
| **Measurement class** | `mea:feature_of_interest`, `mea:observable_property`, `mea:procedure`, `mea:condition`, `mea:aggregation_window`, `mea:metric_assertion` | The frame that makes a value interpretable (§4.1). |
| **Metric class** | a term of kind `class` in the `measurement` module | The identity a stored claim declares itself an instance of (§5.5). |
| **Binding property** | `mea:has_quantity_kind`, `mea:has_unit`, `mea:measured_by` | Attaches a metric to its measurement science. |
| **Assertion kind** | `mea:observed_value` … `mea:capability` | What sort of claim is being made (§4.3). |
| **Cross-family predicate** | `core:aligns_to_term`, `core:instance_of` | Connects a keyword concept to a governed term, and a record to its class. |
| **Processing-state concept** | `semantic:*` | Names what a processing stage determined — including what it could not determine. |
| **Label** | `kb.ontology_term_labels` | Readable, language-specific names for a term. |
| **Class contract revision** | `kb.ontology_class_contract_revisions` | The fuller definition of a class: value type, permitted units, constraints, capabilities (§10.1). |
| **Ontology candidate** | `kb.ontology_candidates` | Proposed vocabulary. Not a term yet, and never usable as one. |
| **Governed value mapping** | `kb.metric_value_range_type_map` | Governed but not an ontology term: maps the free-text `value_range_type` a document produced onto a canonical bucket. |

### 5.3 The corpus-level identities

| Entity | Recorded in | Its role for a metric |
|---|---|---|
| **Keyword concept** | `kb.keyword_concepts`, with observed spellings in `kb.keyword_surfaces` | Groups the different names people use for one thing. It is not governed vocabulary and has no review lifecycle; its statuses are `active`, `provisional`, `merged`, `deprecated`. |
| **Object node** | `kb.object_nodes` | The canonical thing a metric is measured on — the display module, the battery cell — reconciled across documents. This is what the ontology frame calls a feature of interest. |
| **Canonical claim identity** | `kb.semantic_claim_identities` | A deterministic key over a claim's identity-bearing fields, deliberately excluding provenance, so two documents stating the same thing converge instead of duplicating. |

### 5.4 The record-born entities

| Entity | Recorded in | Its role for a metric |
|---|---|---|
| **Input record** | `kb.inputs` | The document as the system received it. |
| **Extracted metric** | `kb.metrics` | One metric as one document stated it: name, unit, value fields, condition, line spans, confidence, and the two governed identifiers described in §7 of the *Metric Keyword and Governed Term Resolution* manual. |
| **Object mention** | `kb.artifact_objects` | The subject as this document worded it, together with the outcome of reconciling it to an object node. |
| **Decision candidate** | `kb.semantic_decision_candidates` | A proposed assertion awaiting adjudication. Nothing reaches the assertion store without passing through here. |
| **Semantic assertion** | `kb.semantic_assertions` | The stored claim: subject, predicate, value, assertion kind, unit, quantity kind, class, and four independent state axes. |
| **Assertion evidence** | `kb.assertion_evidence` | The link back to the document, the quote, and the line spans that support the assertion. |
| **Processing outcome and finding** | `kb.semantic_processing_outcomes`, `kb.semantic_processing_findings` | What each stage managed to determine about this artifact — recorded for clean attempts too, so "not processed" is distinguishable from "processed cleanly". |
| **Class resolution decision** | `kb.ontology_class_resolution_decisions` | Which class was selected for this record's claim, and on what basis. |
| **Observed class profile** | `kb.ontology_observed_class_profiles` and its attribute tables | Evidence-only aggregation of what documents actually contain. It never grants contract authority. |
| **Projection** | `kb.search_artifacts_metric`, `kb.projection_state` | Derived, rebuildable views. Never a source of truth. |

### 5.5 How they connect

```text
document                        kb.inputs
   │  extraction
   ▼
metric row                      kb.metrics
   ├── metric_name ───────────► keyword concept          kb.keyword_concepts
   │                                  │ core:aligns_to_term
   │                                  ▼
   ├── metric_definition_term_id ──► metric_definition term      [ontology]
   ├── metric_unit ────────────────► unit + quantity kind        [ontology]
   ├── value_range_type ───────────► governed value mapping      [ontology]
   └── subject ──► object mention ──► object node          kb.object_nodes
                   kb.artifact_objects
   │  normalization
   ▼
decision candidate              kb.semantic_decision_candidates
   │  adjudication
   ▼
semantic assertion              kb.semantic_assertions
   ├── subject_object_id ─────────► object node
   ├── predicate_term_id ─────────► mea:measured_by              [ontology]
   ├── assertion_kind_term_id ────► mea:observed_value, …        [ontology]
   ├── unit_term_id, quantity_kind_term_id ─► unit, quantity kind [ontology]
   ├── instance_of_term_id ───────► metric class                 [ontology]
   ├── logical_identity_key ──────► canonical claim identity  kb.semantic_claim_identities
   └── evidence ──────────────────► kb.assertion_evidence ──► back to the document
```

Three of these joins carry most of the meaning.

**Name to concept to term.** A metric name does not point at a governed term directly. It points at a keyword concept, and the concept points at a governed `metric_definition` term through an accepted `core:aligns_to_term` assertion. These are two separate decisions on purpose — a lexical one and a governance one — and a name can complete the first without the second. The *Metric Keyword and Governed Term Resolution* manual covers this path in full.

**Claim to subject.** A stored metric claim is always *about* an object node, never about a bare string. That is why object reconciliation is a prerequisite rather than an enrichment: with no resolved object, there is no legal subject and the claim is held back (§9.5).

**Claim to class.** The assertion's `instance_of_term_id` is what makes it an instance of an ontology class rather than a free-floating row. It points at a metric class term in the `measurement` module, and the assertion additionally records *how* that class was arrived at — an existing class matched, or a provisional one created.

One nuance is worth knowing before reading these identifiers. Governed terms are counted in `kb.ontology_terms` (the catalog §3.3 measures), while class identity is anchored in `kb.ontology_term_headers`. When a metric already carries a `metric_definition_term_id`, that same identifier is reused as its class identifier, so one string can appear as a `metric_definition` in the catalog and as a `class` in the identity registry. Treat the two registries as answering different questions, and confirm with the owning team before relying on either count as the total.

## 6. A worked example

Take a product specification containing:

> **Display luminance (typical): 500 cd/m², measured per IEC 62341-6-1 at 25 °C.**

The Metric Ontology contributes the reusable meanings:

| Role | Term |
|---|---|
| The metric | a `metric_definition` for display luminance |
| The measurable quality | `quantity:qk_Luminance` |
| The unit | `quantity:unit_CD-PER-M2` |
| The thing measured | an instance of `mea:feature_of_interest` — the display module |
| The measurement method | an instance of `mea:procedure` — IEC 62341-6-1 |
| The circumstances | an instance of `mea:condition` — 25 °C |
| The kind of claim | `mea:observed_value` |

What stays outside the ontology: the number `500`, the word "typical," the sentence itself, and its location in the document. Those live in the extracted metric record and its semantic assertion, with evidence linking back to the source.

The payoff is that a second document saying "亮度 ≥ 250 cd/m²" resolves to the same quantity kind and the same unit, while being correctly distinguished as a `mea:lower_bound_requirement` rather than an observed value. The two become comparable without either being rewritten, and without the system having to guess that the Chinese and English wording meant the same thing.

## 7. How new metric vocabulary enters

Documents constantly introduce metrics the ontology has not seen. Vocabulary therefore grows through a governed path rather than by silent invention.

### 7.1 Candidates

Proposed vocabulary is recorded as an **ontology candidate**, holding the proposal, its target module, where it came from, how it was discovered, a confidence score, and a fingerprint used to recognize duplicates. Candidates may be terms, labels, mappings, axioms, profiles, profile rules, or module changes.

A candidate moves through: `discovered` → `draft` → `in_review` → `approved` → `included_in_release`, or ends at `rejected`, `deferred`, or `superseded`.

Observed at 2026-08-20T16:37:47-05:00: 170 candidates in `miner`, all of kind `term` and all at status `discovered` — that is, harvested but not yet triaged. A backlog at `discovered` is normal for a system actively reading new documents; it becomes a curation concern when it stops moving.

### 7.2 Auto-promotion

Waiting for review would mean discarding information in the meantime, so the system can create a governed term immediately and mark it `auto-promoted`. These terms are usable at runtime right away, alongside released vocabulary, while their status preserves how they entered so they can be reviewed and included in a later release.

Auto-promoted metric definitions are recognizable by identifiers of the form `measurement:kwc_<hash>` — derived from a keyword concept rather than from curated wording. Of the 61 metric definitions observed, 60 were auto-promoted in this way and 1 was released.

Read that ratio carefully. It means the working metric vocabulary today is overwhelmingly machine-derived and has not been through curation. Auto-promoted terms are usable, but they are not evidence that a metric has been reviewed, named well, or distinguished correctly from a near neighbour.

### 7.3 Module releases

Approved vocabulary is published as a **module release**, and one release per module is active at a time. Activation and deactivation are both recorded, so it is always possible to establish which vocabulary was in force at a given moment — which is what makes a past interpretation reproducible.

## 8. Governance lifecycle

Every term carries one of seven statuses:

| Status | What to expect |
|---|---|
| `draft` | Being prepared; not approved. |
| `in_review` | Awaiting or undergoing review. |
| `approved` | Accepted as governed content; eligible for release. |
| `included_in_release` | Published in a module release. |
| `auto-promoted` | Created by the automatic path; usable now, provenance retained for later review. |
| `superseded` | Replaced by a later term; keep for history, do not present as current. |
| `rejected` | Not accepted for governed use. |

Two habits follow from this. First, a term's label is not proof of its suitability — check the identifier, kind, definition, scope, module, version, and status before relying on it, because similar names can carry different meanings. Second, when a meaning changes materially, approve a replacement rather than quietly redefining an established identifier. Past references must remain understandable, and comparisons made last quarter must still mean what they meant when they were made.

## 9. The metric lifecycle

Section 8 describes the lifecycle of a *governed term* — how vocabulary is drafted, approved, and released. This section describes a different one: the lifecycle of *one metric*, from a sentence in a document to a stored claim attached to a governed class and a reconciled object. The two lifecycles run on separate clocks, and neither waits for the other.

The stages are document processors. The pipeline declares their order by dependency, so a later stage never runs on a record an earlier stage has not finished:

```text
extract_metrics ──► normalize_assertions ──► associate_semantics ──► project_semantics
```

### 9.1 Extraction

`extract_metrics` reads the document's chunks and writes one row per metric found: the name as worded, the unit, the value fields, the range type, any applicability condition, the threshold or target text, the source line spans, and a confidence. Nothing is governed at this point — every field is still the document's own wording.

The same stage also harvests proposed vocabulary into `kb.ontology_candidates`, which is where the `discovered` backlog described in §7.1 comes from.

### 9.2 Name resolution and auto-promotion

This is not a separate stage. It happens at the moment each metric row is persisted, so that every write path produces the same result. Each distinct metric name is resolved through the keyword resolver, and two identifiers are attached to the row:

- `keyword_concept_id`, from the lexical resolution. When the name has never been seen, a provisional concept is created for it — which is what happens on first encounter with almost every name.
- `metric_definition_term_id`, when a governed term is available. If the concept already has an accepted `core:aligns_to_term` alignment, that term is used. If it does not, one is created now: a `metric_definition` term is synthesized from the metric's own extracted fields — its definition text, value type, range type, and a unit term matched from its unit string — aligned to the concept, and marked `auto-promoted`.

This is the mechanism behind the ratio reported in §7.2. Its benefit is that a metric almost never waits for curation to acquire a governed identity. Its cost is that the working metric vocabulary is predominantly machine-made, and §7.2's warning applies in full: `auto-promoted` means usable, not reviewed.

### 9.3 Ontology object creation

Also within `extract_metrics`, the subject each metric is about becomes an object mention in `kb.artifact_objects`, and each mention is reconciled against the existing `kb.object_nodes`:

| Reconciliation outcome | What happens |
|---|---|
| A single exact candidate, or a best candidate above the confidence bar | Matched to the existing object node; the mention adopts its `object_id`. |
| Two candidates tied on score | Recorded as `ambiguous` rather than guessed. It can be resolved later, optionally with model assistance, and the competing candidates are preserved meanwhile. |
| Nothing close enough | A new object node is created, and the mention becomes its first occurrence. |

The object node produced here is the ontology object the later claim will be about. It is also the reason a metric can stall: an unresolved subject is one of only two conditions that still hold a metric back at adjudication.

### 9.4 Normalization

`normalize_assertions` reads the metric rows and proposes exactly one decision candidate per metric. It performs the text-to-structure work extraction deliberately left alone: parsing the threshold or target text into a value form, comparator, and numeric endpoints; choosing an assertion kind; and looking the document's `value_range_type` wording up in the governed mapping table.

A value it cannot parse still produces a candidate — carrying value form `unparsed` and the untouched raw text. Nothing is dropped for being hard to parse, and no value is invented to fill a gap. This stage writes no assertions; it only proposes.

### 9.5 Adjudication, ontology instance creation, and the stored claim

`associate_semantics` turns candidates into assertions. For a metric this is a single database transaction that does five things:

1. **Class resolution — the ontology instance step.** A class identifier is derived deterministically: the metric's own `metric_definition_term_id` when it has one, otherwise a stable hash of its normalized name. If a class with that identifier already exists it is reused, and the identity state is recorded as *resolved existing*. If it does not, an identity-only class is created in the `measurement` module with a class contract revision, and the state is recorded as *provisional new*. Either way a class resolution decision row records what happened and why.
2. **Claim identity.** A canonical key is computed over the claim's identity-bearing fields — assertion kind, quantity kind, unit, comparator, value — deliberately excluding the document, the model, the prompt, and any wording that does not identify the value. Semantically equal occurrences in different documents converge on one claim rather than accumulating duplicates.
3. **The assertion.** The claim is persisted with its subject object, the predicate `mea:measured_by`, the value as a typed literal, its assertion kind, its unit and quantity-kind terms, and `instance_of` pointing at the class from step 1 — this is what makes the row an instance of an ontology class rather than an unattached record. Under the current default it is stored with status `represented`: admitted and readable, carrying no endorsement.
4. **Evidence.** The supporting quote, line spans, extraction run, model, and prompt version are attached, and any superseded prior evidence for the same metric is closed out rather than deleted.
5. **Outcomes.** One outcome envelope per stage attempt records the disposition — *normalized* when both the value parsed and the mapping resolved, *raw preserved* otherwise — along with any findings, on the successful attempts as well as the problematic ones.

Only two conditions still stop a metric here: an unresolved subject object from §9.3, and a `mea:measured_by` predicate that is not released. Neither an unparsable value nor an ungoverned assertion kind defers a metric any more; both become recorded states on the assertion instead of silence.

Two observations in §10 follow directly from this stage. The identity-only class contract revisions §10.1 reports as absent are precisely what step 1 creates — they are absent in that database because no metrics have been processed there (§10.3), not because the path is missing. And the classes step 1 creates are `class` terms in the identity registry, which is the registry nuance noted at the end of §5.5.

### 9.6 Projection

`project_semantics` rebuilds derived views from accepted assertions. Projections are always rebuildable and never authoritative; when a build fails, the target is marked stale rather than left looking current with no record that a rebuild is owed.

### 9.7 When something is missing

A metric that stalls is not abandoned. Deferred candidates are retried by a backlog drain that re-normalizes the affected records rather than flipping statuses directly, so a candidate is reconsidered only when the thing it was waiting on actually changed — a subject that became resolvable, or a term that became released.

The corollary matters operationally: a drain pass cannot fix a condition that does not depend on a changing dependency. A metric held back by wording no one has triaged waits for a curation decision, not for another pass, and repeated draining will report no progress. That is the system working as designed, not a stuck queue.

### 9.8 The lifecycle end to end

Taking the §6 example — *Display luminance (typical): 500 cd/m², measured per IEC 62341-6-1 at 25 °C* — through every stage:

| Stage | What it produces for this metric |
|---|---|
| Extraction | A metric row: name `Display luminance`, unit `cd/m²`, the typical-value wording, the condition `25 °C`, and its line spans. |
| Name resolution | A keyword concept for the name, and a `metric_definition` term — matched if the concept was already aligned, auto-promoted from this row's own fields if not. |
| Object creation | An object mention for the display module, matched to an existing object node or creating a new one. |
| Normalization | One decision candidate: value form and numeric value `500`, assertion kind *observed value*, unit `cd/m²`, raw text retained. |
| Adjudication | A metric class resolved or created, a canonical claim identity, and a `represented` assertion linking the object node, `mea:measured_by`, `mea:observed_value`, the unit and quantity-kind terms, and the class. |
| Evidence | The sentence, its line spans, and the extraction run that produced it, attached to the assertion. |
| Projection | Rebuildable derived views over the accepted result. |

What the ontology contributed is the reusable half of that table; what the document contributed is the other half; and the evidence row is what keeps the two attributable to each other.

## 10. What to expect today

The Metric Ontology is being introduced in phases, and the vocabulary layer is considerably further along than the definition layer. The following were observed in `miner` at 2026-08-20T16:37:47-05:00 and should be confirmed against your deployment before relying on them.

### 10.1 Class contracts are not yet populated

A **class contract** is the fuller definition of a metric class: its expected value type, permitted units, constraints, normalization rules, and which capabilities — such as validation or comparison — it can support. The supporting tables are deployed, including a `definition_state` of `identity_only`, `partially_defined`, or `validated`, and per-capability results of `enabled`, `disabled`, or `indeterminate`.

**No class contract revisions existed at the time of observation.** Every metric class is therefore identity-only in practice.

The consequence is specific and important: a term establishes *what a metric is called and what it refers to*, not *how its values may be validated or compared*. Do not assume that because two claims resolve to the same metric definition, the system can safely compare them. Until a contract declares a comparison capability, that judgment remains a human one.

### 10.2 Metric-level fields on terms are uncontrolled

Terms carry `value_type`, `range_type`, and `permitted_unit_term_ids` fields. The first two have **no database constraint restricting their values**, and the observed data shows the drift that follows from that:

**`value_type` values observed**

| Value | Count |
|---|---|
| `text` | 11 |
| `number` | 10 |
| `numeric` | 10 |
| `integer` | 10 |
| `qualitative` | 7 |
| `string` | 2 |
| `percentage` | 1 |

**`range_type` values observed**

| Value | Count |
|---|---|
| `qualitative` | 18 |
| `exact` | 14 |
| `limit_absent` | 10 |
| `lower_bound` | 8 |
| `upper_bound` | 8 |
| `range` | 2 |

`number`, `numeric`, and `integer` appear as three separate values, as do `text` and `string`. Treat these fields as descriptive hints, not as a reliable basis for filtering or grouping, and expect equivalent values to be spelled differently. Whether these variants are intended to be distinct requires confirmation from the owning team.

### 10.3 The vocabulary is loaded; the metric data is not

At the time of observation, `kb.metrics` and `kb.semantic_assertions` were both empty in `miner`. The ontology was fully seeded, but no extracted metrics or assertions were present. This reflects the current state of that database rather than a property of the system, and it will not be true of a database that has processed documents. Verify against your own environment.

## 11. Common pitfalls

- **Do not put a value in the ontology.** `250 cd/m²` is evidence in an assertion record; only the metric, quantity kind, and unit are ontology terms.
- **Do not treat matching labels as matching meanings.** Two terms named "brightness" may be genuinely different metrics. Read definition, scope, and module.
- **Do not ignore the assertion kind.** A target, a requirement, and an observation are different claims even when their numbers are identical.
- **Do not assume comparability from a shared metric definition.** With no class contract, comparison capability is undeclared.
- **Do not read `auto-promoted` as reviewed.** It means usable now, with provenance kept for review later.
- **Do not use `quality_kind`.** The deployed constraint accepts `quantity_kind`.
- **Do not filter on `value_type` or `range_type` expecting a controlled vocabulary.** Neither is constrained.
- **Do not silently redefine an established term.** Supersede it and approve a replacement.
- **Do not read `represented` as endorsed.** It means the claim was admitted losslessly, not that anyone accepted it.
- **Do not treat a keyword concept as an ontology entity.** It is a lexical identity with no governance status; only its `aligns_to_term` alignment reaches the ontology.
- **Do not expect a backlog drain to clear a curation-blocked metric.** Drains retry dependencies that changed; wording nobody has triaged is not one of them.

## 12. Glossary

| Term | Meaning |
|---|---|
| Metric Ontology | The governed vocabulary describing measurement, chiefly the `measurement` and `quantity` modules. |
| Module | A governed area of vocabulary that declares its dependencies. |
| Governed term | A stable, versioned identity for a meaning, with a kind, module, and lifecycle status. |
| Metric definition | The governed identity of a metric, distinct from any observed measurement. |
| Quantity kind | The measurable quality itself, independent of unit or value. |
| Dimension | The dimensional structure that determines which units are compatible. |
| Unit | A standardized way of expressing a value. |
| Assertion kind | The nature of a claim: observation, requirement, target, reference, or capability. |
| Feature of interest | The entity a metric is asserted about. |
| Procedure | The test method that produces a value. |
| Class contract | The fuller versioned definition of a class, including value type, permitted units, and capabilities. |
| Ontology candidate | Proposed vocabulary awaiting triage, review, or rejection. |
| Auto-promotion | Immediate creation of a usable governed term, with provenance kept for later review. |
| Module release | A published set of approved vocabulary; one is active per module at a time. |
| Keyword concept | A corpus-level lexical identity grouping the different names used for one thing; not governed vocabulary. |
| Object node | The reconciled, cross-document identity of the thing a metric is measured on — the ontology's feature of interest in practice. |
| Decision candidate | A proposed assertion awaiting adjudication; nothing becomes an assertion without passing through this state. |
| Semantic assertion | One stored claim: subject, predicate, value, assertion kind, class, and its independent state axes. |
| Ontology instance | A record that declares itself an instance of a governed class, through the assertion's `instance_of` reference. |
| Canonical claim identity | A deterministic key over a claim's identity-bearing fields, excluding provenance, so equal claims converge. |
| Represented | A lifecycle status meaning the claim was admitted and is readable, carrying no endorsement. |

## 13. Related manuals

- *Governed Ontology Terms Guide* — the term registry. See the correction in §3.2.
- *Ontology Labels Guide* — readable names for terms.
- *SemOS Semantic Layer User Manual* — assertions, evidence, and lossless processing.
- *Metric Keyword and Governed Term Resolution* — how document wording resolves to governed terms.
- *Metric and Assertion Semantic Processing* — the processing pipeline in detail.

## Change Log

### 1.1 — 2026-08-20T19:20:00-05:00

Author: Claude

Reason: Reader request — the manual described the vocabulary but not the entity model around a metric, nor how a metric travels from a document to a stored, class-attached claim.

Summary: Added §5 *The Metric Ontology model*, classifying every entity a metric touches as ontology-born, corpus-level, or record-born, listing where each is recorded, and mapping the joins between them; added §9 *The metric lifecycle*, tracing one metric through extraction, name resolution and auto-promotion, ontology object creation, normalization, adjudication with ontology instance creation, projection, and retry, with an end-to-end trace of the §6 example; renumbered the sections that followed; added keyword concept, object node, decision candidate, semantic assertion, ontology instance, canonical claim identity, and `represented` to the glossary, and three pitfalls covering `represented`, keyword concepts, and backlog drains.

### 1.0 — 2026-08-20T16:37:47-05:00

Author: Not specified

Reason: Initial manual explaining the Metric Ontology for users who work with measurement information.

Summary: Defined the Metric Ontology and its boundary against values and evidence; documented the six active modules, the eight permitted term kinds, the measurement frame of six classes, the quantity chain, and the eight assertion kinds; explained candidates, auto-promotion, module releases, and the governance lifecycle; recorded observed vocabulary counts and the current limitations regarding unpopulated class contracts and unconstrained `value_type` and `range_type`; and corrected the `quality_kind` and seven-kind statements in the *Governed Ontology Terms Guide*.
