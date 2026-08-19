---
title: Governed Ontology Terms Guide
language: en
format: markdown
version: 1.0
status: current
author: Not specified
owner: Not specified
audience: ChenWeb users, ontology curators, reviewers, and system operators
create-time: 2026-08-19T08:26:08-05:00
last-modify-time: 2026-08-19T08:26:08-05:00
keywords: ontology terms, governed vocabulary, ontology_terms, term_kind, class, concept, dimension, metric definition, property, quality kind, unit
---

# Governed Ontology Terms Guide

## 1. Purpose

`kb.ontology_terms` is the system’s registry of **governed ontology terms**: approved, reusable identities for the concepts and relationships that the semantic layer needs to describe.

Use it when different documents, processors, or reviewers need to refer to the same meaning consistently. For example, a term can identify the property “has unit,” the metric definition “display luminance,” or the unit “degree Celsius.” It is not a store of document occurrences or measured values; those belong in the records that preserve the source material and assertions.

Each term has a stable `term_id`, a `term_kind`, a module, lifecycle status, and supporting descriptive content such as a definition and scope. Terms are versioned so that an established identity can be maintained and governed over time.

## 2. Why the table matters

Without a governed term registry, the same idea may be represented with inconsistent names, spelling variants, or incompatible meanings. `kb.ontology_terms` provides an authoritative identity that other parts of the system can reference.

This helps the system:

- use one agreed meaning across documents and workflows;
- distinguish a relationship from a category, a measurement definition, or a unit;
- make terms reviewable and releaseable instead of silently inventing vocabulary; and
- preserve a stable reference even when a term’s descriptive content is revised.

Labels, mappings, and logical statements about a term may be stored in related ontology tables. The `kb.ontology_terms` row is the core identity and governance record.

## 3. Reading a term record

The most important fields are:

| Field | What it tells you |
|---|---|
| `term_id` | The stable, namespaced identifier for the term, such as `measurement:display_luminance`. Use this identifier when a system record needs to refer to the term. |
| `version` | Which revision of that governed term record is being viewed. |
| `term_kind` | What sort of ontology term the record represents. See the next section. |
| `module_id` | The vocabulary module responsible for the term. |
| `status` | Where the term is in its governance lifecycle. A term should only be used where the relevant workflow permits its status. |
| `definition` and `scope` | The intended meaning and boundaries of use. Read these before deciding that two similarly named terms are the same. |

## 4. Allowed term kinds

`term_kind` must be one of the following seven values.

| Value | Meaning | Example | Use it when |
|---|---|---|---|
| `class` | A category whose members share a defined type or role. | `measurement:measurement_device` | You need a reusable category for classification. |
| `concept` | A controlled idea used for organizing, labeling, or navigating knowledge. A concept does not by itself state that something is a class or a real-world object. | `document-authority:normative` | You need a curated idea or subject for classification, hierarchy, or mapping. |
| `dimension` | The physical dimension or dimensional structure of a quantity. | `quantity:length` | You need to express dimensional compatibility, such as length rather than time. |
| `metric_definition` | The governed identity of a metric being measured, assessed, or compared. It is not one observed measurement value. | `measurement:display_luminance` | You need to identify what a metric means across many observations. |
| `property` | A named relationship or attribute that can connect or describe things. | `core:has_unit` | You need to express a predicate such as “has unit,” “measured by,” or “is part of.” |
| `quality_kind` | The kind of measurable quality or quantity being discussed, independent of a specific unit or observed value. | `quantity:luminance` | You need to say what is measured—such as luminance, mass, or temperature. |
| `unit` | A standardized unit used to express a measured value. | `unit:candela-per-square-metre` | You need to state how a value is expressed or converted. |

## 5. Choosing the right kind

Start with the question the term answers:

| If the term answers… | Choose… |
|---|---|
| “What category does this belong to?” | `class` |
| “What controlled idea or subject is this?” | `concept` |
| “What relationship or attribute links these?” | `property` |
| “What metric are we talking about?” | `metric_definition` |
| “What measurable quality is involved?” | `quality_kind` |
| “What physical dimension applies?” | `dimension` |
| “What unit expresses the value?” | `unit` |

### Example: display luminance

The phrase “display luminance is at least 250 cd/m²” contains several distinct meanings. They should not all become one term:

| Meaning | Suitable term kind | Example term |
|---|---|---|
| The metric being evaluated | `metric_definition` | Display luminance |
| The measurable quality | `quality_kind` | Luminance |
| The unit on the observed value | `unit` | Candela per square metre |
| The dimensional basis for compatible units | `dimension` | Luminous intensity per area |
| A relationship connecting the metric to its unit | `property` | Has unit |

The observed threshold, `250 cd/m²`, is evidence or a value in a measurement/assertion record. It is not itself a `kb.ontology_terms` entry.

## 6. Important distinctions

### Metric definition vs. quality kind

A `metric_definition` identifies a particular metric that can be found in many sources. A `quality_kind` identifies the general measurable quality. “Display luminance” can be a metric definition; “luminance” is the quality kind it concerns.

### Quality kind vs. unit vs. dimension

These form a useful measurement chain:

```text
quality_kind: what is measured
        ↓
dimension: physical compatibility of the measurement
        ↓
unit: how a particular value is written or converted
```

For example, temperature is a quality kind; thermodynamic temperature is its dimension; degrees Celsius and kelvins are units.

### Class vs. concept

Use a `class` when membership in a category has semantic significance. Use a `concept` when you need a governed idea for organization, classification, or mapping without asserting that it is a class of real-world things.

## 7. What to expect in governance

Do not treat a term label alone as proof that a term is suitable. Before using or creating a term, check its identifier, kind, definition, scope, module, version, and lifecycle status. Similar labels can have different meanings, and a term may be unavailable to a workflow until it has reached the required status.

When a meaning changes materially, create or approve an appropriate replacement rather than silently changing what an established identifier means. This keeps past references understandable and supports reliable comparison over time.

## 8. Current value set

The allowed `term_kind` values are exactly:

```text
class
concept
dimension
metric_definition
property
quality_kind
unit
```

Values not in this list are not valid for `kb.ontology_terms.term_kind`. In particular, use `quality_kind` for a measurable quality; do not use the older name `quantity_kind`.

## Change Log

### 1.0 — 2026-08-19T08:26:08-05:00

Author: Not specified  
Reason: Initial manual for the `kb.ontology_terms` table and its current `term_kind` values.  
Summary: Defined the table’s purpose, explained its key fields, and documented all seven allowed term kinds with examples and selection guidance.
