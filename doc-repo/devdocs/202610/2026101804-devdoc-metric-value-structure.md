# Metric values — preserve alternatives and collections without inventing assertions

**Date:** 2026-10-18 \
**Scope:** How metric extraction preserves the meaning of multiple values and protects numeric consumers. \
**Code root:** `ChenWeb/server/api/doc-processing`, `server/api/metricvalue`, `server/api/ontology/assertions`

## Summary

A metric may legitimately have several values. “Available diameters: 10, 20 or 30 mm” describes a
choice, while “inspect at 10, 30 and 50 mm” requires every listed point. Neither means three
unrelated equalities. The earlier one-value-per-row policy could lose that distinction.

Extraction now splits only independently interpretable assertions. “Male: 300 mm; female: 250 mm”
still becomes two rows with the correct conditions. Alternatives and mandatory point collections
stay together, carrying an explicit description of their relationship. Composite sizes and
expressions remain whole. When the source's relationship is unclear, the complete value remains
available for review instead of being forced apart.

This resolves four concerns together: preserve value-to-condition mappings; prevent numeric
consumers from guessing a scalar; support structured collections alongside scalars; and make
benchmark annotation and scoring follow the same meaning-preserving boundaries.

## Where things live

- Candidate prompt v30 and enrichment prompt v29 apply the same boundary rules. Combined values
  without a valid interpretation get one evidence-based review with an explicit split, keep or
  unresolved decision. Keeping a legitimate collection is successful processing, not an error.
- `value_structure` is an optional JSON field on production and benchmark metrics. The existing
  `metric_value` remains the complete display text. Metric APIs, reference copies, artifact
  snapshots, review input and merge resolution retain both. Different relationships cannot merge.
- The normalizer accepts only complete supported numeric forms. Unsupported collections,
  composites, expressions and ambiguous text become unparsed; they never become the first number.
  Existing simple scalar, interval and supported tolerance handling remains available.
- Benchmark rules 10.0.0 and scoring version 5 account for relationships and every collection
  member. Earlier rule files remain available unchanged. Reordering an unordered set is harmless;
  replacing it with its first member, a continuous interval or a different relationship is not.

## Contract and implementation plan

The OpenSpec change is `ChenWeb/openspec/changes/semantic-metric-values/`:

- `proposal.md` explains the problem and scope.
- `design.md` records the representation, recovery decisions and consumer boundaries.
- `tasks.md` records implementation and verification.
- `specs/metric-value-structure/spec.md`, `specs/metric-row-granularity/spec.md` and
  `specs/metric-value-notation/spec.md` define the behavior.

These specs are the contract: update them when behavior changes, not just this devdoc. After
archiving, consult the corresponding canonical files under `ChenWeb/openspec/specs/`.

## Deployment and limitations

Apply project migration `20261018000003_add_metric_value_structure.sql` before running the updated
worker or API against a database. It adds nullable fields to `kb.metrics` and `testbed.metrics`;
existing rows remain unchanged. Startup runs the project migration through the existing mechanism.
The active prompts are candidate v30, enrich v29 and merge v4; remove or update production env
overrides pointing at older prompts. The worker's embedded defaults include the new versions.
Scoring uses the workspace's updated benchmark/scoring skill scripts and app scoring prompt v5.

Numeric comparison of collections is deliberately deferred. A retained collection is useful
evidence even when the comparison engine cannot yet calculate a verdict for it. Conservative
parsing may also defer older compound values and uncommon notation that used to yield a partial,
potentially misleading number. Source interpretation still depends on the model; numeric and
evidence checks cannot prove arbitrary semantic equivalence.

This implementation does not repair historical extractions or derived assertions. Previously
split alternatives and first-number reductions require explicit re-extraction and semantic
reprocessing after deployment. Historical benchmark runs also retain their original granularity;
new comparisons should use the same gold rules and scoring version. No production deployment or
reprocessing was performed as part of this change.
