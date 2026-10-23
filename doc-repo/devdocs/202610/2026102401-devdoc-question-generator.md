# Question Generator — document-grounded search benchmark candidates

**Date:** 2026-10-24 \
**Scope:** Generating, saving, and inspecting questions for one input document. \
**Code root:** `ChenWeb/server/api/kbhandler/question_generator*.go`

## Summary

Question Generator creates candidate questions for evaluating document search.
Open **System Admin → Benchmark → Question Generator**, enter an input record ID,
describe the questions' Purpose and optional Description, and choose how many
one-hop, two-hop, and multi-hop questions to generate. Each count starts at ten.
The system reads the record's canonical line file and generates questions in the
current interface language, English or Chinese.

Generation runs in the background. The page shows its status and lets you reopen
saved runs for the same record. Each question includes a reference answer,
reasoning steps, and copies of the cited source lines. Previous runs are kept.
These are generated candidates that need human review before use as a benchmark.

## Details

### Inputs and configuration

- `input_record_id`: positive `kb.inputs.id`; the source is its parsed line file,
  resolved through `docprocessing.LoadRecordLinesByID`, not a browser-supplied path.
- `purpose`: required, up to 2,000 characters. Guides question selection.
- `description`: optional additional context, up to 10,000 characters.
- `one_hop_count`, `two_hop_count`, `multi_hop_count`: optional integers, default
  ten each; 0–50 per category, with a positive total. Zero disables a category.
- `lang`: `en` (default) or `zh-cn`; the page sends its active locale. Saved content
  retains the language used for that run when the interface language changes.
- `QUESTION_GEN_MODEL_NAME`: model reference in `.models.toml`, default
  `deepseek-flash-processor` when unset or blank. Uses the existing configured
  provider client and usage logging.
- Prompt: `ChenWeb/prompts/prompt-question-generator-v1.md`, loaded through the
  existing prompt resolver (`PROMPT_DIR` or the project's prompts directory).

The full source is sent to the model without truncation. Empty sources fail;
formatted source inputs exceeding 600,000 characters fail explicitly. The model's
own context and output limits may impose lower limits.

### API and storage

All endpoints require an authenticated administrator or owner:

| Method | Path under `/api/v1/kb/question-generator` | Result |
|---|---|---|
| POST | `/runs` | Validate input, persist a running run, return HTTP 202 with `{run}` |
| GET | `/runs?input_record_id=416` | Latest 50 saved runs, newest first, as `{runs}` |
| GET | `/runs/:id` | `{run, questions}`, or HTTP 404 |

`testbed.generated_question_runs` holds Purpose, Description, counts, language,
model reference and resolved model name, prompt filename, creator, timestamps,
source SHA256, and `running` / `done` / `failed` status. The hash covers the full
ordered, serialized source-line content supplied to the model; it is not a hash of
the raw line file's bytes.

`testbed.generated_questions` holds one row per question: `run_id`,
`input_record_id`, `hop_type`, `question`, `answer`, `reasoning_steps`,
`step_line_ids`, and `evidence` (objects containing `line_id` and `text`).
The composite foreign key ensures a question and its run reference the same input.
Deleting the input deletes its runs and questions. A new generation preserves
previous question sets.

Questions and successful completion commit in one transaction. An invalid model
response or failed write saves no partial question set. Runs still running after
ten minutes are marked failed on history/detail reads; a late worker cannot turn
an expired or failed run into a successful one. The model call and save operation
also have a ten-minute worker deadline. Failure details appear in the run inspector.

Migration: `ChenWeb/project_migrations/20261024000001_create_generated_questions.sql`.
It is picked up by the existing startup project migrator before routes are served.

### Question validation

The prompt defines one-hop as direct fact retrieval, two-hop as combining two
independently evidenced facts, and multi-hop as combining at least three linked
facts. Each needs at least one, two, or three reasoning steps and distinct cited
source lines respectively. Every step must have citations; the question's evidence
must be their exact union. Evidence text is copied from the loaded source by the
server, never accepted from the model.

The server rejects unknown hop types, wrong per-category counts, blank questions
or answers, duplicate questions (ignoring case and whitespace), empty reasoning,
unknown or repeated evidence lines, and unsupported reasoning steps.

## Known limitations

- Validation checks structure and citation existence. It cannot establish that an
  answer is correct or that the requested reasoning actually needs multiple facts.
- The model may fail to produce the requested quantities or supported hop types;
  such runs fail rather than saving a smaller or padded set.
- Generation uses an in-process background worker. A server restart interrupts it;
  history reads report failure after the deadline. There is no automatic retry.
- Each history request shows the latest 50 runs for the selected record.
- The page inspects saved candidates; it does not score search results, edit
  questions, or mark candidates as an approved benchmark.

## Related documents

- [Hybrid search](../../../Capsules/coding-capsules/llm-wiki/hybrid-search.md)
- [Input and line-file management](../../../Capsules/coding-capsules/input-management/+CAPSULE.md)
- [Implementation plan](../../../Capsules/coding-capsules/llm-wiki/question-generator-implementation.md)
