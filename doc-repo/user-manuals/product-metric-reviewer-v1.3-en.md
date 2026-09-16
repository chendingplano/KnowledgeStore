---
title: Product Metric Reviewer — User Manual
language: en
format: markdown
version: 1.4
status: current
author: Not specified
owner: Not specified
audience: Compliance and quality engineers, product engineers, knowledge-base operators, and reviewers who need to find every metric that applies to a product
create-time: 2026-09-12T06:47:28-05:00
last-modify-time: 2026-09-16T19:00:00-05:00
keywords: Product Metric Reviewer, PMR, product metrics, metric coverage, scope profile, scope tree, part hierarchy, lifecycle aspects, coverage gaps, coverage report, metric retrieval, compliance review, standards review, evidence drawer, run diff, re-run, knowledge base, start a review, self-service, Applications menu, duplicate product, view results, past reviews, review history, card list, product drawing, 3D drawing, generate drawing, resizable panels, results layout
---

# Product Metric Reviewer

## 1. What it is

Product Metric Reviewer answers one question: *which metrics apply to this product?* Give it
a product — a name like "Ventilator," optionally with a short description — and it returns
every metric in the knowledge base that applies to that product. Not just metrics with the
product's name on them, but the metrics of the product's parts, and the metrics that govern the
product across its life: storage, transport, maintenance, the environment it runs in, safety,
packaging, disposal. Every metric comes back with the document it was found in, the exact
lines, and a plain-language reason it was included.

Use it when you need a complete, evidence-backed list of the metrics that apply to a product —
for example, to assemble a standards-conformance file, to check whether a product's
documentation set actually covers a required measurement, or to see at a glance which parts of
a product have no supporting metrics at all.

### Why a name search doesn't work

Searching the knowledge base for the word "ventilator" misses most of the answer. A product is
a nested thing — a product made of modules, made of parts, made of smaller parts — and most
metrics are attached to a part, not to the product itself. *Display luminance* is a metric of
the display. *Battery endurance* is a metric of the battery. *Leakage current* is a metric of
the power supply. None of those mention the word "ventilator," so a name search misses all of
them.

A name search also misses the conditions a product has to satisfy over its lifetime. A
storage-temperature limit or a drop-test requirement is about the ventilator, but its subject is
a condition, not a part, so again the product's name never appears in it.

Product Metric Reviewer bridges that gap by building a picture of the product first — its parts
and its lifecycle conditions — and then finding every metric attached to any piece of that
picture, wherever in the knowledge base it lives.

## 2. Before you start

You need access to ChenWeb. Open **Applications → Product Review** from the workspace
navigation to start a review yourself — no administrator hand-off is needed.

If someone instead sends you a direct link to a specific run (a page at
`/home3/product-metric-review` with a run identifier), that works too and opens straight to that
run's results — see [Section 4](#4-start-or-open-a-review).

Everything described in this manual — starting a review, reading results, curating the
product's breakdown, exploring the report, and re-running the review — happens in the page
itself, with no operator involvement needed.

## 3. Concepts you'll see

A few ideas recur throughout the page. Understanding them makes everything else easier to read.

**Scope profile.** A saved, reusable description of a product's structure: the product itself,
its parts (nested as deep as the breakdown goes), and a fixed set of lifecycle **aspects** —
storage, transport, maintenance, usage environment, safety, and similar — attached to it. One
profile can be reused by many review runs, and a closely related product (an anaesthesia machine
next to a ventilator, say) can start from a copy.

**How the profile is built.** A profile is assembled in three passes, and you don't need to do
anything to trigger them — they run before you ever see the tree:

1. A single AI pass proposes the product's breakdown from its name and description.
2. Each proposed part is *grounded* — matched, where possible, to an identity the knowledge base
   already tracks across many documents, so that later matching works by identity rather than by
   spelling. A part that matches nothing stays in the tree and is matched by its text only.
3. The tree is *expanded* using part relationships the knowledge base already records, which can
   add real parts the first pass never named.

**Tiers.** Every metric that comes back is labeled with exactly one tier, based on *what it
matched*:

| Tier (as shown on screen) | Meaning |
|---|---|
| `direct` | The metric's subject is the product itself. |
| `part` | The metric's subject is one of the product's parts or modules. |
| `aspect` | The metric's subject or context is one of the lifecycle aspects (storage, safety, and so on). |
| `document_scope` | The metric matched no specific part of the product, but it was found in a document that is about the product. |

A metric whose subject is the display is always tier `part` — even if the only reason it
surfaced is that its document happened to be in scope.

**Two ways a metric is found.** The app looks by document (every metric in a document that is
about the product) and by subject (every metric whose own subject matches a part of the
product, regardless of which document it's in) — independently, then combines the results. A
metric found either way, or both ways, appears exactly once and keeps a record of every way it
was found. Looking by subject is what surfaces a figure like *display luminance* sitting in a
third-party component datasheet that never mentions the product's name at all.

**A run and its report.** Each time a review is executed it produces one *run*: a list of
results plus a coverage report. Runs are repeatable — the same request can be run again later,
and the app can compare the new run to the previous one.

**Profile version.** Every time the product's breakdown is edited, its version number goes up.
A finished run always remembers the exact version it ran against, so editing the profile later
never changes a past run's results.

## 4. Start or open a review

### Starting a new review

Open **Applications → Product Review** from the workspace navigation. You'll see a short form:

- the product's **name** (required) — this is what Product Metric Reviewer matches later if you
  or someone else starts a review for the same product again, so use the name you'd want to
  find it under;
- an optional **short description**;
- optional **keywords**, kept on the product for search later;
- optional **notes** — background for whoever reads the run afterward.

Select **Start**. Product Metric Reviewer creates the product's profile, builds it (see
"How the profile is built" in [Section 3](#3-concepts-youll-see)), runs the first review, and
takes you straight to its results.

### Browsing and re-running a past review

Below the form, a **Past reviews** list shows every product that already has a profile, most
recently updated first, each as a card with its name, description, keywords, and its latest run's
status ("Completed," "Running…," "Failed," or "Never run") and — for a completed run — how long
ago it finished.

Select a card to fill the form above with that product's name, description, keywords, and notes.
The form stays on screen and stays editable — selecting a card is not the same as the "product
already reviewed" choice described below — and the action button changes from **Start** to
**Re-Run**. Selecting **Re-Run** starts a fresh run against that product's existing profile (or,
if the profile was created but never successfully run before, resumes it) and takes you to the
results.

You can still edit the description, keywords, or notes before selecting **Re-Run**; edits to
notes carry into the new run the same way manually entered notes would. If you change the
**product name** field to something other than the selected card's name, the selection is
dropped and the button reverts to **Start** — editing the name always means "review a different
product," never "re-run this one under a new label."

Use the controls above the cards to sort by time, product name, or metric count, in ascending or
descending order. **Filter by keywords** lists every keyword currently used by your product
profiles; selecting multiple keywords shows products that contain *any* selected keyword. **Filter
by name** performs a case-insensitive substring search across the product names. Filters update the
list as you change them, and you can remove selected keyword chips individually.

The Past reviews list has no pagination and shows a bounded number of profiles after applying the
selected sort and filters. A product you reviewed a long time ago may still fall out of the
bounded result set even though its profile and past runs are unaffected.

### If the product has already been reviewed

If the name you enter matches a product that already has a profile, Product Metric Reviewer
does not create a second, duplicate profile. Instead it offers you a choice:

- **View results** — opens the latest completed run for that product, exactly as described
  under "Opening a specific run directly" below.
- **Re-run** — starts a fresh run against the product's existing profile, using its current
  breakdown and version. This is the same action described in [Section 9](#9-re-run-a-review).

If the existing profile has never finished a run — an earlier attempt didn't complete — only
**Re-run** is offered, since there is no run yet to view.

### Opening a specific run directly

Someone can also send you a direct link to one run: a page at `/home3/product-metric-review`
with a run identifier. Opening it loads the product's name, the breakdown tree, the results, and
the coverage report for that run.

If the profile has been edited since the run you're viewing was produced, a banner at the top
tells you so and offers a **Re-run** action (see [Section 9](#9-re-run-a-review)).

## 5. Read and curate the scope tree

The left-hand pane shows the product's breakdown as a tree: the product at the root, its parts
and modules nested underneath, and the lifecycle aspects attached to the root.

Each row shows:

- a **kind badge** — product, module, part, or aspect;
- an **origin marker** — whether the node was proposed by the AI pass, added by the graph-expansion
  pass, or added by a person;
- a **grounding dot** — whether the node is tied to a reconciled identity in the knowledge base,
  or is matched by text only;
- a **warning flag** on a node whose matched identity is itself ambiguous in the knowledge base
  and needs a person's judgment;
- a **count** of how many results the current run attributed to that node.

Select a row to filter the results pane to that node alone; select it again to clear the filter.

You can curate the tree directly:

- **Accept** or **reject** a node to include or exclude it from future runs.
- **Rename** a node whose label needs correcting.
- **Add** a child node under any part or module — for something the automatic breakdown missed.
- **Delete** a node that doesn't belong (the product root itself cannot be deleted).

Every edit raises the profile's version. The run you're currently viewing keeps showing its own
results unchanged; only a *new* run picks up your edits.

## 6. Explore the results

### The product drawing

At the top of the **Results** tab, above the scope tree, results, and metric-details panes, the
page shows a generated illustration of the product under review — a technical, exploded-view
style drawing, similar to what you'd see in an assembly manual. It's a picture meant to help you
orient yourself, not an engineering-accurate 3D model or a file you can open in CAD software.

If the profile doesn't have a drawing yet, this area shows a generator instead: a description of
the drawing to create, already filled in from the product's name, description, keywords, and
notes (you can edit it before generating). Select **Generate 3D Drawing**, review the result, and
either **Keep** it — which saves it against this product so it appears automatically the next
time you open the review — or **Discard** it and try again with a different description. Once a
drawing is kept, a **Regenerate** action lets you replace it later; your current drawing keeps
showing until a replacement is generated and kept, so you're never left without one mid-attempt.

Below the drawing, the scope-tree, results, and metric-details panes can each be resized by
dragging the thin divider between them, and the divider under the drawing resizes its height the
same way. On this tab the page also uses the full width of your window rather than stopping at a
fixed maximum, so there's more room for all three panes at once. Your chosen sizes are
remembered in this browser for next time; they aren't shared with other browsers or devices, and
the Report tab (Section 8) keeps its own, unrelated layout.

### Filtering and grouping

The results pane lists every metric the run found, grouped by the scope-tree node it matched.

Use the filters above the list to narrow what you see:

- **Tier** — show only `direct`, `part`, `aspect`, or `document_scope` results.
- **Path** — show only results found "by document," only those found "by subject," or both.
- **Document** — narrow to one specific source document.
- **Text** — free-text search across the result's label and its inclusion reason.

Selecting a node in the scope tree also filters the list to that node; the two filters combine.

Metrics with no specific part-of-the-product match — the `document_scope` tier — are collapsed
into their own group by default, showing only a count, because a single large standard can
contribute hundreds of them. Expand that group when you want to see them.

If a run returns no results at all, the pane says so and links you to the report's gap list
(see [Section 8](#8-the-coverage-report)), which is usually the more useful thing to look at.

## 7. Look at the evidence

Select any result to open the evidence drawer. It shows:

- the metric's identity and label;
- the source **document** it was found in, with a link to open that document;
- the exact **line spans** it came from;
- which **node** it was matched to (or a note that it matched no node);
- which **routes** found it ("by document," "by subject," or both);
- a plain-language **reason** explaining why the result was included — naming the matched node
  and the evidence, or, for a `document_scope` result, naming the document and why that document
  was in the product's scope.

Use the document link to open the source and check the finding against the original text before
relying on it.

## 8. The coverage report

Open the **Report** tab to see the run's summary:

- headline counts — how many results matched a specific part of the product versus how many
  came only from a scoped document, how many documents were in scope, and how many results were
  dropped by the run's size caps (see [Section 11](#11-current-implementation-boundaries));
- a **coverage table** — one row per accepted node in the scope tree, with its grounding state
  and how many metrics and documents it matched;
- a **gap list** — every accepted node that matched *zero* metrics.

The gap list is often the most actionable part of the report. For someone assembling a
conformance file, "no metric found for the humidifier module" is a finding, not a blank space.
Each gap also shows the node's grounding state, which tells you whether the gap is likely a real
hole in the source documents or simply a part the app was never able to pin down to an identity
— curating that node (Section 5) may close the gap on the next run.

When the run you're viewing is not the first run of its review, the report also shows a **diff**
against the previous run: which results are new, which are gone, and which changed tier. If the
scope profile itself changed version between the two runs, the report says so, so that you can
tell a genuine change in the source documents apart from a change you made to the product's
breakdown.

## 9. Re-run a review

Select **Re-run** to execute a fresh run of the same review — for example, after new documents
have been added to the knowledge base, or after you've curated the scope tree and want to see
the effect. The new run gets its own number, its own results, and its own report, and the report
compares it to the run before it (Section 8).

Re-running does not change or remove any earlier run; each one is kept, with the exact profile
version it used.

## 10. Understand the outcomes

**No results.** The run found nothing. Check the report's gap list — the profile may need more
or better-grounded nodes, or the corpus may genuinely lack coverage.

**A gap in the report.** An accepted node with zero metrics is either a genuine gap in the
source documents, or a part the app could not tie to a reconciled identity. The node's grounding
state tells you which is more likely.

**Results need judgment.** Product Metric Reviewer is an assistive retrieval tool, not a
compliance decision. A result being returned means the app found a documented metric it
considers relevant to the product — it does not by itself certify that the metric is the
correct, current, or governing one for your purpose. Always open the evidence and check it
against the source document.

**It's repeatable, within a version.** The only place the app uses an AI model is the initial
breakdown of the product (and, occasionally, mapping an unusual lifecycle aspect). Everything
after that — scoring, matching, tiering, and the report — is deterministic lookup work. Given
the same profile version and the same documents, running a review twice produces the same
results with the same tiers.

## 11. Current implementation boundaries

- **One product family per profile.** A profile describes one product; a closely related product
  is handled as its own profile.
- **Metrics only, for now.** This version of the app finds metrics. Other kinds of requirements
  (provisions, inventory items, and similar) are not yet included.
- **Per-document and per-run caps.** A single document can carry a very large number of
  results, so the app caps how many results one document contributes and how many a whole run
  returns. When a cap is reached, the highest-scoring results are kept, the number dropped is
  recorded on the run, and a specific-part-of-the-product result is never dropped to make room
  for a document-only result.
- **The lifecycle aspect list is fixed by configuration.** Storage, transport, maintenance,
  usage environment, safety, and the rest come from the deployment's configuration; a different
  installation may show a different aspect list.
- **The AI-proposed breakdown and the graph-expansion pass are not exhaustive.** A generic or
  unusual part may be missing from the first draft. This is exactly what node curation
  (Section 5) is for, and every correction you make is kept for future runs of the same profile.
- **Duplicate detection matches on name only.** Starting a review offers "view results" or
  "re-run" when the product name you enter matches an existing profile exactly (after trimming
  spaces and ignoring letter case) — not when it's merely similar. "Ventilator" and "Ventilator
  Model X" are treated as different products and each gets its own profile.
- **The Past reviews list has no pagination.** It shows a bounded number of profiles after applying
  the selected sort and filters. A product you reviewed a long time ago may fall out of the list
  even though its profile and past runs are unaffected and still reachable by re-entering its exact
  name (Section 4) or by a direct run link.
- **Re-running from a selected card doesn't save edited description/keywords.** Editing those
  fields before selecting Re-Run changes what's shown on screen but is not written back to the
  stored profile — only edited **notes** carry into the new run. To change a profile's stored
  description or keywords, edit its scope tree/profile directly rather than through this list.
- **The product drawing is an illustration, not a 3D model.** Generating one produces a single
  2D image in a technical, exploded-view style; there is no downloadable 3D file, and nothing is
  generated automatically — you choose when to generate, keep, discard, or regenerate. One
  drawing is kept per profile at a time; regenerating replaces it, it doesn't add a gallery.
- **Panel and drawing sizes are per-browser.** Dragging the dividers on the Results tab is
  remembered on the device and browser you used, not synced to your account, so the layout may
  look different the next time you open the page on another computer or browser.
- **The dashboard's generic side panel doesn't appear on this page.** When Product Review is
  open inside the main ChenWeb dashboard, the "App Status" side panel that other pages can show
  is not available here — this page uses that space for its own scope-tree, results, and
  metric-details panels instead. This has no effect on any other page.

## 12. Troubleshooting

| Problem | What to check |
|---|---|
| I can't find Product Review in the navigation | Confirm you have access to ChenWeb and look under **Applications → Product Review**. If it's still missing, ask your administrator about your permissions. |
| A run link won't open | Confirm you have the correct link, including the run identifier — or start a fresh review instead from Applications → Product Review (Section 4). |
| I entered a product name and got offered "View results" / "Re-run" instead of a new review | That's expected: a profile for that exact product name already exists. Choose **View results** to see its latest run, or **Re-run** to get a fresh one (Section 4). |
| A product I reviewed a while ago isn't in the Past reviews list | The list only shows the most recently updated profiles (Section 11). Re-enter its exact product name in the form instead — the duplicate check above still finds it. |
| I selected a past review by mistake and want to start fresh | Edit the product name field to something else, or clear it and type a new name — the selection drops automatically once the name no longer matches (Section 4). |
| I edited the description/keywords before Re-Run but the results don't reflect them | Expected — Re-Run from a selected card doesn't save those edits to the profile (Section 11). Edit the profile's scope tree directly instead. |
| The scope tree looks wrong or incomplete | Curate it directly — accept, reject, rename, add, or delete nodes (Section 5) — then ask for a re-run. |
| A part shows a warning flag | Its matched identity is ambiguous in the knowledge base; it needs a person's judgment rather than an automatic pick. |
| A node has zero results and no warning flag | Check the report's gap list and the node's grounding state (Section 8). It may be a real coverage gap, or a part that never matched an identity. |
| The results list looks empty | Check whether a filter (tier, path, document, or text) is active, and whether the collapsed "from a scoped document" group is hiding results (Section 6). |
| The banner says the profile changed since this run | Select **Re-run** to see results that reflect the current scope (Section 9). |
| A result looks wrong or out of date | Open the evidence drawer, follow the document link, and check the source text directly (Section 7) before relying on the result. |
| No drawing appears and there's no generator either | Confirm you're on the **Results** tab — the drawing area doesn't show on the Report tab (Section 6). |
| The generated drawing doesn't look right | Select **Discard**, adjust the prompt text, and generate again; nothing is saved until you select **Keep** (Section 6). |
| A panel is too narrow or too wide | Drag the thin divider between panels (or below the drawing) to resize it; your choice is remembered in this browser (Section 6, Section 11). |
| I don't see the "App Status" panel other pages have | Expected on this page — Product Review uses that space for its own panels instead (Section 11). |

## Change Log

| Version | Timestamp | Responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.4 | 2026-09-16T19:00:00-05:00 | Not specified | Past-reviews sorting and filtering shipped | Documented the Past reviews sort controls, tenant keyword picker with OR matching, case-insensitive name filtering, live updates, and the bounded filtered result set. |
| 1.3 | 2026-09-13T09:15:00-05:00 | Not specified | Product drawing and resizable results layout shipped | Documented the new product-drawing area at the top of the Results tab (Section 6): generating, keeping, discarding, and regenerating a drawing, and that it's a 2D illustration rather than a 3D model. Documented that the scope-tree, results, and metric-details panels are now independently resizable and that the Results tab uses the full window width (Section 6), and that the dashboard's generic "App Status" side panel no longer appears on this page (Section 11). Added three implementation-boundary bullets to Section 11 and four rows to Section 12's troubleshooting table. |
| 1.2 | 2026-09-13T07:55:00-05:00 | Not specified | Past-reviews list shipped | Documented the new "Past reviews" card list on the intake page (Section 4): browsing previously reviewed products, selecting a card to prefill the form and relabel the action **Re-Run**, editing the product name to drop the selection, and that edited description/keywords aren't saved back through this path (only notes are). Added two new implementation boundaries to Section 11 (no search/pagination on the list; edited description/keywords not persisted via Re-Run) and three rows to Section 12's troubleshooting table. |
| 1.1 | 2026-09-12T08:10:00-05:00 | Not specified | Self-service intake shipped | Documented the new in-page "start a review" flow reachable from Applications → Product Review (product name, description, keywords, notes, and a Start action); documented the duplicate-detection choice ("view results" or "re-run") offered when a product name matches an existing profile; updated Section 2 to remove the operator hand-off requirement, rewrote Section 4 to cover starting a new review and opening a specific run directly, removed the two now-resolved implementation boundaries from Section 11, and updated Section 12's troubleshooting table accordingly. |
| 1.0 | 2026-09-12T06:47:28-05:00 | Not specified | Initial manual | Documented the current Product Metric Reviewer implementation: what it does, the scope profile and its curation, tiers and the two retrieval routes, the results and evidence views, the coverage report and run diff, re-running a review, and current implementation boundaries. |
