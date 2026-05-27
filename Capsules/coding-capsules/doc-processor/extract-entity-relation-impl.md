# Extract Entity & Relation Processor — Implementation Notes

Companion to [extract-entity-relation-spec.md](extract-entity-relation-spec.md). This file documents the actual Go layout, helpers used, the migration shape, and the dashboard wiring.

## File Map

| Path | Purpose |
|---|---|
| `ChenWeb/prompts/prompt-extract-entity-relation-v1.md` | Single-pass extraction prompt |
| `ChenWeb/server/api/doc-processing/extract-entity-relation.go` | Processor, store, prompt builder, file writer |
| `ChenWeb/server/api/doc-processing/extract-entity-relation_test.go` | Unit tests |
| `ChenWeb/server/api/doc-processing/llm_contracts.go` | Adds `entityRelationExtractionContract()` |
| `ChenWeb/server/api/doc-processing/search_indexing.go` | Adds `searchArtifactEntity`, `searchArtifactRelation`, plus `ReindexEntitySearchForRecord` / `ReindexRelationSearchForRecord` and `buildEntityRegistryRows` / `buildRelationRegistryRows` |
| `ChenWeb/server/cmd/doc-processor/main.go` | Registers `NewEntityRelationProcessor` and creates its dedicated LLM client |
| `ChenWeb/config.toml` | Adds `extract_entity_relation` under `[doc-processing].required_processors` |
| `ChenWeb/project_migrations/20260527000010_create_kb_entities_relations_tables.sql` | Creates `kb.entities`, `kb.relations`, search triggers, and `search_artifacts` partitions |
| `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-state.ts` | Adds the `extract_entity_relation` stage and ID |
| `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` | Pipeline row, status JSON, and required-processors example |
| `KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-dashboard-impl.md` | `ALL_PROCESSOR_IDS` and `PIPELINE_FINAL_OPS` lists |

## Processor Shape

`EntityRelationProcessor` mirrors `StructuredKnowledgeProcessor` but with a **single LLM call per chunk**, no enrichment pass, and no category-paths indexing. It does NOT use `BlockBufferFromContext` — it operates on the chunk artifact, like `extract_structured_knowledge` and `extract_semantic_projections`.

Construction (`NewEntityRelationProcessor`):

```go
promptText, promptRef, promptPath, promptErr := loadProductPromptFromEnvKeys(
    []string{"EXTRACT_ENTITY_RELATION_PROMPT"},
    "prompt-extract-entity-relation-v1.md",
)
modelRef, modelCfgPath, modelCfg, modelErr := loadModelConfigFromEnvKeys(
    []string{"EXTRACT_ENTITY_RELATION_MODEL_NAME"},
    "MODEL_DEF_FILE",
)
fallbackModelRef, fallbackModelCfgPath, fallbackModelCfg, fallbackModelErr := loadOptionalModelConfigFromEnv(
    "EXTRACT_ENTITY_RELATION_FALLBACK",
    "MODEL_DEf_FILE",
)
```

Notes:

- The fallback env var is **`EXTRACT_ENTITY_RELATION_FALLBACK`** (no `_MODEL_`), per the requirements. Internally we still pass it through `loadOptionalModelConfigFromEnv` which only cares about the env var name.
- We apply the chosen model config to the extractor with `applyStructureModelConfigToExtractor` so the shared LLM client picks up `thinking`, `temperature`, etc. We do NOT force `ThinkingType = "disabled"`; the prompt is small enough that the default config wins.

### Event handling

`HandleEvent` follows the structured-knowledge processor exactly except:

- it loads only one prompt and one primary model (plus optional fallback),
- after persisting rows it calls `ReindexEntitySearchForRecord` AND `ReindexRelationSearchForRecord`,
- it does NOT call any tree-indexing helper.

`Name()` returns `"extract_entity_relation"`.

### Per-chunk LLM call

```go
for idx, chunk := range chunks {
    chunkText := buildMarkedChunkInputText(chunk.Lines)
    payload, modelName, err := p.extractEntityRelationWithFallback(ctx, chunkText)
    if err != nil { /* warn, skip chunk */ continue }
    if payload == nil { continue }

    if lang := strings.TrimSpace(asString(payload["language"])); lang != "" && detectedLanguage == "unknown" {
        detectedLanguage = lang
    }
    entities = append(entities, normalizeEntityRows(payload["entities"], chunk.SeqNo)...)
    relations = append(relations, normalizeRelationRows(payload["relations"], chunk.SeqNo)...)
}
```

Fallback logic is the same as `extractKnowledgeCandidateWithFallback` in `extract-structured-knowledge.go`.

### Normalization

`normalizeEntityRows` and `normalizeRelationRows` perform the same trimming + `toStringSlice` + `normalizeSourceLineSpans` work as the metrics normalizer. Spans accept both `"12"` and `"12-15"` (per spec) but on insert we re-emit them via `normalizeSourceLineSpans` which uses `":"`-separator output (e.g., `"12:15"`). Either form is accepted upstream.

ID assignment is global across chunks:

```go
for i := range entities { entities[i]["entity_id"] = fmt.Sprintf("%d_e_%d", recordID, i+1) }
for i := range relations { relations[i]["relation_id"] = fmt.Sprintf("%d_r_%d", recordID, i+1) }
```

### Persistence

`EntityRelationSQLStore` exposes:

- `EntitiesExist(ctx, recordID) (bool, error)`
- `DeleteEntitiesByInputRecordID(ctx, recordID) (int64, error)`
- `SaveEntities(ctx, SaveEntitiesRequest) (int64, error)`
- `RelationsExist(ctx, recordID) (bool, error)`
- `DeleteRelationsByInputRecordID(ctx, recordID) (int64, error)`
- `SaveRelations(ctx, SaveRelationsRequest) (int64, error)`

Both `Save*` insert one row at a time inside a single SQL connection (no explicit transaction; matching how `MetricsSQLStore` writes). When `language` is English we skip the `_en` columns by passing `NULL` for text fields and the literal `null` JSON for JSONB columns. Columns are NULLable.

### File output

`saveEntitiesToFile` and `saveRelationsToFile` write pretty-printed JSON arrays:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.entities
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.relations
```

The file content includes every column except the auto / search columns (`id`, `search_document`, `search_vector`, `create_time`). Failing to write the artifact file is logged at `Warn`; it does not fail the processor (matching `extract_metrics`).

### Search reindex

Both `Reindex*ForRecord` helpers are added to `search_indexing.go` and:

- `SELECT id, entity_id, language, entity, entity_en, entity_type, desc, desc_en, keywords, keywords_en, source_line_spans, search_document FROM kb.entities WHERE input_record_id = $1 ORDER BY id`
- ...and analogous for `kb.relations`.

Each row becomes a `kbsearch.RegistryRow` with:

- `ArtifactType = "entity"` / `"relation"`
- `ArtifactID = BuildArtifactID(recordID, "entity", lastDelimitedToken(entityID))`
- `PrimaryLabel = firstNonEmpty(entity, entityID)` (entities) or `firstNonEmpty(subject + " " + predicate + " " + object, relationID)` (relations)
- `SecondaryLabel = entity_type` (entities) or `predicate` (relations)
- `SearchDocument = firstNonEmpty(searchDoc, fallbackConcat)`
- `CategoryPaths = json.RawMessage("[]")` — entities and relations have no category paths
- `SourceLineSpans = json.RawMessage(source_line_spans_jsonb)`

`replaceRegistryRows` then deletes and inserts as usual.

### Status persistence

`persistEntityRelationStatus` decodes `rec.StatusRaw`, replaces any prior entry whose `operation == "extract_entity_relation"`, and writes back via `InputStore.UpdateInputMetadata`.

## Migration

`20260527000010_create_kb_entities_relations_tables.sql`:

- Creates `kb.entities` and `kb.relations` with all the columns from the spec, plus `search_document TEXT` / `search_vector TSVECTOR`.
- Creates `kb.entity_search_document(...)` and `kb.relation_search_document(...)` SQL functions that concatenate the searchable fields via `kb.search_jsonb_array_text` (reused from the existing hybrid-search migration).
- Creates per-table `BEFORE INSERT OR UPDATE OF ...` triggers that recompute both columns automatically.
- Creates `GIN` indexes on `search_vector` and btree indexes on `input_record_id` for both tables.
- Creates the `kb.search_artifacts_entity` and `kb.search_artifacts_relation` partitions of `kb.search_artifacts`, with the same partition-level GIN + btree indexes used by the other artifact types (`metric`, `provision`, etc.).
- Down migration drops everything created here, in reverse order.

We **do not** drop `kb.knowledges` or any existing table — this processor is purely additive.

## Registration

### `main.go`

Inside `func main`:

```go
entityRelationLLMClient := newLLMClient()
// ...
control := &docprocessing.ControlService{
    // ...
    Processors: []docprocessing.Processor{
        // existing entries...
        docprocessing.NewEntityRelationProcessor(
            inputStore,
            docprocessing.EntityRelationSQLStore{DB: ApiTypes.ProjectDBHandle},
            entityRelationLLMClient,
            logger,
        ),
    },
}
```

The `processors` log line at startup adds `"extract_entity_relation"` to the slice.

### `config.toml`

Add `extract_entity_relation` to `[doc-processing].required_processors`:

```toml
[doc-processing]
required_processors = [
    "extract_metrics", "extract_provisions", "generate_summaries",
    "generate_topics", "generate_scene_blocks", "extract_semantic_projections",
    "extract_structured_knowledge", "extract_entity_relation"
]
```

### Dashboard (`doc-processor-dashboard-state.ts`)

- Append `{ id: 'extract_entity_relation', label: 'Extract Entity/Relation', operations: ['extract_entity_relation'] }` to `PIPELINE_STAGES`.
- Append `'extract_entity_relation'` to `ALL_CONFIGURABLE_PROCESSOR_IDS`.

`isActiveRecord` is data-driven from those lists, so no additional change is needed.

## Coexistence With `extract_structured_knowledge`

Both processors stay registered. Operationally they extract overlapping information into different tables; downstream consumers can pick which surface to query. We do not delete `kb.knowledges` or change the existing extractor.

## Things We Intentionally Did NOT Do

- No multi-pass (candidate / enrich) extraction.
- No category-path generation, no `ARTIFACT_WEB_DIR` tree writes.
- No preview / save REST APIs (those exist for metrics; this processor is event-driven only).
- No backfill of historical records — running the processor again with `force=true` on an existing event is sufficient.
