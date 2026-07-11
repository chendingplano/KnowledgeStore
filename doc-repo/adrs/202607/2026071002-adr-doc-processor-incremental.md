# ADR Incremental Update Artifacts in Doc Processors

**Date:** 2026-07-10 \
**Status:** Proposal \ 
**Component:** xxx \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/10, ADR Created

## Context
Doc processors are all idempotent, which is achieved by removing all
the records a doc processor generated for the given input record 
(note: doc processors always run with a given input record), then
insert the extracted artifacts into the table for the given input record.

This ADR applies to the following doc processors:
- `extract_metrcs`
- `extract_provisions`
- `extract_inventory_items`
- `extract_entity_relation`

## Decision
### DR1 
Add a flag for doc processor run: `force_clear`. When a doc processor
is launched manually, the frontend allows users to specify whether to
`force_clear` or not. If `force_clear` is true, it works as before.
Otherwise, it updates the database (see DR2).

If a doc processor is run automatically by the pipeline, its `force_clear`
is always set to false.

### DR2
When `force_clear` is false:
- Do not delete the artifacts generated so far for the given input record. 
  Instead, read them in.
- Merge the existing artifacts and the ones extracted by this run.

#### Metric Groups
Two or more metrics form a Metric Group if they share at least one common line.

#### Merge Rules for Metrics:
Rule-1: Two metrics A and B are the same if their fields that are listed below are the same:
- `metric_name`
- `source_line_spans`
- `metric_subject`
- `metric_unit`
- `threshold_or_target`
- `metric_value`
- `value_data_type`
- `value_range_type`
- `value_class`
- `metric_categories`

For each newly extracted artifact A:
Rule-2: If A and an existing metric are the same, ignore A.

Rule-3: If A's line span does not overlap with any of the existing 
metrics, add A to the existing metric set

Rule-4: Otherwise, find a Metric Group by 
- If a newly extracted artifact has the same line span with an existing
  artifact, they are treated the same. Merge the two artifacts: 
  - if a field has no value in the existing artifact but the newly
    extracted artifact has, copy the value to the existing artifact.
  

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