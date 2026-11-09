---
title: Product Review — User Manual
language: en
format: markdown
version: 1.5
status: current
author: Not specified
owner: Not specified
audience: Compliance and quality engineers, product engineers, knowledge-base operators, and reviewers who need to find every metric that applies to a product
create-time: 2026-11-09T11:00:00-06:00
last-modify-time: 2026-11-09T11:00:00-06:00
keywords: Product Review, Product Metric Reviewer, PMR, Applications menu, product metrics, scope profile, scope tree, lifecycle aspects, coverage report, coverage gaps, evidence, PDF highlight, metric details, full details, export CSV, re-run, run diff, past reviews, product name typeahead, product drawing, resizable panels
supersedes: product-metric-reviewer-v1.3-en.md
---

# Product Review

Menu path: **Development → Applications → Product Review**

## 1. What it is

Product Review answers one question: *which metrics apply to this product?* You give it a
product name. It returns every metric in the knowledge base that applies to that product, each
with the document it came from, the exact lines, and a plain-language reason for including it.

It finds more than a name search would. A product is made of modules and parts, and most
metrics belong to a part, not to the product: *display luminance* belongs to the display,
*battery endurance* to the battery. It also covers the conditions a product has to meet over
its life, such as storage temperature or drop tests, whose subject is a condition and not a
part. None of these mention the product's name. Product Review first builds a picture of the
product (its parts and its lifecycle conditions), then finds every metric attached to any piece
of that picture, wherever in the knowledge base it sits.

Use it to assemble a standards-conformance file, to check that a product's documents cover a
required measurement, or to see which parts of a product have no supporting metrics.

## 2. Before you start

- You need a ChenWeb login with access to **Applications → Product Review**. If the item is
  missing from the menu, ask your administrator about your role. (Other Applications items such
  as Installed, Browse, Configure and Generate Doc are admin-only; Product Review is not.)
- Everything in this manual happens in the page itself. No operator step is needed.
- Starting a review opens the results in the same page. Leaving Product Review through the menu
  and coming back always returns you to the start screen.

## 3. Concepts you'll see

**Scope profile.** A saved, reusable description of one product: the product, its parts nested
as deep as the breakdown goes, and a fixed set of lifecycle **aspects** (storage, transport,
maintenance, usage environment, safety and so on). One profile can serve many runs.

**How the profile is built.** It happens automatically before you see the tree:

1. An AI pass proposes the breakdown from the product name and description.
2. Each part is *grounded*: matched, where possible, to an identity the knowledge base already
   tracks across documents. A part that matches nothing stays in the tree and is matched by text.
3. The tree is *expanded* with part relationships the knowledge base already records, which can
   add real parts the AI pass never named.

**Tiers.** Each metric carries exactly one tier, based on what it matched:

| Tier | Meaning |
|---|---|
| `direct` | The metric's subject is the product itself. |
| `part` | The subject is one of the product's parts or modules. |
| `aspect` | The subject or context is a lifecycle aspect (storage, safety, …). |
| `document_scope` | Matched no specific part, but was found in a document that is about the product. |

**Two ways a metric is found.** By document (every metric in a document about the product) and
by subject (every metric whose subject matches a part, in any document). The two are combined.
A metric found either way, or both, appears once and records how it was found. On screen the
path is shown as `document_first` or `direct`.

**Run and report.** Each execution is one *run*: a result list plus a coverage report. Runs are
repeatable and kept; each remembers the profile version it used.

**Profile version.** Editing the breakdown raises the version. Editing never changes a past
run's results.

## 4. Start a review

Open **Applications → Product Review**. The top card, **Review a product**, has these fields:

| Field | Notes |
|---|---|
| **Product name** (required) | Type to get suggestions from the product-name catalogue. It matches Chinese names, English names and aliases (up to 20 suggestions). Picking one records its English name with the review. You can also type a name that isn't in the catalogue. |
| **Keywords** (optional) | Comma-separated. Stored on the product and usable to filter Past reviews. |
| **Image Generation Model** | The model used to draw the product (see below). The list comes from your deployment's configuration; the first entry is the default. |
| **Short description** (optional) | A sentence or two about the product. It helps the breakdown. |
| **Notes** (optional) | Background for whoever reads the run later. |

Select **Start**. The page creates the profile, builds it, runs the first review and opens the
results.

**Automatic drawing.** When you Start, the page looks for an existing product drawing with the
same name and attaches it. If none exists, it generates one with the model you picked. If
drawing fails, the review still goes ahead without a picture. You can generate one from the
Results page later.

### If the product has already been reviewed

If the name exactly matches an existing profile (ignoring case and surrounding spaces), no
second profile is created. You get an **Already reviewed** card with:

- **View results**: opens the latest completed run.
- **Re-run**: starts a fresh run against the existing profile.
- **Start over**: dismisses the card and returns to the form.

If the profile never finished a run, only **Re-run** is offered. "Ventilator" and "Ventilator
Model X" are different products.

### Past reviews

Below the form, **Past reviews** shows one card per profile. Each card has:

- the product drawing (or a placeholder);
- the name, as `Chinese / English` when both exist;
- keywords, description and the metric count of the latest run;
- the latest run's status (Completed, Running…, Failed, Pending, Never run) and, for a
  completed run, how long ago it finished;
- a **View results** button, when the profile has a run.

**Selecting a card** (anywhere except View results) fills the form with that product's name,
description, keywords and notes, and changes the button from **Start** to **Re-Run**. **Re-Run**
starts a fresh run on the stored profile, or resumes it if it was never run, and opens the
results. If you edit the product name to something else, the selection drops and the button
returns to **Start**.

Controls above the cards:

- **Sort**: by time, product name or metric count, ascending or descending.
- **Filter by keywords**: tick one or more keywords. A product matches if it has *any* ticked
  keyword. Ticked keywords show as chips; click a chip to remove it.
- **Filter by name**: case-insensitive "contains" search.

The list updates as you change these. It has no pagination and shows a bounded number of
profiles, so a very old review can drop out of view. It is still found by entering its exact
name in the form.

## 5. The results page

Starting or opening a run shows the review. **← Back** returns to the start screen.

**Header.** It shows the product name and a one-line summary: run status, the number of results
matched to a part, the number from document scope, and the number of documents in scope. A
warning shows how many results were dropped by size caps, if any. Two buttons sit at the right:

- **Export CSV** downloads every result of this run. Columns: `artifact_type`, `artifact_id`,
  `primary_label`, `document_record_id`, `source_line_spans`, `matched_node_id`, `tier`,
  `score`, `paths`, `inclusion_reason`.
- **Re-run**: see [Section 9](#9-re-run-a-review).

If the profile was edited after this run, a banner says which version the run used, which is
current, and offers **Re-run**.

**Tabs.** **Results** (with the result count) and **Report** (with the gap count).

### 5.1 The product drawing

At the top of the Results tab is an illustration of the product in an exploded-view style. It
is an orientation aid, not an engineering model, and there is no downloadable file.

If the profile has no drawing, a generator is shown instead. It has a **Drawing prompt**
(pre-filled from the product name and its parts, and editable) and a **Model** pulldown. Select
**Generate 3D Drawing**, look at the result, then **Keep** it (saved with the product, shown
automatically from then on) or **Discard** it and try again. Once a drawing is kept,
**Regenerate** replaces it. The current one stays visible until a replacement is kept. One
drawing is kept per product.

### 5.2 Layout

Below the drawing are three areas, left to right:

1. **Scope tree** ([Section 6](#6-the-scope-tree)).
2. **Results list** ([Section 7](#7-the-results-list)).
3. **Right-hand pane**: the **source PDF** on the left and the **Metric Details** panel on the right
   ([Section 8](#8-evidence-metric-details-and-the-source-pdf)).

Drag any thin divider to resize: between the areas, between the PDF and Metric Details, and
under the drawing for its height. The scope tree has a collapse button (the panel icon in its
header) that shrinks it to a narrow rail; use the same button to expand it. The Results tab
uses the full window width. Your sizes and the collapsed state are remembered per browser, not
per account, and the Report tab has its own layout. In a narrow window the panes stack.

The generic "App Status" side panel is hidden on this page, because Product Review uses that
space for its own panes.

## 6. The scope tree

The scope tree shows the product at the root, its modules and parts below, and the lifecycle
aspects. Each row shows:

- a **kind badge**: product, module, part or aspect;
- an **origin marker**: `llm` (proposed by the AI pass), `graph` (added from knowledge-base
  relationships) or `user` (added by a person);
- a **grounding dot**: tied to a knowledge-base identity, or text-only;
- a **warning triangle** when the matched identity is ambiguous and needs a person's judgment;
- a **count** of results attributed to that node in this run.

Click a row to filter the results list to that node. Click it again, or use **Clear**, to remove
the filter. Rows with children can be folded.

Row actions:

- **✓ Accept** / **✕ Reject**: include or exclude the node in future runs. A rejected node is
  shown struck through.
- **Pencil**: rename the node. Press Enter or **Save**.
- **+**: add a **part** or **module** under this node, for something the breakdown missed.
- **Trash**: delete a node. The product root cannot be deleted.

Every edit raises the profile version. **The run on screen keeps its own results.** Only a new
run picks up your edits, so use **Re-run** afterwards.

## 7. The results list

Results are grouped by the scope-tree node they matched, largest group first. Each row shows
the tier, the metric label, the document number (`#123`), the path, and the score.

Filters above the list, combined with a selected tree node:

- **Tier**: `direct`, `part`, `aspect` or `document_scope`.
- **Path**: `direct` (found by subject) or `document_first` (found through a document).
- **Document**: one source document, shown as `#id · kind`.
- **Text**: free text over the label, the inclusion reason and the metric id.

Results with no specific part match (`document_scope`) are collapsed into one **Document scope**
group showing only a count, because one large standard can contribute hundreds. Click the group
header to expand it.

If nothing matches, the pane says so. If the run has gaps, it links to them.

## 8. Evidence, Metric Details and the source PDF

Click a result row. Two things happen:

- The **source PDF** opens in the right-hand pane at the first cited page, with the cited lines
  highlighted. If the document has no PDF preview, the pane says so.
- **Metric Details** fills in:

| Field | Meaning |
|---|---|
| Artifact | The metric's id. |
| Metric name, Subject | From the metric record. |
| Object | The scope-tree node's canonical object (or "None (document scope)"). |
| Document | `#id`. Click it to open a dialog with the document's record fields and doc metadata. |
| Matched name | The scope-tree node the result was matched to. |
| Path | How it was found. |
| Value, Threshold, Unit, Frequency, Class, Data type, Range type | From the metric record; `—` when empty. |
| Score | The ranking score. |
| Line spans | The source lines. |
| Inclusion reason | Plain-language explanation of why the result was included. |

**Full Details** (button at the bottom of Metric Details) opens a dialog with the complete
metric record, as the Knowledge Base → Metrics workspace shows it. It has five groups:
**Metric**, **Metadata**, **Context**, **Grounding** and **Reasoning**. Each header shows how many
fields are filled, for example `(7/12)`. Close it with **Close**, Escape, or a click outside.
You stay on the page.

Always check a finding against the highlighted source text before relying on it.

## 9. Re-run a review

Select **Re-run** (in the header, or in the stale-version banner) to execute a fresh run of the
same review. Do this after new documents were added to the knowledge base, or after curating
the scope tree. The new run gets its own number, results and report, and the report compares it
with the previous run. Earlier runs are not changed or removed.

## 10. The Report tab

- **Headline counts**: attributed (matched to a part), document scope, documents in scope, and
  truncated (dropped by caps).
- **Coverage by scope node**: one row per accepted node, with kind, grounding, and the number of
  metrics and documents it matched. Rows with zero metrics are highlighted.
- **Coverage gaps**: every accepted node that matched zero metrics. This is often the most
  useful part. "No metric found for the humidifier module" is a finding, not a blank. A gap
  with a text-only grounding is more likely a part the system couldn't pin down than a real
  hole in the documents. Curating that node may close it on the next run.
- **Truncation**: documents whose results were capped, with how many were dropped.
- **Change since run N** (when this isn't the first run): results **Added**, **Removed** and
  **Re-tiered**. If the profile version changed between the two runs, the report says so, so you
  can tell a change in the documents from a change you made to the breakdown.

## 11. Understand the outcomes

- **No results.** Look at the gap list. The profile may need more or better-grounded nodes, or
  the knowledge base may genuinely lack coverage.
- **Results need judgment.** Product Review is an assistive retrieval tool, not a compliance
  decision. A returned metric is one the system found relevant. It isn't certified as correct,
  current or governing.
- **Repeatable within a version.** An AI model is used only for the initial breakdown (and
  occasionally to map an unusual lifecycle aspect) and for drawings. Retrieval, scoring, tiering
  and the report are deterministic. The same profile version and documents give the same results.

## 12. Current boundaries

- One product per profile. A related product gets its own profile.
- Metrics only. Provisions, inventory items and similar are not included.
- Per-document and per-run caps apply. When one is hit, the highest-scoring results are kept,
  the number dropped is recorded, and a part-matched result is never dropped to make room for
  a document-scope one.
- The lifecycle aspect list comes from deployment configuration and may differ between
  installations.
- The AI breakdown and graph expansion are not exhaustive. Use node curation to fix gaps.
- Duplicate detection matches the exact name only.
- Past reviews has no pagination and is bounded.
- Re-Run from a selected card does not save edited description or keywords. Only edited notes
  carry into the new run.
- Drawings are 2D illustrations, one per profile, and are never generated unless you start a
  review (the automatic drawing) or choose to generate one.
- Panel sizes are per browser.
- The Product Name suggestions come from a catalogue loaded once per page visit. Names
  added to it later appear after you reload the page.

## 13. Troubleshooting

| Problem | What to check |
|---|---|
| Product Review isn't in the menu | Look under **Development → Applications**. If it's missing, ask your administrator about your role. |
| I got "Already reviewed" instead of a new review | A profile with that exact name exists. Choose **View results** or **Re-run**. |
| A review I did long ago isn't in Past reviews | The list is bounded. Enter its exact name in the form. |
| I selected a past review by mistake | Change the product name field. The selection drops and the button returns to **Start**. |
| My description/keyword edits didn't affect Re-Run | Expected. Only notes carry over. |
| No drawing appeared after Start | Drawing is best-effort. Open the Results tab and use **Generate 3D Drawing**. |
| No drawing area on the Report tab | The drawing is shown on the Results tab only. |
| The drawing looks wrong | **Discard**, edit the prompt, and generate again. Nothing is saved until **Keep**. |
| The results list looks empty | Check the Tier, Path, Document and Text filters and any selected tree node. Expand the collapsed **Document scope** group. |
| My tree edits didn't change the results | Expected. The run on screen is fixed. Use **Re-run**. |
| The banner says the profile changed since this run | Select **Re-run**. |
| A part has a warning triangle | Its matched identity is ambiguous in the knowledge base and needs a person's judgment. |
| A node has zero results | Check the Report's gap list and the node's grounding (Section 10). |
| The PDF pane is empty | Click a result row. If the pane says no preview is available, that document has no PDF. |
| A panel is too narrow, or the scope tree is in the way | Drag a divider, or collapse the scope tree with its header button. |
| A result looks wrong or out of date | Read the highlighted source text and open **Full Details** before relying on it. |

## Change Log

| Version | Timestamp | Responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.5 | 2026-11-09T11:00:00-06:00 | Not specified | Manual rewritten against the current page | Replaces `product-metric-reviewer-v1.3-en.md` (which carried version 1.4 inside). Added: results shown in the same menu item with a Back button; product-name typeahead; Image Generation Model and automatic drawing at Start; richer Past reviews cards with a View results button; Export CSV; the PDF viewer with line highlights beside Metric Details; Full Details dialog and document record dialog; collapsible scope tree and the PDF/details splitter. Corrected: the run on screen keeps its results after tree edits; menu path and access. |
