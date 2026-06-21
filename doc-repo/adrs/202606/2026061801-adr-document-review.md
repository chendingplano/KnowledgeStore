# ADR 2026061801 — Document Review: LLM-Powered Multi-Aspect Review Pipeline

**Date:** 2026-06-18 \
**Status:** Proposal \
**Component:** ChenWeb, Doc Processor — document_review \
**Authors:** Chen Ding \
**Tags:** doc processor, document review, compliance, quality assurance

---

## Change Logs
* 2026/06/18, ADR Created.

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
| **P1 — Language & Style** | Surface-level writing quality | `grammar_spelling`, `tone_voice`, `formatting_consistency`, `readability`, `localization` | Per-chunk |
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

Each reviewer manages its own internal concurrency and context assembly. The framework
only calls `ReviewDocument(ctx, recordID, cfg)` and collects the `[]ReviewFinding`.

### DR3 — Per-reviewer configuration

Each reviewer is independently configured. Configuration is per-document-review-run,
stored alongside the review request:

```toml
[doc_review.reviewers.grammar_spelling]
enabled = true
model_ref = "claude-haiku-4-5"
prompt = "prompt-review-grammar.md"
max_tool_turns = 0          # 0 = one-shot (no tools)

[doc_review.reviewers.standards_compliance]
enabled = true
model_ref = "claude-sonnet-4-6"
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

## Data Model

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
    review_status   TEXT NOT NULL DEFAULT 'pending',  -- pending, accepted, rejected, deferred
    create_time     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doc_review_findings_record ON kb.doc_review_findings (input_record_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_findings_pass ON kb.doc_review_findings (input_record_id, pass);
CREATE INDEX IF NOT EXISTS idx_doc_review_findings_aspect ON kb.doc_review_findings (input_record_id, aspect);
CREATE INDEX IF NOT EXISTS idx_doc_review_findings_severity ON kb.doc_review_findings (input_record_id, severity);
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

## Implementation Plan

Development is staged to deliver a working framework early, then add reviewers
incrementally.

### Phase I — Framework + 1–2 simple reviewers ✅ (framework + grammar_spelling done)

1. ✅ **Database migration:** `kb.doc_review_findings` table + indexes.
2. ✅ **Reviewer interface + framework:** `Reviewer` interface, `ReviewerConfig`,
   `ReviewProcessor`, goroutine fan-out in PostProcessIndex, findings persistence.
3. ✅ **First reviewer:** `grammar_spelling` (P1, one-shot, cheap model, per-window).
4. ✅ **On-demand invocation:** `review_document` registered in `main.go`, excluded from
   `config.toml` `required_processors`. Invoked via `operation: ["review_document"]`.
5. ☐ **Second reviewer:** `confidentiality` (P6, one-shot + rule-based PII grep).
6. ☐ **End-to-end test:** Process a known document through the full workflow (parse →
   extract artifacts → review → collect findings).

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

## Consequences

- **Positive:** SemOS gains its first LLM-powered document review capability. The
  reviewer-per-aspect design is naturally extensible — adding a new aspect means writing
  one reviewer, no changes to existing ones. The unified `Reviewer` interface makes the
  framework simple: launch N goroutines, collect findings, generate report. The missing-
  compliance check (DR6) addresses the core use case directly. Human-in-the-loop gates
  (steps 3 and 5 in DR9) ensure the LLM reviews operate on clean input. Staged
  development delivers a working framework in Phase I, validates the approach on real
  documents in Phases II–III, and reaches full coverage in Phases IV–V.
- **Negative / risk:** Quality is gated on prompt engineering — early runs may produce
  noisy findings. Mitigated by iterative prompt refinement on real documents and the
  human accept/reject loop. P5 reference retrieval quality depends on the reference
  standard corpus coverage — if a needed reference is not in SemOS, compliance checks
  will be incomplete. The large number of concurrent reviewers (~40 goroutines, each
  potentially making per-chunk LLM calls) could strain API rate limits; the framework
  should support a configurable max-concurrent-LLM-calls bound.
- **Cost:** Per-document cost scales with (enabled reviewers × document length × model
  choice). Phase I–II costs are low (1–4 reviewers). Phase V with all 40 reviewers
  enabled would be substantial — mitigation via DR8 Phase 2 (model downgrades, caching,
  token budgeting) and user-selectable aspect filtering.

## Documentation Impact

- New spec: `KnowledgeStore/Capsules/coding-capsules/doc-processor/document-review-spec.md`
- New implementation doc: `KnowledgeStore/Capsules/coding-capsules/doc-processor/document-review-impl.md`
- Updated: `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` (add to pipeline table)
- Updated: [1] with implementation references
- **Stale:** none (new capability)

## References
[1] `KnowledgeStore/doc-repo/specs/202606/2026061102-spec-document-review-checklist.md` — Document Review Checklist

[2] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` — Doc Processor Pipeline

[3] `KnowledgeStore/Capsules/coding-capsules/llm-wiki/artifact-connections.md` — Artifact Connections

[4] `KnowledgeStore/doc-repo/specs/202604/2026042101-spec-line-file.md` — Line File Spec

[5] ADR 2026061702 — Decouple Relation Extraction (concurrent Phase B pattern reused)

[6] ADR 2026061701 — Entity Reconciliation (entity-name dictionary reused for DR6)
