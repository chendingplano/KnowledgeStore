# LLM Cache Optimization

**Date:** 2026-07-03 \
**Status:** Implemented \
**Component:** ChenWeb/server/api/doc-processing \
**Authors**: Chen Ding \

## Change Logs
* 2026/07/03, ADR Created

## Context
When processing a new doc, the runtime will make N LLM calls with the input simultaneously:
```
<prompt> + <chunk>
```
where N is the number of chunks. Since this is a fresh call to the doc, chunks are
definitely new to the LLM, which means it will most likely miss the cache. But all the
N LLM calls share the same prompt. The size of prompts is normally lower thousands, 
such as 2000-3000. This mounts up to 2000 x 20 = 40,000 bytes for a 20 chunk document.

If we make one LLM call, wait LLM_CALL_STAGGER seconds, then make the rest of the LLM
calls simultaneously, it results to:
- First call: cache hit = 0, cache miss =  2,000 + 2,000 (assume prompt size: 2,000 and chunk size: 2,000)
- Subsequent calls: cache hit = 2,000 x 19, cache miss = 2,000 x 19

It converts 38,000 cache miss to cache hit.

## Decision
When processing a doc processing request with one or more doc processors:
- pick the first processor
- make an LLM call for the first chunk
- wait LLM_CALL_STAGGER seconds
- make LLM calls for the rest of the chunks simultaneously
- wait LLM_CALL_STAGGER seconds
- make LLM calls for all the processors, each with all the chunks

### Alternative Decisions

### Database Migrations

### Data Formats

### Environment Variables

## Implementation

### Code Changes

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-processing/chunk_batch_coordinator.go` | `scheduleChunkBatch()` — Phase 1 split into 1a (seed chunk 0 only) + stagger (1b) + remaining seed chunks (1c) |
| `ChenWeb/server/api/doc-processing/chunk_batch.go` | `ChunkBatchProcessor` interface comment updated to describe the new four-phase algorithm |

## Operational Behaviors 

## Consequences

## Tests

## Documentation Impact

## Consequences

## References
