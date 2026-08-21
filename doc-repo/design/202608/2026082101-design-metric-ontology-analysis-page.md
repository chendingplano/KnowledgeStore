# Metric Ontology Analysis — Dashboard Model-Graph Redesign

**Date:** 2026-08-21 \
**Status:** Draft \
**Component:** ChenWeb / Home3 \
**Source decision:** [ADR 2026082004](../../adrs/202608/2026082004-adr-metric-ontology-analysis-page.md) · amends [2026082005-design-metric-ontology-analysis-page.md](2026082005-design-metric-ontology-analysis-page.md) §4
**Audience:** ChenWeb frontend implementers, ontology operators, QA

## 1. Purpose

This document redesigns the layout of Page 1 — Metric Dashboard from
`2026082005-design-metric-ontology-analysis-page.md` §4, so that the Metric Ontology Model
(`metric-ontology-v1.0-en.md` §5, "The Metric Ontology model") is the page's visual center: a
full-width hero band carrying the whole of §5 as a diagram, with the dashboard's existing KPIs,
panels, and table grouped by entity beneath it instead of stacked linearly. It amends §4 only. Everything else in the prior design doc — the shared shell (§3), Document Metrics (§5–6),
Ontology Metrics (§7–8), non-happy-path behavior (§9), delivery order (§10), and out of scope (§11)
— is unchanged and still applies.

This is a presentational redesign. No new data, filter, or interaction is introduced; every KPI,
panel, and table listed in the prior §4 is kept, only relocated and visually grouped.

## 2. The Metric Ontology Model as a diagram

The diagram is the page's teaching surface: a reader who has never opened the manual should be able
to look at it and come away with the shape of the model. It therefore renders the whole of manual
§5, not just the four tables the metric row joins to.

### 2.1 Three lanes, one per population

Manual §5.1 divides everything a metric touches into three populations, distinguished by what
reprocessing a document does to them. The diagram makes that division its primary axis: three
horizontal lanes, each in its own colour, labelled down the left edge.

| Lane | Colour token | Holds |
|---|---|---|
| **Ontology-born** (top) | `--bronze` | `kb.ontology_modules`, module releases, the `kb.ontology_terms` / `kb.ontology_term_headers` shell and its term kinds, `kb.ontology_candidates`, `kb.ontology_term_labels`, and the governed `kb.metric_value_range_type_map` |
| **Corpus-level identity** (middle) | `--violet` | `kb.keyword_concepts`, `kb.object_nodes`, `kb.semantic_claim_identities` |
| **Record-born** (bottom) | `--blue` | `kb.inputs`, `kb.metrics`, `kb.artifact_objects`, `kb.semantic_decision_candidates`, `kb.semantic_assertions`, `kb.assertion_evidence`, `kb.semantic_processing_outcomes` / `_findings` |

The second axis is the pipeline. The record-born lane runs left to right through the processor
order of manual §9 — `extract_metrics`, `normalize_assertions`, `associate_semantics` — with the
stage name printed above each arrow. Every reference a record makes to a shared or governed
identity is drawn as an upward edge into the lane above, so "what this row means" is always read
vertically and "what happens next" is always read horizontally.

`kb.metrics` keeps the emphasis treatment it had in the previous design (accent border and tinted
fill): it remains the point of contact between all three populations.

### 2.2 The governed vocabulary, expanded

Inside the ontology lane, the terms shell carries the identity line from manual §3.2 (identifier ·
kind · module · version · status) and groups the term kinds a metric actually reaches, under three
headings:

* **Metric identity** — `metric_definition` (§5.2) and `class` / metric class (§5.5).
* **Measurement science** — the `quantity_kind → dimension → unit` chain of §4.2, plus
  `kb.metric_value_range_type_map`, drawn with a dashed border because it is governed but is *not*
  an ontology term (§5.2).
* **Claim frame** — the eight assertion kinds of §4.3 and the binding properties of §4.1.

The six measurement classes of §4.1 run as a single caption along the bottom of the shell rather
than as six boxes, because they are a frame the reader needs named, not a set of nodes anything in
the diagram points at individually.

`kb.ontology_modules → module release` sits to the left of the shell (governance in, §7.3) and
`kb.ontology_candidates` and `kb.ontology_term_labels` to its right, both drawn with dashed edges —
candidates because auto-promotion (§7.2) is a different kind of arrival than curation, labels
because they name a term rather than participate in resolution.

### 2.3 The edges that carry the meaning

Manual §5.5 singles out three joins; all three are labelled edges in the diagram, together with the
rest of the assertion's outbound references:

| Edge | From → to | Label |
|---|---|---|
| Name to concept to term | `kb.metrics` → keyword concept → terms shell | `metric_name`, then `core:aligns_to_term` |
| Claim to subject | `kb.metrics` → object mention → object node → `kb.semantic_assertions` | `subject`, `reconciled to`, `subject_object_id` |
| Claim to class | `kb.semantic_assertions` → terms shell | `instance_of · assertion kind · unit · quantity kind` |
| Range/unit lookup at normalization | `kb.semantic_decision_candidates` → terms shell | `resolves value range type · unit · quantity kind` |
| Claim convergence | `kb.semantic_assertions` → canonical claim identity | `logical_identity_key` |
| Attributability | `kb.assertion_evidence` → `kb.inputs` | dashed return edge along the bottom of the record lane |

A legend above the canvas restates the three populations with the reprocessing rule that
distinguishes them, so the colour coding is decodable without the manual.

### 2.4 Rendering constraints

The diagram is hand-authored inline SVG on a `0 0 1520 740` viewBox, scaled to the card width. It
carries `<title>` and a full `<desc>` narrating the model for screen readers. Colours come from the
page's existing theme tokens so the diagram follows light/dark with the rest of the shell.

Two mechanical rules matter for anyone editing it:

* Mix accent tokens with `transparent`, never with `--border` or `--surface`, in `color-mix(in
  oklch, …)`. Interpolating between two tokens with distant hues swings through the intervening
  hues — mixing `--blue` into `--border` renders green, and `--violet` into `--border` renders pink.
  Where an opaque tint is wanted (the `kb.metrics` fill, the card background) use `in srgb`.
* The canvas scrolls inside its own `overflow-x: auto` wrapper with a `min-width` floor, and the
  grid cell holding it sets `min-width: 0`. Without that floor the labels become unreadable on
  narrow screens; without `min-width: 0` the floor pushes the whole page into horizontal scroll.

## 3. Redesigned Page 1 layout (supersedes the §4 layout diagram)

**Desktop layout**

```text
┌ ScopeBar ────────────────────────────────────────────────────────────────────────┐
│ [document] [class] [status …]                              [Reset filters]       │
├ CoverageStrip ───────────────────────────────────────────────────────────────────┤
├ METRIC ONTOLOGY MODEL — full-width hero band ────────────────────────────────────┤
│ kicker · title · lede · legend                                                   │
│ ┌ ontology-born lane ──────────────────────────────────────────────────────────┐ │
│ ├ corpus-level lane ───────────────────────────────────────────────────────────┤ │
│ └ record-born lane (extract → normalize → associate) ─────────────────────────-┘ │
├─────────────────────────────────────┬────────────────────────────────────────────┤
│ ontology_terms spoke                │ semantic_assertions spoke                  │
│ KPI · Ontology metrics              │ KPI · Current instances                    │
│ KPI · Metric classes                │ Coverage state (chart + table)             │
│ Mapping inventory table             │ Errors by type (chart + table)             │
├─────────────────────────────────────┴────────────────────────────────────────────┤
│ assertion_evidence spoke (full width)                                            │
│ KPI · Occurrences  ·  KPI · With errors  ·  KPI · No detected errors             │
│ Error presence (donut + exact-value table)                                       │
│ Recent metric occurrences (table)                                                │
└──────────────────────────────────────────────────────────────────────────────────┘
```

The graph is a full-width band above the spokes rather than the middle column between them. A
diagram carrying the whole of §5 needs roughly 1500px to stay legible, which the centre column of a
three-column band cannot supply; and the band, with its accent top rule, warm gradient and legend,
reads as the page's centre by prominence and reading order instead of by geometry. The spokes
below keep the entity grouping and the reading order of §4 unchanged — `ontology_terms` left,
`semantic_assertions` right, `assertion_evidence` full width beneath.

The page shell widens with it: `.content` goes to `max-width: 1840px` with
`padding-inline: clamp(18px, 2.4vw, 46px)`, which also gives the mapping inventory and coverage
tables room they did not have in the narrow spokes.

On narrow screens (≤1050px) the band collapses to a single column in reading order: graph,
`ontology_terms` spoke, `semantic_assertions` spoke, `assertion_evidence` spoke. The diagram itself
then scrolls horizontally within its own wrapper rather than shrinking its labels below legibility.

## 4. Component-to-entity mapping

Every KPI, panel, and table from the prior §4 implementation details is kept; only its position
changes. The mapping below is what implementers should place in each spoke:

| Component (2026082005 §4) | Spoke | Why it belongs there |
|---|---|---|
| "Ontology metrics" KPI | `ontology_terms` | governed `metric_definition` term count |
| "Metric classes" KPI | `ontology_terms` | instantiated `class` terms in the `measurement` module |
| Mapping inventory panel | `ontology_terms` | the metric-definition ↔ governed-term mapping table — the manual §5.5 "name to concept to term" join, made visible |
| "Current instances" KPI | `semantic_assertions` | distinct current `kb.semantic_assertions` rows |
| Coverage state panel (complete / findings / blocked / …) | `semantic_assertions` | these are assertion-lifecycle states produced by `associate_semantics` adjudication |
| Errors by type panel (unresolved unit, range-type fallback, missing assertion edge, …) | `semantic_assertions` | these findings are recorded during `normalize_assertions`/`associate_semantics`, i.e. while building the assertion from `Metrics` and `ontology_terms` |
| "Occurrences" KPI | `assertion_evidence` spoke | record-born row count, grounding the center `Metrics` entity in its concrete, evidence-linked occurrences |
| "With errors" / "No detected errors" KPIs | `assertion_evidence` spoke | occurrence-level error presence, grounded in the evidence-linked occurrence view |
| Error presence donut | `assertion_evidence` spoke | same grain as the KPIs above it |
| Recent metric occurrences table | `assertion_evidence` spoke | each row is one occurrence together with its document/evidence context — the concrete, evidence-grounded instances of the model |

## 5. What stays unchanged

The shared shell (§3 of the prior doc — ScopeBar, CoverageStrip, StateBadgeGroup, mode tabs,
responsive rules for the shell itself), Document Metrics (§5–6), Ontology Metrics (§7–8), the
non-happy-path table (§9), delivery order (§10), and out-of-scope list (§11) all apply as written
and are not touched by this redesign. Within the relocated Page 1 components, their existing
data/interaction requirements (exact-value table beside every chart, drill-down count equivalence,
zero-vs-unavailable handling, accessible captions) still apply — only their position on the page has
moved.

## 6. Change log

### 2026-08-21 — model graph expanded and promoted to a hero band

Reason: the shipped diagram carried four entities (`kb.metrics`, `ontology_terms`,
`assertion_evidence`, `semantic_assertions`) against a manual §5 model of roughly twenty, and at
~40% of a three-column band it had no room to carry more. Users reported that it neither drew the
eye as the page's centre nor taught the model.

Changes: §2 rewritten — the diagram now renders all three populations of manual §5.1 as colour-coded
lanes, the pipeline of §9 as the horizontal axis, the governed term kinds of §3.2/§4.1–4.3 grouped
inside a `kb.ontology_terms` shell, and every join of §5.5 as a labelled edge; §2.4 added, recording
the SVG/accessibility contract and the `color-mix` and `min-width` rules the implementation depends
on. §3 layout diagram replaced — the graph moves from the centre column of the three-column band to
a full-width hero band above two spokes, and the page shell widens to `max-width: 1840px`. §4's
component-to-entity mapping is unchanged; only the graph's position moved.
