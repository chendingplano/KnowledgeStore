# ADR 

**Date:** 2026-07-12 \
**Status:** Proposal \ 
**Component:** xxx \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/12, ADR Created

## Context
- Doc Processor: `extract_metrics`
- input_record_id: 244
- Model: 'deepseek-flash-chen'
- Prompt: 'ChenWeb/prompt-extract-metric-candidates-v4.md'
- Number of Runs: the same processor ran twice

Following are some of the failures in extracting metrics.

### Case 01
- Line: 88
- Content: "1) 24 h 平均收缩压、舒张压、心率，24 h最高及最低收缩压，发生时间；24 h最高及最低舒张压，发生时间。"

Detected metrics:
- 24小时最低舒张压
- 24小时最高收缩压发生时间
- 24小时最低收缩压发生时间
- 24小时最高舒张压发生时间
- 24小时最低舒张压发生时间

The metrics the second run detected:
- 24小时最高舒张压

Missed metrics:
- 24 h 平均收缩压
- 24 h 平均舒张压
- 24 h 平均心率

**Analysis**

Line 88 is followed by two very similar lines:
- "2) 白天平均收缩压、舒张压、心率，白天最高及最低收缩压，发生时间；白天最高及最低舒张压，发生时间。" (Line 89)
- "3) 夜间平均收缩压、舒张压、心率，夜间最高及最低收缩压，发生时间；夜间最高及最低舒张压，发生时间。" (Line 90)
- "4) 清晨平均收缩压、舒张压、心率，清晨最高及最低收缩压，发生时间；清晨最高及最低舒张压。" (Line 91)

All metrics are extracted correctly.

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
