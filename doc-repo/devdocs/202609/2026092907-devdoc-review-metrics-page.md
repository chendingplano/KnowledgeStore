# Review Metrics Page — an LLM checks the metrics extracted from a document

**Date:** 2026-09-29 \
**Scope:** What the System Admin → LLM → Review Metrics page does, where its parts
live, and its limits. Open this before changing the review prompt, the report
format, or how reviews are stored.
**Code root:** `ChenWeb/server/api/kbhandler/metric_review_handler.go`,
`ChenWeb/web/src/lib/components/home3/metric-review-view.svelte`

**Traceability — openspec** (change `llm-review-metrics`; paths move under
`openspec/changes/archive/` once archived):
- `ChenWeb/openspec/changes/llm-review-metrics/proposal.md` — why this exists
- `ChenWeb/openspec/changes/llm-review-metrics/design.md` — rationale, alternatives
  considered, risks/trade-offs
- `ChenWeb/openspec/changes/llm-review-metrics/tasks.md` — implementation log
- `ChenWeb/openspec/specs/metric-extraction-review/spec.md` (after archive; until then
  `openspec/changes/llm-review-metrics/specs/metric-extraction-review/spec.md`) — the
  canonical requirements. **Update this spec file, not just this doc, if behavior
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

A review takes from under a minute to a few minutes. It runs in the background: the
page shows "Reviewing…" and updates itself when the report is ready, so you can leave
it open.

## Where things live

| What | Where |
|---|---|
| Menu | System Admin → LLM → Review Metrics (nav id `sysadmin-llm-review-metrics`) |
| Page | `web/src/lib/components/home3/metric-review-view.svelte` + `metric-review-client.ts` |
| Server | `server/api/kbhandler/metric_review_handler.go` — `GET` / `POST /api/v1/kb/metric-reviews/:record_id` |
| Stored reviews | table `kb.metric_reviews`, one row per run (migration `20260929000002_create_kb_metric_reviews.sql`) |
| Prompt | `prompts/prompt-review-metric-extraction-v1.md`, named by env var `REVIEW_METRICS_PROMPT` |
| Model | `.models.toml` entry named by env var `REVIEW_METRICS_MODEL_NAME` (dev: `gpt-6-luna`, which needs `omit_temperature = true` — see [2026092908-devdoc-llm-omit-temperature.md](2026092908-devdoc-llm-omit-temperature.md)) |
| LLM usage | logged like other calls; filter LLM Usage Logs by call reason `review_metrics` |

Document search reuses the existing `GET /kb/inputs` endpoint: a number searches by
record ID, anything else searches titles. Admins see all records; other users see only
their own.

The two env vars live in `mise.local.toml` for development; **the production config
must add them too**, or every review fails with an error naming the missing variable.

The prompt is named `prompt-review-metric-extraction-*`, not `prompt-review-metrics-*`:
the latter family already belongs to the Doc Review cross-document metric reviewer.

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
- **Only the latest review is shown.** Earlier reviews stay in `kb.metric_reviews` for
  comparison, but the page has no history view.
- **A server restart interrupts a running review.** It is shown as failed
  ("interrupted") after 10 minutes, and can be run again.
- **Report prose is English**; quotes from the document stay in their original
  language. The menu label has no Chinese translation yet.
