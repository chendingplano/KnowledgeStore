# Question Generator — document-grounded search benchmark candidates

**Date:** 2026-10-24 \
**Scope:** Generating, saving, and inspecting metric-search questions for one document or a random batch. \
**Code root:** `ChenWeb/server/api/kbhandler/question_generator*.go`

## Summary

Question Generator creates candidate questions for evaluating metric search.
Open **System Admin → Benchmark → Question Generator**, enter an input record ID,
or leave it blank to sample documents randomly. Select **Search Metrics** as the
Purpose, add an optional Description, and choose **Metrics per document** and **Total metrics**. Both start at ten.
Each sampled metric produces three questions: one-hop, two-hop, and multi-hop
(ten metrics produce thirty questions). A specified record ignores Total metrics;
batch mode reduces the final document's metric count to reach the total exactly.

Generation runs in the background. The page shows its status and lets you reopen
saved runs for one record or across all records. For each requested metric set, the
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
- `metrics_per_document`: optional integer, default ten, range 1–50.
- `total_metrics`: optional batch target, default ten, range 1–1,000. A specified
  input ID ignores this value and uses Metrics per document instead.
- Legacy per-hop count request fields remain accepted when equal; unequal values
  fail validation because a metric always generates one question of each hop type.
  The new metric count fields take precedence over legacy fields.
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
neighbor count. `context_line_ranges` preserves the corresponding canonical IDs as inclusive
range strings, for example `["124:128", "130", "132:144"]`. Missing IDs between
ranges remain unavailable evidence. Output question citations remain integer IDs.
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

For a document, N is Metrics per document, clipped to the remaining Total metrics
in batch mode. The generator randomly samples N metric entries, choosing without
replacement until the eligible pool is exhausted, then refilling it if necessary.
Every set contains one selected metric and three assigned targets: one-hop,
two-hop, and multi-hop. Each target gets an independent random language.
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
For new runs, the three per-hop requested counts each equal the metric count,
and their total targets each equal Total metrics. Existing run rows are unchanged.

`testbed.generated_questions` holds one row per question: `run_id`,
`input_record_id`, `purpose`, `hop_type`, `question`, `answer`, `reasoning_steps`,
`step_line_ids`, `evidence` (objects containing `line_id` and `text`), `set_no`,
`metric_id`, `metric_snapshot`, `lang`, and `source_sha256`. Each question keeps its
actual input ID even when its run samples many documents. Its non-null `purpose`
is copied from the saved run when inserted and included in question API responses;
model-supplied purpose is ignored. Existing questions are backfilled from their
parent runs, preserving historical purpose values. The metric snapshot is
copied from the loaded database metric, not accepted from model output. Set numbers
identify metric sets within one document model call, shared by their three
questions. New metric snapshots include `context` and `context_line_ranges`;
historical snapshots with `context_line_ids` remain readable. The hash covers the serialized
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
`20261024000011_question_generator_metric_batches.sql` (batch/metric metadata),
and `20261024000012_add_generated_questions_purpose.sql` (question-level purpose
and historical backfill).
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

If a parsed model response fails validation, the generator makes one correction
call with the same sampled metrics, contexts, language targets, run ID, and input
record ID. Its JSON input adds `validation_error` and `previous_response`; the
Search Metrics prompt instructs the model to return the full corrected question
array. Both attempts use the same strict validation, input-size cap, and run
deadline. A second invalid response fails the document without saving partial
questions. Provider/request errors do not trigger this correction call. Each call
is recorded separately in LLM usage logs under the same run ID.

Reasoning errors report the actual counts, for example two reasoning steps but
one citation array. Multiple explanations supported by one source line still
require one citation array per explanation; the server does not infer or copy
missing citations. This reproduces the failure seen in run 6 for input 416.


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
