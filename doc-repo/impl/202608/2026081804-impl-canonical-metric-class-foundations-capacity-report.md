# 2026081804 — Canonical Metric Class Foundations: Capacity and Exception Report

**Date:** 2026-08-18  
**Status:** Task 8.4 evidence complete; lossless metric writer remains disabled  
**Implements:** ADR `2026081701`; OpenSpec `canonical-metric-class-foundations`

## Evidence

The read-only corpus baseline was rerun against the active database on 2026-08-18.

| Measure | Result |
|---|---:|
| Metric occurrences | 7,074 |
| Metric-bearing records | 58 |
| Duplicate current metric supports | 17 |
| Metrics without a current support | 7,020 (99.24%) |
| Projected foundation storage | 17.3 MiB |
| Projected full lossless storage worst case | 36.6 MiB |

The corpus-scale scratch-database test also passed at the active configured caps:

| Measure | Result |
|---|---:|
| Write 21,222 envelopes / 1,011 findings | 6.064 s (3,500 envelopes/sec) |
| Idempotent replay | 2.715 s (2,606 replays/sec) |
| Retry sweep | 9 ms |
| Completeness projection over 7,074 artifacts | 71 ms |
| Outcomes relation / indexes | 16.3 MiB / 9.0 MiB |

## Capacity and rollback decision

The current caps remain acceptable: profile examples 25, redirect traversal 16,
canonical-key shadow detail 1,000 rows, and same-class review retrieval 20 rows. The
foundation tables and shadow reports are additive. Rollback disables readers and writer
gates; it retains migrated history, evidence, claims, profiles, and redirects.

## Exceptions retained for Phase 3

- Existing corpus evidence still contains 17 duplicate metric-support occurrences. The
  auditable cleanup must execute before the new partial unique index is applied to an
  environment containing those rows.
- 7,020 source metrics are not yet reachable through current support evidence. This is
  the lossless-writer migration objective, not a justification to enable its gate.
- Source-backed class terms are sparse; shadow reports surface unavailable source-class
  candidates for later provisional/ambiguous resolution.
- No writer gate changed: `LOSSLESS_SEMANTIC_WRITES_METRIC` remains disabled.

## Reproduction

```bash
cd ~/Workspace/ChenWeb
mise exec -- go run ./server/cmd/semantic-baseline/ --format markdown
SEMANTIC_LOAD_TEST=1 TEST_DATABASE_URL='<libpq template database DSN>' \
  go test ./server/api/ontology/semantic -run TestIntegrationLoadTestCorpusScale -v -timeout 30m
```
