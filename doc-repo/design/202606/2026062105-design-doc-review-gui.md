# DR13 — Document Review Request GUI: Design Document

**Date:** 2026-06-21
**Status:** Draft
**Component:** ChenWeb — doc_review
**ADR Reference:** ADR 2026061801 (DR13, DR15)

## Revisions
- 2026-06-22a — **GUI fix: unified Step-2 aspect selection.** The Step-2 "Choose
  Check Level" radios + independent per-tier selections were replaced by a single
  shared aspect set (`selectedAspects`) edited through per-tier **On/Off toggles** and
  per-aspect chips. This removes the bug where a selection made under one tier was
  silently stranded when a different tier's radio was active (summary showed
  "0 selected" despite a checked aspect). The separate "Customize Aspects" step was
  folded into Step 2 (now 4 steps total). "Next" on Step 2 is disabled while the set
  is empty, with a hover help message; submit-time validation now surfaces in a
  confirmation dialog that, on OK, jumps back to the offending step. The persisted
  `tier` is `custom` unless the selection exactly equals one tier's full aspect set.
- 2026-06-21a — Initial DR13 full-stack design.
- 2026-06-21b — **DR15: per-aspect review status + live job monitor.** Added the
  `kb.doc_review_status` table (one row per reviewed aspect per run), moved
  `review_run_id` assignment to request-accept time, and redefined the GUI job
  monitor as a **global** view of all review jobs that still have at least one
  unfinished aspect (an aspect is *finished* iff its status is `success` or
  `failed`). A job leaves the monitor once all its aspects are finished. See §3.3,
  §4.4, §6 (`GET /active`), §7.2.

---

## 1. Overview

Implement DR13 of ADR 2026061801: the Review Request GUI for the SemOS document
review service. Full-stack implementation covering database tables, service layer
(DocReviewController, DocReviewReportGenerator), API endpoints, and frontend
components integrated into the home3 layout.

---

## 2. Architecture

```
Frontend (SvelteKit 5 / home3)
  NavRail ── "Apps → Document Review"
  ContentPanel ── DocumentReviewView (5-step form)
               ── DocumentReviewResultsView (polling, findings table, report)
  │
  │ fetch() ── /api/v1/doc-review/*
  ▼
Backend (Go + Echo v4)
  docreviewhandler/ ── HTTP handlers (9 endpoints)
       │
       ▼
  docreview/ ── DocReviewController (service layer)
       │      ── DocReviewReportGenerator (report builder)
       │      ── aspects.go (aspect definitions, tier mappings)
       │      ── models.go (request/response types)
       │
       ▼
  doc-processing/review-document.go ── ReviewProcessor (existing)
       │
       ▼
  Database
    kb.doc_review_findings   (existing)
    kb.doc_review_requests   (new)
    kb.doc_review_reports    (new)
    kb.doc_review_status     (new, DR15 — one row per reviewed aspect per run)
```

---

## 3. Database Migrations

### 3.1 `kb.doc_review_requests`

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_requests (
    id              BIGSERIAL       PRIMARY KEY,
    input_record_id BIGINT          NOT NULL,
    review_run_id   TEXT,
    tier            TEXT            NOT NULL,       -- "must_review", "should_review", "custom"
    aspects         JSONB           NOT NULL,       -- ["completeness", "grammar_spelling", ...]
    reference_docs  JSONB,
    notes           TEXT,
    model_overrides JSONB,
    requester_name  TEXT            NOT NULL,
    requester_id    BIGINT          NOT NULL,
    report_template TEXT,                           -- template for report doc generation
    doc_template    TEXT,                           -- template for modified doc generation
    status          TEXT            NOT NULL DEFAULT 'accepted',  -- accepted|running|completed|failed|stopped
    create_time     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    start_time      TIMESTAMPTZ,
    end_time        TIMESTAMPTZ,
    error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_doc_review_requests_record ON kb.doc_review_requests (input_record_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_requests_status ON kb.doc_review_requests (status);
```

### 3.2 `kb.doc_review_reports`

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_reports (
    id                BIGSERIAL       PRIMARY KEY,
    request_id        BIGINT          NOT NULL,
    input_record_id   BIGINT          NOT NULL,
    review_run_id     TEXT            NOT NULL,
    report_json       JSONB           NOT NULL,
    report_markdown   TEXT            NOT NULL,
    executive_summary TEXT            NOT NULL,
    total_findings    INT             NOT NULL,
    high_count        INT             NOT NULL DEFAULT 0,
    medium_count      INT             NOT NULL DEFAULT 0,
    low_count         INT             NOT NULL DEFAULT 0,
    overall_assessment TEXT           NOT NULL,
    create_time       TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doc_review_reports_request ON kb.doc_review_reports (request_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_reports_record  ON kb.doc_review_reports (input_record_id);
```

### 3.3 `kb.doc_review_status` (DR15)

Tracks the status of **each reviewed aspect** within a review run. One row is
created per `(review_run_id, aspect)` at request-accept time, so the run's
progress is observable from the moment it is queued — not only when it finishes.

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_status (
    id              BIGSERIAL    PRIMARY KEY,
    request_id      BIGINT       NOT NULL,                    -- kb.doc_review_requests.id
    input_record_id BIGINT       NOT NULL,                    -- the document under review
    review_run_id   TEXT         NOT NULL,                    -- assigned at accept (see §3.1)
    aspect          TEXT         NOT NULL,                    -- one row per reviewed aspect, e.g. "completeness"
    pass            TEXT,                                     -- "P1".."P6" (denormalized for grouping)
    status          TEXT         NOT NULL DEFAULT 'pending',  -- pending | running | success | failed
    finding_count   INT          NOT NULL DEFAULT 0,          -- findings produced by this aspect
    error_message   TEXT,                                     -- set when status = 'failed'
    start_time      TIMESTAMPTZ,                              -- when this aspect transitioned to 'running'
    end_time        TIMESTAMPTZ,                              -- when this aspect finished (success/failed)
    create_time     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    modify_time     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (review_run_id, aspect)
);

CREATE INDEX IF NOT EXISTS idx_doc_review_status_request ON kb.doc_review_status (request_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_status_run     ON kb.doc_review_status (review_run_id);
-- Partial index accelerates the "active jobs" query (rows that are not yet finished).
CREATE INDEX IF NOT EXISTS idx_doc_review_status_active  ON kb.doc_review_status (request_id)
    WHERE status NOT IN ('success', 'failed');
```

**Per-aspect lifecycle:** `pending → running → success | failed`. An aspect is
**finished** if and only if its `status` is `success` or `failed`. A review *job*
is finished when **all** of its aspect rows are finished; at that point it drops
out of the live monitor (§4.4, §7.2).

**Relationship to `kb.doc_review_requests.status`:** the request-level `status`
column remains the overall lifecycle marker (accepted/running/completed/failed/
stopped), but the **authoritative liveness signal for the monitor is per-aspect**.
The controller keeps them consistent: the request is marked `completed` once every
aspect row is finished.

> **Note — `review_run_id` is now assigned at accept time** (§3.1). Previously it
> was set when the request transitioned to `running`. It must exist at accept so
> the `kb.doc_review_status` rows can key off it. The column stays nullable in the
> schema for backward compatibility, but the controller always populates it on
> accept.

---

## 4. DocReviewController — Service Layer

**Package:** `server/api/docreview/`

### 4.1 DocReviewController

A standalone service component (not a pipeline processor) managing the review request lifecycle.

**Methods:**
- `ValidateRequest(ctx, input)` — check document exists, aspects selected, requester resolved
- `ResolveReviewerSet(tier, aspects)` → translate tier/custom list to concrete reviewer configs
- `MergeModelOverrides(configs, overrides)` — apply per-request model overrides
- `MergeReferenceDocs(userRefs, autoRefs)` — combine user-supplied with auto-discovered refs
- `AcceptRequest(ctx, input)` — validate + store as "accepted"
- `RunReview(ctx, requestID)` — status → "running", delegate to ReviewProcessor.PostProcessIndex
- `CollectFindings(ctx, reviewRunID)` — read from kb.doc_review_findings
- `GenerateReport(ctx, requestID, findings)` — delegate to DocReviewReportGenerator
- `StopRequest(ctx, requestID)` — transition running → stopped
- `GetRequest(ctx, requestID)` — return request + findings
- `GetReport(ctx, reportID)` — return report JSON
- `GetReportHTML(ctx, reportID)` — render HTML template from report JSON

### 4.2 State Machine

```
accepted → running → completed
                   → failed (retryable)
                   → stopped (user cancelled)
```

### 4.3 Aspect/Tier Definitions

**Package:** `server/api/docreview/aspects.go`

Defined inline, matching the Document Review Checklist spec:
- `ListAspects()` — returns all ~40 aspects with group, priority, description, default model
- `ListTiers()` — returns tier→aspect mapping (must_review, should_review, etc.)
- `AspectPriority` — "Must Review", "Should Review", "Review for External/Public", "Review for Regulated"

### 4.4 Per-Aspect Status Tracking & Live Monitor (DR15)

**New controller methods:**
- `SeedAspectStatuses(ctx, requestID, reviewRunID, recordID, aspects)` — called by
  `AcceptRequest`; bulk-inserts one `kb.doc_review_status` row per aspect (`pending`).
- `MarkAspectRunning(ctx, reviewRunID, aspect)` — `pending → running`, sets `start_time`.
- `MarkAspectFinished(ctx, reviewRunID, aspect, status, findingCount, errMsg)` —
  `running → success|failed`, sets `end_time`, `finding_count`, `error_message`.
- `ListActiveJobs(ctx)` — returns every request that still has ≥1 unfinished aspect,
  each with its full per-aspect status list (drives the monitor; §6, §7.2).

**Where transitions happen.** `RunReview` delegates to `ReviewProcessor`, which runs
the reviewers as concurrent goroutines (ADR DR1/DR2). To populate the status rows
accurately, each reviewer goroutine reports its own start/finish through a small
status sink. Two implementation options:

1. **Per-reviewer updates (recommended, true live progress).** The controller passes
   a status-reporting callback (or a `DocReviewStatusStore`) into `ReviewProcessor`.
   Each reviewer calls `MarkAspectRunning` when its goroutine starts and
   `MarkAspectFinished` (with its finding count, or an error) when it returns. The
   monitor then shows aspects lighting up green/red independently, exactly like the
   Active Pipelines dashboard.
2. **Coarse, controller-only (fallback).** The controller flips all aspect rows to
   `running` before delegating, then — after `ReviewProcessor` returns — marks every
   aspect `success` (using the per-aspect finding counts from `kb.doc_review_findings`)
   or, if the run errored as a whole, `failed`. Less granular (all aspects flip
   together) but requires no change to `ReviewProcessor`.

The chosen option is recorded at implementation time; the table schema and the
monitor are identical either way.

**Implemented (2026-06-22): Option 2 (coarse) + async execution.** Phase-I
`ReviewProcessor` only runs `grammar_spelling`, so per-reviewer live signals would
leave the other aspects dark; the controller therefore flips all aspects
`running` at start and `success` (with per-aspect finding counts) / `failed` at the
end. Execution was also made **asynchronous**: `SubmitRequest` accepts + seeds the
status rows and returns immediately, then runs the review in a background goroutine
(detached `context.Background()`), so the monitor can observe the job while it runs.
The controller passes the accept-time `review_run_id` into
`ReviewProcessor.ReviewRunID` so findings share the run identity.

**Active-jobs query (the monitor's source of truth):**

```sql
SELECT r.id, r.input_record_id, r.review_run_id, r.tier, r.status,
       r.requester_name, r.create_time, r.start_time
FROM kb.doc_review_requests r
WHERE EXISTS (
    SELECT 1 FROM kb.doc_review_status s
    WHERE s.request_id = r.id
      AND s.status NOT IN ('success', 'failed')   -- ≥ 1 unfinished aspect
)
ORDER BY r.create_time DESC;
```

For each returned request, the per-aspect rows are loaded (joined or a second query)
to render the aspect nodes. **A job disappears from this result the moment its last
aspect finishes** — satisfying "remove the review from the monitor when it finishes"
with no extra bookkeeping.

**Terminal-state handling (stop / whole-run failure).** Because *finished* is
defined strictly as `success` or `failed`, any path that ends a run must drive its
not-yet-finished aspects to one of those two states, or the job would linger in the
monitor forever:
- `StopRequest` — set every `pending`/`running` aspect of the run to `failed` with
  `error_message = "stopped"` (and the request to `stopped`). The job then leaves the
  monitor on the next poll.
- Whole-run failure (e.g. `ReviewProcessor` errors before per-aspect reporting) — set
  all non-finished aspects to `failed` with the run error, request → `failed`.
- Crash/stale-run safety — a sweeper (or a `created older than N hours` guard in the
  active query) can fail out aspects whose run is no longer live, so a process that
  dies mid-run cannot pin a job in the monitor permanently.

---

## 5. DocReviewReportGenerator

**Package:** `server/api/docreview/report.go`

### 5.1 Inputs
- `[]ReviewFinding` for the review_run_id
- Document metadata (title, doc_no, file_name)
- Review request row (aspects ran, user notes)
- `kb.summaries` (for executive summary context)

### 5.2 Report Assembly

```
1. Load findings by review_run_id
2. Group by pass (P1–P6)
3. Group findings by finding_type within each pass
4. Compute severity counts (high/medium/low)
5. Build compliance_summary from reference_doc-tagged findings
6. Delegate executive summary to cheap LLM (one-shot Haiku)
7. Build recommendations from high-severity findings
8. Fill JSON skeleton → serialize
9. Render Go HTML template from JSON
10. Render Go Markdown template from JSON
11. Persist JSON + Markdown to kb.doc_review_reports
```

### 5.3 Report Representations

| Format | Storage | Served via |
|--------|---------|------------|
| JSON | `report_json` (DB) | `GET /reports/<id>` |
| HTML | On-the-fly template render | `GET /reports/<id>/html` |
| Markdown | `report_markdown` (DB) | `GET /reports/<id>/export?format=md` |

The HTML template is a single Go `html/template` driven by the report JSON struct
with inline CSS for standalone viewing. The Svelte results page can embed it as
structured content or link to the HTML endpoint.

---

## 6. API Endpoints

**Package:** `server/api/docreviewhandler/`

Route registration in `server/api/routes.go` under `/api/v1/doc-review/` group.

| Method | Path | Handler | Purpose |
|--------|------|---------|---------|
| `GET` | `/api/v1/doc-review/aspects` | `ListAspects` | All aspects + groups + priorities |
| `GET` | `/api/v1/doc-review/tiers` | `ListTiers` | Tier→aspect mappings |
| `POST` | `/api/v1/doc-review/requests` | `SubmitRequest` | Create + trigger review |
| `GET` | `/api/v1/doc-review/requests/:id` | `GetRequest` | Status + findings |
| `GET` | `/api/v1/doc-review/reports/:id` | `GetReport` | Full report JSON |
| `GET` | `/api/v1/doc-review/reports/:id/html` | `GetReportHTML` | HTML report view |
| `GET` | `/api/v1/doc-review/reports/:id/export` | `ExportReport` | Markdown/PDF/DOCX |
| `PATCH` | `/api/v1/doc-review/findings/:id` | `UpdateFinding` | Accept/reject/defer |
| `POST` | `/api/v1/doc-review/requests/:id/stop` | `StopRequest` | Cancel running review |
| `GET` | `/api/v1/doc-review/active` | `ListActiveJobs` | **(DR15)** All jobs with ≥1 unfinished aspect, each with per-aspect status — drives the live monitor |

**`GET /active` response shape (DR15):**

```json
{
  "status": true,
  "jobs": [
    {
      "request_id": 42,
      "input_record_id": 416,
      "review_run_id": "416_review_20260621T115000",
      "tier": "must_review",
      "status": "running",
      "requester_name": "Alex Johnson",
      "create_time": "2026-06-21T11:50:00Z",
      "aspects": [
        { "aspect": "completeness", "pass": "P3", "status": "success", "finding_count": 3 },
        { "aspect": "security",     "pass": "P5", "status": "running", "finding_count": 0 },
        { "aspect": "pii",          "pass": "P6", "status": "pending", "finding_count": 0 }
      ]
    }
  ]
}
```

### 6.1 Request Validation — Requester Resolution

On `POST /requests`:
1. Parse body (requester_name, requester_id, tier, aspects, ...)
2. Look up requester_id in Kratos/users table
3. If not found → return 422 with error message guiding to register
4. If found → continue validation

---

## 7. Frontend — Home3 Integration

### 7.1 Nav Rail

Add child under existing "Applications" parent in `nav-rail.svelte`:
```typescript
{ id: 'apps-document-review', label: 'Document Review' }
```

Update `content-panel.svelte` to map this child ID to the view component.

### 7.2 View Components

**`document-review-view.svelte`** — The 4-step form (main view):
1. **Select Document** — searchable list of processed documents (`kb.inputs`)
2. **Choose Check Level & Aspects** — one **shared** aspect set edited via per-tier
   **On/Off toggles** (On iff ≥1 of the tier's aspects is selected) and per-aspect
   chips grouped by P1–P6. "Next" is disabled (with a hover help message) while the
   set is empty. There is no separate "Customize" step — fine-tuning happens inline.
3. **Supporting Documents** — optional search-and-add reference standards
4. **Notes/Requester + Submit** — requester name + optional notes, review summary,
   sends POST /requests. Missing-field validation shows a confirmation dialog that
   jumps back to the offending step on OK.

**`doc-review-results-view.svelte`** — Results page (sub-view after submission):
1. **Progress indicator** — polling spinner while `status: "running"`
2. **Summary cards** — total findings, severity bar chart, pass-by-pass breakdown
3. **Findings table** — filterable, sortable, expandable rows with accept/reject/defer
4. **Report view** — full report rendering (from JSON or embedded HTML)
5. **Export buttons** — Markdown/PDF

**`doc-review-monitor.svelte`** — Live job monitor (DR15), shown on top of the
Document Review page (Active-Pipelines style):
- Polls `GET /api/v1/doc-review/active` every 3 s and renders **one card per active
  job** — every review that still has ≥1 unfinished aspect, across all users/sessions
  (not just the job submitted in the current session).
- Each card shows the document, tier, requester, elapsed time, and a horizontal chain
  of **per-aspect status nodes** driven by `kb.doc_review_status.status`
  (pending = idle, running = pulsing, success = green check + finding count, failed = red).
- When a job's last aspect finishes (all `success`/`failed`), it is no longer returned
  by `/active` and **its card disappears from the monitor** on the next poll.
- Controls: Stop (while running) and a link into the full results view.

### 7.3 Service Layer

**`web/src/lib/services/docReviewService.ts`** — Following existing service pattern:
```typescript
const BASE = '/api/v1/doc-review';

export async function listAspects(): Promise<Aspect[]> { ... }
export async function listTiers(): Promise<Tier[]> { ... }
export async function submitRequest(input: SubmitInput): Promise<SubmitResult> { ... }
export async function getRequest(id: number): Promise<RequestWithFindings> { ... }
export async function getReport(id: number): Promise<Report> { ... }
export async function updateFinding(id: number, status: string): Promise<void> { ... }
export async function stopRequest(id: number): Promise<void> { ... }
```

### 7.4 Results Page Navigation

After submission, the view switches to the results view either by:
- Changing `activeMenu` selection to `apps-document-review-results` with a parameter
- Or using a component-internal state toggle (`$state('submitted') → $state('results')`)

Using internal state keeps it simpler — the nav rail item stays "Document Review" and the view component manages its own form/results screens internally.

---

## 8. Files to Create/Modify

### New Files
| Path | Purpose |
|------|---------|
| `server/api/docreview/controller.go` | DocReviewController service |
| `server/api/docreview/models.go` | Request/response types |
| `server/api/docreview/aspects.go` | Aspect definitions, tier mappings |
| `server/api/docreview/report.go` | DocReviewReportGenerator |
| `server/api/docreview/report_template.html` | HTML report template |
| `server/api/docreview/report_markdown.tmpl` | Markdown report template |
| `server/api/docreviewhandler/handler.go` | HTTP handlers |
| `project_migrations/20260621000001_create_doc_review_requests.sql` | Migration 1 |
| `project_migrations/20260621000002_create_doc_review_reports.sql` | Migration 2 |
| `project_migrations/2026062100000X_create_doc_review_status.sql` | **(DR15)** Migration 3 — `kb.doc_review_status` |
| `web/src/lib/components/home3/document-review-view.svelte` | 5-step form view |
| `web/src/lib/components/home3/doc-review-results-view.svelte` | Results view |
| `web/src/lib/components/home3/doc-review-monitor.svelte` | **(DR15)** Live job monitor |
| `web/src/lib/services/docReviewService.ts` | API service functions |

### Modified Files
| Path | Change |
|------|--------|
| `server/api/routes.go` | Register doc-review routes |
| `web/src/lib/components/home3/nav-rail.svelte` | Add "Document Review" nav item |
| `web/src/lib/components/home3/content-panel.svelte` | Wire view component |

---

## 9. Tests

- **Controller — requester resolution:** valid requester → request accepted; unknown requester → 422 error
- **Controller — state machine:** lifecycle transitions (accepted→running, running→completed, running→failed, running→stopped)
- **Controller — override merging:** model override for P5 replaces P5 default, leaves P1–P4 untouched
- **ReportGenerator — JSON skeleton:** report structure conforms to schema, counts match underlying findings
- **ReportGenerator — HTML template:** renders without error given valid JSON
- **API — submit + retrieve:** POST request → GET returns status
- **API — findings PATCH:** update review_status, GET reflects change
- **(DR15) Status seeding:** accepting a request inserts one `kb.doc_review_status` row per aspect with status `pending` and the request's `review_run_id`
- **(DR15) Aspect transitions:** `MarkAspectRunning`/`MarkAspectFinished` move a row `pending → running → success|failed` and set the timestamps/finding_count
- **(DR15) Active query — inclusion:** a job with ≥1 aspect not in (`success`,`failed`) appears in `GET /active`
- **(DR15) Active query — removal:** once every aspect of a job is `success`/`failed`, the job is absent from `GET /active`
- **(DR15) Finished predicate:** an aspect counts as finished iff its status is `success` or `failed` (not `pending`/`running`)
