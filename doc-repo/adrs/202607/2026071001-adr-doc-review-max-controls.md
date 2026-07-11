# ADR Document Review Improvements

**Date:** 2026-07-10 \
**Status:** Implemented \ 
**Component:** ChenWeb Document Review \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/10, ADR Created
* 2026/07/11, Implementation completed and verified

## Context
**Problem-01**\
During document review, some reviewers (such as metrics, provisions and inventory items)
retrieve related artfacts for a given artifact-under-review. The max number of 
matched artifacts is controlled by env vars, such as:
- PROVISION_REVIEW_MAX_MATCHES
- ENTITY_REVIEW_MAX_MATCHES
- INVENTORY_REVIEW_MAX_MATCHES

These matched artifacts are useful, but if we pass too many to LLM,
it may generate too much findings/analyses. It will not only make the
review reports too big for people to consume, but also consume too many
tokens.

## Decision

### DR1
Will add a new env var: MAX_MATCHES_TO_LLM, defaults to 3.
This env var controls the max number of retrieved matches to
pass on to the LLM.

### DR2
Add Review Depth in document requests. Allowed values are 1 (default), 
2, and 3.

### DR3
Add the following configuration items in `ChenWeb/doc-review.local.toml`:
- 'max_findings', which defaults to [100, 200, 300], which means if
  Review Depth = 1, its 'max_findings' is 100; Review Depth = 2, its
  'max_findings' is 200, and Review Depth = 3, its 'max_findings' is 300.
  This attribute controls the max number of findings a reviewer generates. 
  Note that this max limit is
  imposed softly: when this number reaches the max, no new goroutines 
  will be launched, if any, since reviewers run LLM in parallel.
  The final results may exceed the max limit. It should log the ones
  that are canceled due to the max limit.
- 'max_analyses', which defaults to [100, 200, 300]. Its meaning is similar
  to 'max_findings'. 'Analyses' means either a finding is not error.
  It requires (normally) no actions, such as 'similarity analysis', 
  'difference analysis', etc.

Note that these two configuration items can be at the global level (i.e.), 
apply to all reviewers and reviewer level, which overrides the global
ones. They are optional both at the global and the reviewer level.

### Alternative Decisions
- Keep using only retrieval-side caps. Rejected because retrieval breadth and
  LLM payload size are different controls with different tradeoffs.
- Hard-stop reviewers exactly at the configured maximum. Rejected because
  reviewers already run work in parallel, so a soft cap preserves completed
  units while preventing new launches after the threshold is reached.

### Database Migrations
- Added `project_migrations/20260710000001_add_doc_review_request_depth.sql`.
- Added `review_depth INT NOT NULL DEFAULT 1` to
  `kb.doc_review_requests`.
- Added check constraint:
  `CHECK (review_depth BETWEEN 1 AND 3)`.

### Data Formats
- `POST /api/v1/doc-review/requests` now accepts `review_depth`.
- Allowed values are `1`, `2`, and `3`.
- Missing or zero values normalize to `1`.
- Other values are rejected with HTTP 422.
- Request status payloads now include `review_depth`.

### Environment Variables
- Added `MAX_MATCHES_TO_LLM`, default `3`.
- Existing reviewer retrieval env vars such as
  `PROVISION_REVIEW_MAX_MATCHES`,
  `ENTITY_REVIEW_MAX_MATCHES`, and
  `INVENTORY_REVIEW_MAX_MATCHES`
  remain responsible for retrieval breadth rather than LLM payload breadth.

## Implementation

### Code Changes
- Added depth-indexed output-limit config resolution for document reviewers.
- Added persisted request-level `review_depth` handling in API, model, SQL,
  restart, and stalled-run recovery paths.
- Added LLM-side related-artifact truncation through `MAX_MATCHES_TO_LLM`
  while preserving broader retrieval for ranking and matching.
- Added a shared output scheduler/work gate that enforces soft limits for
  findings and analyses before launching more work.
- Propagated resolved output limits to all relevant reviewers.
- Added frontend review-depth selection and request submission support.
- Fixed frontend type/check blockers discovered during implementation so the
  document review UI changes could be validated cleanly.

## Operational Behaviors 
- Review depth selects depth-indexed `max_findings` and `max_analyses`
  values using built-in defaults `[100, 200, 300]` unless overridden in
  `doc-review.local.toml`.
- The checked-in local test configuration uses `[10, 20, 30]`.
- Limits are soft: after the threshold is reached, no new goroutines are
  launched for additional units, but already-running work may still complete.
- Skipped launches are logged.
- Restarted and recovered reviews reuse the original stored request depth.
- Reviewer retrieval breadth remains independent from LLM payload breadth.

## Consequences
- Review output size and token usage are more predictable.
- Operators can tune review intensity through request depth instead of
  changing per-reviewer code or prompts.
- Existing clients remain compatible because omitted `review_depth`
  preserves depth-1 behavior.
- Some final result counts may still exceed the configured soft caps due to
  in-flight concurrent work, which is intentional.

## Tests
- Added/updated tests for:
  - depth-indexed config inheritance and validation
  - request review-depth persistence and lifecycle behavior
  - restart and stalled-run recovery retaining review depth
  - LLM match-cap enforcement
  - output-limit propagation and scheduler gating
  - frontend request typing and UI submission behavior
- Verification completed with:
  - `go test ./server/api/doc-reviews ./server/cmd/config`
  - `go build ./server/api/doc-reviews ./server/cmd/config`
  - `cd web && APP_BASE_URL=http://127.0.0.1:8080 bun run check`
  - `cd web && APP_BASE_URL=http://127.0.0.1:8080 bun run build`

## Documentation Impact
- This ADR now records the implemented behavior.
- Design and implementation planning artifacts were also written under
  `ChenWeb/docs/superpowers/specs/2026-07-10-doc-review-max-controls-design.md`
  and
  `ChenWeb/docs/superpowers/plans/2026-07-10-doc-review-max-controls.md`.
- Frontend and operational behavior around review depth and output limits
  should now be treated as current behavior rather than proposal.

## Consequences
- The system now separates:
  - how many related artifacts are retrieved
  - how many are passed to the LLM
  - how much reviewer output is allowed to expand at each review depth
- This makes review runs more tunable without losing contextual retrieval.

## References
- `ChenWeb/docs/superpowers/specs/2026-07-10-doc-review-max-controls-design.md`
- `ChenWeb/docs/superpowers/plans/2026-07-10-doc-review-max-controls.md`
- `ChenWeb/project_migrations/20260710000001_add_doc_review_request_depth.sql`
