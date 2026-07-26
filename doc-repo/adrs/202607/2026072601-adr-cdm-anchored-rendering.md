# ADR 2026072601 — CDM Anchored Rendering: Typst Layout as the Location Substrate

**Date:** 2026-07-26 \
**Status:** Implemented \
**Component:** SemOS CDM rendering and provenance — Typst renderer, `kb.cdm_anchors`, line-file generation, document viewer \
**Authors**: Chen Ding \
**Tags**: SemOS, CDM, typst, provenance, highlight, viewer, svg, doc-processing

## Change Logs
* 2026/07/26, ADR created. Records the decision that a Typst anchored render —
  not a generated PDF — is the location substrate for authored documents.
  Capability was verified hands-on against Typst 0.14.2 before the decision was
  taken.
* 2026/07/26, Phase 1 implemented in `ChenWeb/server/api/cdm/`. Added an
  Implementation Notes section recording four real corrections found only
  through actual Typst compilation (cross_reference via `#link` not `#ref`,
  citation as plain text not `#cite`, lists needing an explicit `#block[...]`
  wrapper, table-row anchors embedded in cell content rather than as table
  arguments), a confirmed X/W fragment-precision limitation, and the
  `kb.cdm_renderings` schema fix (new `page` column) it took to store
  multiple SVG pages. Status moved to Implemented.

## Context

Applications built on the SemOS knowledge base depend on being able to answer
"where did this come from?" — to jump to the place an artifact was extracted and
highlight it. That capability is what makes an extracted metric or provision
trustworthy to a human reviewer.

Today it works only for uploaded documents. MinerU parses a PDF into a canonical
`.txt` line file plus per-element bounding boxes; artifacts anchor to
`source_line_spans` (the convention appears in ~48 places across the migrations);
and `web/src/lib/components/home3/shared-pdf-viewer.svelte` paints
`.pdf-highlight` overlay elements at those boxes over rendered PDF pages,
scrolling the first one to center.

CDM introduces documents authored inside SemOS, which have no source file. The
obvious path was to make them mimic uploaded documents: render to PDF, parse the
PDF back with MinerU, and rejoin the pipeline. That works, but it is a lossy
round trip — the layout engine already knows exactly where everything is, and
re-deriving that from a rendered PDF discards the knowledge and then
approximates it back.

The question this ADR answers: can a Typst render serve the viewer's location
needs directly, without a PDF in the loop?

## Decision

**Yes. A CDM document renders to paginated SVG pages plus an anchor map, and
that pair replaces the PDF as the location substrate.** Typst's layout engine is
treated as an authority on document geometry, not merely as a typesetter.

### DR1 — The viewer contract is narrow enough to satisfy directly

The existing viewer needs exactly two things:

> **`line span → {page, x, y, w, h}`, plus paginated pages to draw on.**

Everything else — scroll-to-center, overlay painting, zoom — is viewer-side and
origin-agnostic. So parity does not require producing a PDF; it requires
producing that contract.

### DR2 — Anchor extraction via `typst query`

Each anchorable unit is wrapped in a marker that records `here().position()`
into a Typst `state`. The document terminates with a queryable `metadata` label,
read back out of band with:

```
typst query <file> "<label>" --field value
```

This yields exact `{id, page, x, y, w, h}` in points for every unit.

**Verified** against Typst 0.14.2: positions are returned as expected; units
that flow past a page break correctly report `page: 2` with `y` measured from
that page's origin rather than cumulatively.

### DR3 — Paginated SVG is the viewing target; Typst HTML export is not

`typst compile --format svg` emits one SVG per page, each carrying its page box
as the `viewBox`, in the same coordinate space as the query output. **Verified:**
a rectangle placed at an externally queried bounding box lands exactly on its
block when rendered — checked visually, not merely numerically.

Typst 0.14.2 also offers an `html` export target which produces clean semantic
HTML, and it was rejected. It emits
`html export is under active development and incomplete … do not rely on this
feature for production use cases`, and decisively it discards pagination:
`page set rule was ignored during HTML export`. Without pages there are no page
coordinates and the DR1 contract collapses.

*Accepted cost:* SVG emits text as glyph references, so rendered text is not
selectable. Text selection and in-document search must be driven from the line
file and anchor map — which is already how they work for uploaded documents. If
true text selection is later required, the answer is an invisible text layer
positioned over the SVG from the anchor map, the technique PDF viewers use.

### DR4 — Anchor granularity is the line-file unit, with paired start/end marks

Anchors are emitted per **line-file unit** — the same unit that becomes one line
in the generated line file: a paragraph, list item, table row, heading, equation,
or code block. Matching the two granularities makes `line span → location` a 1:1
index lookup rather than a range computation.

Each unit emits **two** marks, start and end, rather than one position plus a
measured height. `measure()` reports a unit's height in isolation, which is wrong
whenever the unit breaks across a page: a probe unit measured 108pt of content
inside an 80pt page body, so a single-record highlight would have run off the
bottom of page 1 and painted nothing on page 2. **Verified:** paired marks
correctly report a unit starting on page 1 and ending on page 2, from which one
highlight fragment per occupied page is derived — the same way a PDF viewer
paints a multi-page selection.

`kb.cdm_anchors.fragment_ordinal` carries those per-page fragments.

### DR5 — Line file and anchor map are generated in one pass

Both are emitted from the same AST in the same operation, and publish fails if
any line file line lacks exactly one anchor.

This is the decision that makes the mapping exact **by construction** rather
than inferred. The contrast is concrete: `ChenWeb/server/cmd/backfill-mineru-list-bboxes`
exists because MinerU gave every item in a list one shared, oversized box, so
"highlighting a single cited line visually painted" the wrong region — a repair
tool made necessary by an inferred mapping. CDM has no equivalent failure mode
available to it, provided the two artifacts are never produced separately.

### DR6 — Anchor maps are versioned with what produced them

The anchor map depends on layout, so it is valid only for the `content_version`
and `renderer_version` that produced it; both are part of the key on
`kb.cdm_anchors`. A Typst upgrade or a theme edit shifts coordinates and
invalidates stored maps — versioning makes that detectable rather than silently
wrong.

### Alternative Decisions

* **Render to PDF and re-parse with MinerU (rejected).** Maximal reuse — CDM
  documents would be literally indistinguishable downstream. Rejected as a lossy
  round trip: it discards exact geometry the layout engine already has, then
  approximates it back, inheriting MinerU's inference errors for content that
  never needed inferring. It also puts PDF generation and PDF parsing on the
  critical path for viewing.
* **Typst HTML export as the viewer target (rejected, DR3).** Semantic, small,
  and text-selectable. Rejected: unpaginated and explicitly not production-ready.
* **Position plus measured height per unit (rejected, DR4).** Half the marks and
  a simpler record. Rejected: demonstrably wrong for page-spanning units.
* **Anchor per top-level block rather than per line-file unit (rejected, DR4).**
  Fewer anchors. Rejected: turns span resolution into a range computation and
  makes highlights coarser than the citation they represent — the precise defect
  the MinerU backfill tool had to repair.

### Database Migrations

`kb.cdm_anchors` (spec §11), created with the other `kb.cdm_*` tables through
goose migrations at implementation time.

### Data Formats

Anchor coordinates are in **points**, in the page coordinate space shared with
the rendered SVG `viewBox`. One row per highlight fragment; `fragment_ordinal`
is `0` for units contained on a single page.

### Environment Variables

None. The Typst binary becomes a runtime dependency of publish; ChenWeb already
shells out to `typst compile` in `server/api/doc-reviews/typst_report.go`, so
the invocation pattern and the binary are established.

## Implementation

Not started. Planned as capability `cdm-anchored-rendering` and task group 9 in
`ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`.

### Code Changes

None yet. At implementation: anchor emission in the Typst renderer, an anchor
extraction step invoking `typst query`, fragment derivation from paired marks,
SVG page rendering, line-file generation, and a resolver from
`source_line_spans` to highlight fragments.

## Operational Behaviors

- Publish becomes a multi-step operation that shells out to Typst twice (render
  to SVG, query anchors). Publish latency is therefore bounded by Typst, not by
  the database.
- A Typst version upgrade invalidates every stored anchor map. Maps must be
  regenerated, which is safe because they are derived — but until they are,
  highlights for previously published documents are stale. Version pinning and
  a regeneration path are required operationally.
- Because both origins converge on the same line file, the doc-process pipeline,
  extractors, and review tooling need no CDM awareness.

## Consequences

- Navigation and highlight work identically for authored and uploaded documents,
  which was the goal.
- For authored documents the provenance is **more** accurate than for uploaded
  ones: ground-truth coordinates from the layout engine, and an exact
  line↔location mapping.
- PDF generation moves off the critical path. It remains available for export
  and download, but nothing in viewing, navigation, or highlight depends on it.
- Typst is promoted from an output format to a load-bearing runtime dependency.
  Its availability, version, and layout stability now affect a core user-facing
  capability.
- The frontend viewer must generalize: `shared-pdf-viewer.svelte` needs to become
  origin-agnostic with two page backends (PDF canvas, SVG pages) behind one
  highlight contract. Scoped as a follow-on change.
- Text selection in CDM documents is not solved by this decision (DR3).

## Implementation Notes (2026/07/26)

Phase 1 was implemented in `ChenWeb/server/api/cdm/{model,rendering,store}`.
The design above held; four points below were discovered only once real Typst
compilation was in the loop, not from reasoning about the design, and are
recorded because they change what a future maintainer needs to know.

* **`cross_reference` renders as `#link(label(id))[...]`, not
  `#ref(label(id))`.** Verified against the compiler: `#ref` only resolves
  Typst's own numbered/referenceable elements (headings, figures, equations
  with numbering enabled) and hard-errors — "cannot reference text" — on
  arbitrary content such as a plain paragraph. Since a CDM `cross_reference`
  must be able to target *any* block, `#link` is the only mechanism that
  resolves universally.
* **`citation` renders as plain bracketed text, not `#cite(label(...))`.**
  `#cite` requires an actual `#bibliography` to be present in the document or
  it hard-errors ("the document does not contain a bibliography"). Phase 1
  builds no bibliography infrastructure, and `reference` blocks (the entries a
  citation would resolve against, spec §7) are not even a supported block type
  in this renderer — Phase 3 scope. Rendering visible text instead of a call
  guaranteed to fail was the only defensible Phase 1 choice.
* **Every block is wrapped, but a `list` needs an explicit `#block[...]`
  container.** Every rendered block gets a Typst label matching its own id,
  used for both cross-reference targets and (see below) as the anchor point.
  Attaching that label directly after a bare list's markup was verified to
  attach to the *last item*, not the list as a whole — the compiler warns
  "content labelled multiple times... only the last label is used" and
  silently discards the earlier one, which would have broken that item's own
  reference/anchor. Wrapping list items in `#block[...]` gives the list's own
  label a container to attach to instead.
* **Anchors are a separate mechanism from content labels, by necessity for
  tables.** A `#table(...)` call's positional arguments are all cells
  (row-major, by declared column count); a bare `mark()` call inserted as an
  extra argument would corrupt the table's shape. Verified instead that a mark
  embedded *inside* a cell's own content — `[#mark(id, "start")text]` —
  records its position without disturbing layout, so each row's start/end
  marks live in its first and last cell respectively.

One precision limitation was found and is now documented prominently rather
than silently accepted: fragment `x`/`w` use the page's full content
margin/width for every unit, not the unit's actual rendered width. This is
verified pixel-accurate for full-width flow content (paragraphs, headings) —
confirmed both by automated bounds checks and by a manual visual proof
(rendering a real document, painting a rectangle at the derived fragment
coordinates over the real compiled page, and inspecting the image) — but
visibly overshoots for narrower content such as a table, and undershoots the
true left edge for indented list items. The Y-axis (page and vertical
bounds — the harder problem, since it required solving pagination) is
unaffected and pixel-accurate in both cases. Fixing X/W precision would need a
per-unit measured width, which is deferred rather than solved now, consistent
with this ADR's DR4 rejection of `measure()` for the page-spanning case.

A related schema gap was found and fixed: `kb.cdm_renderings`' original unique
key `(document_id, content_version, renderer, renderer_version)` had no room
for a paginated renderer, since one document produces multiple SVG files
(one per page) under the same renderer/version. Migration
`20260726000002_add_page_to_kb_cdm_renderings.sql` adds a `page` column
(`0` for non-paginated renderers) and widens the unique key to include it;
applied and rolled back cleanly against the live `miner` database before being
left applied. See ADR 2026072501's storage section and spec §11 (updated).

## Tests

The capability was verified experimentally before deciding (see the original
Tests section content below), then re-verified end-to-end during
implementation against the real Typst 0.14.2 binary and the live `miner`
database — not merely asserted at the Go string level:

* `TestGoldenFilesCompileWithTypst`, `TestAnchoredRendering_AlignmentAgainstRenderedSVG`,
  and the `TestRenderSVGPages_*` / `TestExtractAnchors_*` suites all compile
  real Typst source and/or query the real compiler; these caught the four
  implementation-notes findings above, none of which were visible from
  Go-level assertions alone.
* `TestCollectUnits_EveryUnitHasExactlyOneAnchorPair` queries real Typst output
  and asserts the coverage property directly (every anchorable unit has
  exactly one start and one end mark).
* `TestExtractAnchors_PageRelativeCoordinates` and
  `TestDeriveFragments_PageSpanningUnit` force a real 40-paragraph document
  across a page boundary and verify page-relative coordinates and the
  paired-mark fragment derivation end to end.
* `TestPublisher_PublishEndToEnd` and `TestPublisher_RepublishSupersedesArtifacts`
  (`ChenWeb/server/api/cdm/store/publish_test.go`) exercise the full pipeline —
  save, create draft, publish (render, extract anchors, derive fragments,
  generate line file, render SVG pages, persist all of it, transition
  `kb.inputs`) — against the live database, including `ResolveHighlight`
  returning a well-formed fragment for a real line number.

Pre-implementation findings, retained for the historical record:

* `typst query` returns exact per-unit `{page, x, y, w, h}` — confirmed.
* Units past a page break report page-relative coordinates on the correct page —
  confirmed (`page=2`, `y` reset).
* A rect placed at an externally queried bbox aligns with its block in the
  rendered output — confirmed visually.
* `measure()` is unreliable for page-spanning units — confirmed (108pt measured
  inside an 80pt page body).
* Paired start/end marks correctly straddle a page break — confirmed
  (`start page=1 y=40.4`, `end page=2 y=70.4`).
* Typst HTML export discards pagination — confirmed
  (`page set rule was ignored during HTML export`).

Not yet done: an actual doc processor (e.g. `extract_metrics`) has not been run
against a generated CDM line file to confirm its artifacts carry usable
`source_line_spans` end to end — that requires the doc-processor
binary/worker, outside what could be driven in this session. A direct
side-by-side parity check against an uploaded document's real highlight
resolution code path is likewise not done; `ResolveHighlight` is verified to
return the documented `{page, x, y, w, h}` shape, but not compared line-by-line
against the PDF-based resolver's actual output.

## Documentation Impact

*What knowledge changed:* Typst's role in CDM was elevated from a publication
target to the location substrate for authored documents, and the CDM document
lifecycle was defined. It was also established that both document origins share
one doc-process pipeline — correcting an earlier plan that would have excluded
authored documents from extraction.

*Which docs were updated:* spec `2026072501-spec-canonical-doc-model` — new §5.6
(Anchored Rendering), rewritten §10 pipeline showing both origins converging,
new §10.1 (Document Lifecycle and Line-File Generation), `kb.cdm_anchors` added
to §11, §13.1 extended, §16 refreshed, and the preface reframed. ADR 2026072501
amended with DR11–DR14. Change artifacts under
`ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`.

*Which docs are now stale:* none identified. The frontend viewer has no design
doc yet; the follow-on change that generalizes `shared-pdf-viewer.svelte` should
create one.

*What was intentionally left undocumented:* the line-file dialect (must be read
off the current MinerU output before the generator is written); the SVG delivery
strategy (pre-render at publish vs. on demand); and the invisible-text-layer
design for text selection, which is only needed if that requirement firms up.

## References
- Spec: `doc-repo/specs/202607/2026072501-spec-canonical-doc-model.md` §5.7, §10.1, §11
- ADR 2026072501 (CDM v1.0 schema decisions) — DR11–DR14 in particular
- Change: `ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`,
  capability `cdm-anchored-rendering`
- Implementation: `ChenWeb/server/api/cdm/rendering/{anchors,svg,linefile,typst}.go`,
  `ChenWeb/server/api/cdm/store/publish.go`
- Migrations: `ChenWeb/project_migrations/20260726000001_create_kb_cdm_tables.sql`,
  `..._20260726000002_add_page_to_kb_cdm_renderings.sql`
- Existing viewer: `ChenWeb/web/src/lib/components/home3/shared-pdf-viewer.svelte`
- Existing Typst invocation: `ChenWeb/server/api/doc-reviews/typst_report.go`
- Existing line-file dialect: `ChenWeb/server/api/file-converters/opendata.go` (`formatOpenDataLines`), `mineru.go`
- Inferred-mapping failure precedent: `ChenWeb/server/cmd/backfill-mineru-list-bboxes/main.go`
- Worklist queries: `ChenWeb/server/api/kbhandler/handler.go:679`, `:748`
