# ADR 2026061201 — Entity

**Date:** 2026-06-12  
**Status:** Implemented  
**Component:** Doc Processor - Entities

---

## Context

Entities are extracted by the doc processor (refer to [1]).
Entities are stored in the table `kb.entities`.

---

## Decision
* `kb.entities.source_line_spans` is not used now. Need to be removed. If there is code that accesses the field, it should access `kb.entities.line_spans` instead.
* `kb.entity.line_spans` is an array of `<line_range>`, which is either an individual line or a range of continuous lines. Group all its `<line_range>` by their chunks. For each chunk, retrieve `<chunk_context>` = `<chunk_summary>` + [`<leading_lines>` + `<line_range>`], where `<leading_lines>` is the ARTIFACT_CONTEXT_SIZE lines prior to `<line_range>`. 
the entity has multiple `<line_range>`, separate the elements `<context>` with two '\n'. 
* Add field `kb.entity.entity_context` (text) to save all its `<chunk_context>` to it, separate them by '\n\n', if there are multiple `<chunk_text>`.
* Add field `kb.entity.doc_name` (text). Populate `kb.inputs.title` to it.
* Retrieve the keywords from all the `kb.summaries.keywords` and `kb.summaries.keywords_en` and add them to `kb.entities.search_document`

### Changes - 2026/06/13

#### Change 01
Original:
```text
* `kb.entity.line_spans` is an array of `<line_range>`, which is either an individual line or a range of continuous lines. Group all its `<line_range>` by their chunks. For each chunk, retrieve `<chunk_context>` = `<chunk_summary>` + [`<leading_lines>` + `<line_range>`], where `<leading_lines>` is the ARTIFACT_CONTEXT_SIZE lines prior to `<line_range>`. 
```

Change: "`<chunk_context>` = `<chunk_summary>` + ..." to: "`<chunk_context>` = 'Summary: ' + `<chunk_summary>` + ..."

#### Change 02
Retrieve the keywords from the chunk's semantic projection and add them to `kb.entities.search_document`.

#### Change 03
* Add `kb.entities.categories` field.

#### Change 04
Added `entity_categories` and `relation_categories` fields, which are array of one or more categories 
returned from the LLM.

Populate `entity_categories` to `kb.entities.categories`.

### Changes - 2026/06/14
Do not 

---

## Implementation

### Migration
`project_migrations/20260612000003_add_entity_context_doc_name_to_kb_entities.sql`
- Drops `source_line_spans` from `kb.entities` if it exists (no-op; the column was never added).
- Adds `entity_context TEXT` and `doc_name TEXT` to `kb.entities`.
- The `ensureTables` DDL in `EntityRelationSQLStore` was updated to match (with `ADD COLUMN IF NOT EXISTS` guards).

`project_migrations/20260613000001_add_categories_to_kb_entities.sql` *(2026-06-13 amendment)*
- Adds `categories JSONB` to `kb.entities`.

### Schema changes
- `DocMetadataInputRecord` gained a `Title string` field; all three SQL queries in `extract-doc-metadata-store.go` (`GetInputRecord`, `ListParsedInputRecords`, `ListRecordsWithFailedDocProcessors`) were updated to fetch `COALESCE(title, '')`.

### Store interface additions (`EntityRelationStore`)
Three new methods on `EntityRelationSQLStore`:
- `GetChunkSummaries(ctx, inputRecordID) map[int]string` — queries `kb.summaries` (level 0) and returns a `seqNo → summaryText` map.
- `AppendSummaryKeywordsToEntitySearch(ctx, inputRecordID)` — queries all `kb.summaries.keywords` / `keywords_en` for the record, deduplicates, and does a direct `UPDATE kb.entities SET search_document = concat_ws(' ', …), search_vector = to_tsvector(…)` that bypasses the entity-specific trigger (which only fires on updates to entity name/type/keyword columns).
- `AppendSemanticProjectionKeywordsToEntitySearch(ctx, inputRecordID)` *(2026-06-13)* — same pattern as above but reads `kb.semantic_projections.keywords` / `keywords_en` for the record.

### Entity context building
`buildEntityContextForEntities(entities, chunks, allLines, chunkSummaries, contextSize)`:
1. Builds a `lineNo → Line` map and a `lineNo → chunk.SeqNo` map from the loaded chunks.
2. For each entity, groups its `line_spans` by chunk (falls back to the entity's own `chunk_seq_no` if the span's start line isn't in any loaded chunk).
3. For each chunk group: prepends `"Summary: " + chunk summary text` *(2026-06-13: "Summary: " prefix added)*, then for each span appends up to `contextSize` leading document lines followed by the span lines.  Multiple spans within a chunk are separated by `\n\n`; multiple chunk-contexts are also separated by `\n\n`.
4. Sets `entity["entity_context"]` in-place before `SaveEntities` is called.

`contextSize` is read from the `ARTIFACT_CONTEXT_SIZE` environment variable (default 3).

### LLM response normalization *(2026-06-13)*
- `normalizeEntityRows` now picks up `entity_categories` from the LLM response and stores it as `[]string` under the key `"entity_categories"`.
- `normalizeRelationRows` now picks up `relation_categories` similarly (stored in-memory; no DB column exists for relations yet).

### HandleEvent orchestration changes
After LLM extraction and entity ID assignment:
1. Call `GetChunkSummaries` → pass to `buildEntityContextForEntities`.
2. `SaveEntitiesRequest` now carries `DocName` (from `rec.Title`); `SaveEntities` inserts it into `doc_name`.
3. `SaveEntities` inserts `entity_categories` into `kb.entities.categories` (JSONB). *(2026-06-13)*
4. After entities are saved, call `AppendSummaryKeywordsToEntitySearch`; failures are logged as warnings (non-fatal).
5. After step 4, call `AppendSemanticProjectionKeywordsToEntitySearch`; failures are logged as warnings (non-fatal). *(2026-06-13)*

### Files changed
- `project_migrations/20260612000003_add_entity_context_doc_name_to_kb_entities.sql` (new)
- `project_migrations/20260613000001_add_categories_to_kb_entities.sql` (new, 2026-06-13)
- `server/api/doc-processing/extract-doc-metadata-store.go`
- `server/api/doc-processing/extract-entity-relation.go`
- `server/api/doc-processing/extract-entity-relation_test.go`

---

## Alternatives Considered

- **Trigger-based `search_document` update for summary keywords**: rejected because a trigger cannot efficiently JOIN another table. Direct `UPDATE` after insert bypasses the trigger without side effects since the trigger only fires on writes to the entity's own searchable columns.
- **Storing `entity_context` in a separate table**: rejected; a single TEXT column on the row keeps reads simple.

---

## Consequences

- All new entity rows carry a pre-computed `entity_context` and `doc_name`.
- `kb.entities.search_document` now includes the record's summary keywords, improving full-text search recall.
- `ARTIFACT_CONTEXT_SIZE` (env var, default 3) controls how many leading lines precede each cited line range in the context.
- Existing rows remain NULL for the new columns until re-processed with `force=true`.

## Test Cases

- `TestParseLineSpanRange` — covers single line, range, colon separator, invalid inputs.
- `TestBuildEntityContextForEntities` — verifies `"Summary: "` prefix + summary text, leading line, and span line all appear in output.
- `TestBuildEntityContextForEntities_NoSpans` — verifies no key is set for entities with empty spans.
- `TestNormalizeEntityRowsCategories` *(2026-06-13)* — verifies `entity_categories` is populated from the LLM response and defaults to empty when absent.

## References
[1] 2026061207-spec-extract-entities-relations.md