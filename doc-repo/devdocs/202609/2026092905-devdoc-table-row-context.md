# Table Row Context — metrics taken from tables now carry their whole table row

**Date:** 2026-09-29 \
**Scope:** How ChenWeb points at individual rows of a table, and how it builds the
context text shown and searched for metrics extracted from tables. Open this if a
table metric's context looks wrong, or before changing how tables reach the LLM.
**Code root:** `ChenWeb/server/api/doc-processing/` (`table_grid.go`,
`table_metric_context.go`, `table_context_window.go`, `table_context_backfill.go`)

**Traceability — openspec:**
- `ChenWeb/openspec/changes/table-row-context/proposal.md` — why this exists
- `ChenWeb/openspec/changes/table-row-context/design.md` — rationale, alternatives
  considered, risks/trade-offs
- `ChenWeb/openspec/changes/table-row-context/tasks.md` — implementation log,
  including anything not independently verified
- `ChenWeb/openspec/specs/table-row-addressing/spec.md` and
  `ChenWeb/openspec/specs/table-metric-context/spec.md` — the canonical requirements
  once the change is archived (until then, under the change's `specs/` folder).
  **Update the spec, not just this doc, if behavior changes** — this doc explains the
  feature for people and points at code; the spec is the contract for agents.

## Summary

When ChenWeb reads a PDF, the parser (MinerU) turns every table into one single
"line" of text, however many rows the table has. Each metric we extract remembers
which lines it came from, so a metric from a table could only ever point at "the
whole table". The short description stored with it (its *context*) was written
freely by the AI model, which usually produced a thin summary such as
`表1 … 易腐垃圾-机器成肥`. That dropped the cells that actually matter — for the
metric 比能耗, the technical requirements and where the rule applies.

The system now works with tables row by row:

- **Every row has a name.** Header rows are `h0, h1, …` and data rows `r1, r2, …`.
  Merged cells are copied into every row they cover, so each row makes sense on its
  own. Line numbers are unchanged; a row is addressed as "line 116, row r1".
- **The AI sees tables as numbered rows** instead of raw web markup, and is asked to
  name the rows a metric came from.
- **The context is now built by code, not written by the AI.** For a table metric it
  is the table caption plus the complete matching row, written as
  `column: value` pairs. The row is found from the rows the AI named, or by looking
  for the metric's name and value in the cells. Small tables (five rows or fewer) are
  included whole when no single row can be picked.
- **Neighboring rows are shown but never stored.** When a person opens the metric
  popup on the PDF, or when the doc-review system compares metrics, the row above and
  the row below are shown too, with the matched row highlighted. They are left out of
  the stored context on purpose: that text feeds search, and storing neighbors would
  make a search for one row's treatment method find metrics from the next row.

Existing metrics were updated once, with no AI calls, by a backfill command. On
2026-09-29 it updated 143 of the 176 table metrics on the staging database.

## Where things live

- **Seeing it:** in the metric management view (the page with metric cards next to
  the PDF), open a record and click a metric that comes from a table. The floating card on the PDF shows a small table (caption, header, matched
  row highlighted, one neighbor row each side).
- **Stored data:** column `kb.metrics.source_table_rows` (added by migration
  `project_migrations/20260929000001_add_kb_metrics_source_table_rows.sql`) holds
  which rows a metric came from, plus a fingerprint of each row so a changed table is
  noticed. `metric_context` holds the rebuilt text.
- **Prompt:** `ChenWeb/prompts/prompt-enrich-metrics-v6.md` (the default; a local
  `ENRICH_METRICS_PROMPT` setting overrides it).
- **Backfill command:** `server/cmd/table-metric-context-backfill`. Run it with
  `mise exec -- go run ./server/cmd/table-metric-context-backfill --dry-run
  --record-id <id>` to preview; drop `--dry-run` to write. Running it twice changes
  nothing the second time.
- **Popup UI:** `web/src/lib/components/home3/metric-mgmt-view.svelte` and
  `metric-table-context.ts`.

## Known limitations

- **Highlighting on the PDF is still for the whole table.** The parser gives only
  one box for the entire table, not per row.
- **The English context is not rebuilt by the backfill.** Only the source-language
  context is rebuilt without AI; `metric_context_en` stays as the AI wrote it until
  the document's metrics are extracted again with the new prompt.
- **Some metrics keep the AI's context.** When a large table has no single row that
  clearly matches and the AI named no row, the old text is kept and a warning is
  logged (15 of 176 on the staging database).
- **Header detection is a best guess.** The parser does not mark header rows, so the
  first row is treated as the header, plus the next one when the first has merged
  cells. Tables with no header, or with unusual layouts, can get odd column labels.
- **Only metrics store row references so far.** Provisions, inventory items and the
  other extractors see the numbered-row tables, but do not yet save which rows they
  used.
- **Tables split across pages** are two separate table lines; each is handled on its
  own.
