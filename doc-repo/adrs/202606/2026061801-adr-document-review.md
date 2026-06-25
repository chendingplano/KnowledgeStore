# ADR 2026061801 — Document Review: LLM-Powered Multi-Aspect Review Pipeline

**Date:** 2026-06-18 \
**Status:** Proposal \
**Component:** ChenWeb, Doc Processor — document_review \
**Authors:** Chen Ding \
**Tags:** doc processor, document review, compliance, quality assurance

---

## Change Logs
* 2026/06/18, ADR Created.
* 2026/06/21, Added the Review Service Layer (DR11–DR13): `DocReviewController`,
  `DocReviewReportGenerator`, and the Review Request GUI; added
  `kb.doc_review_requests` and `kb.doc_review_reports`; added the staged plan
  (Phase VI). Recorded that the original skill proposal (spec 2026061101) is
  superseded by this ADR.
* **2026/06/21, DR13 implemented full-stack.** Backend: `kb.doc_review_requests`
  and `kb.doc_review_reports` tables (goose migrations), `DocReviewController`
  (service layer with request lifecycle state machine), `DocReviewReportGenerator`
  (JSON + Markdown + HTML report builder), 9 API endpoints via Echo v4 handler
  package. Frontend: 5-step review request form (`document-review-view.svelte`),
  results view with polling, findings table, accept/reject, and report view
  (`doc-review-results-view.svelte`), integrated into home3 layout under
  Apps → Document Review. See implementation plan at
  `docs/superpowers/plans/2026-06-21-doc-review-gui-plan.md`.
* 2026/06/21, **DR14 (configurable review tiers)** — review tiers and their aspect
  membership are configurable via a `[doc-reviews]` table in
  `config.toml` / `config.local.toml`; falls back to priority-derived tiers when
  absent. Implemented. See spec 2026062104 §DR14.
* 2026/06/21, **DR15 (per-aspect review status + live job monitor)** — added below.
  New `kb.doc_review_status` table (one row per `(review_run_id, aspect)`),
  `review_run_id` assigned at accept time, and a global live monitor
  (`GET /api/v1/doc-review/active`) listing every job with ≥1 unfinished aspect.
* **2026/06/22, DR15 implemented.** `kb.doc_review_status` migration; status seeding
  at accept; coarse controller-driven per-aspect transitions; **async** review
  execution (background goroutine) so the monitor observes in-flight jobs;
  `GET /api/v1/doc-review/active`; global `doc-review-monitor.svelte` polling it.
  Design 2026062105 §3.3/§4.4/§6/§7.2.
* **2026/06/23, DR3 config loading wired.** `doc-review.local.toml` with
  `[packages.P1..P6]` group defaults and `[reviewers.<aspect>]` per-aspect blocks
  (all ~40 aspects configured). Config loaded at startup via
  `GetDocReviewConfig()` (walks up from CWD; cached via `sync.Once`).
  `ReviewerConfig` is resolved by merging group defaults → per-aspect overrides.
  `NewReviewProcessor` reads config exclusively from the TOML file; if no model
  name or prompt is specified in the configuration, `NewReviewProcessor` treats
  it as an error and disables the reviewer. Refactored `loadPromptByRef` and
  `loadModelConfigByRef`
  out of the env-based loaders so both paths share resolution logic.
  **Scope:** Phase I — only `grammar_spelling` reviewer is wired to execution;
  other per-aspect blocks are forward-looking config. Per-review-run TOML and
  `reference_docs` remain out of scope. Code in `review-config.go` and
  `review-document.go` (relocated 2026/06/23 to `server/api/doc-reviews`; see the
  relocation note below).
* **2026/06/23, `formatting_consistency` reviewer wired (P1).** Third P1 reviewer
  after `grammar_spelling` and `tone_voice`. `StrategyChunk`, one-shot, cheap model
  (`deepseek-v4-flash`), 200-line windows (wider context to compare formatting of the
  same construct across sections). Findings default to `pass=P1`,
  `aspect=formatting_consistency`, `finding_type=inconsistency`. Resolved from
  `[reviewers.formatting_consistency]` via `GetDocReviewConfig()`/`ResolveReviewer`;
  disabled if prompt/model unset. Code in `review-formatting-consistency.go`
  (+ wiring in `review-document.go`); prompt
  `prompts/prompt-review-formatting-consistency.md`.
* **2026/06/23, reviewer framework relocated to `server/api/doc-reviews`.** Per the
  ADR's "Implementation Files" directive, all `review-*` files (the `ReviewProcessor`
  framework, `review-config.go`, and the `grammar_spelling` / `tone_voice` /
  `formatting_consistency` reviewers) moved from `server/api/doc-processing`
  (package `docprocessing`) into `server/api/doc-reviews` (package `docreviews`),
  joining the DR11–DR16 service layer. Rationale: with ~40 reviewers planned,
  keeping them out of the already-large `doc-processing` package keeps both
  organized. The reviewers still reuse `doc-processing`'s line-file / LLM / config /
  concurrency helpers via a thin exported shim (`doc-processing/review_exports.go`,
  e.g. `BuildReviewerLLMClient`, `RunReviewConcurrent`, `NewLLMJSONInput`) bound to
  local names in `doc-reviews/review_framework_aliases.go`. No import cycle: nothing
  in `doc-processing` references the reviewer framework. `controller.go` now
  constructs `NewReviewProcessor` / `ReviewFindingsSQLStore` locally.
* **2026/06/23, `readability` reviewer wired (P1).** Fourth P1 reviewer after
  `grammar_spelling`, `tone_voice`, and `formatting_consistency`. `StrategyChunk`,
  one-shot, cheap model (`deepseek-v4-flash`), 200-line windows (wider context to
  judge paragraph length and sentence flow across a passage). Checks overlong/complex
  sentences, dense paragraphs, passive-voice/nominalization overuse, and undefined
  jargon — judged relative to the audience inferred from `doc_context`. Findings
  default to `pass=P1`, `aspect=readability`, `finding_type=readability`. Resolved
  from `[reviewers.readability]` via `GetDocReviewConfig()`/`ResolveReviewer`;
  disabled if prompt/model unset. Code in `review-readability.go` (+ wiring in
  `review-document.go`); prompt `prompts/prompt-review-readability.md`.
* **2026/06/23, `localization` reviewer wired (P1).** Fifth P1 reviewer after
  `grammar_spelling`, `tone_voice`, `formatting_consistency`, and `readability`.
  `StrategyChunk`, one-shot, cheap model (`deepseek-v4-flash`), 200-line windows
  (wider context to catch inconsistent date/number/unit conventions used for the
  same construct across a passage). Checks locale-inconsistent date/number/currency
  formats, measurement-unit mismatch, untranslated/mixed-language fragments,
  untranslatable idioms, culture-specific references, hard-coded locale assumptions,
  and encoding/typography issues — judged relative to the target locale inferred
  from `doc_context`. Findings default to `pass=P1`, `aspect=localization`,
  `finding_type=localization`. Resolved from `[reviewers.localization]` via
  `GetDocReviewConfig()`/`ResolveReviewer`; disabled if prompt/model unset. Code in
  `review-localization.go` (+ wiring in `review-document.go`); prompt
  `prompts/prompt-review-localization.md`.
* **2026/06/24, DR16 (finding actions on the report page) implemented.** Added per-finding
  **LLM Auto Fix**, **Edit Tool** (find/replace dialog), **Delete**, and **Accept** actions,
  plus a conditional **Regenerate PDF** button, to the Document Review Report page. Auto Fix
  (model from `AUTO_FIX_MODEL_NAME`, fallback `AUTO_FIX_CALLBACK`) and Edit Tool mutate the
  document's extracted **line-file** in place; Delete/Accept set `review_status`
  (`deleted`/`accepted` — set extended with `deleted`+`fixed`); Regenerate rebuilds the
  report JSON/markdown + Typst PDF into the same report row. Backend:
  `server/api/doc-reviews/auto_fix.go` (line-file editor, LLM auto-fix, edit-save, report
  regeneration), handlers in `handler.go`, 4 routes in `routes.go`. Frontend:
  `edit-tool-dialog.svelte`, report-page wiring, and service functions in
  `docReviewService.ts`. The Edit Tool dialog shows the finding's suggestion in
  auto-sizing multi-line fields and, for `…例如：'<content>'`-style suggestions, splits
  off the quoted proposed content behind an in-dialog **Accept** button (DR16a). The
  report page groups findings into collapsible package → reviewer sections with a
  per-reviewer local scrollbar. See DR16 below.
* **2026/06/24, DR19 (report page action bar) implemented.** The 'Correction Report'
  and 'Regenerate PDF' buttons were relocated from the `title-row` header to the
  `show-mode-bar` next to 'Show Active' / 'Show All', renamed 'Generate Change Report'
  and 'Re-Generate Review Report' respectively. 'Re-Generate Review Report' is now always
  visible (previously shown only when `dirty`). A thin separator divides view-mode toggles
  from action buttons. Frontend-only change:
  `web/src/routes/home3/doc-review-report/[id]/+page.svelte`.
* **2026/06/24, DR17 (correction activity log + Correction Report) implemented.** Every
  reviewer correction action is now recorded in a new `kb.doc_review_activities` table:
  **LLM Auto Fix**, **Edit Tool** save, finding **Delete**, and the three **Document
  Structure** edits (modify / split / delete). A new leaf package
  `server/api/docactivity` (`Log` + `List`, depends only on `database/sql` +
  `loggerutil`) lets both the doc-reviews controller and the kbhandler doc-structure
  handlers log without an import cycle; logging is best-effort (never breaks the user's
  action). A new **Document Review Correction Report** (`GenerateCorrectionReport`,
  `server/api/doc-reviews/correction_report.go`) renders those activities into a Typst
  source and compiles it to PDF — mirroring `GenerateTypstReport` (output to
  `$DOC_REVIEW_REPORTS` as `<stamp>-<reportID>-corrections.{typ,pdf}`), via
  `POST /api/v1/doc-review/reports/<id>/correction-report` and a **Correction Report**
  button on the report page. Migration
  `project_migrations/20260624000001_create_doc_review_activities.sql`; template
  `docs/doc-templates/template-correction-report.typ`
  (`$DOC_REVIEW_CORRECTION_TEMPLATE_FILENAME`). See DR17 below.
* **2026/06/24, `logical_flow` reviewer wired (P2).** First P2 (Structure & Organization)
  reviewer and the first `StrategyDocument` reviewer. Unlike the P1 chunk reviewers, it
  reasons across the whole document: out-of-order content, undefined prerequisites, abrupt
  transitions/non-sequiturs, missing logical steps, circular reasoning, contradictory
  ordering, and orphaned content — judged relative to the document type inferred from
  `doc_context`. Document-level, one-shot, cheap model (`deepseek-v4-flash`); large
  documents are split into page-aligned blocks of up to `DefaultInputBlockSize` (20) pages
  via `buildPageBlocks` (ADR DR2) and reviewed concurrently. Findings default to `pass=P2`,
  `aspect=logical_flow`, `finding_type=logical_flow`. Resolved from `[reviewers.logical_flow]`
  via `GetDocReviewConfig()`/`ResolveReviewer`; disabled if prompt/model unset. Code in
  `server/api/doc-reviews/review-logical-flow.go` (+ wiring in `review-document.go`); prompt
  `prompts/prompt-review-logical-flow.md`.
* **2026/06/24, `heading_hierarchy` reviewer wired (P2).** Second P2 (Structure &
  Organization) reviewer after `logical_flow`, and the second `StrategyDocument` reviewer.
  Like `logical_flow` it reasons across the whole document rather than a single passage:
  skipped heading levels, inconsistent/out-of-sequence numbering, level/style mismatches
  between sibling headings, empty/orphaned sections, phrasing (non-parallel) inconsistency,
  and misordered hierarchy — judged relative to the heading convention inferred from
  `doc_context`. Document-level, one-shot, cheap model (`deepseek-v4-flash`); large documents
  are split into page-aligned blocks of up to `DefaultInputBlockSize` (20) pages via
  `buildPageBlocks` (ADR DR2) and reviewed concurrently, with the prompt instructing the model
  to lower confidence at block boundaries (a parent/sibling heading may fall in an unseen
  block). Findings default to `pass=P2`, `aspect=heading_hierarchy`,
  `finding_type=heading_hierarchy`. Resolved from `[reviewers.heading_hierarchy]` via
  `GetDocReviewConfig()`/`ResolveReviewer`; disabled if prompt/model unset. Code in
  `server/api/doc-reviews/review-heading-hierarchy.go` (+ wiring in `review-document.go`);
  prompt `prompts/prompt-review-heading-hierarchy.md`.
* **2026/06/24, `navigability` reviewer wired (P2).** Third P2 (Structure & Organization)
  reviewer after `logical_flow` and `heading_hierarchy`, and the third `StrategyDocument`
  reviewer. Like the other P2 reviewers it reasons across the whole document rather than a
  single passage, but its concern is **findability**: broken cross-references (a "see
  Appendix C" with no such appendix), vague cross-references ("see above"/"described below"),
  missing navigational aids (no TOC/index/signposting a document of its type warrants),
  non-descriptive section titles, missing signposting in long sections, and inconsistent
  reference style — judged relative to the document type inferred from `doc_context`.
  Document-level, one-shot, cheap model (`deepseek-v4-flash`); large documents are split into
  page-aligned blocks of up to `DefaultInputBlockSize` (20) pages via `buildPageBlocks`
  (ADR DR2) and reviewed concurrently, with the prompt instructing the model to lower
  confidence when a cross-reference target may fall in an unseen block. Findings default to
  `pass=P2`, `aspect=navigability`, `finding_type=navigability`. Resolved from
  `[reviewers.navigability]` via `GetDocReviewConfig()`/`ResolveReviewer`; disabled if
  prompt/model unset. Code in `server/api/doc-reviews/review-navigability.go` (+ wiring in
  `review-document.go`); prompt `prompts/prompt-review-navigability.md`.
* **2026/06/24, `section_balance` reviewer wired (P2).** Fourth P2 (Structure &
  Organization) reviewer after `logical_flow`, `heading_hierarchy`, and `navigability`,
  and the fourth `StrategyDocument` reviewer. Like the other P2 reviewers it reasons
  across the whole document rather than a single passage, but its concern is
  **proportion**: stub sections (a heading with little/no substantive content), bloated
  sections, imbalanced sibling sections, disproportionate subsection nesting, and a
  front/back-loaded structure whose emphasis does not match the document's purpose —
  judged relative to the document type inferred from `doc_context`. Document-level,
  one-shot, cheap model (`deepseek-v4-flash`); large documents are split into
  page-aligned blocks of up to `DefaultInputBlockSize` (20) pages via `buildPageBlocks`
  (ADR DR2) and reviewed concurrently, with the prompt instructing the model to lower
  confidence when a section may continue into an unseen block. Findings default to
  `pass=P2`, `aspect=section_balance`, `finding_type=section_balance`. Resolved from
  `[reviewers.section_balance]` via `GetDocReviewConfig()`/`ResolveReviewer`; disabled if
  prompt/model unset. Code in `server/api/doc-reviews/review-section-balance.go` (+ wiring
  in `review-document.go`); prompt `prompts/prompt-review-section-balance.md`.
* **2026/06/24, `modularity` reviewer wired (P2).** Fifth P2 (Structure & Organization)
  reviewer after `logical_flow`, `heading_hierarchy`, `navigability`, and `section_balance`,
  and the fifth `StrategyDocument` reviewer. Like the other P2 reviewers it reasons across
  the whole document rather than a single passage, but its concern is **self-containment and
  reuse**: duplicated content (the same material restated in several places, free to drift),
  poor separation of concerns (sections that bleed into each other), hidden coupling (a
  section that cannot stand on its own because it silently depends on context defined far
  away), un-factored shared material that belongs in a glossary/appendix, and content welded
  to one narrow context that the document type would expect to be reusable — judged relative
  to the document type inferred from `doc_context`. Document-level, one-shot, cheap model
  (`deepseek-v4-flash`); large documents are split into page-aligned blocks of up to
  `DefaultInputBlockSize` (20) pages via `buildPageBlocks` (ADR DR2) and reviewed
  concurrently, with the prompt instructing the model to lower confidence when a duplicate or
  a shared definition may fall in an unseen block. Findings default to `pass=P2`,
  `aspect=modularity`, `finding_type=modularity`. Resolved from `[reviewers.modularity]` via
  `GetDocReviewConfig()`/`ResolveReviewer`; disabled if prompt/model unset. Code in
  `server/api/doc-reviews/review-modularity.go` (+ wiring in `review-document.go`); prompt
  `prompts/prompt-review-modularity.md`.
* **2026/06/25, `completeness` reviewer wired (P3).** First P3 (Content Quality) reviewer.
  `StrategyChunk` (per-chunk, like the P1 reviewers), one-shot, cheap model
  (`deepseek-v4-flash`), 200-line windows (wider context to judge whether a section's
  promised content is delivered within the passage). Detects missing expected
  topics/sections for the document type (DR6c — implicit expectation injection via
  `doc_context`), incomplete/stub sections, missing detail (values/units/thresholds/roles),
  placeholders (TODO/TBD/`[…]`), dangling references whose target is promised but absent,
  unfinished/truncated passages, and asymmetric coverage. **Scope:** Phase I one-shot only —
  the cross-document roster comparison against reference standards (DR6a/DR6b) and the
  tool-use investigation loop (DR10) remain Phase II+. Findings default to `pass=P3`,
  `aspect=completeness`, `finding_type=incompleteness`, `severity=medium`. Resolved from
  `[reviewers.completeness]` via `GetDocReviewConfig()`/`ResolveReviewer`; disabled if
  prompt/model unset. Code in `server/api/doc-reviews/review-completeness.go` (+ wiring in
  `review-document.go`); prompt `prompts/prompt-review-completeness.md`.
* **2026/06/25, `relevance` reviewer wired (P3).** Fifth P3 (Content Quality) reviewer
  after `completeness`, `correctness`, `clarity`, and `conciseness`. `StrategyChunk`, one-shot,
  cheap model (`deepseek-v4-flash`), 200-line windows (wide enough to spot an off-topic subsection
  across a passage while remaining tractable for one-shot processing). Detects off-topic sections,
  tangential digressions, wrong-document content reproduced in full, scope creep beyond the
  document's declared boundary, and orphaned boilerplate — judged relative to the document type
  and stated purpose inferred from `doc_context`. Findings default to `pass=P3`,
  `aspect=relevance`, `finding_type=irrelevance`, `severity=low`. Enabled in
  `doc-review.local.toml` (`[reviewers.relevance]`). Code in
  `server/api/doc-reviews/review-relevance.go` (+ wiring in `review-document.go`); prompt
  `prompts/prompt-review-relevance.md`.
* **2026/06/25, `conciseness` reviewer wired (P3).** Fourth P3 (Content Quality) reviewer
  after `completeness`, `correctness`, and `clarity`. `StrategyChunk`, one-shot, cheap model
  (`deepseek-v4-flash`), 200-line windows (wide enough to catch repeated caveats and restated
  content across a passage). Detects redundant phrases ("in order to", "due to the fact that"),
  tautologies ("end result", "past history"), padding openers ("It is important to note that"),
  excessive hedging where the document type demands directness, avoidable nominalizations
  ("make a decision" → "decide"), and content repetition — judged relative to the document
  type inferred from `doc_context`. Findings default to `pass=P3`, `aspect=conciseness`,
  `finding_type=verbosity`, `severity=low`. Enabled in `doc-review.local.toml`
  (`[reviewers.conciseness]`). Code in `server/api/doc-reviews/review-conciseness.go`
  (+ wiring in `review-document.go`); prompt `prompts/prompt-review-conciseness.md`.
* **2026/06/25, `correctness` reviewer wired (P3).** Second P3 (Content Quality) reviewer
  after `completeness`. `StrategyChunk` (per-chunk, like `completeness` and the P1 reviewers),
  one-shot, cheap model (`deepseek-v4-flash`), 200-line windows (wider context so a value or
  claim that contradicts another statement made earlier in the same passage can be caught).
  Detects internal contradictions, incorrect values/units, broken calculations, factual errors,
  misstated definitions/references, and logical falsehoods — judged relative to the document
  type/domain inferred from `doc_context`. It is the complement of `completeness`: completeness
  flags what is *missing*, correctness flags whether what is *present* is *right*. **Scope:**
  Phase I one-shot only — errors provable from the passage itself (contradictions, arithmetic,
  out-of-range values) are high-confidence; claims needing external ground truth are reported at
  low confidence. The cross-document verification against reference standards (DR4/DR6) and the
  tool-use investigation loop (DR10) remain Phase II+. Findings default to `pass=P3`,
  `aspect=correctness`, `finding_type=incorrectness`, `severity=medium`. Resolved from
  `[reviewers.correctness]` via `GetDocReviewConfig()`/`ResolveReviewer`; disabled if
  prompt/model unset. Code in `server/api/doc-reviews/review-correctness.go` (+ wiring in
  `review-document.go`); prompt `prompts/prompt-review-correctness.md`.
* **2026/06/25, `currency` reviewer wired (P3).** Sixth P3 (Content Quality) reviewer
  after `completeness`, `correctness`, `clarity`, `conciseness`, and `relevance`.
  `StrategyChunk`, one-shot, cheap model (`deepseek-v4-flash`), 200-line windows (wide
  enough to catch inconsistent version or date references across a passage). Detects
  superseded standards cited as current, deprecated APIs/libraries, obsolete product
  versions, expired dates presented as future obligations, replaced technologies
  (e.g., TLS 1.0, SHA-1), and stale regulatory requirements — judged relative to the
  document type and domain inferred from `doc_context`. Findings default to `pass=P3`,
  `aspect=currency`, `finding_type=outdated`, `severity=medium`. Enabled in
  `doc-review.local.toml` (`[reviewers.currency]`). Code in
  `server/api/doc-reviews/review-currency.go` (+ wiring in `review-document.go`); prompt
  `prompts/prompt-review-currency.md`.
* **2026/06/25, DeepSeek prompt cache strategy recorded.** All configured reviewers now use
  `deepseek-v4-flash`, and DeepSeek context caching is automatic but prefix-based. The
  generic OpenAI-compatible helper currently sends `system = reviewer prompt` and
  `user = document/window JSON`, which fragments the prefix across 40+ reviewers. Added
  DR8a: doc-review LLM calls should put a canonical, byte-identical document/window/block
  input before reviewer-specific instructions, schedule reviewers by shared input unit, and
  capture DeepSeek `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` for measurement.

## Context

SemOS ingests and processes technical documents (standards, specifications, regulatory
documents) into a rich set of structured artifacts — entities, relations, metrics, provisions,
semantic projections, summaries, topics, scene objects, and inventory items — connected through
line-overlap, category membership, entity-name dictionaries, relation-predicate dictionaries,
and hybrid semantic links. A processed document is therefore not just text: it is a graph of
verifiable claims.

The next step is to use LLMs to **review** a document against a checklist of ~40 aspects
(defined in [1]) spanning content quality, structure, technical accuracy, compliance,
usability, writing style, data confidentiality, and traceability. The review is a **paid
service**; quality is the primary goal, cost optimization follows in a second phase.

The document-under-review may be **incomplete** — for example, a medical device specification
that omits a required metric or fails to address a mandatory regulatory requirement. Detecting
these absences is the central value proposition.

## Decision

### DR1 — One reviewer per aspect, grouped into P1–P6

Each review aspect is implemented by an independent **reviewer** — a single-purpose unit
specializing in exactly one aspect (e.g. `grammar_reviewer`, `standards_compliance_reviewer`).
All reviewers implement the same Go interface (§DR2). They run as concurrent goroutines
during Phase C.

The ~40 aspects are organized into **six groups (P1–P6)** for configuration and
prioritization, but the groups are logical buckets, not execution monoliths:

| Group | Description | Example reviewers | Execution |
|-------|-------------|-------------------|-----------|
| **P1 — Language & Style** | Surface-level writing quality | `grammar_spelling`, `tone_voice`, `formatting_consistency`, `readability`, `localization` | Document-level |
| **P2 — Structure & Organization** | Document architecture | `logical_flow`, `heading_hierarchy`, `toc_accuracy`, `navigability`, `section_balance`, `modularity` | Document-level |
| **P3 — Content Quality** | Depth and correctness of content | `completeness`, `correctness`, `clarity`, `conciseness`, `relevance`, `currency`, `examples`, `diagrams`, `testable_claims`, `evidence_rationale` | Per-chunk |
| **P4 — Consistency** | Cross-document coherence | `internal_contradictions`, `terminology_consistency`, `cross_reference_correctness`, `formatting_consistency`, `requirement_traceability` | Document-level |
| **P5 — Technical & Compliance** | Standards, regulations, technical depth | `technical_accuracy`, `assumptions`, `prerequisites`, `standards_compliance`, `legal_compliance`, `regulatory_compliance`, `internal_policy`, `security`, `performance`, `error_handling`, `limitations` | Per-chunk or document-level |
| **P6 — Meta & Process** | Document housekeeping | `version_history`, `review_status`, `ownership`, `references`, `related_documents`, `confidentiality`, `sensitive_data`, `pii`, `data_retention`, `license_ip` | Document-level |

The group determines **default** model and tool selection; each reviewer can override.

### DR2 — Unified Reviewer interface, two execution strategies

Every reviewer implements the same interface. The interface is the contract that allows
the framework to launch, monitor, and collect results from any reviewer uniformly:

```go
// Reviewer executes one review aspect against a document.
type Reviewer interface {
    // Name returns the aspect name, e.g. "grammar_spelling".
    Name() string

    // Group returns the group key, e.g. "P1".
    Group() string

    // Strategy returns how the reviewer processes the document.
    Strategy() ReviewStrategy  // StrategyChunk or StrategyDocument

    // ReviewDocument runs the review and returns findings.
    ReviewDocument(ctx context.Context, recordID int64, cfg ReviewerConfig) ([]ReviewFinding, error)
}
```

Two execution strategies, selected by `Strategy()`:

**StrategyChunk** — the reviewer receives chunks and processes them concurrently (via
`runConcurrent`). The reviewer's `ReviewDocument` internally fans out per chunk,
aggregates findings, and returns a single slice. Used for aspects where issues are
localizable to a passage (grammar, completeness, technical accuracy).

**StrategyDocument** — the reviewer receives a single assembled context (headings tree,
full entity roster, full metric roster, metadata, etc.) and makes one or more
document-level LLM calls. Used for aspects that require cross-document reasoning
(consistency, logical flow, confidentiality).

If a document is too big, it will break up the document into multiple blocks. 
Each block contains up to INPUT_BLOCK_SIZE (default: 20) pages.

Each reviewer manages its own internal concurrency and context assembly. The framework
only calls `ReviewDocument(ctx, recordID, cfg)` and collects the `[]ReviewFinding`.

### DR3 — Per-reviewer configuration

Each reviewer is independently configured. Configuration is per-document-review-run,
stored alongside the review request:

```toml
[doc_review.reviewers.grammar_spelling]
enabled = true
model_ref = "deepseek-v4-flash"
prompt = "prompt-review-grammar.md"
max_tool_turns = 0          # 0 = one-shot (no tools)

[doc_review.reviewers.standards_compliance]
enabled = true
model_ref = "deepseek-v4-flash"
prompt = "prompt-review-standards-compliance.md"
max_tool_turns = 12
reference_docs = ["ISO 13485:2016", "IEC 62304:2006"]  # optional override

[doc_review.reviewers.readability]
enabled = false             # skip this aspect for this run
```

Defaults by group:
- P1: cheap model, one-shot, no tools
- P2: strong model, one-shot, no tools
- P3: strong model, tool-use (max 5 turns)
- P4: strong model, tool-use (max 8 turns)
- P5: strongest model, tool-use (max 12 turns)
- P6: strong model, one-shot (rule-based pre-filter for PII/secrets)

Per-document overrides allow the user to target specific reference standards for P5
reviewers.

**Implementation status (2026/06/23):** DR3 config loading is wired for Phase I.
Configuration is **global** (loaded once at startup from `doc-review.local.toml`),
not per-review-run. The file has two sections:

- `[packages.P1..P6]` — group-level defaults (`enabled`, `model`, `max_tool_turns`,
  `strategy`).
- `[reviewers.<aspect>]` — per-aspect overrides (`enabled`, `group`, `model`,
  `prompt`, `max_tool_turns`). Pointer fields distinguish "unset" from explicit zero.

Resolution merges group defaults → per-aspect overrides via
`DocReviewConfig.ResolveReviewer(aspect, group)`. `NewReviewProcessor` reads the
config exclusively through `GetDocReviewConfig()` (singleton, `sync.Once`);
if no model name or prompt is specified in the configuration, it is treated as
an error and the reviewer is disabled.

**Currently wired:** the five P1 reviewers `grammar_spelling`, `tone_voice`,
`formatting_consistency`, `readability`, and `localization`; the five P2
(document-level) reviewers `logical_flow`, `heading_hierarchy`, `navigability`,
`section_balance`, and `modularity`; and six P3 (content-quality, per-chunk)
reviewers `completeness`, `correctness`, `clarity`, `conciseness`, `relevance`, and `currency`. All other
per-aspect blocks are forward-looking config — their reviewers do not exist yet. **Out of scope:**
per-review-run TOML (single-run overrides must come from the request's stored
`model_overrides` JSONB, which is persisted but not yet applied at execution time —
see DR11 gap). `reference_docs` is not supported. `max_tool_turns` is stored but
the tool-use conversation loop (DR10b) is Phase II+. See
`server/api/doc-processing/review-config.go`.

### DR4 — Reference documents live in SemOS

SemOS already ingests reference standards (ISO, IEC, GB, NIST, etc.) through the same
pipeline. Their entities, relations, metrics, provisions, and full text are available in
the same database. P5 retrieves relevant reference sections via:

1. **Category-path overlap** — the document-under-review's semantic projections identify
   its domain categories; reference documents in the same categories are primary candidates.
2. **Entity-name dictionary** — entities from the document-under-review matched to
   reference-standard entities via `kb.entity_names` → identifies which reference standards
   define those entities.
3. **Hybrid search** — `kb.search_artifacts` BM25 + vector RRF retrieval for relevant
   provisions/metrics from reference documents.

### DR5 — Phase C execution, on-demand invocation only

`review_document` is a configurable processor registered in the pipeline but **excluded
from `config.toml` `required_processors`**. It never runs during automatic corpus ingestion
(batch document processing). It is an **application** of SemOS, not a pipeline step.

Invocation is via explicit `operation` selection:

```json
{
  "record_id": "416",
  "operation": ["review_document"],
  "force": false
}
```

When invoked:
1. Phase A mandatory processors run (they detect existing results and skip with
   `force: false` — negligible overhead).
2. Phase B: `review_document.HandleEvent` is a no-op.
3. Phase C: `review_document.PostProcessIndex` runs the review against the already-
   extracted artifacts.

Rationale for Phase C:
- Review reads entities, relations, metrics, provisions, summaries, and semantic
  projections — all must be complete.
- Phase C is the canonical "all artifacts ready" hook.
- Review is inherently a post-hoc step, not a parallel extraction.
- Separating invocation from automatic ingestion prevents reviewing incomplete or
  uncorrected documents during knowledgebase building.

The processor is registered in `main.go` (available for selection) but excluded from
`required_processors` (not auto-enabled). This follows the existing `operation`-based
selector pattern used by all configurable processors.

### DR6 — Missing compliance detection

This is the critical capability: detecting what the document-under-review **should have but
doesn't**. Two complementary mechanisms:

**DR6a — Entity/Metric roster completeness (cross-document comparison):**

For each relevant reference standard identified in DR4:
1. Extract the reference's **requirements roster**: all entities, metrics, and provisions
   that a compliant document must address.
2. Normalize entity names through the `kb.entity_names` dictionary (cross-document).
3. Compare against the document-under-review's own entities and metrics.
4. Flag reference entities/metrics with **no match** in the reviewed document as
   `finding_type = "missing_requirement"`.

This is a **document-level** step within P5, executed after the per-chunk compliance check.

**DR6b — Provision-to-requirement gap analysis:**

For each normative provision in the reference standard:
1. Check whether the document-under-review has a corresponding provision (matched by
   normalized name + category overlap).
2. If the reference provision has an associated metric (via line-overlap in the reference
   document), check whether the reviewed document specifies that metric.
3. Flag unmatched reference provisions as `finding_type = "missing_provision"`.

**DR6c — Implicit expectation injection (prompt-level):**

P3's per-chunk prompt includes a section: *"For a document of this type (identified from
doc_context), the following entities, metrics, and provisions are typically expected. Flag
any that are missing from this chunk or the document as a whole."* The roster is assembled
from reference-standard artifacts and injected as structured context.

### DR7 — One-time review per document version

Review is triggered once per document version (not continuously). Idempotent: re-running
replaces all findings for that document. The review is tied to the document's processing
run; if the document is re-processed (e.g., after artifact corrections), review can be
re-run.

### DR8 — Two-phase development

**Phase 1 (quality):**
- All 6 passes implemented with strong models where needed.
- Comprehensive prompt engineering per aspect.
- Human-in-the-loop: internal assistants review parsed content and extracted artifacts
  before review runs.
- Findings stored with full provenance (evidence quotes, line locations, confidence scores).
- Dashboard for configuring aspects, running review, and browsing findings.

**Phase 2 (cost optimization):**
- Model downgrading where quality is preserved (P1 already cheap).
- Aspect batching within passes (e.g., combine low-priority P6 aspects into one sub-call).
- Caching: if the document text hasn't changed, skip text-only passes (P1) on re-run.
- Token budgeting: limit reference-standard context to the most relevant sections.

### DR8a — DeepSeek prefix-cache-aware prompt layout

All doc reviewers are configured to use `deepseek-v4-flash`. DeepSeek's API context
caching is automatic, but it is a **prefix cache**: a later request can hit cache only
for a beginning segment that fully matches a prefix unit already persisted by DeepSeek.
The response usage object exposes `prompt_cache_hit_tokens` and
`prompt_cache_miss_tokens` for verification.

The current generic LLM helper layout is not sufficient for cross-reviewer cache reuse:

```text
system: <reviewer-specific prompt>
user:   <document/window/block JSON>
```

With that layout, each reviewer starts with a different prefix, so DeepSeek cannot reuse
the large shared document/window input across the 40+ aspect reviewers as effectively as
it should. For document-review calls, the request should be shaped as:

```text
system: You are a document review engine. Return strict JSON only.

user:
<DOCUMENT_INPUT>
{canonical doc_context + lines JSON}
</DOCUMENT_INPUT>

<REVIEW_TASK>
Aspect: correctness
Reviewer rubric, task-specific instructions, output schema, examples, and tool rules.
</REVIEW_TASK>
```

Operational rules:

1. Canonicalize `doc_context` + `lines` JSON and keep it byte-identical for every reviewer
   that reviews the same input unit.
2. Keep all reviewer-specific content after `</DOCUMENT_INPUT>`.
3. Reuse block boundaries across reviewers where feasible: shared line windows for
   `StrategyChunk`, shared page blocks for `StrategyDocument`.
4. Schedule by shared input unit (`block -> all selected reviewers`) rather than by reviewer
   (`reviewer -> all blocks`) so the cache has just been warmed when the sibling reviewers
   run. DeepSeek notes cache construction takes seconds and unused cache is cleared after
   hours to days.
5. Extend LLM usage capture to persist `prompt_cache_hit_tokens` and
   `prompt_cache_miss_tokens`, then report hit rate by `(model, record_id, input_unit_hash,
   strategy)` before adding more cache-specific complexity.

This does not make the API stateful; the document input must still be sent on every call.
It only gives DeepSeek a stable prefix to reuse and discount. Primary references:
DeepSeek Context Caching (`https://api-docs.deepseek.com/guides/kv_cache`) and Chat
Completion usage fields (`https://api-docs.deepseek.com/api/create-chat-completion`).

### DR9 — Human-in-the-loop workflow

The review is not fully automated. The workflow is:

1. **Submit** — user uploads PDF/DOCX.
2. **Parse** — SemOS converts to line file.
3. **Human pre-review of parsed content** — internal assistant reviews parsed content,
   corrects visual parsing errors (mis-identified headings, merged paragraphs, etc.).
4. **Extract artifacts** — run all doc processors on the document.
5. **Human pre-review of artifacts** — internal assistant reviews extracted entities,
   relations, metrics, provisions; corrects errors (invalid entities, duplicates,
   inaccurate metrics, missing categorizations).
6. **Configure review** — select aspects to check (by priority tier or individually),
   configure models per aspect.
7. **Run review** — `review_document` processor executes the selected passes.
8. **Review findings** — browse, filter, accept/reject, annotate findings.
9. **Adjust and re-run** — if quality insufficient, adjust prompts, models, or corrected
   artifacts, then re-run.

Steps 3 and 5 are the human quality gates that ensure the LLM review operates on clean input.

### DR10 — Tool-use reviewers: LLM as investigator, Go as platform

For simple reviewers (P1 grammar, P6 meta), a one-shot LLM call is sufficient: present
the text, receive findings. But for complex reviewers — completeness, correctness,
consistency, standards compliance — the review is an **investigation**, not a single
classification. The LLM needs to form hypotheses ("this claim looks suspicious"), chase
them down ("what does the reference standard require?"), discover new leads ("that entity
is related to several metrics I should check"), and only then produce findings.

One-shot prompts can't do this. They fire once and hope the assembled context was
sufficient. If the Go code pre-assembled the wrong context, the review silently misses
things.

**Decision: Reviewers declare their execution mode — one-shot or tool-use — via
`ReviewerConfig.MaxToolTurns`.** When `MaxToolTurns == 0`, the reviewer runs one-shot.
When `MaxToolTurns > 0`, the reviewer runs the managed conversation loop (DR10b). The
Go code is the **platform** — it owns the artifact stores, executes tool calls, enforces
budget, and persists findings. The LLM is the **investigator** — it decides what to look
for, in what order, based on what it discovers.

Default mode by group:

| Group | Default mode | Max tool turns | Rationale |
|-------|-------------|----------------|-----------|
| P1 Language & Style | One-shot | — | Local text check; no investigation needed |
| P2 Structure | One-shot | — | Headings tree is compact and complete |
| P3 Content Quality | **Tool-use** | 5 turns | Chase suspect claims by querying related entities/metrics/provisions |
| P4 Consistency | **Tool-use** | 8 turns | Follow entity/relation graph to trace contradictions across the document |
| P5 Compliance | **Tool-use** | 12 turns | Retrieve reference standards, compare requirements, iterate on gaps |
| P6 Meta | One-shot | — | Metadata + rule-based PII checks |

#### DR10a — Tool catalog (shared, per-reviewer selection)

The Go framework exposes a fixed, shared set of SemOS-aware tools. Each reviewer declares
which subset of tools it needs via `ReviewerConfig.Tools []string`. The framework binds
the requested tools before starting the conversation loop.

```go
type ReviewTool struct {
    Name        string
    Description string           // natural-language description for the LLM
    Parameters  map[string]any   // JSON Schema for arguments
    Execute     func(ctx context.Context, args map[string]any) (any, error)
}
```

**Core tools (document-intrinsic, available to all tool-use reviewers):**

| Tool | Description | Returns |
|------|-------------|---------|
| `search_entities` | Full-text search `kb.entities` in this document. Args: `query`, `limit` | Matching entity rows (entity_id, entity, entity_type, aliases, desc, line_spans) |
| `get_entity` | Fetch one entity by ID. Args: `entity_id` | Full entity row + connected chunk summaries |
| `get_entity_relations` | All relations involving an entity. Args: `entity_id` | Subject/object relation triples with predicate, line_spans, confidence |
| `search_metrics` | Full-text search `kb.metrics` in this document. Args: `query`, `limit` | Matching metric rows (metric_id, metric_name, value_range, unit, source_line_spans) |
| `get_metric` | Fetch one metric by ID. Args: `metric_id` | Full metric row + connected provisions + entities |
| `search_provisions` | Full-text search `kb.provisions` in this document. Args: `query`, `limit` | Matching provision rows |
| `get_provision` | Fetch one provision by ID. Args: `provision_id` | Full provision row + connected metrics |
| `get_chunk_summary` | Summary for a chunk. Args: `chunk_id` | Summary text + sibling (prev/next) summaries |
| `get_chunk_lines` | Raw lines for a chunk. Args: `chunk_id`, `offset`, `limit` | Subset of chunk lines (for deep-dive into a specific passage) |

**P5 tools (cross-document, available to compliance/standards reviewers):**

| Tool | Description | Returns |
|------|-------------|---------|
| `search_reference_docs` | Find reference standards relevant to a concept. Args: `concept`, `limit` | Matching documents from `kb.search_artifacts` with record_id, title, doc_no, relevance score |
| `get_reference_roster` | Extract the requirements roster from a reference doc. Args: `record_id` | Entities, metrics, and provisions that a compliant document must address |
| `search_reference_provisions` | Search provisions in a specific reference doc. Args: `record_id`, `query`, `limit` | Matching provision rows from that reference |
| `check_entity_in_reference` | Check if an entity name matches any in a reference standard's roster. Args: `entity_name`, `reference_record_id` | Matched reference entity + match method (exact, alias, normalized) |

#### DR10b — Managed conversation loop

Each tool-use reviewer runs a bounded conversation loop. The Go framework manages the
cycle: assemble system + user messages → call LLM with tool definitions → if findings,
done → if tool calls, execute them → append results → repeat.

```
┌────────────────────────────────────────────┐
│ Go: assemble system prompt + user context   │
│     + tool definitions                      │
│                ↓                            │
│ LLM call ──→ tool_calls? ──→ YES ──→ Go    │
│   │                          executes tools │
│   │ NO (findings produced)         ↓        │
│   ↓                          append results │
│ return findings              to messages    │
│                                ↓            │
│                         increment turn      │
│                         count               │
│                                ↓            │
│                         turn < max? ──→ YES │
│                                │            │
│                                NO           │
│                                ↓            │
│                         force-produce       │
│                         findings prompt     │
└────────────────────────────────────────────┘
```

Pseudo-code contract (shared by all tool-use reviewers):

```go
func runToolUseReview(
    ctx context.Context,
    cfg ReviewerConfig,
    systemPrompt string,
    userContext string,     // chunk lines + doc_context + initial evidence
    findingsSchema string,  // JSON Schema for structured findings output
    onStop OnStopFunc,
) ([]ReviewFinding, error) {
    tools := buildToolList(cfg.Tools)

    messages := []llmMessage{
        {Role: "system", Content: systemPrompt},
        {Role: "user",   Content: userContext},
    }

    for turn := 0; turn < cfg.MaxToolTurns; turn++ {
        // Check for stop request at each LLM call boundary.
        if CheckAndHandleStop(ctx, onStop) {
            return findingsSoFar, ErrPipelineStopped
        }

        resp, err := callLLMWithTools(ctx, messages, tools, findingsSchema)
        if err != nil { return nil, err }

        // LLM produced final findings — exit loop.
        if resp.HasStructuredOutput() {
            return normalizeFindings(resp.StructuredOutput, turn), nil
        }

        // LLM requested tool calls — execute them.
        toolResults, execErrors := executeToolCalls(ctx, resp.ToolCalls, tools)
        messages = append(messages, resp.AssistantMessage)
        messages = append(messages, toolResults...)

        if resp.HasPartialFindings() {
            findingsSoFar = append(findingsSoFar, resp.PartialFindings...)
        }
    }

    // Budget exhausted — force finalize.
    messages = append(messages, llmMessage{
        Role: "user",
        Content: "You have reached the maximum investigation turns. " +
            "Produce your final findings based on the evidence collected so far.",
    })
    resp, err := callLLM(ctx, messages, findingsSchema)
    if err != nil { return nil, err }
    return normalizeFindings(resp.StructuredOutput, cfg.MaxToolTurns), nil
}
```

**Why expose `findingsSchema` alongside tool definitions:** the LLM returns structured
findings that conform to the `kb.doc_review_findings` shape. The schema is the
contract — the LLM either emits `Findings` (final) or `ToolCalls` (more investigation
needed), never both in the same response.

#### DR10c — Budget management

Cost is bounded per reviewer, per invocation (per chunk for StrategyChunk, per document for
StrategyDocument):

```go
type ReviewerConfig struct {
    Enabled        bool     // whether this reviewer runs
    ModelRef       string   // which model (must support tool use if MaxToolTurns > 0)
    PromptRef      string   // which prompt file
    MaxToolTurns   int      // 0 = one-shot, >0 = tool-use with this cap
    MaxToolTokens  int64    // cap total tokens consumed by tool results across all turns
    Tools          []string // which tool names are available
    ReferenceDocs  []string // P5 only: specific reference standards to check against
}
```

Default budgets by group:
- P3 reviewers: 5 turns, core tools. ~$0.15–0.30/chunk with Sonnet.
- P4 reviewers: 8 turns, core tools. One document-level call. ~$0.50–1.00/doc.
- P5 reviewers: 12 turns, core + P5 tools. ~$0.40–0.80/chunk + $1.00–2.00/doc.

When `MaxToolTurns` is exhausted, the loop appends a force-produce message asking the LLM
to finalize findings from the evidence already collected. No findings are lost.

#### DR10d — Why tool-use over pure skill

A pure skill (Claude Code driving the entire review from outside the pipeline) would
address the "LLM as investigator" need, but loses:

- **Concurrency:** a skill processes chunks sequentially; the Go framework runs all
  chunk-based reviewers' per-chunk calls concurrently via `runConcurrent`, and runs
  all reviewers themselves as concurrent goroutines.
- **DB integration:** Go has connection pools, prepared statements, and transaction
  management tuned for the SemOS schema. A skill queries through the MCP or shell layer.
- **Dashboard:** the GUI reads `kb.doc_review_findings` for findings, `kb.inputs.status`
  for progress. A skill would need to write these outside the pipeline's status-locking
  protocol.
- **Stop handling:** the pipeline's `CheckAndHandleStop` contract is Go-native.
- **Model routing:** the existing `config.toml` → `structureModelConfig` → LLM client path
  already handles per-reviewer model selection with primary/fallback.

The hybrid (DR10) keeps the Go platform for what it does well and lets the LLM drive the
investigation inside each reviewer — the same "Harness Engineering" principle, embedded
within the doc processor.

**Skill is still used for:** (a) human pre-review of parsed content and artifacts (steps 3
and 5 in DR9), and (b) prototyping new reviewer prompts and tool definitions before baking
them into Go.

### DR11 — DocReviewController: the coordinator

The `ReviewProcessor` handles the mechanics of launching reviewers and saving findings,
but it expects everything to be pre-configured: which aspects to run, which models to use,
which reference documents to compare against, whether the user chose a priority tier or
hand-picked individual aspects. There is no place for user intent.

**`DocReviewController` is the service layer that sits between the user request and the
review execution.** It receives a *review request* from the GUI, resolves it into concrete
reviewer configurations, invokes `ReviewProcessor`, and returns the outcome.

```
┌──────────────┐     request      ┌─────────────────────┐     resolve     ┌────────────────────┐
│    GUI       │ ───────────────▶ │ DocReviewController  │ ─────────────▶ │  ReviewProcessor   │
│ (review form)│                  │                      │                │  (PostProcessIndex)│
│              │ ◀─────────────── │                      │ ◀───────────── │                    │
│              │     response     │                      │   findings     │                    │
└──────────────┘                  └─────────────────────┘                └────────────────────┘
                                          │
                                          │ request finished
                                          ▼
                                  ┌─────────────────────────┐
                                  │ DocReviewReportGenerator │
                                  │ (DR12)                   │
                                  └─────────────────────────┘
```

**Responsibilities:**

| Responsibility | Detail |
|---------------|--------|
| Accept review request | Validates the request, stores it in `kb.doc_review_requests` (see data model). |
| Resolve reviewer set | Translates user intent ("check completeness and grammar at medium priority") into a list of enabled/disabled reviewers. Supports three modes: **by tier** (Must/Should/Review), **by individual aspect** (checkbox), and **default** (run all enabled). |
| Resolve models per reviewer | Applies group defaults (P1 → cheap, P5 → strongest) with per-request overrides from the user. |
| Resolve reference docs | User may provide additional supporting/reference documents beyond what DR4 auto-retrieves. Controller merges user-supplied refs with auto-discovered refs. |
| Run the review | Delegates to `ReviewProcessor.PostProcessIndex(ctx, recordID)`. The controller does **not** own the reviewer goroutines — it owns the *orchestration* (before/after hooks, request lifecycle). |
| Trigger report generation | After findings are collected, hands off to `DocReviewReportGenerator`. |
| Enforce idempotency | A document version gets one review request per submission. Re-submission replaces previous findings. |

**Invocation flow:**

```
GUI submits review request
        │
        ▼
DocReviewController.AcceptRequest(ctx, req)
        │
        ├─ Validate: document exists, at least one aspect selected
        ├─ Store request in kb.doc_review_requests (status = "accepted")
        ├─ Resolve reviewer configs from request
        │
        ▼
DocReviewController.RunReview(ctx, req)
        │
        ├─ Update request status → "running"
        ├─ Delegate to ReviewProcessor.PostProcessIndex(ctx, recordID)
        │   (ReviewProcessor reads its own config from env / config.toml as today)
        ├─ Collect findings
        ├─ Update request status → "completed" (or "failed")
        │
        ▼
DocReviewController.GenerateReport(ctx, req)
        │
        ├─ Delegate to DocReviewReportGenerator.Build(ctx, request, findings)
        ├─ Store report in kb.doc_review_reports
        └─ Return report ID to caller
```

**Request-level configuration overrides:**

Not all user choices map to the static `ReviewerConfig` the `ReviewProcessor` knows
today. The controller introduces **per-request overrides** that travel alongside the
review request, stored as JSONB on the request row. Reviewers read these overrides
at execution time:

| Override | Example | Effect |
|----------|---------|--------|
| `enabled` | `{"completeness": false}` | Skip a normally-enabled reviewer. |
| `model_ref` | `{"standards_compliance": "deepseek-v4-flash"}` | Upgrade model for one reviewer. |
| `reference_docs` | `["ISO 13485:2016", "IEC 62304"]` | Additional reference documents for P5. |
| `max_tool_turns` | `{"technical_accuracy": 20}` | Extend investigation budget for one reviewer. |
| `priority_tier` | `"must_review"` | Bulk-enable reviewers in the "Must Review" tier. |

The controller is **not a pipeline processor** — it is a standalone service component
invoked by the HTTP handler that the GUI calls. It does not implement the `Processor`
interface; it *uses* the `ReviewProcessor` (which does).

**Internal state machine (per request):**

```
accepted → running → completed
                   → failed (retryable)
                   → stopped (user cancelled)
```

When `force: true`, a new request replaces the previous one for the same document
version (DR7 still holds: one review per version).

### DR12 — DocReviewReportGenerator

Review findings alone are a list of issues. The reviewer group sees findings grouped
by pass; the customer (document owner) wants a **structured report** that:

- Summarizes findings per pass and per severity.
- Groups related findings (e.g., three terminology-drift findings become one section).
- Provides an executive summary suitable for non-technical stakeholders.
- List all review result items
- Includes actionable fix recommendations with line references.
- Identifies which findings are `missing_requirement` / `missing_provision` (the
  compliance-gap highlights the customer cares most about).

`DocReviewReportGenerator` is a **post-review component** that builds this report
from raw findings + document metadata. It runs synchronously after review completes
(not an async job — the user is waiting for the result).

**Inputs:**

| Input | Source |
|-------|--------|
| `[]ReviewFinding` | `kb.doc_review_findings` for this `review_run_id` |
| Document metadata | `kb.inputs` row (title, doc_no, file_name, parser_name) |
| Review request | `kb.doc_review_requests` row (which aspects were selected, user notes) |
| Artifact summaries | `kb.summaries` for the document (for context in the executive summary) |

**Output:** A full report stored in `kb.doc_review_reports` (see data model) with
two representations:

1. **Structured JSON** — machine-readable, drives the GUI's report view.
2. **Markdown** — human-readable, exportable to PDF/DOCX.

**Report skeleton (DR12a):**

```json
{
  "meta": {
    "report_id": "rpt_416_20260621T120000",
    "document_title": "...",
    "document_record_id": 416,
    "generated_at": "2026-06-21T12:00:00Z",
    "review_run_id": "416_review_20260621T115000",
    "num_reviewers_ran": 4,
    "total_findings": 37
  },
  "executive_summary": {
    "text": "...",
    "top_findings": ["...", "..."],
    "overall_assessment": "pass_with_issues" | "fail" | "needs_review"
  },
  "findings_by_pass": {
    "P1": { "label": "Language & Style", "findings": [...] },
    "P3": { "label": "Content Quality", "findings": [...] },
    ...
  },
  "compliance_summary": {
    "reference_standards_checked": ["ISO 13485:2016"],
    "provisions_satisfied": 82,
    "provisions_partially_satisfied": 7,
    "provisions_not_addressed": 3,
    "provisions_not_applicable": 12,
    "missing_requirements": ["design_change_control_procedure", ...]
  },
  "findings": [
    {
      "pass": "P5",
      "aspect": "standards_compliance",
      "severity": "high",
      "finding_type": "missing_provision",
      "title": "...",
      "description": "...",
      "evidence": "...",
      "location": { "start_line": 142, "end_line": 148 },
      "suggestion": "...",
      "confidence": 0.92
    }
  ],
  "recommendations": [
    {
      "priority": 1,
      "action": "Add documented design change control procedure per ISO 13485 §7.3.7",
      "related_finding_ids": [3, 17]
    }
  ]
}
```

**Implementation approach (DR12b):**

The report structure is assembled by Go code (filling the JSON skeleton). The
*executive summary text* and *top findings selection* may be delegated to an LLM
call (one-shot, cheap model) fed with the aggregated findings. The compliance
summary is computed by counting findings by `finding_type` and `pass`.

The Markdown export is a straightforward Go template that renders the JSON report
as sections with headings. No LLM needed for rendering.

### DR13 — Review Request GUI

Users need a review submission form integrated into the SemOS dashboard. This is
an incremental addition to the existing Svelte frontend, not a separate application.

**Route:** `/dashboard/doc-review` (new page)

**Page layout:**

```
┌─────────────────────────────────────────────────────────┐
│  Document Review                                   [?]  │
│                                                         │
│  Step 1: Select Document                                │
│  ┌───────────────────────────────────────────────────┐  │
│  │ [Search documents...]                              │  │
│  │ ○ doc-016 — Surgical Instrument SOP v2.3          │  │
│  │ ○ doc-042 — Temperature Monitoring Procedure       │  │
│  │ ● doc-087 — Sterilization Validation Protocol     │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  Step 2: Choose Check Level                          │
│  ┌───────────────────────────────────────────────────┐  │
│  │ ● Must Review (9 aspects)   — Critical only       │  │
│  │ ○ Should Review (6 aspects) — Recommended          │  │
│  │ ○ Custom Selection          — Pick individually ▼ │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  Step 3: Customize Aspects (when Custom Selection)    │
│  ┌───────────────────────────────────────────────────┐  │
│  │ P1 Language & Style                               │  │
│  │   ☑ Grammar & Spelling    ☑ Tone & Voice          │  │
│  │   ☐ Formatting             ☐ Readability          │  │
│  │ P3 Content Quality                                │  │
│  │   ☑ Completeness          ☑ Correctness           │  │
│  │   ☑ Clarity               ☐ Conciseness           │  │
│  │   ☐ Relevance             ☐ Currency              │  │
│  │   ☐ Examples              ☐ Diagrams              │  │
│  │   ☑ Testable Claims       ☑ Evidence & Rationale  │  │
│  │ ... (collapsed by default for P2/P4/P5/P6)        │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  Step 4: Supporting Documents (optional)              │
│  ┌───────────────────────────────────────────────────┐  │
│  │ [Search and add reference standards...]            │  │
│  │   ✕ ISO 13485:2016 (already in knowledgebase)     │  │
│  │   ✕ IEC 62304:2006 (already in knowledgebase)     │  │
│  │ + Add reference document...                        │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  Step 5: Notes (optional)                             │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Focus especially on sterilization cycle validation │  │
│  │ sections. The previous review flagged temperature  │  │
│  │ monitoring gaps.                                   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│                       [Cancel]    [Start Review]        │
└─────────────────────────────────────────────────────────┘
```

**Priority tier presets:**

When the user selects a tier, the backend resolves it to a concrete set of aspects
using the checklist's tier map (spec [1], §3.10). The map is maintained in the
backend, not hardcoded in the frontend — it is fetched from an endpoint so it
can evolve as the checklist grows.

| Tier | API key | How many aspects (today) |
|------|---------|--------------------------|
| Must Review | `must_review` | 12 |
| Should Review | `should_review` | 6 (+ 12 from Must) |
| Review for External/Public | `review_external` | 5 (+ above) |
| Review for Regulated | `review_regulated` | 6 (+ above) |
| Custom | `custom` | User picks individually |

**Model selection helper:**

By default, the controller uses group defaults (DR3). For advanced users, an
expandable "Advanced Settings" section lets them override the model per group:

```
Model overrides:
  P1 (Language):    [Default (Haiku 4.5) ▼]
  P3 (Content):     [Default (Sonnet 4.5) ▼]
  P5 (Compliance):  [Opus 4.8           ▼]
```

**After submission — progress and result view:**

Submission redirects to `/dashboard/doc-review/results/<request_id>` which shows:

1. **Progress indicator** — while the review is running (`status: "running"`),
   poll for status and show a spinner with the current stage.
2. **Summary cards** — when complete, show: total findings, findings by severity
   (high/medium/low bar chart), pass-by-pass breakdown, compliance gaps.
3. **Findings table** — filterable, sortable table of all findings. Each row
   expandable with evidence, location, and suggestion. "Accept" / "Reject" /
   "Defer" buttons per finding (writes back to `kb.doc_review_findings.review_status`).
4. **Full report** — DR12's structured JSON rendered as sections. "Export PDF"
   and "Export DOCX" buttons.

**API endpoints (new):**

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/doc-review/aspects` | Returns all aspects with their group, priority, description (drives the checkbox UI). |
| `GET` | `/api/doc-review/tiers` | Returns the tier → aspect mapping (drives the priority picker). |
| `POST` | `/api/doc-review/requests` | Submit a review request. Body: `{record_id, tier, aspects[], reference_docs[], notes, model_overrides{}}`. Returns `{request_id}`. |
| `GET` | `/api/doc-review/requests/<id>` | Returns request status + findings when complete. |
| `GET` | `/api/doc-review/reports/<id>` | Returns the full report JSON. |
| `GET` | `/api/doc-review/reports/<id>/export?format=pdf|docx` | Returns the report as PDF or DOCX. |
| `PATCH` | `/api/doc-review/findings/<id>` | Update a single finding's `review_status` (accept/reject/defer). |
| `POST` | `/api/doc-review/requests/<id>/stop` | Request stop during execution. |

Document review report generation is documented in [8].

### DR15 — Per-Aspect Review Status & Live Job Monitor

The original DR13 monitor had a fidelity gap: findings are persisted only when a
run completes, and `kb.doc_review_requests.status` is a single job-level value, so
the monitor could only show "all aspects queued → all running → all done." It could
not show individual reviewers (aspects) progressing independently, nor list *all*
in-flight jobs the way the Active Pipelines dashboard does for the ingestion pipeline.

**Decision: track review progress at the granularity of a single aspect, in a new
`kb.doc_review_status` table, and drive the GUI monitor from it.**

- **One row per `(review_run_id, aspect)`.** Created when the request is accepted
  (status `pending`), so progress is observable from the moment the job is queued.
- **`review_run_id` is assigned at accept time** (previously at run-start) so the
  status rows — and the findings — can share the run identity from the start.
- **Per-aspect lifecycle:** `pending → running → success | failed`. An aspect is
  **finished iff** its status is `success` or `failed`. Transitions are reported by
  each reviewer goroutine (true live progress) or, as a fallback, set by the
  controller after `ReviewProcessor` returns (all aspects flip together).
- **A review job is finished when all its aspects are finished**; the controller
  then marks the request `completed`. Per-aspect status — not the request-level
  status — is the authoritative liveness signal for the monitor.
- **Global monitor.** `GET /api/v1/doc-review/active` returns every request that
  still has ≥1 unfinished aspect (across all users/sessions), each with its
  per-aspect status list. The GUI monitor polls this endpoint and renders one card
  per active job, with per-aspect status nodes. **A job is removed from the monitor
  automatically the moment its last aspect finishes** — it simply stops being
  returned by the active query.

This keeps the monitor honest (it reflects real per-aspect state, not an inferred
job-level approximation), matches the Active Pipelines UX, and needs no extra
"is this job still shown?" bookkeeping — the `WHERE EXISTS (… status NOT IN
('success','failed'))` predicate is the single source of truth.

### DR16 — Finding actions on the report page (Auto Fix, Edit Tool, Delete, Accept) + report regeneration

The Document Review Report page (`/home3/doc-review-report/<report_id>`) was
read-only: it rendered the frozen `report_json` skeleton (DR12a) and let the
reviewer click a finding to focus the corresponding source lines in the
Document-Structure panel. It offered no way to **act** on a finding — to apply a
fix, dismiss it, or accept it as-is.

**Decision: each finding on the report page gets four actions, plus a conditional
"Regenerate PDF" control.** The report's finding cards are now rendered from the
**live `kb.doc_review_findings` rows** (fetched via `GET /requests/<request_id>`)
rather than the frozen `report_json`, so every card carries a stable finding `id`
and current `review_status` to target. The executive summary, meta, and severity
totals still come from `report_json`.

| Action | Behavior | Mechanism |
|--------|----------|-----------|
| **LLM Auto Fix** | Corrects the offending source line(s) automatically. If the issue cannot be fixed, the user is prompted with the reason (no silent no-op). | LLM call → edits the line-file → marks finding `fixed`. |
| **Edit Tool** | Opens a find/replace dialog over the offending line(s) for a manual, deterministic edit. | Dialog → `POST /findings/<id>/edit` writes the line-file → marks finding `fixed`. |
| **Delete** | Removes the finding from the report. | `PATCH /findings/<id>` → `review_status = 'deleted'` (soft delete; hidden from the list and excluded from regeneration). |
| **Accept** | Keep as-is — take no action. | `PATCH /findings/<id>` → `review_status = 'accepted'`. Does **not** change the document or the report set. |

**Scope of "the fix": the extracted line-file, not the original PDF.** Auto Fix and
Edit Tool both mutate the document's extracted **line-file** (the 7-field
tab-separated record the right-panel line list and `report.go`'s `loadDocLines`
read). The original uploaded/scanned source PDF is never rewritten — it cannot be
regenerated from edited text. Edits replace only the content field (field 7) of
the targeted line numbers in place; all other fields and untouched lines are
preserved verbatim. The offending line numbers come from the finding's `location`
(parsed by the existing `parseLocationRange`).

**LLM Auto Fix engine.** The model is resolved from `AUTO_FIX_MODEL_NAME` (a
`MODEL_DEF_FILE` ref), with `AUTO_FIX_CALLBACK` as an optional fallback ref, built
through the existing `docprocessing.BuildReviewerLLMClient` path. The model is
sent the offending line(s) plus the issue (title / description / suggestion /
aspect / severity) and must return strict JSON
`{ "fixable": bool, "reason": str, "fixes": [{ "line_no": int, "corrected": str }] }`.
When `fixable` is false, no model is configured, the finding has no parseable line
location, or the model proposes no change, the API returns a 200 with
`fixable: false` and a message the GUI surfaces to the reviewer (the "prompt the
user" path) — it is not an HTTP error.

Since letting an LLM fix a problem is a lengthy operation, the browser should prompt
the user and a kind of 'waiting wheel' is shown. When the LLM responds, it should 
open a dialog that shows:
- The model name
- The time used in milliseconds
- The finding's reasons
- The offending lines
- The response from the LLM
- The 'Cancel', 'Retry', 'Save' buttons

If `fixable: false` is false, show the reasons why it is not fixable (should come
from the LLM response).)

**Edit Tool dialog.** Shows the finding's **Suggestion** at the top, then each
offending line (with its line number) in an editable, auto-sizing multi-line
field (the textarea grows to fit the line's content on open and as the reviewer
types; it stays manually resizable), plus a *Find* substring field and a *Replace*
field. **Find** (enabled when the search field is non-empty) locates the next
occurrence with wrap-around and selects it; **Replace** and **Remove** (enabled
only when a match is found) rewrite/erase the matched span; **Cancel** discards;
**Save** persists the edited line content to the line-file.

**Suggestion split + in-dialog Accept (DR16a).** Reviewers frequently phrase a
suggestion as an *instruction followed by a worked example*, e.g.
`将长句拆分为两个或三个短句。例如：'<rewritten paragraph>'` (or an English/quoted
variant). The dialog parses this shape — splitting off the **quoted proposed
content** from the leading instruction — and renders the proposed content in a
highlighted block with its own **Accept** button. Accept drops the proposed content
into the (first) offending line's editable field; the reviewer then verifies/edits
and clicks **Save** to persist (it does not auto-save). The split is purely
client-side and heuristic: it scans for a matching quote pair (typographic CN/EN
quotes, corner brackets `「」`/`『』`, or straight quotes) and takes the longest
quoted span as the proposed content. When no quoted content is found, the full
suggestion is shown verbatim with no Accept button. The reviewer is responsible
for confirming the proposed text is correct and complete before saving.

The report page itself groups findings into **two levels of collapsible sections**
(all folded by default): an outer **package** (P1–P6) and, within it, one **reviewer
(aspect)** sub-section. Each expanded reviewer's finding list scrolls locally (its
own scrollbar, styled to match the Document-Structure LINES list).

**Regenerate PDF.** Auto Fix, Edit Tool, and Delete mark the report **dirty** and
reveal a "Regenerate PDF" button (Accept does not — it changes neither the document
nor the finding set). Regeneration rebuilds the report from the current
**non-deleted** findings and updates the **same** `kb.doc_review_reports` row in
place (`report_json`, `report_markdown`, counts, executive summary) — the report
id and URL stay stable — then re-runs the Typst report PDF (`GenerateTypstReport`,
gated on `DOC_REVIEW_REPORTS`). Because `Build` re-reads the line-file for source
context, the regenerated report reflects the corrected text. Scope note: the PDF
regenerated is the **review-report PDF**, not a corrected-document PDF.

**`review_status` lifecycle extended.** DR13's `pending | accepted | rejected |
deferred` set gains `deleted` (soft delete) and `fixed` (auto-fixed or
hand-edited). `UpdateFinding`'s allow-list is widened accordingly.

**New endpoints (under `/api/v1/doc-review`):**

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/findings/<id>/auto-fix` | Run the LLM auto-fix; edits the line-file. Returns `{fixable, message?, original?, corrected?}`. |
| `GET` | `/findings/<id>/lines` | Current content of the finding's offending line(s) (drives the Edit Tool dialog). |
| `POST` | `/findings/<id>/edit` | Save user-edited line content to the line-file. Returns `{changed}`. |
| `POST` | `/reports/<id>/regenerate` | Rebuild report JSON/markdown + Typst PDF in place from current findings. |

**Implementation note.** Because the report page now sources finding cards from the
live request, it depends on the request being `completed` (always true for a
generated report). The right-panel source PDF is image-based and is not updated by
line-file edits; the line list reflects edits on reload.

### DR17 — Correction activity log + Document Review Correction Report

DR16 lets a reviewer *act* on a document (Auto Fix, Edit Tool, Delete) and DR15's
Document-Structure panel lets them correct the parsed structure (modify / split /
delete a line). But these corrections left no durable trail: there was no record of
*what* was changed, *by whom*, *when*, or *from what to what*. The customer (document
owner) receives a Review Report listing problems, but no companion artifact showing the
**corrections applied** during review.

**Decision: record every correction action in a new `kb.doc_review_activities` table,
and generate a "Document Review Correction Report" (Typst → PDF) from it** — a sibling
deliverable to the Review Report (DR12 / [8]), written and named the same way.

**Logged actions.** Six `activity_type` values, captured at their source:

| `activity_type`    | Trigger | Source |
|--------------------|---------|--------|
| `auto_fix`         | LLM Auto Fix applied to a finding's line(s) | `DocReviewController.AutoFixFinding` |
| `edit_tool`        | Edit Tool save of a finding's line(s) | `DocReviewController.ApplyFindingEdit` |
| `finding_delete`   | Delete button (`review_status='deleted'`) | `DocReviewController.UpdateFinding` |
| `structure_modify` | Document Structure line edited (type/content/coords) | `kbhandler.UpdateDocStructureLine` |
| `structure_split`  | Document Structure line split into multiple lines | `kbhandler.SplitDocStructureLine` |
| `structure_delete` | Document Structure line deleted | `kbhandler.DeleteDocStructureLine` |

Each row captures `input_record_id`, `review_run_id` (NULL for Document-Structure edits,
which carry no run), the resolved `report_id`, the `finding_id` / page+line target, the
`location`, the **before** (`old_content`) and **after** (`new_content`) text, a JSONB
`detail` (finding title/aspect/severity, model, line type, etc.), the `actor`
(authenticated user when available), and `create_time`.

**Leaf package to avoid an import cycle.** Both the doc-reviews controller and the
kbhandler doc-structure handlers must log. A new package `server/api/docactivity`
(`Log`, `List`, and the activity-type constants) depends only on `database/sql` +
`loggerutil`, so each caller imports it without `kbhandler → doc-reviews` (or the
reverse) coupling. `docactivity.Log` is **best-effort**: on any error it logs a warning
and returns — a logging failure never breaks the reviewer's correction action.

**Correction Report generation.** `DocReviewController.GenerateCorrectionReport(reportID)`
loads the report's `(input_record_id, review_run_id)`, fetches the activities via
`docactivity.List`, renders a Typst source against the
`document-correction-report` template, and compiles it to PDF. It mirrors
`GenerateTypstReport` exactly:

- **Output dir:** `$DOC_REVIEW_REPORTS` (no-op if unset — the same dir as the Review Report).
- **Template:** `$DOC_REVIEW_CORRECTION_TEMPLATE_FILENAME`
  (default `docs/doc-templates/template-correction-report.typ`).
- **Language:** `$DOC_REVIEW_REPORT_LANGUAGE` (default `en`).
- **File names:** `<yyyymmdd-hhmm>-<reportID>-corrections.{typ,pdf}` — parallels the Review
  Report's `<stamp>-<reportID>-reports.{typ,pdf}`.

The template (`#document-correction-report(...)`) renders a cover, basic information, an
"Actions by Type" summary table, and one `correction-entry(...)` per action with
before/after blocks, location, actor, time, and a context note.

**New endpoint + UI.**

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/api/v1/doc-review/reports/<id>/correction-report` | Build the Correction Report (Typst + PDF) from recorded activities. Returns `{status, pdf_path, pdf_file}`. |

Frontend: `generateCorrectionReport(reportId)` in `docReviewService.ts`, triggered by a
**Correction Report** button on the report page.

### DR18 - Report and Corrections File Names
**Report File Names**

A document, identified by record_id `kb.inputs.id`, may be reviewed multiple times. A new record in `kb.doc_review_requests` 
is created for each doc review request. If the review is successful, it will generate
a 'Document Review Report' in both '.typ' and '.pdf'. 

To find all the document review report files for a given `record_id`:
Find all the records in `kb.doc_review_requests` with 
`kb.doc_review_requests.input_record_id` = `record_id`.
Each record maps to one '.pdf' file.

**Report Corrections File Names**
For each '-reports.pdf' file, it may have a '-corrections.pdf' file.

## Data Model

### `kb.doc_review_requests`

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_requests (
    id              BIGSERIAL       PRIMARY KEY,
    input_record_id BIGINT          NOT NULL,  -- the document under review
    review_run_id   TEXT,                      -- assigned at accept time (DR15); links kb.doc_review_findings + kb.doc_review_status
    tier            TEXT            NOT NULL,  -- "must_review", "should_review", "custom", ...
    aspects         JSONB           NOT NULL,  -- ["completeness", "grammar_spelling", ...]
    reference_docs  JSONB,                     -- [{"record_id": N, "doc_no": "...", "title": "..."}]
    notes           TEXT,                      -- user-provided notes
    model_overrides JSONB,                     -- {"P5": {"model_ref": "deepseek-v4-flash"}}
    status          TEXT            NOT NULL DEFAULT 'accepted',  -- accepted, running, completed, failed, stopped
    created_by      TEXT,                      -- user who submitted
    create_time     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    start_time      TIMESTAMPTZ,
    end_time        TIMESTAMPTZ,
    error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_doc_review_requests_record ON kb.doc_review_requests (input_record_id);
```

### `kb.doc_review_reports`

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_reports (
    id                BIGSERIAL       PRIMARY KEY,
    request_id        BIGINT          NOT NULL,  -- references kb.doc_review_requests.id
    input_record_id   BIGINT          NOT NULL,
    review_run_id     TEXT            NOT NULL,
    report_json       JSONB           NOT NULL,  -- full report per DR12a skeleton
    report_markdown   TEXT            NOT NULL,  -- Markdown export
    executive_summary TEXT            NOT NULL,  -- plain-text executive summary
    total_findings    INT             NOT NULL,
    high_count        INT             NOT NULL DEFAULT 0,
    medium_count      INT             NOT NULL DEFAULT 0,
    low_count         INT             NOT NULL DEFAULT 0,
    overall_assessment TEXT           NOT NULL,  -- "pass_with_issues" | "fail" | "needs_review"
    create_time       TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doc_review_reports_request ON kb.doc_review_reports (request_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_reports_record ON kb.doc_review_reports (input_record_id);
```

### `kb.doc_review_status` (DR15)

One row per reviewed aspect per run. Seeded at request-accept (status `pending`),
updated as each reviewer runs. The live monitor lists jobs that still have ≥1 row
with `status NOT IN ('success','failed')`.

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_status (
    id              BIGSERIAL    PRIMARY KEY,
    request_id      BIGINT       NOT NULL,                    -- kb.doc_review_requests.id
    input_record_id BIGINT       NOT NULL,                    -- the document under review
    review_run_id   TEXT         NOT NULL,                    -- assigned at accept; matches requests + findings
    aspect          TEXT         NOT NULL,                    -- one row per reviewed aspect
    pass            TEXT,                                     -- "P1".."P6" (denormalized for grouping)
    status          TEXT         NOT NULL DEFAULT 'pending',  -- pending | running | success | failed
    finding_count   INT          NOT NULL DEFAULT 0,
    error_message   TEXT,                                     -- set when status = 'failed'
    start_time      TIMESTAMPTZ,
    end_time        TIMESTAMPTZ,
    create_time     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    modify_time     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (review_run_id, aspect)
);

CREATE INDEX IF NOT EXISTS idx_doc_review_status_request ON kb.doc_review_status (request_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_status_run     ON kb.doc_review_status (review_run_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_status_active  ON kb.doc_review_status (request_id)
    WHERE status NOT IN ('success', 'failed');
```

An aspect is **finished iff** its `status` is `success` or `failed`. A review job is
finished — and removed from the monitor — when every one of its aspect rows is finished.

### `kb.doc_review_findings`

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_findings (
    id              BIGSERIAL       PRIMARY KEY,
    input_record_id BIGINT          NOT NULL,  -- the document under review
    review_run_id   TEXT            NOT NULL,  -- idempotency key: "<record_id>_review_<timestamp>"
    pass            TEXT            NOT NULL,  -- "P1".."P6"
    aspect          TEXT            NOT NULL,  -- e.g. "completeness", "grammar", "standards_compliance"
    severity        TEXT            NOT NULL,  -- "high", "medium", "low"
    finding_type    TEXT            NOT NULL,  -- "issue", "missing_requirement", "missing_provision", "inconsistency", "suggestion"
    title           TEXT            NOT NULL,  -- one-line summary
    description     TEXT            NOT NULL,  -- detailed explanation
    evidence        TEXT,                      -- quoted text from the document or reference
    location        JSONB,                     -- {"start_line": 142, "end_line": 148, "page": 7, "chunk_id": "..."}
    reference_doc   JSONB,                     -- {"record_id": N, "title": "...", "doc_no": "...", "section": "..."} (for P5 findings)
    suggestion      TEXT,                      -- recommended fix
    confidence      DOUBLE PRECISION,          -- 0.0–1.0
    metadata        JSONB,                     -- pass-specific extra data
    reviewed_by     TEXT,                      -- human reviewer who accepted/rejected this finding
    review_status   TEXT NOT NULL DEFAULT 'pending',  -- pending, accepted, rejected, deferred, deleted, fixed (deleted/fixed: DR16)
    create_time     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doc_review_findings_record ON kb.doc_review_findings (input_record_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_findings_pass ON kb.doc_review_findings (input_record_id, pass);
CREATE INDEX IF NOT EXISTS idx_doc_review_findings_aspect ON kb.doc_review_findings (input_record_id, aspect);
CREATE INDEX IF NOT EXISTS idx_doc_review_findings_severity ON kb.doc_review_findings (input_record_id, severity);
```

### `kb.doc_review_activities` (DR17)

One row per reviewer correction action (Auto Fix, Edit Tool, finding Delete, and the
three Document-Structure edits). Source for the Document Review Correction Report.
`review_run_id` is NULL for Document-Structure edits (they carry no run); nullable
columns are left NULL when they do not apply to the action.

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_activities (
    id              BIGSERIAL    PRIMARY KEY,
    activity_type   TEXT         NOT NULL,  -- auto_fix | edit_tool | finding_delete | structure_modify | structure_split | structure_delete
    input_record_id BIGINT       NOT NULL,  -- the document under review (kb.inputs.id)
    review_run_id   TEXT,                   -- review run; NULL for run-agnostic Document-Structure edits
    report_id       BIGINT,                 -- latest kb.doc_review_reports.id for the run, when resolvable
    finding_id      BIGINT,                 -- finding targeted (finding-based activities)
    page_number     INT,                    -- Document-Structure target
    line_number     INT,                    -- Document-Structure target
    location        TEXT,                   -- finding line range (e.g. "42", "53-56")
    old_content     TEXT,                   -- before text
    new_content     TEXT,                   -- after text
    detail          JSONB,                  -- extras: title, aspect, severity, model, line_type, ...
    actor           TEXT,                   -- authenticated user name, when available
    create_time     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doc_review_activities_record ON kb.doc_review_activities (input_record_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_activities_run    ON kb.doc_review_activities (review_run_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_activities_report ON kb.doc_review_activities (report_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_activities_type   ON kb.doc_review_activities (activity_type);
```

### Review configuration storage

Review configuration (which aspects to check, models, prompts) is stored in `kb.inputs`
or a dedicated config table, keyed by `input_record_id`. TBD during implementation.

## Reviewer Groups & Example Reviewers

The ~40 reviewers are organized into P1–P6 groups. Below are representative examples from
each group, showing the pattern that all reviewers follow.

### P1 — Language & Style (StrategyChunk, one-shot)

**Example: `grammar_spelling`**

- Strategy: `StrategyChunk`
- Execution: one-shot (`MaxToolTurns = 0`)
- Model: cheap (Haiku / flash)
- Context per chunk: `{"doc_context": "...", "chunk_lines": [...]}`
- Output: findings with `{severity, location, evidence, suggestion}`

Other P1 reviewers (`tone_voice`, `formatting_consistency`, `readability`, `localization`)
follow the same pattern with different prompts.

### P2 — Structure & Organization (StrategyDocument, one-shot)

**Example: `heading_hierarchy`**

- Strategy: `StrategyDocument`
- Execution: one-shot
- Model: strong (Sonnet / Opus)
- Context: full heading tree + summary tree + ToC + doc metadata
- Output: findings about nesting errors, missing sections, ToC inaccuracies

Other P2 reviewers (`logical_flow`, `toc_accuracy`, `navigability`, `section_balance`,
`modularity`) follow the same pattern with the same or subset context.

### P3 — Content Quality (StrategyChunk, tool-use)

**Example: `completeness`**

- Strategy: `StrategyChunk`
- Execution: tool-use (`MaxToolTurns = 5`)
- Model: strong (must support tool use)
- Tools: `search_entities`, `get_entity`, `get_entity_relations`, `search_metrics`,
  `get_metric`, `get_chunk_summary`, `get_chunk_lines`
- Context per chunk:
  ```json
  {
    "doc_context": "...",
    "chunk_lines": [...],
    "chunk_summary": "...",
    "sibling_summaries": [...],
    "entity_roster": [...], "metric_roster": [...], "provision_roster": [...],
    "expected_entities": [...]   // DR6c injection
  }
  ```
- Example trace:
  ```
  Turn 1 LLM: "temperature monitoring device" — are its calibration requirements covered?
              → tool: search_entities("temperature monitoring")
  Turn 1 Go:  returns 3 matching entities
  Turn 2 LLM: Entity E1 has relation "calibrated_by" → entity E5. Does E5 appear in this chunk?
              → tool: get_entity("416_ent_5")
  Turn 2 Go:  E5 is defined in a different chunk, not referenced here.
  Turn 3 LLM: → produces finding: missing_requirement, "Calibration certificate entity not
              referenced in this section (defined at line 203, expected here per ISO 13485 §7.6)"
  ```

Other P3 reviewers (`correctness`, `clarity`, `conciseness`, `relevance`, `currency`,
`examples`, `diagrams`, `testable_claims`, `evidence_rationale`) follow the same pattern
with different prompts and may use different tool subsets.

### P4 — Consistency (StrategyDocument, tool-use)

**Example: `terminology_consistency`**

- Strategy: `StrategyDocument`
- Execution: tool-use (`MaxToolTurns = 8`)
- Model: strong (must support tool use)
- Tools: `search_entities`, `get_entity`, `get_entity_relations`, `get_chunk_lines`
- Context: full entity roster with aliases + line_spans, relation graph summary,
  cross-reference map, summary tree
- Example trace:
  ```
  Turn 1 LLM: "temperature monitoring device" (12 occurrences) vs "temp monitor" (7).
              Shared referent? → tool: get_entity("416_ent_17"), get_entity("416_ent_53")
  Turn 1 Go:  returns both entities — no shared alias, different line spans
  Turn 2 LLM: → produces finding: inconsistency, "Terminology drift — merge or add alias"
  ```

### P5 — Technical & Compliance (StrategyChunk or StrategyDocument, tool-use)

**Example: `standards_compliance`**

- Strategy: `StrategyDocument` (cross-document comparison is inherently document-level)
- Execution: tool-use (`MaxToolTurns = 12`)
- Model: strongest available (must support advanced tool use)
- Tools: all core tools + `search_reference_docs`, `get_reference_roster`,
  `search_reference_provisions`, `check_entity_in_reference`
- Context: document entities/metrics/provisions + `candidate_references` (pre-retrieved
  via DR4)
- Example trace:
  ```
  Turn 1 LLM: Document claims ISO 13485 conformance → get_reference_roster(ref_13485)
  Turn 1 Go:  returns 120 entities, 45 metrics, 82 provisions
  Turn 2 LLM: Reference requires "design_change_control_procedure" → search_entities("design change")
  Turn 2 Go:  returns 0 matches
  Turn 3 LLM: Try alternatives → search_entities("change control")
  Turn 3 Go:  returns "engineering_change_order" — related but incomplete
  Turn 4 LLM: Check reference details → get_entity(ref_13485_ent_23)
  Turn 4 Go:  returns entity + linked provisions requiring review/approval steps
  Turn 5 LLM: → produces finding: missing_provision, severity=high
              "Lacks documented design change control procedure with review/approval steps
              (ISO 13485 §7.3.7). 'engineering_change_order' partially addresses but has
              no associated normative provisions."
  ```

**Example: `technical_accuracy`**

- Strategy: `StrategyChunk`
- Execution: tool-use (`MaxToolTurns = 12`)
- Context: chunk lines + chunk summary + relevant reference excerpts (pre-retrieved)
- Checks: code snippets, formulas, API signatures, config values, CLI commands

Other P5 reviewers (`assumptions`, `prerequisites`, `legal_compliance`,
`regulatory_compliance`, `internal_policy`, `security`, `performance`, `error_handling`,
`limitations`) follow one of these two patterns.

### P6 — Meta & Process (StrategyDocument, one-shot or rule-based)

**Example: `confidentiality`**

- Strategy: `StrategyDocument`
- Execution: one-shot
- Model: strong
- Context: doc metadata + first/last pages
- Plus: rule-based grep for PII patterns, API keys, secrets (no LLM needed)

Other P6 reviewers (`version_history`, `review_status`, `ownership`, `references`,
`related_documents`, `sensitive_data`, `pii`, `data_retention`, `license_ip`) follow
the same pattern.

### DR19 — Report page action bar: consolidated action buttons in the show-mode bar

DR16 added **Regenerate PDF** to the `title-row` header and DR17 added **Correction
Report** there too. With two operational buttons sharing the header alongside the report
title, the header had become a mixed-concern row: a label and two context-sensitive
actions sitting side-by-side with no visual grouping. **Regenerate PDF** was also
conditionally hidden (only shown when `dirty`), making its availability unpredictable to
the reviewer.

**Decision: relocate both action buttons to the `show-mode-bar` row and make them
permanently visible.**

| Before | After |
|--------|-------|
| `[Report Title] [Regenerate PDF?] [Correction Report]` in `title-row` | `title-row` holds the report title only |
| "Regenerate PDF" visible only when at least one finding was Auto Fixed / Edited / Deleted (`dirty`) | "Re-Generate Review Report" always visible |
| "Correction Report" always visible in header | "Generate Change Report" in action bar |

**Layout of the `show-mode-bar` after this change:**

```
[ Show Active ] [ Show All ] │ [ Generate Change Report ] [ Re-Generate Review Report ]
```

A thin vertical separator (`show-mode-sep`, 1 px wide) divides the view-mode toggle
group from the action group, preserving their logical separation while keeping them on
the same toolbar row.

**Renamed buttons:**

| Old label | New label | Functionality |
|-----------|-----------|---------------|
| Correction Report | Generate Change Report | Builds the Document Review Correction Report (Typst → PDF) from `kb.doc_review_activities` via `POST /reports/<id>/correction-report` (DR17). |
| Regenerate PDF | Re-Generate Review Report | Rebuilds the review report JSON / Markdown / Typst PDF from the current non-deleted findings via `POST /reports/<id>/regenerate` (DR16). |

**Why always-visible for "Re-Generate Review Report".** The `dirty` flag only tracked
in-session mutations (Auto Fix, Edit Tool, Delete in the current browser session). A
reviewer opening an existing report that was mutated in a previous session had no
indication the report might be stale, and the button did not appear. Keeping the button
always visible makes regeneration an explicit reviewer choice at any time, at no extra
server cost when nothing has changed (the regeneration is idempotent).

**Visual differentiation.** Action buttons carry the accent fill style (`.action-btn` —
solid accent background, white text, bold weight) while the view-mode toggles remain
ghost buttons. This makes the two functional categories immediately distinguishable at
a glance.

**Frontend-only change.** No backend endpoints, data model, or business logic were
altered. The `dirty` state variable is retained in the frontend (it continues to be set
by mutation callbacks) but no longer gates button visibility.

## Implementation Plan

Development is staged to deliver a working framework early, then add reviewers
incrementally.

### Phase I — Framework + 1–2 simple reviewers ✅ (framework + grammar_spelling + DR3 config done)

1. ✅ **Database migration:** `kb.doc_review_findings` table + indexes.
2. ✅ **Reviewer interface + framework:** `Reviewer` interface, `ReviewerConfig`,
   `ReviewProcessor`, goroutine fan-out in PostProcessIndex, findings persistence.
3. ✅ **First reviewer:** `grammar_spelling` (P1, one-shot, cheap model, per-window).
4. ✅ **On-demand invocation:** `review_document` registered in `main.go`, excluded from
   `config.toml` `required_processors`. Invoked via `operation: ["review_document"]`.
5. ☐ **Second reviewer:** `confidentiality` (P6, one-shot + rule-based PII grep).
6. ☐ **End-to-end test:** Process a known document through the full workflow (parse →
   extract artifacts → review → collect findings).
7. ✅ **DR3 per-aspect configuration (2026/06/23):** `doc-review.local.toml` with
   `[packages.P1..P6]` group defaults and `[reviewers.<aspect>]` blocks for all ~40
   aspects. Config loaded at startup via `GetDocReviewConfig()` (walks up from CWD,
   `sync.Once` cached). `ResolveReviewer(aspect, group)` merges group defaults → per-
   aspect overrides. `NewReviewProcessor` reads config exclusively from the TOML file; if no model
   name or prompt is specified in its configuration, `NewReviewProcessor` treats
   it as an error and disables the reviewer.
   Code in `server/api/doc-processing/review-config.go`. Note: per-review-run TOML
   and `reference_docs` are out of scope; request-level `model_overrides` JSONB is
   persisted but not yet applied at execution time (DR11 gap).

### Phase II — 1–2 moderate reviewers

1. **Tool registry:** `ReviewTool` interface + core tool implementations.
2. **Tool-use execution path:** `runToolUseReview` conversation loop with budget
   enforcement.
3. **Second reviewers:** `completeness` (P3, tool-use, chunk-based) and
   `terminology_consistency` (P4, tool-use, document-level).

### Phase III — 1–2 complex reviewers

1. **Cross-document tools:** P5 tool set (`search_reference_docs`, `get_reference_roster`,
   `search_reference_provisions`, `check_entity_in_reference`).
2. **Reference retrieval (DR4):** Category-path overlap + entity-name dictionary +
   hybrid search pipeline.
3. **Third reviewers:** `standards_compliance` (P5, tool-use, cross-document) and
   `technical_accuracy` (P5, tool-use, chunk-based).

### Phase IV — Expand P3/P4/P5 coverage

Add remaining reviewers in P3 (correctness, clarity, conciseness, relevance, testable_claims),
P4 (internal_contradictions, cross_reference_correctness, requirement_traceability), and
P5 (assumptions, prerequisites, legal_compliance, regulatory_compliance, security,
performance, error_handling, limitations).

### Phase V — Complete all reviewers

Add remaining P1, P2, and P6 reviewers. Cost optimization (DR8 Phase 2) can run in
parallel — tune `MaxToolTurns`, downgrade models where quality is preserved, add caching
for text-only reviewers.

### Phase VI — Review Service Layer (DR11–DR13) ✅ (DR13 implemented)

1. ✅ **`kb.doc_review_requests` table** — database migration, indexes. Includes
   `requester_name`, `requester_id`, `report_template`, `doc_template` fields.
2. ✅ **`kb.doc_review_reports` table** — database migration, indexes.
3. ✅ **`DocReviewController`** — request validation, reviewer resolution (by tier, by
   individual aspect), reviewer config override merging, request lifecycle state
   machine, delegation to `ReviewProcessor`, trigger report generation.
4. ✅ **Review aspect/tier API** — `GET /api/doc-review/aspects` and
   `GET /api/doc-review/tiers` endpoints, loaded from the checklist spec [1].
5. ✅ **`POST /api/doc-review/requests`** — submit a review request, persists to
   `kb.doc_review_requests`, kicks off the review (synchronously). Returns `request_id`.
6. ✅ **`GET /api/doc-review/requests/<id>`** — pollable status endpoint that returns
   findings when complete.
7. ✅ **`DocReviewReportGenerator`** — assembles the report JSON skeleton from findings
   + metadata, delegates executive summary to LLM (one-shot), computes compliance
   summary from finding counts, renders Markdown export.
8. ✅ **`GET /api/doc-review/reports/<id>`** and `.../export`** — report retrieval and
   Markdown/JSON/HTML export endpoints.
9. ✅ **`PATCH /api/doc-review/findings/<id>`** — accept/reject/defer individual findings.
10. ✅ **Review Request GUI (home3 Apps → Document Review)** — document selector,
    tier picker, individual aspect checkboxes, supporting document search, notes field,
    model override expandable.
11. ✅ **Results page (inline in Document Review view)** — polling progress indicator,
    summary cards (by severity), filterable findings table with accept/reject
    actions, full report view with export buttons.

### Phase VII — Configurable tiers (DR14) + per-aspect status & live monitor (DR15)

1. ✅ **DR14 — Configurable review tiers** — `[doc-reviews]` config table in
   `config.toml`/`config.local.toml`, merged at startup, with priority-derived
   fallback. (`server/api/docreview/aspects.go`, `server/cmd/config/config.go`)
2. ✅ **DR15 — `kb.doc_review_status` table** — goose migration
   `20260621000003_create_doc_review_status.sql`; one row per `(review_run_id,
   aspect)`; partial index for the active-jobs query.
3. ✅ **DR15 — assign `review_run_id` at accept**; seed `pending` status rows for
   every aspect in `AcceptRequest`. The run id is passed into
   `ReviewProcessor.ReviewRunID` so findings share it.
4. ✅ **DR15 — per-aspect transitions (coarse, controller-driven)** — `markAspectsRunning`
   at run start; `finalizeAspectsSuccess` (with per-aspect finding counts) on
   completion; `failOpenAspects` on whole-run failure / stop. Per-reviewer live
   transitions deferred (Phase-I `ReviewProcessor` runs only `grammar_spelling`).
5. ✅ **DR15 — async execution** — `SubmitRequest` accepts + seeds, then runs the
   review in a background goroutine (detached context); the submit response returns
   immediately so the monitor can observe in-flight jobs.
6. ✅ **DR15 — `GET /api/v1/doc-review/active`** — lists jobs with ≥1 unfinished
   aspect + per-aspect status; request marked `completed` when all aspects finish.
7. ✅ **DR15 — global monitor** — `doc-review-monitor.svelte` polls `/active`,
   renders one card per job atop the Document Review form, and drops finished jobs.

## Tests

- **Reviewer interface:** a mock reviewer implementing the `Reviewer` interface can be
  registered, launched by the framework, and its findings collected.
- **Context assembly:** each reviewer receives the correct artifact subset for a known record.
- **Per-chunk aggregation:** findings from multiple chunks merged without duplicates.
- **Missing-compliance:** reference entity/metric present in reference standard but absent
  in document-under-review correctly flagged.
- **Idempotency:** re-running review replaces findings, matching `review_run_id`.
- **Model fallback:** primary model failure → fallback model attempt (reuse existing pattern).
- **Tool registry:** each tool's JSON Schema is valid and its Execute returns correctly
  typed results.
- **Conversation loop:** simulated LLM responses with tool calls → Go executes correct
  tool → results fed back → loop terminates with findings.
- **Budget enforcement:** when `MaxToolTurns` is exhausted, force-produce prompt is
  appended and findings are returned. When `MaxToolTokens` is exceeded, outstanding tool
  calls are rejected with a budget-exhausted message.
- **Stop handling:** `CheckAndHandleStop` at each LLM call boundary in the conversation
  loop correctly interrupts mid-investigation, persists partial findings, and returns
  `ErrPipelineStopped`.
- **Structured output contract:** LLM response with both tool calls and findings in the
  same message is rejected as malformed.
- **DocReviewController — reviewer resolution:** selecting "Must Review" tier enables
  exactly the 12 aspects mapped at that tier; custom selection enables only the checked
  aspects.
- **DocReviewController — override merging:** per-request model override for P5 replaces
  the P5 default but leaves P1–P4 defaults untouched.
- **DocReviewController — state machine:** accepted → running; running → completed (with
  findings) or failed (with error_message); stop request during running transitions to
  stopped.
- **DocReviewController — idempotency:** re-submitting a review for the same document
  version replaces the previous request and its findings.
- **DocReviewReportGenerator — JSON skeleton:** report structure conforms to the DR12a
  schema. Count fields (total_findings, high_count, etc.) match the underlying findings.
- **DocReviewReportGenerator — compliance summary:** provision counts by relationship
  label are deterministic given a fixed set of findings.
- **DocReviewReportGenerator — Markdown export:** produces valid Markdown with correct
  heading hierarchy matching the JSON report sections.
- **GUI — form submission:** valid request returns `request_id` and status `accepted`.
  Missing document or zero aspects selected returns 4xx.
- **GUI — findings accept/reject:** `PATCH /api/doc-review/findings/<id>` updates
  `review_status` and `reviewed_by`.
- **GUI — report export:** requesting `?format=pdf` returns an `application/pdf` response
  with valid PDF bytes.

## Consequences

- **Positive:** SemOS gains its first LLM-powered document review capability. The
  reviewer-per-aspect design is naturally extensible — adding a new aspect means writing
  one reviewer, no changes to existing ones. The unified `Reviewer` interface makes the
  framework simple: launch N goroutines, collect findings, generate report. The missing-
  compliance check (DR6) addresses the core use case directly. Human-in-the-loop gates
  (steps 3 and 5 in DR9) ensure the LLM reviews operate on clean input. Staged
  development delivers a working framework in Phase I, validates the approach on real
  documents in Phases II–III, and reaches full coverage in Phases IV–V. DR11–DR13
  (Phase VI) provide the user-facing GUI, coordinator, and report generator that make
  the review service usable by document owners without engineering involvement.
- **Negative / risk:** Quality is gated on prompt engineering — early runs may produce
  noisy findings. Mitigated by iterative prompt refinement on real documents and the
  human accept/reject loop. P5 reference retrieval quality depends on the reference
  standard corpus coverage — if a needed reference is not in SemOS, compliance checks
  will be incomplete. The large number of concurrent reviewers (~40 goroutines, each
  potentially making per-chunk LLM calls) could strain API rate limits; the framework
  should support a configurable max-concurrent-LLM-calls bound. The Phase VI GUI adds
  a long-running synchronous request path — if review takes minutes, the HTTP connection
  must be handled with care (SSE polling or a background task pattern).
- **Cost:** Per-document cost scales with (enabled reviewers × document length × model
  choice). Phase I–II costs are low (1–4 reviewers). Phase V with all 40 reviewers
  enabled would be substantial — mitigation via DR8 Phase 2 (model downgrades, caching,
  token budgeting), DR8a DeepSeek prefix-cache-aware prompt layout, and user-selectable
  aspect filtering. The report generator adds one
  cheap LLM call per review (executive summary). The GUI adds no API cost beyond existing
  HTTP endpoints.

## Implementation Files
All the code files related to doc reviewers should be in `ChenWeb/server/api/doc-reviews`.

## Documentation Impact

- New spec: `KnowledgeStore/Capsules/coding-capsules/doc-processor/document-review-spec.md`
- New implementation doc: `KnowledgeStore/Capsules/coding-capsules/doc-processor/document-review-impl.md`
- Updated: `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` (add to pipeline table)
- Updated: [1] with implementation references
- Updated: `KnowledgeStore/doc-repo/specs/202606/2026061101-spec-skill-review-document.md` — superseded by this ADR
- New: `server/api/doc-reviews/review-config.go` — DR3 config loading + merging (2026/06/23; relocated from `doc-processing`)
- New: `doc-review.local.toml` — per-aspect reviewer configuration for all ~40 aspects
- New: `server/api/doc-reviews/review-formatting-consistency.go` — `formatting_consistency` reviewer (P1, 2026/06/23)
- New: `prompts/prompt-review-formatting-consistency.md` — `formatting_consistency` reviewer prompt
- New: `server/api/doc-processing/review_exports.go` — exported shim of doc-processing internals for the relocated reviewers (2026/06/23)
- Updated: `KnowledgeStore/doc-repo/design/202606/2026062105-design-doc-review-gui.md` — §4.5 DeepSeek prompt cache strategy
- New: `server/api/doc-reviews/review_framework_aliases.go` — binds shim to local names in the `docreviews` package (2026/06/23)
- Moved: all `server/api/doc-processing/review-*.go` → `server/api/doc-reviews/` (package `docprocessing` → `docreviews`, 2026/06/23)
- New: `server/api/doc-reviews/auto_fix.go` — DR16 line-file editor, LLM Auto Fix (`AUTO_FIX_MODEL_NAME`/`AUTO_FIX_CALLBACK`), Edit Tool save, and report regeneration (2026/06/24)
- New: `web/src/lib/components/home3/edit-tool-dialog.svelte` — DR16 Edit Tool find/replace dialog, with suggestion display, auto-sizing multi-line offending-line fields, and the DR16a suggestion-split **Accept** button (2026/06/24)
- Updated: `server/api/doc-reviews/handler.go`, `server/api/routes.go` — DR16 endpoints (`/findings/<id>/auto-fix`, `/findings/<id>/lines`, `/findings/<id>/edit`, `/reports/<id>/regenerate`)
- Updated: `server/api/doc-reviews/controller.go` — `UpdateFinding` allow-list extended with `deleted`+`fixed` (DR16)
- Updated: `web/src/routes/home3/doc-review-report/[id]/+page.svelte`, `web/src/lib/services/docReviewService.ts` — DR16 finding actions, Regenerate PDF, and collapsible package → reviewer grouping with per-reviewer local scrollbar
- New: `project_migrations/20260624000001_create_doc_review_activities.sql` — `kb.doc_review_activities` table + indexes (DR17, 2026/06/24)
- New: `server/api/docactivity/activity.go` — DR17 leaf package: activity-type constants, `Log` (best-effort), `List` (2026/06/24)
- New: `server/api/doc-reviews/correction_report.go` — DR17 `GenerateCorrectionReport` (activities → Typst → PDF) (2026/06/24)
- New: `docs/doc-templates/template-correction-report.typ` — DR17 Correction Report Typst template (`#document-correction-report`) (2026/06/24)
- New: `docs/doc-review-correction-report.md` — DR17 feature doc (activity log + Correction Report) (2026/06/24)
- Updated: `server/api/doc-reviews/auto_fix.go`, `controller.go` — DR17 activity logging in `AutoFixFinding`, `ApplyFindingEdit`, and `UpdateFinding` (delete) (2026/06/24)
- Updated: `server/api/kbhandler/doc_structure_handler.go` — DR17 activity logging in `UpdateDocStructureLine` / `SplitDocStructureLine` / `DeleteDocStructureLine` (2026/06/24)
- Updated: `server/api/doc-reviews/handler.go`, `server/api/routes.go` — DR17 `POST /reports/<id>/correction-report` endpoint (2026/06/24)
- Updated: `mise.local.toml` — `DOC_REVIEW_CORRECTION_TEMPLATE_FILENAME` (DR17)
- Updated: `web/src/routes/home3/doc-review-report/[id]/+page.svelte` — DR19: relocated 'Generate Change Report' and 'Re-Generate Review Report' buttons from `title-row` to `show-mode-bar`; always-visible; accent-fill `.action-btn` style; visual separator between toggle group and action group (2026/06/24)
- New: `server/api/doc-reviews/review-relevance.go` — `relevance` reviewer (P3, StrategyChunk, one-shot, 2026/06/25)
- New: `prompts/prompt-review-relevance.md` — `relevance` reviewer prompt (2026/06/25)
- Updated: `server/api/doc-reviews/review-document.go` — `RelevanceClient`/`RelevanceModelName`/`RelevancePromptRef`/`RelevancePromptText` fields; resolution in `NewReviewProcessor`; wiring in `buildReviewers` (2026/06/25)
- Updated: `doc-review.local.toml` — `[reviewers.relevance]` enabled (2026/06/25)
- New: `server/api/doc-reviews/review-currency.go` — `currency` reviewer (P3, StrategyChunk, one-shot, 2026/06/25)
- New: `server/api/doc-reviews/review-currency_test.go` — `currency` reviewer test (2026/06/25)
- New: `prompts/prompt-review-currency.md` — `currency` reviewer prompt (2026/06/25)
- Updated: `server/api/doc-reviews/review-document.go` — `CurrencyClient`/`CurrencyModelName`/`CurrencyPromptRef`/`CurrencyPromptText` fields; resolution in `NewReviewProcessor`; wiring in `buildReviewers` (2026/06/25)
- Updated: `doc-review.local.toml` — `[reviewers.currency]` enabled (2026/06/25)
- **Stale:** none (new capability; in-tree references updated)

## References
[1] `KnowledgeStore/doc-repo/specs/202606/2026061102-spec-document-review-checklist.md` — Document Review Checklist

[2] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` — Doc Processor Pipeline

[3] `KnowledgeStore/Capsules/coding-capsules/llm-wiki/artifact-connections.md` — Artifact Connections

[4] `KnowledgeStore/doc-repo/specs/202604/2026042101-spec-line-file.md` — Line File Spec

[5] ADR 2026061702 — Decouple Relation Extraction (concurrent Phase B pattern reused)

[6] ADR 2026061701 — Entity Reconciliation (entity-name dictionary reused for DR6)

[7] `KnowledgeStore/doc-repo/specs/202606/2026061101-spec-skill-review-document.md` — Original skill proposal (superseded)

[8] ADR 2026062203 - Document Review Report Generation
