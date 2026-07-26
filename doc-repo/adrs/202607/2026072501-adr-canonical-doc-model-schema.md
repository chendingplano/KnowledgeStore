# ADR 2026072501 — Canonical Document Model (CDM) v1.0 Schema Decisions

**Date:** 2026-07-25 \
**Status:** Accepted (design only — not yet implemented) \
**Component:** SemOS Canonical Document Model — `kb.documents`, `kb.document_blocks`, `kb.document_renderings`, `kb.document_projections`, renderers, retrieval projections \
**Authors**: Chen Ding \
**Tags**: SemOS, CDM, document-model, retrieval, typst, rendering, schema, storage

## Change Logs
* 2026/07/25, ADR created. Records the schema decisions taken while resolving
  internal contradictions in spec `2026072501-spec-canonical-doc-model`. The
  spec was rewritten in place to conform to these decisions; the Go and JSON
  examples in it were verified to compile and parse.
* 2026/07/26, Amended during change planning
  (`ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`). Added DR11
  (authored-only scope and coexistence), DR12 (`kb.cdm_*` namespace, which
  **supersedes the table names in DR10**), DR13 (registration in `kb.inputs`
  and the publish lifecycle), and DR14 (module ownership). The anchored-rendering
  architecture is recorded separately in ADR 2026072601, which supersedes the
  assumption in this ADR that Typst is only a publication target.

## Context

Spec `2026072501-spec-canonical-doc-model` proposes a Canonical Document Model
that stores document **meaning** once and derives retrieval, presentation, and
export representations from it. The architectural core of that proposal is
sound and is not in question here.

The first draft, however, was not implementable as written. A review found that
it specified several constructs more than one way, so a reader could not tell
which shape was authoritative:

* **Identifiers contradicted themselves.** Every JSON example used readable
  string IDs (`doc:jaro-winkler`, `intro`, `example-table`), while the storage
  model required `uuid` primary keys and `block_ids uuid[]`. Both could not be
  right, and the stated benefit "stable block IDs" argued against opaque UUIDs.
* **Equations were specified four different ways** — §1 used
  `math{format, expression}`, §6.1 used `representations{latex, typst}`, §6.2
  used `format`+`source`, and §6.3 recommended `original`+`normalized`+
  `parse_status`. The canonical §1 example did not match the document's own
  recommendation.
* **The Go examples did not compile.** `renderBlock` referenced `block.Text`
  and `block.Children`, which the `Block` struct did not declare; it called an
  undefined `renderBlocks`; `renderTable` read `row.Values[col.Key]` while the
  JSON showed flat row objects; and `TableRow`, `TableColumn`, and
  `MathExpression` were used but never defined.
* **Semantic overlaps were unresolved.** `warning` appeared both as a `role` on
  a `callout` and as its own block type in the renderer; `definition` was listed
  both as a base block type and as a semantic block; `section` vs `heading` and
  `figure` vs `image` were both listed without distinction.
* **Declared-but-unspecified features.** `citation`, `cross_reference`, and
  `reference` appeared in the type lists and in the pipeline's "reference
  resolution" step, and "reusable references" was a headline benefit, but no
  reference schema existed.
* **The example mathematics was wrong.** The Jaro AST summed two terms; the
  formula and the spec's own prose projection have three. `abs` was used for
  string length, and the transposition variable was `t` in one section and `tau`
  in another.
* **The storage model did not match the codebase.** It used `uuid` keys and
  `created_at`, whereas the existing `kb` schema (e.g. `kb.chunks`, `kb.inputs`)
  uses `BIGSERIAL` keys and `create_time` / `update_time`, and embeddings are
  `vector(1536)`.

This ADR records the decisions taken to resolve each of these, so that the
choices are not re-litigated when implementation starts.

## Decision

CDM `schema_version` is `1.0`. Where the draft offered alternatives, exactly one
shape is now normative, and every example in the spec conforms to it.

### DR1 — Three identifier kinds; block references are text, never UUID

| Identifier | Type | Scope | Purpose |
|---|---|---|---|
| `documents.id` | `BIGSERIAL` | database | Surrogate PK and FK target; never in canonical JSON |
| `document_key` | `text` | global | Stable, human-readable document identity (`doc:jaro-winkler`) |
| `Block.id` | `text` | one document | Stable, human-readable block slug, unique within the document |

Block IDs are **slugs, not UUIDs**. The "stable block IDs" property requires an
ID that survives re-parsing and editing of the source and that a human can
recognize in a retrieval result; a regenerated UUID has neither property.
Consequently `kb.document_blocks.block_id` is `VARCHAR`, and
`kb.document_projections.block_ids` is `TEXT[]` rather than `uuid[]`.

This also removes the draft's ambiguity about what `document_id` meant: the
canonical JSON carries `document_key`, and the database carries a numeric
`document_id` foreign key. They are different things with different names.

### DR2 — Equations: semantic AST with original source as fallback (Option C + B)

Adopted as the single equation shape:

```json
{
  "math": {
    "display": true,
    "parse_status": "success",
    "original":   { "format": "latex", "source": "..." },
    "normalized": { "op": "equal", "args": [] }
  }
}
```

* `original` always stores the source as authored, so nothing is lost when the
  parser fails or improves later.
* `normalized` stores the semantic AST **directly** — there is no
  `{format, expression}` envelope, because the format is always the CDM math AST.
* `parse_status` (`success` / `failed` / `skipped`) records the outcome
  explicitly rather than leaving it inferable from a missing field.
* Renderers prefer `normalized`, and fall back to converting `original`. This
  rule is now executable in the spec as `TypstRenderer.renderMath`.

Two related fixes: numeric literals are carried as **exact decimal strings**
(`"value": "3"`) so text round-trips without binary floating-point loss, with
rationals expressed as a `divide` node rather than a `"1/3"` literal; and the
operator vocabulary distinguishes **`length`** (cardinality of a string or
sequence, `|s|`) from **`abs`** (numeric absolute value). Conflating them
produced incorrect verbalization in the retrieval projection.

The example Jaro formula was corrected to its actual three-term definition,
`J = 1/3 (m/|s_1| + m/|s_2| + (m-t)/m)`, and the transposition symbol is `t`
everywhere, including in the LLM-context projection that explains it.

### DR3 — One `Block` struct, with an explicit content/children/items rule

CDM keeps a single `Block` struct rather than a type-per-block hierarchy —
it keeps JSON round-tripping and the renderer dispatch simple. The cost is that
which fields are meaningful depends on `Type`, so the rule is made normative:

> A block carries inline payload in `content`, **or** nested blocks in
> `children`, **or** list items in `items` — never more than one of the three.

`paragraph`, `heading`, and `quote` use `content`; `callout`, `definition`, and
the other semantic containers use `children`; `list` uses `items`. The struct
now actually declares every field the renderer reads (`Text`, `Lang`,
`Children`, `Term`, `Title`, `Role`, `Ordered`, `Src`, `Alt`, `Caption`), and
`TableColumn`, `TableRow`, `Equation`, `MathSource`, `MathExpr`, and `RefTarget`
are all defined.

### DR4 — Table rows are keyed maps of inline content

```json
{ "cells": { "left": [{ "type": "text", "text": "John" }] } }
```

Rows key their cells by `TableColumn.Key`, and each cell is `[]Inline`, not a
string. Cells routinely need emphasis, links, and inline math; a canonical model
that cannot express them forces a lossy escape hatch later, and widening the
type after data exists is far more expensive than paying the verbosity now. A
key absent from `cells` renders as an empty cell. This resolves the draft's
`row.Values[col.Key]` / flat-object mismatch.

### DR5 — `warning` is a `callout` role, not a block type

Warnings, notes, cautions, and tips share one structure and differ only in
severity, so they are one block type (`callout`) carrying a `role`. The
governing rule:

> If two constructs project **differently for retrieval**, they are different
> **types**. If they differ only in how prominently they are **displayed**, they
> are one type with different **roles**.

`role` is therefore restricted to the callout severity vocabulary (`note`,
`tip`, `important`, `warning`, `caution`). Everything in the semantic block list
— `claim`, `definition`, `provision`, `metric`, `procedure`, `example`,
`counterexample`, `assumption`, `evidence`, `reference` — is a distinct type,
and `definition` is listed only there, not also among the base block types.

### DR6 — Flat headings, derived `section_path`; `figure` folded into `image`

`section` is **not** a container block. Headings are flat blocks carrying a
`level`, and `section_path` is *derived* during projection by tracking the
heading stack. This keeps the AST shallow and makes incremental block edits
cheap — a concern that matters given the block-level storage table and
incremental reprocessing.

`figure` is dropped from v1.0 and folded into `image`, which carries `caption`
and `alt`. A numbered, separately referenceable `figure` needs a numbering
authority, which is deferred (see Open Questions).

`document` is likewise not a block type — the document is the root object.

### DR7 — Explicit three-part reference model

The draft promised "reusable references" and a "reference resolution" pipeline
step without a schema. v1.0 defines three constructs:

* **`cross_reference`** (inline) — targets a block via
  `{document_key?, block_id}`; an absent `document_key` means the current
  document. Optional `content` supplies display text.
* **`citation`** (inline) — targets a bibliography entry via `citation_key`,
  with an optional `locator`.
* **`reference`** (block) — a bibliography entry whose `id` *is* the citation
  key that `citation_key` resolves against.

Reference resolution verifies every target and records unresolved references as
**validation errors** rather than silently dropping them. Cross-document
references resolve against `document_key`, which is why DR1's stability
requirement matters.

### DR8 — Four renderers

Typst (primary publication), HTML (browser), Markdown (LLM context,
interchange), and plain text (retrieval projections). The draft's §5 listed only
two while its own diagram, `PlainTextRenderer` type, and pipeline listed four.
All renderers are **deterministic** — same document plus same renderer version
yields byte-identical output — which is the precondition that makes the cached
artifacts in `kb.document_renderings` safe to reuse.

### DR9 — `rendering_type` is the spelling; metadata is a nested object

The template-selection field is `rendering_type` everywhere — never
`render_type`, which the draft used in one place. Document metadata is a nested
`metadata` object with `authors` as a real JSON array (the draft had it as a
string that merely looked like one) and RFC 3339 timestamps.

Template resolution is **most-specific-wins**: an explicit per-document template
beats a `rendering_type` association, which beats a fallback; and within each,
user beats tenant beats system. The draft's "lower level overrides the higher
level" was ambiguous about which direction was "lower".

### DR10 — Storage follows existing `kb` schema conventions

> **Amended 2026/07/26 by DR12.** The table *names* below (`kb.documents`,
> `kb.document_blocks`, `kb.document_renderings`, `kb.document_projections`) are
> superseded by the `kb.cdm_*` namespace. Every other convention in this decision
> stands.

The storage model was realigned to what `kb` already does, rather than
introducing a second convention:

* `BIGSERIAL` surrogate primary keys, not `uuid`.
* `create_time` / `update_time`, not `created_at` / `updated_at`.
* `VARCHAR(n)` for bounded identifiers and enums; `ON DELETE CASCADE` from all
  child tables to `kb.documents`.
* `embedding vector(1536)`, matching the embedding model already in use in `kb`.
* Uniqueness that was missing is now explicit: `(document_id, block_id)`,
  `(document_id, parent_block_id, ordinal)` with `NULLS NOT DISTINCT`
  (PostgreSQL 15+, so top-level blocks are constrained too), and a
  `content_version`-aware unique key on projections and renderings.
* `doc_type`, `rendering_type`, and `authors` are promoted from the JSON into
  columns because they are filtered on; they must be written consistently with
  `semantic_document`.

### DR11 — CDM v1.0 serves authored documents; retrieval paths coexist

CDM v1.0 is for documents SemOS creates — the CDM Editor, LLM output, pipeline
output. Documents arriving as uploaded files keep the existing parse +
`line_range` path. CDM retrieval projections serve CDM-backed documents only;
`kb.chunks` / `kb.chunk_ranges` continue serving everything else.

This is what makes the first implementation tractable. Making CDM the parse
target for uploaded PDFs and Word documents would require bridging block-slug
provenance to the `line_range` convention used by roughly a dozen extractor and
search tables, and re-embedding the corpus. Deferring that keeps the work
additive and reversible, and proves the model on content whose structure we
control before it meets parser output.

Note this scopes the *representation*, not the *processing*: authored documents
still run through the same doc-process pipeline (DR13).

### DR12 — `kb.cdm_*` table namespace

Tables are `kb.cdm_documents`, `kb.cdm_blocks`, `kb.cdm_renderings`,
`kb.cdm_projections`, and `kb.cdm_anchors` — superseding the names in DR10.

Two collisions force this. `kb.semantic_projections` already exists and means
something unrelated: a search-oriented enrichment of an input (keywords,
category paths, search vectors) produced by the doc-processor, closer to a
summary than to a rendition. A CDM projection is not a summary at all — it is a
de-formatted textual rendition of the document. Two tables whose names both say
"projections" but mean different things will be misused by human developers and
coding assistants alike. Separately, a bare `kb.documents` would sit beside
`kb.doc_process_runs`, `kb.doc_proc_logs`, and the `kb.doc_review_*` family.

A subsystem prefix follows the convention already used by `kb.artifact_*`,
`kb.benchmark_*`, and `kb.inventory_*`. It disambiguates every CDM table at once
and leaves "projection" usable as the concept word in prose, so no vocabulary
churn in the spec.

*Alternative considered:* keep the original names and document the distinction
in table comments. Rejected — the failure mode is silent misuse by a future
reader, which a comment does not prevent.

### DR13 — CDM documents register in `kb.inputs` and join the standard pipeline

Every published CDM document gets a `kb.inputs` row with `type = 'cdm'`.
`input_record_id` is the foreign-key hub the artifact and search tables hang
off, so a CDM document without one would be invisible to all existing knowledge
tooling.

Lifecycle: `editing → published → rendered → line_file_generated →
doc-process pipeline`.

> **Amended 2026/07/26 by ADR 2026072602 DR5.** An earlier form of this decision
> gave a draft *no* input row. That is incompatible with author-triggered
> extraction in the editor, which needs somewhere to attach artifacts while the
> document is still being written. A draft now has its input row from creation,
> written with **both** derived states terminal
> (`parse_state = 'parsed_success'`, `pipeline_state = 'success'`) so it stays
> off both worklists; publishing clears the `doc_processing` status entry so
> `pipeline_state` derives back to `'pending'` and the standard worklist
> enqueues it. Publish is a status transition, not a row creation.

`parse_state` and `pipeline_state` are *derived* from the `status` JSONB by
`kb.input_status_parse_state` and `kb.input_status_pipeline_state`, and both
default to `'pending'`. A published CDM document is written **born parsed but
pipeline-pending**:

```json
[{ "operation": "parsed", "proc_status": "success" }]
```

This skips the parse worklist (`parse_state = 'pending'`) — there is no file to
parse, and the CDM AST *is* the parse result — while the doc-processing worklist
(`parse_state = 'parsed_success' AND pipeline_state = 'pending'`) picks it up
like any other document. Tenancy comes from the input row, which also resolves
the spec's open question about tenant scoping of `document_key`.

*Rejected during planning:* marking CDM documents pipeline-complete so
extraction never runs over them. That would split SemOS into two classes of
document, with authored content invisible to metrics, provisions, entity, and
review tooling — the opposite of the intent. One pipeline, both origins.

### DR14 — Module ownership: ChenWeb, with a dependency-light core

CDM lives in ChenWeb at `server/api/cdm/`, split into `model` (types, JSON,
validator — no database imports), `rendering` (depends only on `model`), and
`store` (the only package touching the database).

CDM's storage is the `kb` schema, which is ChenWeb's, and no other workspace
project needs a document model today. Per the workspace guidance that
`shared/go` is for truly common functionality, promoting it now would be
speculative; keeping `model` and `rendering` import-clean makes a later
promotion a package move rather than a rewrite.

### Alternative Decisions

* **UUID block IDs (rejected, DR1).** Uniform with the rest of the schema and
  trivially unique, but breaks ID stability across re-parses and makes retrieval
  results unreadable — which defeats two of CDM's stated benefits.
* **Store parallel LaTeX + Typst variants (Option A, rejected, DR2).** Simplest
  to implement, but duplicates content with no authoritative copy, so the
  variants drift and nothing resolves a disagreement. It is now explicitly
  ruled out in the Phase 1 MVP text, which previously recommended it.
* **LaTeX as the sole canonical source (Option B, rejected as primary, DR2).**
  Retained only as the *fallback* path. Good provenance, but conversion is
  lossy and no structure is available for verbalizing formulas into retrieval
  text.
* **Type-per-block Go hierarchy (rejected, DR3).** Type-safe, but costs custom
  JSON marshalling for every type and a heavier renderer; the invariant in DR3
  buys most of the safety through validation instead.
* **String table cells (rejected, DR4).** Much less verbose, and adequate for
  the MVP, but widening a cell type after data exists is expensive.
* **`section` container blocks (rejected, DR6).** Better structural fidelity and
  a natural `section_path`, but deepens the tree and complicates incremental
  block updates; the heading stack reconstructs the same information at
  projection time.

### Database Migrations

None yet — this ADR is design-only. When implementation begins, all four tables
(`kb.documents`, `kb.document_blocks`, `kb.document_renderings`,
`kb.document_projections`) must be created through **goose** migrations under
the owning project's `project_migrations/`, per workspace policy, and not as
ad-hoc DDL. `UNIQUE NULLS NOT DISTINCT` sets a PostgreSQL 15+ floor.

### Data Formats

Canonical JSON per spec §1, `schema_version` `1.0`. Timestamps RFC 3339 UTC.
Math numeric literals are exact decimal strings.

### Environment Variables

None.

## Implementation

Not started. The spec's §13 phasing is unchanged in substance, with two
corrections: Phase 1 stores `original` with `parse_status: "skipped"` (rather
than parallel LaTeX/Typst forms, per DR2), and Phase 3's semantic block list now
reads `callout (with role)` plus `reference` (per DR5, DR7).

### Code Changes

None in application code. Changes in this cycle were confined to the
specification document, which was rewritten in place.

## Operational Behaviors

No runtime behavior changes yet. Two forward-looking constraints follow from
the decisions:

* Renderer determinism (DR8) is what allows `kb.document_renderings` to be
  treated as a cache keyed by `(document, content_version, renderer,
  renderer_version)`. A non-deterministic renderer would silently serve stale
  or inconsistent artifacts.
* Unresolved references are validation failures (DR7), so ingesting a document
  with a dangling cross-reference will surface an error rather than quietly
  producing a document with a broken link.

## Consequences

* The spec is now internally consistent: one identifier model, one equation
  shape, one table shape, one place where each semantic construct is defined.
  An implementer can code from it without guessing.
* Block IDs being text slugs means the ingestion pipeline **must** generate
  stable, unique-per-document slugs, and must have a defined collision policy.
  This is real work that UUIDs would have avoided; it is the price of DR1.
* Table cells as `[]Inline` make canonical JSON noticeably more verbose. This is
  accepted (§1 already accepts verbosity in exchange for structure).
* Promoting `doc_type` / `rendering_type` / `authors` into columns creates a
  consistency obligation with `semantic_document` on every write.
* `UNIQUE NULLS NOT DISTINCT` requires PostgreSQL 15 or later.
* Deferred scope is now explicit rather than accidentally missing — numbered
  figures, structured diagrams, per-block language, block-level access control,
  and tenant scoping of `document_key` are recorded as Open Questions in spec
  §16 instead of being silently absent.

## Tests

No application tests, as no application code exists yet. The spec's examples
were verified mechanically:

* All 7 Go snippets were extracted into a single package and compiled:
  `go build` and `go vet` both pass. The three helper functions the spec
  declares as signature-only (`indentContinuation`, `renderTypstMath`,
  `convertLatexToTypst`) were stubbed for this check; everything else compiles
  as written.
* All 15 JSON snippets were parsed: 15 valid, 0 invalid. The draft's document
  metadata example had a trailing comma and did not parse.

When implementation starts, the schema deserves round-trip tests
(JSON → `Document` → JSON), validator tests for each §1.2 invariant, and
golden-file tests for each renderer to enforce the determinism DR8 requires.

## Documentation Impact

*What knowledge changed:* the CDM canonical schema moved from a set of competing
sketches to a single normative v1.0 definition, and its storage model was
aligned with existing `kb` conventions.

*Which docs were updated:*
`doc-repo/specs/202607/2026072501-spec-canonical-doc-model.md`, rewritten in
place. Substantive changes: a normative note in the preface; new §1.1
(Identifiers) and §1.2 (Content model invariants); §2 resolved-omissions note;
§3 type-vs-role rule; §4.1 metadata corrections; §5 expanded to four renderers
with corrected, compiling Go; §5.3/§5.4 explicit resolution order; new §5.5;
§6.4 promoted from a loose "Recommendation" to a decision with an operator
vocabulary; new §7 (References, Citations, Cross-References); §8 `section_path`
derivation; §11 storage realigned; §13 MVP corrected; new §16 (Open Questions).
Sections were renumbered from §7 onward to accommodate the new reference
section, and heading levels were normalized so subsection depth matches
numbering.

*Which docs are now stale:* none identified. No other document in
`KnowledgeStore` currently references CDM; this ADR and the spec are the only
sources. Any future CDM Editor document (spec §14) must be written against
this schema.

*What was intentionally left undocumented:* the internals of
`renderTypstMath`, `convertLatexToTypst`, and `indentContinuation` (signatures
only — these are implementation detail); the HTML and Markdown renderer bodies;
the parser front-ends for each source format; and the chunking policy that
decides projection boundaries. Each is a separate design task.

## References
- Spec: `doc-repo/specs/202607/2026072501-spec-canonical-doc-model.md` (CDM v1.0)
- ADR 2026072601 (CDM anchored rendering — Typst as the location substrate)
- Change: `ChenWeb/openspec/changes/cdm-phase1-ast-and-typst-renderer/`
- Existing `kb` schema conventions: `ChenWeb/project_migrations/20260420113000_create_kb_chunks_table.sql`
- Input status derivations: `kb.input_status_parse_state`,
  `kb.input_status_pipeline_state`; worklists at
  `ChenWeb/server/api/kbhandler/handler.go:679` and `:748`
- Goose migration policy: `shared/go/api/goose/goose.md`, workspace `CLAUDE.md`
- Related: ADR 2026070101 (object-centric design), ADR 2026071002 (doc-processor incremental)
