# Provisions Reviewer (`review_provisions`) — checks a document's provisions against other documents

**Date:** 2026-11-10 (updated 2026-11-11: how the similarity search really behaves) \
**Scope:** What the provisions reviewer does during a document review, what it needs in the
database to be useful, how to configure it, and how to read its LLM calls when a run looks
wrong. Open it before changing the reviewer or when a review's provision findings look odd.
**Code root:** `ChenWeb/server/api/doc-reviews` (`review-provisions.go`)

## Summary

A *provision* is a rule stated in a document: a requirement ("shall"), a prohibition, a
permission or a condition. When someone reviews a document and ticks **Provision
Consistency** (条款一致性), the provisions reviewer takes every provision already extracted
from that document and looks for similar provisions in the *other* documents of the
knowledge base. For each provision it then asks a language model to compare: do the two
provisions govern the same thing, and if so, do they contradict each other, use different
limits, or reflect an older edition of a standard? The model also checks that the provision
was extracted correctly from the document's own text.

The result is two kinds of output in the review report: **findings** (a conflict, an
outlier, an extraction error, or something that could not be settled) and **analyses** (one
short comparison note for every similar provision found, even when there is no problem), so
a reader can see what was compared and why nothing was flagged.

The reviewer can only compare against documents whose provisions have been extracted
(`extract_provisions`) and indexed. With no such documents, it still makes one call per
provision, but all it can check is the extraction.

To find similar provisions it does **not** use the knowledge base's search engine. It uses
an older private copy of it, which in practice matches by meaning only (word matching never
finds anything) and looks across all documents regardless of knowledge store. A proposed
change, `hybrid-search-engine-api`, makes the search engine callable by reviewers so this
copy can be retired.

## Details

### Where it runs

- **Started from:** Applications → Document Review in the web app, or
  `POST /api/v1/doc-review/requests` with `"provisions"` in `aspects` (P5 group). The
  request's `review_depth` (1–3) selects the output limits below.
- **Process:** the API server. `Input = "artifact"` routes the reviewer through
  `runReviewersLegacy` → `provisionsReviewer.ReviewDocument`, not the per-chunk scheduler.
- **Configuration:** `[reviewers.provisions]` in `ChenWeb/doc-review.local.toml`, read once
  at startup (restart the server after editing).

### Steps of one run

1. **Load provisions** of the record from `kb.provisions` (ordered by `id`); keep the first
   `PROVISION_REVIEW_MAX_PROVISIONS` when set.
2. **Find matches** for each provision, from two sources:
   - *Similarity search* (`docprocessing.FindSimilarArtifactsOnTheFly`): reads the
     provision's own row in `kb.search_artifacts` (`artifact_type = 'provision'`,
     `artifact_id = prov_id`) and runs a hybrid search over other provision rows. One leg is
     Postgres full text (`ts_rank_cd`, dictionary from `[artifact_search]`), the other is
     pgvector cosine on the 1024-dimension embedding; each leg takes up to 200 candidates,
     merged by reciprocal rank fusion (k = 60). A candidate is kept when cosine ≥
     `ARTIFACT_CONNECT_MIN_COSINE` or lexical rank ≥ `artifact_search.min_rank`. The first
     `PROVISION_REVIEW_MAX_MATCHES` kept candidates are returned.

     This is **not** the knowledge-base search engine (`kbhandler/search_registry.go`:
     ParadeDB BM25 with the Jieba tokenizer, query keywords, scope filters). It is a copy made
     in June 2026 for the index-time linking step, which `doc-processing` could not import
     from `kbhandler`; on 2026-07-01 it became this read-time function. Its full-text leg
     passes the whole search document (50–400 words) to `plainto_tsquery`, which requires
     every word, and the `simple` dictionary does not split Chinese into words. On 2026-11-10
     the full-text leg found no candidate for any of the 205 provisions, so **matching is
     embedding-only** (cosine ≥ 0.75). The search excludes only the provision itself: no
     knowledge-store, document-group or record filters.
   - *Object anchors* (`loadObjectAnchoredPeerIDs`): provision → `kb.artifact_objects`
     object → the object node plus up to 20 comparable nodes (same type, shared normalized
     name) → `kb.artifact_connections` `object_id` edges → provisions of other documents.
3. **Resolve and filter:** load the candidates from `kb.provisions` by `prov_id` (with
   `kb.inputs` title, filename and document number), drop the record's own provisions and
   duplicates, sort by fusion score (object-anchor matches have no score and sort after),
   and keep `PROVISION_REVIEW_MAX_MATCHES` per provision.
4. **Add context to matches:** each match gets `source_context`, lines from its own document
   (10 before and 10 after its first span's start, plus all its span lines; tables are shown
   as numbered rows).
5. **Load the source passage:** the record's extraction chunks from its saved `.chunks`
   file (`docprocessing.LoadRecordChunks`), each rendered by `RenderLinesCompact`. Each
   provision gets the chunk it was extracted from (rule in openspec change
   `artifact-review-source-chunk`, design §2). If the spans run past that chunk, the payload
   sets `context_truncated: true`.
6. **Schedule:** one unit per provision, **including provisions with no matches**. Units
   are grouped by chunk: one unit per chunk starts first, then after `LLM_CALL_STAGGER` the
   rest, at most `MAX_DOC_REVIEWER_TASKS` at a time. The output-limit gate stops starting
   new units once the run reaches `max_findings` findings or `max_analyses` analyses for its
   depth; unstarted units are logged as skipped.
7. **Call the model** (next section) and parse its JSON.
8. **Store the results:** `analyses` are written to `kb.doc_review_provision_analyses` (only
   when the call has a `run_id`) and also turned into findings with `finding_type =
   'analysis'`, `severity = 'info'` and `metadata.result_kind = 'provision_analysis'`. All
   findings get `pass = 'P5'`, `aspect = 'provisions'`, `artifact_id = prov_id`; their
   `metadata` JSONB carries the provision's fields, `related_artifact_id` /
   `related_record_id`, and the matched provision's fields when `related_artifact_id` names
   a match. Missing values default to `finding_type = 'issue'`, `severity = 'low'`, and
   `location` = the provision's line spans. The framework saves them to
   `kb.doc_review_findings`; the report (`typst_report.go`) reads the analyses by run.

### The model call

With `max_tool_turns > 0` and a tool-capable client, the call runs the shared tool loop
(`runToolUseReviewWithPayload`, `review-tool-loop.go`); otherwise it is a single JSON
extraction. The tool loop:

- sends a one-line system prompt, then one user message:

  ```text
  <DOCUMENT_INPUT>
  Document: 农村生活垃圾分类处理规范 | DB33/T 2030—2018
  [22] GB 14554 恶臭污染物排放标准
  [36 h1] 3 术语和定义
  [43] 分类投放要定时、分类收集要定人、分类运输要定车、分类处理要定位的农村生活垃圾处置要求。
  …
  </DOCUMENT_INPUT>

  <REVIEW_TASK>
  <prompt-review-provisions-v6.md>

  # ARTIFACT REVIEW INPUT

  {"provision_under_review": {...}, "artifact_line_spans": ["43"], "matching_provisions": [...]}
  </REVIEW_TASK>
  ```

- offers the tools listed in `tools`: `get_artifact_context(record_id, artifact_id)` (lines
  around any artifact, in any document) and `get_document_metadata(record_id)` (title,
  number, authority class, dates, language);
- repeats while the model asks for tools, up to `max_tool_turns` turns or `max_tool_tokens`
  tokens, then forces a final answer without tools. A reply that is neither tool calls nor
  parseable JSON gets one repair request.

Payload fields:

| Field | Content |
|---|---|
| `provision_under_review` | `prov_id`, `prov_name`, `provision_type` (`mandatory` / `recommended` / `optional`), `provision`, `provision_subject`, `category_paths`, `source_line_spans` |
| `artifact_line_spans` | the provision's line spans |
| `context_truncated` | present and `true` only when the spans run past the source chunk |
| `matching_provisions[]` | the first `MAX_MATCHES_TO_LLM` matches: `provision` (same fields), `source_record_id`, `source_filename`, `source_doc_authority` (`standard` / `regulation` / `peer_document`, a heuristic on document number and title), `match_via` (`hybrid_search` / `object_anchor`), `match_rank` (1 = strongest), `source_context` |

Output contract (`prompt-review-provisions-v6.md` §6): `analyses[]`, one per matching
provision (`related_artifact_id`, `related_record_id`, `relationship` = `same_subject` /
`related_subject` / `unrelated`, `summary` in Chinese), and `findings[]` (`severity`,
`finding_type` = `issue` / `observation`, `title`, `description`, `evidence`, `suggestion`,
`confidence`, `related_artifact_id`, `related_record_id`). The checks are: direct
contradiction, conflicting values, scope or condition conflict, definitional conflict,
outlier, currency (newer edition), systematic pattern, and extraction error (including a
"provision" taken from a term's definition).

### Configuration

| Setting | Where | Value (default / local) | Effect |
|---|---|---|---|
| `enabled`, `checked` | `[reviewers.provisions]` | `true` | offered / ticked by default in the UI |
| `model` | same | `deepseek-flash-processor` | model profile (resolved through `MODEL_DEF_FILE`) |
| `prompt` | same | `prompt-review-provisions-v6.md` | rubric, from `PROMPT_DIR` |
| `max_tool_turns`, `max_tool_tokens` | same | `4`, `24000` | tool-loop budget; `0` turns = single JSON call |
| `tools` | same | `get_artifact_context`, `get_document_metadata` | tools offered to the model |
| `max_findings`, `max_analyses` | top of `doc-review.local.toml`, or per reviewer | built-in `[100, 200, 300]`, local `[10, 20, 30]` | per-depth output limits |
| `PROVISION_REVIEW_MAX_MATCHES` | env | `20` / `10` | candidates kept per provision |
| `MAX_MATCHES_TO_LLM` | env | `3` / `10` | candidates sent to the model |
| `PROVISION_REVIEW_MAX_PROVISIONS` | env | `0` (no cap) | provisions reviewed per run |
| `ARTIFACT_CONNECT_MIN_COSINE` | env | `0.75` | semantic acceptance threshold |
| `[artifact_search]` `dictionary`, `min_rank` | `config.toml` | `simple`, `0.0` | lexical search and threshold |
| `MAX_DOC_REVIEWER_TASKS`, `LLM_CALL_STAGGER` | env | run concurrency / `1` s | scheduling |
| `ARTIFACT_DIR`, `CHUNK_SIZE`, `CHUNK_OVERLAP_PERCENT` | env | — | where `.chunks` files live; rebuild settings when a file is missing |

### Data it depends on

- `kb.provisions` rows for the reviewed record and for other documents.
- The provision search index: `kb.search_artifacts` partition `provision`, one row per
  provision with `artifact_id = prov_id`, a search document, a full-text vector and an
  embedding. The doc-processing service writes it after `extract_provisions`
  (`IndexProvisionsForRecord`, `ReindexProvisionSearchForRecord`; ids from
  `provisionArtifactID`). A provision with no index row gets no similarity matches, and no
  error is raised.
- `kb.artifact_objects`, `kb.object_nodes` and `object_id` edges in
  `kb.artifact_connections`, for object-anchor matches.
- The record's line file and its `.chunks` file under `ARTIFACT_DIR`.

### Logs and debugging

- **LLM calls** (`public.llm_usage_event`):
  - tool loop: `call_reason = 'review_provisions'`, `call_loc = 'MID-20260706-014'`, one row
    per turn; `metadata_json` has `prv_id`, `run_id`, `turn_count`, `prompt_ref`;
  - forced final answer: `call_reason = 'review_tool_use_finalize'`,
    `call_loc = 'MID-20260712-01'` (shared by all tool-loop reviewers);
  - single-call path: `call_reason = 'review-provision'`, `call_loc = 'MID-20260706-0001'`,
    `metadata_json.provision_id`.

  Request and response bodies are stored as gzip JSON under the LLM log directory
  (`input_body_ref`, `output_body_ref`). These rows have `http_status = 0` and an empty
  `error_message` on success; 0 is not an error.
- **Server log:** `provisions review running` (provisions, reviewed provisions, chunks) and,
  per provision, `provisions review provision done` (`matches`, `matches_sent_to_llm`,
  `findings`, `ms_used`, cache-hit and cache-miss tokens).
- **First check when a run finds nothing:** whether `matching_provisions` is empty in the
  request bodies. If so, check that the record's provisions have rows in
  `kb.search_artifacts` with `artifact_id = prov_id`, and that other documents have
  provisions at all.

### Files

| File | Purpose |
|---|---|
| `ChenWeb/server/api/doc-reviews/review-provisions.go` | reviewer: loading, matching, payload, analyses, findings |
| `ChenWeb/server/api/doc-reviews/review-artifact-window.go` | source chunks, chunk choice, chunk-grouped scheduling (shared with the metrics and inventory reviewers) |
| `ChenWeb/server/api/doc-reviews/review-object-anchor-matches.go` | object-anchor matches |
| `ChenWeb/server/api/doc-reviews/review-tool-loop.go`, `review-tools.go` | tool loop and tools |
| `ChenWeb/server/api/doc-reviews/review-match-limit.go`, `review-output-limits.go` | `MAX_MATCHES_TO_LLM`; output-limit gate |
| `ChenWeb/server/api/doc-processing/artifact_indexing.go` | `FindSimilarArtifactsOnTheFly` and `queryArtifactHybridCandidates` (the private search copy) |
| `ChenWeb/server/api/doc-processing/search_indexing.go` | provision index rows, `provisionArtifactID` |
| `ChenWeb/prompts/prompt-review-provisions-v6.md` | current rubric (earlier versions kept for old runs) |
| `ChenWeb/project_migrations/20260706000001_create_doc_review_provision_analyses.sql` | analyses table |

### Related documents

- ADR 2026063003 — the provisions reviewer (`adrs/202606/2026063003-adr-doc-reviewer-provisions.md`).
- ADR 2026070201 — source passage, scheduling, tool use, prompt v2; AR2/AR3 amended
  2026-11-10 to the extraction chunk in compact form.
- ADR 2026070602 — mandatory `analyses`.
- ADR 2026070501 — LLM call logging (`call_reason`, `call_loc`, `metadata_json`).
- OpenSpec change `ChenWeb/openspec/changes/artifact-review-source-chunk/` — the source
  passage contract (`specs/artifact-review-input/spec.md`).
- Module doc `modules/module-compact-document-lines.md` — `RenderLinesCompact`,
  `LoadRecordChunks`.
- OpenSpec change `ChenWeb/openspec/changes/hybrid-search-engine-api/` (proposed, not
  implemented) — makes the search engine callable by server modules, with reference queries,
  exclusion filters, keyword and similarity criteria and a documented score; moving this
  reviewer onto it is a follow-up change.
- Capsule `Capsules/coding-capsules/llm-wiki/hybrid-search.md` — the knowledge-base search
  engine.

## Known limitations

- **It needs other documents' provisions.** As of 2026-11-10 only two documents (records
  416 and 638) have extracted provisions, so most reviews find no matches until more
  documents go through `extract_provisions`.
- **Every provision costs a call, matches or not.** Without matches the call can only check
  the extraction.
- **The document's own provisions can crowd out other documents'.** The similarity search
  returns its top `PROVISION_REVIEW_MAX_MATCHES` candidates before the reviewer removes the
  document's own provisions, so a document with many similar provisions of its own can
  leave few or no slots for other documents.
- **It does not use the search engine.** The similarity search is a private copy of the
  knowledge-base search from June 2026. It lacks everything added since (BM25 with Chinese
  word splitting, query keywords), and it is maintained separately from the engine.
- **Matching is by meaning only.** The copy's word-matching half requires every word of the
  provision's search document, so it never finds a candidate. Provisions that share an exact
  standard number, clause number or limit but are worded differently are found only if their
  embeddings are close (cosine ≥ 0.75).
- **No scope.** Candidates come from every document in the database, whatever its knowledge
  store or document group, and their text and file names are quoted into the report.
- **Candidates can still be loose.** Embedding similarity of 0.75 groups provisions on the
  same topic, not only the same obligation; the model is told to screen candidates and record
  unrelated ones as `unrelated`.
- **The passage is local.** The model sees the chunk the provision came from, not the
  document's scope clause or definitions elsewhere in the document; its tools fetch only
  lines around an artifact and document metadata.
- **Authority is guessed.** `source_doc_authority` comes from a pattern match on the
  document number and title (GB, ISO, 标准, 条例…), not from a curated register.
- **Output limits cut runs short.** Once a run reaches its depth's finding or analysis
  limit, the remaining provisions are not reviewed (logged as skipped).
- **The index can drift.** Provisions deleted outside re-extraction leave index rows behind
  unless the deleting path also clears them (`scripts/clear_artifact_data.sql` does since
  2026-11-10).
