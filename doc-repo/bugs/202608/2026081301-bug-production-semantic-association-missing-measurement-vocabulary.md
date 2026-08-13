# Production `associate_semantics` has no released measurement vocabulary

Date: 2026-08-13

Status: open

System: `ChenWeb` document processing / SemOS ontology

Component: `ontology-seed`, `associate_semantics`, production database bootstrap

Related: [metric assertion and semantic processing manual](../user-manuals/metric-assertion-semantic-processing-v1.1-en.md),
`ChenWeb/server/api/ontology/assertions/associate_semantics.go`,
`ChenWeb/server/cmd/ontology-seed/main.go`

## Summary

Running `associate_semantics` for input record 416 in the production `miner`
database produced no rows in `kb.semantic_assertions` or
`kb.assertion_evidence`.

The normal command paths are using the correct database:

- `mise dev` in `ChenWeb` resolves `PG_DB_NAME=miner`.
- `mise doc-process-run` in `ChenWeb/server/cmd/doc-processor` resolves
  `PG_DB_NAME=miner`.
- `chenweb_test` is selected by benchmark/test tooling, not by these normal
  service commands.

The production database is missing the released curated `measurement` ontology
module. It contains auto-promoted metric-definition terms, but it does not
contain the released assertion vocabulary required by `associate_semantics`.

## Expected behavior

The documented path is:

```text
extract_metrics
    -> kb.metrics
    -> metric identity resolution
    -> metric_definition_term_id
    -> normalize_assertions
    -> kb.semantic_decision_candidates
    -> associate_semantics
    -> kb.semantic_assertions + kb.assertion_evidence
```

For a parseable metric candidate with a resolved subject, `associate_semantics`
should accept the claim when the governed measurement terms are available.

## Actual behavior

For input record 416 in `miner`:

| Result | Count |
|---|---:|
| `kb.metrics` rows | 66 |
| metric decision candidates | 66 |
| accepted semantic assertions | 0 |
| evidence rows | 0 |

Candidate deferrals were:

| Deferral reason | Count |
|---|---:|
| `no_governed_assertion_kind_term:unparsed` | 37 |
| `unresolved_referent` | 20 |
| `no_governed_assertion_kind_term:exact_value` | 6 |
| `governed_term_not_released:mea:measured_by,mea:lower_bound_requirement` | 3 |

The last three candidates demonstrate the production vocabulary problem. The
association code checks for:

```text
mea:measured_by
mea:lower_bound_requirement
```

with `status = 'included_in_release'`. Neither term exists in `miner`.

## Database evidence

The production database currently has:

```text
kb.ontology_modules:
  core
  quantity

kb.ontology_module_releases:
  core@1.0.0
  quantity@1.0.0

kb.ontology_terms:
  core: ... included_in_release
  quantity: ... included_in_release
  measurement: ... auto-promoted metric_definition terms
```

It does not have a `measurement` row in `kb.ontology_modules`, a
`measurement@1.0.0` release, or the curated `mea:*` terms from
`server/cmd/ontology-seed/content.go`.

The `measurement:auto:kwc_*` terms attached to the 416 metrics are different
records. They are metric-definition identities created by the metric-name
resolution path. They do not create the assertion predicate or assertion-kind
vocabulary.

## Root cause

This is a production ontology bootstrap defect:

1. `ontology-seed` is a separate command and is not run by `mise dev` or
   `mise doc-process-run`.
2. Database migrations create ontology tables but do not install the curated
   measurement module.
3. The production database was never seeded and released with the measurement
   module.
4. The standalone `ontology-seed` command has an inconsistent environment
   contract: it reads `PG_USER`, while `mise.local.toml` defines
   `PG_USER_NAME`. It also defaults `PG_DB_NAME` to `chenweb_test` when the
   variable is absent.
5. The `mise run ontology-compiler` task explicitly exports
   `PG_DB_NAME=chenweb_test`, making it unsafe as a production bootstrap path.

This is not caused by the normal services connecting to `chenweb_test`, and it
is not caused by the `auto-promoted` status of the metric-definition terms.
`auto-promoted` terms are intended to be usable metric identities. The
association gate is a separate check for released curated predicate and
assertion-kind terms.

## Additional implementation gap affecting record 416

After a candidate is deferred, `AssociateSemantics.Run` selects only rows in
`candidate` or `in_review` status. It does not reprocess existing
`deferred` rows merely because a governed term was later released.

The existing `/kb/semantic-decisions/drain-deferred` path only targets
`unresolved_referent` candidates and re-normalizes them. It does not drain
candidates deferred because a governed term was unavailable.

Therefore, installing the measurement module fixes future runs, but it does not
by itself provide a complete supported retry path for the three existing
governed-term deferrals from record 416.

The other 63 candidates have independent blockers: unparsed values, the
currently unsupported `exact_value` assertion kind, or unresolved subjects.

## Correct production bootstrap

The measurement module should be authored, released, and activated against
`miner`, using the standalone seed command with explicit environment mapping:

```bash
cd /Users/cding/Workspace/ChenWeb

mise exec -- sh -c '
  PG_USER="$PG_USER_NAME" \
  PGPASSWORD="$PG_PASSWORD" \
  PG_DB_NAME="$PG_DB_NAME" \
  go run ./server/cmd/ontology-seed --module measurement
'
```

The post-bootstrap checks should show:

- `kb.ontology_modules.module_id = 'measurement'`;
- an active `measurement@1.0.0` release; and
- `mea:measured_by` and the supported `mea:*` assertion-kind terms with
  `status = 'included_in_release'`.

The command is idempotent for the curated seed content and should be part of a
documented production deployment/bootstrap procedure. It should not be
silently run on every application startup without an explicit ownership and
release policy for ontology content.

## Remediation needed

1. Bootstrap and verify the curated `measurement` module in `miner`.
2. Make the ontology CLI accept the same PostgreSQL environment naming as the
   services, or add a production-safe mise task that maps
   `PG_USER_NAME -> PG_USER` and never defaults to `chenweb_test`.
3. Add a deployment preflight or health check that verifies the required active
   measurement release before semantic association is enabled.
4. Add a governed-term dependency-fingerprint retry path for candidates
   deferred because a required ontology term was not released.
5. Decide whether accepted semantic assertions should carry a direct
   `metric_definition_term_id` reference. The current implementation keeps the
   metric identity on `kb.metrics` and only carries the metric name as an
   assertion qualifier; this is documented as a current limitation.
6. Add an integration test that runs the complete metric path against a freshly
   seeded database and verifies the expected assertion/evidence rows.

## Disposition

Open. No code fix has been applied by this bug investigation. The production
ontology bootstrap and the deferred governed-term retry behavior remain owed.
