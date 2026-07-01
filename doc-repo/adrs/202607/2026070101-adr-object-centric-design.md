# ADR 2026070101 - Object Centric Design

**Date:** 2026-07-01 \
**Status:** Proposal \ 
**Component:** xxx \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/01, ADR Created

## Context
This is about the artifacts (refer to [1]) and their hybrid search.

### Problem 1
For artifacts, such as `metrics`, `inventory_items`, and `provisions`,
as it is now, are extracted alone. These artifacts are, however, do not
make much sense without relating to the objects they apply. For instance, 
for a metric: 'max-pressure' = 100, it does not make any sense without
mentioning the object the metric applies to. If we are talking about the max
pressure on liquit gas tanks, 'liquit gas tank' should be an integral part
of the metric. 

The same is true for other artifacts.

### Problem 2
For `topics`, it is true that topics do make sense on their own. But from 
the '

## Decision
### DR1 


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
- [1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md