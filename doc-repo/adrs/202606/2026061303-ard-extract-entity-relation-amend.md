# ADR 2026061302 — Entity-Relation Extraction: Entity-Linked Relations

**Date:** 2026-06-13 \
**Status:** Accepted — implemented (D1–D6) \
**Component:** Doc Processor — Entities & Relations

## Change Logs
### Change 01
Problems: when extracting relations, it needs to build the context 
for entities. In the current implementation, for each entity, its
context is:
  - the chunk summary
  - file leading lines
  - the line in which the entity is extracted

Note that this is for each entity. Below is the analysis for a 12-page document:
- Number of entities: 192 (after consolidation)
- Total size in bytes of its line file: 26,759
- The total size of the context is: 432,044, nearly 25x size of the entire line file.

### Decisions:
Change the context to the line file.

### Evaluation (2026-06-14)

**Verdict: the proposal is sound and is a net improvement — but the one-line
decision is under-specified and must be tightened before implementation.**

**Where the 25x blowup comes from (confirmed in code).** Phase 2 input is
assembled by `buildRelationWindowInputText` (`entity-relation-linking.go:396`),
which emits, *per entity*, the `entity_context` produced by
`buildEntityContextForEntities` (`extract-entity-relation.go:1078`). That context
is `chunk_summary + leading_lines + span_lines` for each entity. Within a window
the entities overwhelmingly share the same chunks, so the **chunk summary and the
leading/span lines are re-emitted once per entity**. With 192 entities the same
underlying text is duplicated dozens of times — hence 432 KB of context over a
26.7 KB line file. The redundancy is structural, not incidental.

**Does it make sense? Yes.** The line file is the source of truth that every
`entity_context` is sliced from. Feeding the (windowed) line text *once* and
listing the entities separately removes the duplication by construction.

**Effect on extraction effectiveness — expected to improve, not degrade:**
- Relations are asserted in *contiguous* prose ("A … relates to … B", with A and
  B near each other). Per-entity context **fragments** that prose into per-entity
  snippets and loses the connective tissue between the two endpoints. Contiguous
  line text preserves the sentence that actually states the relation, which
  should raise recall and precision for exactly the local relations D5 targets.
- It directly relieves the "lost-in-the-middle / `n²` pair dilution" pressure
  that D5 (and the timeout/empty-JSON fallback) were fighting: a shorter,
  non-redundant prompt is more needle-rich.
- Minor loss: the `chunk_summary` abstraction drops out of the relation input.
  For *local* relation extraction this is acceptable (raw lines are the better
  signal); summaries were never where relations are stated.

**Required clarifications (the decision must specify these):**
1. **"The line file" = the window's contiguous line-range *slice*, not the whole
   file per call.** Feeding the entire line file into *every* window call would
   re-introduce the precise failure modes D5 exists to prevent (context bloat on
   large docs, `n²` dilution) and would not scale beyond the 12-page example.
   `buildRelationWindows` currently returns only entity groups and discards the
   window's `[lo, hi]` line bounds; it must also return the line range so the
   slice can be cut. (Whole-file context is acceptable *only* as the degenerate
   small-doc / spanless-entity case that already collapses to one window.)
2. **Keep passing the entity roster** (id / name / type / aliases) alongside the
   line text. The line slice replaces *per-entity context only*; without the
   explicit id-bearing list the relations can no longer be entity-linked (D1) and
   D4 resolution loses its anchor.
3. **Scope is the Phase 2 relation input, not the stored field.**
   `kb.entities.entity_context` is still persisted and consumed elsewhere
   (`SaveEntities`/artifact reads, search/display). So `buildEntityContextFor
   Entities` is *not* removed — only `buildRelationWindowInputText` stops
   embedding it. (Whether to keep computing `entity_context` at all is a separate
   question, out of scope for Change 01.)

**Bonus opportunity.** If the sliced line text carries **line numbers**, the
model can cite `lines` directly. Today relation grounding is endpoint-derived
(`relationSpansFromEndpoints`, per the Implementation Status) precisely because
the window input has no line numbers; numbered slices would let relations ground
to the line where they are stated, a strict improvement over endpoint-union
spans.

**Consequences / migration.** Code-only change (prompt input composition +
`buildRelationWindows` returning ranges + `processRelationWindow` reading the
slice). No schema change. Phase 2 cost/latency drop substantially; the per-window
fallback to Phase-1 relations is unaffected. Relation prompt
(`prompt-extract-relations-v1.md`) should be re-checked: it currently expects a
"context:" block per entity and must be reworded for "here is the source text +
here is the entity list."

### Resolution / chosen design (2026-06-14)

The whole document (or whole line file) is **not** fed in — it can exceed the
context window and a too-large context degrades relation recall (lost-in-the-
middle, `n²` pair dilution; see D5). Windowing is retained; only the **unit** of
the window size and the **content** of each window change:

- **`RELATION_WINDOW_SIZE` is now expressed in *pages* (default `20`)**, replacing
  the previous line-count semantics (was `200` lines). A window covers a
  contiguous page range; its content is the materialized **line-file text for that
  page range** (cut once, contiguous), not per-entity `entity_context`.
- **`RELATION_WINDOW_OVERLAP` stays in *lines* (default `20`)**. Adjacent windows
  share an `overlap`-line band at the page-window boundary so a relation whose
  endpoints straddle the boundary still lands in a window holding both.
- Each window call carries: (a) the **entity roster** for entities positioned in
  the window (id / name / type / aliases — required so relations stay
  entity-linked per D1/D4), plus (b) the **contiguous source text** of the
  window. Per-entity `entity_context` is no longer embedded in the Phase 2 input.
- `kb.entities.entity_context` is still computed and persisted for its other
  consumers (search / display); only its use as Phase 2 relation input is dropped.

### Change 02
Need to treat `kb.entities.entity_en` the same way as `kb.relations.predicates`:
* It is a dictionary for entity names
* Need normalize
* Need to relate the dictionary key to 'instance'

---

## Context

Entities and relations are currently extracted by a **single structured LLM
call per chunk** (`EntityRelationProcessor.processChunk`,
`server/api/doc-processing/extract-entity-relation.go`). Each call returns
`{language, entities[], relations[]}`, and chunks are processed concurrently.
Results are written to `kb.entities` and `kb.relations` (refer to [1], [2]).

The question that prompted this ADR was whether entity and relation extraction
should be split into two separate LLM calls. Investigating the current code
surfaced two structural problems that matter more than the call-count question
itself:

1. **Relations are not entity-linked.** In `normalizeRelationRows`, a relation's
   `subject` / `object` are stored as free-text strings with no foreign key to
   `kb.entities.entity_id`. Even though entities and relations come from the same
   call, nothing guarantees a relation endpoint corresponds to an extracted
   entity. The linkage is implicit and best-effort.

2. **Everything is per-chunk.** Each chunk is extracted in isolation, so a
   relation whose subject appears in chunk 3 and object in chunk 7 **cannot be
   captured at all** by the current design.

The existing timeout / empty-JSON fallback path
(`extractEntityRelationWithFallback`) is a signal that the combined per-chunk
output is already under size/latency pressure.

### Existing segmentation: chunks vs. blocks

The pipeline already has two segmentation processors with different granularity:

- **Chunking** — small segments sized by `CHUNK_SIZE` (currently **2000**).
  Entity/relation extraction currently runs per chunk.
- **Blocking** — larger segments sized by `INPUT_BLOCK_SIZE` (currently
  **20 pages**). Blocks are **only** used by metadata extraction today.

> **Terminology caution:** "block" is therefore an overloaded word in this
> codebase. Throughout this ADR, *candidate block* / *candidate pair* (D5) refers
> to a **relatedness-based grouping of entities** for relation extraction — it is
> **not** the `INPUT_BLOCK_SIZE` page-block produced by the blocking processor.
> A page-block is a span of source text; a candidate block is a set of entities.

**Guiding principle:** *A relation is only useful if its endpoints are real,
identified entities.* A triple of free-text strings that does not resolve to
entities in the graph carries almost no value — it cannot be traversed, joined,
or deduplicated. Therefore **entity-linking is not optional**; it is the
property that makes relations worth storing.

---

## Decision

### D1 — Relations MUST reference entity IDs (entity-linked relations)

Every relation persisted to `kb.relations` MUST carry the resolved
`entity_id` of its subject and object, in addition to the surface strings:

- Add `subject_entity_id TEXT` and `object_entity_id TEXT` to `kb.relations`.
- A relation whose subject or object cannot be resolved to an extracted entity
  is **not dropped**; the unresolved endpoint is promoted to a *provisional*
  entity so the relation still links to a real `entity_id` (see D4).
- The surface strings (`subject`, `object`, and their `_en` variants) are
  retained for display and search, but the `*_entity_id` columns are the
  authoritative graph edges.

### D2 — Adopt a two-phase extraction flow

Keep entity extraction per-chunk (where local context is richest), but make
relation extraction **entity-aware** by feeding the resolved entity set into the
relation step:

1. **Phase 1 — Entity extraction (per chunk).** Extract entities per chunk as
   today.
2. **Phase 1.5 — Entity consolidation (dedicated step, in the existing
   processor).** Consolidate and deduplicate entities at the document level so
   each distinct entity has a single canonical `entity_id` (merging aliases /
   `entity_en`). This runs to completion **before** any relation extraction
   begins. See D6 for where it lives.
3. **Phase 2 — Relation extraction (entity-aware).** Provide the consolidated
   entity list (canonical name + aliases + `entity_id` + `entity_context`) to
   the relation LLM call and instruct it to connect **only** entities from that
   list. The model returns relations referencing entity IDs (or names that the
   normalizer resolves back to IDs).

**Consolidate**
Phase 1 extracts entities per chunk, so the same real-world entity shows up 
multiple times: once per chunk it appears in, and sometimes under different 
surface forms (e.g. "Acme Corporation" in chunk 2, "Acme" in chunk 7). 
Consolidation (Phase 1.5 / consolidateEntities) merges all of those into one 
canonical entity with one entity_id, unioning their aliases/keywords/line_spans.

So "consolidated entities" = the final, deduped entity set that gets canonical 
IDs assigned. That set is what relations must link to.

**Phase 2 input must contain the materialized line *text*, not line-span
references.** `line_spans` (e.g. `"14-16"`) are just pointers; the model cannot
reason over line numbers. The `entity_context` field already solves this — it
materializes the actual content of the cited lines (chunk summary + leading
lines + span lines, built by `buildEntityContextForEntities`). Phase 2 therefore
feeds each entity's `entity_context` (real text), and the relation step never
sees bare span numbers.

This split is justified not by "two tasks per chunk hurts quality" alone, but
because Phase 2 is the only place where (a) relations can be reliably
entity-linked, and (b) **cross-chunk relations** become expressible — the
relation pass sees the whole entity set rather than one chunk.

### D3 — Relation extraction's *scope* is the document, not a chunk

Phase 2 reasons over the document's consolidated entity graph rather than one
chunk, which is what recovers cross-chunk edges. "Document-level" means the
document is the **resolution scope** — it does **not** mean the whole document
(or all entities and their contexts) is stuffed into a single prompt. How the
work is partitioned within that scope is governed by D5.

### D5 — Partition relation extraction by locality (overlapping windows)

Feeding all entities + contexts into one call has two failure modes:

1. **Context-window overflow** (unlikely, but possible for pathologically large
   docs). The Phase 2 input scales with the *number of entities and the size of
   their contexts*, not raw document length, so this is rarer than it first
   appears.
2. **Needle-in-a-haystack / lost-in-the-middle** (the binding constraint). Even
   when the input fits the window, recall degrades for items buried in a large
   input, and *n* entities create ~*n²* candidate pairs that dilute the model's
   attention. A bigger context window does **not** fix this — scale itself
   lowers per-pair recall.

Therefore relation extraction is partitioned into **overlapping positional
windows**, not fed whole and not split by arbitrary size:

- Entities are ordered by document position (first `line_span`) and grouped into
  windows. Each window's entities + their `entity_context` form one relation
  call.
- **Adjacent windows overlap** (default **10 lines**, tunable) so a relation
  whose two entities straddle a window boundary is still captured by the window
  that contains both.
- Two entities that never share a window are **not connected** — long-range
  relations are deliberately out of scope (see "Accepted trade-off" below).

This deliberately drops the earlier relatedness/keyword/anchor candidate-
generation machinery in favor of **pure positional locality**. It is simpler,
bounds context size (mitigates failure 1), and keeps each call short and
needle-rich (mitigates failure 2). It still improves on the status quo because a
window spans **more than one chunk** and overlaps its neighbors, so the
cross-*chunk* relations the current per-chunk design loses are recovered;
only cross-*document* (far-apart) relations are forgone.

**Accepted trade-off — ignoring far-apart relations (Q2/Q3).** A relation is
almost always asserted locally: the text stating "A relates to B" names A and B
near each other. A relation between entities that never co-occur nearby is not
*stated* in the document — extracting it would be inference, not extraction,
which is out of scope. The residual risk is long-range coreference (one entity
discussed in distant sections); window overlap covers boundary cases but not
truly distant ones. We accept this loss as small and revisit only if downstream
graph completeness proves insufficient.

Window size and overlap are governed by env vars (e.g. `RELATION_WINDOW_SIZE`,
`RELATION_WINDOW_OVERLAP`, default overlap 10 lines); concrete defaults are an
implementation tuning task, not a fixed part of this decision.

### D6 — Where entity consolidation (Phase 1.5) lives

Entity consolidation is a **dedicated, separately-testable step** (its own
function and logging) executed **inline within the existing
`EntityRelationProcessor.HandleEvent`** — *not* a new doc processor wired to a
new event.

Rationale: consolidation has no consumer other than this processor's own Phase 2
and produces no independently useful artifact, so a separate event/processor
would add plumbing (event emission, status tracking, ordering guarantees)
without benefit. Keeping it inline guarantees it runs to completion before
relation extraction starts (D2). Making it a distinct function (rather than
inlined logic) keeps it unit-testable and lets it move to its own processor
later if a second consumer ever appears.

### D4 — Resolution policy: mark unresolved endpoints, don't drop

**What "endpoint" and "provisional entity" mean.**
A relation (edge) is `subject — predicate — object`; its **two endpoints are the
subject and the object**. "An endpoint matches no consolidated entity" means that
for *one* of those two, the surface string the relation LLM returned does not
resolve to any entity in the consolidated set (checked exact → alias →
normalized). Both endpoints *should* map to Phase-1 entities — the Phase 2 prompt
explicitly says "connect only entities in this list" — so a **provisional
entity** is a signal that this expectation was violated. Typical causes:

- the model named an endpoint not in the list (it read the entity's `context`
  text, which mentions many things, and pulled in a name never extracted as an
  entity);
- the model used a variant/surface form the resolver did not match (a missing
  alias);
- Phase 1 genuinely missed that entity.

A large provisional count for a document is therefore a quality signal worth
investigating, not just bookkeeping (it usually points at Phase-1 entity recall
or the relation prompt over-reaching beyond the supplied list).

**Resolution mechanics:**

- Normalizer resolves each relation endpoint against the consolidated entity set
  by exact match, then alias / `entity_en` match, then normalized
  (case/whitespace-folded) match.
- **Unresolved endpoints are marked, not dropped.** When an endpoint (from
  an edge) matches no
  consolidated entity, a **provisional entity** row is created in `kb.entities`
  for the surface string so the relation still links to a real `entity_id`. The
  provisional row is flagged via a **new `kb.entities` field**
  `entity_status TEXT NOT NULL DEFAULT 'extracted'`, set to `'provisional'` for
  these auto-created endpoints.
- This keeps every relation entity-linked (D1) while making the unlinked-ness
  inspectable: provisional entities (and the relations that reference them) can
  be listed for review or downstream filtering with
  `WHERE entity_status = 'provisional'`. Counted in the doc-proc summary as
  `provisional_entities`.
- Rationale for marking over dropping: a dropped relation is silently lost,
  whereas a flagged provisional entity preserves the edge *and* surfaces the
  consolidation gap (often a missed alias) for correction.

### Change 02

---

## Alternatives Considered

- **Keep the single combined per-chunk call (status quo).** Rejected as the
  target design: it leaves relations un-linked and structurally cannot capture
  cross-chunk relations. Acceptable only as a cheap baseline.
- **Split into two calls *within* each chunk (entities, then relations, both
  per-chunk).** Fixes entity-linking but still loses cross-chunk relations and
  doubles call count without the document-level benefit. Rejected in favor of D2/D3.
- **Single combined call, but feed prior entity list back as a prompt hint.**
  A cheaper middle step that improves linking without a separate phase. Viable
  as an interim measure but does not address cross-chunk relations; treated as a
  fallback, not the decision.
- **Post-hoc fuzzy linking of free-text triples to entities after extraction.**
  Rejected as the primary mechanism: matching is lossy and produces exactly the
  dangling/ambiguous edges this ADR aims to eliminate. The resolver in D4 is a
  safety net, not the source of truth.
- **Single whole-document relation call (all entities + contexts in one prompt).**
  Rejected: even when it fits the context window, lost-in-the-middle and *n²*
  pair dilution depress recall (see D5).
- **Naive size-based batching (split entities into equal groups).** Rejected: it
  bounds context but re-creates the cross-chunk blind spot when nearby entities
  fall in different batches. D5's *overlapping positional windows* are used
  instead.
- **Relatedness/keyword/anchor candidate generation.** Considered (an earlier
  draft of D5) to capture long-range edges via shared keywords and a global
  anchor set. Rejected for simplicity: per Q2/Q3 we accept forgoing far-apart
  relations, which makes pure positional windowing sufficient and far cheaper to
  build and reason about.
- **Reuse the `INPUT_BLOCK_SIZE` page-block as the relation window.** A
  page-block (20 pages) is a plausible *positional* window, but it is sized for
  metadata extraction and is likely too large for the needle problem, and it is
  not entity-aware. Relation windows are sized independently (D5); alignment with
  block/chunk sizing can be revisited during tuning.

---

## Consequences

- `kb.relations` gains `subject_entity_id` / `object_entity_id`; relations
  become true graph edges that can be traversed and joined to `kb.entities`.
- `kb.entities` gains `entity_status` (`'extracted'` | `'provisional'`); every
  relation stays entity-linked, and unlinked endpoints become inspectable rather
  than silently lost (D4).
- Relation extraction becomes *N* small, locality-windowed calls (D5) instead of
  the per-chunk relation portion; each call is focused with smaller output. Cost
  scales with window count, not *n²* entity pairs.
- Cross-*chunk* relations become expressible; cross-*document* (far-apart)
  relations are deliberately forgone (accepted trade-off, D5).
- Entity consolidation/deduplication becomes a required step (Phase 1.5) before
  relation extraction (new work; previously entities were saved per chunk
  without global merge).
- Migration required for the new columns; existing rows remain NULL/default
  until reprocessed with `force=true`.

---

## Implementation Status (2026-06-13)

**Landed** (build + unit tests green in `server/api/doc-processing`):

- **Migration** `project_migrations/20260613000002_add_entity_relation_linking.sql`:
  `kb.relations.subject_entity_id` / `object_entity_id`, `kb.entities.entity_status`
  (default `'extracted'`), plus indexes; mirrored in `ensureTables` DDL.
- **Persistence** (`extract-entity-relation.go`): `SaveRelations` writes the two
  entity-id columns; `SaveEntities` writes `entity_status`; artifact-file reads
  surface all three new columns. Status constants `entityStatusExtracted` /
  `entityStatusProvisional`.
- **Linking module** (`entity-relation-linking.go`, pure/testable):
  `consolidateEntities` (D6, union-find over name+alias surface forms, fullest
  name wins as canonical), `buildRelationWindows` (D5 positional overlapping
  windows), `buildEntityResolutionIndex` + `resolveAndLinkRelations` (D4 — link
  endpoints, mint provisional entities, dedup by
  `(subject_entity_id, predicate, object_entity_id)`).
- **Orchestration** (`HandleEvent`): Phase 1.5 consolidation → canonical
  `entity_id` assignment → `entity_context` build → endpoint resolution +
  provisional entities → relation-id assignment; logs
  `raw/consolidated/provisional` entity counts and `linked_relations`.
- **Tests** (`entity-relation-linking_test.go`): consolidation by name/alias,
  windowing (single/split/overlap), resolution dedup + provisional creation.

- **Phase 2 — windowed relation re-extraction (D5), now live):**
  - New relation-only prompt `prompts/prompt-extract-relations-v1.md`
    (env `EXTRACT_RELATION_PROMPT`) and contract `relationExtractionContract()`
    (`{language, relations}`).
  - `buildRelationWindows` is consumed by `extractRelationsFromWindows` /
    `processRelationWindow`: one entity-aware LLM call per overlapping window
    (input = `buildRelationWindowInputText`: entity roster id/name/type/aliases +
    the contiguous line-file **source text** for the window's page range — per
    Change 01, no longer per-entity `entity_context`), concurrent under
    `EXTRACT_ENTITY_RELATION_MAX_TASKS`, failed windows skipped.
  - Window sizing via env `RELATION_WINDOW_SIZE` (default **20 pages**, per
    Change 01) and `RELATION_WINDOW_OVERLAP` (default **20 lines**). Each window's
    LLM input is the entity roster plus the contiguous line-file text for the
    window's page range (Change 01); per-entity `entity_context` is no longer
    embedded in the relation input.
  - The shared extractor path was refactored into
    `extractStructuredWithFallback` / `extractStructuredPayload` so the entity
    and relation calls reuse the same primary/fallback model policy.
  - In `HandleEvent`, Phase 2 replaces the per-chunk relations before linking;
    if the relation prompt is unavailable or the pass fails, it **falls back**
    to the per-chunk relations so relations are never lost.
  - **Phase 1 is entity-only.** New prompt `prompts/prompt-extract-entity-relation-v3.md`
    (the code default for `EXTRACT_ENTITY_RELATION_PROMPT`; set the env var to v3)
    and a matching `entityExtractionContract()` (`{language, entities}`). The
    relation-output tokens Phase 1 used to spend are reclaimed, and Phase 2 is now
    the sole relation source.
  - **The relation prompt has no code default.** It is supplied solely via
    `EXTRACT_RELATION_PROMPT`. When unset, `RelationPromptErr` is non-nil and
    Phase 2 is skipped with a warning (no relations are produced).
  - **Relation line grounding is derived from endpoints.** The Phase 2 window
    input carries entity *context text* but not line numbers, so the model
    cannot cite `lines`. `resolveAndLinkRelations` therefore sets each relation's
    `line_spans` to the union of its subject/object entities' spans
    (`relationSpansFromEndpoints`). Without this, relations persist with empty
    `line_spans`, and search indexing logs "empty chunks" / "empty
    semantic_projects" and cannot index the edge.
  - **Provisional entities are grounded from referencing relations.** Provisional
    entities are minted with no `line_spans` of their own;
    `backfillProvisionalEntitySpans` sets each one to the union of the spans of
    the relations that reference it, so they index cleanly. A provisional entity
    referenced only by spanless relations stays ungrounded (no document evidence).

**Notes / follow-ups:**
- `RELATION_WINDOW_SIZE` is interpreted in **document pages** (default 20) as of
  Change 01 (2026-06-14); `RELATION_WINDOW_OVERLAP` remains in lines (default 20).
  Tune on real docs.
- Required env for the two-phase flow:
  - `EXTRACT_ENTITY_RELATION_PROMPT=prompt-extract-entity-relation-v3.md` (entity-only)
  - `EXTRACT_RELATION_PROMPT=prompt-extract-relations-v1.md` (relations; **no default**)
  - both files present in `PROMPT_DIR`.

---

## Implementation Notes (to be detailed when Status → Accepted)

- **Migration:**
  `ALTER TABLE kb.relations ADD COLUMN IF NOT EXISTS subject_entity_id TEXT, ADD COLUMN IF NOT EXISTS object_entity_id TEXT`;
  `ALTER TABLE kb.entities ADD COLUMN IF NOT EXISTS entity_status TEXT NOT NULL DEFAULT 'extracted'`;
  matching `ensureTables` DDL updates in `EntityRelationSQLStore`.
- **Entity consolidation (Phase 1.5, D6):** dedicated, separately-testable
  function called inline from `HandleEvent` after Phase 1, producing a canonical
  `entity_id` per distinct entity (alias-aware), before relation extraction.
- **Windowing (D5):** order consolidated entities by first `line_span`, form
  positional windows with overlap; env vars `RELATION_WINDOW_SIZE` and
  `RELATION_WINDOW_OVERLAP` (default overlap 10 lines). Each window → one Phase 2
  call carrying that window's entity list with materialized `entity_context`.
- **Phase 2 prompt:** new relation prompt constrained to the window's entity
  list.
- **`normalizeRelationRows`:** resolve `subject`/`object` to `entity_id` per D4;
  create + flag a `'provisional'` entity for unresolved endpoints.
- **`SaveRelations` / `SaveRelationsRequest`:** carry and persist
  `subject_entity_id` / `object_entity_id`.
- **De-duplication:** a relation may surface in two overlapping windows; dedupe
  by `(subject_entity_id, predicate, object_entity_id)` before insert.
- **Logging:** add `provisional_entities` to the doc-proc summary.

---

## Open Questions

- ~~Concrete defaults for `RELATION_WINDOW_SIZE` (and whether it is expressed in
  lines, chars, or chunks)~~ → Resolved by Change 01 (2026-06-14):
  `RELATION_WINDOW_SIZE` is in **pages** (default 20); `RELATION_WINDOW_OVERLAP`
  in **lines** (default 20). Exact page count remains a tuning task on real docs.
- Entity ordering within a window when an entity's `line_spans` cover multiple
  distant regions — order by first span, or place the entity in every window its
  spans touch?
- Provisional-entity hygiene: should provisional rows be periodically re-checked
  against the consolidated set (e.g. a later doc revision adds the missing
  alias), and merged?

### Resolved since first draft

- *Where entity consolidation lives* → D6 (dedicated step, inline in the existing
  processor).
- *Candidate-generation thresholds / anchor-set bounding / block overlap* →
  obviated by D5's switch to positional windows; far-apart relations are
  accepted as out of scope (Q2/Q3), and window overlap is fixed at 10 lines (Q4).
- *Drop vs. quarantine for unresolved endpoints* → D4: mark via a provisional
  entity (`entity_status`), never drop (Q5).

---

## References

[1] 2026061201-adr-entity-amend.md — Entity context, doc_name, categories, search.

[2] 2026061207-spec-extract-entities-relations.md — Extraction spec.
