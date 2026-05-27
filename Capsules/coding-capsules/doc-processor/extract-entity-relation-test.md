# Extract Entity & Relation Processor — Test Plan

Lives in `ChenWeb/server/api/doc-processing/extract-entity-relation_test.go`. All tests are Go unit tests using `testing` plus the patterns established in the neighboring `extract-structured-knowledge_test.go` and `extract-metrics_test.go` files.

## Test Helpers Reused

- `fakeJSONExtractor` / `fakeStructuredJSONExtractor` from `extract-doc-metadata_test.go` for stubbing the LLM client.
- `DocMetadataInputRecord` fixture builder pattern from the structured-knowledge tests.
- `discardLogger` (or `loggerutil.CreateDefaultLogger` for the trivial case).

## Unit Tests

### 1. `Test_normalizeEntityRows`

Given a raw `[]any` payload as returned by the LLM, with mixed valid and invalid items (missing `entity`, empty string, non-map entries), assert:

- empty / missing-name items are dropped,
- `keywords` / `keywords_en` / `aliases` / `aliases_en` are normalized via `toStringSlice` (trimming, dropping empties),
- `source_line_spans` is normalized to canonical form (`"12"`, `"13:15"`).

### 2. `Test_normalizeRelationRows`

Same as above for relations; additionally:

- a relation with empty `subject`, `predicate`, OR `object` is dropped,
- `predicate` is normalized to lowercase snake_case in the returned row.

### 3. `Test_entityRelationLanguageDetection`

Given two chunk responses where the first has `language = ""` and the second has `language = "zh"`, after processing assert:

- the resulting `language` is `"zh"`,
- `_en` fields ARE populated in the inserts (non-English language).

Given a single chunk response with `language = "en"`, assert:

- the resulting `language` is `"en"`,
- `_en` fields are NOT populated (NULL passed for text columns, empty JSONB for array columns).

### 4. `Test_entityRelationIDAssignment`

Given a payload with three entities in chunk A and two in chunk B, assert:

- entity_ids are `<record_id>_e_1` through `<record_id>_e_5` in order,
- relation_ids restart at `_r_1` independently from entities.

### 5. `Test_entityRelationFallbackOnPrimaryError`

Set up the fake extractor so the first call returns an error and the second call (fallback model) succeeds. Assert:

- the chunk's rows come from the fallback response,
- a `Warn` log is recorded with `primary_model` and `fallback_model` keys,
- the processor's overall status entry is `success`.

### 6. `Test_entityRelationSkipChunkOnBothFailures`

Set up the fake extractor so both primary and fallback error. Assert:

- the chunk's rows are absent from the final insert request,
- the processor's overall status entry is still `success` (chunk-level errors don't abort the run),
- a `Warn` log is recorded.

### 7. `Test_entityRelationFailedWhenPromptMissing`

Construct a processor where `PromptErr` is non-nil. Call `HandleEvent` with a valid event. Assert:

- the function returns a non-nil error wrapping `MID_<id>`,
- no rows are inserted.

### 8. `Test_entityRelationStatusUpsertReplaces`

Pre-seed `rec.StatusRaw` with an existing `extract_entity_relation` entry. After a successful run, assert:

- the status array still contains exactly one `extract_entity_relation` entry,
- its `proc_status` is `"success"` and `start_time` matches the new run.

### 9. `Test_appendEntityRelationStatusNewEntryAppended`

Pure unit test of `appendEntityRelationStatus`: given a status array without an `extract_entity_relation` entry, the result has one appended at the end with the right shape.

### 10. `Test_saveEntitiesToFileAndSaveRelationsToFile`

Use `t.TempDir()` as `ARTIFACT_DIR`. Run `saveEntitiesToFile` and `saveRelationsToFile` with a sample `rec` and 2 rows each. Assert:

- the directory `<tmp>/0/<recordID>` exists,
- `<filename_root>_<parser_name>.entities` exists and unmarshals back to the same slice,
- `<filename_root>_<parser_name>.relations` likewise,
- writing again overwrites cleanly.

### 11. `Test_entityRelationIdempotentWithoutForce`

Set the store stub so `EntitiesExist` returns `true` and `force = false`. Assert:

- `HandleEvent` returns nil,
- no LLM call is made,
- the status entry is `"success"`.

### 12. `Test_entityRelationDeletesOnForce`

Set `force = true`. Assert:

- both `DeleteEntitiesByInputRecordID` and `DeleteRelationsByInputRecordID` are called BEFORE any insert,
- the inserts then proceed.

## Integration-ish Tests (still in the same `*_test.go`)

### 13. `Test_entityRelationContractParsesPromptOutput`

Use `entityRelationExtractionContract()` and feed it the JSON shape documented in the prompt. Assert it parses without errors and surfaces the `entities` / `relations` arrays. Mirrors `Test_metricsExtractionContract` patterns.

### 14. `Test_buildEntityRegistryRows` and `Test_buildRelationRegistryRows`

Use `sqlmock` (consistent with how other `build*RegistryRows` are tested elsewhere — check the existing test file for the exact helper; if `sqlmock` is not in this package, follow the pattern used by `buildKnowledgeRegistryRows` tests). Assert:

- `ArtifactType` is `"entity"` / `"relation"`,
- `PrimaryLabel` falls back to the ID when `entity` / `subject` is empty,
- `SearchDocument` falls back to a concatenation when the stored column is empty,
- `CategoryPaths` is the literal `[]` JSON.

## Manual / End-to-End Smoke

After `mise build-server` succeeds:

1. Run `go test ./server/api/doc-processing/...`.
2. Start the doc-processor binary against a local Postgres with the new migration applied (`mise migrate` or whatever the project uses).
3. Publish a `kb.line-file-generated` event for a record whose `.chunks` artifact exists. Confirm:
   - rows appear in `kb.entities` and `kb.relations`,
   - `.entities` and `.relations` files appear under the expected artifact path,
   - the dashboard renders an `Extract Entity/Relation` stage that goes from pending → success,
   - `SELECT artifact_type, COUNT(*) FROM kb.search_artifacts WHERE input_record_id = $1 GROUP BY 1` includes `entity` and `relation` rows.

## What This Test Plan Intentionally Does NOT Cover

- Real LLM correctness or accuracy on real documents — out of scope for unit tests.
- The shared Postgres schema migrations themselves — covered by the project's migration tests.
- Translation quality — the prompt explicitly allows skipping `_en` fields and a downstream translation pass MAY be added.
