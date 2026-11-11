# Question Generator — document-grounded search benchmark candidates

**Date:** 2026-10-24 (updated 2026-10-25: preserve valid questions on partial failure, questions/jobs tabs and count-based sampling; 2026-11-11: questions for every search artifact type, and Mix) \
**Scope:** Generating, saving, and inspecting search questions for one document or a random batch. \
**Code root:** `ChenWeb/server/api/kbhandler/question_generator*.go`

## Summary

Question Generator creates and browses candidate questions for evaluating search.
A question's answer, its *target*, is one item that hybrid search can return: a
metric, a provision, a summary, an entity, an original passage and so on. Open **System Admin → Benchmark → Question Generator** to see saved
questions immediately. Filter by Purpose, Run ID, Record ID, Language, and creation
time, then click **Search**. **Reset** clears the conditions and reloads all
questions. The results panel has two tabs: **Generated questions** (selected by
default) and **Question generation jobs**. The first contains the existing question
browser; switching tabs preserves its filters, selection, and List/Cards view.
Question filters are hidden while viewing jobs, whose list always spans all documents.
Question results are paginated, newest first. The **Cards** view is selected by
default and shows three columns on wide layouts; **List** shows a compact table
with expandable full details.
Each question shows its answer,
model, prompt, source record, language, and expandable reasoning and evidence.
Check questions in either view, or use **Select All** to select the current page,
and click **Delete** to move them to an archive. A confirmation prompt shows how many
questions are selected and explains that they will be archived. Confirming starts the
archive request; cancelling keeps the selection and sends no request. The prompt is
available in English and Chinese. Select All shows a partial state
when only some questions are checked; unchecking it clears the selection.
Selections carry between tabs and clear when the results reload. Questions are
retained in full, with who archived them and when, and disappear from active
results. A failed archive keeps the selected questions available for retry.
The site footer is hidden on this page.

**Question generation jobs** lists every saved generation run, newest first, in
pages of 25. It shows Run ID, Record ID (or Random documents for batch jobs), status,
generated/target question counts, start time, elapsed time for finished jobs, and
description. **Previous** and **Next** reach older jobs beyond the first 50.
**Refresh** reloads the current page; a page with running jobs refreshes every
2.5 seconds. Running jobs use the same flashing amber badge, with a steady highlight
for reduced motion. **View** opens the job's status panel above the tabs, including
progress, model/prompt, and failure details. Starting a new job refreshes the visible
jobs list to its first page. Both tabs support keyboard navigation and English/Chinese.

Click **Generate Questions** to open the generation dialog. Enter an input record
ID or leave it blank to sample documents randomly. Choose a **Purpose**: it decides
what the questions are about. **Search Metrics** asks about metrics, and **Search
Provisions**, **Search Summaries**, **Search Entities** and the other "Search …"
purposes ask about that kind of item. **Mix** draws a random kind for each target,
so one run contains questions about different kinds of items. Add an optional
Description, and set **Questions to generate** for a specific document (default
thirty, range 1–3,000). The server loads the document's items of the chosen kind,
keeps those linked to usable source lines, and randomly selects distinct targets.
Each selected target produces one-hop, two-hop, and multi-hop questions, so the count
rounds up to a complete group of three: requesting ten questions selects four
targets and produces twelve questions. The dialog shows this plan before submission.
If there are too few usable targets, a confirmation prompt states how many questions
can be generated. Confirming uses all the available targets once; cancelling keeps
the settings and starts no run. With no usable targets, the page reports zero
available questions and starts no run. The confirmed target pool and source lines
are retained for the worker, so generation uses the same pool that was checked.
Each question card shows its **Target** as the kind of item and its ID, for example
"Provision · 416_prv_40".

For random batch mode, choose **Targets per document** and **Total targets** instead.
Both counts start at ten; batch mode reduces the final document's count to reach
the target. The single-document count and confirmation flow do not change batch mode.
Close the dialog with **Close**, Escape, or a press starting on the backdrop.
Selecting text inside a field and dragging outside keeps the dialog open.

Generation runs in the background. A status panel reports its saved Run ID,
progress, and any failure. The Running badge has an amber highlight that flashes
gently in both themes; reduced-motion settings keep the highlight steady. The
highlight and animation stop when the run finishes or fails.
The list and filter options refresh when the run ends,
using the currently applied search conditions. Existing questions remain saved.
An invalid question does not discard its valid neighbors. Successful questions are
saved before the correction attempt, and newly corrected questions are added afterward.
If some questions still fail, the job is marked Failed but the status panel states
how many successful questions were saved; they remain in Generated questions and
can be filtered by Run ID. The progress counts show actual saved questions.
Only each sampled target's surrounding source context is sent to the model.
Question language is independently chosen as English or Chinese. These are
candidates that need human review before use as a benchmark.

## Details

### Purposes and targets

The contract for this section is the spec
`ChenWeb/openspec/specs/question-generator-artifact-types/spec.md`. Update that spec when
changing this behaviour. The change that introduced it (proposal, design, tasks) is archived in
`ChenWeb/openspec/changes/archive/2026-11-11-question-generator-artifact-types/`.

| Purpose | Target type | Target source |
|---|---|---|
| `search_metrics` (Search Metrics) | `metric` | `kb.metrics` (unchanged path, prompt v3) |
| `search_chunks`, `search_summaries`, `search_topics`, `search_scene_blocks`, `search_provisions`, `search_products`, `search_inventory_items`, `search_semantic_projections`, `search_knowledge`, `search_entities`, `search_relations` | the matching search artifact type | `kb.search_artifacts` rows of that type |
| `search_mixed` (Mix) | every search artifact type, `metric` included | `kb.search_artifacts` rows of all types |

The purpose table is `questionPurposes` in `question_generator.go`; a unit test keeps it
equal to the search registry's partition types (`searchArtifactPartitionTypes`).

**Registry targets** (every purpose except Search Metrics) come from the search registry, so
each target is exactly something hybrid search can return. A row is eligible when it has an
artifact ID, at least one source line span, every span's endpoints exist among the document's
non-empty canonical lines, and its formatted source context is at most 20,000 characters.
The size limit mainly excludes level-0 summaries that cover a whole document. Duplicate IDs
count once. Code: `question_generator_artifacts.go`.

**Mix** keeps one pool per type. For each target it first picks a type with equal probability
among the types that still have unused targets in the document, then a target of that type.
A small type (two provisions) is therefore drawn as often as a large one (700 entities). Pools
refill only when every type is used up. Each question keeps `purpose = search_mixed` and
stores its own target type.

**Model input** for a registry target set: `artifact_type`, `artifact_id`, `primary_label`,
`secondary_label`, `snippet` (the first 1,000 characters of `snippet_basis`), `semantic_payload`
with empty values removed, `source_line_spans`, `context` and `context_line_ranges`. The context
is built exactly as for metrics (below). The prompt is `PROMPT_GENERATE_ARTIFACT_QUESTIONS`,
default `prompt-question-generator-search-artifacts-v1.md`. It keeps the metric prompt's hop,
language, single-target and citation rules and adds one paragraph per type on what a question
asks for (for a relation: the missing end of the fact; for a provision: what is required and
when). It also requires the answer to come from the target's own lines; neighbouring lines may
only describe the situation.

**Validation** is shared with metrics (`question_generator_targets.go`): citations must stay in
the target's context and at least one must fall inside its spans. A two- or multi-hop question
may not contain the target's `primary_label` (and, for an inventory item, its `secondary_label`,
the English name). Other types' secondary labels are codes such as `mandatory` and are not
checked. Messages name the target type ("does not cite its selected entity's source lines
(source_line_spans 44)"), which the correction round passes back to the model.

LLM calls of registry purposes use `call_reason = question_generation_<purpose>` and call
location `20261111-742`. Search Metrics keeps `question_generation_search_metrics` and
`20261024-741`.

### Browsing and filters

The page loads up to 50 questions per page. The Purpose menu lists every current purpose
plus any historical purpose found in saved questions. Run ID, Record ID, and Language
menus contain all distinct values stored in `testbed.generated_questions`. The API provides these values independently of active filters.
Time From and Time To are local date/time pickers, converted to timezone-aware
RFC3339 timestamps by the client. Either bound can be omitted; both are inclusive
and filter each question's `created_at`. Reversed ranges are rejected.

Each record uses the shared [Name-Value Visualizer](../../modules/module-name-value-visualizer.md)
through `question-record.svelte`, which adapts the question, answer, run/record
metadata, language, model, prompt, and creation time into localized field lists.
Expandable reasoning and evidence use the same component, including per-step line
IDs. Values retain source language and line breaks; optional blank fields are
omitted by the visualizer. Text stays selectable in both themes.

The results container uses three equal-width cards when its content width exceeds
1,100px, two at 721–1,100px, and one at 720px or below. These breakpoints use the
available results width, so navigation and context panels are accounted for.

Editing controls does not change results until Search is clicked. Pagination uses
the last applied conditions. Reset clears both draft and applied conditions and
queries the database again. Request cancellation prevents stale searches from
replacing newer results. The modal supports keyboard dismissal and focus return.

### Archiving selected questions

`POST /api/v1/kb/question-generator/questions/archive` uses the existing question
administrator middleware. Its JSON body is `{"ids":[1,2]}` (1–1,000 positive
integer IDs), and the response is `{"archived_count":2}`. Duplicate IDs and IDs
already archived or absent do not increase the count; the request is safe to retry.

Migration `20261025000003_archive_generated_questions.sql` creates
`testbed.generated_questions_archive`, preserving all question columns and the
original ID, plus `archived_at` and `archived_by`. A single PostgreSQL statement
moves rows from the active table into the archive; any insert error rolls back
the entire move. Archive rows have no foreign keys to live runs or inputs, so
later deletion of those parents does not erase archived content. The server logs
the actor, selected IDs, result count, and any failure.

Active browser totals, filter choices, generation-run question lists, and new
benchmarks read the active table. Historical generation progress counts continue
to describe what the run generated. Existing benchmark result snapshots remain
stored; their nullable active-question reference is cleared by its existing
`ON DELETE SET NULL` foreign key when a question is archived.

The page disables Delete until there is a selection and during loading/archiving.
After success it refreshes results and filter choices, returning to the preceding
page if needed. Selection is limited to the displayed page. Both views support
English/Chinese labels, keyboard tab navigation, and selectable text.

Migration rollback restores archived rows before dropping the archive table.
If a parent input/run no longer exists, or a live uniqueness constraint would be
violated, rollback fails without discarding the archive; resolve the conflict
before retrying. Archive timestamps and actor metadata are removed on rollback.
There is no archive browser or per-question restore action in this change.

### Inputs and configuration

- `input_record_id`: positive `kb.inputs.id` for one document. Omitted, null, or
  zero means random batch mode. Negative values are invalid. Source comes from
  the record's canonical line file via `docprocessing.LoadRecordLinesByID`.
- `purpose`: required; one of the thirteen IDs in *Purposes and targets*. Search
  Metrics uses the metric prompt and every other purpose the artifact prompt; unknown
  purposes fail validation with HTTP 400. Historical free-text purposes remain readable.
- `description`: optional additional context, up to 10,000 characters.
- `num_questions_to_generate`: integer 1–3,000 for a specified document. Takes
  precedence over target and legacy hop counts; the sample size is `ceil(count / 3)`.
  Every selected target is distinct within this run.
- `confirmed_available_questions`: the reduced question count accepted by the user
  after a shortage response. The server rechecks capacity on resubmission; a changed
  capacity requires a new confirmation. No run is inserted and no model is called
  before this check succeeds.
- `metrics_per_document`: optional integer, default ten, range 1–50. Despite the
  name it counts targets of the chosen purpose (Targets per document on the page).
- `total_metrics`: optional batch target, default ten, range 1–1,000, also counting
  targets. A specified input ID ignores this value and uses the per-document count.
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
  `prompt-question-generator-search-metrics-v3.md` (v2 until 2026-10-25). Loaded through the existing
  prompt resolver (`PROMPT_DIR`, an absolute path, or the project's prompts directory).
  The resolved reference is saved on the run and its LLM usage events.
- `PROMPT_GENERATE_ARTIFACT_QUESTIONS`: prompt for every other purpose, default
  `prompt-question-generator-search-artifacts-v1.md`, resolved the same way.

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

### Document and target sampling

Batch mode samples `kb.inputs` in random order, directly filtering to documents
that have targets: primary `kb.metrics` rows (`ref_mention_id IS NULL`) for Search
Metrics, or `kb.search_artifacts` rows of the purpose's types otherwise (any type for
Mix). The metric details below apply to registry targets in the same way. This is equivalent
to random draws followed by skipping metric-free inputs. Metrics are loaded for
each selected document; a document whose metrics disappeared is skipped as well.
Missing line files or insufficient metric grounding skip the candidate in batch mode
and fail a specifically requested single document. Invalid model responses retain
every independently validated question; a batch continues processing its other
documents, then reports unresolved failures without discarding saved results.

For a single document using Questions to generate, N is `ceil(requested / 3)` or
the available metric count after a confirmed shortage. Sampling is without replacement;
duplicate metric IDs do not inflate availability. Legacy requests without the question
count and random batch mode retain Metrics per document, clipped to remaining Total
metrics in batch mode, and may refill the eligible pool after exhausting it.
Every set contains one selected metric and three assigned targets: one-hop,
two-hop, and multi-hop. Each target gets an independent random language.
The model never receives the full stored metric inventory or the full source file.

The input JSON starts with `document_metadata`: input record ID, title, document
number, filename, publication date, and the stored extracted metadata excluding
`drafting_persons` and `drafting_organizations`. These two fields are omitted only
from question-generation model input; stored document metadata is unchanged.
Before sending the request, empty metadata values are removed recursively:
nulls, blank or whitespace-only strings, and empty arrays or objects (including
containers emptied by pruning). This applies to top-level fields such as `doc_no`
and all nested extracted metadata. Empty array entries are removed while retaining
the order of remaining entries. Numeric values, including zero, and booleans,
including false, are retained. It then
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
page explicitly labels it **Run ID**. Since 2026-11-08, LLM calls carry a separate
ID from the shared `llm_run_id` sequence, stored in
`testbed.generated_question_runs.llm_run_id`. Every document and correction call
in that generation run shares the LLM ID, while model input and generated-question
relationships keep the table run ID. Use the stored **LLM run ID** in **LLM Usage
Logs → Run ID**, plus the actual input record in `RecordID`.

| Method | Path under `/api/v1/kb/question-generator` | Result |
|---|---|---|
| GET | `/questions` | Paginated questions and total count matching filters |
| GET | `/question-filters` | Distinct purposes, run IDs, record IDs, and languages from saved questions |
| POST | `/runs` | Validate input and capacity; return HTTP 409 for a shortage, otherwise persist a running run and return HTTP 202 with `{run}` |
| GET | `/runs` | Latest 50 runs across all records, as `{runs}`; legacy unpaginated interface |
| GET | `/runs?page=1&page_size=25` | Paginated jobs as `{runs, total, page, page_size}`, reaching all saved runs |
| GET | `/runs?input_record_id=416` | Latest 50 runs for this record, including batches with saved questions for it |
| GET | `/runs/:id` | `{run, questions}`, or HTTP 404 |

Job pagination accepts `page` from 1 to 1,000,000 (default 1) and `page_size` from
1 to 100 (default 50). Invalid values return HTTP 400. The optional `input_record_id`
filter also works with pagination, although the jobs tab intentionally requests all
records. The implementation is `question-generation-jobs.svelte` and
`listQuestionJobs` in `questionGeneratorService.ts`; the existing status panel remains
in `question-generator-view.svelte`.

The shortage response is `{confirmation_required, available_targets, available_questions,
requested_questions}` for every purpose (`available_targets` replaced `available_metrics`
on 2026-11-11). `confirmation_required` is false at zero capacity; otherwise
the client asks the user and resubmits with `confirmed_available_questions` only after
acceptance. Missing canonical files and database errors remain failures, not shortages.

Migration `20261025000005_question_generation_requested_count.sql` raises each stored
per-hop count limit from 50 to 1,000 for question-count requests. Startup applies the
project migrations before serving requests. Rollback restores the old checks and
fails transactionally if any run exceeds 50 metrics; it never deletes run history.

The question-count and confirmation contract is in
`ChenWeb/openspec/changes/question-generator-indirect-hops/specs/question-generator-hops/spec.md`;
update that spec when changing this behavior.

`GET /questions` accepts optional `purpose`, `run_id`, `input_record_id`, `lang`,
`created_from`, and `created_to`, combined with AND. Values are SQL parameters.
Positive `page` defaults to 1 (maximum 1,000,000); `page_size` defaults to 50
(maximum 100). Results sort by `created_at DESC, id DESC` and return
`{questions, total, page, page_size}`. `GET /question-filters` returns
`{purposes, run_ids, record_ids, languages}`. Both endpoints use the same admin
middleware as generation. The older run-history endpoints remain available.

`testbed.generated_question_runs` holds Purpose, Description, counts, language,
model reference and resolved model name, prompt filename, creator, timestamps,
`running` / `done` / `failed` status, per-document limits, total targets, generated
counts per hop, document processing count, and expiration deadline. Batch runs
have a null `input_record_id` in the database (returned as zero by the API).
`documents_processed` counts document visits with saved questions, including partial
documents and repeat visits, once per visit regardless of correction writes.
For new runs, the three per-hop requested counts each equal the metric count,
and their total targets each equal Total metrics. Existing run rows are unchanged.

`testbed.generated_questions` holds one row per question: `run_id`,
`input_record_id`, `purpose`, `prompt_name`, `model_name`, `created_at`, `hop_type`, `question`, `answer`, `reasoning_steps`,
`step_line_ids`, `evidence` (objects containing `line_id` and `text`), `set_no`,
`metric_id`, `metric_snapshot`, `artifact_type`, `artifact_id`, `artifact_snapshot`, `lang`,
and `source_sha256`. `artifact_type` / `artifact_id` identify the target for every purpose
(metric questions store `metric` and their metric ID). Registry targets store the registry
row (type, ID, labels, `snippet_basis`, source title, spans, semantic payload) as
`artifact_snapshot` and leave `metric_id` empty and `metric_snapshot` `{}`. Each question keeps its
actual input ID even when its run samples many documents. Its non-null `purpose`
is copied from the saved run when inserted and included in question API responses;
model-supplied purpose is ignored. `prompt_name` and `model_name` are also copied
from the parent run on insertion and returned by question APIs. Existing questions
are backfilled from their parent runs, preserving historical purposes and known
model/prompt values (an unknown historical model stays empty). The metric snapshot is
copied from the loaded database metric, not accepted from model output. Set numbers
identify metric sets within one document model call, shared by their three
questions. New metric snapshots include `context` and `context_line_ranges`;
historical snapshots with `context_line_ids` remain readable. The hash covers the serialized
union of selected context lines, not the raw file bytes. Legacy run-level source hashes
remain readable. Deleting an input deletes its questions and its single-document
runs; a batch run and its other documents' questions remain.

Each accepted batch of questions and its progress counters commit in one transaction.
When an initial response contains invalid questions, its valid questions commit before
the correction call. A correction appends only newly accepted slots, without replacing
earlier valid questions or counting the document again. The run becomes Done only when
all requested slots were accepted; unresolved questions leave it Failed with the saved
results and diagnostics intact. In batch mode, attempted metric sets consume the planned
budget even if some of their questions are rejected; the worker does not silently resample
metrics to replace those questions. A later batch failure preserves committed results. Single
document runs expire after ten minutes, batches after one hour. History reads mark
expired runs failed, and a late worker cannot revive them. Worker contexts enforce
the same limits. Failure details and progress appear in the run inspector.

Migrations: `20261024000001_create_generated_questions.sql` (initial schema) and
`20261024000011_question_generator_metric_batches.sql` (batch/metric metadata),
and `20261024000012_add_generated_questions_purpose.sql` (question-level purpose
and historical backfill), plus
`20261024000013_add_generated_questions_model_prompt.sql` (question-level model
and prompt provenance), and `20261111000010_generated_questions_artifact_target.sql`
(the three `artifact_*` columns on the live and archive tables, metric backfill; its
rollback refuses while non-metric questions exist).
The existing startup project migrator applies them before routes are served. The
second migration retains historical rows and backfills their counts and languages.
Its rollback refuses to proceed while batch runs exist, because the original schema
cannot represent them.

### Question validation

Hop types measure how indirect a question is — how much a searcher must work out
before knowing which metric to look up (prompt v3, openspec
`question-generator-indirect-hops`):

- **one-hop** names the metric and asks for its value: the question is itself a
  good search query.
- **two-hop** must not name the metric; it describes a situation, purpose or
  condition whose answer is the metric, so one inference is needed to know what to
  search for. Example: "After the gas cooler reaches steady state, how long must I
  keep recording?" instead of "What is the minimum test duration?".
- **multi-hop** must not name the metric either, and identifying it takes a chain
  of at least two inferences (e.g. scenario → method or table → metric).

Every question has exactly one target metric; "what are X, Y and Z" lists are not
allowed. The model input carries both `metric_name` and `metric_name_en`, and the
server rejects a two- or multi-hop question containing either name
(case-insensitive, names of two or more characters); the correction round passes
that error back. Close paraphrases are forbidden by the prompt but not checked.

Before v3 (runs 1–9, prompts v1/v2), a hop meant a reasoning step over the evidence:
most two- and multi-hop questions named the target and asked for several values at
once, and semantic search still found 98–100% of targets in the top 10. Those
questions remain stored; filter by run (or prompt) to benchmark only v3 questions.
Each question needs at least one, two, or three reasoning steps respectively. Distinct
facts can share a table's canonical line. Every step must have citations, and the
evidence must be their exact union, including a source line for the selected metric.
The returned set/hop/language must exactly match an assigned target. Evidence text
is copied from the loaded source by the server, never accepted from the model.

The version 2 prompt returns a `reasoning` array of objects, each with `text` and
its own nonempty `line_ids`. Keeping each explanation together with its citations
avoids the mismatched parallel arrays repeatedly produced for one-hop questions
in run 8 (input 753). A one-hop question can still have two written explanations;
each must supply citations, even if they cite the same line. The server converts
these objects into the existing stored `reasoning_steps` and `step_line_ids`, and
derives evidence from their unique citation union. No schema or browser API change
is needed. Missing citations, unknown source lines, and unsupported steps still
fail validation; the server does not fill in missing citations.

Legacy parallel-array responses remain supported for custom prompts and undergo
the same strict alignment validation. A response cannot mix paired objects with
legacy arrays. Version 1 remains available; deployments explicitly setting
`PROMPT_GENERATE_METRIC_QUESTIONS` to version 1 must switch it to version 2 to use
the paired output contract.

If a parsed model response fails validation, the generator makes one correction
call with the same sampled metrics, contexts, language targets, run ID, and input
record ID. Its JSON input adds `validation_error` and `previous_response`; the
Search Metrics prompt instructs the model to address every reported error, check
the full array for citation alignment, blank fields, and duplicate questions,
preserve valid questions, and return the full corrected question
array. Both attempts use the same strict validation, input-size cap, and run
deadline. Every question is decoded and validated independently; malformed or missing
neighbors do not invalidate accepted questions. The correction can fill unresolved
`(set_no, hop_type)` slots, but cannot replace an accepted slot. Duplicate checks use the
questions that are actually retained, ignoring replacement candidates for accepted slots.
A second invalid response leaves successful questions saved and reports the remaining
failures. Provider/request errors do not trigger a further correction call or erase
earlier accepted questions. Each call
is recorded separately in LLM usage logs under the same allocated LLM run ID.

Reasoning errors report the actual counts, for example two reasoning steps but
one citation array. Multiple explanations supported by one source line still
require one citation array per explanation; the server does not infer or copy
missing citations. This reproduces the failure seen in run 6 for input 416.

For a correctly sized, decodable response, structural validation checks every
question and reports the first failure for each invalid question together with
any hop-count errors. This prevents an early citation mismatch from hiding later
invalid questions in the correction request, as could happen in run 7 for input
753. Blank question text, missing answers, and duplicate text have separate error
messages; duplicate errors identify the earlier question, ignoring case and
whitespace. Metric assignment and context checks run after structural validation
passes. A correction can still fail; this feedback does not guarantee valid model
output. Structural/name-leak diagnostics retain the question's original position in
the model response, so “question 57” is a response position, not a saved database ID.

The run 12 diagnostic naming “保温层长度” means that a multi-hop question directly
included the target metric name. This gives away the lookup instead of requiring the
intended inference. The name-leak rule remains strict; the persistence change saves
the other valid questions. This change applies to new generation attempts; it does
not reconstruct questions discarded by already-finished runs.


The server rejects unknown hop types, wrong per-category counts, blank questions
or answers, duplicate questions (ignoring case and whitespace), empty reasoning,
unknown or repeated evidence lines, and unsupported reasoning steps.

## Known limitations

- The Hybrid Search Benchmark still runs only Search Metrics questions. Running the
  other purposes there is a follow-up change.
- Chunk and knowledge rows are not in the search registry yet, so those purposes report
  that no document has such items; Mix includes them automatically once rows exist.
- Registry targets inherit the quality of the extracted items. In the first live check
  (record 416, 2026-11-11) entity and relation questions were only as good as their rows
  (a relation "this standard specifies separate collection" gives a thin question), and
  summary questions tend to ask about several points the summary covers.
- Entity and relation rows have no embeddings (`EMBED_ENTITY_RELATION` off), so semantic
  search cannot find them; this matters once the benchmark runs those questions.

- Validation checks structure and citation existence. It cannot establish that an
  answer is correct or that the requested reasoning actually needs multiple facts.
- The model may fail to produce supported questions for all targets. Batch mode
  tries other documents, then reports failure if no progress is possible. Generated
  progress remains visible; failed batches are not marked complete.
- Generation uses an in-process background worker. A server restart interrupts it;
  history reads report failure after the deadline. Interrupted runs do not resume
  automatically.
- The legacy run-history API shows the latest 50 matching runs. The question
  browser uses pagination across all matching questions.
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
- Spec `ChenWeb/openspec/specs/question-generator-artifact-types/spec.md` and archived change `ChenWeb/openspec/changes/archive/2026-11-11-question-generator-artifact-types/` (purposes, registry targets, Mix)
- [Input and line-file management](../../../Capsules/coding-capsules/input-management/+CAPSULE.md)
- [Implementation plan](../../../Capsules/coding-capsules/llm-wiki/question-generator-implementation.md)
