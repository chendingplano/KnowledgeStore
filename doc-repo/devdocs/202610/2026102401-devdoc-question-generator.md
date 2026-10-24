# Question Generator — document-grounded search benchmark candidates

**Date:** 2026-10-24 \
**Scope:** Generating, saving, and inspecting metric-search questions for one document or a random batch. \
**Code root:** `ChenWeb/server/api/kbhandler/question_generator*.go`

## Summary

Question Generator creates candidate questions for evaluating metric search.
Open **System Admin → Benchmark → Question Generator**, enter an input record ID,
or leave it blank to sample documents randomly. Select **Search Metrics** as the
Purpose, add an optional Description, and choose per-document and total counts
for one-hop, two-hop, and multi-hop questions. All counts start at ten. A specified
record uses only the per-document counts; batch mode repeats until it reaches the
total targets, reducing the final document's counts as necessary.

Generation runs in the background. The page shows its status and lets you reopen
saved runs for one record or across all records. For each requested question, the
system randomly selects a stored metric and sends only its surrounding source
context to the model. Each question independently uses English or Chinese, chosen
randomly by the server. It includes a reference answer, reasoning steps, the
selected metric, and copies of the cited source lines. Previous runs are kept.
These are generated candidates that need human review before use as a benchmark.

## Details

### Inputs and configuration

- `input_record_id`: positive `kb.inputs.id` for one document. Omitted, null, or
  zero means random batch mode. Negative values are invalid. Source comes from
  the record's canonical line file via `docprocessing.LoadRecordLinesByID`.
- `purpose`: required stable ID `search_metrics`, displayed as Search Metrics.
  Each supported purpose resolves to its own versioned prompt; unknown purposes
  fail validation. Historical free-text purposes remain readable.
- `description`: optional additional context, up to 10,000 characters.
- `one_hop_count`, `two_hop_count`, `multi_hop_count`: optional integers, default
  ten each per document; 0–50 per category, with at least one positive count.
- `total_one_hop_count`, `total_two_hop_count`, `total_multi_hop_count`: optional
  batch targets, default ten each; 0–1,000 per category, with at least one positive
  total. Each positive total needs a positive per-document count. A specified
  input ID ignores supplied total values and uses the per-document counts instead.
- `lang`: legacy request field, ignored. New runs have `lang = mixed`; each question
  has `en` or `zh-cn`. Random selection does not guarantee both languages appear
  in a small run. Interface language changes do not translate saved questions.
- `QUESTION_GEN_MODEL_NAME`: model reference in `.models.toml`, default
  `deepseek-flash-processor` when unset or blank. Uses the existing configured
  provider client and usage logging. Generator calls explicitly send
  `thinking.type = disabled`, overriding the profile's reasoning setting for
  this client. The model profile itself is unchanged.
- `PROMPT_GENERATE_METRIC_QUESTIONS`: Search Metrics prompt file reference, default
  `prompt-question-generator-search-metrics-v1.md`. Loaded through the existing
  prompt resolver (`PROMPT_DIR`, an absolute path, or the project's prompts directory).
  The resolved reference is saved on the run and its LLM usage events.

Only sampled metric contexts are sent. For each metric, `context` joins the source
content with newline separators: up to ten actual canonical lines before its first
source line, its metric source lines, and up to ten lines after its last source
line. Disjoint metric spans exclude intervening lines outside those spans. Window
boundaries are clamped to the document, and sparse line IDs do not reduce the
neighbor count. `context_line_ids` preserves the corresponding canonical IDs.
Tables use the existing numbered-row representation.

The context windows are combined and deduplicated for evidence validation and
source hashing. Unrelated document content is neither included in the prompt nor
subject to the context size limit. Empty contexts or assembled inputs over 600,000
characters fail without truncation. A model's context/output limits may be lower.

### Document and metric sampling

Batch mode samples `kb.inputs` in random order, directly filtering to documents
that have primary `kb.metrics` rows (`ref_mention_id IS NULL`). This is equivalent
to random draws followed by skipping metric-free inputs. Metrics are loaded for
each selected document; a document whose metrics disappeared is skipped as well.
Missing line files, insufficient metric grounding, or invalid model responses skip
the candidate in batch mode and fail a specifically requested single document.

For a document, N is the sum of the requested one-hop, two-hop, and multi-hop
counts. The generator randomly samples N metric entries, choosing without
replacement until the eligible pool is exhausted, then refilling it if necessary.
Every set contains one selected metric and exactly one assigned question target.
The model never receives the full stored metric inventory or the full source file.

The input JSON starts with `document_metadata`: input record ID, title, document
number, filename, publication date, and the stored extracted metadata. It then
contains `run_id`, record ID, Purpose, Description, the selected metric sets (with
their individual contexts), and previous questions. Citation validation restricts
each question to its own metric's context, even if another selected metric has
additional context in the same request.

If one pass cannot fill the totals, eligible documents are sampled again. Already
saved question texts are supplied to later calls and normalized duplicates are
rejected before insertion. A pass making no progress fails clearly; duplicate-only
passes get up to two extra retries. Earlier completed documents remain available.

### API and storage

All endpoints require an authenticated administrator or owner:

Creation generates a saved numeric run ID (`testbed.generated_question_runs.id`),
which all its `testbed.generated_questions.run_id` values reference. The generator
page explicitly labels it **Run ID**. Every LLM call also carries that same ID in
`JSONExtractionInput.RunID` plus the actual input record in `RecordID`, so **LLM
Usage Logs → Run ID** can display and filter the corresponding calls.

| Method | Path under `/api/v1/kb/question-generator` | Result |
|---|---|---|
| POST | `/runs` | Validate input, persist a running run, return HTTP 202 with `{run}` |
| GET | `/runs` | Latest 50 runs across all records, as `{runs}` |
| GET | `/runs?input_record_id=416` | Latest 50 runs for this record, including batches with saved questions for it |
| GET | `/runs/:id` | `{run, questions}`, or HTTP 404 |

`testbed.generated_question_runs` holds Purpose, Description, counts, language,
model reference and resolved model name, prompt filename, creator, timestamps,
`running` / `done` / `failed` status, per-document limits, total targets, generated
counts per hop, document processing count, and expiration deadline. Batch runs
have a null `input_record_id` in the database (returned as zero by the API).
`documents_processed` counts successful document visits, including repeat visits.

`testbed.generated_questions` holds one row per question: `run_id`,
`input_record_id`, `hop_type`, `question`, `answer`, `reasoning_steps`,
`step_line_ids`, `evidence` (objects containing `line_id` and `text`), `set_no`,
`metric_id`, `metric_snapshot`, `lang`, and `source_sha256`. Each question keeps its
actual input ID even when its run samples many documents. The metric snapshot is
copied from the loaded database metric, not accepted from model output. Set numbers
identify individual question targets within one document model call. The metric
snapshot includes `context` and `context_line_ids`. The hash covers the serialized
union of selected context lines, not the raw file bytes. Legacy run-level source hashes
remain readable. Deleting an input deletes its questions and its single-document
runs; a batch run and its other documents' questions remain.

Each document's questions and progress counters commit in one transaction. The
last successful document also marks the run done. Invalid responses save no partial
document; a later batch failure preserves already committed documents. Single
document runs expire after ten minutes, batches after one hour. History reads mark
expired runs failed, and a late worker cannot revive them. Worker contexts enforce
the same limits. Failure details and progress appear in the run inspector.

Migrations: `20261024000001_create_generated_questions.sql` (initial schema) and
`20261024000011_question_generator_metric_batches.sql` (batch/metric metadata).
The existing startup project migrator applies them before routes are served. The
second migration retains historical rows and backfills their counts and languages.
Its rollback refuses to proceed while batch runs exist, because the original schema
cannot represent them.

### Question validation

The prompt defines one-hop as direct fact retrieval, two-hop as combining two
independently evidenced facts, and multi-hop as combining at least three linked
facts. Each needs at least one, two, or three reasoning steps respectively. Distinct
facts can share a table's canonical line. Every step must have citations, and the
evidence must be their exact union, including a source line for the selected metric.
The returned set/hop/language must exactly match an assigned target. Evidence text
is copied from the loaded source by the server, never accepted from the model.

The server rejects unknown hop types, wrong per-category counts, blank questions
or answers, duplicate questions (ignoring case and whitespace), empty reasoning,
unknown or repeated evidence lines, and unsupported reasoning steps.

## Known limitations

- Validation checks structure and citation existence. It cannot establish that an
  answer is correct or that the requested reasoning actually needs multiple facts.
- The model may fail to produce supported questions for all targets. Batch mode
  tries other documents, then reports failure if no progress is possible. Generated
  progress remains visible; failed batches are not marked complete.
- Generation uses an in-process background worker. A server restart interrupts it;
  history reads report failure after the deadline. Interrupted runs do not resume
  automatically.
- Each history request shows the latest 50 matching runs.
- The page inspects saved candidates; it does not score search results, edit
  questions, or mark candidates as an approved benchmark.

## Development troubleshooting

If a blank record ID gets HTTP 400 with `positive input_record_id and purpose are
required`, the API is serving the original implementation. The current handler
accepts omitted, null, and zero input IDs; a PostgreSQL-backed HTTP integration test
covers all three alongside a specified ID. Check the running API process, not just
whether the latest binary builds. Air uses `stop_on_error = false`, so failed
rebuilds can leave the older server running. Resolve the build/configuration error
and restart the development API through `mise dev-server` after stopping its old
reloader. The frontend may already have updated independently.

## Related documents

- [Hybrid search](../../../Capsules/coding-capsules/llm-wiki/hybrid-search.md)
- [Input and line-file management](../../../Capsules/coding-capsules/input-management/+CAPSULE.md)
- [Implementation plan](../../../Capsules/coding-capsules/llm-wiki/question-generator-implementation.md)
