# Review Report: Fix-Size Chunking Implementation

Date: 2026-04-30

## Scope

Reviewed against:

- `KnowledgeStore/DevDocuments/Specs/spec-chunking-fix-size.md`
- `KnowledgeStore/DevDocuments/Specs/spec-generate-chunk-summary.md`
- `KnowledgeStore/DevDocuments/Specs/spec-category-extraction.md`

Reviewed implementation:

- `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
- `ChenWeb/server/api/doc-processing/topic_chunking_shared.go`
- `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`
- `ChenWeb/server/api/doc-processing/semantic-chunking.go`
- `ChenWeb/server/api/doc-processing/chunking_test.go`
- `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`

## Executive Summary

The implementation covers the main happy-path pipeline: parse lines, build fixed-size chunks, write a `.chunks` artifact, extract topics per chunk, write `.topics`, generate per-chunk summaries, build a summary tree, update `kb.chunks`, and persist `kb.inputs.status`.

The biggest issues are not in the existence of the pipeline, but in **spec compliance**:

1. **Category extraction and storage are only partially implemented.** The code stores one normalized path per topic and one root-summary path per document, but it does not implement the category-extraction spec’s multi-path structure, metadata files, semantic directory matching, or per-summary categorization.
2. **Topic JSON parsing does not match the spec shape.** The implementation reads `keywords`, not `topic_keywords`, and cannot parse the documented nested `categories` payload.
3. **Topic and summary embeddings are specified but not implemented.**
4. **Chunk sizing is approximate rather than spec-accurate.** The byte budget is computed from a reduced line rendering, not the canonical line-file record, and canonical line validation is weaker than the spec implies.

## Findings

### High

1. **Topic category extraction does not implement the spec/prompt-defined category payload or multi-path behavior.**
   - Spec: the topic output includes `categories`, and category extraction is delegated to `spec-category-extraction.md`, which defines richer category structures and one-or-more category paths per artifact.
   - Prompt: the LLM is instructed via [`prompt-extract-categories.md`](../../ChenWeb/prompts/prompt-extract-categories.md), whose output format matches the spec’s nested `category_path` structure (`[{name, keywords, confidence}, ...]`) with `path_keywords` and `path_confidence` per path.
   - Code: [`extractTopicsFromLinesWithLLM`](../../ChenWeb/server/api/doc-processing/topic_chunking_shared.go) only extracts a single flat path from `category_path`, flat `categories`, `category`, or `topic_category` strings, then stores exactly one `[]string` in `TopicItem.CategoryPath` ([topic_chunking_shared.go:301-407](../../ChenWeb/server/api/doc-processing/topic_chunking_shared.go:301), [semantic-chunking.go:587-645](../../ChenWeb/server/api/doc-processing/semantic-chunking.go:587)). It does not parse the nested `category_path` objects, nor does it collect `path_keywords` or `path_confidence`.
   - Impact: if the LLM returns the spec/prompt nested category structure, or more than one category path, the implementation either drops the information or misparses it.

2. **Topic tree storage format does not match `spec-category-extraction.md`.**
   - Spec: topic categories should be stored as directories under `TOPIC_TREE_ROOT_DIR`, with metadata files such as `topic_meta.json`; workflow also describes semantic matching with existing directories.
   - Code: [`writeTopicsCategoryTreeToDir`](../../ChenWeb/server/api/doc-processing/topic_chunking_shared.go:218) writes leaf files like `category_a/category_b.txt` containing tab-separated rows, and creates no metadata files or similarity-based matching ([topic_chunking_shared.go:218-299](../../ChenWeb/server/api/doc-processing/topic_chunking_shared.go:218)).
   - The current tests explicitly lock in this simplified format, e.g. `document_overview/closing_notes.txt` ([chunking_test.go:253-259](../../ChenWeb/server/api/doc-processing/chunking_test.go:253)).
   - Impact: the persisted topic tree is materially different from the documented design.

3. **Summary category extraction/storage is much narrower than the summary/category specs.**
   - Spec: compose all summaries and summaries-of-summaries, run category extraction, create/update the summary file tree, create category metadata, and store/update summaries under category paths.
   - Code: the service generates **one** category path from the **root summary only**, then writes only the root summary ID into one `summaries.txt` leaf ([fix-size-chunking.go:353-363](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:353), [chunk_summary_shared.go:218-299](../../ChenWeb/server/api/doc-processing/chunk_summary_shared.go:218)).
   - No per-summary categorization, no `category_meta.json`, no similarity matching, and no summary content/time rows are written.
   - Impact: the implementation does not satisfy the spec’s “handle summaries” workflow; it implements a much smaller “index the root summary” behavior instead.

4. **Topic embeddings and summary embeddings are specified but not implemented.**
   - Spec: topic embeddings should be generated and stored (`.embed`), and summary embeddings should be generated as well.
   - Code: I did not find any implementation that calls an embedding model for topics or summaries in the fix-size pipeline. `SummaryItem` has an `Embedding` field, but it is never populated in this flow, and no `.embed` file is written ([chunk_summary_shared.go:25-34](../../ChenWeb/server/api/doc-processing/chunk_summary_shared.go:25), [fix-size-chunking.go:266-375](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:266)).
   - Impact: two explicit spec requirements are currently missing.

### Medium

5. **Topic JSON input parsing does not match the spec field names.**
   - Spec topic JSON uses `topic_keywords`.
   - Code reads `keywords` from the LLM response, not `topic_keywords` ([topic_chunking_shared.go:380-402](../../ChenWeb/server/api/doc-processing/topic_chunking_shared.go:380)).
   - Output `.topics` files do use `topic_keywords` ([topic_chunking_shared.go:75-126](../../ChenWeb/server/api/doc-processing/topic_chunking_shared.go:75)), so the write side matches the spec better than the read side.
   - Impact: a spec-compliant extractor response can lose keywords before persistence.

6. **Chunk size is measured on a reduced line representation, not the canonical line-file bytes.**
   - Spec says chunk target size is `CHUNK_SIZE` bytes.
   - Code measures bytes using `lineRawForChunking`, which reduces each line to `"lineNo pageNo lineType content"` and drops tab structure, font, font size, coordinate, and completely drops `image` lines ([fix-size-chunking.go:644-655](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:644), [fix-size-chunking.go:699-712](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:699)).
   - Impact: chunk boundaries are deterministic, but they are only an approximation of the true canonical input size. Large coordinate/font-heavy records will be chunked differently from what the byte spec suggests.

7. **Canonical line validation is weaker than the spec implies.**
   - Workflow says “Validate and parse the input line buffer.”
   - `ParseInputLines` / `parseLine` only enforce field count, integer line/page numbers, and non-empty `line_type/font/font_size/coordinate`; they do not validate numeric font size or coordinate format ([fix-size-chunking.go:521-579](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:521)).
   - The semantic chunking path has a stricter `validateCanonicalLine`, but fix-size chunking does not reuse it ([semantic-chunking.go:218-260](../../ChenWeb/server/api/doc-processing/semantic-chunking.go:218)).
   - Impact: malformed “canonical” lines can pass here even though adjacent code treats stronger validation as important.

8. **Summary generation can silently fall back to a truncated input echo.**
   - If the summary extractor returns no `summary` or `text`, the code falls back to `fallbackSummaryText`, which is basically the first 20 words of the input text ([fix-size-chunking.go:424-431](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:424), [fix-size-chunking.go:477-486](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:477)).
   - Impact: the pipeline can report success while producing a non-LLM, low-signal summary that does not meet the “generate a summary” intent of the spec.

### Low

9. **Summary file format is close, but still simplified relative to the summary spec.**
   - The implementation writes `summary_id`, `record_id`, `level`, `lines`, `children`, `summary_begin`, `summary_end`, and optional `embedding`.
   - It does not write `embedding_model_name`, and it writes a fully qualified summary ID (`record_level_seq`) instead of the abbreviated example shown in the summary spec ([chunk_summary_shared.go:62-90](../../ChenWeb/server/api/doc-processing/chunk_summary_shared.go:62)).
   - Impact: small format drift; likely acceptable if the full ID is intended, but it should be clarified in the spec or normalized in code.

## Requested Topic Review

## 1. How Chunking Is Implemented

Current implementation:

- The service parses the input line file, skips `TOC` rows, and builds chunks with `BuildChunks` ([fix-size-chunking.go:243-250](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:243)).
- Chunk boundaries are chosen by accumulating a byte budget over `lineRawForChunking`, then adjusting the cut so tables, formulas, and protected list blocks are not split ([fix-size-chunking.go:581-641](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:581), [fix-size-chunking.go:715-760](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:715)).
- Overlap is line-count based: `overlapLines := (end - start) * overlap / 100` ([fix-size-chunking.go:625-638](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:625)).
- The persisted `.chunks` file matches the high-level shape in the spec: repeated `overlap:` / `lines:` pairs with line number ranges ([topic_chunking_shared.go:129-171](../../ChenWeb/server/api/doc-processing/topic_chunking_shared.go:129)).

What looks good:

- No-split protection for tables and formulas is present.
- Non-numeric lists are protected.
- Numeric lists become splittable only when very large, matching the intent of the spec.
- The combined `.chunks` artifact naming and directory layout match the fix-size spec.

Main concerns:

- Byte sizing is approximate, not canonical.
- Input validation is weaker than expected for a canonical line file.
- The code includes overlap lines in downstream LLM input for both topic extraction and summary generation, which may be intentional for context, but it should be explicitly documented because persisted summaries only record regular lines.

## 2. How Topics Are Implemented

Current implementation:

- For each chunk, the service sends all chunk lines to the LLM and parses a `topics` array ([fix-size-chunking.go:266-291](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:266), [topic_chunking_shared.go:301-407](../../ChenWeb/server/api/doc-processing/topic_chunking_shared.go:301)).
- Topics are deduplicated by `(topic_type, category_path, lines, topic)` and then re-sequenced ([semantic-chunking.go:564-584](../../ChenWeb/server/api/doc-processing/semantic-chunking.go:564)).
- The service writes:
  - a spec-style JSON file `<base>.topics`
  - a legacy `topics.txt`
  - a topic tree projection under `CHUNK_TREE_ROOT_DIR`

What looks good:

- The `.topics` artifact format is much closer to the spec than the legacy file.
- The implementation is careful about deterministic ordering and reprocessing behavior.

Main concerns:

- LLM input parsing expects `keywords`, not `topic_keywords`.
- Only a single normalized path per topic is supported.
- The spec-category nested `categories` payload is not implemented.
- Topic embeddings are missing entirely.

## 3. How Summaries Are Implemented

Current implementation:

- The service generates one leaf summary per chunk and writes `summary_0_xxxx.txt` files ([fix-size-chunking.go:310-335](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:310)).
- It then groups summaries by `SUMMARY_GROUP_SIZE` and recursively builds parent summaries until one root summary remains ([fix-size-chunking.go:337-352](../../ChenWeb/server/api/doc-processing/fix-size-chunking.go:337), [chunk_summary_shared.go:119-160](../../ChenWeb/server/api/doc-processing/chunk_summary_shared.go:119)).
- Summary IDs and filenames match the documented tree pattern well.

What looks good:

- Recursive summary tree generation is implemented cleanly.
- Reprocessing removes old summary files before regeneration.
- The summary artifact file format is stable and covered by tests.

Main concerns:

- Summary embeddings are not generated.
- The fallback summary behavior can hide extractor/prompt mismatches.

## 4. How Category Extraction and Storage Are Implemented

Current implementation:

- Topic category storage:
  - normalizes one path per topic
  - writes leaf `.txt` files under `CHUNK_TREE_ROOT_DIR`
  - preserves rows from other records when reprocessing the current record
- Summary category storage:
  - generates one category path from the root summary only
  - writes one `summaries.txt` leaf entry containing the root summary ID

What looks good:

- Reprocessing behavior is deliberate: previous rows for the same record are removed before replacement.
- The code logs collisions caused by category normalization.

Main concerns:

- The storage structure is materially simpler than the category-extraction spec.
- There is no semantic similarity matching for directory reuse.
- No `topic_meta.json` or `category_meta.json` files are created.
- Topic and summary category storage use different file conventions, neither of which fully matches the spec.

## Test Coverage Notes

What is covered:

- core chunk no-split behavior for tables and lists
- happy-path fix-size service flow
- summary tree writing and reprocessing behavior
- status persistence and some failure paths

What is not well covered:

- parsing of spec-shaped `topic_keywords` / nested `categories`
- canonical line validation edge cases
- topic embeddings / summary embeddings
- summary/category behavior required by `spec-category-extraction.md`
- duplicate topic generation caused by overlap-heavy adjacent chunks

I also ran:

```bash
go test ./server/api/doc-processing
```

Result:

- The package test run failed, but the failures I saw were in other doc-processing areas (`semantic-chunking` and `structure-static-analyzer`), not in the fix-size chunking tests themselves.
- That means the review conclusions above are based primarily on code/spec inspection plus the existing fix-size-oriented tests, not on a clean package-wide green test run.

## Bottom Line

The implementation is a solid first pass for **fixed-size chunk creation + topic extraction + summary tree generation**, but it is only **partially aligned** with the written specs.

If the goal is strict spec compliance, the next work items should be:

1. Make topic parsing accept the spec JSON shape, especially `topic_keywords` and nested `categories`.
2. Implement topic and summary embeddings.
3. Rework topic/summarization category storage to match `spec-category-extraction.md`:
   - per-artifact/per-summary categorization
   - directory metadata files
   - semantic directory matching
4. Tighten canonical line validation and decide whether chunk byte sizing should use canonical raw lines or keep the current reduced representation and update the spec.
