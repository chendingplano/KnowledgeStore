# ADR Document Review Improvements

**Date:** 2026-07-10 \
**Status:** Proposal \ 
**Component:** xxx \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/10, ADR Created

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

### Database Migrations

### Data Formats

### Environment Variables

## Implementation

### Code Changes

## Operational Behaviors 

## Consequences

## Tests

## Documentation Impact

## Consequences

## References
