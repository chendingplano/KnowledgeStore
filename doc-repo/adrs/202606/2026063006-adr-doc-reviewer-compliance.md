# ADR 2026060306 — Standard Compliance

**Date:** 2026-06-30 \
**Status:** Proposal \ 
**Component:** xxx \
**Authors**: Chen Ding \
**Tags**: Document Reviewer, Standard Compliance \

## Change Logs
* 2026/06/30, ADR Created

## Context
When a document is added to the knowledge base, the system extracts metrics, entities, relations and other artifacts from the document via the doc processors (refer to [1]).

This document reviewer assumes the document-under-review, identified by record_id (kb.inputs.id), has already been processed by all doc processors. The reviewer is configured as reviewers.metrics (group P5) in [2].

## Decision

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
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md
[2] ChenWeb/doc-review.local.toml
[3] KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md (run model) and ChenWeb/server/api/doc-reviews/review_cache_scheduler.go (dispatch)