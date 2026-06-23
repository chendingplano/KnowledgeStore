# Document Review — Implementation

**Date:** 2026-06-21
**Implements:** ADR 2026061801 (DR11–DR13)

## Scope

Implemented against:
- `KnowledgeStore/Capsules/coding-capsules/doc-processor/document-review-spec.md`
- `ChenWeb/docs/superpowers/specs/2026-06-21-doc-review-gui-design.md`
- `ChenWeb/docs/superpowers/plans/2026-06-21-doc-review-gui-plan.md`

Primary implementation in ChenWeb:

## Backend (Go)

### Package `server/api/docreview/` — Service Layer

| File | Description |
|------|-------------|
| `models.go` | Request/response types (SubmitRequestInput, RequestStatus, FindingItem, AspectInfo, TierInfo, etc.) |
| `aspects.go` | 46 review aspects across P1–P6, 4 tier definitions, ResolveAspectsForTier() helper |
| `controller.go` | DocReviewController — request validation, lifecycle state machine (accepted→running→completed/failed/stopped), reviewer resolution, override merging, idempotency guard |
| `report.go` | DocReviewReportGenerator — report skeleton assembly, executive summary, compliance summary, Markdown rendering, HTML template rendering |

### Package `server/api/docreviewhandler/` — HTTP Layer

| Handler | Method |
|---------|--------|
| `handler.go` | 9 exported handler functions: ListAspects, ListTiers, SubmitRequest, GetRequest, GetReport, GetReportHTML, ExportReport, UpdateFinding, StopRequest |

### Database Migrations

| Migration | Table |
|-----------|-------|
| `project_migrations/20260621000001_create_doc_review_requests.sql` | `kb.doc_review_requests` |
| `project_migrations/20260621000002_create_doc_review_reports.sql` | `kb.doc_review_reports` |

### Route Registration

All 9 endpoints registered in `server/api/routes.go` under `/api/v1/doc-review/` with auth middleware.

## Frontend (Svelte 5)

| File | Description |
|------|-------------|
| `web/src/lib/services/docReviewService.ts` | 7 API service functions: listAspects, listTiers, submitRequest, getRequest, getReport, updateFinding, stopRequest |
| `web/src/lib/components/home3/document-review-view.svelte` | 5-step review request form (document search → tier picker → aspect checkboxes → reference docs → notes & submit) |
| `web/src/lib/components/home3/doc-review-results-view.svelte` | Results view: polling (3s), severity summary cards, filterable findings table with accept/reject/defer, Markdown/JSON/HTML report links |

### Navigation Wiring

- Nav item added to home3 nav-rail under Applications → Document Review (`apps-document-review`)
- View branching added in content-panel.svelte

## Tests

| File | Tests | Status |
|------|-------|--------|
| `server/api/docreview/aspects_test.go` | 5 tests: list count, groups coverage, tiers, resolve, invalid | ✅ PASS |
| `server/api/docreview/report_test.go` | 5 tests: empty findings, mixed severities, compliance summary, recommendations, meta fields | ✅ PASS |
| `server/api/docreview/controller_test.go` | 9 tests: state machine transitions, idempotency, validation, CRUD | ⏳ SKIP (needs DB) |

## Key Files

```
server/api/docreview/
├── models.go
├── aspects.go
├── controller.go
├── report.go
├── aspects_test.go
├── report_test.go
└── controller_test.go

server/api/docreviewhandler/
└── handler.go

project_migrations/
├── 20260621000001_create_doc_review_requests.sql
└── 20260621000002_create_doc_review_reports.sql

web/src/lib/services/
└── docReviewService.ts

web/src/lib/components/home3/
├── document-review-view.svelte
└── doc-review-results-view.svelte
```
