# ADR 2026072602 — CDM Editor Scope and Its Impact on the Canonical Document Model

**Date:** 2026-07-26 \
**Status:** Accepted (design only — not yet implemented) \
**Component:** CDM Editor, Canonical Document Model, artifact provenance, chunking, document versioning \
**Authors**: Chen Ding \
**Tags**: SemOS, CDM, editor, artifacts, chunking, versioning, templates, lifecycle

## Change Logs
* 2026/07/26, ADR created. Records the decisions taken while reviewing spec
  `2026072502-spec-cdm-editor` against CDM v1.0
  (`2026072501-spec-canonical-doc-model`). Seven questions were raised by the
  review; all seven were resolved. The CDM spec was updated with new §5.5,
  §10.2, §10.3, §10.4; the editor spec gained a Design Decisions section.
* 2026/07/26, DR5 resolved (was a deferral). The owner supplied a concrete
  workflow for generated appendices — author-triggered extraction, reconciled
  against human-marked assertions — which closes the document → pipeline →
  document cycle flagged in the original review. Added DR5a (drafts keep a
  `kb.inputs` row, amending DR13 of ADR 2026072501), DR5b (human/LLM
  reconciliation, human wins), DR5c (provenance is a display setting, never
  erased). New CDM spec §10.5, §10.5.1, §10.5.2; §10.1 corrected to match.

## Context

Spec `2026072502-spec-cdm-editor` proposes the CDM Editor: a browser-based
knowledge editor — explicitly *not* another Word or Google Docs — covering
search, rich text editing, semantic annotation ("Knowledge Markdown"), document
reviewers, summarization, extraction, rewriting, ontology association, chunking,
versioning, lifecycles, retention, templates, auto-generated content, deep
research, and chat-to-document.

Reviewing it against CDM v1.0 surfaced one apparent contradiction, three
constructs the model could not express, two decisions it appeared to overturn,
and a collision of terminology. Because CDM Phase 1 is planned but not yet
implemented, these were worth resolving before the schema ships rather than
after — several of them touch the AST or the storage model.

This ADR records the resolutions. It does not expand the Phase 1 change; most
outcomes are deferrals made explicit, and the two that affect the model are
additive.

## Decision

### DR1 — Formatting belongs to Typst templates, not to the document

The editor's Text Edit Tool exposes font, size, color, and alignment controls.
CDM §12 forbids storing exactly those properties. The resolution is that the
controls do not write into the canonical document: **templates carry formatting;
the document carries meaning.**

This is not a compromise but the design's central claim, and it is answering a
concrete requirement. Many organizations mandate document formatting, some in
extreme detail — China's mandatory standard for how a national standard must be
formatted prescribes fonts, sizes, spacing, numbering, and structure precisely.

A prior in-house solution built an online rich-text editor that enforced those
rules directly. It worked, but two failures followed: it became extremely
difficult to maintain, and it could not be generalized — it was welded to one
standard, and adapting it to another customer's rules was impractical because
the rules had never been a separable artifact.

CDM inverts that. The rules become a Typst template: data that is versioned,
reviewable, and swappable per customer, tenant, or document type via the
resolution order in CDM §5.4. A second formatting standard is a second template,
not a second editor.

The operational consequence for the editor is that its toolbar should expose
**semantic** actions — heading, emphasis, list, table, callout, definition — and
let the template decide appearance. Every presentation property admitted into a
document is one the template can no longer control, which is precisely the
leakage that made the earlier tool unmaintainable.

Recorded in CDM §5.5. Full support for a specific mandatory standard is deferred
until CDM and the editor are mature.

### DR2 — Author annotations are ordinary artifacts, and artifacts record origin

"Knowledge Markdown" — selecting a span and marking it as a `terminology`,
`concept`, `definition`, `entity`, `relation`, or `canonical object` — produces
**artifacts in exactly the same sense** as those a doc processor extracts. Same
tables, same search and review tooling, same provenance. They differ only in
production: far cheaper than an LLM extraction pass, and far more accurate,
because a human asserted them.

This composes cleanly with anchored rendering: an author annotates a text span,
spans resolve to line ranges through the line file, so an author-created
artifact carries the same `source_line_spans` as an extracted one — and
therefore identical navigate-and-highlight behavior with no special handling.

**Every artifact records an origin**, defaulting to `extracted`, with
`human-created` for author assertions. This follows the existing
`kb.images.origin VARCHAR(16) NOT NULL DEFAULT 'upload'` convention. The flag is
not bookkeeping: it tells consumers which assertions carry human authority, lets
review tooling skip re-verifying what a human asserted, and lets extraction avoid
overwriting it.

Artifact types that do not exist yet (`terminology`, `concept`, `definition`)
are planned as ordinary doc processors with ordinary tables. **CDM introduces no
new artifact types, and none are added in the current phase.** The origin column
is additive with a safe default, so it can ship with the first human-created
artifact source rather than now.

Recorded in CDM §10.3.

### DR3 — A new version is a new document

Each version of a document is a **separate document** with its own canonical
document and its own `kb.inputs` row, processed independently. Versions are
linked by a typed relation recorded on the input row — a dedicated column or
within `kb.inputs.doc_metadata` — naming the document a version derives from and
how it relates: `addendum`, `amendment`, `replace`.

This resolves the review's most urgent concern. `kb.cdm_documents` stores only
the current document, so a revision model that mutated a document in place would
have lost history irrecoverably — the one problem that cannot be retrofitted.
Treating versions as documents avoids it without a history table, and keeps each
version independently addressable, processed, and citable. That matters because
artifacts, `source_line_spans`, anchors, and renderings all bind to a specific
document; in-place mutation would invalidate all of them on every edit.

Two counters remain, and must not be conflated:

- `content_version` — the **within-document** edit counter, keying that
  document's derived renderings, anchors, and projections.
- The **version lineage** above — *between* documents, and what a reader means
  by "version 2 of the standard".

Recorded in CDM §10.4.

### DR4 — Chunking: authors declare semantically, the pipeline resolves physically

Chunking is an artifact produced after the line file, expressed as line ranges
with overlaps:

```text
overlap: []
lines: [1-23]

overlap: [21-23]
lines: [24-42]
```

Because the line file is logically the same for both document origins, this
artifact and its consumers are unchanged for CDM documents.

CDM adds only the ability for an author to declare chunk boundaries at the
**semantic** level — chunk-group identifiers on blocks, where a maximal run of
consecutive blocks sharing an identifier forms one chunk — which resolve to line
ranges once the line file is generated. Overlap stays the chunker's concern: the
author declares *where meaning divides*, the pipeline decides how much context to
carry across the seam. Absent any declaration the pipeline chunks automatically,
so author chunking is an optional refinement.

This mirrors anchored rendering (ADR 2026072601): the AST carries intent, and
physical coordinates are derived once the concrete artifact exists.

Recorded in CDM §10.2.

### DR5 — Generated appendices are author-triggered runs rendered as projections

Table of contents, list of figures/tables/formulas, and index remain deferred:
several require numbered, referenceable figures and tables, which CDM v1.0
deliberately omits (ADR 2026072501 DR6 folded `figure` into `image`). The
requirement is recorded rather than dropped, so the numbering authority can be
designed when it is actually needed.

The **artifact appendices** (metrics, topics, other artifacts) are resolved
rather than deferred, because their design was the source of the review's
circularity concern — document → pipeline → artifacts → document content.

The workflow: an author invokes *Generate Appendix of Metrics*; the system
generates the line file, chunks it, runs the `extract_metrics` doc processor,
reconciles the result with any metrics the author marked by hand, and renders
the appendix. It is the same line file, chunking, and processor used after
publication; only the trigger differs.

Three properties break the cycle: the trigger is **manual and bounded**; a draft
sits off both worklists so a run cannot enqueue further runs (DR5a); and the
appendix is a **render-time projection, not a stored block**. The third is
decisive — the appendix is rendered from current artifacts rather than written
back into the AST, so it cannot go stale, editing cannot invalidate it, and its
content can never be re-extracted as though it were authored prose. *Generate
Appendix* means "run extraction now so the appendix has current artifacts to
show", not "insert an appendix into my document".

#### DR5a — Drafts have an input row, kept off both worklists

Author-triggered extraction needs somewhere to attach artifacts while the
document is still being written, so a draft's `kb.inputs` row exists from
creation — **amending ADR 2026072501 DR13**, which had given drafts no row.

A draft is written with both derived states terminal
(`parse_state = 'parsed_success'`, `pipeline_state = 'success'`), so neither
worklist selects it and anything that runs does so because an author asked.
Publishing clears the `doc_processing` status entry, so `pipeline_state` derives
back to `'pending'` and the standard worklist enqueues the authoritative run.
Publish is a status transition, not a row creation.

Because a draft may already have been processed on demand, artifacts are keyed
to the `content_version` they derive from, and a later run supersedes artifacts
from an older version rather than appending to them.

#### DR5b — Human and LLM assertions are reconciled, human wins

An author who marked metrics by hand will often still want the extractor to run,
precisely because they may have missed some. The sources are complementary:
human marking is high **precision**, LLM extraction is high **recall**. So the
sets are reconciled, not concatenated. Where both assert the same metric they
merge into one and the **human assertion is authoritative** — its values,
wording, and boundaries win, and `origin` stays `human-created`. Where only the
extractor found something, it is added as `extracted`.

This is the class of problem the existing object reconciliation machinery solves
for entities and inventory items (`kb.reconcile_runs`,
`kb.entity_merge_candidates`, `kb.entity_merges`, `kb.inventory_item_merges`;
ADR 2026070701 for ambiguous ties). **No equivalent exists for metrics**, so
this needs building, with the entity machinery as its model.

#### DR5c — Provenance is displayed, never erased

While drafting, the appendix shows which entries are the author's and which the
LLM proposed. On publication that annotation should normally disappear — a
reader of a standard does not need to see which metrics a model suggested.

**This is a display setting, not a data operation.** The `origin` value on the
artifact (DR2) is permanent and is never cleared, at publish or otherwise.
Publishing hides provenance in the *rendered appendix*; it does not remove
provenance from the *record*.

The distinction is load-bearing: `origin` is what tells downstream consumers
which assertions carry human authority, lets review tooling skip re-verifying
human assertions, and lets later extraction avoid overwriting them. Clearing it
at publish would destroy precisely the value the flag exists to provide, and
unrecoverably — nothing else records that a human rather than a model made the
claim. The implementation is one permanent `origin` column plus a per-render
`show_provenance` option, defaulting on while editing and off once published.

### DR6 — Lifecycles are user-defined state machines; two axes stay separate

Document lifecycles are application- and business-dependent, so the system must
let users **define their own** rather than ship a fixed set. A lifecycle is a
finite state machine with optional conditions gating entry into a state, support
for automatic transitions, and manual transitions by users. Most documents will
have no lifecycle at all.

Deferred — and confirmed to require no change to the current design, which was
the condition for deferring it. The guard that makes this true, and that applies
now: the **editorial** lifecycle is a separate axis from the **processing**
lifecycle in CDM §10.1 (`editing → published → rendered → line_file_generated →
doc-process pipeline`). Both use the word `published` and they are not the same
thing; the editorial publish event *triggers* the processing one. Because they
are two axes, a user-defined FSM can later be added as document metadata plus its
own definition tables, touching neither the processing path nor the AST.

### DR7 — Ontology deferred

Ontology association is a large topic of its own and is deferred. When taken up
it must connect to the existing object model (ADR 2026070101, object-centric
design) rather than introduce a parallel one.

### Alternative Decisions

* **Admit presentation properties into CDM (rejected, DR1).** Would make a
  WYSIWYG editor straightforward and formatting fidelity exact. Rejected: it
  abandons the model's central rule, and the prior in-house tool demonstrates
  the maintenance and generalization cost concretely.
* **A separate annotation store for author assertions (rejected, DR2).** Cleaner
  isolation from extracted data. Rejected: it would fork search, review, and
  provenance into two paths for what is the same kind of knowledge. One store
  with an origin flag keeps every consumer unchanged.
* **Version history inside one document (rejected, DR3).** Conventional, and
  fewer rows. Rejected: it invalidates artifacts, anchors, and renderings on
  every edit, and makes a version hard to cite.
* **Author chunking expressed directly as line ranges (rejected, DR4).** Simpler
  — no resolution step. Rejected: line numbers do not exist while authoring, and
  would break on every edit.

### Database Migrations

None in the current phase. Additive changes recorded for when their features
ship: an `origin` column on artifact tables (DR2, safe default `extracted`); a
version-relation field on `kb.inputs` (DR3); and metric reconciliation tables
modeled on `kb.entity_merge_candidates` / `kb.entity_merges` (DR5b), since no
metric equivalent exists today.

### Data Formats

Chunk artifacts keep the existing `overlap:` / `lines:` line-range format (DR4).

### Environment Variables

None.

## Implementation

Not started. None of these decisions expand the CDM Phase 1 change
(`ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`); DR1, DR3, DR6,
and the CDM-side guards are satisfied by the design as planned. DR2, DR4, DR7
remain deferrals with their constraints recorded. DR5 is resolved in design but
not implemented: the draft-input-row change (DR5a) does touch Phase 1's
`kb.inputs` registration behavior and should land there rather than in a later
phase; metric reconciliation (DR5b) and the appendix renderer (DR5c) are
editor-side work for when the editor itself is built.

### Code Changes

None. Changes in this cycle were confined to specifications.

## Operational Behaviors

- Author-created artifacts flow through the same search, review, and highlight
  paths as extracted ones, distinguished only by `origin` (DR2).
- Each published version being its own document means artifact and search
  results are attributable to an exact version rather than to a mutable
  document (DR3).
- A draft's on-demand extraction runs (DR5) are ordinary doc-processing runs
  triggered manually instead of by the worklist poller; they use the same
  processors, the same line file, and the same artifact tables. Publish is the
  moment a draft's processing status flips from terminal to pending, handing it
  to the worklist for its authoritative run (DR5a).
- `origin` is permanent on every artifact row; only the *rendering* of an
  appendix hides or shows it, controlled by a `show_provenance` flag that
  defaults on in `editing` and off in `published` (DR5c).

## Consequences

- CDM's prohibition on presentation properties is now backed by a concrete
  business case rather than a principle, which makes it defensible when an
  editor feature request pushes against it.
- The editor's most valuable feature — human annotation — requires no new CDM
  machinery beyond an origin flag, because annotations reuse the artifact and
  line-span provenance that already exists.
- Version lineage lives on `kb.inputs`, not in CDM. CDM stays a
  single-document model, which keeps its schema small.
- Deferred items (table/figure/formula lists, index, lifecycles, ontology,
  mandatory formatting standards) are now recorded with their design
  constraints, so taking them up later does not require rediscovering why they
  were deferred.
- Two terminology hazards are documented rather than latent: `published` on two
  lifecycle axes (DR6), and `content_version` versus version lineage (DR3).
- The document → pipeline → document cycle that motivated this ADR's original
  DR5 deferral is closed, not merely avoided: generated appendices are
  render-time projections of artifacts that already exist, never stored blocks,
  so there is no path back into the AST for the pipeline to re-consume (DR5).
- Metrics now need a human/LLM reconciliation path that does not exist yet
  (DR5b) — this is new scope, not covered by Phase 1, and should be planned
  alongside the editor rather than assumed to fall out of existing entity
  reconciliation machinery.
- The draft-input-row correction (DR5a) means CDM's `kb.inputs` registration
  behavior is state-dependent (`editing` vs. `published`) rather than a single
  write at publish time, which is a materially different (and slightly larger)
  implementation than ADR 2026072501 DR13 originally described.

## Tests

No tests — specification-only. When the corresponding features are implemented,
the decisions here imply: an origin-defaulting test on artifact tables (DR2); a
test that an author annotation resolves to the same `source_line_spans` shape as
an extracted artifact (DR2); a semantic-to-physical chunk resolution test
(DR4); a test that version relations survive independent reprocessing of each
version (DR3); a test that a draft's `kb.inputs` row is invisible to both
worklists while `editing`, and that publish makes it visible to exactly the
doc-processing one (DR5a); a reconciliation test asserting a human-marked metric
survives an extractor run unchanged in value but merged in coverage (DR5b); and
a rendering test asserting `origin` is unchanged by publish while the rendered
appendix's displayed provenance differs before and after (DR5c).

## Documentation Impact

*What knowledge changed:* the editor's formatting requirements were reconciled
with CDM's prohibition on presentation properties; author annotations were
established as ordinary artifacts with an origin flag; document versioning was
defined as document-to-document lineage rather than in-document history; author
chunking was given a semantic/physical split; and generated appendices were
resolved as author-triggered, reconciled, render-time projections — closing the
document → pipeline → document cycle that the original review had only
flagged. That resolution required correcting the draft lifecycle: drafts keep a
`kb.inputs` row from creation, not from publish.

*Which docs were updated:* `2026072501-spec-canonical-doc-model` — new §5.5
(Templates Carry Formatting Requirements), §10.2 (Chunking), §10.3 (Author
Annotations Are Artifacts), §10.4 (Document Versions Are Documents), §10.5 /
§10.5.1 / §10.5.2 (author-triggered extraction, reconciliation, provenance
display); §10.1 corrected for the draft input row; §5.5–§5.7 renumbered and
cross-references corrected; §14 and §16 updated. `2026072502-spec-cdm-editor` —
new Design Decisions section D1–D7, typos fixed, references extended. ADR
2026072501 DR13 carries an amendment banner pointing here. ChenWeb change
`cdm-phase1-ast-and-typst-renderer/design.md` updated for the corrected draft
behavior.

*Which docs are now stale:* none identified.

*What was intentionally left undocumented:* the FSM definition schema for
user-defined lifecycles (DR6); the ontology model (DR7); the numbering authority
for the still-deferred figure/table/formula lists and index (DR5); the concrete
chunk-group field name on `Block`, deferred to the Phase 2 chunking work (DR4);
the retention plan model, not contested by the review; and the metric
reconciliation schema itself (DR5b) — only the requirement and its model
(existing entity reconciliation) are recorded, not a table design.

## References
- Spec: `doc-repo/specs/202607/2026072502-spec-cdm-editor.md` (the reviewed proposal)
- Spec: `doc-repo/specs/202607/2026072501-spec-canonical-doc-model.md` §5.5, §10.2–§10.4
- ADR 2026072501 (CDM v1.0 schema decisions) — DR6 on `figure`, DR11–DR14
- ADR 2026072601 (CDM anchored rendering)
- ADR 2026070101 (object-centric design) — the object model ontology must connect to
- ADR 2026061801 (document review) — the reviewers referenced by the editor spec
- Existing origin-column convention: `ChenWeb/project_migrations/20260722000003_create_kb_images.sql`
- Chunk artifact example: `~/Apps/SemOS/Artifacts/0/434/test_doc_244_mineru.chunks`
