# ADR 2026070602 — Provisions Reviewer: Mandatory Comparison Analyses

**Date:** 2026-07-06 \
**Status:** Accepted — implemented 2026/07/06 \
**Component:** ChenWeb — `server/api/doc-reviews`, `prompts` \
**Authors:** Chen Ding \
**Tags:** document reviewer, provisions, cross-document consistency, tool-use loop, DeepSeek

---

## Change Logs
* 2026/07/06, ADR created and implemented.

## Context

The provisions reviewer (ADR 2026063003 [4]) compares each provision extracted from
the document under review against semantically-matched provisions from other
documents, and reports cross-document conflicts as `findings`. In production
(`doc-review.local.toml`, `max_tool_turns = 4`) it runs through the shared tool-use
conversation loop (`runToolUseReview`, `review-tool-loop.go`).

A review transcript surfaced a problem with this design: when the LLM concludes there
is **no conflict**, it still performs a substantive comparison — same subject or not,
identical or reworded text, notable differences in the surrounding context (e.g. a
peer document's neighboring clauses using different thresholds or a different
edition) — and then discards all of that reasoning, because the prompt only asks for
`findings` and an empty conflict list serializes to `{"findings": []}`. The comparison
happened, but nothing about it is retained. This is true even though the reviewer's
underlying value is largely in that comparison, not only in the conflicts it happens
to find.

The fix has two parts: (1) make the prompt require a record of the comparison
regardless of outcome, and (2) make sure that record actually survives the code path
it runs through, including the tool-use loop, rather than being dropped a layer
lower the same way it was dropped by the LLM output before.

## Decision

### DR1 — Prompt v4: mandatory `analyses` alongside `findings`

`prompt-review-provisions-v4.md` (new; supersedes `prompt-review-provisions-v2.md` as
the active prompt) adds a required `analyses` array to the output contract: **one
entry per candidate in `matching_provisions`**, always populated, independent of
whether anything rises to a finding. Each entry records:

- `related_artifact_id` / `related_record_id` — which matched provision this is about.
- `relationship` — `same_subject | related_subject | unrelated`.
- `summary` — 1-3 sentences: what was compared (text, and surrounding context when
  informative), and the conclusion, even when the conclusion is "identical, no issue."

`findings` keeps its existing meaning unchanged: confirmed conflicts, outliers,
currency signals, extraction errors, and unverified-but-plausible discrepancies. The
prompt is explicit that `findings: []` is a legitimate empty result, but `analyses`
must never be empty when `matching_provisions` is non-empty — an empty `analyses` is
a prompt-contract violation, not "no issues."

Two intermediate prompt drafts (`v2`, still the previously active one, and `v3`,
which merely added a `zh`-language variant field) predate this change and were left
untouched; `v4` is additive to `v2`'s structure, not a rewrite.

### DR2 — Tool-use loop: parallel payload-returning entry point

The provisions reviewer runs with `max_tool_turns = 4` in production, so it goes
through `runToolUseReview` (`review-tool-loop.go`), which is also used by 21 other
reviewers (P3 text reviewers and several P5 artifact reviewers). That loop's response
parsing (`parseFindingsContentDetailed`, used at its three possible exit points: a
normal tool-free response, the budget-exhausted finalize call, and the JSON-repair
retry) extracts only the `findings` key from the raw model JSON and throws the rest
away. Requesting `analyses` in the prompt alone would not have been sufficient — it
would have been parsed by the LLM correctly and then discarded by this shared code,
reproducing the exact problem one layer down.

Three options were considered for exposing the raw payload to the provisions
reviewer:

1. **Full generic refactor** — change `runToolUseReview`'s public return signature to
   include the raw payload for all 22 call sites. Most "correct" long-term (any
   tool-use reviewer could read sibling fields later) but the largest blast radius —
   every existing reviewer's call site and its behavior would need re-verifying for a
   feature only one reviewer needs today.
2. **Disable tool-use for provisions** — set `max_tool_turns = 0` so it falls back to
   the simple `ExtractJSON` path (`review-provisions.go`), where reading a sibling
   JSON key is trivial. Zero risk to shared code, but gives up the
   `get_artifact_context` verification step (ADR 2026070201 AR4) for provisions.
3. **Parallel entry point (chosen)** — extract the loop's internal implementation so
   it also returns the raw payload of whichever response ultimately produced the
   findings, keep the existing `runToolUseReview` (3-tuple: findings, usage, error)
   as an unchanged-behavior wrapper for the 21 other call sites, and add a new
   `runToolUseReviewWithPayload` (4-tuple, payload included) for the provisions
   reviewer to call instead.

Option 3 was chosen: it gives the provisions reviewer everything it needs without
touching the contract or behavior of any other reviewer.

Concretely, every function in the loop's call chain gained a `WithPayload` sibling
that threads a `map[string]any` alongside the existing `[]ReviewFinding`, while the
original functions became thin wrappers that call the new one and drop the payload
(this preserves existing direct unit tests of `runToolUseReview`, `finalizeFindings`,
and `parseFindingsContentDetailed`, which assert their original tuple shapes):

```text
runToolUseReview(...)              ([]ReviewFinding, *LLMUsage, error)              — public, 21 existing callers, unchanged behavior
runToolUseReviewWithPayload(...)   ([]ReviewFinding, map[string]any, *LLMUsage, error) — new; provisions reviewer only

finalizeFindings(...)              ([]ReviewFinding, *LLMUsage, error)              — kept for its direct unit tests
finalizeFindingsWithPayload(...)   ([]ReviewFinding, map[string]any, *LLMUsage, error) — new core implementation

repairFinalFindingsJSON            → renamed repairFinalFindingsJSONWithPayload (4-tuple; not directly unit-tested, no wrapper needed)
callFinalFindingsRepair            → renamed callFinalFindingsRepairWithPayload (4-tuple; not directly unit-tested, no wrapper needed)

parseFindingsContentDetailed(...)            ([]ReviewFinding, bool, string)              — kept for its direct unit tests
parseFindingsContentDetailedWithPayload(...)  ([]ReviewFinding, map[string]any, bool, string) — new core implementation
```

`parseFindingsContent` (the two-value convenience wrapper used only inside the main
loop body) was left as-is; the main loop's tool-free response branch now calls
`parseFindingsContentDetailedWithPayload` directly instead.

### DR3 — Persistence: new table, not a re-used one

The comparison analyses are structurally different from findings (guaranteed
one-per-match rather than zero-or-more-per-conflict, no severity/suggestion/evidence
fields) and are not meant to appear in the existing findings-driven report UI. Rather
than overload `kb.doc_review_findings` with a synthetic `finding_type` to carry them
(which would conflate routine comparison records with genuine observations and pollute
report queries filtered by `finding_type`), they get a dedicated table:
`kb.doc_review_provision_analyses`, scoped to `input_record_id` + `run_id` like every
other doc-review artifact.

Persistence happens directly inside `provisionsReviewer.reviewProvision` via
`saveProvisionAnalyses`, using the same `run_id` already threaded through
`context.Context` for LLM-call metadata (`llmRunIDFromContext`, aliased from
`docprocessing.LLMRunIDFromContext`). A missing `db` handle or a context with no
`run_id` (both occur in unit tests) causes the save to no-op rather than error or
panic, since `run_id` is `NOT NULL` and there is nothing meaningful to insert without
it.

### Alternative Decisions
- **Log-only (no schema change):** rejected — analyses would be visible in logs but
  not queryable, and would not survive log rotation, defeating the point of retaining
  them.
- **Fold into findings as `finding_type: "observation"`:** rejected — would force
  every "no conflict" comparison through the existing findings pipeline/report UI as
  a low-confidence observation, conflating "we checked and it's fine" with genuine
  low-confidence findings, and inflating finding counts in the report.
- **Full tool-use-loop refactor (all 22 callers):** rejected for this change (see
  DR2) — correct long-term, unnecessary blast radius today. Revisit if a second
  tool-use reviewer needs sibling-key access.

### Database Migrations
New table, `project_migrations/20260706000001_create_doc_review_provision_analyses.sql`:

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_provision_analyses (
    id                  BIGSERIAL    PRIMARY KEY,
    input_record_id     BIGINT       NOT NULL,
    run_id              BIGINT       NOT NULL,
    prov_id             TEXT         NOT NULL,
    related_artifact_id TEXT,
    related_record_id   BIGINT,
    relationship        TEXT         NOT NULL,
    summary             TEXT         NOT NULL,
    create_time         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
-- + indexes on input_record_id, run_id, prov_id
```

No changes to `kb.doc_review_findings` or any other existing table.

### Data Formats

**LLM output** (`prompt-review-provisions-v4.md`), `analyses` entry:

```json
{
  "related_artifact_id": "2002_prv_9",
  "related_record_id": 2002,
  "relationship": "same_subject | related_subject | unrelated",
  "summary": "concise comparison: textual match, context differences, and why this does or does not rise to a finding"
}
```

**Go representation** (`review-provisions.go`):

```go
type ProvisionAnalysis struct {
    RelatedArtifactID string
    RelatedRecordID   int64
    Relationship      string
    Summary           string
}
```

`parseProvisionAnalysesJSON` reads `payload["analyses"]` the same way
`normalizeFindingsJSON` reads `payload["findings"]`; entries with an empty `summary`
are dropped rather than persisted as noise.

### Environment Variables
None new.

## Implementation

### Code Changes

| File | Change |
|---|---|
| `ChenWeb/prompts/prompt-review-provisions-v4.md` | New prompt: adds the mandatory `analyses` array (DR1). |
| `ChenWeb/doc-review.local.toml` | `reviewers.provisions.prompt` → `prompt-review-provisions-v4.md`. |
| `ChenWeb/server/api/doc-reviews/review-tool-loop.go` | Added `runToolUseReviewWithPayload`, `finalizeFindingsWithPayload`, `repairFinalFindingsJSONWithPayload` (renamed from `repairFinalFindingsJSON`), `callFinalFindingsRepairWithPayload` (renamed from `callFinalFindingsRepair`), `parseFindingsContentDetailedWithPayload`. `runToolUseReview`, `finalizeFindings`, `parseFindingsContentDetailed`, `parseFindingsContent` kept as unchanged-behavior wrappers (DR2). |
| `ChenWeb/server/api/doc-reviews/review-provisions.go` | New `ProvisionAnalysis` type, `parseProvisionAnalysesJSON`, `saveProvisionAnalyses`. `reviewProvision` now calls `runToolUseReviewWithPayload` (tool-use branch) or captures `out` directly (`ExtractJSON` branch), and persists any parsed analyses after building findings (DR1/DR3). |
| `ChenWeb/project_migrations/20260706000001_create_doc_review_provision_analyses.sql` | New table `kb.doc_review_provision_analyses` (DR3). |
| `ChenWeb/server/api/doc-reviews/review-tool-loop_test.go` | Unchanged — existing tests assert the original 3-tuple functions' behavior, which is now delegated to the new `WithPayload` implementations. |
| `ChenWeb/server/api/doc-reviews/review-provisions_test.go` | New: `TestParseProvisionAnalysesJSON`, `TestParseProvisionAnalysesJSON_NoAnalysesKey`, `TestReviewProvision_SavesAnalyses` (sqlmock, asserts the INSERT fires through the full `reviewProvision` path). |

## Operational Behaviors
- **No matches for a provision:** unchanged — no LLM call, no findings, no analyses.
- **`analyses` absent or empty in the LLM response** (e.g. still running under
  `prompt-review-provisions-v2.md`, or a model that ignores the instruction):
  `parseProvisionAnalysesJSON` returns nil, `saveProvisionAnalyses` is not called.
  Findings behavior is completely unaffected either way.
- **No `run_id` in context, or no `db` handle** (unit tests; a reviewer instantiated
  without a DB): `saveProvisionAnalyses` no-ops silently rather than failing the
  review. Findings are still returned normally.
- **Analysis persistence failure** (DB error mid-insert): logged as a warning and
  swallowed — it must not fail the provision's findings, which are the primary
  reviewer output.
- **Tool-use loop for the other 21 reviewers:** byte-for-byte unchanged behavior;
  `runToolUseReview` is now a wrapper but its observable contract (return values,
  error conditions, retry/repair behavior) is identical to before this change.

## Consequences

**Positive**
- The reviewer's comparison reasoning is retained for every matched provision, not
  only for the subset that becomes a finding — closing the gap the review transcript
  exposed.
- Zero behavioral or risk change for the 21 other tool-use reviewers; the shared loop
  gained a capability without changing its existing contract.
- `analyses` and `findings` remain cleanly separated: report queries filtered by
  `finding_type`/`severity` are unaffected by this change.

**Negative / cost**
- One more LLM-output field to hold the model to; a model that ignores the
  instruction degrades silently to "no analyses persisted" rather than failing loudly
  — acceptable per Operational Behaviors, but means prompt-adherence issues could go
  unnoticed without evaluation/monitoring on `analyses` coverage.
- `kb.doc_review_provision_analyses` is not yet surfaced by any report or UI — it is
  captured and durable, but only queryable directly today (see Documentation Impact).
- Slight duplication in `review-tool-loop.go`: two parallel signatures per function in
  the chain (`X` and `XWithPayload`). Accepted as the lower-risk option over changing
  22 call sites (DR2, Alternative Decisions).

## Tests
- `TestParseProvisionAnalysesJSON` — parses a mixed `analyses` array, confirms an
  entry with an empty `summary` is dropped.
- `TestParseProvisionAnalysesJSON_NoAnalysesKey` — payload without an `analyses` key
  returns nil (backward compatible with `v2`/`v3` prompt output).
- `TestReviewProvision_SavesAnalyses` — sqlmock-backed, drives `reviewProvision` with
  a fake JSON extractor returning both `findings` and `analyses`, asserts the exact
  `INSERT INTO kb.doc_review_provision_analyses` call with `run_id` taken from
  context.
- Full existing `runToolUseReview*` / `finalizeFindings` / `parseFindingsContent*`
  test suite (`review-tool-loop_test.go`) re-run unchanged and passing, confirming
  the wrapper refactor preserved behavior for the other 21 reviewers.
- `go build ./...` and `go test ./server/api/doc-reviews/...` clean after the change.

## Documentation Impact
- This ADR is the design record for the `analyses` mechanism; ADR 2026063003 [4]
  remains the design record for the reviewer's core matching/comparison logic (Branch
  A/B retrieval, dedup, cap) and is unchanged by this ADR.
- **Resolved by later ADRs:** ADR 2026062203 §1.2 added the report section for
  `kb.doc_review_provision_analyses` (grouped per-artifact alongside findings), and
  ADR 2026070604 extends this `analyses` mechanism to the metrics and
  inventory-items reviewers (ADR 2026063002, ADR 2026063005), which share the
  provisions reviewer's artifact-comparison architecture and prompt shape. ADR
  2026070604 is a Proposal as of this writing — not yet implemented.

## References
- [1] ADR 2026061801 — Document Review: LLM-Powered Multi-Aspect Review Pipeline
- [2] ADR 2026062804 — Document Review: `kb.doc_review_runs` — First-Class Run Table
- [3] ADR 2026070201 — Document Review: Artifact Reviewer Context, Prompt-Cache Layout, and Missing-Metric Detection (AR4/AR5: tool-use and prompt-v2 groundwork for provisions/metrics/inventory-items)
- [4] ADR 2026063003 — Cross-Document Provision Consistency Reviewer (`KnowledgeStore/doc-repo/adrs/202606/2026063003-adr-doc-reviewer-provisions.md`)
- [5] ADR 2026063002 — Cross-Document Metric Consistency Reviewer
- [6] ADR 2026063005 — Cross-Document Inventory-Item Consistency Reviewer
- [7] `ChenWeb/prompts/prompt-review-provisions-v4.md`
- [8] `ChenWeb/server/api/doc-reviews/review-tool-loop.go`
