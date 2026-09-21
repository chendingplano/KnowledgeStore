# 2026092201-bug — Merged pass returned 0 rows for every chunk and wiped record 416

**Status:** Fixed 2026-09-22
**Component:** `ChenWeb/server/api/doc-processing/extract-products.go`, merged-pass mode
**Severity:** High — silent data loss (1219 `kb.products` rows deleted, run reported success)

## Symptom

The first real run of `EXTRACT_PRODUCTS_MERGED_PASS=true` on record 416
(`req=e-e5cc9191`, 2026-09-22 07:47) logged `rows="0"` for all 10 chunks
despite healthy token counts (`output_tokens` 15k–19k, `ms_used` ~67s each),
then:

```
search registry reindexed  deleted_rows="1219" inserted_rows="0"
products extracted         record_id="416" inserted_rows="0" products_count="0"
finish processing request  proc_status="success"
```

Record 416's 1219 existing product rows were deleted and nothing replaced
them. The run was recorded as a **success**.

## Root cause

`extractProductsMergedForChunk` built its task suffix with
`buildProductMentionsTaskPrompt(block.Index)` — Pass 1's builder, which ends
with:

```text
Return JSON only. Use exactly this top-level schema:
{"mentions":[{...}]}
```

That suffix is the *last* thing in the prompt, so it overrode the merged
prompt's own `## Output JSON Schema` (`{"products": [...]}`). The model
complied and returned `{"mentions": [...]}` — 22 mentions on the chunk
inspected (`llm-0bae6083`). The code then read `payload["products"]`, found
nothing, and produced 0 rows.

Two things made the failure silent rather than loud:

1. **`productExtractionContract()` accepts either key.** It is an `anyOf` over
   `["products"]` / `["mentions"]` (`llm_contracts.go:297`), so the
   mention-shaped payload validated cleanly — no parse error, no retry, no
   provider error.
2. **A zero-row result is indistinguishable from an empty document.**
   `FinalizeChunkBatch` force-deletes the record's existing rows *before*
   saving, so 0 rows means "delete everything and insert nothing", and the
   status is written as success.

## Fixes

1. **`buildMergedProductsTaskPrompt`** — new task-suffix builder emitting the
   `products` relation schema plus the block index. The merged pass uses it
   instead of Pass 1's builder.
2. **Shape guard** — if a merged call returns a payload with `mentions` and no
   `products`, `extractProductsMergedForChunk` now returns an error naming the
   mismatch instead of contributing 0 rows quietly.
3. **All-chunks-failed guard** — `FinalizeChunkBatch` counts merged chunk
   failures (`batchMergedFailures`). Individual chunk failures stay non-fatal,
   but if *every* chunk failed the record fails before reaching the
   force-delete, so a broken run can no longer overwrite good data with
   nothing.

Regression tests: `TestBuildMergedProductsTaskPrompt_PinsProductsSchema`,
`TestExtractProductsMergedForChunk_RejectsMentionShapedPayload`.

## Verification

The 10 archived failing requests were replayed against `api.deepseek.com`
with the corrected suffix (the exact bytes the fixed builder emits). All 10
returned `keys=['products']`; row counts 6/14/54/10/18/12/2/3/52/1 = **172
rows**, 83,005 completion tokens.

## Still open

- **Record 416 must be re-run** — its rows are gone (`SELECT count(*) FROM
  kb.products WHERE input_record_id=416` returns 0) and the search registry
  index for it was cleared.
- **The force-delete-then-save window is not merged-specific.** Any run of
  either pipeline that legitimately reaches the save step with 0 rows will
  still wipe the record and report success. The guard added here only covers
  "every merged chunk errored". Deciding whether a zero-row save should ever
  be allowed to replace a non-empty record is a separate design question.
