# Provision Window (Focus Mode) — Implementation Notes

Companion to the `Provisions` section in
[`+CAPSULE.md`](+CAPSULE.md). This document records **how** the Provision Window is
built and **why** certain design and engineering choices were made.

## Summary

When the user clicks a provision in the `kb.provisions` list, the main navigation
panel and the record-list panel are both hidden and the view enters **focus mode**:
the full viewport is split between an **Information Panel** (left, scrollable
attribute list) and a **PDF Display Panel** (right, source document with line
highlights).

The full UI lives in a single component:

- [`ChenWeb/web/src/lib/components/home3/provision-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/provision-mgmt-view.svelte)

It is modeled directly on the Metric Window
([`metric-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte))
and shares the same `KbInputRecordBrowser` / `PdfViewWindow` plumbing. The backend
list endpoint mirrors `GET /kb/metrics?input_record_id=N` with a new
`GET /kb/provisions?input_record_id=N` handler added in
[`provision_handlers.go`](../../../../ChenWeb/server/api/kbhandler/provision_handlers.go).

## Opening the Provision Window

Clicking a provision card calls `selectMetric(m)` (the function retains the
metric-window name internally):

```ts
async function selectMetric(m: KbProvisionRecord) {
    selectedMetricId = m.id;
    highlightSelectionVersion += 1;
    enterFocusMode();                  // hides the left panels
    const first = normalizeMetricSpans(m)[0];
    if (!first) return;
    docPage = first.page_number > 0 ? first.page_number : 1;
}

function enterFocusMode() {
    if (recordBrowserFolded) return;
    recordBrowserFolded = true;
    onFocusModeChange?.(true);
}
```

`recordBrowserFolded = true` collapses the three-column body to a single column
(`minmax(0, 1fr)`), hiding the record browser and the provision sidebar. The
`.right` section gains the `.focus-split` class, switching it to a flex-row split.

The `Escape` key calls `goBack()` when focus mode is active.

## Layout of the Provision Window

```
.right.focus-split  (flex-direction: row)
├─ .metric-canvas-wrap          (flex: 1 1 0; min-width: 0; overflow: hidden)
│  ├─ .canvas-toolbar           (toolbar strip — see Controls below)
│  └─ .metric-canvas            (overflow-y: auto; scrollable)
│     ├─ .attr-view             (when a provision is selected)
│     │  ├─ .attr-view-header   (provision name + optional sub-label)
│     │  ├─ .attr-group × 5    (one rounded card per group)
│     │  │  ├─ .attr-group-head (icon · label · filled/total count)
│     │  │  └─ .attr-group-body (attribute rows — see Attribute groups)
│     │  └─ …
│     └─ .canvas-empty          (when no provision is selected)
├─ .focus-resize-handle         (draggable column resizer, flex: 0 0 14px)
└─ .doc-frame-wrap              (flex: 0 0 {focusPdfWidth}px)
   └─ <PdfViewWindow>           (source document with source-line highlights)
```

The split between the two panels is draggable. The PDF panel width is stored in
`focusPdfWidth` (default: `round(window.innerWidth / 3)`), with bounds:

- **Minimum PDF width:** 280 px (constant `FOCUS_PDF_MIN`)
- **Maximum PDF width:** `round(window.innerWidth × 0.75)` — enforces that the
  Information Panel always occupies **at least 25%** of the viewport width
- Persisted to `localStorage["metrics:focus-pdf-width"]`

The Info Panel has its own draggable width (unused by the v1 text template but
wired up for future use), stored under `localStorage["metrics:info-panel-width"]`,
clamped to `[220, 620]`.

## Controls in the Information Panel toolbar

The `.canvas-toolbar` strip runs across the top of the Information Panel and
contains the following controls, left to right:

### Back button

```svelte
<button class="toolbar-back" onclick={goBack}>
    <ArrowLeftIcon /> Back
</button>
```

`goBack()` sets `recordBrowserFolded = false`, clears `selectedMetricId`, and
calls `onFocusModeChange?.(false)`. This restores the three-column body layout.

### Filter by name (dropdown)

```svelte
<select class="toolbar-select" value={metricNameDropdownValue}
        onchange={handleMetricNameDropdown}>
    <option value="">— Provision by name —</option>
    {#each metrics as m}
        <option value={m.id}>{metricNameOf(m)}</option>
    {/each}
</select>
```

Lists every provision in the current record. The select's `value` is kept in sync
with `selectedMetricId` via a `$effect`, so it always reflects whichever provision
is displayed — whether opened from this dropdown, the card list, or Prev / Next.

`metricNameOf(m)` resolves the display label as:
`prov_name → provision_subject → "Provision #<id>"`.

### Filter by keyword (text input)

Bound to `keywordFilter`. The `filteredMetrics` derivation retains only provisions
where `keywordFilter` (lowercased) appears in `provision_keywords`,
`provision_keywords_en`, `prov_name`, or `provision_subject`. A datalist is
populated from `allKeywords` — the union of all keywords across loaded provisions.
A clear button (×) appears while the field is non-empty.

### Filter by confidence (text input)

Bound to `confidenceFilter` with the same `≥N` / `<N` prefix semantics as the
Metric Window. A clear button (×) appears while the field is non-empty.

### Prev / Next buttons and position indicator

`prevMetric` and `nextMetric` are `$derived` from `filteredMetrics` and
`selectedMetricInFilteredIndex`. Both buttons are disabled at the boundary.
The position indicator shows 1-based position within the currently filtered list
(e.g. `3 / 12`).

## Information Panel — attribute display

When a provision is selected, the `.metric-canvas` area renders a scrollable
`.attr-view` with:

1. **Header** (`.attr-view-header`): the provision's primary label (`prov_name`,
   falling back to `provision_subject` or `Provision #id`) in serif, and the
   English sub-label below it in small monospace if present.
2. **Five group cards** (`.attr-group`): one rounded card per functional group,
   each with a brass header row and a body of attribute rows.

Groups and their attributes:

| Group | Icon | Attributes |
|---|---|---|
| **Metadata** | `BookOpenIcon` | ID, Name, Type, Confidence, Explicit, Verify |
| **Statement** | `FileTextIcon` | Provision, Subject, Desc |
| **Context** | `TagIcon` | Context, Keywords, Categories |
| **Grounding** | `MapPinIcon` | Lines (source line cards) |
| **Provenance** | `HashIcon` | Model, Prompt, Location |

Each attribute row uses one of three renderers driven by `AttrDef.kind`:

- **`text`** — a `gip-label` + `gip-val` pair on one line.
- **`chips`** — a `gip-label` above a row of `gip-chip` pill badges
  (`provision_keywords`, `categories`).
- **`lines`** — a `gip-label` above a stack of `gip-line-card` bordered cards,
  one per `LineEntry { head, content, lineType }`. The head shows
  `L<line> · P<page>` in brass monospace; a pill-shaped `line_type` tag follows
  if present.

Empty attributes render at reduced opacity with a dash (`—`) but are **not
hidden** — the layout is stable across provisions.

## PDF Display Panel

The right side of the focus split is a `<PdfViewWindow>` showing the source
document. When a provision is selected the viewer jumps to the page of the first
source span. Matched source lines are highlighted via `renderMetricHighlights`
using `selectedLinesByPage` built from `normalizeMetricSpans` + `rawLineByKey`.

The PdfViewWindow toolbar exposes:
- **Edit / Delete / Add line** buttons (shared raw-line editing utilities).
- **Source Lines toggle** — switches the right panel between the PDF renderer and
  a raw-line text view (`linesView` snippet).

## Span normalisation — provision-specific

Provision `source_line_spans` use a different encoding than metrics. Three formats
are handled by `normalizeMetricSpans`:

| Format | Example | Written by |
|---|---|---|
| `"page:line"` string | `"3:90"` | `CreateProvision` handler |
| `{page_number, line_number}` object | `{"page_number":3,"line_number":90}` | Extraction pipeline |
| Bare line-number string or number | `"90"` / `90` | Legacy / fallback |

For the `"page:line"` format the page number is taken directly. For bare
line-only forms the page is resolved via `lineNumToPage` (a `Map<lineNo, pageNo>`
built from the loaded `RawLine[]`). Bracket characters (`[`, `]`) are stripped
before matching so compacted JSON array strings are handled gracefully.

```ts
const mm = s.match(/^(\d+)\s*:\s*(\d+)$/);
if (mm) {
    // "page:line"
    pushLine(parseInt(mm[2], 10), parseInt(mm[1], 10));
}
```

Each span entry references a single source line (no range expansion), so
`spanCount(m)` is simply `raw.length`.

## Add Provision dialog

Drag-selecting lines on the PDF opens the **Add Provision** dialog
(`addMetricOpen`). The workflow:

1. **Selected Lines** table — shows page, line, type, content. Lines can be
   edited (saves to the raw_line file via `updateRawLine`), removed from the
   selection, or extended with the "+ Add" buttons above/below the table.
2. **Extracted Provisions** section — populated by `extractKbProvisions`, which
   calls `POST /kb/provisions/extract` with `{ record_id, source_line_spans }`.
   Individual results can be removed before saving.
3. **Save** — calls `saveExtractedKbProvisions` (`POST /kb/provisions/save`)
   then refreshes the provision list via `listKbProvisions`.

The dialog also supports **Extract Provision** (the legacy quick-create path via
`POST /kb/provisions`, now superseded by the extract/save workflow) — this button
was removed in the current version in favour of a single "Extract Provision"
button that runs the full extraction pipeline.

## Backend — `ListProvisions`

`GET /api/v1/kb/provisions?input_record_id=N`

Handler: `ListProvisions` in
[`provision_handlers.go`](../../../../ChenWeb/server/api/kbhandler/provision_handlers.go).
Returns every row in `kb.provisions` for one input record, ordered by `prov_id`,
with all canonical columns written by `SaveExtractedProvisions`:

```
id, input_record_id, prov_id, input_filename,
prov_name, prov_name_en, provision_type, source_text, source_line_spans,
provision, provision_en, provision_subject, provision_subject_en,
prov_desc, prov_desc_en, prov_context, prov_context_en,
provision_keywords, provision_keywords_en, category_paths, category_paths_en,
location_type, confidence, is_explicit, need_verify, model_name, prompt_name,
created_at
```

Response shape mirrors `ListMetrics`:

```go
type listProvisionsResponse struct {
    Status  bool                  `json:"status"`
    Results []provisionRecordJSON `json:"results"`
    Total   int                   `json:"total"`
}
```

## Data model

```ts
type AttrKind = 'text' | 'chips' | 'lines';
type LineEntry = { head: string; content: string; lineType: string };
type AttrDef = {
  key: string; label: string; icon: any;
  kind: AttrKind; value: string; items: string[];
  entries: LineEntry[];
  count: number; hasValue: boolean;
};
type GroupNode = {
  key: string; label: string; icon: any;
  count: number; filledCount: number; hasValue: boolean;
  // x, y, wire, satellites — geometry computed by metricsMap but not rendered
  attrs: AttrDef[];
};
type MetricsCanvas = {
  W: number; H: number; /* geometry — computed but unused by text template */
  metricLabel: string; metricSubLabel: string;
  groups: GroupNode[];
};
```

`buildMetricGroupAttrs` populates each group from the selected `KbProvisionRecord`.
`metricsMap = $derived.by(...)` assembles the canvas — geometry fields are
retained in the derived object but not consumed by the text-list template.

`KbProvisionRecord` in `kbService.ts` mirrors the `listProvisionsResponse` JSON.
`category_paths` and `category_paths_en` are typed `unknown` because the column
stores heterogeneous JSON (structured path arrays from the extraction pipeline or
plain string arrays from legacy data); `provisionCategoryStrings()` normalises
them to `string[]` for display.

## File map

- [`provision-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/provision-mgmt-view.svelte)
  — Everything described here lives in this one component.
- [`metric-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte)
  — The template this component was derived from.
- [`provision_handlers.go`](../../../../ChenWeb/server/api/kbhandler/provision_handlers.go)
  — `ListProvisions` handler (appended at end of file) and all other provision
  backend logic.
- [`kbService.ts`](../../../../ChenWeb/web/src/lib/services/kbService.ts)
  — `KbProvisionRecord`, `ListKbProvisionsResponse`, `listKbProvisions`.
- [`+page.svelte`](../../../../ChenWeb/web/src/routes/home3/knowledge/+page.svelte)
  — Wires `<ProvisionMgmtView>` into the `kb-provision-tree` section (nav label:
  **Provisions**).

## Maintenance notes

- **Adding an attribute to an existing group**: extend the array in
  `buildMetricGroupAttrs`. The text view auto-renders the new row based on
  `kind`. No template changes needed.
- **Adding a new group**: append a `GroupSpec` to `groupSpecs` in `metricsMap`,
  add its attribute array to `buildMetricGroupAttrs`'s return type, and populate
  it in the function body. The text view picks it up automatically.
- **Adding inline field editing**: add `PUT /kb/provisions/:id` to the backend
  (mirror `UpdateMetric` in `metrics_handler.go`), import `updateKbProvision` in
  the component, and wire the edit affordance to individual `gip-row` elements.
  The existing update-metric pattern is a direct template.
- **Adding global search**: `SearchProvisions` (`GET /kb/provisions/search`)
  already exists in the backend but returns `topicCategoryRecord` shape (not a
  flat provision record). A dedicated search subsystem similar to
  `kb-metric-search-state.js` / `kbMetricSearch.ts` would be needed. The sidebar
  has a ready slot where the search panel would go (between the count badge and
  the provision list).
- **Resizing the PDF panel**: `localStorage["metrics:focus-pdf-width"]` stores
  the last dragged width. Delete it to revert to the `round(window.innerWidth / 3)`
  first-load default. The 75%-of-viewport ceiling is enforced at runtime on every
  clamp call, so widths saved from a wider display are automatically clamped on a
  narrower one.
- **`category_paths` display**: `provisionCategoryStrings()` handles three wire
  formats (plain string array, `[[{name, keywords, confidence}, …], …]` chain
  array, `[{category_path: […], path_confidence, path_keywords}, …]` payload
  array). If a new extraction schema introduces a fourth format, extend that
  function — it is the single point responsible for normalising category paths to
  displayable strings.
