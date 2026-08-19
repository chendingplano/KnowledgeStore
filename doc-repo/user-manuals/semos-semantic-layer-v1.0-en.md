---
title: Semos Semantic Layer User Manual
language: en
format: markdown
version: 1.0
status: Draft — describes the intended semantic-layer model; several referenced ADRs are proposed
author: Not specified
owner: Not specified
audience: Semos users, reviewers, ontology curators, and operators
create-time: 2026-08-19T00:00:00-05:00
last-modify-time: 2026-08-19T00:00:00-05:00
keywords:
  supplied: Semos Semantic Layer, kb.ontology_terms, kb.semantic_assertions, kb.assertion_evidence
  generated: ontology, ontology object class, ontology object instance, metric, provenance, semantic assertion, evidence, represented status
---

# Semos Semantic Layer

## What this is for

The Semos Semantic Layer helps people find, interpret, review, and compare information extracted from documents without losing the connection to what the source actually said. It organizes information into three connected layers:

1. **Classes** — the kinds of things Semos can describe, such as *Display Luminance*.
2. **Assertions** — specific source-backed claims about those things, such as a stated luminance value.
3. **Evidence** — the document material that supports, qualifies, or contradicts a claim.

This model is useful when a document contains valuable information that may be incomplete, ambiguous, malformed, or not yet aligned to a governed vocabulary. Semos keeps that information visible instead of silently discarding it.

## The semantic-layer model

```text
Ontology class                  Assertion / instance                 Evidence
kb.ontology_terms       <-     kb.semantic_assertions        <-     kb.assertion_evidence
“Display Luminance”            “This display is 500 cd/m²”          Source excerpt and location
```

An assertion is associated with a class. Evidence connects the assertion back to one or more source occurrences. One class can have many assertions, and an assertion can have one or more evidence records.

## Key concepts

### Ontology terms: `kb.ontology_terms`

`kb.ontology_terms` is Semos’s ontology vocabulary and identity registry. Each entry identifies a term and its kind. Term kinds include classes, properties, individuals, concepts, metric definitions, quantity kinds, units, and dimensions.

In the semantic-layer model, a term can identify an ontology object class: a reusable category that tells users what sort of object an assertion concerns. For example, **Display Luminance** is a class; individual statements of a display’s luminance are instances of that class.

### Important current limitation

The current term table alone is intentionally treated as too simple to be a complete class definition. A label-only term does not yet specify all of the meaning needed to validate or compare instances—for example, its expected value type, permitted units, range, or applicable rules.

Semos is evolving toward richer, versioned class contracts alongside stable term identities. Until that work is complete, users should treat a term as the authoritative identity and vocabulary anchor, not assume that every term already carries a complete definition or validation contract.

### Semantic assertions: `kb.semantic_assertions`

`kb.semantic_assertions` stores ontology object instances: source-backed claims represented in a form that semantic tools can use. An assertion can contain a normalized value when Semos can interpret the source reliably, or a raw-preserved representation when it cannot.

For a metric class, the distinction looks like this:

| Layer | Example |
|---|---|
| Class | Display Luminance |
| Assertion | A particular product document states 500 cd/m² |
| Evidence | The quoted text and location in that product document |

Creating an assertion means only that Semos has preserved a source-backed claim. It does **not** mean the claim is true, accepted, compliant, or suitable for every comparison.

### Assertion evidence: `kb.assertion_evidence`

`kb.assertion_evidence` provides provenance. It records which source artifacts support, qualify, or contradict an assertion, and lets a reviewer trace a semantic result back to the document context.

Evidence is not a replacement copy of normalized data. The raw artifact remains the primary record of what was extracted; the evidence record explains the assertion’s relationship to that source.

## What happens when Semos cannot fully interpret a claim

Semos separates a processing problem from a problem in the source content.

- A **system failure** prevents safe processing or storage, such as an unavailable database or unreadable required input.
- A **semantic finding** means Semos preserved the claim but found an issue, such as an unknown unit mapping, an unparsed value, an ambiguous class, missing data, or a conflict with another source.

The intended lossless behavior is to retain the raw source occurrence, create a usable semantic representation where the artifact family supports one, attach evidence, record the findings, and continue with capabilities that remain possible.

### The `represented` status

Losslessly ingested assertions begin with lifecycle status `represented`. This means:

> The source expressed this claim, and Semos preserved it.

It does not mean that Semos has accepted the claim as correct. A represented assertion may later become a candidate, enter review, be accepted, be deferred, or be rejected according to governance rules. Interfaces that show represented assertions should also show their warnings or findings; they must not silently treat them as accepted facts or hide them.

## How to read a semantic result

When viewing an assertion, use this sequence:

1. Identify the **class** to understand what kind of thing is being described.
2. Read the **assertion** as the source-backed claim, including whether its value was normalized or raw-preserved.
3. Check its **lifecycle and findings** before relying on it for a decision or comparison.
4. Open the **evidence** to see the source wording and location.
5. Use accepted, appropriately validated claims where an application requires authoritative comparison; use represented claims for discovery, diagnostics, and review with their warnings in view.

## What to expect today

The semantic layer is being introduced in phases. The referenced architecture decisions describe the intended data model and rollout safeguards, but they are marked proposed. Availability of particular class contracts, lossless assertion writing, lifecycle states, and consumer behavior depends on the deployed Semos version and the enabled module.

In particular, do not assume that every existing `kb.ontology_terms` entry has a complete class contract, or that every document artifact has already been migrated to lossless semantic processing. If a result affects an operational or compliance decision, confirm the assertion’s status, findings, evidence, and the capabilities of the deployed consumer.

## Glossary

| Term | Meaning |
|---|---|
| Ontology object class | A reusable category of objects, such as Display Luminance. |
| Ontology object instance | A specific occurrence of a class, represented as a semantic assertion. |
| Semantic assertion | A source-backed claim that Semos has preserved in its semantic layer. |
| Evidence | Provenance that connects an assertion to supporting, qualifying, or contradicting source material. |
| Normalized | Interpreted into a canonical semantic form suitable for supported uses. |
| Raw-preserved | Kept with its original source representation because full interpretation was not available. |
| Finding | A recorded semantic issue; it is distinct from a system execution failure. |
| Represented | An assertion lifecycle state showing that a source claim is stored, without asserting it is accepted or true. |

## Related architecture decisions

- `2026081801-adr` — Lossless Semantic Processing and Knowledge Preservation
- `2026081701-adr` — Ontology Object Classes, Normalized Metric Instances, and Semantic Relations
- `2026072901-adr` — Ontology Platform and Adaptive Pipeline

## Change Log

- **1.0 — 2026-08-19T00:00:00-05:00 — Not specified.** Created an English Markdown user manual for the Semos Semantic Layer, covering ontology terms, semantic assertions, evidence, lossless processing, status interpretation, current limitations, and related ADRs.
