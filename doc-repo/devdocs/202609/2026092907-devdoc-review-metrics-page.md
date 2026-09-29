# Review Metrics Page — an LLM checks the metrics extracted from a document

**Date:** 2026-09-29 \
**Scope:** What the System Admin → LLM → Review Metrics page does, where its parts
live, and its limits. Open this before changing the review prompt, the report
format, or how reviews are stored.
**Code root:** `ChenWeb/server/api/kbhandler/metric_review_handler.go`,
`ChenWeb/web/src/lib/components/home3/metric-review-view.svelte`

**Traceability — openspec** (changes `llm-review-metrics` and
`metric-review-i18n-export` (languages, translation, export); paths move under
`openspec/changes/archive/` once archived):
- `ChenWeb/openspec/changes/llm-review-metrics/proposal.md` — why this exists
- `ChenWeb/openspec/changes/llm-review-metrics/design.md` — rationale, alternatives
  considered, risks/trade-offs
- `ChenWeb/openspec/changes/llm-review-metrics/tasks.md` — implementation log
- `ChenWeb/openspec/specs/metric-extraction-review/spec.md` (after archive; until then
  `openspec/changes/llm-review-metrics/specs/metric-extraction-review/spec.md`) — the
  canonical requirements; `openspec/changes/metric-review-i18n-export/specs/metric-extraction-review/spec.md`
  adds the language, translation and export requirements. **Update this spec file, not just this doc, if behavior
  changes** — this doc explains the feature for humans and points at code; the spec
  is the contract for agents.

## Summary

The metric extractor reads a document and stores the measurable values it finds
("metrics"). Until now, checking whether it did a good job meant reading the document
line by line against the stored rows by hand, as was done for record 416 in
[2026092903-devdoc-extract-metrics-review-report.md](2026092903-devdoc-extract-metrics-review-report.md).

The Review Metrics page does that check with an LLM. You search for a document, select
it, and press **Review**. The LLM compares the document's text with the stored metrics
and answers three questions:

1. **What was missed?** Values in the document that no stored metric covers.
2. **What should not be a metric?** Stored rows that are not really metrics, are
   duplicates of another row, or are only inputs to a formula.
3. **Are the details right?** For the rows that are real metrics — wrong bounds,
   missing conditions, wrong units, vague subjects, and so on.

The page shows the answer as a report: a short summary, a row of counts (stored, kept,
removed by reason, missed), then one section per question, with every finding pointing
at the metric rows and source lines it is about. Hovering a metric ID shows that
metric's name, value and line.

Reviews are saved. Selecting a document that has already been reviewed shows the saved
report straight away without calling the LLM again. To run a new review anyway — for
example after changing the extractor — tick **Force to Review**; the new review is
saved alongside the old ones and becomes the one shown.

### Languages, translation and export

Each review is written in one language — the language the page is shown in (English or
中文, switched in the site header). Selecting a document looks for a review **in the
current language only**. If there is none, but a finished review exists in the other
language, the page asks whether to translate it; pressing **Translate** has the LLM
translate that report, which takes 10–20 seconds instead of the minute or more a new
review takes. A translation only changes wording: counts, metric IDs, severities,
categories and field codes (such as `lower_bound`) are copied from the original, and the
report says "Translated from review #N". Pressing **Review** instead runs a fresh review
in the current language. If a translation fails, the page shows "Translation failed" with the
**Translate** button again, so it can be retried without a full review.

**Export** (next to Review) saves the review on screen:

- *Export Markdown* downloads `review-<record>-<lang>.md`.
- *Export PDF* opens a print-ready copy of the report and the browser's print dialog —
  choose "Save as PDF" there. (This keeps Chinese text correct without bundling fonts.
  If nothing opens, the browser blocked the pop-up; allow pop-ups for the site.)

Both export only the current-language review.

A review takes from under a minute to a few minutes. It runs in the background: the
page shows "Reviewing…" and updates itself when the report is ready, so you can leave
it open.

## Where things live

| What | Where |
|---|---|
| Menu | System Admin → LLM → Review Metrics (nav id `sysadmin-llm-review-metrics`) |
| Page | `web/src/lib/components/home3/metric-review-view.svelte` + `metric-review-client.ts` |
| Server | `server/api/kbhandler/metric_review_handler.go` — `GET /api/v1/kb/metric-reviews/:record_id?lang=`, `POST` (body `{force, lang}`), `POST …/:record_id/translate` (body `{lang}`) |
| Stored reviews | table `kb.metric_reviews`, one row per run (migrations `20260929000002_create_kb_metric_reviews.sql`, `20260929000003_add_lang_to_kb_metric_reviews.sql`) |
| Prompt | `prompts/prompt-review-metric-extraction-v2.md` (v1 = English-only), named by env var `REVIEW_METRICS_PROMPT` |
| Translate prompt | `prompts/prompt-translate-metric-review-v1.md`, named by env var `REVIEW_METRICS_TRANSLATE_PROMPT` |
| Page text | `web/messages/{en,zh-cn}.json`, keys `mrv_*`; export builders in `metric-review-client.ts` |
| Model | any `llm` entry in `ChenWeb/.models.toml`, named by env var `REVIEW_METRICS_MODEL_NAME` (dev: `gpt-6-luna`) — see "Choosing the model" below |
| LLM usage | logged like other calls; filter LLM Usage Logs by call reason `review_metrics` (reviews) or `review_metrics_translate` (translations) |

Document search reuses the existing `GET /kb/inputs` endpoint: a number searches by
record ID, anything else searches titles. Admins see all records; other users see only
their own.

The three env vars live in `mise.local.toml` for development; **the production config
must add them too**, or every review (or translation) fails with an error naming the
missing variable. If `REVIEW_METRICS_PROMPT` still names v1, reviews come out in English
whatever the page language.

The prompt is named `prompt-review-metric-extraction-*`, not `prompt-review-metrics-*`:
the latter family already belongs to the Doc Review cross-document metric reviewer.

### Database tables

| Table | Used for | Access |
|---|---|---|
| `kb.metric_reviews` | The stored reviews — one row per run with language (`lang`: `en` / `zh-cn`), status (`running` / `done` / `failed`), the report (JSON), error message, model and prompt names, metric count, who ran it and when, and for a translation the review it was translated from (`translated_from_id`). Created by this feature. | read + write |
| `kb.metrics` | The extracted metric rows being reviewed (all rows with `input_record_id` = the selected record). | read only |
| `kb.inputs` | Document search on the page, and the reviewed document's title, doc number and `result_filename` (which locates its line-numbered text file). | read only |
| `public.llm_usage_event` | One row per LLM call, written by the shared LLM client — this is what LLM Usage Logs shows. | written by the shared client |

The document text itself is not in a table: it is read from the line file next to
`kb.inputs.result_filename` (e.g. `Artifacts/0/416/std_1503937_mineru.txt`).

### Choosing the model

The review can use **any `llm`-type model defined in `ChenWeb/.models.toml`**. Put the
model's section name (the text in `[...]`) in `REVIEW_METRICS_MODEL_NAME`, e.g.
`"deepseek-flash-processor"`, `"qwen3-6-plus"`, `"gpt-6-luna"`, or a local `mlx-…` model. No
code change is needed.

- The entry must have `model_type = 'llm'` and non-empty `model_name`, `api_key`,
  `base_url` and `timeout_sec`; otherwise the review fails with an error naming the missing
  field. Embedding models and `decision-model` entries (e.g. `jev-latest`) cannot be used —
  the review needs a chat model that returns JSON.
- Models that reject `temperature: 0` (OpenAI reasoning models such as `gpt-6-luna`) need
  `omit_temperature = true` in their entry — see
  [2026092908-devdoc-llm-omit-temperature.md](2026092908-devdoc-llm-omit-temperature.md).
- The model must accept the whole document plus its metrics in one request (up to 600 000
  characters) and answer within its `timeout_sec`. Small local models and entries with a
  short timeout (the `gpt-5-*` entries use 100 s) may fail on large documents.
- The env var is read from the server's environment, which `mise` sets when the server
  starts: after changing `REVIEW_METRICS_MODEL_NAME`, restart `mise dev`. Each review
  records the model it used, so reviews by different models can be compared.

## Known limitations

- **The review is advisory.** Nothing on the page changes the stored metrics; fixing
  what it finds is still a separate step.
- **Very large documents cannot be reviewed.** The whole document and all its metrics
  go to the LLM in one call. Above 600 000 characters the review fails with a "too
  large" message rather than reviewing half a document.
- **The LLM can be wrong.** Its judgement of what "is a metric" follows the rules in
  the prompt, which are precision-first; treat findings as a checklist to confirm. The
  server does guard the numbers: it computes the counts itself and throws away any
  metric ID the LLM cites that does not exist.
- **Only the latest review in the current language is shown.** Earlier reviews stay in `kb.metric_reviews` for
  comparison, but the page has no history view.
- **A server restart interrupts a running review.** It is shown as failed
  ("interrupted") after 10 minutes, and can be run again.
- **Only English and 中文** are supported (the site's two languages). Quotes from the
  document stay in their original language in both.
- **A translation repeats the original's mistakes**; it is not a second opinion. Run a
  fresh Review for that.
- **Export PDF goes through the print dialog**, not a direct download.
- The menu label has no Chinese translation yet (menu labels come from the page-config
  overrides, not from `messages/*.json`).
