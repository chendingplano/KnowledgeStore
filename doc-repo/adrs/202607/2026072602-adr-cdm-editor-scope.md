# ADR 2026072602 — CDM Editor Scope and Its Impact on the Canonical Document Model

**Date:** 2026-07-26 \
**Status:** Accepted (design only — not yet implemented), **except DR5d, which
is Implemented, and DR13, which is Proposed pending confirmation** \
**Component:** CDM Editor, Canonical Document Model, artifact provenance, chunking, document versioning \
**Authors**: Chen Ding \
**Tags**: SemOS, CDM, editor, artifacts, chunking, versioning, templates, lifecycle, block-identity, search, access-control, concurrency

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
* 2026/07/26, second review of the editor spec. The first review had left the
  spec's feature sections unrevised, so several contradicted their own
  decisions, and nine features had no decision at all. Adds **DR5d** (Typst
  generates the TOC and the lists of figures/tables/formulas — amending DR5,
  which had deferred them) and **DR8–DR17**. The editor spec was restructured
  into document management vs. editor tools, renumbered with a phasing section
  and open questions, and "Knowledge Markdown" renamed to "Semantic
  Annotation". CDM spec §16.1 corrected: the display lists no longer require a
  numbering authority, only cross-document citation does.
* 2026/07/26, DR5d implemented (`cdm-phase1-ast-and-typst-renderer` task group
  10): tables wrapped in `#figure(...)`; TOC and figure/table/formula lists
  emitted via `#outline(...)`; heading and equation numbering added as a new
  renderer constant rather than in `theme.typ`, after confirming against the
  real compiler that a `#set` rule inside an imported module has no effect on
  the importing document. Also fixes a pre-existing bug found in the process:
  headings were rendering as literal `= Heading Text`, never as real Typst
  heading elements, because every block's `#mark(id, "start")` prefix broke
  Typst's line-position-sensitive `=` heading syntax — invisible to both
  existing tests, which asserted only the raw source string or only that
  compilation succeeds. Fixed via the `#heading(level: N)[...]` function form.
  Status upgraded to Implemented for DR5d only.

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

**A second review on the same day** re-read the editor spec after those
decisions were written into it, and found two further classes of problem. The
spec's feature sections had not been revised alongside its new Design Decisions,
so several features still contradicted the decisions taken about them. And nine
features had drawn no decision at all in the first pass — document reviewers on
drafts, search, deletion, access control, concurrency, configurable
vocabularies, the editing surface itself, and the handling of LLM-generated
content and block identity. DR5d and DR8–DR17 record that second set. One of
them, DR5d, reverses a first-review deferral outright.

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

> **Amended 2026/07/26 by DR5d.** The first paragraph below deferred the table
> of contents and the lists of figures, tables, and formulas on the grounds that
> they need a numbering authority. That was wrong: they need *layout*
> numbering, which Typst already performs. Only the **index** remains deferred.
> DR5d supersedes this paragraph.

~~Table of contents, list of figures/tables/formulas, and index remain deferred:
several require numbered, referenceable figures and tables, which CDM v1.0
deliberately omits (ADR 2026072501 DR6 folded `figure` into `image`). The
requirement is recorded rather than dropped, so the numbering authority can be
designed when it is actually needed.~~

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

---

The decisions below were taken by the **second review** of 2026/07/26. DR5d
amends DR5; DR8–DR17 cover features the first review left without a decision.
They correspond to D5a and D8–D17 in the editor spec.

### DR5d — Typst generates the TOC and the lists of figures, tables, and formulas

The table of contents and the lists of figures, tables, and formulas are
produced by the **Typst renderer at render time**, the way Microsoft Word builds
a table of contents from heading styles. They are never stored in the document.

```typst
#outline(title: [Contents])
#outline(target: figure.where(kind: image),        title: [List of Figures])
#outline(target: figure.where(kind: table),        title: [List of Tables])
#outline(target: math.equation.where(block: true), title: [List of Formulas])
```

Typst is the right owner on both counts that matter. Numbering and ordering are
layout facts, and Typst is the component that knows them. Placement, title, and
depth are formatting choices, which DR1 assigns to the template.

This corrects DR5's original reasoning, which conflated two different needs.
*Displaying* a list of tables needs numbers that exist at layout time — Typst
supplies them. *Citing* "Table 3" from an artifact or from another document
needs a stable number carried in the AST, which is the numbering authority CDM
§16.1 defers. Only the second is still deferred.

The **index** remains deferred regardless: it requires authored index terms —
an inline node type CDM does not have — plus a Typst indexing package.

Two renderer changes are prerequisites, and neither is satisfied by the Phase 1
implementation as built:

1. Tables must be emitted inside `#figure(kind: table, caption: …)`. The
   renderer currently emits a bare `#table(...)`
   (`server/api/cdm/rendering/typst.go:186`), and only figures appear in
   `#outline(target: figure…)`. Images are already wrapped correctly
   (`typst.go:115`).
2. `Block.caption` must be permitted on `table`, not only on `image`. The field
   already exists on the single `Block` struct, so this is a spec and validator
   change with no migration.

Equation numbering is a template setting
(`#set math.equation(numbering: "(1)")`), consistent with DR1.

### DR8 — Published documents are read-only; the first edit after publish opens a new version

A document is read-write in any non-frozen state and read-only once frozen
(`published` by default, DR6). Saves before publication increment
`content_version` in place. The **first** modification after publication creates
a new document per DR3, related by `amendment` (default), `addendum`, or
`replace`. Subsequent modifications of that new document are again in-place
until it is published in turn. The lineage therefore grows once per
publish-then-edit cycle, not once per save.

This resolves an ambiguity the editor spec had carried since the first draft —
"each modification generates a new version" — which, read against DR3, meant
every keystroke-save created a document.

More importantly it is what makes DR3 affordable. DR3's justification is that
artifacts, `source_line_spans`, anchors, and renderings all bind to a specific
document. Immutability after publish is what guarantees those bindings can never
be invalidated; the lineage record alone would not. It also bounds block-ID
churn to drafts, which is the property DR9 depends on.

### DR9 — Block identity is preserved across edits and rewrites

CDM §1.1 makes block IDs stable slugs, and `kb.cdm_anchors`,
`kb.cdm_projections.block_ids`, `cross_reference.target.block_id`, and artifact
provenance all bind to them. A block ID is therefore an identity, not a label,
and the editor must treat it as one.

IDs are allocated once at block creation and are immutable for the block's
lifetime within its document; editing content never changes an ID. Generative
tools never emit IDs — they return content for a span of existing blocks, and
the editor maps the result back: a rewritten block keeps its ID, a split yields
one inheriting block plus newly allocated IDs, a merge keeps the first block's
ID. IDs that disappear are recorded as **retired**, so an inbound
`cross_reference` can be reported as broken rather than dangling silently.

The first review missed this entirely, and it is the editor's sharpest
constraint: four features (rewrite, summarize, deep research, chat-to-document)
regenerate whole blocks, and a naive implementation that re-slugs them would
break every anchor and cross-reference pointing at the document.

DR8 is what keeps it tractable. Cross-document references always target
published — hence frozen — documents, so ID churn is confined to drafts and can
never break an external reference.

### DR10 — LLM output is validated into CDM AST and inserted only on acceptance

Every generative tool emits a **CDM block fragment**, not prose, Markdown, or
HTML. The preferred mechanism is a constrained tool-call schema mirroring CDM's
`Block` and `Inline` types, with a Markdown fallback parsed by the Markdown
reader for models that cannot honor it. Every fragment passes the CDM §1.2
validator before insertion; a fragment that fails is surfaced as a rejected
suggestion and nothing invalid is written.

Insertion is a **proposal the author accepts or rejects** in a diff view, never
a direct write. Besides keeping a human in the loop, this is what keeps `origin`
(DR2) honest: the author's acceptance is what makes an assertion human-authored.
Without it, `human-created` would silently come to mean "an LLM wrote it in a
human's editor", destroying the distinction DR2 exists to preserve.

### DR11 — The editing surface is a block editor isomorphic to the CDM AST

The editor's in-memory document model must be isomorphic to the CDM AST, so that
saving is a serialization rather than a conversion. Its schema must mirror CDM
§2 and §3 block and inline types and must **forbid** marks carrying
presentation, which is DR1 enforced at the level of what the editor can even
express.

The concrete component is deliberately left open. A ProseMirror-family
component is the leading candidate, since its node model is already close to
CDM's, but the choice should be made when the editor work starts rather than
now.

### DR12 — Draft reviews are author-triggered runs, keyed to `content_version`

Document reviewers consume artifacts from doc-process runs, and a draft sits off
both worklists (DR5a). A draft review is therefore explicitly requested by the
author and runs the same reviewers, on the same line file, against the same
artifact tables — the shape DR5 established for appendices, applied to the
feature the first review had overlooked.

Review results are keyed to the `content_version` they were produced from.
Results from an older version are displayed as **stale**, never as current. This
matters more for reviews than for appendices: a review finding that silently
refers to deleted text is worse than no finding.

### DR13 — One search index, one corpus, latest version by default

An authored document is indexed **once**, by the standard doc-process pipeline
off its line file, exactly as an uploaded document is. There is no second,
CDM-specific search corpus.

The review found an apparent double-indexing path: CDM §11 gives
`kb.cdm_projections` its own `embedding vector(1536)`, while §10 also routes the
line file through the pipeline's "chunking + embedding". Two indexes over one
document would return duplicate hits for every authored document and would
contradict §10's own headline — two document origins, one processing pipeline.

What CDM's projections contribute is *better text*, not a second index: for an
authored document, a chunk's retrieval text is the CDM projection of the blocks
in that chunk's line range (verbalized tables, equations with variable
descriptions — CDM §8, §9) rather than raw line-file text. Uploaded documents
keep existing behavior.

Because every version is its own document (DR3), search returns the **latest
version in each lineage** by default, with an explicit option to search all
versions. Otherwise a document published five times returns five near-identical
hits.

**This decision changes what `kb.cdm_projections` is for and touches CDM §9 and
§11. It is recorded as proposed, pending confirmation, unlike the rest of this
ADR.**

### DR14 — Deletion checks lineage and inbound references

Soft delete is the default. Hard delete removes the `kb.inputs` row and cascades
to all derived artifacts through the existing input-deletion path
(ADR 2026072301); CDM's `ON DELETE CASCADE` from `kb.cdm_documents` covers
blocks, renderings, projections, and anchors, so no CDM-specific deletion path is
needed.

Two referential hazards are reported before a hard delete, and require explicit
acknowledgement: the document may be a link in a version lineage (DR3), and
other documents may hold `cross_reference`s to its `document_key`. Deleting a
middle version leaves its successor's relation pointing at a missing document,
so that relation is marked dangling rather than silently rewritten — rewriting
would fabricate a lineage that never existed.

Hard-deleting a published document requires elevated privilege (DR15), since
published documents are immutable and citable by design.

### DR15 — Access control follows the existing role model

Editor actions map onto the roles in ADR 2026072001 / 2026072002 (Kratos).
These are distinct permissions, not one "edit" right: read; edit a draft;
publish; perform a lifecycle transition; manage templates; hard delete;
force-unlock (DR16).

Publish and template authoring are privileged. A Typst template is executable
code compiled server-side, so template compilation runs sandboxed — no
filesystem or network access, with CPU, memory, and wall-clock limits. This
follows from DR1 rather than being incidental: making formatting rules into data
means users author that data, and the data is a program.

Every editor query is tenant-scoped. Documents inherit `tenant_id` and
`ks_store_id` from their `kb.inputs` row, which is why CDM needs no tenant
prefix on `document_key`.

### DR16 — Concurrency control: backend section locks, deferred

The intended model, recorded as an early sketch:

1. During initial drafting, before a `kb.inputs` row exists, there is no
   concurrency control.
2. Editing takes a lock on the **immediate section**, managed in the backend. On
   failure the user is told who holds the lock and since when, and is offered
   the option to wait.
3. A granted lock records holder and acquisition time.
4. Saving releases the lock; the first user in the waiting list is notified.
5. A user may also lock the **entire document**, explicitly requested.
6. An administrator may force-unlock. Consequently **the save path must re-check
   lock ownership at save time** and tell the user if the lock was taken away.

Full design deferred. One guard applies now: point 6 makes save an
optimistic-concurrency operation rather than a blind write. The save API should
carry the expected `content_version` and lock token and reject a stale save from
the outset. Building that in now is cheap; retrofitting it means revisiting
every client, every autosave path, and every generative tool's insertion path
(DR10), all of which write through the same endpoint.

### DR17 — Vocabularies are configuration, not code

The annotation types (DR2) and the lifecycle state set (DR6) are both
**indicative examples**, not fixed vocabularies. Different deployments, tenants,
and users need different sets, so both are configuration.

They follow the resolution order already used for template fallback (CDM §5.3) —
system → tenant → user, most specific wins — and reuse the existing
configurable-menu and label-i18n mechanisms (ADR 2026071601, ADR 2026071602)
rather than introducing a third configuration pattern. All user-visible labels
are localized through that mechanism.

One clarification this forced, recorded in the editor spec §3.2: the
author-facing annotation list mixes two kinds of thing. Most entries produce
artifacts (DR2), but `reference` and `quotation` correspond to CDM **block
types** (`reference`, `quote` — CDM §3, §7), so marking a span as one of those
changes the AST instead of emitting an artifact row. The configuration records
which kind each entry is.

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
* **Storing the TOC and lists as blocks in the document (rejected, DR5d).**
  Would make them visible while editing. Rejected: they would go stale on every
  edit, and they would re-enter the pipeline as authored prose — the same cycle
  DR5 closes for appendices.
* **Every save creates a new version (rejected, DR8).** The literal reading of
  the original spec text. Rejected: it would create a document per keystroke-save
  and a lineage nobody could read.
* **Mutable published documents (rejected, DR8).** Conventional. Rejected: it
  reintroduces exactly the invalidation problem DR3 was adopted to avoid, since
  artifacts, anchors, and renderings bind to a specific document.
* **Regenerating block IDs on rewrite (rejected, DR9).** Simplest to implement —
  the LLM returns new content, the editor re-slugs it. Rejected: it silently
  breaks every anchor, projection, and cross-reference bound to the old IDs, and
  the breakage is invisible until someone follows a link.
* **Letting generative tools write directly into the document (rejected,
  DR10).** Fewer clicks. Rejected: it makes `origin = 'human-created'` mean "an
  LLM wrote it in a human's editor", which destroys the flag's value (DR2), and
  it admits AST-invalid content.
* **A Markdown-source editing surface (rejected, DR11).** Familiar and simple.
  Rejected: Markdown cannot express semantic blocks, reliable tables, or the
  equation AST — the model's whole point.
* **A WYSIWYG-over-HTML editing surface (rejected, DR11).** What users expect.
  Rejected: it leaks presentation into the document, which is DR1's failure mode
  and the prior in-house tool's.
* **Searching CDM projections as a second corpus (rejected, DR13).** Would use
  the better projected text directly. Rejected: two indexes over one document
  return duplicate hits and contradict CDM §10's single-pipeline claim. Feeding
  projection text into the one pipeline index gets the same benefit.
* **Cascade-deleting a version's whole lineage (rejected, DR14).** Tidy.
  Rejected: each version is independently citable (DR3), so deleting one must
  not destroy the others.

### Database Migrations

None in the current phase. Additive changes recorded for when their features
ship: an `origin` column on artifact tables (DR2, safe default `extracted`); a
version-relation field on `kb.inputs` (DR3); metric reconciliation tables
modeled on `kb.entity_merge_candidates` / `kb.entity_merges` (DR5b), since no
metric equivalent exists today; a retired-block-ID record per document (DR9);
lock tables for section and document locks when concurrency control is taken up
(DR16); and lifecycle-definition and vocabulary-configuration tables (DR6,
DR17).

### Data Formats

Chunk artifacts keep the existing `overlap:` / `lines:` line-range format (DR4).

Generative tools exchange CDM block fragments conforming to the §1.2 validator,
not prose, Markdown, or HTML (DR10).

### Environment Variables

None.

## Implementation

Not started, except DR5d (below), which is implemented. None of these
decisions expand the CDM Phase 1 change
(`ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`); DR1, DR3, DR6,
and the CDM-side guards are satisfied by the design as planned. DR2, DR4, DR7
remain deferrals with their constraints recorded. DR5 is resolved in design but
not implemented: the draft-input-row change (DR5a) does touch Phase 1's
`kb.inputs` registration behavior and should land there rather than in a later
phase; metric reconciliation (DR5b) and the appendix renderer (DR5c) are
editor-side work for when the editor itself is built.

**DR5d was the one exception, and it has since been implemented as a Phase 1
follow-up** (`ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`,
task group 10). What was actually built differs from the plan in two ways
worth recording, both found by testing against the real Typst compiler rather
than assumed:

1. Tables are wrapped in `#figure(...)` in
   `server/api/cdm/rendering/typst.go` (`renderTable`), carrying `Block.Caption`
   as the figure caption when present and omitting it otherwise — a captionless
   table is still numbered and listed, matching Word's behavior. `Block.Caption`
   needed no validator change: `validate.go` already validated it unconditionally
   regardless of block type, so only its doc comment needed widening from
   image-only to image-and-table.
2. **The numbering set rules do not live in `theme.typ`, as originally
   planned — they cannot.** Verified with a minimal repro: a `#set` rule
   executed inside an imported module has no effect on the importing document,
   even wrapped in a called function, because `#set` only affects the remainder
   of the scope it is textually written in and `#import` carries bindings, not
   styling context. `#set heading(numbering: "1.1")` and
   `#show math.equation.where(block: true): set math.equation(numbering: "(1)")`
   are instead a new renderer constant (`numberingTypst`, `anchors.go`), emitted
   directly in `RenderDocument` alongside the pre-existing `pageSetupTypst` — the
   same constraint that already put page geometry there rather than in the
   theme. The TOC and the three lists (`outlinesTypst`) are emitted the same
   way, immediately after the title, which is itself emitted via
   `#heading(numbering: none, outlined: false)[...]` so it is excluded from both
   numbering and the Contents outline.

**A third, unplanned fix was required and is folded into the same change: a
pre-existing Phase 1 bug that made DR5d's TOC impossible.** Every block is
prefixed with `#mark(id, "start")` on the same source line as its own content,
and Typst's `= ...` heading sugar only parses as a heading when it is the first
token on its line. Every heading in every already-shipped CDM document was
therefore rendering as literal `= Heading Text` — visually broken, and
returning zero `query(heading)` matches, so numbering and outline
participation were silently broken for every heading in production. Neither
existing test caught it, because both asserted at the wrong level: one checked
only the raw source string (true whether or not Typst parses it as a heading),
the other checked only that compilation succeeds (a literal `=== Sub` compiles
fine as body text). Confirmed via direct `typst compile`/`typst query` against
the previously-committed golden file before writing any fix. The fix — render
headings via `#heading(level: N)[...]` instead of `= ...` sugar, which has no
line-position sensitivity — is a one-case change in `renderBlock`'s heading
branch.

Verified end to end: `go build`/`go vet` clean for both the `cdm` package and
the whole `server` tree; both golden fixtures regenerated and reviewed;
`go test ./server/api/cdm/...` passes, including three new tests
(`outline_test.go`) that compile with the real `typst` binary and query the
compiled structure — the standard this package already held itself to — one of
which is the direct regression guard for the heading fix. Both fixtures were
also compiled to PNG and inspected visually to confirm the Contents/List of
Figures/Tables/Formulas render as intended.

The remaining second-review decisions are editor-side work with no Phase 1
impact, except DR16's save-path guard, which should be honored by whatever
builds the first save endpoint.

### Code Changes

DR5d implemented in `ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`
task group 10 (2026/07/26): `server/api/cdm/rendering/typst.go` (table→figure
wrapping; heading rendering fixed to `#heading(level: N)[...]`; title emission
excludes numbering/outline), `server/api/cdm/rendering/anchors.go`
(`numberingTypst`, `outlinesTypst` constants), `server/api/cdm/model/types.go`
(`Block.Caption` doc comment widened to table), plus test and golden-fixture
updates. No other change in this cycle; everything else was confined to
specifications.

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
- A published document cannot be edited. Editing one opens a new document, and
  the reader-visible effect is that a URL or citation to a published version
  always resolves to identical content (DR8).
- The TOC and the lists of figures, tables, and formulas appear only in rendered
  output, never in the editing surface, because Typst produces them at render
  time (DR5d).
- Generative tool output arrives as a diff the author accepts or rejects, never
  as a direct edit (DR10).
- Search returns one hit per document lineage by default, not one per published
  version (DR13).

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

From the second review:

- Immutability after publish (DR8) turns DR3 from a bookkeeping convention into
  a guarantee: bindings from artifacts, anchors, and renderings to a document
  can never be invalidated, because the document can never change.
- That same property is what makes block-ID stability (DR9) tractable rather
  than a distributed-identity problem — churn is confined to drafts, and no
  external reference can be broken by it.
- The editor now has a hard constraint the first review missed: four generative
  features regenerate whole blocks, and block IDs are load-bearing identity.
  Every one of those features must be built on the ID-preserving mapping in DR9,
  which is a real implementation cost that was previously invisible.
- DR5d removes a deferral rather than adding one — three of the five
  auto-generated content items turn out to be free, because Typst already does
  the work. It also narrows CDM §16.1 from "required by the editor's lists" to
  "required for cross-document citation", which is a smaller and later need.
- Phase 1's renderer is now known to be incomplete for DR5d. This is the first
  case where an editor decision has produced rework in already-implemented CDM
  code, and it is small only because the missing piece is `#figure` wrapping
  rather than a schema change.
- DR13 is recorded as **proposed, not accepted**: it changes what
  `kb.cdm_projections` is for, and the rest of this ADR should not be read as
  carrying it.
- Deferring concurrency control (DR16) is safe only if the save endpoint is
  built as an optimistic-concurrency operation from the start. That is a
  constraint on Phase 1-adjacent work, not on the deferred design.

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

From the second review: a golden-file test asserting the rendered TOC and lists
of figures/tables/formulas are **non-empty**, since an empty `#outline` compiles
cleanly and would otherwise pass silently (DR5d); a test that saving a published
document is rejected and that the new-version action produces a second document
with the expected relation (DR8); a test that a rewrite spanning several blocks
preserves each block's ID, and that a merge retires the absorbed IDs rather than
dropping them (DR9); a validator test that a malformed LLM fragment is rejected
before insertion (DR10); a test that a review result from an older
`content_version` is reported stale (DR12); a search test asserting one hit per
lineage by default and n hits with all-versions enabled (DR13); a deletion test
asserting lineage and inbound-reference hazards are reported before a hard
delete (DR14); and a save test asserting a stale `content_version` or a revoked
lock token is rejected (DR16).

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

### Second review, 2026/07/26

*What knowledge changed:* the editor's auto-generated content split into three
groups with different owners — Typst at render time, author-triggered
extraction, and still-deferred — which removed a deferral rather than adding
one; versioning gained the rule that decides *when* a version is created
(read-write until published, read-only after); block IDs were established as
identity that must survive generative rewrites; LLM output was constrained to
validated CDM fragments inserted only on author acceptance; and the apparent
double-indexing of authored documents was resolved to a single corpus. Nine
features that previously had no decision — reviewers on drafts, search, delete,
access control, concurrency, vocabularies, the editing surface — now have one.

*Which docs were updated:* `2026072502-spec-cdm-editor` — restructured into
document management (§2) and editor tools (§3), Design Decisions extended with
D5a–D5c and D8–D17, new §5 phasing table and §6 open questions, header metadata
added, "Knowledge Markdown" renamed to "Semantic Annotation", references
extended from 4 to 10. This ADR — DR5d and DR8–DR17, with DR5 marked amended.
`2026072501-spec-canonical-doc-model` — §16.1 corrected.

*Which docs are now stale:* `ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`
is complete and its renderer does not satisfy DR5d. The change is not reopened;
the gap is carried as implementation tasks in this ADR's Implementation section
instead.

*What was intentionally left undocumented:* the editing component choice
(DR11) and the block-level AST diff behind change summaries, both left as open
questions in the editor spec §6; the retired-block-ID store's shape (DR9); the
lock table design (DR16); and the vocabulary configuration schema (DR17), which
should follow ADR 2026071601's existing pattern rather than be designed afresh.

## References
- Spec: `doc-repo/specs/202607/2026072502-spec-cdm-editor.md` (the reviewed proposal)
- Spec: `doc-repo/specs/202607/2026072501-spec-canonical-doc-model.md` §5.5, §10.2–§10.4
- ADR 2026072501 (CDM v1.0 schema decisions) — DR6 on `figure`, DR11–DR14
- ADR 2026072601 (CDM anchored rendering)
- ADR 2026070101 (object-centric design) — the object model ontology must connect to
- ADR 2026061801 (document review) — the reviewers referenced by the editor spec
- ADR 2026072301 (kb input and artifact deletion) — the deletion path DR14 reuses
- ADR 2026072001 / 2026072002 (user roles in Kratos, user management) — the role
  model DR15 maps onto
- ADR 2026071601 / 2026071602 (configurable knowledge menus, menu label i18n) —
  the configuration and localization pattern DR17 reuses
- Renderer to change for DR5d: `ChenWeb/server/api/cdm/rendering/typst.go`
  (`renderTable`, line 186; `renderBlock` image case, line 115)
- Existing origin-column convention: `ChenWeb/project_migrations/20260722000003_create_kb_images.sql`
- Chunk artifact example: `~/Apps/SemOS/Artifacts/0/434/test_doc_244_mineru.chunks`
