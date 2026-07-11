# ADR - Looping over a Doc Processor

**Date:** 2026-07-11 \
**Status:** Proposal \ 
**Component:** xxx \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/11, ADR Created

## Context
Almost all doc processors use LLMs to extract/generate artifacts, such as 
metrics, summaries, provisions, etc. LLMs are undeterministic. The same
LLM, same prompt, same input, the artifacts a doc processor extracts
vary. It may fail extracting some artifacts, but re-run it, it may extract
them.

## Decision
### DR1 - Add a Loop to a Doc Processor
When a doc processor (refer to [1] for doc processors) runs, 
it does not just run once, but N times.
Running a doc processor is done by running M goroutines
in parallel, where M is the number of slices (windows) of the input,
and each goroutine handles one slice.

Here is the algorithm:
- Run the doc processor once
- Collect the results and cache them
- If N > 1, run the doc processor N - 1 times in parallel. That is,
  running the remaining (N - 1) * M goroutines.
  Note that the first run should cache the inputs, the prompt.
  The subsequent run should be cheap.
- Collect the results from the LLM calls. Log and ignore the failed
  LLM calls.
- Merge and resolve the collected results using the algorithm documented in [2].

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
[2] KnowledgeStore/doc-repo/adrs/202607/2026071002-adr-doc-processor-incremental.md