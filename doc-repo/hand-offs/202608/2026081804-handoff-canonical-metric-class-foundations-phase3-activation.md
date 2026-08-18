# Canonical Metric Class Foundations — Phase 3 Activation Handoff

**Date:** 2026-08-18  
**Status:** ADR `2026081701` foundations certified in shadow mode; no writer activation

## Delivered

Stable term/class identity and current-term compatibility, append-only contracts and
resolution decisions, observed-profile storage, canonical claim identities, assertion
class references, redirects, duplicate-support cleanup, metric-only support cardinality,
shadow reports, compatibility tests, and capacity evidence are complete.

## Writer-gate handoff point

The next owner is `lossless-semantic-processing` Phase 3. It may consume the
foundation APIs and shadow reports, but it must keep both
`LOSSLESS_SEMANTIC_WRITES_METRIC` and `LOSSLESS_SEMANTIC_FALLBACK_WRITES` false
until its direct metric writer passes its own complete acceptance suite.

Before a target environment receives the metric-support unique index, run the
auditable duplicate-support cleanup against that environment's existing data.
No migration or rollback may delete evidence, claims, profiles, or redirects.

## Open policy choices

- Approval policy and actor for autonomous provisional-class/contract activation.
- Human review and cutover policy for canonical-key convergence, collisions, class
  merges/splits, and redirect supersession.
- Retention/compaction policy for raw metric fragments and bounded shadow details.
- Default Review Document filtering and severity policy for represented/outlier rows.

## Documents requiring follow-up

- The v1.2 metric manual describes the certified shadow foundations but its legacy
  accepted-assertion path remains the current writer behavior until Phase 3.
- ADR `2026081801` and the pre-existing Phase 0/1 handoff have local uncommitted
  edits outside this change; review and commit them independently.
- The capacity report `2026081804` and certification `2026081805` are the current
  operational evidence for this handoff.
