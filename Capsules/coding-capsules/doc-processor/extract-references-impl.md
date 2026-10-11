# extract_references — implementation notes

Code: `ChenWeb/server/api/doc-processing/`

| File | Holds |
|---|---|
| `extract-references.go` | `ReferencesProcessor` (chunk batching), payload parsing, assembly, own-identity choice, holding event |
| `reference_model.go` | governed vocabularies, `RefMention`, `normalizeRefMention`, stable keys |
| `reference_identifiers.go` | identifier parsing (standard, RFC, legal, DOI, arXiv, ISBN, ISSN, PMID, patent, URL), identity key, own identifier |
| `reference_normativity.go` | list linking, normativity, `list_mismatch` |
| `reference_table_rows.go` | table row validation, system hashes and evidence via metrics table helpers; row locations for deduplication and stable keys |
| `reference_store.go` | mentions, catalog (R1), own-document attachment, holdings with access (R2) |
| `reference_resolver.go` | resolver interface and registry, `ResolveOutgoing` (step 5), `ResolveIncoming` (step 6 / holding event) |
| `reference_metric_resolver.go` | metric family: scoring policy `metric_reference_match/v1`, `Apply` (links + `<rec>_rfm_<n>` rows) |
| `reference_kbmetrics_guard_test.go` | guard: every `kb.metrics` reader has a `ref_mention_id` predicate or an allowlisted reason |

Migrations: `ChenWeb/project_migrations/20261011000001_create_kb_reference_tables.sql`,
`20261011000002_add_reference_columns_to_kb_metrics.sql`,
`20261011000004_add_reference_source_table_rows.sql`.

## Things that are easy to get wrong

- **Overlapping chunks report the same occurrence twice**, sometimes with different raw text. The
  assembly key is the list line (including logical row locations for tables) for listed entries,
  and source location plus cited identity for in-text references. Different table rows stay distinct.
- **Positional ids.** `metric_id` and `drop_id` change on every re-extraction. Links also store
  stable keys (`mention_key`, `target_artifact_key`), so later human decisions can reattach.
- **Concurrency.** `Apply` takes `pg_advisory_xact_lock` per referencing record before numbering
  `<rec>_rfm_<n>`, and link inserts are idempotent. Each event commits before it looks for the
  other side.
- **No `Withdraw`.** Re-resolving replaces. Deleting a mention cascades its rows and links.
  Deleting an input runs `deleteInputReferenceRows` (`kbhandler/metrics_handler.go`).
- **Standard numbers.** Known publisher prefixes are matched case-sensitively. A generic prefix
  (CJJ 27, JJG(苏)263) is allowed only when the model labelled the citation `standard_number`, or for
  the document's own number.
- **Normativity is never inferred from wording.** `in_requirement` carries the wording.
  `not_listed` is set only for references with a public identifier.

## Verification done (2026-10-11)

- Unit tests for parsing, normativity, assembly, scoring and the reader guard.
- Table provenance: row-aware deduplication, header/multirow evidence, system hashes, mixed prose,
  invalid rows and unmatched tables. PostgreSQL scratch-database test covers mention storage/load,
  resolved metric provenance, and migration rollback/reapply.
- `go test ./api/... ./cmd/...` green.
- Live runs on records 753, 373 and 362, with a synthetic step 5/6 check (362 → 373). See the
  openspec `tasks.md` for what was and was not verified, including the missing non-Chinese live run.

## References workspace

`references-mgmt-view.svelte` uses `KbInputRecordBrowser` with `fitPanel` so its document list
fills the host grid panel. This mode hides the browser's independent width controls. The host's
divider between records and references redistributes their combined width, supports pointer and
arrow-key adjustment, and persists both widths in localStorage.
The selected mention's `source_table_rows` is passed to `PdfViewWindow.tableReferences`, which
uses the shared table geometry endpoint to highlight the cited rows and navigate to their page.
The prose overlay skips lines with row provenance, avoiding a whole-table rectangle over the
row highlights. Selecting a prose reference clears table highlights and retains line highlights.
The viewer's `floatingOverlay` snippet shows a dark Reference Info card next to the highlight,
with the selected reference's title, ID, type/content, normativity, holding state and excerpt.
It updates on every selection, fits inside the viewer, and allows selection/copying of its text.
Dragging its heading uses the shared viewer's overlay positioning.

Verified with a headless browser and synthetic API/PDF fixtures: panel fit at 1800px and 1400px,
two cited row highlights without a whole-table overlay, switching to prose and back, divider
drag/keyboard/reload persistence, and info card content, containment and text selection.
