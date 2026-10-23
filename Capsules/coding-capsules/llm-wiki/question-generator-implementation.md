# Question Generator implementation plan

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
