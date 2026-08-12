---
title: Metric Name Resolution: Keyword Concepts and Governed Ontology Terms
language: en
format: markdown
version: 1.0
status: current
author: Not specified
owner: Not specified
audience: ChenWeb users, metric reviewers, and system operators
create-time: 2026-08-12T14:00:00-05:00
last-modify-time: 2026-08-12T14:00:00-05:00
keywords: metrics, metric names, keyword concepts, ontology terms, metric_definition, aligns_to_term, canonicalization, reconciliation, multilingual metrics
---

# Metric Name Resolution: Keyword Concepts and Governed Ontology Terms

## 1. Purpose

This manual explains how a metric name found in a document is connected to:

- a **keyword concept** in `kb.keyword_concepts`, which groups the different names people use; and
- a governed **ontology term** in `kb.ontology_terms`, which gives the metric its authoritative identity.

This distinction matters when documents use names such as `Luminance`, `luminance`, `亮度`, or `显示亮度`. The names may look different, but they should contribute to one governed metric when the domain evidence says they mean the same thing.

The goal is not to replace the original wording. The original `metric_name` remains available as provenance. The goal is to make differently worded metrics resolve consistently and appear under one governed metric identity.

## 2. The two identities

### 2.1 Keyword concept: “which names belong together?”

`kb.keyword_concepts` stores an opaque, stable `concept_id`. A concept represents one name identity in the keyword lexicon.

The concept can have several **surfaces** in `kb.keyword_surfaces`, such as:

| Surface | Role | Meaning |
|---|---|---|
| `luminance` | preferred | The normal display label for the concept |
| `Luminance` | alternative | An observed capitalization |
| `亮度` | alternative | A language variant |
| `luminence` | hidden | A searchable misspelling that is not displayed |

The surface preserves the text that was observed. Normalization creates lookup keys for spelling, case, spacing, and similar variations, but normalization does not decide that unrelated words or translations have the same meaning.

### 2.2 Ontology term: “which governed metric is this?”

`kb.ontology_terms` stores governed terms. For this workflow, the relevant term has:

- `term_kind = 'metric_definition'`; and
- `status = 'included_in_release'`.

The governed term is the authoritative identity used by downstream metric consumers. A keyword concept is not itself a governed metric definition. It becomes connected to one only through an accepted `aligns_to_term` assertion.

## 3. How a metric name is resolved

The resolution path is:

```text
document metric name
        ↓
keyword resolution
        ↓
keyword_concept_id
        ↓  accepted aligns_to_term assertion
released metric_definition term
        ↓
metric_definition_term_id on the metric row
```

The process has two related decisions:

1. **Lexical decision:** Which `kb.keyword_concepts` concept does this name belong to?
2. **Governance decision:** Which released `metric_definition` term, if any, does that concept represent?

These decisions are intentionally separate. A name can be recognized as belonging to a keyword concept even when no released governed term is available yet.

## 4. Online keyword resolution

When a targeted metric name is submitted, the resolver checks increasingly broad evidence and stops at the first tier that produces candidates:

1. Exact surface text.
2. The normalized key.
3. Alternate keys for spacing, token order, singular forms, or initials.
4. Enabled rewrite rules.
5. Fuzzy matching for carefully bounded misspellings.

The online path does not call an LLM. It records the method, score, normalizer version, and decision information so outcomes can be inspected and corrected.

Examples:

- `Luminance` and `luminance` can resolve to the same concept through stored surfaces and normalized lookup.
- `ML` can resolve to a concept whose preferred surface is `machine learning` through the initials bridge.
- `kubernets` may resolve to `Kubernetes` through guarded fuzzy matching.
- `亮度` and `luminance` are not made equivalent by normalization alone because they are different strings in different scripts.

### What the result means

| Result | What it means for the metric |
|---|---|
| Accepted | A concept was selected using the available evidence. |
| Ambiguous | Multiple concepts tied. The system records the tie and uses a top-1 result for the immediate occurrence while preserving the competing candidates for reconciliation. |
| Targeted miss or weak match | A provisional concept is created so the metric has an attributable identity immediately. |
| Collector miss | An untargeted vocabulary observation is recorded for later processing rather than creating a concept for every token. |

## 5. Reconciliation for different words and translations

Offline reconciliation handles cases that online normalization cannot solve, especially genuinely different words and cross-language names.

For example, `luminance` and `亮度` can be considered for unification only after stronger evidence is available. Reconciliation may use:

- a deterministic lexical recheck for close spellings;
- approved external identity evidence, such as an authoritative `exact_equivalent` claim; and
- multilingual embeddings to rank candidates.

Embeddings rank candidates but do not authorize a cross-language merge by themselves. An automatic tier-6 merge requires authoritative exact-identity evidence and no conflicting target. Weaker imported relationships such as `related`, `broad`, or `narrow` must not be silently promoted to an exact alias.

Reconciliation also revisits ambiguous online results. It can attach a previously ambiguous surface to one surviving concept when the evidence is strong enough, but it does not merge the tied concepts merely to remove the ambiguity.

## 6. Connecting a concept to a governed metric term

After keyword resolution, the concept is aligned to a released governed term with an accepted `aligns_to_term` assertion.

For example:

| Item | Example |
|---|---|
| Keyword concept | `concept-123` |
| Surfaces | `luminance`, `亮度`, `显示亮度` |
| Governed term | `metric_definition` term `term-456` |
| Assertion | `concept-123 aligns_to_term term-456` |

The catalog and the assignment have different review expectations:

- Creating or releasing a governed metric term is a small, reviewable catalog decision.
- Assigning millions of document observations to that catalog is the high-volume resolution task and is designed to run automatically when the evidence meets the policy.

The system must not infer that two similar-sounding quantities are identical. For example, whether `brightness` and `luminance` should be one metric or two is a domain-owner decision. A lexical or embedding similarity score is not sufficient on its own.

## 7. What is stored on a metric row

A resolved metric retains both its source wording and its two identities:

| Field | Purpose |
|---|---|
| `metric_name` | The exact name extracted from the document; retained as provenance. |
| `keyword_concept_id` | The keyword concept selected by lexical resolution. |
| `metric_definition_term_id` | The governed `metric_definition` term, populated when the concept has a resolved alignment. |

The displayed name is selected from the governed term's preferred name when available, then a localized concept label, and finally the original `metric_name`.

If no released `metric_definition` term or accepted alignment exists, `keyword_concept_id` may still be present while `metric_definition_term_id` remains empty. This is an unresolved governance link, not proof that the original metric name was lost.

## 8. Worked example

Suppose three documents contain these metric names:

```text
Document A: Luminance = 450 cd/m²
Document B: 亮度 = 450 cd/m²
Document C: 显示亮度 = 450 cd/m²
```

The intended result is:

1. Each observed name is preserved as a surface and as the document's original `metric_name`.
2. The three surfaces resolve to one `keyword_concept_id` when curation or reconciliation establishes that they are the same concept.
3. That concept has one accepted `aligns_to_term` assertion to a released `metric_definition` term.
4. Each metric row receives the same `metric_definition_term_id`.
5. A comparison view can use that governed term id as the metric row identity, so the three documents contribute to one metric rather than three name-based rows.

If the evidence is not sufficient, the system keeps the uncertainty visible: it may preserve separate provisional concepts, record an ambiguity, or leave the governed term id empty until a released catalog term and valid alignment are available.

## 9. Important limits and operator expectations

- Normalization handles forms of a string; it does not establish semantic equivalence between different words.
- A keyword concept is not automatically a governed ontology term.
- Only a released `metric_definition` term can serve as the governed metric target.
- A high embedding similarity does not by itself authorize a cross-language merge.
- Accepted human assertions are locked; reconciliation may propose but must not overwrite them.
- Merges are recorded as reversible lifecycle changes rather than deleting the original concept.
- Every resolution is intended to be attributable through its method, score, provenance, and decision log.
- The full cross-lingual acceptance example depends on the deployment having released `metric_definition` terms and approved vocabulary evidence. The specification does not establish that those rows exist in every live database.

## 10. Reference

This manual is based on:

`KnowledgeStore/doc-repo/specs/202608/2026080403-spec-keyword-canonicalization-and-reconciliation.md`

The specification is the authoritative source for implementation status, thresholds, schema details, and deferred work.

## Change Log

| Version | Timestamp | Author / responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.0 | 2026-08-12T14:00:00-05:00 | Not specified | Initial manual | Explained how document metric names resolve to `kb.keyword_concepts`, how concepts align to released `kb.ontology_terms`, and how both identifiers appear on metric rows. |
