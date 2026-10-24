# Question Generator implementation plan

## Current revision: Filterable question browser and generation dialog (2026-10-24)

- [x] List saved questions on page load; remove the site footer only on Question
  Generator. Show model/prompt, purpose, run/record IDs, language, and creation time.
- [x] Move the existing form to a native modal opened by Generate Questions. Retain
  optional input IDs, metric counts, background progress, and failure details.
- [x] Add Purpose, Run ID, Record ID, Language menus populated from distinct table
  values, plus inclusive local From/To time pickers. Search applies all filters;
  Reset clears and re-queries. Keep pagination tied to applied conditions.
- [x] Add admin-only GET `/questions` and `/question-filters` endpoints under the
  existing question-generator API, parameterized filters and stable pagination.
- [x] Add migration 20261024000013 for non-null question `prompt_name`/`model_name`.
  Backfill from parent runs and copy authoritative run metadata on future inserts.
- [x] Extend PostgreSQL tests for backfill/rollback/re-up, insert provenance, API
  responses, combined filters, exact time boundaries, pagination, and SQL parameters.

Verification: generator and PostgreSQL integration tests pass, including combined
filters, exact date boundaries, provenance, pagination, and migration rollback.
Server build and bilingual frontend checks pass. English/dark and Chinese/light
browser fixtures cover default listing, modal focus/Escape, Search/Reset, stale
requests, applied-filter pagination, optional IDs, generation progress and failure,
reasoning/evidence, and footer absence. Migration 13 is applied on staging with
zero question/run model or prompt mismatches.


## Earlier revision: Question purpose column (2026-10-24)

- [x] Add non-null TEXT `testbed.generated_questions.purpose` through goose migration
  `20261024000012_add_generated_questions_purpose.sql`, with rollback.
- [x] Backfill existing questions from their parent run's purpose, including historical
  free-text purposes. New inserts copy the saved run's purpose directly in SQL.
- [x] Include purpose in question API responses and TypeScript types.
- [x] Verify migration up/down/re-up, historical backfill, authoritative insert and
  API round trip in isolated PostgreSQL; run generator tests and build checks.

Staging startup applied the migration: all eight existing questions have
`search_metrics`, with zero question/run purpose mismatches.

## Earlier revision: Correct invalid model output once (2026-10-24)

Run 6 for input 416 returned two reasoning steps but one `step_line_ids` array
for question 1. Its archived response confirms a citation alignment error, not
an absence of reasoning or a problem with the record ID.

- [x] Retain strict reasoning/citation validation and report precise counts.
- [x] Give invalid parsed output one correction call with `validation_error` and
  `previous_response`; retain the exact sampled sets, source context, run ID, and
  language targets. Request the full corrected output through the versioned prompt.
- [x] Validate again before saving. A repeated failure stops the document; provider
  errors do not trigger correction, and the existing run deadline/size cap apply.
- [x] Regression tests reproduce the mismatch, verify corrected triplets, bound
  persistent failures to two calls, and leave provider errors at one call.

Generator/PostgreSQL tests and the server build pass. No live provider call was
made for this revision; the original failed run remains unchanged.

## Earlier revision: Metric counts, triplets, and line ranges (2026-10-24)

- [x] Replace hop count controls with Metrics per document (1–50, default 10) and
  Total metrics (1–1,000, default 10). A specified input ignores the total.
- [x] Sample N metrics per document and generate exactly three questions per metric:
  one-hop, two-hop, and multi-hop, each with an independent English/Chinese choice.
  Batch clipping counts metric sets, keeping all triplets intact.
- [x] Accept `metrics_per_document` and `total_metrics` in the API. Preserve existing
  per-hop storage and saved runs; accept equal legacy hop counts, reject unequal
  legacy requests. Explicit new fields take precedence.
- [x] Replace expanded context IDs in model input and new metric snapshots with
  inclusive `context_line_ranges`, such as `["124:144"]`. Preserve gaps and check
  integer output citations against exact internal IDs.
- [x] Update the Search Metrics prompt, bilingual form, tests, and current devdoc.

Verification: generator and PostgreSQL tests, server build, bilingual type/i18n
checks, and English/dark plus Chinese/light browser fixtures pass. A broader
handler run (excluding the two historical metric-scoring failures) still fails
unrelated model-configuration tests (`deepseek-v4-flash` is missing locally) and
`TestGetRelatedMetricsSimilarClassRanksByMatchedClassScore` (SQL mock argument
mismatch). No live provider call was made for this revision.

## Earlier revision: Bounded metric context and usage correlation (2026-10-24)

- [x] Carry the saved generator run ID and actual input record ID on every LLM
  request so the existing LLM Usage Logs Run ID column is populated. Label run IDs
  explicitly on the generator page in both languages.
- [x] Resolve the Search Metrics prompt through `PROMPT_GENERATE_METRIC_QUESTIONS`,
  with the existing prompt filename as fallback. Preserve the resolved reference
  on generator runs and usage events.
- [x] Let N be the sum of requested per-document hop counts. Sample N metrics,
  without replacement until the usable pool is exhausted, then refill if needed.
  Assign exactly one question target to each sampled metric entry.
- [x] Attach `context` and `context_line_ids` to each sampled metric. Concatenate
  ten actual lines before the first metric line, the metric's own lines, and ten
  after its last line; clamp boundaries and exclude disjoint-span gaps. Do not send
  the full source or full metric inventory. Validate citations within each metric's
  context and hash only the union of selected lines.
- [x] Put document metadata first in the JSON input, ahead of the sampled listing.
  Include record ID, title, document number, filename, date, and extracted metadata.
- [x] Cover input shape, metadata order, prompt override, sampling, large unused
  document content, sparse/disjoint spans, citation isolation, and run correlation
  with tests. Review the implementation and update the current devdoc.

Generator and PostgreSQL tests, server build, and bilingual UI checks pass. The
broader kbhandler suite passes excluding the same two previously documented
unrelated metric-scoring tests. A live call records its saved run ID in
`public.llm_usage_event` and uses a reduced context input. Live inspection also
identified a model response with misaligned per-step citations; the prompt now
explicitly requires one citation array per explanation, including repeated arrays
when multiple steps use the same table line.

## Earlier revision: Search Metrics (2026-10-24)

The user's follow-up replaces the generic purpose with `search_metrics` (dropdown
label Search Metrics), mapped to `prompt-question-generator-search-metrics-v1.md`.
The earlier implementation notes below describe the first version.

- [x] Keep existing hop counts as per-document limits (default 10, range 0–50).
  Add total targets (default 10, range 0–1000 per hop). A specified input ID ignores
  total targets. Otherwise sample eligible inputs in random order, clipping the
  last document's counts to hit every total exactly. A positive target requires a
  positive per-document count for that hop.
- [x] Retrieve stored metrics for each document. Documents without metrics are
  skipped. For each set, randomly choose a metric and create one question per active
  hop type. Randomly assign English or Chinese to each question on the server.
  A document model call receives numbered sets, selected metric snapshots, desired
  languages, and the canonical source. Validate the exact set/hop/language mapping.
- [x] Use a new goose migration: batch runs have nullable input IDs, total targets,
  progress counters, and deadlines; each question keeps its actual input ID,
  metric identity/snapshot, set number, language, and source hash. Save each full
  document transactionally and expose progress. Completed documents remain visible
  if a later failure interrupts a batch. Never revive expired/failed runs.
- [x] Revisit eligible documents if targets exceed a single pass; stop with a clear
  error if an entire pass makes no progress. Missing line files, insufficient
  source evidence, or invalid model output skip that candidate in batch mode.
  Bound the worker by 10 minutes for a single input and one hour for a batch.
  Prior question context and bounded duplicate retries prevent uniqueness conflicts
  from terminating a batch on the first repeated response.
- [x] Add request/selection/target-clipping/metric-provenance/language tests, worker
  and database lifecycle coverage, bilingual frontend and browser fixture checks.
  Review, update the existing devdoc, and commit only this task's files through jj.

Current revision verification: focused generator tests and isolated PostgreSQL
migration/storage lifecycle tests pass, including exact target clipping, metric-free
document skipping, duplicate recovery/exhaustion, preserved batch progress, and old
row retention. `mise build-server` and `bun run check` pass. Browser fixtures pass
in English/dark and Chinese/light with both count groups, optional IDs, history,
per-question metadata and source citations. Real provider calls were not exercised.
The two previously documented unrelated metric-scoring tests remain excluded from
the broader kbhandler check. The new migration is present in the local application
database. An identical duplicate SEARCH_QUERY_KEYWORDS_MODEL_NAME assignment was
removed from ignored mise.local.toml to restore mise parsing, retaining its value.

## Original implementation (historical)

User-approved scope (2026-10-24): a ChenWeb web page and API, with input record ID,
Purpose, Description, and counts for one-hop, two-hop, and multi-hop questions.
Each count defaults to ten. Persist results in `testbed.generated_questions`.

## Design

Add the page under System Admin → Benchmark, using the existing dashboard styling,
English/Chinese Paraglide messages, and selectable text. A form starts generation;
saved runs can be loaded by record ID and opened to inspect their questions.
Use the active UI language for generated content.

`POST /api/v1/kb/question-generator/runs` accepts `input_record_id`, `purpose`,
`description`, optional `one_hop_count`, `two_hop_count`, `multi_hop_count`, and
`lang` (`en` or `zh-cn`). Purpose is required; Description is optional context.
Counts allow 0–50 each, but the total must be positive. Return HTTP 202 with the
persisted run. `GET /runs?input_record_id=...` returns the latest 50 runs;
`GET /runs/:id` returns a run and its questions. All use the authenticated API group.

`testbed.generated_question_runs` stores request metadata, model/prompt identity,
source SHA256, timestamps, and running/done/failed state. Each question is one row
in `testbed.generated_questions`, linked to its run and input, with hop type,
question, reference answer, reasoning steps, and evidence (line IDs plus text
snapshots). Preserve earlier runs. Save all questions and mark the run done in one
transaction. Failed generations save no partial question sets. Runs still running
after 10 minutes are marked failed, including after a server restart. Completion
is conditional on a still-running, unexpired row; otherwise roll back all questions.

Read the full canonical line file with existing document-processing helpers. Fail
explicitly on empty or oversized input instead of truncating it. Use the configured
`QUESTION_GEN_MODEL_NAME` or `deepseek-flash-processor`, and a versioned prompt in
ChenWeb/prompts. Validate nonempty answers, unique questions, exact requested hop
counts, at least 1/2/3 reasoning steps and distinct cited lines for one/two/multi-hop,
and source citations for every reasoning step. The prompt defines direct retrieval,
combining two independently evidenced facts, and combining at least three linked
facts respectively. These structural checks do not establish factual correctness; the
questions are generated benchmark candidates for human review.

## Implementation and verification

- [x] Add failing Go tests for request defaults/bounds and malformed model output,
  evidence validation, and transactional persistence.
- [x] Add the goose migration, request/output validation, asynchronous handlers,
  worker, prompt, and route registration. Run the focused Go tests.
- [x] Build the dashboard page, navigation, API client, and English/Chinese messages.
  Poll only while a run is active; cancel on unmount. Run `bun run check`.
- [x] Review spec compliance and code quality, fix findings, and build the server.
- [x] Test migration Up/Down/Up in an isolated database if local PostgreSQL permits.
- [x] Update the existing Question Generator devdoc to describe actual behavior and
  limitations. Commit only this task's files through jj and inspect linear history.

## Verification results

- Generator validation, handler, administrator authorization, worker success/failure,
  and transaction rollback tests pass.
- Isolated PostgreSQL lifecycle test passes, including Up/Down/Up and rejection of
  late results. The application database also has the generated questions table.
- `mise build-server` and `bun run check` pass (zero Svelte errors/warnings; i18n OK).
- Browser fixtures pass in English/dark and Chinese/light: defaults, validation,
  request payloads, running→done polling, history, answers, per-step citations,
  text selection, and record changes while details are loading. No browser errors.
- The kbhandler suite passes excluding `TestMetricScoreScorerParityAndInvalidMatches`
  and `TestMetricScoreRunnerEndToEnd`, which fail in unrelated metric-scoring frozen
  tool/hash and scorer availability checks. These files were not changed.
- Provider calls used fixtures; this session did not test real model quality or
  incur live generation calls.
