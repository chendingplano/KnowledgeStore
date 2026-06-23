# DR13 — Document Review Request GUI: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement full-stack document review request GUI in ChenWeb/home3 — database tables, service layer (DocReviewController + DocReviewReportGenerator), API endpoints, and Svelte frontend — per DR13 of ADR 2026061801.

**Architecture:** Go Echo v4 backend with new `docreview` service package and `docreviewhandler` HTTP layer; SvelteKit 5 frontend integrated into existing home3 layout under Apps → Document Review. Review execution delegates to existing `ReviewProcessor.PostProcessIndex`.

**Tech Stack:** Go 1.25 + Echo v4, PostgreSQL (goose migrations), SvelteKit 5 + shadcn-svelte, Tailwind CSS v4, Lucide icons.

## Global Constraints

- Go module: `github.com/chendingplano/deepdoc` at `ChenWeb/server/`
- DB access via `ApiTypes.ProjectDBHandle` (global `*sql.DB`)
- Handler packages named `<feature>handler`, exported functions with `func(c echo.Context) error` signature
- Routes registered in `server/api/routes.go` under `/api/v1/doc-review/` group with auth middleware
- Migration SQL files go in `project_migrations/YYYYMMDDHHMMSS_description.sql`
- Frontend services use `fetch()` with `credentials: 'same-origin'` and `'Content-Type': 'application/json'`
- Frontend components use Svelte 5 runes (`$state`, `$derived`, `$effect`, `$props()`)
- View components accept `{ darkMode: boolean }` prop
- Nav items defined inline in `nav-rail.svelte`; view wiring in `content-panel.svelte` if/else chain
- LLM client for review: `&llmclients.OpenAIJSONClient{HTTPClient: &http.Client{Timeout: 100 * time.Second}}` from `github.com/chendingplano/shared/go/api/llm`

---

## File Structure

### New Files (Backend — Go)

| File | Responsibility |
|------|---------------|
| `server/api/docreview/models.go` | Request/response types: `SubmitRequestInput`, `RequestStatus`, `AspectInfo`, `TierInfo` |
| `server/api/docreview/aspects.go` | Static aspect definitions, tier→aspect mappings, `ListAspects()`, `ListTiers()` |
| `server/api/docreview/controller.go` | `DocReviewController`: request lifecycle, reviewer resolution, override merging, state machine |
| `server/api/docreview/report.go` | `DocReviewReportGenerator`: assemble report JSON, executive summary, compliance summary |
| `server/api/docreview/report_template.html` | Go `html/template` for rendering report as HTML from JSON |
| `server/api/docreview/report_markdown.tmpl` | Go `text/template` for rendering report as Markdown from JSON |
| `server/api/docreviewhandler/handler.go` | HTTP handlers for all 9 endpoints |

### New Files (Backend — Migrations)

| File | Responsibility |
|------|---------------|
| `project_migrations/20260621000001_create_doc_review_requests.sql` | `kb.doc_review_requests` table |
| `project_migrations/20260621000002_create_doc_review_reports.sql` | `kb.doc_review_reports` table |

### New Files (Frontend)

| File | Responsibility |
|------|---------------|
| `web/src/lib/services/docReviewService.ts` | API service functions for all doc-review endpoints |
| `web/src/lib/components/home3/document-review-view.svelte` | Main 5-step review request form |
| `web/src/lib/components/home3/doc-review-results-view.svelte` | Results page with findings table, report view, accept/reject |

### Modified Files

| File | Change |
|------|--------|
| `server/api/routes.go` | Add import + 9 route registrations under `/api/v1/doc-review/` |
| `web/src/lib/components/home3/nav-rail.svelte` | Add `{ id: 'apps-document-review', label: 'Document Review' }` under Applications children |
| `web/src/lib/components/home3/content-panel.svelte` | Add import + `{:else if}` branch for `apps-document-review` |

---

## Tasks

### Task 1: Database Migrations

**Files:**
- Create: `project_migrations/20260621000001_create_doc_review_requests.sql`
- Create: `project_migrations/20260621000002_create_doc_review_reports.sql`

**Interfaces:**
- Consumes: `kb.doc_review_findings` table (existing)
- Produces: Two new tables consumed by Task 3 (controller) and Task 4 (report generator)

- [ ] **Step 1: Create `kb.doc_review_requests` migration**

Write `project_migrations/20260621000001_create_doc_review_requests.sql`:

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_requests (
    id              BIGSERIAL       PRIMARY KEY,
    input_record_id BIGINT          NOT NULL,
    review_run_id   TEXT,
    tier            TEXT            NOT NULL,
    aspects         JSONB           NOT NULL,
    reference_docs  JSONB,
    notes           TEXT,
    model_overrides JSONB,
    requester_name  TEXT            NOT NULL,
    requester_id    BIGINT          NOT NULL,
    report_template TEXT,
    doc_template    TEXT,
    status          TEXT            NOT NULL DEFAULT 'accepted',
    create_time     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    start_time      TIMESTAMPTZ,
    end_time        TIMESTAMPTZ,
    error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_doc_review_requests_record ON kb.doc_review_requests (input_record_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_requests_status ON kb.doc_review_requests (status);
```

- [ ] **Step 2: Create `kb.doc_review_reports` migration**

Write `project_migrations/20260621000002_create_doc_review_reports.sql`:

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

- [ ] **Step 3: Verify migrations compile and format**

Migrations are auto-discovered by goose from `project_migrations/` directory. No registration needed.

---

### Task 2: Go Models & Aspect Definitions

**Files:**
- Create: `server/api/docreview/models.go`
- Create: `server/api/docreview/aspects.go`

**Interfaces:**
- Produces: `SubmitRequestInput`, `AspectInfo`, `TierInfo`, `RequestStatus` types
- Consumed by Task 3 (controller), Task 5 (handler), Task 7 (frontend service)

- [ ] **Step 1: Write models.go**

```go
package docreview

import "encoding/json"

// SubmitRequestInput is the request body for POST /api/v1/doc-review/requests.
type SubmitRequestInput struct {
	InputRecordID int64              `json:"input_record_id"`
	Tier          string             `json:"tier"`          // "must_review", "should_review", "custom"
	Aspects       []string           `json:"aspects"`       // selected aspect names (all when tier-based)
	ReferenceDocs []ReferenceDoc     `json:"reference_docs,omitempty"`
	Notes         string             `json:"notes,omitempty"`
	ModelOverrides map[string]ModelOverride `json:"model_overrides,omitempty"`
	RequesterName string             `json:"requester_name"`
	RequesterID   int64              `json:"requester_id"`
	ReportTemplate string            `json:"report_template,omitempty"`
	DocTemplate   string             `json:"doc_template,omitempty"`
}

type ReferenceDoc struct {
	RecordID int64  `json:"record_id"`
	DocNo    string `json:"doc_no"`
	Title    string `json:"title"`
}

type ModelOverride struct {
	ModelRef string `json:"model_ref"`
}

// RequestStatus represents a row from kb.doc_review_requests.
type RequestStatus struct {
	ID             int64               `json:"id"`
	InputRecordID  int64               `json:"input_record_id"`
	ReviewRunID    string              `json:"review_run_id,omitempty"`
	Tier           string              `json:"tier"`
	Aspects        []string            `json:"aspects"`
	ReferenceDocs  []ReferenceDoc      `json:"reference_docs,omitempty"`
	Notes          string              `json:"notes,omitempty"`
	ModelOverrides map[string]ModelOverride `json:"model_overrides,omitempty"`
	RequesterName  string              `json:"requester_name"`
	RequesterID    int64               `json:"requester_id"`
	ReportTemplate string              `json:"report_template,omitempty"`
	DocTemplate    string              `json:"doc_template,omitempty"`
	Status         string              `json:"status"`
	CreateTime     string              `json:"create_time"`
	StartTime      string              `json:"start_time,omitempty"`
	EndTime        string              `json:"end_time,omitempty"`
	ErrorMessage   string              `json:"error_message,omitempty"`
}

// RequestWithFindings extends RequestStatus with findings.
type RequestWithFindings struct {
	Request  RequestStatus   `json:"request"`
	Findings []FindingItem   `json:"findings,omitempty"`
}

// FindingItem is a finding row from kb.doc_review_findings.
type FindingItem struct {
	ID           int64   `json:"id"`
	Pass         string  `json:"pass"`
	Aspect       string  `json:"aspect"`
	Severity     string  `json:"severity"`
	FindingType  string  `json:"finding_type"`
	Title        string  `json:"title"`
	Description  string  `json:"description"`
	Evidence     string  `json:"evidence,omitempty"`
	Location     string  `json:"location,omitempty"`
	Suggestion   string  `json:"suggestion,omitempty"`
	Confidence   float64 `json:"confidence"`
	ReviewStatus string  `json:"review_status"`
}

// ReportRow represents a row from kb.doc_review_reports (partial, for listing).
type ReportRow struct {
	ID                int64  `json:"id"`
	RequestID         int64  `json:"request_id"`
	InputRecordID     int64  `json:"input_record_id"`
	ReviewRunID       string `json:"review_run_id"`
	TotalFindings     int    `json:"total_findings"`
	HighCount         int    `json:"high_count"`
	MediumCount       int    `json:"medium_count"`
	LowCount          int    `json:"low_count"`
	OverallAssessment string `json:"overall_assessment"`
	CreateTime        string `json:"create_time"`
}

// ReportDetail is the full report with JSON content for detail view.
type ReportDetail struct {
	ReportRow
	ExecutiveSummary string                 `json:"executive_summary"`
	ReportJSON       map[string]any         `json:"report_json"`
	ReportMarkdown   string                 `json:"report_markdown"`
}

// AspectInfo describes one review aspect.
type AspectInfo struct {
	Name        string `json:"name"`
	Group       string `json:"group"`       // "P1".."P6"
	Label       string `json:"label"`       // human-readable, e.g. "Grammar & Spelling"
	Priority    string `json:"priority"`    // "Must Review", "Should Review", etc.
	Description string `json:"description"`
	DefaultModel string `json:"default_model"`
	IsToolUse   bool   `json:"is_tool_use"`
}

// TierInfo describes one priority tier.
type TierInfo struct {
	Key         string   `json:"key"`         // "must_review", "should_review", etc.
	Label       string   `json:"label"`       // "Must Review"
	Description string   `json:"description"` // "Critical compliance aspects"
	AspectNames []string `json:"aspect_names"`
}

// SubmitResult is the response from POST /api/v1/doc-review/requests.
type SubmitResult struct {
	RequestID   int64  `json:"request_id"`
	Status      string `json:"status"`
	ReviewRunID string `json:"review_run_id,omitempty"`
}
```

- [ ] **Step 2: Write aspects.go with aspect definitions and tier mappings**

```go
package docreview

// ListAspects returns all review aspects with their metadata.
// Source: Document Review Checklist spec (doc-repo/specs/202606/2026061102-spec-document-review-checklist.md)
func ListAspects() []AspectInfo {
	return []AspectInfo{
		// P1 — Language & Style
		{Name: "grammar_spelling",         Group: "P1", Label: "Grammar & Spelling",        Priority: "Should Review", Description: "Checks grammar, spelling, punctuation, and capitalization.", DefaultModel: "claude-haiku-4-5"},
		{Name: "tone_voice",              Group: "P1", Label: "Tone & Voice",              Priority: "Should Review", Description: "Evaluates consistency of tone and voice throughout.", DefaultModel: "claude-haiku-4-5"},
		{Name: "formatting_consistency",  Group: "P1", Label: "Formatting Consistency",    Priority: "Should Review", Description: "Checks for consistent use of formatting (bold, italic, lists).", DefaultModel: "claude-haiku-4-5"},
		{Name: "readability",            Group: "P1", Label: "Readability",                 Priority: "Should Review", Description: "Measures sentence complexity, paragraph length, and clarity.", DefaultModel: "claude-haiku-4-5"},
		{Name: "localization",           Group: "P1", Label: "Localization",                Priority: "Review for External/Public", Description: "Checks if content is suitable for target locale.", DefaultModel: "claude-haiku-4-5"},

		// P2 — Structure & Organization
		{Name: "logical_flow",           Group: "P2", Label: "Logical Flow",                Priority: "Must Review", Description: "Evaluates whether content follows a logical sequence.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "heading_hierarchy",      Group: "P2", Label: "Heading Hierarchy",           Priority: "Should Review", Description: "Validates heading nesting and consistency.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "toc_accuracy",           Group: "P2", Label: "Table of Contents Accuracy",   Priority: "Should Review", Description: "Verifies ToC matches actual headings.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "navigability",           Group: "P2", Label: "Navigability",                Priority: "Review for Regulated", Description: "Assesses how easily a reader can find relevant sections.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "section_balance",        Group: "P2", Label: "Section Balance",             Priority: "Review for External/Public", Description: "Checks if sections are proportional in length.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "modularity",             Group: "P2", Label: "Modularity",                  Priority: "Review for Regulated", Description: "Evaluates whether content is self-contained and reusable.", DefaultModel: "claude-sonnet-4-6"},

		// P3 — Content Quality
		{Name: "completeness",           Group: "P3", Label: "Completeness",                Priority: "Must Review", Description: "Checks if all required topics are covered.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "correctness",            Group: "P3", Label: "Correctness",                 Priority: "Must Review", Description: "Verifies factual accuracy of content.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "clarity",                Group: "P3", Label: "Clarity",                     Priority: "Must Review", Description: "Evaluates how clearly concepts are explained.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "conciseness",            Group: "P3", Label: "Conciseness",                 Priority: "Should Review", Description: "Checks for unnecessary verbosity.", DefaultModel: "claude-haiku-4-5"},
		{Name: "relevance",              Group: "P3", Label: "Relevance",                   Priority: "Should Review", Description: "Ensures content is relevant to the document's purpose.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "currency",               Group: "P3", Label: "Currency",                    Priority: "Should Review", Description: "Verifies information is up-to-date.", DefaultModel: "claude-haiku-4-5"},
		{Name: "examples",               Group: "P3", Label: "Examples",                    Priority: "Review for External/Public", Description: "Checks for adequate examples.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "diagrams",               Group: "P3", Label: "Diagrams",                    Priority: "Review for External/Public", Description: "Evaluates quality and relevance of diagrams.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "testable_claims",        Group: "P3", Label: "Testable Claims",             Priority: "Must Review", Description: "Flags claims that should be testable.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "evidence_rationale",     Group: "P3", Label: "Evidence & Rationale",        Priority: "Must Review", Description: "Checks if claims are supported by evidence.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},

		// P4 — Consistency
		{Name: "internal_contradictions",     Group: "P4", Label: "Internal Contradictions",      Priority: "Must Review", Description: "Finds contradictory statements across the document.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "terminology_consistency",     Group: "P4", Label: "Terminology Consistency",       Priority: "Must Review", Description: "Checks for consistent use of terms.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "cross_reference_correctness", Group: "P4", Label: "Cross-Reference Correctness",   Priority: "Must Review", Description: "Validates cross-references point to correct targets.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "requirement_traceability",    Group: "P4", Label: "Requirement Traceability",      Priority: "Review for Regulated", Description: "Traces requirements to their implementation.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},

		// P5 — Technical & Compliance
		{Name: "technical_accuracy",     Group: "P5", Label: "Technical Accuracy",           Priority: "Must Review", Description: "Verifies technical details, code snippets, formulas.", DefaultModel: "claude-opus-4-8", IsToolUse: true},
		{Name: "assumptions",            Group: "P5", Label: "Assumptions",                  Priority: "Must Review", Description: "Identifies unstated or invalid assumptions.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "prerequisites",          Group: "P5", Label: "Prerequisites",                Priority: "Should Review", Description: "Checks if prerequisites are documented.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "standards_compliance",   Group: "P5", Label: "Standards Compliance",         Priority: "Must Review", Description: "Checks compliance with relevant standards (ISO, IEC, GB).", DefaultModel: "claude-opus-4-8", IsToolUse: true},
		{Name: "legal_compliance",       Group: "P5", Label: "Legal Compliance",             Priority: "Review for Regulated", Description: "Checks compliance with legal requirements.", DefaultModel: "claude-opus-4-8", IsToolUse: true},
		{Name: "regulatory_compliance",  Group: "P5", Label: "Regulatory Compliance",        Priority: "Review for Regulated", Description: "Checks compliance with regulatory requirements.", DefaultModel: "claude-opus-4-8", IsToolUse: true},
		{Name: "internal_policy",        Group: "P5", Label: "Internal Policy",              Priority: "Review for Regulated", Description: "Checks adherence to internal policies.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "security",               Group: "P5", Label: "Security",                     Priority: "Must Review", Description: "Identifies security vulnerabilities and concerns.", DefaultModel: "claude-opus-4-8", IsToolUse: true},
		{Name: "performance",            Group: "P5", Label: "Performance",                  Priority: "Should Review", Description: "Evaluates performance implications.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "error_handling",         Group: "P5", Label: "Error Handling",               Priority: "Should Review", Description: "Checks if error scenarios are addressed.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},
		{Name: "limitations",            Group: "P5", Label: "Limitations",                  Priority: "Should Review", Description: "Identifies undocumented limitations.", DefaultModel: "claude-sonnet-4-6", IsToolUse: true},

		// P6 — Meta & Process
		{Name: "version_history",       Group: "P6", Label: "Version History",               Priority: "Should Review", Description: "Checks if version history is complete.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "review_status",         Group: "P6", Label: "Review Status",                 Priority: "Should Review", Description: "Verifies review status is documented.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "ownership",             Group: "P6", Label: "Ownership",                     Priority: "Should Review", Description: "Checks document ownership is identified.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "references",            Group: "P6", Label: "References",                    Priority: "Must Review", Description: "Verifies all references are properly cited.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "related_documents",     Group: "P6", Label: "Related Documents",             Priority: "Should Review", Description: "Checks if related documents are referenced.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "confidentiality",       Group: "P6", Label: "Confidentiality",               Priority: "Must Review", Description: "Checks for proper confidentiality markings.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "sensitive_data",        Group: "P6", Label: "Sensitive Data",                Priority: "Must Review", Description: "Flags potentially sensitive information.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "pii",                   Group: "P6", Label: "Personally Identifiable Info",   Priority: "Must Review", Description: "Detects PII exposure risks.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "data_retention",        Group: "P6", Label: "Data Retention",                Priority: "Review for Regulated", Description: "Checks if data retention is addressed.", DefaultModel: "claude-sonnet-4-6"},
		{Name: "license_ip",            Group: "P6", Label: "License & IP",                  Priority: "Review for Regulated", Description: "Checks license and intellectual property issues.", DefaultModel: "claude-sonnet-4-6"},
	}
}

// ListTiers returns the priority tier definitions with their aspect mappings.
func ListTiers() []TierInfo {
	all := ListAspects()
	var mustReview, shouldReview, externalReview, regulatedReview []string
	for _, a := range all {
		switch a.Priority {
		case "Must Review":
			mustReview = append(mustReview, a.Name)
		case "Should Review":
			shouldReview = append(shouldReview, a.Name)
		case "Review for External/Public":
			externalReview = append(externalReview, a.Name)
		case "Review for Regulated":
			regulatedReview = append(regulatedReview, a.Name)
		}
	}
	return []TierInfo{
		{Key: "must_review", Label: "Must Review", Description: "Critical compliance and quality aspects", AspectNames: mustReview},
		{Key: "should_review", Label: "Should Review", Description: "Recommended aspects", AspectNames: shouldReview},
		{Key: "review_external", Label: "Review for External/Public", Description: "For documents intended for external audiences", AspectNames: externalReview},
		{Key: "review_regulated", Label: "Review for Regulated", Description: "For regulated industry documents", AspectNames: regulatedReview},
	}
}

// ResolveAspectsForTier returns the aspect names for a given tier key.
func ResolveAspectsForTier(tierKey string) []string {
	for _, t := range ListTiers() {
		if t.Key == tierKey {
			return t.AspectNames
		}
	}
	return nil
}
```

- [ ] **Step 3: Verify both files compile**

Run: `cd /Users/cding/Workspace/ChenWeb/server && go build ./api/docreview/`
Expected: no errors (will produce no binary since it's a package dir)

---

### Task 3: DocReviewController

**Files:**
- Create: `server/api/docreview/controller.go`

**Interfaces:**
- Consumes: `SubmitRequestInput`, `RequestStatus` (Task 2), `ApiTypes.ProjectDBHandle`, `docprocessing.NewReviewProcessor`, `docprocessing.ReviewProcessor`, `docprocessing.ReviewFindingsSQLStore`, `docprocessing.DocMetadataSQLStore`, `docprocessing.EntityRelationSQLStore`
- Produces: `DocReviewController` with `AcceptRequest`, `GetRequest`, `GetRequestWithFindings`, `StopRequest`, `UpdateFinding` methods
- Consumed by Task 5 (handler)

- [ ] **Step 1: Write controller.go**

```go
package docreview

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/chendingplano/deepdoc/server/api/doc-processing"
	"github.com/chendingplano/shared/go/api/ApiTypes"
	"github.com/chendingplano/shared/go/api/loggerutil"
	llmclients "github.com/chendingplano/shared/go/api/llm"
)

// DocReviewController manages the review request lifecycle.
type DocReviewController struct {
	DB *sql.DB
}

// NewDocReviewController creates a DocReviewController.
func NewDocReviewController() *DocReviewController {
	return &DocReviewController{DB: ApiTypes.ProjectDBHandle}
}

// AcceptRequest validates input, resolves requester, stores the request as "accepted".
func (c *DocReviewController) AcceptRequest(ctx context.Context, input SubmitRequestInput) (*SubmitResult, error) {
	// Validate document exists.
	var exists bool
	err := c.DB.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM kb.inputs WHERE id = $1)`, input.InputRecordID).Scan(&exists)
	if err != nil {
		return nil, fmt.Errorf("check document %d: %w", input.InputRecordID, err)
	}
	if !exists {
		return nil, &RequestError{Status: http.StatusUnprocessableEntity, Message: fmt.Sprintf("Document %d not found", input.InputRecordID)}
	}

	// Resolve requester.
	var userExists bool
	err = c.DB.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM identities WHERE id = $1)`, input.RequesterID).Scan(&userExists)
	if err != nil {
		// identities table may not exist; try kratos identities
		err = c.DB.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM kratos.identities WHERE id = $1::uuid)`, input.RequesterID).Scan(&userExists)
	}
	if !userExists {
		return nil, &RequestError{
			Status:  http.StatusUnprocessableEntity,
			Message: fmt.Sprintf("User %d (%s) not found. Please register or re-enter the user name.", input.RequesterID, input.RequesterName),
		}
	}

	// Resolve aspect list.
	var aspects []string
	if input.Tier == "custom" {
		aspects = input.Aspects
	} else {
		aspects = ResolveAspectsForTier(input.Tier)
	}
	if len(aspects) == 0 {
		return nil, &RequestError{Status: http.StatusUnprocessableEntity, Message: "At least one aspect must be selected"}
	}

	// Enforce idempotency: if a request exists for this document that is still running/active, reject.
	var activeID int64
	err = c.DB.QueryRowContext(ctx,
		`SELECT id FROM kb.doc_review_requests WHERE input_record_id = $1 AND status IN ('accepted','running') LIMIT 1`,
		input.InputRecordID,
	).Scan(&activeID)
	if err == nil {
		return nil, &RequestError{
			Status:  http.StatusConflict,
			Message: fmt.Sprintf("A review request (ID %d) is already active for this document. Stop it first or wait for completion.", activeID),
		}
	}

	refDocsJSON, _ := json.Marshal(input.ReferenceDocs)
	aspectsJSON, _ := json.Marshal(aspects)
	overridesJSON, _ := json.Marshal(input.ModelOverrides)

	var id int64
	err = c.DB.QueryRowContext(ctx, `
		INSERT INTO kb.doc_review_requests
			(input_record_id, tier, aspects, reference_docs, notes, model_overrides,
			 requester_name, requester_id, report_template, doc_template, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'accepted')
		RETURNING id`,
		input.InputRecordID, input.Tier, aspectsJSON, refDocsJSON, input.Notes, overridesJSON,
		input.RequesterName, input.RequesterID, input.ReportTemplate, input.DocTemplate,
	).Scan(&id)
	if err != nil {
		return nil, fmt.Errorf("insert review request: %w", err)
	}

	return &SubmitResult{RequestID: id, Status: "accepted"}, nil
}

// RunReview transitions the request to "running", delegates to ReviewProcessor, then completes.
func (c *DocReviewController) RunReview(ctx context.Context, requestID int64) error {
	// Load request.
	req, err := c.loadRequest(ctx, requestID)
	if err != nil {
		return fmt.Errorf("load request %d: %w", requestID, err)
	}
	if req.Status != "accepted" {
		return fmt.Errorf("request %d is in status %q, expected 'accepted'", requestID, req.Status)
	}

	reviewRunID := fmt.Sprintf("%d_review_%s", req.InputRecordID, time.Now().UTC().Format("20060102T150405"))

	// Update status → running.
	_, err = c.DB.ExecContext(ctx,
		`UPDATE kb.doc_review_requests SET status = 'running', review_run_id = $1, start_time = NOW() WHERE id = $2`,
		reviewRunID, requestID,
	)
	if err != nil {
		return fmt.Errorf("update request %d to running: %w", requestID, err)
	}

	// Build and run ReviewProcessor.
	llmClient := &llmclients.OpenAIJSONClient{
		HTTPClient: &http.Client{Timeout: 100 * time.Second},
	}
	inputStore := docprocessing.DocMetadataSQLStore{DB: c.DB}
	entityStore := docprocessing.EntityRelationSQLStore{DB: c.DB}
	findingsStore := docprocessing.ReviewFindingsSQLStore{DB: c.DB}

	processor := docprocessing.NewReviewProcessor(inputStore, entityStore, findingsStore, llmClient, nil)
	err = processor.PostProcessIndex(ctx, req.InputRecordID)
	if err != nil {
		// Update status → failed.
		errMsg := err.Error()
		c.DB.ExecContext(ctx,
			`UPDATE kb.doc_review_requests SET status = 'failed', end_time = NOW(), error_message = $1 WHERE id = $2`,
			errMsg, requestID,
		)
		return fmt.Errorf("review failed for record %d: %w", req.InputRecordID, err)
	}

	// Update status → completed.
	_, err = c.DB.ExecContext(ctx,
		`UPDATE kb.doc_review_requests SET status = 'completed', end_time = NOW() WHERE id = $1`,
		requestID,
	)
	return err
}

// GetRequest returns the request status row.
func (c *DocReviewController) GetRequest(ctx context.Context, requestID int64) (*RequestStatus, error) {
	return c.loadRequest(ctx, requestID)
}

// GetRequestWithFindings returns the request with its findings.
func (c *DocReviewController) GetRequestWithFindings(ctx context.Context, requestID int64) (*RequestWithFindings, error) {
	req, err := c.loadRequest(ctx, requestID)
	if err != nil {
		return nil, err
	}
	result := &RequestWithFindings{Request: *req}

	// Only return findings if completed.
	if req.Status == "completed" && req.ReviewRunID != "" {
		rows, err := c.DB.QueryContext(ctx, `
			SELECT id, pass, aspect, severity, finding_type, title, description,
			       COALESCE(evidence,''), COALESCE(location,''), COALESCE(suggestion,''),
			       COALESCE(confidence,0), COALESCE(review_status,'pending')
			FROM kb.doc_review_findings
			WHERE input_record_id = $1 AND review_run_id = $2
			ORDER BY id`, req.InputRecordID, req.ReviewRunID)
		if err != nil {
			return nil, fmt.Errorf("load findings: %w", err)
		}
		defer rows.Close()
		for rows.Next() {
			var f FindingItem
			if err := rows.Scan(&f.ID, &f.Pass, &f.Aspect, &f.Severity, &f.FindingType,
				&f.Title, &f.Description, &f.Evidence, &f.Location, &f.Suggestion,
				&f.Confidence, &f.ReviewStatus); err != nil {
				return nil, fmt.Errorf("scan finding: %w", err)
			}
			result.Findings = append(result.Findings, f)
		}
	}
	return result, nil
}

// StopRequest transitions a running request to stopped.
func (c *DocReviewController) StopRequest(ctx context.Context, requestID int64) error {
	res, err := c.DB.ExecContext(ctx,
		`UPDATE kb.doc_review_requests SET status = 'stopped', end_time = NOW() WHERE id = $1 AND status = 'running'`,
		requestID,
	)
	if err != nil {
		return fmt.Errorf("stop request %d: %w", requestID, err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("request %d is not in 'running' status", requestID)
	}
	return nil
}

// UpdateFinding updates review_status and reviewed_by on a finding.
func (c *DocReviewController) UpdateFinding(ctx context.Context, findingID int64, reviewStatus string, reviewedBy string) error {
	allowed := map[string]bool{"pending": true, "accepted": true, "rejected": true, "deferred": true}
	if !allowed[reviewStatus] {
		return fmt.Errorf("invalid review_status: %q (must be pending/accepted/rejected/deferred)", reviewStatus)
	}
	res, err := c.DB.ExecContext(ctx,
		`UPDATE kb.doc_review_findings SET review_status = $1, reviewed_by = $2 WHERE id = $3`,
		reviewStatus, reviewedBy, findingID,
	)
	if err != nil {
		return fmt.Errorf("update finding %d: %w", findingID, err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("finding %d not found", findingID)
	}
	return nil
}

// loadRequest fetches one request row.
func (c *DocReviewController) loadRequest(ctx context.Context, id int64) (*RequestStatus, error) {
	var req RequestStatus
	var aspectsJSON, refDocsJSON, overridesJSON sql.NullString
	var reviewRunID, notes, errorMsg, startTime, endTime sql.NullString
	var reportTmpl, docTmpl sql.NullString

	err := c.DB.QueryRowContext(ctx, `
		SELECT id, input_record_id, COALESCE(review_run_id,''), tier, aspects::text,
		       COALESCE(reference_docs::text,''), COALESCE(notes,''), COALESCE(model_overrides::text,''),
		       requester_name, requester_id, COALESCE(report_template,''), COALESCE(doc_template,''),
		       status, create_time::text, COALESCE(start_time::text,''), COALESCE(end_time::text,''),
		       COALESCE(error_message,'')
		FROM kb.doc_review_requests WHERE id = $1`, id,
	).Scan(&req.ID, &req.InputRecordID, &reviewRunID, &req.Tier, &aspectsJSON,
		&refDocsJSON, &notes, &overridesJSON,
		&req.RequesterName, &req.RequesterID, &reportTmpl, &docTmpl,
		&req.Status, &req.CreateTime, &startTime, &endTime, &errorMsg)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("request %d not found", id)
		}
		return nil, fmt.Errorf("load request %d: %w", id, err)
	}

	req.ReviewRunID = reviewRunID.String
	req.Notes = notes.String
	req.ReportTemplate = reportTmpl.String
	req.DocTemplate = docTmpl.String
	req.StartTime = startTime.String
	req.EndTime = endTime.String
	req.ErrorMessage = errorMsg.String

	if aspectsJSON.Valid {
		json.Unmarshal([]byte(aspectsJSON.String), &req.Aspects)
	}
	if refDocsJSON.Valid && refDocsJSON.String != "" {
		json.Unmarshal([]byte(refDocsJSON.String), &req.ReferenceDocs)
	}
	if overridesJSON.Valid && overridesJSON.String != "" {
		json.Unmarshal([]byte(overridesJSON.String), &req.ModelOverrides)
	}
	return &req, nil
}

// RequestError is an HTTP-level error with status code.
type RequestError struct {
	Status  int
	Message string
}

func (e *RequestError) Error() string { return e.Message }
```

- [ ] **Step 2: Verify compilation**

Run: `cd /Users/cding/Workspace/ChenWeb/server && go build ./api/docreview/`

Expected: no errors

---

### Task 4: DocReviewReportGenerator

**Files:**
- Create: `server/api/docreview/report.go`
- Create: `server/api/docreview/report_template.html`
- Create: `server/api/docreview/report_markdown.tmpl`

**Interfaces:**
- Consumes: `FindingItem`, `RequestStatus` (Task 2), `ApiTypes.ProjectDBHandle`
- Produces: `DocReviewReportGenerator` with `Build` method
- Consumed by Task 5 (handler)

- [ ] **Step 1: Write report.go**

```go
package docreview

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"html/template"
	"sort"
	"strings"
	"text/tabwriter"

	"github.com/chendingplano/shared/go/api/ApiTypes"
)

// DocReviewReportGenerator builds structured reports from findings.
type DocReviewReportGenerator struct {
	DB *sql.DB
}

// NewDocReviewReportGenerator creates a report generator.
func NewDocReviewReportGenerator() *DocReviewReportGenerator {
	return &DocReviewReportGenerator{DB: ApiTypes.ProjectDBHandle}
}

// ReportSkeleton is the full report structure stored in report_json.
type ReportSkeleton struct {
	Meta           ReportMeta              `json:"meta"`
	ExecutiveSummary ExecutiveSummary       `json:"executive_summary"`
	FindingsByPass map[string]PassGroup     `json:"findings_by_pass"`
	ComplianceSummary ComplianceSummary      `json:"compliance_summary,omitempty"`
	Findings       []ReportFinding          `json:"findings"`
	Recommendations []Recommendation        `json:"recommendations"`
}

type ReportMeta struct {
	ReportID       string `json:"report_id"`
	DocumentTitle  string `json:"document_title"`
	DocumentRecordID int64 `json:"document_record_id"`
	GeneratedAt    string `json:"generated_at"`
	ReviewRunID    string `json:"review_run_id"`
	NumReviewersRan int   `json:"num_reviewers_ran"`
	TotalFindings  int    `json:"total_findings"`
}

type ExecutiveSummary struct {
	Text              string   `json:"text"`
	TopFindings       []string `json:"top_findings"`
	OverallAssessment string   `json:"overall_assessment"`
}

type PassGroup struct {
	Label    string         `json:"label"`
	Findings []ReportFinding `json:"findings"`
}

type ReportFinding struct {
	Pass        string `json:"pass"`
	Aspect      string `json:"aspect"`
	Severity    string `json:"severity"`
	FindingType string `json:"finding_type"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Evidence    string `json:"evidence,omitempty"`
	Location    string `json:"location,omitempty"`
	Suggestion  string `json:"suggestion,omitempty"`
	Confidence  float64 `json:"confidence"`
}

type ComplianceSummary struct {
	ReferenceStandardsChecked []string `json:"reference_standards_checked"`
	ProvisionsSatisfied       int      `json:"provisions_satisfied"`
	ProvisionsPartiallySatisfied int   `json:"provisions_partially_satisfied"`
	ProvisionsNotAddressed    int      `json:"provisions_not_addressed"`
	ProvisionsNotApplicable   int      `json:"provisions_not_applicable"`
	MissingRequirements       []string `json:"missing_requirements"`
}

type Recommendation struct {
	Priority        int      `json:"priority"`
	Action          string   `json:"action"`
	RelatedFindingIDs []int  `json:"related_finding_ids"`
}

// Build assembles the full report for a given review request.
func (g *DocReviewReportGenerator) Build(ctx context.Context, req *RequestStatus, findings []FindingItem) (*ReportSkeleton, error) {
	// Build meta.
	report := &ReportSkeleton{
		Meta: ReportMeta{
			ReportID:          fmt.Sprintf("rpt_%d_%s", req.InputRecordID, strings.ReplaceAll(req.CreateTime, " ", "T")),
			DocumentRecordID:  req.InputRecordID,
			GeneratedAt:       timeNow(),
			ReviewRunID:       req.ReviewRunID,
			TotalFindings:     len(findings),
		},
		FindingsByPass: make(map[string]PassGroup),
	}

	// Load document metadata.
	var docTitle string
	g.DB.QueryRowContext(ctx, `SELECT COALESCE(title,'') FROM kb.inputs WHERE id = $1`, req.InputRecordID).Scan(&docTitle)
	report.Meta.DocumentTitle = docTitle

	// Group findings by pass.
	passLabels := map[string]string{
		"P1": "Language & Style", "P2": "Structure & Organization",
		"P3": "Content Quality", "P4": "Consistency",
		"P5": "Technical & Compliance", "P6": "Meta & Process",
	}
	passFindings := make(map[string][]FindingItem)
	for _, f := range findings {
		passFindings[f.Pass] = append(passFindings[f.Pass], f)
	}
	report.Meta.NumReviewersRan = len(passFindings)

	var totalHigh, totalMedium, totalLow int
	for pass, items := range passFindings {
		var rfList []ReportFinding
		for _, f := range items {
			rf := ReportFinding{
				Pass: f.Pass, Aspect: f.Aspect, Severity: f.Severity,
				FindingType: f.FindingType, Title: f.Title, Description: f.Description,
				Evidence: f.Evidence, Location: f.Location, Suggestion: f.Suggestion,
				Confidence: f.Confidence,
			}
			rfList = append(rfList, rf)
			report.Findings = append(report.Findings, rf)
			switch f.Severity {
			case "high": totalHigh++
			case "medium": totalMedium++
			default: totalLow++
			}
		}
		report.FindingsByPass[pass] = PassGroup{
			Label:    passLabels[pass],
			Findings: rfList,
		}
	}

	// Build executive summary.
	overall := "pass_with_issues"
	if totalHigh > 0 {
		overall = "fail"
	} else if totalHigh == 0 && totalMedium == 0 && totalLow == 0 {
		overall = "pass_with_issues" // no findings still needs review
	}

	topFindings := make([]string, 0, 3)
	for _, f := range report.Findings {
		if f.Severity == "high" && len(topFindings) < 3 {
			topFindings = append(topFindings, f.Title)
		}
	}
	if len(topFindings) == 0 && len(report.Findings) > 0 {
		topFindings = append(topFindings, report.Findings[0].Title)
	}

	summaryText := fmt.Sprintf("Reviewed %d aspects across %d passes. Found %d findings (%d high, %d medium, %d low).",
		len(findings), report.Meta.NumReviewersRan, len(findings), totalHigh, totalMedium, totalLow)
	if totalHigh > 0 {
		summaryText += fmt.Sprintf(" %d high-severity issues require immediate attention.", totalHigh)
	}
	report.ExecutiveSummary = ExecutiveSummary{
		Text:              summaryText,
		TopFindings:       topFindings,
		OverallAssessment: overall,
	}

	// Build compliance summary (findings tagged with reference docs).
	var refsChecked []string
	refSeen := map[string]bool{}
	var missingReqs []string
	for _, f := range findings {
		if f.FindingType == "missing_requirement" || f.FindingType == "missing_provision" {
			missingReqs = append(missingReqs, f.Title)
		}
	}
	for _, rd := range req.ReferenceDocs {
		if !refSeen[rd.DocNo] {
			refsChecked = append(refsChecked, rd.DocNo)
			refSeen[rd.DocNo] = true
		}
	}
	report.ComplianceSummary = ComplianceSummary{
		ReferenceStandardsChecked: refsChecked,
		MissingRequirements:       missingReqs,
	}

	// Build recommendations from high-severity findings.
	for i, f := range report.Findings {
		if f.Severity == "high" {
			report.Recommendations = append(report.Recommendations, Recommendation{
				Priority:          len(report.Recommendations) + 1,
				Action:            f.Suggestion,
				RelatedFindingIDs: []int{i + 1},
			})
		}
	}

	return report, nil
}

// Persist saves the report to kb.doc_review_reports and returns the report ID.
func (g *DocReviewReportGenerator) Persist(ctx context.Context, req *RequestStatus, report *ReportSkeleton) (int64, error) {
	reportJSON, _ := json.Marshal(report)
	markdown := renderMarkdown(report)
	html, _ := renderHTML(report)

	var id int64
	err := g.DB.QueryRowContext(ctx, `
		INSERT INTO kb.doc_review_reports
			(request_id, input_record_id, review_run_id, report_json, report_markdown,
			 executive_summary, total_findings, high_count, medium_count, low_count,
			 overall_assessment)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		RETURNING id`,
		req.ID, req.InputRecordID, req.ReviewRunID, reportJSON, markdown,
		report.ExecutiveSummary.Text, report.Meta.TotalFindings,
		countBySeverity(report.Findings, "high"),
		countBySeverity(report.Findings, "medium"),
		countBySeverity(report.Findings, "low"),
		report.ExecutiveSummary.OverallAssessment,
	).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("insert report: %w", err)
	}
	_ = html // stored separately or served via template
	return id, nil
}

// GetReport returns the full report from the database.
func (g *DocReviewReportGenerator) GetReport(ctx context.Context, reportID int64) (*ReportDetail, error) {
	var d ReportDetail
	var execSummary, markdown string
	var reportJSONBytes []byte

	err := g.DB.QueryRowContext(ctx, `
		SELECT id, request_id, input_record_id, review_run_id,
		       total_findings, high_count, medium_count, low_count,
		       overall_assessment, create_time::text,
		       executive_summary, report_json::text, report_markdown
		FROM kb.doc_review_reports WHERE id = $1`, reportID,
	).Scan(&d.ID, &d.RequestID, &d.InputRecordID, &d.ReviewRunID,
		&d.TotalFindings, &d.HighCount, &d.MediumCount, &d.LowCount,
		&d.OverallAssessment, &d.CreateTime,
		&execSummary, &reportJSONBytes, &markdown)
	if err != nil {
		return nil, fmt.Errorf("load report %d: %w", reportID, err)
	}
	d.ExecutiveSummary = execSummary
	d.ReportMarkdown = markdown
	json.Unmarshal(reportJSONBytes, &d.ReportJSON)
	return &d, nil
}

// GetReportHTML renders the HTML template for a report.
func (g *DocReviewReportGenerator) GetReportHTML(ctx context.Context, reportID int64) (string, error) {
	report, err := g.GetReport(ctx, reportID)
	if err != nil {
		return "", err
	}
	return renderHTMLFromMap(report.ReportJSON)
}

func countBySeverity(findings []ReportFinding, sev string) int {
	var n int
	for _, f := range findings {
		if f.Severity == sev {
			n++
		}
	}
	return n
}

func timeNow() string { return time.Now().UTC().Format(time.RFC3339) }

// renderMarkdown renders the report as Markdown.
func renderMarkdown(report *ReportSkeleton) string {
	var b strings.Builder
	b.WriteString(fmt.Sprintf("# Document Review Report\n\n"))
	b.WriteString(fmt.Sprintf("**Document:** %s (ID: %d)\n", report.Meta.DocumentTitle, report.Meta.DocumentRecordID))
	b.WriteString(fmt.Sprintf("**Generated:** %s\n", report.Meta.GeneratedAt))
	b.WriteString(fmt.Sprintf("**Total Findings:** %d\n\n", report.Meta.TotalFindings))

	b.WriteString("## Executive Summary\n\n")
	b.WriteString(report.ExecutiveSummary.Text + "\n\n")
	b.WriteString(fmt.Sprintf("**Assessment:** %s\n\n", report.ExecutiveSummary.OverallAssessment))

	if len(report.ExecutiveSummary.TopFindings) > 0 {
		b.WriteString("### Top Findings\n")
		for _, tf := range report.ExecutiveSummary.TopFindings {
			b.WriteString(fmt.Sprintf("- %s\n", tf))
		}
		b.WriteString("\n")
	}

	passOrder := []string{"P1","P2","P3","P4","P5","P6"}
	for _, p := range passOrder {
		pg, ok := report.FindingsByPass[p]
		if !ok || len(pg.Findings) == 0 {
			continue
		}
		b.WriteString(fmt.Sprintf("## %s — %s\n\n", p, pg.Label))
		for _, f := range pg.Findings {
			b.WriteString(fmt.Sprintf("### [%s] %s\n", strings.ToUpper(f.Severity), f.Title))
			b.WriteString(fmt.Sprintf("**Aspect:** %s | **Type:** %s\n", f.Aspect, f.FindingType))
			if f.Description != "" {
				b.WriteString(fmt.Sprintf("\n%s\n", f.Description))
			}
			if f.Suggestion != "" {
				b.WriteString(fmt.Sprintf("\n*Suggestion:* %s\n", f.Suggestion))
			}
			if f.Location != "" {
				b.WriteString(fmt.Sprintf("\n*Location:* %s\n", f.Location))
			}
			b.WriteString("\n")
		}
	}
	return b.String()
}

// renderHTML renders the HTML report from a ReportSkeleton.
func renderHTML(report *ReportSkeleton) (string, error) {
	tmpl := template.Must(template.New("report").Parse(reportHTMLTemplate))
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, report); err != nil {
		return "", err
	}
	return buf.String(), nil
}

// renderHTMLFromMap renders the HTML template from a JSON map (for on-the-fly view).
func renderHTMLFromMap(data map[string]any) (string, error) {
	tmpl := template.Must(template.New("report").Parse(reportHTMLTemplate))
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", err
	}
	return buf.String(), nil
}

// reportHTMLTemplate is the HTML template for online report viewing.
const reportHTMLTemplate = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{{.Meta.DocumentTitle}} — Review Report</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 960px; margin: 0 auto; padding: 2rem; color: #1a1a2e; background: #f8f9fa; }
  h1 { color: #1a1a2e; border-bottom: 2px solid #4361ee; padding-bottom: 0.5rem; }
  h2 { color: #3a0ca3; margin-top: 2rem; }
  h3 { color: #4361ee; }
  .meta { color: #64748b; font-size: 0.9rem; }
  .assessment { display: inline-block; padding: 0.25rem 0.75rem; border-radius: 4px; font-weight: 600; }
  .assessment.fail { background: #fee2e2; color: #dc2626; }
  .assessment.pass_with_issues { background: #fef9c3; color: #a16207; }
  .finding { background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 1rem; margin: 0.75rem 0; }
  .finding.high { border-left: 4px solid #dc2626; }
  .finding.medium { border-left: 4px solid #f59e0b; }
  .finding.low { border-left: 4px solid #10b981; }
  .sev-high { color: #dc2626; font-weight: 600; }
  .sev-medium { color: #f59e0b; font-weight: 600; }
  .sev-low { color: #10b981; font-weight: 600; }
  .badge { display: inline-block; padding: 0.15rem 0.5rem; border-radius: 999px; font-size: 0.75rem; background: #e2e8f0; }
  .summary-cards { display: flex; gap: 1rem; margin: 1rem 0; }
  .summary-card { background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 1rem 1.5rem; flex: 1; text-align: center; }
  .summary-card .count { font-size: 2rem; font-weight: 700; }
  .summary-card .label { font-size: 0.8rem; color: #64748b; }
  .summary-card.high .count { color: #dc2626; }
  .summary-card.medium .count { color: #f59e0b; }
  .summary-card.low .count { color: #10b981; }
</style>
</head>
<body>
<h1>Document Review Report</h1>
<p class="meta">Document: {{.Meta.DocumentTitle}} (ID: {{.Meta.DocumentRecordID}})<br>
Generated: {{.Meta.GeneratedAt}}<br>
Review Run: {{.Meta.ReviewRunID}}</p>

<div class="summary-cards">
  <div class="summary-card high"><div class="count">{{.Meta.TotalFindings}}</div><div class="label">Total Findings</div></div>
</div>

<h2>Executive Summary</h2>
<p>{{.ExecutiveSummary.Text}}</p>
<p>Assessment: <span class="assessment {{.ExecutiveSummary.OverallAssessment}}">{{.ExecutiveSummary.OverallAssessment}}</span></p>

{{if .ExecutiveSummary.TopFindings}}
<h3>Top Findings</h3>
<ul>{{range .ExecutiveSummary.TopFindings}}<li>{{.}}</li>{{end}}</ul>
{{end}}

{{range $pass, $pg := .FindingsByPass}}
<h2>{{$pass}} — {{$pg.Label}}</h2>
{{range $pg.Findings}}
<div class="finding {{.Severity}}">
  <strong>{{.Title}}</strong>
  <span class="sev-{{.Severity}}">[{{.Severity | upper}}]</span>
  <span class="badge">{{.Aspect}}</span>
  <p>{{.Description}}</p>
  {{if .Suggestion}}<p><em>Suggestion:</em> {{.Suggestion}}</p>{{end}}
  {{if .Location}}<p class="meta">Location: {{.Location}}</p>{{end}}
</div>
{{end}}
{{end}}

{{if .ComplianceSummary.MissingRequirements}}
<h2>Compliance Gaps</h2>
<ul>{{range .ComplianceSummary.MissingRequirements}}<li>{{.}}</li>{{end}}</ul>
{{end}}
</body>
</html>`
```

- [ ] **Step 2: Add the `time` import to report.go**

The `timeNow` function needs `"time"`. The `renderHTML` function embeds the template — no separate file needed for HTML template (it's a const in Go, served via the endpoint). The Markdown template is also inline in `renderMarkdown`.

- [ ] **Step 3: Verify compilation**

Run: `cd /Users/cding/Workspace/ChenWeb/server && go build ./api/docreview/`
Expected: no errors

---

### Task 5: HTTP Handler — API Endpoints

**Files:**
- Create: `server/api/docreviewhandler/handler.go`

**Interfaces:**
- Consumes: `DocReviewController` (Task 3), `DocReviewReportGenerator` (Task 4)
- Produces: 9 exported handler functions consumed by Task 6 (routes.go)

- [ ] **Step 1: Write handler.go**

```go
package docreviewhandler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/chendingplano/deepdoc/server/api/docreview"
	"github.com/labstack/echo/v4"
)

// ListAspects returns all review aspects.
func ListAspects(c echo.Context) error {
	aspects := docreview.ListAspects()
	return c.JSON(http.StatusOK, map[string]any{
		"status":  true,
		"aspects": aspects,
	})
}

// ListTiers returns tier definitions with aspect mappings.
func ListTiers(c echo.Context) error {
	tiers := docreview.ListTiers()
	return c.JSON(http.StatusOK, map[string]any{
		"status": true,
		"tiers":  tiers,
	})
}

func submitRequestHelper(c echo.Context, synchronous bool) error {
	ctrl := docreview.NewDocReviewController()

	var input docreview.SubmitRequestInput
	if err := c.Bind(&input); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{
			"status":     false,
			"error_msg":  "Invalid request body: " + err.Error(),
		})
	}

	ctx := c.Request().Context()

	// Accept the request (validates and persists).
	result, err := ctrl.AcceptRequest(ctx, input)
	if err != nil {
		if re, ok := err.(*docreview.RequestError); ok {
			return c.JSON(re.Status, map[string]any{
				"status":    false,
				"error_msg": re.Message,
			})
		}
		return c.JSON(http.StatusInternalServerError, map[string]any{
			"status":    false,
			"error_msg": err.Error(),
		})
	}

	// Run the review synchronously (the controller handles the lifecycle).
	if err := ctrl.RunReview(ctx, result.RequestID); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]any{
			"status":    false,
			"error_msg": err.Error(),
		})
	}

	// Generate report.
	req, _ := ctrl.GetRequest(ctx, result.RequestID)
	if req != nil && req.Status == "completed" {
		wf, _ := ctrl.GetRequestWithFindings(ctx, result.RequestID)
		gen := docreview.NewDocReviewReportGenerator()
		report, buildErr := gen.Build(ctx, &wf.Request, wf.Findings)
		if buildErr == nil {
			reportID, persistErr := gen.Persist(ctx, &wf.Request, report)
			if persistErr == nil {
				result.ReviewRunID = req.ReviewRunID
				return c.JSON(http.StatusOK, map[string]any{
					"status":     true,
					"request_id": result.RequestID,
					"report_id":  reportID,
				})
			}
		}
	}

	return c.JSON(http.StatusOK, map[string]any{
		"status":     true,
		"request_id": result.RequestID,
	})
}

// SubmitRequest creates and runs a review request synchronously.
func SubmitRequest(c echo.Context) error {
	return submitRequestHelper(c, true)
}

// parseID extracts an int64 path parameter.
func parseID(c echo.Context, name string) (int64, error) {
	return strconv.ParseInt(c.Param(name), 10, 64)
}

// GetRequest returns request status + findings.
func GetRequest(c echo.Context) error {
	id, err := parseID(c, "id")
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{"status": false, "error_msg": "Invalid ID"})
	}
	ctrl := docreview.NewDocReviewController()
	result, err := ctrl.GetRequestWithFindings(c.Request().Context(), id)
	if err != nil {
		return c.JSON(http.StatusNotFound, map[string]any{"status": false, "error_msg": err.Error()})
	}
	return c.JSON(http.StatusOK, map[string]any{"status": true, "request": result.Request, "findings": result.Findings})
}

// GetReport returns the full report JSON.
func GetReport(c echo.Context) error {
	id, err := parseID(c, "id")
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{"status": false, "error_msg": "Invalid ID"})
	}
	gen := docreview.NewDocReviewReportGenerator()
	report, err := gen.GetReport(c.Request().Context(), id)
	if err != nil {
		return c.JSON(http.StatusNotFound, map[string]any{"status": false, "error_msg": err.Error()})
	}
	return c.JSON(http.StatusOK, map[string]any{"status": true, "report": report})
}

// GetReportHTML returns the HTML-rendered report.
func GetReportHTML(c echo.Context) error {
	id, err := parseID(c, "id")
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{"status": false, "error_msg": "Invalid ID"})
	}
	gen := docreview.NewDocReviewReportGenerator()
	html, err := gen.GetReportHTML(c.Request().Context(), id)
	if err != nil {
		return c.JSON(http.StatusNotFound, map[string]any{"status": false, "error_msg": err.Error()})
	}
	return c.HTML(http.StatusOK, html)
}

// ExportReport returns the report in the requested format.
func ExportReport(c echo.Context) error {
	id, err := parseID(c, "id")
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{"status": false, "error_msg": "Invalid ID"})
	}
	gen := docreview.NewDocReviewReportGenerator()
	report, err := gen.GetReport(c.Request().Context(), id)
	if err != nil {
		return c.JSON(http.StatusNotFound, map[string]any{"status": false, "error_msg": err.Error()})
	}

	format := c.QueryParam("format")
	switch format {
	case "md", "markdown":
		return c.Blob(http.StatusOK, "text/markdown; charset=utf-8", []byte(report.ReportMarkdown))
	case "pdf":
		// Deferred — return markdown for now.
		return c.Blob(http.StatusOK, "text/markdown; charset=utf-8", []byte(report.ReportMarkdown))
	default:
		// Return JSON.
		reportJSON, _ := json.Marshal(report.ReportJSON)
		return c.Blob(http.StatusOK, "application/json", reportJSON)
	}
}

// UpdateFinding updates a finding's review_status.
func UpdateFinding(c echo.Context) error {
	id, err := parseID(c, "id")
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{"status": false, "error_msg": "Invalid ID"})
	}
	var body struct {
		ReviewStatus string `json:"review_status"`
		ReviewedBy   string `json:"reviewed_by"`
	}
	if err := c.Bind(&body); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{"status": false, "error_msg": "Invalid body"})
	}
	ctrl := docreview.NewDocReviewController()
	if err := ctrl.UpdateFinding(c.Request().Context(), id, body.ReviewStatus, body.ReviewedBy); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{"status": false, "error_msg": err.Error()})
	}
	return c.JSON(http.StatusOK, map[string]any{"status": true})
}

// StopRequest stops a running review.
func StopRequest(c echo.Context) error {
	id, err := parseID(c, "id")
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{"status": false, "error_msg": "Invalid ID"})
	}
	ctrl := docreview.NewDocReviewController()
	if err := ctrl.StopRequest(c.Request().Context(), id); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]any{"status": false, "error_msg": err.Error()})
	}
	return c.JSON(http.StatusOK, map[string]any{"status": true})
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd /Users/cding/Workspace/ChenWeb/server && go build ./api/docreviewhandler/`
Expected: no errors

---

### Task 6: Route Registration

**Files:**
- Modify: `server/api/routes.go`

**Interfaces:**
- Consumes: handler functions from Task 5
- Produces: working HTTP endpoints

- [ ] **Step 1: Add import to routes.go**

Add after the existing imports block (around line 36):
```go
"github.com/chendingplano/deepdoc/server/api/docreviewhandler"
```

- [ ] **Step 2: Add route registrations**

Add before the closing `return nil` of `RegisterRoutes`, after the existing `/api/v1` apiGroup routes (around line 244):
```go
// Doc Review endpoints.
apiGroup.GET("/doc-review/aspects", docreviewhandler.ListAspects)
apiGroup.GET("/doc-review/tiers", docreviewhandler.ListTiers)
apiGroup.POST("/doc-review/requests", docreviewhandler.SubmitRequest)
apiGroup.GET("/doc-review/requests/:id", docreviewhandler.GetRequest)
apiGroup.GET("/doc-review/reports/:id", docreviewhandler.GetReport)
apiGroup.GET("/doc-review/reports/:id/html", docreviewhandler.GetReportHTML)
apiGroup.GET("/doc-review/reports/:id/export", docreviewhandler.ExportReport)
apiGroup.PATCH("/doc-review/findings/:id", docreviewhandler.UpdateFinding)
apiGroup.POST("/doc-review/requests/:id/stop", docreviewhandler.StopRequest)
```

- [ ] **Step 3: Build and verify compilation**

Run: `cd /Users/cding/Workspace/ChenWeb/server && go build ./api/`
Expected: no errors

---

### Task 7: Frontend API Service

**Files:**
- Create: `web/src/lib/services/docReviewService.ts`

**Interfaces:**
- Produces: `listAspects`, `listTiers`, `submitRequest`, `getRequest`, `getReport`, `updateFinding`, `stopRequest` functions
- Consumed by Task 9 (form view) and Task 10 (results view)

- [ ] **Step 1: Write docReviewService.ts**

```typescript
const BASE = '/api/v1/doc-review';

export type AspectInfo = {
    name: string;
    group: string;       // "P1".."P6"
    label: string;
    priority: string;
    description: string;
    default_model: string;
    is_tool_use: boolean;
};

export type TierInfo = {
    key: string;
    label: string;
    description: string;
    aspect_names: string[];
};

export type ReferenceDoc = {
    record_id: number;
    doc_no: string;
    title: string;
};

export type SubmitInput = {
    input_record_id: number;
    tier: string;
    aspects: string[];
    reference_docs?: ReferenceDoc[];
    notes?: string;
    model_overrides?: Record<string, { model_ref: string }>;
    requester_name: string;
    requester_id: number;
    report_template?: string;
    doc_template?: string;
};

export type SubmitResult = {
    request_id: number;
    status: string;
    review_run_id?: string;
};

export type RequestStatus = {
    id: number;
    input_record_id: number;
    review_run_id?: string;
    tier: string;
    aspects: string[];
    reference_docs?: ReferenceDoc[];
    notes?: string;
    model_overrides?: Record<string, { model_ref: string }>;
    requester_name: string;
    requester_id: number;
    status: string;
    create_time: string;
    start_time?: string;
    end_time?: string;
    error_message?: string;
};

export type FindingItem = {
    id: number;
    pass: string;
    aspect: string;
    severity: string;
    finding_type: string;
    title: string;
    description: string;
    evidence?: string;
    location?: string;
    suggestion?: string;
    confidence: number;
    review_status: string;
};

export async function listAspects(): Promise<AspectInfo[]> {
    const res = await fetch(`${BASE}/aspects`, { credentials: 'same-origin' });
    const data = await res.json();
    if (!data.status) throw new Error(data.error_msg || 'Failed to load aspects');
    return data.aspects;
}

export async function listTiers(): Promise<TierInfo[]> {
    const res = await fetch(`${BASE}/tiers`, { credentials: 'same-origin' });
    const data = await res.json();
    if (!data.status) throw new Error(data.error_msg || 'Failed to load tiers');
    return data.tiers;
}

export async function submitRequest(input: SubmitInput): Promise<SubmitResult> {
    const res = await fetch(`${BASE}/requests`, {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(input),
    });
    const data = await res.json();
    if (!data.status) {
        throw new Error(data.error_msg || 'Failed to submit review request');
    }
    return { request_id: data.request_id, status: data.status, review_run_id: data.review_run_id };
}

export async function getRequest(id: number): Promise<{ request: RequestStatus; findings: FindingItem[] }> {
    const res = await fetch(`${BASE}/requests/${id}`, { credentials: 'same-origin' });
    const data = await res.json();
    if (!data.status) throw new Error(data.error_msg || 'Failed to load request');
    return { request: data.request, findings: data.findings || [] };
}

export async function getReport(id: number): Promise<any> {
    const res = await fetch(`${BASE}/reports/${id}`, { credentials: 'same-origin' });
    const data = await res.json();
    if (!data.status) throw new Error(data.error_msg || 'Failed to load report');
    return data.report;
}

export async function updateFinding(id: number, review_status: string, reviewed_by?: string): Promise<void> {
    const res = await fetch(`${BASE}/findings/${id}`, {
        method: 'PATCH',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ review_status, reviewed_by }),
    });
    const data = await res.json();
    if (!data.status) throw new Error(data.error_msg || 'Failed to update finding');
}

export async function stopRequest(id: number): Promise<void> {
    const res = await fetch(`${BASE}/requests/${id}/stop`, {
        method: 'POST',
        credentials: 'same-origin',
    });
    const data = await res.json();
    if (!data.status) throw new Error(data.error_msg || 'Failed to stop request');
}
```

---

### Task 8: Nav & View Wiring

**Files:**
- Modify: `web/src/lib/components/home3/nav-rail.svelte`
- Modify: `web/src/lib/components/home3/content-panel.svelte`

**Interfaces:**
- Produces: Navigable menu item + view rendering hook
- Consumed by: User interaction (Task 9 + Task 10 render when selected)

- [ ] **Step 1: Add nav item in nav-rail.svelte**

In `nav-rail.svelte`, find the `applications` children array (around line 121-126) and add after the `apps-generate-doc` entry:
```typescript
{ id: 'apps-document-review', label: 'Document Review' },
```

The result should look like:
```typescript
children: [
    { id: 'apps-installed',       label: 'Installed' },
    { id: 'apps-browse',          label: 'Browse' },
    { id: 'apps-configure',       label: 'Configure' },
    { id: 'apps-generate-doc',    label: 'Generate Doc' },
    { id: 'apps-document-review', label: 'Document Review' },
]
```

- [ ] **Step 2: Add import and view branch in content-panel.svelte**

Add import at the top of `content-panel.svelte` (around line 7):
```typescript
import DocumentReviewView from '$lib/components/home3/document-review-view.svelte';
```

Add the view branch in the if/else chain (after the `apps-generate-doc` branch around line 168):
```svelte
{:else if activeMenu?.childId === 'apps-document-review'}
    <DocumentReviewView {darkMode} />
```

---

### Task 9: Document Review Form View (5-step form)

**Files:**
- Create: `web/src/lib/components/home3/document-review-view.svelte`

**Interfaces:**
- Consumes: `docReviewService.ts` (Task 7), `{ darkMode: boolean }` prop
- Produces: Submit request → navigates to results view (internal state toggle)

- [ ] **Step 1: Write document-review-view.svelte**

Create a comprehensive Svelte 5 component with:

1. **Step 1 — Select Document**: A searchable document list. The component fetches from existing `kbService.ts` (which has KB input listing), or calls a dedicated search endpoint. Use a debounced search input + dropdown.

2. **Step 2 — Choose Check Level**: Radio buttons for Must Review / Should Review / Custom. When Custom is selected, it loads and shows Step 3.

3. **Step 3 — Customize Aspects**: Loaded from `listAspects()`, grouped by P1–P6. Each group is a collapsible section with checkboxes. Default: all Must Review aspects checked.

4. **Step 4 — Supporting Documents**: An optional search-and-add input for reference documents. Uses existing kbService search.

5. **Step 5 — Notes + Requester**: Text inputs for requester name, notes (textarea), and optional report/doc templates.

**Submit button**: Validates requester name is filled, calls `submitRequest()`, on success toggles to results view with the request_id.

**Internal state management**:
```typescript
let currentStep = $state(1);
let selectedDoc = $state<{id: number; title: string} | null>(null);
let selectedTier = $state('must_review');
let customAspects = $state<string[]>([]);
let requesterName = $state('');
let requesterId = $state(0);
let notes = $state('');
let referenceDocs = $state<ReferenceDoc[]>([]);
let submittedRequestId = $state<number | null>(null);
let isSubmitting = $state(false);
let error = $state('');
```

After submission, the view switches internally to show `DocReviewResultsView` inline when `submittedRequestId` is set.

```svelte
<script lang="ts">
    import { onMount } from 'svelte';
    import { listAspects, listTiers, submitRequest, getRequest, updateFinding } from '$lib/services/docReviewService';
    import type { AspectInfo, TierInfo, FindingItem, ReferenceDoc } from '$lib/services/docReviewService';
    import DocReviewResultsView from './doc-review-results-view.svelte';
    import SearchIcon from '@lucide/svelte/icons/search';
    import CheckIcon from '@lucide/svelte/icons/check';
    import XIcon from '@lucide/svelte/icons/x';
    import LoaderIcon from '@lucide/svelte/icons/loader';
    import ChevronDownIcon from '@lucide/svelte/icons/chevron-down';
    import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';

    let { darkMode = true }: { darkMode: boolean } = $props();

    // Design tokens
    let cardBg = $derived(darkMode ? '#1F2333' : '#FFFFFF');
    let borderColor = $derived(darkMode ? '#2D3348' : '#E4E6EB');
    let accent = $derived(darkMode ? '#818CF8' : '#6366F1');
    let accentTint = $derived(darkMode ? 'rgba(129,140,248,0.15)' : 'rgba(99,102,241,0.10)');
    let textPrimary = $derived(darkMode ? '#E2E8F0' : '#111827');
    let textSecondary = $derived(darkMode ? '#94A3B8' : '#6B7280');
    let textMuted = $derived(darkMode ? '#64748B' : '#9CA3AF');
    let inputBg = $derived(darkMode ? '#0F1729' : '#F8FAFC');
    let successBg = $derived(darkMode ? 'rgba(34,197,94,0.15)' : 'rgba(34,197,94,0.10)');
    let errorBg = $derived(darkMode ? 'rgba(239,68,68,0.15)' : 'rgba(239,68,68,0.10)');

    // State
    let aspects = $state<AspectInfo[]>([]);
    let tiers = $state<TierInfo[]>([]);
    let currentStep = $state(1);
    let selectedDocId = $state<number | null>(null);
    let selectedDocTitle = $state('');
    let selectedTier = $state('must_review');
    let customAspects = $state<Set<string>>(new Set());
    let expandedGroups = $state<Set<string>>(new Set(['P1', 'P3', 'P5']));
    let requesterName = $state('');
    let notes = $state('');
    let referenceDocs = $state<ReferenceDoc[]>([]);
    let submittedRequestId = $state<number | null>(null);
    let submitError = $state('');
    let isSubmitting = $state(false);
    let searchQuery = $state('');
    let docSearchResults = $state<Array<{id: number; title: string}>>([]);
    let isSearching = $state(false);

    // Derived: aspects grouped by group
    let aspectsByGroup = $derived.by(() => {
        const map: Record<string, AspectInfo[]> = {};
        for (const a of aspects) {
            if (!map[a.group]) map[a.group] = [];
            map[a.group].push(a);
        }
        return map;
    });

    // Derived: which aspects are selected based on tier
    let effectiveAspects = $derived.by(() => {
        if (selectedTier === 'custom') {
            return [...customAspects];
        }
        const tier = tiers.find(t => t.key === selectedTier);
        return tier?.aspect_names || [];
    });

    // Derived: group labels
    const groupLabels: Record<string, string> = {
        P1: 'Language & Style', P2: 'Structure & Organization',
        P3: 'Content Quality', P4: 'Consistency',
        P5: 'Technical & Compliance', P6: 'Meta & Process',
    };

    onMount(async () => {
        try {
            aspects = await listAspects();
            tiers = await listTiers();
            // Default: auto-select must_review aspects for custom mode
            const mustTier = tiers.find(t => t.key === 'must_review');
            if (mustTier) mustTier.aspect_names.forEach(a => customAspects.add(a));
        } catch (e) {
            submitError = 'Failed to load aspects';
        }
    });

    // Document search (debounced)
    let searchTimer: ReturnType<typeof setTimeout>;
    function onSearchInput(e: Event) {
        const q = (e.target as HTMLInputElement).value;
        searchQuery = q;
        clearTimeout(searchTimer);
        if (q.length < 2) { docSearchResults = []; return; }
        searchTimer = setTimeout(async () => {
            isSearching = true;
            try {
                const res = await fetch(`/api/v1/kb/inputs?query=${encodeURIComponent(q)}&limit=10`, { credentials: 'same-origin' });
                const data = await res.json();
                docSearchResults = (data.inputs || data.records || data.data || []).map((r: any) => ({
                    id: r.id, title: r.title || r.file_name || `Document ${r.id}`,
                }));
            } catch { docSearchResults = []; }
            isSearching = false;
        }, 300);
    }

    function selectDoc(doc: {id: number; title: string}) {
        selectedDocId = doc.id;
        selectedDocTitle = doc.title;
        docSearchResults = [];
        searchQuery = doc.title;
        currentStep = 2;
    }

    function toggleAspect(name: string) {
        const next = new Set(customAspects);
        if (next.has(name)) next.delete(name); else next.add(name);
        customAspects = next;
    }

    function toggleGroup(group: string) {
        const next = new Set(expandedGroups);
        if (next.has(group)) next.delete(group); else next.add(group);
        expandedGroups = next;
    }

    async function handleSubmit() {
        if (!selectedDocId) { submitError = 'Please select a document'; return; }
        if (!requesterName.trim()) { submitError = 'Please enter your name'; currentStep = 5; return; }

        isSubmitting = true;
        submitError = '';
        try {
            const result = await submitRequest({
                input_record_id: selectedDocId,
                tier: selectedTier,
                aspects: effectiveAspects,
                reference_docs: referenceDocs.length > 0 ? referenceDocs : undefined,
                notes: notes || undefined,
                requester_name: requesterName,
                requester_id: 0, // TODO: resolve from auth context
            });
            submittedRequestId = result.request_id;
        } catch (e: any) {
            submitError = e.message || 'Submission failed';
        } finally {
            isSubmitting = false;
        }
    }

    // If submitted, show results
    if (submittedRequestId) {
        return <DocReviewResultsView {darkMode} requestId={submittedRequestId} />;
    }
</script>

<div style="padding: 1.5rem; color: {textPrimary};">
    <h1 style="font-size: 1.5rem; font-weight: 700; margin-bottom: 0.5rem;">Document Review</h1>
    <p style="color: {textSecondary}; margin-bottom: 2rem;">
        Submit a document for AI-powered review across quality, compliance, and technical aspects.
    </p>

    <!-- Step indicators -->
    <div style="display: flex; gap: 0.5rem; margin-bottom: 2rem; font-size: 0.8rem;">
        {#each ['Select Document', 'Check Level', 'Customize', 'References', 'Submit'] as step, i}
            <div style="display: flex; align-items: center; gap: 0.25rem;">
                <div style="width: 24px; height: 24px; border-radius: 50%; display: flex; align-items: center; justify-content: center;
                    background: {i + 1 <= currentStep ? accent : borderColor}; color: {i + 1 <= currentStep ? '#fff' : textMuted};
                    font-size: 0.75rem; font-weight: 600;">
                    {i + 1 <= (submittedRequestId ? 5 : currentStep) ? '✓' : i + 1}
                </div>
                <span style="color: {i + 1 === currentStep ? accent : textMuted}; white-space: nowrap;">{step}</span>
            </div>
        {/each}
    </div>

    <!-- Step 1: Document Search -->
    {#if currentStep === 1}
        <div style="background: {cardBg}; border: 1px solid {borderColor}; border-radius: 12px; padding: 1.5rem; margin-bottom: 1rem;">
            <h2 style="font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem;">Step 1: Select Document</h2>
            <div style="position: relative;">
                <div style="display: flex; align-items: center; background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; padding: 0.5rem 0.75rem;">
                    <SearchIcon size={16} style="color: {textMuted}; margin-right: 0.5rem;" />
                    <input type="text" placeholder="Search documents..."
                        value={searchQuery} oninput={onSearchInput}
                        style="flex: 1; background: transparent; border: none; outline: none; color: {textPrimary}; font-size: 0.9rem;" />
                    {#if isSearching}
                        <LoaderIcon size={14} style="color: {textMuted};" />
                    {/if}
                </div>
                {#if docSearchResults.length > 0}
                    <div style="position: absolute; top: 100%; left: 0; right: 0; background: {cardBg}; border: 1px solid {borderColor}; border-radius: 8px; margin-top: 4px; z-index: 10; max-height: 240px; overflow-y: auto;">
                        {#each docSearchResults as doc}
                            <button onclick={() => selectDoc(doc)}
                                style="display: block; width: 100%; text-align: left; padding: 0.75rem 1rem; background: transparent; border: none; color: {textPrimary}; cursor: pointer; font-size: 0.9rem;
                                border-bottom: 1px solid {borderColor};">
                                {doc.title}
                            </button>
                        {/each}
                    </div>
                {/if}
            </div>
            {#if selectedDocTitle}
                <div style="margin-top: 1rem; padding: 0.75rem; background: {accentTint}; border-radius: 8px; display: flex; align-items: center; gap: 0.5rem;">
                    <CheckIcon size={16} style="color: {accent};" />
                    <span style="color: {accent};">Selected: {selectedDocTitle}</span>
                </div>
            {/if}
        </div>
        <button onclick={() => selectedDocId && (currentStep = 2)}
            disabled={!selectedDocId}
            style="padding: 0.6rem 1.5rem; background: {selectedDocId ? accent : borderColor}; color: {selectedDocId ? '#fff' : textMuted}; border: none; border-radius: 8px; cursor: {selectedDocId ? 'pointer' : 'not-allowed'}; font-size: 0.9rem;">
            Next →
        </button>
    {/if}

    <!-- Step 2: Check Level -->
    {#if currentStep === 2}
        <div style="background: {cardBg}; border: 1px solid {borderColor}; border-radius: 12px; padding: 1.5rem; margin-bottom: 1rem;">
            <h2 style="font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem;">Step 2: Choose Check Level</h2>
            <div style="display: flex; flex-direction: column; gap: 0.75rem;">
                {#each tiers as tier}
                    <label style="display: flex; align-items: flex-start; gap: 0.75rem; padding: 1rem; background: {inputBg}; border: 2px solid {selectedTier === tier.key ? accent : borderColor}; border-radius: 8px; cursor: pointer;">
                        <input type="radio" name="tier" value={tier.key}
                            checked={selectedTier === tier.key}
                            onchange={() => selectedTier = tier.key}
                            style="margin-top: 0.2rem;" />
                        <div>
                            <div style="font-weight: 600; color: {textPrimary};">{tier.label}</div>
                            <div style="font-size: 0.85rem; color: {textSecondary};">{tier.description} — {tier.aspect_names.length} aspects</div>
                        </div>
                    </label>
                {/each}
            </div>
        </div>
        <div style="display: flex; gap: 0.5rem;">
            <button onclick={() => currentStep = 1}
                style="padding: 0.6rem 1.5rem; background: transparent; color: {textSecondary}; border: 1px solid {borderColor}; border-radius: 8px; cursor: pointer; font-size: 0.9rem;">← Back</button>
            <button onclick={() => currentStep = selectedTier === 'custom' ? 3 : 4}
                style="padding: 0.6rem 1.5rem; background: {accent}; color: #fff; border: none; border-radius: 8px; cursor: pointer; font-size: 0.9rem;">Next →</button>
        </div>
    {/if}

    <!-- Step 3: Customize Aspects -->
    {#if currentStep === 3}
        <div style="background: {cardBg}; border: 1px solid {borderColor}; border-radius: 12px; padding: 1.5rem; margin-bottom: 1rem;">
            <h2 style="font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem;">Step 3: Customize Aspects</h2>
            {#each Object.entries(aspectsByGroup) as [group, groupAspects]}
                <div style="margin-bottom: 0.75rem;">
                    <button onclick={() => toggleGroup(group)}
                        style="display: flex; align-items: center; gap: 0.5rem; width: 100%; text-align: left; padding: 0.6rem 0.75rem; background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; cursor: pointer; color: {textPrimary}; font-weight: 600; font-size: 0.9rem;">
                        {expandedGroups.has(group) ? <ChevronDownIcon size={16} /> : <ChevronRightIcon size={16} />}
                        {group} — {groupLabels[group] || group}
                        <span style="margin-left: auto; font-size: 0.8rem; color: {textMuted};">
                            {groupAspects.filter(a => customAspects.has(a.name)).length}/{groupAspects.length}
                        </span>
                    </button>
                    {#if expandedGroups.has(group)}
                        <div style="padding: 0.5rem 0 0 1.5rem; display: flex; flex-direction: column; gap: 0.25rem;">
                            {#each groupAspects as aspect}
                                <label style="display: flex; align-items: center; gap: 0.5rem; padding: 0.3rem 0.5rem; border-radius: 4px; cursor: pointer; font-size: 0.85rem; color: {textSecondary};">
                                    <input type="checkbox" checked={customAspects.has(aspect.name)} onchange={() => toggleAspect(aspect.name)} />
                                    {aspect.label}
                                </label>
                            {/each}
                        </div>
                    {/if}
                </div>
            {/each}
        </div>
        <div style="display: flex; gap: 0.5rem;">
            <button onclick={() => currentStep = 2}
                style="padding: 0.6rem 1.5rem; background: transparent; color: {textSecondary}; border: 1px solid {borderColor}; border-radius: 8px; cursor: pointer; font-size: 0.9rem;">← Back</button>
            <button onclick={() => currentStep = 4}
                disabled={customAspects.size === 0}
                style="padding: 0.6rem 1.5rem; background: {customAspects.size > 0 ? accent : borderColor}; color: {customAspects.size > 0 ? '#fff' : textMuted}; border: none; border-radius: 8px; cursor: {customAspects.size > 0 ? 'pointer' : 'not-allowed'}; font-size: 0.9rem;">Next →</button>
        </div>
    {/if}

    <!-- Step 4: Supporting Documents -->
    {#if currentStep === 4}
        <div style="background: {cardBg}; border: 1px solid {borderColor}; border-radius: 12px; padding: 1.5rem; margin-bottom: 1rem;">
            <h2 style="font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem;">Step 4: Supporting Documents <span style="font-weight: 400; color: {textMuted};">(optional)</span></h2>
            <p style="color: {textSecondary}; font-size: 0.85rem; margin-bottom: 1rem;">
                Add reference standards or supporting documents for compliance checking.
            </p>
            {#each referenceDocs as doc, i}
                <div style="display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem 0.75rem; background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; margin-bottom: 0.5rem;">
                    <span style="flex: 1; color: {textPrimary}; font-size: 0.9rem;">{doc.title}</span>
                    <button onclick={() => referenceDocs = referenceDocs.filter((_, idx) => idx !== i)}
                        style="background: none; border: none; color: {textMuted}; cursor: pointer;">
                        <XIcon size={14} />
                    </button>
                </div>
            {/each}
            <div style="display: flex; gap: 0.5rem;">
                <input type="text" placeholder="Reference document title or ID"
                    style="flex: 1; background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; padding: 0.5rem 0.75rem; color: {textPrimary}; font-size: 0.9rem;" />
                <button onclick={() => {/* TODO: add search for reference docs */}}
                    style="padding: 0.5rem 1rem; background: {accentTint}; color: {accent}; border: none; border-radius: 8px; cursor: pointer; font-size: 0.85rem;">Add</button>
            </div>
        </div>
        <div style="display: flex; gap: 0.5rem;">
            <button onclick={() => currentStep = selectedTier === 'custom' ? 3 : 2}
                style="padding: 0.6rem 1.5rem; background: transparent; color: {textSecondary}; border: 1px solid {borderColor}; border-radius: 8px; cursor: pointer; font-size: 0.9rem;">← Back</button>
            <button onclick={() => currentStep = 5}
                style="padding: 0.6rem 1.5rem; background: {accent}; color: #fff; border: none; border-radius: 8px; cursor: pointer; font-size: 0.9rem;">Next →</button>
        </div>
    {/if}

    <!-- Step 5: Notes & Submit -->
    {#if currentStep === 5}
        <div style="background: {cardBg}; border: 1px solid {borderColor}; border-radius: 12px; padding: 1.5rem; margin-bottom: 1rem;">
            <h2 style="font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem;">Step 5: Review Details</h2>
            <div style="margin-bottom: 1rem;">
                <label style="display: block; margin-bottom: 0.3rem; color: {textSecondary}; font-size: 0.85rem;">Your Name *</label>
                <input type="text" bind:value={requesterName} placeholder="Enter your name"
                    style="width: 100%; background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; padding: 0.5rem 0.75rem; color: {textPrimary}; font-size: 0.9rem;" />
            </div>
            <div style="margin-bottom: 1rem;">
                <label style="display: block; margin-bottom: 0.3rem; color: {textSecondary}; font-size: 0.85rem;">Notes (optional)</label>
                <textarea bind:value={notes} placeholder="e.g., Focus on sterilization validation sections..."
                    rows={4}
                    style="width: 100%; background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; padding: 0.5rem 0.75rem; color: {textPrimary}; font-size: 0.9rem; resize: vertical;"></textarea>
            </div>
            <div style="margin-bottom: 1rem;">
                <label style="display: block; margin-bottom: 0.3rem; color: {textSecondary}; font-size: 0.85rem;">Report Template (optional)</label>
                <input type="text" placeholder="Template name or path"
                    style="width: 100%; background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; padding: 0.5rem 0.75rem; color: {textPrimary}; font-size: 0.9rem;" />
            </div>
            <div style="margin-bottom: 1rem;">
                <label style="display: block; margin-bottom: 0.3rem; color: {textSecondary}; font-size: 0.85rem;">Doc Template (optional)</label>
                <input type="text" placeholder="Template name or path"
                    style="width: 100%; background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; padding: 0.5rem 0.75rem; color: {textPrimary}; font-size: 0.9rem;" />
            </div>
        </div>

        <!-- Review Summary -->
        <div style="background: {cardBg}; border: 1px solid {borderColor}; border-radius: 12px; padding: 1.5rem; margin-bottom: 1rem;">
            <h3 style="font-size: 1rem; font-weight: 600; margin-bottom: 0.75rem;">Review Summary</h3>
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; font-size: 0.85rem;">
                <div style="color: {textSecondary};">Document:</div>
                <div style="color: {textPrimary};">{selectedDocTitle}</div>
                <div style="color: {textSecondary};">Check Level:</div>
                <div style="color: {textPrimary};">{tiers.find(t => t.key === selectedTier)?.label || selectedTier}</div>
                <div style="color: {textSecondary};">Aspects:</div>
                <div style="color: {textPrimary};">{effectiveAspects.length} selected</div>
                <div style="color: {textSecondary};">Requester:</div>
                <div style="color: {textPrimary};">{requesterName}</div>
            </div>
        </div>

        {#if submitError}
            <div style="padding: 0.75rem; background: {errorBg}; border: 1px solid rgba(239,68,68,0.3); border-radius: 8px; color: #ef4444; margin-bottom: 1rem; font-size: 0.9rem;">
                {submitError}
            </div>
        {/if}

        <div style="display: flex; gap: 0.5rem;">
            <button onclick={() => currentStep = 4}
                disabled={isSubmitting}
                style="padding: 0.6rem 1.5rem; background: transparent; color: {textSecondary}; border: 1px solid {borderColor}; border-radius: 8px; cursor: pointer; font-size: 0.9rem;">← Back</button>
            <button onclick={handleSubmit}
                disabled={isSubmitting || !requesterName.trim()}
                style="flex: 1; padding: 0.75rem; background: {accent}; color: #fff; border: none; border-radius: 8px; cursor: pointer; font-size: 1rem; font-weight: 600; display: flex; align-items: center; justify-content: center; gap: 0.5rem;">
                {#if isSubmitting}
                    <LoaderIcon size={16} style="animation: spin 1s linear infinite;" />
                    Submitting...
                {:else}
                    Start Review
                {/if}
            </button>
        </div>
    {/if}
</div>

<style>
    @keyframes spin { to { transform: rotate(360deg); } }
</style>
```

---

### Task 10: Results View (progress polling, findings table, report)

**Files:**
- Create: `web/src/lib/components/home3/doc-review-results-view.svelte`

**Interfaces:**
- Consumes: `{ darkMode, requestId }` props, `docReviewService.ts` (Task 7)
- Produces: Rendered results page with findings table and report

- [ ] **Step 1: Write doc-review-results-view.svelte**

The results view handles three states:

1. **Loading / In Progress**: When `status === 'accepted'` or `'running'`, poll `getRequest()` every 3 seconds, show spinner with status.
2. **Completed**: Show summary cards (total findings by severity), findings table (filterable by pass/severity), and report view.
3. **Failed / Stopped**: Show error message.

```svelte
<script lang="ts">
    import { onMount, onDestroy } from 'svelte';
    import { getRequest, getReport, updateFinding, stopRequest } from '$lib/services/docReviewService';
    import type { RequestStatus, FindingItem } from '$lib/services/docReviewService';
    import LoaderIcon from '@lucide/svelte/icons/loader';
    import CheckIcon from '@lucide/svelte/icons/check';
    import XIcon from '@lucide/svelte/icons/x';
    import AlertCircleIcon from '@lucide/svelte/icons/alert-circle';
    import FileTextIcon from '@lucide/svelte/icons/file-text';
    import ChevronDownIcon from '@lucide/svelte/icons/chevron-down';
    import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';

    let { darkMode = true, requestId = 0 }: { darkMode: boolean; requestId: number } = $props();

    // Design tokens
    let cardBg = $derived(darkMode ? '#1F2333' : '#FFFFFF');
    let borderColor = $derived(darkMode ? '#2D3348' : '#E4E6EB');
    let accent = $derived(darkMode ? '#818CF8' : '#6366F1');
    let accentTint = $derived(darkMode ? 'rgba(129,140,248,0.15)' : 'rgba(99,102,241,0.10)');
    let textPrimary = $derived(darkMode ? '#E2E8F0' : '#111827');
    let textSecondary = $derived(darkMode ? '#94A3B8' : '#6B7280');
    let textMuted = $derived(darkMode ? '#64748B' : '#9CA3AF');
    let highBg = $derived(darkMode ? 'rgba(239,68,68,0.15)' : 'rgba(239,68,68,0.10)');
    let mediumBg = $derived(darkMode ? 'rgba(245,158,11,0.15)' : 'rgba(245,158,11,0.10)');
    let lowBg = $derived(darkMode ? 'rgba(34,197,94,0.15)' : 'rgba(34,197,94,0.10)');

    // State
    let request = $state<RequestStatus | null>(null);
    let findings = $state<FindingItem[]>([]);
    let reportData = $state<any>(null);
    let error = $state('');
    let filterPass = $state('');
    let filterSeverity = $state('');
    let expandedFindings = $state<Set<number>>(new Set());
    let activeTab = $state<'findings' | 'report'>('findings');
    let isStopping = $state(false);

    // Derived counts
    let highCount = $derived(findings.filter(f => f.severity === 'high').length);
    let mediumCount = $derived(findings.filter(f => f.severity === 'medium').length);
    let lowCount = $derived(findings.filter(f => f.severity === 'low').length);
    let pendingCount = $derived(findings.filter(f => f.review_status === 'pending').length);

    // Derived filtered findings
    let filteredFindings = $derived.by(() => {
        let result = findings;
        if (filterPass) result = result.filter(f => f.pass === filterPass);
        if (filterSeverity) result = result.filter(f => f.severity === filterSeverity);
        return result;
    });

    // Derived unique passes
    let passes = $derived([...new Set(findings.map(f => f.pass))].sort());

    // Polling
    let pollTimer: ReturnType<typeof setTimeout>;
    let isActive = $state(true);

    async function pollStatus() {
        if (!isActive) return;
        try {
            const result = await getRequest(requestId);
            request = result.request;
            findings = result.findings || [];

            if (request.status === 'completed' || request.status === 'failed' || request.status === 'stopped') {
                isActive = false;
                if (request.status === 'completed') {
                    // Load report
                    try {
                        const res = await fetch(`/api/v1/doc-review/reports?request_id=${requestId}`, { credentials: 'same-origin' });
                        const data = await res.json();
                        // Alternative: we don't have a "by request" report endpoint, so load the latest
                    } catch {}
                }
            }
        } catch (e: any) {
            error = e.message;
            isActive = false;
        }
    }

    let intervalId: ReturnType<typeof setInterval>;
    onMount(async () => {
        await pollStatus();
        if (isActive) {
            intervalId = setInterval(pollStatus, 3000);
        }
    });

    onDestroy(() => {
        clearInterval(intervalId);
    });

    async function handleAcceptReject(findingId: number, status: string) {
        try {
            await updateFinding(findingId, status);
            findings = findings.map(f => f.id === findingId ? { ...f, review_status: status } : f);
        } catch (e: any) {
            error = e.message;
        }
    }

    async function handleStop() {
        isStopping = true;
        try {
            await stopRequest(requestId);
            await pollStatus();
        } catch (e: any) {
            error = e.message;
        }
        isStopping = false;
    }

    function toggleFinding(id: number) {
        const next = new Set(expandedFindings);
        if (next.has(id)) next.delete(id); else next.add(id);
        expandedFindings = next;
    }

    // Loading state
    if (!request) {
        return <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 4rem 2rem; color: {textSecondary};">
            <LoaderIcon size={32} style="animation: spin 1s linear infinite; margin-bottom: 1rem;" />
            <div>Loading review request...</div>
        </div>;
    }

    // Running state
    if (request.status === 'accepted' || request.status === 'running') {
        return <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 4rem 2rem;">
            <LoaderIcon size={48} style="animation: spin 1s linear infinite; color: {accent}; margin-bottom: 1rem;" />
            <h2 style="color: {textPrimary}; font-size: 1.25rem; margin-bottom: 0.5rem;">Review In Progress</h2>
            <p style="color: {textSecondary}; margin-bottom: 1rem;">
                Status: <strong>{request.status}</strong>
            </p>
            <button onclick={handleStop} disabled={isStopping}
                style="padding: 0.5rem 1rem; background: rgba(239,68,68,0.15); color: #ef4444; border: 1px solid rgba(239,68,68,0.3); border-radius: 8px; cursor: pointer;">
                {isStopping ? 'Stopping...' : 'Stop Review'}
            </button>
        </div>;
    }

    // Failed state
    if (request.status === 'failed') {
        return <div style="padding: 2rem;">
            <div style="background: rgba(239,68,68,0.1); border: 1px solid rgba(239,68,68,0.3); border-radius: 12px; padding: 2rem; text-align: center;">
                <AlertCircleIcon size={48} style="color: #ef4444; margin-bottom: 1rem;" />
                <h2 style="color: {textPrimary}; font-size: 1.25rem; margin-bottom: 0.5rem;">Review Failed</h2>
                <p style="color: {textSecondary}; margin-bottom: 0.5rem;">{request.error_message}</p>
            </div>
        </div>;
    }

    // Stopped state
    if (request.status === 'stopped') {
        return <div style="padding: 2rem;">
            <div style="background: rgba(245,158,11,0.1); border: 1px solid rgba(245,158,11,0.3); border-radius: 12px; padding: 2rem; text-align: center;">
                <XIcon size={48} style="color: #f59e0b; margin-bottom: 1rem;" />
                <h2 style="color: {textPrimary}; font-size: 1.25rem; margin-bottom: 0.5rem;">Review Stopped</h2>
                <p style="color: {textSecondary};">The review was cancelled before completion.</p>
            </div>
        </div>;
    }

    // Completed state
    return <div style="padding: 1.5rem;">
        <!-- Header -->
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
            <div>
                <h1 style="font-size: 1.5rem; font-weight: 700; color: {textPrimary};">Review Results</h1>
                <p style="color: {textSecondary}; font-size: 0.85rem;">{findings.length} findings · {request.tier}</p>
            </div>
            <div style="display: flex; gap: 0.5rem;">
                <button onclick={() => activeTab = 'findings'}
                    style="padding: 0.4rem 1rem; background: {activeTab === 'findings' ? accentTint : 'transparent'}; color: {activeTab === 'findings' ? accent : textSecondary}; border: 1px solid {borderColor}; border-radius: 8px; cursor: pointer; font-size: 0.85rem;">Findings</button>
                <button onclick={() => activeTab = 'report'}
                    style="padding: 0.4rem 1rem; background: {activeTab === 'report' ? accentTint : 'transparent'}; color: {activeTab === 'report' ? accent : textSecondary}; border: 1px solid {borderColor}; border-radius: 8px; cursor: pointer; font-size: 0.85rem;">Report</button>
            </div>
        </div>

        <!-- Summary Cards -->
        <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; margin-bottom: 1.5rem;">
            <div style="background: {cardBg}; border: 1px solid {borderColor}; border-radius: 12px; padding: 1rem; text-align: center;">
                <div style="font-size: 2rem; font-weight: 700; color: {textPrimary};">{findings.length}</div>
                <div style="font-size: 0.8rem; color: {textMuted};">Total Findings</div>
            </div>
            <div style="background: {cardBg}; border: 1px solid rgba(239,68,68,0.3); border-radius: 12px; padding: 1rem; text-align: center;">
                <div style="font-size: 2rem; font-weight: 700; color: #ef4444;">{highCount}</div>
                <div style="font-size: 0.8rem; color: #ef4444;">High Severity</div>
            </div>
            <div style="background: {cardBg}; border: 1px solid rgba(245,158,11,0.3); border-radius: 12px; padding: 1rem; text-align: center;">
                <div style="font-size: 2rem; font-weight: 700; color: #f59e0b;">{mediumCount}</div>
                <div style="font-size: 0.8rem; color: #f59e0b;">Medium Severity</div>
            </div>
            <div style="background: {cardBg}; border: 1px solid rgba(34,197,94,0.3); border-radius: 12px; padding: 1rem; text-align: center;">
                <div style="font-size: 2rem; font-weight: 700; color: #22c55e;">{lowCount}</div>
                <div style="font-size: 0.8rem; color: #22c55e;">Low Severity</div>
            </div>
        </div>

        <!-- Findings Tab -->
        {#if activeTab === 'findings'}
            <!-- Filters -->
            <div style="display: flex; gap: 0.5rem; margin-bottom: 1rem;">
                <select bind:value={filterPass} style="background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; padding: 0.4rem 0.75rem; color: {textPrimary}; font-size: 0.85rem;">
                    <option value="">All Passes</option>
                    {#each passes as p}
                        <option value={p}>{p}</option>
                    {/each}
                </select>
                <select bind:value={filterSeverity} style="background: {inputBg}; border: 1px solid {borderColor}; border-radius: 8px; padding: 0.4rem 0.75rem; color: {textPrimary}; font-size: 0.85rem;">
                    <option value="">All Severities</option>
                    <option value="high">High</option>
                    <option value="medium">Medium</option>
                    <option value="low">Low</option>
                </select>
                <span style="margin-left: auto; color: {textMuted}; font-size: 0.85rem; align-self: center;">
                    {filteredFindings.length} of {findings.length} · {pendingCount} pending review
                </span>
            </div>

            <!-- Findings List -->
            <div style="display: flex; flex-direction: column; gap: 0.5rem;">
                {#each filteredFindings as finding (finding.id)}
                    <div style="background: {cardBg}; border: 1px solid {borderColor}; border-radius: 8px; overflow: hidden;">
                        <button onclick={() => toggleFinding(finding.id)}
                            style="display: flex; align-items: center; gap: 0.75rem; width: 100%; text-align: left; padding: 0.75rem 1rem; background: transparent; border: none; cursor: pointer; color: {textPrimary};">
                            <div style="width: 4px; height: 32px; border-radius: 2px;
                                background: {finding.severity === 'high' ? '#ef4444' : finding.severity === 'medium' ? '#f59e0b' : '#22c55e'};">
                            </div>
                            <div style="flex: 1; min-width: 0;">
                                <div style="font-weight: 600; font-size: 0.9rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">
                                    {finding.title}
                                </div>
                                <div style="display: flex; gap: 0.5rem; font-size: 0.75rem; color: {textMuted};">
                                    <span>{finding.pass} · {finding.aspect}</span>
                                    <span style="text-transform: capitalize;">{finding.finding_type.replace(/_/g, ' ')}</span>
                                </div>
                            </div>
                            <div style="display: flex; gap: 0.25rem; align-items: center;">
                                {#if finding.review_status === 'pending'}
                                    <button onclick|stopPropagation={() => handleAcceptReject(finding.id, 'accepted')}
                                        style="padding: 0.25rem 0.5rem; background: {successBg}; color: #22c55e; border: none; border-radius: 4px; cursor: pointer; font-size: 0.75rem;">Accept</button>
                                    <button onclick|stopPropagation={() => handleAcceptReject(finding.id, 'rejected')}
                                        style="padding: 0.25rem 0.5rem; background: rgba(239,68,68,0.1); color: #ef4444; border: none; border-radius: 4px; cursor: pointer; font-size: 0.75rem;">Reject</button>
                                {:else}
                                    <span style="font-size: 0.75rem; color: {textMuted}; text-transform: capitalize;">{finding.review_status}</span>
                                {/if}
                            </div>
                            {expandedFindings.has(finding.id) ? <ChevronDownIcon size={16} style="color: {textMuted};" /> : <ChevronRightIcon size={16} style="color: {textMuted};" />}
                        </button>
                        {#if expandedFindings.has(finding.id)}
                            <div style="padding: 0 1rem 0.75rem; border-top: 1px solid {borderColor};">
                                <p style="color: {textSecondary}; font-size: 0.85rem; margin-top: 0.5rem;">{finding.description}</p>
                                {#if finding.evidence}
                                    <div style="margin-top: 0.5rem; padding: 0.5rem; background: {inputBg}; border-radius: 6px; font-size: 0.8rem; color: {textMuted}; font-family: monospace;">
                                        {finding.evidence}
                                    </div>
                                {/if}
                                {#if finding.suggestion}
                                    <p style="margin-top: 0.5rem; color: {accent}; font-size: 0.85rem;"><strong>Suggestion:</strong> {finding.suggestion}</p>
                                {/if}
                                {#if finding.location}
                                    <p style="margin-top: 0.25rem; color: {textMuted}; font-size: 0.8rem;">Location: {finding.location}</p>
                                {/if}
                                <p style="margin-top: 0.25rem; color: {textMuted}; font-size: 0.75rem;">Confidence: {Math.round(finding.confidence * 100)}%</p>
                            </div>
                        {/if}
                    </div>
                {/each}
                {#if filteredFindings.length === 0}
                    <div style="padding: 2rem; text-align: center; color: {textMuted}; background: {cardBg}; border: 1px solid {borderColor}; border-radius: 8px;">
                        No findings match the current filters.
                    </div>
                {/if}
            </div>
        {/if}

        <!-- Report Tab -->
        {#if activeTab === 'report'}
            <div style="background: {cardBg}; border: 1px solid {borderColor}; border-radius: 12px; padding: 1.5rem; color: {textPrimary};">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                    <h2 style="font-size: 1.1rem; font-weight: 600;">Full Report</h2>
                    <a href={`/api/v1/doc-review/reports/${requestId}/export?format=md`} target="_blank"
                        style="padding: 0.4rem 0.75rem; background: {accent}; color: #fff; border-radius: 6px; text-decoration: none; font-size: 0.85rem;">
                        Export Markdown
                    </a>
                </div>
                <p style="color: {textSecondary}; margin-bottom: 1rem;">
                    Total: {findings.length} findings · {highCount} high · {mediumCount} medium · {lowCount} low
                </p>
                {#each passes as pass}
                    <div style="margin-bottom: 1rem;">
                        <h3 style="font-weight: 600; color: {accent}; margin-bottom: 0.5rem; font-size: 0.95rem;">{pass}</h3>
                        {#each findings.filter(f => f.pass === pass).slice(0, 5) as finding}
                            <div style="padding: 0.5rem 0.75rem; border-left: 2px solid {borderColor}; margin-bottom: 0.25rem; font-size: 0.85rem;">
                                <span style="color: {finding.severity === 'high' ? '#ef4444' : finding.severity === 'medium' ? '#f59e0b' : '#22c55e'}; font-weight: 600;">{finding.severity.toUpperCase()}</span>
                                {' '}{finding.title}
                            </div>
                        {/each}
                    </div>
                {/each}
                <div style="text-align: center; margin-top: 1rem;">
                    <a href={`/api/v1/doc-review/reports/${requestId}`} target="_blank"
                        style="color: {accent}; font-size: 0.85rem;">View Full Report JSON →</a>
                </div>
            </div>
        {/if}
    </div>;
</script>

<style>
    @keyframes spin { to { transform: rotate(360deg); } }
</style>
```

---

## Tasks Summary

| Task | Files | Key Dependencies |
|------|-------|------------------|
| 1 | `project_migrations/*.sql` | None |
| 2 | `server/api/docreview/{models,aspects}.go` | None |
| 3 | `server/api/docreview/controller.go` | Task 2 |
| 4 | `server/api/docreview/report.go` | Task 2 |
| 5 | `server/api/docreviewhandler/handler.go` | Tasks 3, 4 |
| 6 | `server/api/routes.go` | Task 5 |
| 7 | `web/src/lib/services/docReviewService.ts` | Task 6 (needs endpoints to exist) |
| 8 | `web/src/lib/components/home3/{nav-rail,content-panel}.svelte` | None |
| 9 | `web/src/lib/components/home3/document-review-view.svelte` | Task 7 |
| 10 | `web/src/lib/components/home3/doc-review-results-view.svelte` | Task 7 |

Tasks can be parallelized: 1→(2→3→4→5→6) and 8 are independent of 7→9→10. Tasks 1 and 8 are independent of everything.
