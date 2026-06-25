# Document Review Specification

**DocID:** `doc-20260621` (derived from ADR 2026061801)
**Status:** Implemented (Phase VI)
**Date:** 2026-06-21

## Scope

This document describes the architecture and implementation of the Document Review feature — an LLM-powered multi-aspect review pipeline built on top of the SemOS document processor. The full design is in ADR 2026061801; this spec covers the service layer (DR11–DR13) that makes the review accessible to end users.

## Related Documents

- **ADR:** `doc-repo/adrs/202606/2026061801-adr-document-review.md`
- **Design:** `doc-repo/design/202606/2026062105-design-doc-review-gui.md`
- **Impl Plan:** `doc-repo/202606/20260621-plan-doc-review-gui.md`
- **Checklist:** `doc-repo/specs/202606/2026061102-spec-document-review-checklist.md`

## Architecture Overview

```
User (GUI) → DocReviewController → ReviewProcessor → kb.doc_review_findings
                                          ↓
                              DocReviewReportGenerator → kb.doc_review_reports
```

Three tiers:
1. **DocReviewController** — validates requests, resolves reviewer configs, manages lifecycle state machine
2. **ReviewProcessor** (existing) — runs reviewers as concurrent goroutines, persists findings
3. **DocReviewReportGenerator** — assembles structured report (JSON + Markdown + HTML) from raw findings

## Key Design Decisions

### DR11 — DocReviewController
- Standalone Go service (not a pipeline processor)
- State machine: `accepted → running → completed | failed | stopped`
- Per-request configuration overrides (model, aspects, reference docs)
- Idempotency guard (one active review per document version)
- **Implementation:** `server/api/docreview/controller.go`

### DR12 — DocReviewReportGenerator
- Report skeleton assembled in Go code (deterministic)
- Executive summary delegated to cheap LLM (one-shot Haiku)
- Three output formats: JSON (stored), Markdown (stored), HTML (on-the-fly template)
- Compliance summary computed from finding counts + reference_doc metadata
- **Implementation:** `server/api/docreview/report.go`

### DR13 — Review Request GUI
- Svelte 5 view in ChenWeb home3 layout (Apps → Document Review)
- 5-step form: document selection (search existing **or** upload a new file) → tier picker → aspect checkboxes → reference docs → submit
- Tier picker (Step 2) shows a foldable, category-grouped list of each tier's checked aspects; aspects are individually toggleable with a per-tier select/deselect-all
- After submit, a **job monitor** (Active-Pipelines style) sits on top of the page (see DR15)
- Results view with polling (3s interval), severity summary cards, filterable findings table with accept/reject/defer, full report view (rendered below the monitor)
- 10 API endpoints under `/api/v1/doc-review/`
- **Implementation:** `web/src/lib/components/home3/document-review-view.svelte`, `doc-review-results-view.svelte`, `doc-review-monitor.svelte`

### DR14 — Configurable Review Tiers
- Review tiers ("Must Review", etc.) and the aspect items they contain are configurable via a `[doc-reviews]` table in `config.toml` / `config.local.toml` (local takes precedence; merged at startup).
- Format: `tier-key = ["aspect_name", ...]`. Built-in tier keys (`must-review`, `should-review`, `review-external`, `review-regulated`) keep friendly labels and fixed order; custom tiers get a derived Title Case label and sort after the built-ins. Unknown aspect names are dropped.
- When no `[doc-reviews]` section exists, `ListTiers()` falls back to built-in tiers derived from each aspect's `Priority` field (unchanged behavior).
- The aspect catalog itself (names/labels/descriptions) remains code-defined in `aspects.go`; config controls only tier membership and which tiers exist.
- **Implementation:** `server/api/docreview/aspects.go` (`ListTiers`/`tiersFromConfig`), `server/cmd/config/config.go` (`GetDocReviewsConfig`, local merge), `ChenWeb/config.local.toml`

### DR15 — Per-Aspect Review Status & Live Job Monitor
- **Status:** Implemented. Supersedes the interim DR13 monitor that mapped all aspects to one job-level status. (Design: `2026062105-design-doc-review-gui.md` §3.3/§4.4/§6/§7.2.)
- **Execution is now async:** `POST /requests` accepts + seeds status rows and returns immediately; the review runs in a background goroutine (detached context) so the monitor can observe it. Submit no longer returns `report_id`; the GUI picks it up from `GET /requests/:id` (`report_id`) once the run completes.
- **Transition fidelity (chosen):** coarse, controller-driven — all aspects flip `pending→running` at run start, then `→success` (with per-aspect `finding_count` from `kb.doc_review_findings`) on completion, or `→failed` on whole-run failure/stop. Per-reviewer live transitions were deferred because Phase-I `ReviewProcessor` runs only `grammar_spelling` and would leave the other aspects without a real signal.
- New table `kb.doc_review_status` holds **one row per `(review_run_id, aspect)`**, created at request-accept time with status `pending`. Per-aspect lifecycle: `pending → running → success | failed`.
- `review_run_id` is now assigned at **accept** time (was: at run-start), so progress is observable from the moment a request is queued.
- **Finished predicate:** an aspect is finished **iff** its status is `success` or `failed`. A job is finished when **all** its aspects are finished, and the request is then marked `completed`.
- **Monitor = global active view:** `GET /api/v1/doc-review/active` returns every request that has ≥1 unfinished aspect (across all users), each with its per-aspect status list. The monitor polls it (3s) and renders one card per active job. **A job drops off the monitor automatically once its last aspect finishes.**
- Per-aspect transitions are reported by the reviewer goroutines (recommended) or, as a fallback, set coarsely by the controller after `ReviewProcessor` returns (see design §4.4).
- **Implementation:** `project_migrations/20260621000003_create_doc_review_status.sql`; `DocReviewController` (`seedAspectStatuses`, `markAspectsRunning`, `finalizeAspectsSuccess`, `failOpenAspects`, `RunReviewAndReport`, `ListActiveJobs`) + `review_run_id` passed into `ReviewProcessor.ReviewRunID`; `GET /active` handler; `doc-review-monitor.svelte` rewritten as a global list polling `/active` (rendered atop the form), with results opened on demand via `doc-review-results-view.svelte`.

### DR16 — Review Request List & Search
- **Status:** Implemented. The Document Review view now renders a list of **all** review requests below the submit wizard (and below the DR15 live monitor), newest first.
- New endpoint `GET /api/v1/doc-review/requests` returns the requests with optional filters; each row carries the document title (joined from `kb.inputs`), the selected aspect count (`jsonb_array_length(aspects)`), and the latest report's id + `total_findings` (subquery on `kb.doc_review_reports`). Results are capped (default 100, max 200) and ordered by `create_time DESC`.
- **Filters (all optional, AND-combined):** `request_id` (exact), `title` (ILIKE on `inputs.title`/`file_name`), `requester` (ILIKE), `tier` (exact), `status` (exact), `create_start`/`create_end` (`create_time` range, `::timestamptz`), `limit`.
- **Search dialog:** clicking **Search** opens a filter dialog styled after the Knowledge document search dialog (`kb-input-search-dialog.svelte`) and mirrors its interaction model: the dialog's **Search** button runs `listRequests(filter)` and renders the matches in a checkbox table (click to toggle, double-click to pick one, header checkbox selects all); **Select (n)** returns the checked requests to the parent, which then shows just that selection. A "Show all" chip restores the full, unfiltered list. Each row's **View** opens that request in `doc-review-results-view.svelte`.
- **Implementation:** `DocReviewController.ListRequests` + `RequestListFilter`/`RequestListItem` (models.go); `ListRequests` handler; route `GET /doc-review/requests` (registered before `/:id`); `web/src/lib/services/docReviewService.ts` (`listRequests`); `web/src/lib/components/home3/doc-review-requests-list.svelte`, `doc-review-search-dialog.svelte`; wired into `document-review-view.svelte`.

## Data Model

### `kb.doc_review_requests`
| Column | Type | Description |
|--------|------|-------------|
| id | BIGSERIAL | Primary key |
| input_record_id | BIGINT | Document under review |
| review_run_id | TEXT | Assigned at accept time (DR15); links findings + status rows |
| tier | TEXT | must_review, should_review, custom, etc. |
| aspects | JSONB | Selected aspect names |
| reference_docs | JSONB | [{record_id, doc_no, title}] |
| requester_name | TEXT | Submitter's name |
| requester_id | BIGINT | Submitter's user ID |
| report_template | TEXT | Optional report template |
| doc_template | TEXT | Optional doc template |
| status | TEXT | accepted → running → completed/failed/stopped |

### `kb.doc_review_reports`
| Column | Type | Description |
|--------|------|-------------|
| id | BIGSERIAL | Primary key |
| request_id | BIGINT | FK to doc_review_requests |
| report_json | JSONB | Full report skeleton |
| report_markdown | TEXT | Markdown export |
| executive_summary | TEXT | Plain text summary |
| total_findings | INT | Count |
| overall_assessment | TEXT | pass_with_issues / fail / needs_review |

### `kb.doc_review_status` (DR15)
One row per reviewed aspect per run; created at accept time, updated as each reviewer runs.

| Column | Type | Description |
|--------|------|-------------|
| id | BIGSERIAL | Primary key |
| request_id | BIGINT | FK to doc_review_requests.id |
| input_record_id | BIGINT | Document under review |
| review_run_id | TEXT | Run identity (matches requests + findings) |
| aspect | TEXT | Reviewed aspect name (e.g. `completeness`) |
| pass | TEXT | "P1".."P6" (denormalized for grouping) |
| status | TEXT | `pending → running → success \| failed` (finished iff success/failed) |
| finding_count | INT | Findings produced by this aspect |
| error_message | TEXT | Set when status = `failed` |
| start_time / end_time | TIMESTAMPTZ | Per-aspect run window |
| | | **Unique:** (review_run_id, aspect) |

## API Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/doc-review/aspects` | List all aspects + groups |
| GET | `/api/v1/doc-review/tiers` | List tier→aspect mappings |
| POST | `/api/v1/doc-review/requests` | Submit review request |
| GET | `/api/v1/doc-review/requests` | **(DR16)** List all requests (filters: request_id, title, requester, tier, status, create_start/end, limit) |
| GET | `/api/v1/doc-review/requests/:id` | Get status + findings |
| GET | `/api/v1/doc-review/reports/:id` | Get report JSON |
| GET | `/api/v1/doc-review/reports/:id/html` | Get HTML report |
| GET | `/api/v1/doc-review/reports/:id/export` | Export (markdown) |
| PATCH | `/api/v1/doc-review/findings/:id` | Accept/reject/defer |
| POST | `/api/v1/doc-review/requests/:id/stop` | Stop running review |
| GET | `/api/v1/doc-review/active` | **(DR15)** All jobs with ≥1 unfinished aspect + per-aspect status (drives the live monitor) |
