# Spec: CDM Editor

- **DocID:** `doc-2026072502`
- **Status:** Proposed — all Design Decisions recorded in ADR 2026072602 [3].
  D1–D7 map to DR1–DR7 (first review), D5a to DR5d, and D8–D17 to DR8–DR17
  (second review). **D13 is Proposed pending confirmation**; every other
  decision is Accepted. **D5a is implemented** (2026/07/26). **The editor MVP
  is implemented** (2026/07/27, ADR 2026072603, `cdm-editor-mvp`): CDM HTTP API
  and editor UI for §2.2, §3.1, the non-frozen half of §2.3, and preview
  including D5a's outlines — see §5 for exactly what shipped and what did not
  (versioning §2.5, delete §2.6, and templates §2.8 remain unbuilt).
- **Date:** 2026-07-25 (revised 2026-07-26, 2026-07-27)
- **Component:** SemOS / ChenWeb — Canonical Document Model, authoring, artifacts
- **Authors:** Chen Ding
- **Tags:** SemOS, CDM, editor, authoring, artifacts, versioning, templates,
  lifecycle, concurrency

# 1. Overview

CDM (Canonical Document Model, refer to [1]) Editor is a browser-based editor
that lets users create and edit CDM documents.

CDM Editor is not just another rich-text editor in the manner of Google Docs or
Microsoft Word. It is a Knowledge Editor — an editor for AI.

The difference is concrete rather than rhetorical. A conventional editor stores
what a document should *look like*. The CDM Editor stores what a document
*means*, and lets Typst templates decide appearance (§4, D1). Everything the
editor produces — blocks, annotations, chunk declarations — is consumed by the
same pipeline, search, and review tooling that already serves uploaded
documents.

This document specifies the editor's features (§2, §3), the design decisions
that reconcile them with CDM (§4), the order in which they can be built (§5),
and what remains open (§6).

# 2. Document Management

These are document-level operations. They are not editing tools, and are
reachable from outside the editing surface.

## 2.1 Search Documents

Search is a tool usable in any context:

- search while editing
- search relevant documents before creating a new one
- search documents to archive

It provides multi-dimensional searching capabilities:

- Search by metadata, such as title, authors, creation time, read time,
  modify time, etc.
- Search by semantic objects, such as `concept`, `terminology`, `definition`,
  `ontology`, `canonical object`, etc.
- Search document history
- Hybrid search: BM25 + semantic similarity

Authored and uploaded documents are searched through **one** index, not two
(D13). Search by semantic object depends on artifact types that do not exist
yet, and is therefore sequenced accordingly (§5).

## 2.2 Create New Documents

This should be implemented as a function. There will be multiple places
that we may allow users to create new documents.

Creating a document allocates a `document_key` (CDM §1.1, unique and stable) and
writes a `kb.inputs` row immediately, in the draft form described in CDM §10.1 —
`parse_state = 'parsed_success'`, `pipeline_state = 'success'` — so the draft is
invisible to both worklists but has somewhere to attach author-triggered
artifacts. Tenant and store scoping (`tenant_id`, `ks_store_id`) are inherited
from that row.

## 2.3 Modify Documents and Versioning

A document is **read-write until it is published, and read-only afterwards**
(D8). This single rule determines when versions are created:

- While a document is in a non-frozen state, each save increments
  `content_version` in place. No new document is created.
- Publishing freezes the document. It can no longer be modified.
- The **first** modification of a frozen document creates a **new document**
  (D3), related to it by `amendment`, `addendum`, or `replace`, in the `editing`
  state.
- Subsequent modifications of that new document are ordinary in-place saves
  until it, too, is published.

So the version lineage grows once per publish-then-edit cycle, not once per
save.

Each save may also generate a summary of what changed. This requires a
block-level diff over the AST, which is not yet designed (§6).

## 2.4 Document Lifecycles

A document is a living object. A typical lifecycle might have:

```text
proposal
proposal-approved
drafting
draft-review
open-for-comments
comment-review
draft-approved
published
implemented
revision-proposal
revision-proposal-review
revision-proposal-approved
revision-drafting
revision-review
revision-approved
revision-published
document-pre-abolish
document-abolished
```

**This list is indicative, not normative.** Lifecycles are
application- and business-dependent, so they are user-defined state machines and
the set of states is configuration (D6, D17). Not all documents go through all
states, and in reality most documents have no lifecycle at all.

A lifecycle definition designates which of its states are **frozen**
(read-only). `published` is frozen by default; that is what §2.3 relies on.

## 2.5 Version Management

This tool lets users view document history and versions. Because each version is
its own document (D3), history is a traversal of the lineage relation on
`kb.inputs`, and any version can be opened, cited, and searched independently.

## 2.6 Delete Documents

Documents are by default never hard deleted, but users do have the option
to hard delete them.

When deleting a document, it is very important to delete not only the
document but also all its derived data and artifacts. This follows the existing
input-deletion path (ADR 2026072301 [5]) rather than a CDM-specific one.

Hard deletion is guarded against two referential hazards (D14): the document may
be a link in a version lineage, and other documents may hold
`cross_reference`s to it by `document_key`.

## 2.7 Retention

Documents may be associated with a retention plan. Expired documents
are archived first, and may eventually be hard removed from the system.

Retention plans are not yet modeled (CDM §16.12) and are deferred.

## 2.8 Template Management

Let users create, modify, delete and manage Typst templates, and associate them
with a `rendering_type` (CDM §5.4). Resolution order — explicit template,
`rendering_type` association, then fallback at user → tenant → system
specificity — is defined by CDM §5.3 and §5.4 and is not restated here.

A Typst template is executable code compiled server-side. Template authoring is
therefore a privileged action and compilation is sandboxed (D15).

# 3. Editor Tools

The editing surface is made of tools.

## 3.1 Text Edit Tool

A rich-text editing surface, but a **semantic** one. Its toolbar exposes
heading, emphasis, strong, list, table, code, quote, link, equation, image,
callout, and definition — not font, size, color, or alignment. Appearance is
decided by the Typst template (D1).

## 3.2 Semantic Annotation

*Previously called "Knowledge Markdown"; renamed because it is not Markdown and
the old name collided with CDM's Markdown renderer (§5.6) and Markdown
projection (§9.3). ADR 2026072602 uses the old name.*

Users can highlight a piece of text and annotate it as a semantic object, such
as `terminology`, `concept`, `definition`, `reference`, `quotation`, `entity`,
`relation`, `canonical object`, etc.

Two things about this list:

1. **It is indicative and configurable** (D17). Different deployments, tenants,
   and users may have different sets.
2. **Not all entries are the same kind of thing.** Most produce *artifacts*
   (D2). But `reference` and `quotation` correspond to CDM **block types**
   (`reference`, `quote` — CDM §3, §7), so marking a span as one of those
   changes the AST rather than emitting an artifact row. The editor offers both
   gestures; the configuration records which kind each entry is.

## 3.3 Document Reviewers

A rich set of document reviewers implemented in [2].

Reviewers consume artifacts from doc-process runs, and a draft sits off both
worklists (CDM §10.1). Reviewing a draft is therefore an explicitly
author-triggered run, on the same terms as *Generate Appendix* (D12).

## 3.4 Summarization Tool

Summarize a section, a block of text, the entire document, etc.

## 3.5 Extraction Tool

Extract keywords from the entire document, from a chapter/section, or from a
block of selected text.

## 3.6 Rewrite a Chapter/Section, or a Selected Block

Users can specify how to rewrite:

- using a skill,
- select a stored prompt,
- write specific instructions, etc.

## 3.7 Inline Search

Highlight a block of text, or type something, then search the knowledge base
for relevant content.

## 3.8 Ontology

A document may be associated with one or more ontology objects. Users can
create new ontology objects, search ontology objects, modify or delete them.

Deferred (D7).

## 3.9 Chunking

It lets authors do the chunking. If no chunking is done, the system will
do the chunking automatically in the doc processing pipeline. Authors declare
chunk boundaries semantically; the pipeline resolves them to line ranges (D4).

## 3.10 Auto-Generated Content

Two mechanisms, with different owners (D5):

**Generated by Typst at render time** — the document does not store them, and
the author does nothing but place them:

- Table of Contents
- List of Figures
- List of Tables
- List of Formulas

**Generated by author-triggered extraction, rendered as projections:**

- Appendix of Metrics
- Appendix of Topics
- Appendix of other artifact types, as needed

**Deferred:**

- Index — requires index terms in the AST, which CDM does not have (§6).

## 3.11 Deep Research

AI-assisted deep research tool.

## 3.12 Chat-to-Document

It creates documents by chatting with LLMs.

**Note on §3.4–§3.7 and §3.11–§3.12.** All of these are generative tools whose
output must become valid CDM AST and must not disturb block identity. Those two
constraints are D9 and D10 and apply to every tool in this group.

# 4. Design Decisions

D1–D7 were resolved while reviewing this proposal against the CDM specification
[1]. D5a and D8–D17 were resolved by a second review the same day, which found
that the feature sections above had not been revised alongside D1–D7 and that
nine features had drawn no decision at all.

All are recorded in ADR 2026072602 [3], which numbers them DR1–DR7, DR5d, and
DR8–DR17 respectively, together with the alternatives rejected for each.

## D1 — Formatting lives in Typst templates, not in the document

The Text Edit Tool's formatting controls (font, size, color, alignment) must not
write presentation properties into the canonical document. CDM stores meaning;
Typst templates carry appearance (CDM §5.5).

This is what makes mandatory formatting standards tractable. A prior in-house
online editor built to satisfy China's mandatory standard for formatting
national standards worked, but became extremely difficult to maintain and could
not be generalized to other customers — because the formatting rules were welded
into the editor instead of being a separable artifact. Under CDM a second
standard is a second template.

The editing surface should therefore expose **semantic** actions — heading,
emphasis, list, table, callout, definition — and let the template decide how each
one looks. Full support for a specific mandatory standard is deferred until CDM
and this editor are mature.

## D2 — Semantic annotations produce ordinary artifacts

Author annotations (`terminology`, `concept`, `definition`, `entity`,
`relation`, `canonical object`) are artifacts in exactly the same sense as those
a doc processor extracts, stored in the same tables and consumed by the same
tooling. They are simply much cheaper and much more accurate, because a human
asserted them.

Every artifact records an origin, defaulting to `extracted`, with
`human-created` for author assertions — following the existing
`kb.images.origin` convention. Artifact types that do not yet exist
(`terminology`, `concept`, `definition`) are planned as ordinary doc processors
with ordinary tables. **No new artifact types are added in the current phase.**
See CDM §10.3.

The set of annotation types is configuration, not code (D17), and some entries
in the author-facing list are block types rather than artifact types (§3.2).

## D3 — A new version is a new document

Each version is a separate document with its own `kb.inputs` row, processed
independently. Versions are linked by a typed relation recorded on the input row
(a dedicated column or within `kb.inputs.doc_metadata`): `addendum`,
`amendment`, `replace`.

This keeps every version independently addressable and citable, which matters
because artifacts, line spans, anchors, and renderings all bind to a specific
document. Distinguish this from `content_version`, which is the within-document
edit counter. See CDM §10.4.

When a version is created is decided by D8.

## D4 — Authors declare chunks semantically; the pipeline resolves them physically

Chunking is an artifact generated after the line file, as line ranges with
overlaps. Authors may declare chunk groups on blocks at the semantic level;
these resolve to line ranges once the line file exists. Absent any declaration,
the pipeline chunks automatically, as it does for uploaded documents. Overlap
remains the chunker's concern. See CDM §10.2.

## D5 — Typst generates document furniture; artifact appendices are author-triggered projections

The original review deferred all auto-generated content. That was too coarse.
The list splits into three groups with genuinely different answers.

### D5a — Typst generates the TOC and the lists of figures, tables, and formulas

Table of contents, list of figures, list of tables, and list of formulas are
produced by the **Typst renderer at render time**, exactly the way Microsoft
Word builds a table of contents from heading styles. They are never stored in
the document.

```typst
#outline(title: [Contents])
#outline(target: figure.where(kind: image),           title: [List of Figures])
#outline(target: figure.where(kind: table),           title: [List of Tables])
#outline(target: math.equation.where(block: true),    title: [List of Formulas])
```

This is the right owner for two reasons. Numbering and ordering are layout
facts, and Typst is the component that knows them. And placement, titling, and
depth are formatting choices, which D1 says belong to the template.

Two concrete consequences for the CDM renderer, both cheap and both required
before this works:

1. **Tables must be emitted inside `#figure(kind: table, caption: …)`**, not as
   a bare `#table(...)`. Only figures appear in `#outline(target: figure…)`.
2. **`Block.caption` must be permitted on `table`**, not only on `image`. The
   field already exists on the single `Block` struct (CDM §5.2), so this is a
   documentation and validator change with no migration.

Note what this does **not** resolve. Typst numbering is a *rendering* fact. CDM
§16.1's deferred item — a stable, referenceable figure/table number carried in
the AST, so that artifacts and cross-document citations can name "Table 3" —
remains deferred. Displaying the lists needs the former; citing across documents
needs the latter. CDM §16.1 has been narrowed accordingly.

**Implemented 2026/07/26** as a follow-up to CDM Phase 1
(`cdm-phase1-ast-and-typst-renderer` task group 10). Two things were learned in
the building that correct the paragraphs above:

- **The numbering rules cannot live in the Typst template.** Verified against
  the real compiler that a `#set` rule executed inside an imported module has no
  effect on the importing document — `#import` carries bindings, not styling
  context — so `#set heading(numbering: …)` and the block-equation numbering
  `#show` rule are emitted by the renderer itself, alongside the page geometry
  it already emitted for the same reason. This does not weaken D1: the rules are
  still data outside the document, and making them template-overridable is a
  matter of the template exporting values the renderer reads, not of moving the
  `#set` back into the theme.
- **Headings were not rendering as headings at all.** Every block is prefixed
  with an anchor `#mark(...)` call on its own source line, and Typst's `= …`
  heading syntax only parses when it is the first token on its line. Every
  heading in every CDM document was rendering as literal `= Heading Text`, and
  `query(heading)` matched none of them — so the TOC would have been empty no
  matter what else was correct. Fixed by rendering headings through the
  `#heading(level: N)[…]` function form. This was a pre-existing Phase 1 defect
  that D5a happened to expose.

### D5b — Artifact appendices are author-triggered, reconciled, and rendered

Appendix of Metrics, Appendix of Topics, and appendices of other artifact types
as needed are **resolved, not deferred** (ADR 2026072602 DR5, CDM §10.5).

The author invokes *Generate Appendix of Metrics*; the system generates the line
file, chunks it, runs the `extract_metrics` doc processor, reconciles the result
against metrics the author marked by hand, and renders the appendix. Same line
file, same chunking, same processor as after publication — only the trigger
differs.

Three properties keep this from becoming a document → pipeline → document cycle:
the trigger is manual and bounded; a draft sits off both worklists so a run
cannot enqueue further runs; and the appendix is a **render-time projection, not
a stored block**, so nothing it contains can ever be re-extracted as if it were
authored prose.

Where a human and the extractor assert the same thing, they merge and the
**human assertion wins**, keeping `origin = 'human-created'` (CDM §10.5.1).
`origin` is permanent; a per-render `show_provenance` flag defaults on while
editing and off once published (CDM §10.5.2). Metric reconciliation machinery
does not exist yet and must be built, modeled on the existing entity
reconciliation.

### D5c — The index is deferred

An index requires authored index terms — an inline node type CDM does not have —
plus a Typst indexing package. Recorded as a future requirement.

## D6 — Document lifecycles are user-defined state machines, deferred

Lifecycles are application- and business-dependent, so the system must let users
**define their own** rather than shipping a fixed set of states. The list in
§2.4 is one example, not a specification. A lifecycle is a finite state machine
with optional conditions gating entry into a state, support for automatic
transitions, and manual transitions by users. Most documents will have no
lifecycle at all.

A lifecycle definition marks one or more states as **frozen**, which is how D8's
read-only rule generalizes beyond the built-in `published`.

Deferred, with one guard that applies now: this **editorial** lifecycle is a
separate axis from the **processing** lifecycle in CDM §10.1
(`editing → published → rendered → line_file_generated → doc-process pipeline`).
Both use the word `published`, and they are not the same thing — the editorial
lifecycle's publish event *triggers* the processing one. Keeping them as two
axes means a user-defined FSM can be added later as document metadata plus its
own definition tables, without disturbing the processing path or the AST.

## D7 — Ontology is deferred

Ontology association is a large topic in its own right and is deferred. It will
need to connect to the existing object model (ADR 2026070101 [4], object-centric
design) rather than introducing a parallel one.

## D8 — Published documents are read-only; the first edit after publish opens a new version

A document is read-write in any non-frozen state and read-only once frozen
(`published` by default, D6). Saves before publication increment
`content_version` in place. The first modification after publication creates a
new document per D3; subsequent modifications of *that* document are again
in-place until it is published.

This is what makes D3 affordable. Because a published document can never change,
the artifacts, `source_line_spans`, anchors, renderings, and search entries bound
to it can never be invalidated — the immutability is the guarantee, not the
lineage record. It also bounds block-ID churn to drafts, which is what makes D9
tractable.

The author chooses the relation type (`amendment` by default, or `addendum` /
`replace`) when the new version is opened.

## D9 — Block identity is preserved across edits and rewrites

CDM §1.1 makes block IDs stable slugs, and `kb.cdm_anchors`,
`kb.cdm_projections.block_ids`, `cross_reference.target.block_id`, and artifact
provenance all bind to them. The editor must therefore treat a block ID as an
identity, not a label.

- IDs are allocated once, at block creation, and are immutable for the block's
  lifetime within its document. Editing a block's content never changes its ID.
- Generative tools (§3.4–§3.7, §3.11–§3.12) **never emit IDs**. They return
  content for a span of existing blocks, and the editor maps the result back: a
  rewritten block keeps its ID; a split yields one inheriting block plus newly
  allocated IDs; a merge keeps the first block's ID.
- IDs that disappear are recorded as **retired** rather than forgotten, so an
  inbound `cross_reference` can be reported as broken instead of dangling
  silently.
- Allocation derives a slug from heading text or block type plus a short
  disambiguator, unique within the document (CDM §1.2).
  **Implementation note (`cdm-editor-mvp`, 2026/07/27):** the allocator
  supports both, but the MVP's insert-then-type interaction (a block is
  created empty; the author types its content afterward) means heading text
  never exists at the moment a block is actually created through the shipped
  editor. Every id it produces is therefore type-plus-counter (`heading-2`),
  never text-derived (`score-range`), even though the fixtures this spec and
  its tests use show the latter style. Closing this needs either a different
  interaction (author supplies heading text before the block exists) or a
  rename step after first save; out of scope for the MVP.

Cross-document references always point at published — hence frozen (D8) —
documents, so ID churn is confined to drafts and never breaks an external
reference.

## D10 — LLM output is validated into CDM AST, and inserted only on acceptance

Every generative tool emits a **CDM block fragment**, not prose, Markdown, or
HTML. The preferred mechanism is a constrained tool-call schema mirroring CDM's
`Block` and `Inline` types, with a Markdown fallback parsed by the Markdown
reader for models that cannot honor it.

Every fragment passes the CDM §1.2 validator before it can enter the document.
A fragment that fails is surfaced to the author as a rejected suggestion;
nothing invalid is ever written.

Insertion is a **proposal the author accepts or rejects** in a diff view, never a
direct write. This keeps a human in the loop on content, and keeps `origin` (D2)
honest — the author's acceptance is what makes an assertion human-authored.

## D11 — The editing surface is a block editor isomorphic to the CDM AST

The editor's in-memory document model must be isomorphic to the CDM AST, so that
saving is a serialization rather than a conversion. Two alternatives are
rejected: a Markdown-source editor (cannot express semantic blocks, reliable
tables, or the equation AST) and a WYSIWYG-over-HTML editor (leaks presentation
into the document, violating D1).

The concrete component is not yet chosen (§6). Whatever is chosen, its schema
must mirror CDM §2 and §3 block and inline types and must **forbid** marks
carrying presentation. A ProseMirror-family component is the leading candidate,
since its node model is already close to CDM's.

## D12 — Draft reviews are author-triggered runs, keyed to `content_version`

Document reviewers (§3.3) run against artifacts, and a draft is off both
worklists (CDM §10.1). So a draft review is explicitly requested by the author
and runs the same reviewers, on the same line file, against the same artifact
tables — the shape D5b established for appendices.

Review results are keyed to the `content_version` they were produced from.
Results from an older version are shown as **stale**, never as current.

## D13 — One search index, one corpus, latest version by default

An authored document is indexed **once**, by the standard doc-process pipeline
off its line file, exactly as an uploaded document is. There is no second,
CDM-specific search corpus; that would contradict CDM §10's "two document
origins, one processing pipeline" and would return duplicate hits for every
authored document.

What CDM's projections contribute is *better text*, not a second index: for an
authored document, the retrieval text for a chunk is the CDM projection of the
blocks in that chunk's line range (verbalized tables, equations with variable
descriptions — CDM §8, §9) rather than the raw line-file text. Uploaded
documents keep the existing behavior.

Because every version is its own document (D3), search would otherwise return
n near-identical hits per document. Search therefore returns the **latest
version in each lineage** by default, with an explicit option to search all
versions.

*This decision changes what `kb.cdm_projections` is for and touches CDM §9 and
§11. It is recorded in ADR 2026072602 as **Proposed pending confirmation**,
unlike every other decision here.*

## D14 — Deletion checks lineage and inbound references

Soft delete is the default (§2.6). Hard delete removes the `kb.inputs` row and
cascades to all derived artifacts through the existing input-deletion path
(ADR 2026072301 [5]); CDM's `ON DELETE CASCADE` from `kb.cdm_documents` covers
blocks, renderings, projections, and anchors.

Before a hard delete the system reports two things and requires explicit
acknowledgement: whether the document is a link in a version lineage (D3), and
whether any other document holds a `cross_reference` to its `document_key`.
Deleting a middle version leaves its successor's relation pointing at a missing
document, so that relation is marked dangling rather than silently rewritten.

Hard-deleting a *published* document requires elevated privilege (D15), since
published documents are immutable and citable by design.

## D15 — Access control follows the existing role model

Editor actions map onto the roles established in ADR 2026072001 / 2026072002
(Kratos) [6][7]. These are distinct permissions, not one "edit" right: read;
edit a draft; publish; perform a lifecycle transition; manage templates; hard
delete; force-unlock (D16).

Publish and template authoring are privileged. A Typst template is executable
code compiled server-side, so template compilation runs sandboxed — no
filesystem or network access, with CPU, memory, and wall-clock limits.

Every editor query is tenant-scoped. Documents inherit `tenant_id` and
`ks_store_id` from their `kb.inputs` row, which is why CDM needs no tenant
prefix on `document_key`.

## D16 — Concurrency control: backend section locks, deferred

The intended model, recorded as an early design sketch:

1. During initial drafting, before a `kb.inputs` row exists, there is no
   concurrency control.
2. Editing content takes a lock on the **immediate section**. Locks are managed
   in the backend. On failure the user is told who holds the lock and since
   when, and is offered the option to wait.
3. A granted lock records the holder and the acquisition time.
4. Saving to the database releases the lock. The first user in the waiting list
   is notified.
5. A user may also lock the **entire document**, which must be requested
   explicitly.
6. An administrator may force-unlock. Consequently, **the save path must
   re-check lock ownership at save time**, and tell the user if the lock was
   taken away.

Concurrency control is complicated and the full design is deferred.

One guard applies now: point 6 makes save an optimistic-concurrency operation,
not a blind write. The save API should carry the expected `content_version` and
lock token and reject a stale save from the outset. That is cheap to build in
now and expensive to retrofit — every client, every autosave path, and every
generative tool's insertion path would have to be revisited later.

## D17 — Vocabularies are configuration, not code

The annotation types in §3.2 and the lifecycle states in §2.4 are both
**indicative examples**. Different deployments, tenants, and users may need
different sets, so both are configuration.

They follow the resolution order already used for template fallback
(CDM §5.3) — system → tenant → user, most specific wins — and reuse the existing
configurable-menu and label-i18n mechanisms (ADR 2026071601 [8],
ADR 2026071602 [9]) rather than introducing a third configuration pattern. All
user-visible labels are localized through that mechanism.

# 5. Phasing

Editor features are gated by CDM phases (CDM §13). **CDM Phase 1 is
implemented** (AST, validator, Typst renderer, anchored rendering, line-file
generation, storage, publish lifecycle, and D5a's outlines).

**As of 2026/07/27, the editor MVP is also implemented** — HTTP API
(`/api/v1/cdm/*`) and editor UI (`/home3/cdm`) — via ADR 2026072603 and
OpenSpec change `ChenWeb/openspec/changes/cdm-editor-mvp/`. The Phase-1-gated
row below is split accordingly: what the MVP actually shipped vs. what
remains unblocked-but-not-yet-built.

| Depends on | Editor features |
|---|---|
| CDM Phase 1 (**done**) — MVP **shipped** | Create documents (§2.2); Text Edit Tool (§3.1) for all nine Phase 1 block types; in-place save with optimistic concurrency and publish (§2.3, the non-frozen half only); on-demand preview, including the TOC and lists of figures/tables/formulas (D5a) |
| CDM Phase 1 (**done**) — unblocked, **not yet built** | Opening a new version of a published document (§2.3's frozen-document half, D8); version history/lineage browsing (§2.5); delete (§2.6); template selection/management (§2.8 — the MVP always renders with `rendering.DefaultTheme`, no per-document template choice) |
| CDM Phase 2 — retrieval projection and chunking | Search (§2.1), Inline Search (§3.7), author-declared chunking (§3.9) |
| CDM Phase 3 — semantic blocks | Annotations that write blocks (§3.2), Document Reviewers (§3.3), Summarization / Extraction / Rewrite (§3.4–§3.6) |
| New artifact types + metric reconciliation (not part of CDM) | Search by semantic object (§2.1), annotations that write artifacts (§3.2), artifact appendices (D5b) |
| Deferred | Ontology (§3.8), lifecycle FSM (§2.4), retention (§2.7), concurrency control (D16), index (D5c), mandatory formatting standards (D1) |

Two things deserve emphasis, because they were easy to miss when scheduling —
one now resolved, one still live.

**There was no HTTP API for CDM; now there is.** Phase 1 delivered Go packages
(`cdm/model`, `cdm/rendering`, `cdm/store`) with no route in front of them.
`cdm-editor-mvp` added `server/api/cdmhandler`, registered under the existing
`/api/v1` group (`/api/v1/cdm/*`, not `/api/cdm/*` as ADR 2026072603 originally
wrote — corrected during implementation). Every "shipped" feature in the table
above goes through it; the "not yet built" row still needs API work of its own
(a `versions` endpoint, a `delete` endpoint, template CRUD) before its UI can
exist.

**The editor's most valuable feature is gated on work not yet scheduled.**
Semantic annotation depends on artifact types that D2 explicitly does not add in
the current phase; that work must be planned, not assumed to fall out. This
remains true after the MVP: semantic annotation was explicitly out of the
MVP's scope (ADR 2026072603 DR3) and is unaffected by anything shipped above.

Two further gaps the MVP itself introduced, worth carrying into whatever plans
the "not yet built" row above: **Paraglide i18n was not applied to the editor**
(§3's toolbar and every editor string are hard-coded English) — checked
against actual `home3` practice first, which uses Paraglide nowhere outside
the public `/semos` pages, so this matches every sibling `home3` feature
rather than diverging from D17's vocabulary-as-configuration intent; and
**block ids in the shipped editor are always a type-plus-counter slug**
(`heading-2`, not `score-range`) rather than the heading-text-derived slug D9
describes, because the built insert-then-type interaction never has heading
text available at the moment a block is created. Both are recorded in ADR
2026072603's 2026/07/27 Change Log entry with the reasoning; neither blocks
anything in the table above, but a future pass at §2.8 (templates) or a
rename affordance would be the natural place to close the second one.

# 6. Open Questions

1. **AST diff.** §2.3's change summaries need a block-level diff over the CDM
   AST. Stable block IDs (D9) make this tractable, but no algorithm or output
   format is specified.
2. **Referenceable figure and table numbers in the AST.** D5a solves display;
   citing "Table 3" from an artifact or another document still needs the
   numbering authority CDM §16.1 defers.
3. **Index terms.** D5c needs a new inline node type in CDM plus a Typst
   indexing package.
4. **Whether CDM projections supply pipeline chunk text** (D13). Touches CDM §9
   and §11 and needs confirmation.
5. **Metric reconciliation schema** (D5b, CDM §10.5.1). Only the requirement and
   its model — the existing entity reconciliation machinery — are recorded.
6. **Full concurrency design** (D16).
7. **Multi-language documents.** CDM carries `language` per document with no
   per-block override (CDM §16.3); the editor has no answer for a bilingual
   standard.

*Resolved: the editing component (was Q1) — answered by ADR 2026072603 [11]
DR1, accepted 2026/07/26: a Svelte-owned block list holding `[]Block`, with
TipTap confined to the inline content of text-bearing blocks.*

# 7. References

[1] `KnowledgeStore/doc-repo/specs/202607/2026072501-spec-canonical-doc-model.md`

[2] `KnowledgeStore/doc-repo/adrs/202606/2026061801-adr-document-review.md`

[3] `KnowledgeStore/doc-repo/adrs/202607/2026072602-adr-cdm-editor-scope.md`

[4] `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`

[5] `KnowledgeStore/doc-repo/adrs/202607/2026072301-adr-kb-input-artifact-deletion.md`

[6] `KnowledgeStore/doc-repo/adrs/202607/2026072001-adr-user-roles-kratos.md`

[7] `KnowledgeStore/doc-repo/adrs/202607/2026072002-adr-user-management-chenweb.md`

[8] `KnowledgeStore/doc-repo/adrs/202607/2026071601-adr-configurable-knowledge-menus.md`

[9] `KnowledgeStore/doc-repo/adrs/202607/2026071602-adr-knowledge-menu-labels-i18n.md`

[10] `KnowledgeStore/doc-repo/adrs/202607/2026072601-adr-cdm-anchored-rendering.md`

[11] `KnowledgeStore/doc-repo/adrs/202607/2026072603-adr-cdm-editor-frontend.md`
