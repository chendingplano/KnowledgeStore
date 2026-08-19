---
title: Ontology Labels Guide
language: en
format: markdown
version: 1.0
status: current
author: Not specified
owner: Not specified
audience: ChenWeb users, ontology curators, reviewers, and system operators
create-time: 2026-08-19T08:54:59-05:00
last-modify-time: 2026-08-19T10:18:20-05:00
keywords: ontology labels, ontology_labels, ontology_term_labels, governed vocabulary, preferred label, alternate label, hidden label, language tag, undetermined language, Chinese labels, SKOS
---

# Ontology Labels Guide

## 1. Purpose

This guide explains the labels attached to governed ontology terms in ChenWeb. These labels give people readable names for a term without changing the term's stable identity or meaning.

The database table is named `kb.ontology_term_labels`. `kb.ontology_labels` is a convenient shorthand, but it is **not** the deployed table name.

Use labels when a governed term needs a name in one or more languages, a recognized alternative name, or a name that should remain searchable without normally being shown. For example, the term identifier `quantity:luminance` might have the English preferred label “Luminance” and a symbol such as “Lv” as an alternate label.

## 2. What a label is—and is not

An ontology term has a stable `term_id` that systems use as its identity. A label is the human-readable wording associated with that identity.

| This is a label | This is not a label |
|---|---|
| “Display luminance” as the name shown to readers | A new ontology term or a replacement for the term identifier |
| “Luminance” as an alternate accepted name | A measured value such as `250 cd/m²` |
| “旧称” as a historical search name | Proof that two similarly named terms mean the same thing |

Read the related term’s definition, scope, kind, and status before deciding that a label is appropriate. Similar wording can refer to different concepts.

## 3. The three label roles

Each label has one `label_role`. The system supports exactly these roles.

| Role | Meaning | Typical use |
|---|---|---|
| `prefLabel` | The preferred display name for the term in a language. | Show “Luminance” to English-language readers. |
| `altLabel` | An accepted alternative name, spelling, abbreviation, or symbol. | Support “Lv” or “display brightness” where those are appropriate alternatives. |
| `hiddenLabel` | A search or legacy name that is retained for discovery but should not normally be displayed. | Preserve an obsolete name so older material can still be found. |

Use `prefLabel` for the clearest current name. Use `altLabel` only when it genuinely refers to the same governed meaning. Use `hiddenLabel` for search support or historical wording, not as a second public title.

### Preferred-label rule

For a term and language, there can be only one current preferred label. Before replacing it, the existing current `prefLabel` must be superseded; then the replacement can be created. This prevents two competing names from being presented as equally preferred.

The rule is language-specific. A term may have one preferred English label and one preferred Chinese label, for example.

## 4. Reading a label record

| Field | What it tells you |
|---|---|
| `term_id` | The governed term to which the label belongs. This is the stable identity; it is not the label text. |
| `version` | The revision number for the label record. Label history is kept rather than silently overwritten. |
| `label` | The human-readable text. It cannot be empty. |
| `lang` | The language tag for the label. When creating through the supported API, an omitted language defaults to `en`. For auto-promoted metric terms, see the important `und` limitation below. |
| `label_role` | Whether the label is preferred, alternate, or hidden. |
| `status` | The label’s governance lifecycle state. |
| `source_candidate_id` | When present, identifies the ontology candidate from which the label was materialized. |
| `released_in_release_id` | When present in the database, identifies the ontology module release that included the label. |
| `create_time`, `create_by`, `modify_time`, `modify_by` | The recorded creation and most recent modification details. |

## 5. Governance status

Labels use the governed-content lifecycle below. A label’s status is separate from its text and role: the same wording is not automatically ready for use merely because it exists.

| Status | What to expect |
|---|---|
| `draft` | Being prepared; not yet approved. |
| `in_review` | Awaiting or undergoing review. |
| `approved` | Accepted as governed content and eligible for the module-release process. |
| `included_in_release` | Included in a module release. |
| `auto-promoted` | Created through the system’s auto-promotion path; review and release requirements still depend on the applicable workflow. |
| `superseded` | Replaced by a later label; retain it for history rather than presenting it as current. |
| `rejected` | Not accepted for governed use. |

When a module release includes a label, the release linkage preserves which release carried it. Do not treat a `draft`, `in_review`, `rejected`, or `superseded` label as the normal public name for a term.

## 6. Important current findings

### `und` does not mean Chinese

`und` means **undetermined language**. It does not mean Chinese, English, or a multilingual label.

The auto-promotion path currently writes `lang = 'und'` for every preferred and alternate label it creates. It does this as a fixed implementation value and does not inspect the label text or carry a detected language into the label record. Therefore, a Chinese label such as `每户配备分类垃圾容器的数量` can currently be stored with `lang = 'und'`.

This is a known metadata limitation. The label text remains Chinese, but its stored language is unknown. Do not use `und` as evidence that the label is not Chinese; use the text and source material for that assessment. A future correction should preserve the actual language, for example a Chinese language tag, when the source provides it or a reviewed language determination is available.

### Orphaned auto-promoted labels

An observed data-integrity issue can block metric processing. At 2026-08-19T10:18:20-05:00, the live `miner` database contained 183 `auto-promoted` label rows without a matching `kb.ontology_terms` row.

One observed example is the preferred label `每户配备分类垃圾容器的数量`, stored for `measurement:kwc_b5f5355d2860` with `lang = 'und'`. Its matching term and accepted term-alignment record were absent.

When the processor encounters such a concept, it correctly sees that no accepted alignment exists and attempts to create the term and its preferred label. The pre-existing orphaned preferred label then blocks that creation. The attempt is rolled back, so retrying the same batch does not resolve the issue.

Before retrying affected batches, an operator must repair the affected governed records: either remove the orphaned labels so the system can recreate the term, label, and alignment together, or backfill the missing term and accepted alignment using reviewed source information. This repair changes production data and must follow the applicable operational approval process.

## 7. Creating and viewing labels

The supported service endpoints are attached to a specific term:

| Task | Endpoint |
|---|---|
| Create a label | `POST /api/v1/kb/ontology/terms/:term_id/labels` |
| List a term’s label versions | `GET /api/v1/kb/ontology/terms/:term_id/labels` |

To create a label, provide the label text and, as appropriate, its language, role, status, and creator. The creation request accepts these fields:

```text
label
lang
label_role
status
create_by
```

The listing returns all stored label versions for the requested term, newest version first. The current endpoints create and list labels; they do not provide a separate label-edit endpoint. Follow the governed workflow for a revision or replacement rather than assuming that displayed text can be changed in place.

## 8. Worked example

Suppose the stable term is `quantity:luminance`.

| Language | Role | Label | Why |
|---|---|---|---|
| `en` | `prefLabel` | Luminance | The normal English display name. |
| `en` | `altLabel` | Lv | A recognized abbreviation or symbol, if approved for this vocabulary. |
| `fr` | `prefLabel` | Luminance | The normal French display name for the same term. |
| `en` | `hiddenLabel` | Brightness (legacy usage) | Helps find older material without making the older wording the public name. |

All four rows refer to the same `term_id`; they do not create four distinct ontology concepts. If “brightness” has a different intended meaning in a given context, it needs its own governed term or an explicit mapping instead of an alternate label.

## 9. Before you add or replace a label

1. Confirm the target `term_id` and read its definition and scope.
2. Choose the language and the role that best describes the wording.
3. Check existing labels for that term and language, especially the current `prefLabel`.
4. Confirm the wording is an equivalent name, not a related but different concept.
5. Use the appropriate governance status and release workflow.
6. When replacing a preferred name, supersede the old current preferred label first and retain it as history when appropriate.

## 10. Common pitfalls

- Do not use `kb.ontology_labels` in database queries; use `kb.ontology_term_labels`.
- Do not put an observed value, threshold, or source quotation in a label simply because it contains a familiar term.
- Do not create two current `prefLabel` values for the same term and language.
- Do not use an `altLabel` to conceal a disagreement about meaning. Create, map, or review the appropriate term instead.
- Do not assume a label’s language determines the language of the underlying term. The `term_id` remains the same governed identity across languages.
- Do not interpret `und` as Chinese. It means that the auto-promotion path did not determine the language.
- Do not retry an affected auto-promotion batch indefinitely when its preferred label has no matching term. Repair the orphaned governed records first.

## Change Log

### 1.0 — 2026-08-19T10:18:20-05:00

Author: Not specified

Reason: Document verified auto-promotion data-integrity findings and clarify the meaning of `und`.

Summary: Explained that auto-promotion currently assigns `und` without detecting language, documented the observed orphaned-label condition and batch failure mode, and provided approved-repair guidance.

### 1.0 — 2026-08-19T08:54:59-05:00

Author: Not specified

Reason: Initial manual for ontology term labels, requested as `kb.ontology_labels`.

Summary: Clarified the deployed table name, label roles, language-specific preferred-label rule, lifecycle statuses, supported endpoints, and safe label-selection guidance.
