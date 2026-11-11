# Document reviewers — errors abort the affected reviewer

**Date:** 2026-11-11 (America/Chicago) \
**Scope:** Existing reviewer error propagation, dispatch, progress, and unsupported reference selection. \
**Code root:** `ChenWeb/server/api/doc-reviews`

## Summary

A failed model call used to look like a completed review with no findings. The
reviewers now return errors, log the failure, and stop their remaining work.
Other independent reviewers can continue. Output from a failed reviewer is not
presented as successful findings, and a reviewer becomes successful only after
its findings have been saved.

Finding no comparison candidates, or completing a review with no findings, is
normal. Missing input, failed searches, malformed responses, and failed tool calls
are errors. A configured chunk reviewer cannot fall back to blocks or a document
call. Existing reviewers explicitly configured for blocks keep that behavior.

The new compliance reviewer remains a design proposal. Its independence, per-chunk
execution, and absence of fallback are recorded in the
[research document](../../research/202611/2026111103-rsch-compliance-reviewer.md)
and [processor capsule](../../../Capsules/coding-capsules/doc-processor/+CAPSULE.md).
The [document-review specification](../../specs/202606/2026062104-spec-document-review.md)
carries the current failure contract.

## Details

`review-document.go` defines error-returning chunk/block interfaces and progress
callbacks. `review_cache_scheduler.go` cancels work by aspect, retains the original
failure, and discards successful findings from earlier units of a failed reviewer.
`review-artifact-window.go` and the direct review coordinator cancel their workers
on error. Cross-record comparisons use `searchengine.Search`; a missing source
index is an error, while a completed search with no matches is normal.

`review-tool-loop.go` returns errors for failed tools, invalid arguments or output,
provider failures, and exhausted investigation budgets. Output caps that leave required
units unassessed return `ErrReviewOutputLimit`, without advancing their progress. It makes no model repair
or forced-finalization calls after those errors. Locally parsing a valid response
with supported JSON normalization remains allowed. `review-findings-validation.go`
requires a findings array with valid finding objects; an empty array is accepted.

`review_status_store.go` keeps unit progress provisional and explicitly finishes
an aspect after persistence. Failed progress and completion writes are errors.
An overall run can fail while independent successful aspects retain their status.
Incomplete per-unit audit records can remain for diagnosis; they are not a
successful review result.

The UI temporarily removes supporting-document selection and explains this in
English and Chinese. The API rejects nonempty `reference_docs` with HTTP 422;
previously accepted selections fail explicitly instead of being silently ignored.
Historical selections are preserved. This feature needs authorization checks and
tested input delivery before it can be enabled.

## Verification and limits

Regression coverage includes model and tool failure, malformed output, budgets,
reviewer-local cancellation and deadlines, discarded failed-reviewer findings,
unsupported chunk dispatch, completed empty results, selected-reference rejection,
and progress/terminal-status persistence.

Verification passed on 2026-11-11:

- `go test ./server/api/doc-reviews ./server/api/doc-processing ./server/api/searchengine -count=1`.
- Focused `go test -race ./server/api/doc-reviews` for scheduling, error propagation, cancellation, and tool-loop regressions.
- `mise build-server`.
- `bun run check`: zero errors/warnings; i18n valid.
- Reusable-module catalogue check: in sync; whitespace checks clean.

Database-backed tests retain their opt-in requirements; the database-specific
review status integration tests were skipped when their test database was absent.
No model-backed legal accuracy evaluation or production deployment is claimed.

## Documentation impact

Knowledge changed: reviewer completion requires successful execution and durable
results. Updated: the research document, capsule, document-review specification,
this devdoc, and the Artifact Search module record. The provision-reviewer devdoc
now points here for the updated failure semantics. Older architecture descriptions
in the review specification remain historical where this failure contract
supersedes them. No new reusable module, schema, endpoint, or compliance engine was
created. Existing reviewer/search infrastructure was extended in place.
