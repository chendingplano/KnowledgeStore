# Doc Process DAG Management Implementation

**Date:** 2026-08-10 \
**Status:** Implemented \
**Component:** ChenWeb — `kbhandler` Doc Process DAG API, `kb.pipelines`/`kb.pipeline_rules`/`kb.pipeline_bindings` lifecycle, `home3` System Admin page \
**Authors**: Claude Code

## Change Logs
* 2026/08/10, Document created.
* 2026/08/10, Bug fix: list responses dropped the `processors` key for DAGs
  with an empty processor set (Go `omitempty`), crashing the DAG page render
  (frozen "Loading…"). The field is now always emitted (`[]` for empty sets).

## Purpose

This document records the implementation completed for the **Doc Process DAG
management** feature — the composite-object CRUD surface (API + browser page)
that treats a doc process pipeline, its processor DAG, and its knowledge-store
bindings as one atomic unit.

It complements:

- ADR 2026081001 — `2026081001-adr-pipeline-policy-versioning-and-dependency-graph.md` (specifically DR8 and DR10)
- OpenSpec change — `ChenWeb/openspec/changes/doc-process-dag-management/` (proposal, design, spec, tasks)

It focuses on:

- what was implemented
- how the six functional requirements map to code
- how the "exactly one system default" invariant is enforced
- how write operations are validated before save and protected by transactions
- what was verified (unit tests + live smoke test)
- what was intentionally left out of scope

## Summary

The ADR 2026081001 introduced versioned `kb.pipelines`, `kb.pipeline_rules`
(gates + `depends_on_processors` DAG edges), and read-only
`kb.pipeline_bindings`, replacing the single-row `kb.pipeline_policies` model.
Until this change, those tables could only be manipulated through low-level
endpoints (the legacy pipeline / rules handlers and the bootstrap seed tool).

This change adds a **Doc Process DAG** composite object on top of those tables,
with a dedicated handler that owns the whole pipeline-version + rules +
bindings lifecycle as one atomic unit, plus a browser page under:

- `home3 > System Admin > Doc Process Pipeline > Doc Process DAG`

The page lets an operator search, view, create, modify, and delete Doc Process
DAGs, choose which one is the system default, and inspect the processors, DAG
gates, and knowledge-store bindings of any DAG.

## Functional Requirements → Implementation

The six user requirements and where each is enforced:

### 1. Search / view / create / modify / delete

Implemented as a full REST surface (all behind the existing JWT/Kratos auth):

- `GET  /api/v1/kb/doc-process-dags` — list; optional `?search=` matches `name` or `display_name`
- `POST /api/v1/kb/doc-process-dags` — create (v1 authored inside a transaction)
- `GET  /api/v1/kb/doc-process-dags/:name` — detail: current version + rules + bindings
- `PUT  /api/v1/kb/doc-process-dags/:name` — modify
- `DELETE /api/v1/kb/doc-process-dags/:name` — delete (all versions + rules + bindings)
- `GET  /api/v1/kb/doc-process-processors` — the `docprocessing.RegisteredProcessors()` catalog for the page's editor

> **Contract guarantee (fix, 2026-08-10):** the list/detail responses always
> emit the `processors` array, including `[]` for DAGs whose processor set is
> empty (the three legacy rows `legacy_default`, `store_default`,
> `request_override` have `{}` in `kb.pipelines`). Previously the field used
> Go's `omitempty`, which dropped the key entirely for those rows; the
> frontend's `DocProcessDag` type requires `processors`, so the render threw a
> `TypeError` and Svelte 5 aborted the reactive flush, leaving the page on
> "Loading…" forever. The fix removes `omitempty` from the field. No frontend
> change was needed — the backend now guarantees the array (defensive `?? []`
> was intentionally not added per surgical-change guidance).

The browser page (`doc-process-dag-view.svelte`) provides search with
debounce, summary cards (total DAGs, current default, processor count), a DAG
list with default badge, a create/modify editor, a detail panel, and a
confirm-guarded delete.

### 2. DAG names are unique

The pipeline table is versioned, so uniqueness is **per name, across all
versions**:

- DB: `UNIQUE(name, version)` guarantees no duplicate rows within a name's
  version history.
- App: create performs a duplicate-name existence check inside the transaction
  and rejects a second create with the same name
  (`CWB_KB_DAG_112`). `PUT` never renames — the name is a key, not an editable
  field (create-only in the UI).

### 3. At least one doc processor

- `ValidatePipelineVersion` now rejects an empty processor set up front:
  `"pipeline version rejected: at least one doc processor is required"`.
- The frontend editor also disables save until ≥1 processor is selected, and
  the create form refuses to submit an empty selection.

### 4. Validated before saving (DR8)

Every create/modify runs `ValidatePipelineVersion` **before** any database
write, so an invalid DAG never reaches the DB:

- empty processor set (added by this change)
- DR8 check 1 — dependency closure: every `depends_on_processors` edge and
  every gate's `requires` must reference processors inside the DAG
- DR8 check 2 — DAG well-formedness: no cycles, ordering is satisfiable
- DR8 check 3 — gate-fact availability: a gate may not depend on a fact no
  processor in the DAG produces

Rule predicates are canonicalized/analyzed via `semrules.Validate` /
`Canonicalize` / `Analyze` when gates are built from draft payloads. A rejected
DAG produces a descriptive error and no rows are changed (see requirement 5).

### 5. Transaction-protected writes

Create, modify, and delete each run inside a single DB transaction (`tx`):

- **Create** — duplicate-name check → resolve default flag → lock prior
  version → insert pipeline row (`RETURNING id`) → supersede prior version →
  insert rules. Commit or full rollback.
- **Modify** — a content change (processors or rules differ from the current
  version) authors a new version inside a transaction; a cosmetic change
  (display name / description / default flag only) updates in place.
- **Delete** — deletes bindings, then rules, then pipeline rows (FK
  `RESTRICT` order): `DELETE pipeline_bindings → pipeline_rules →
  pipelines`. All versions of the DAG are removed.

### 6. Exactly one system default

Enforced in two layers:

- **DB (≤1):** partial unique index `idx_kb_pipelines_one_system_default` on
  `is_system_default WHERE is_system_default` guarantees at most one row is
  ever marked default.
- **App (≥1):** the handler guarantees at least one default exists:
  - the **first** DAG created becomes the default automatically
  - marking a new default **clears the incumbent** in the same transaction
  - unsetting the **only** default is rejected (`CWB_KB_DAG_211`)
  - deleting the default DAG is rejected (`CWB_KB_DAG_304`)
  - when a content change authors a **new version of the default DAG**, the
    default flag transfers to the new version (and the older version is
    superseded)

## Main Code Changes

### 1. Backend composite-DAG handler

Files:

- `ChenWeb/server/api/kbhandler/doc_process_dag_handler.go`
- `ChenWeb/server/api/kbhandler/doc_process_dag_handler_test.go`

Implemented behavior:

- list/search with `SELECT DISTINCT ON (p.name) ... ORDER BY p.name, p.version DESC` (one row per DAG = current version, plus a `rule_count`)
- fetch-current-version-by-name (`ORDER BY version DESC LIMIT 1`)
- detail = current version + rules (`dagRulesQuery`) + bindings (`dagBindingsQuery` with `COALESCE` on nullable `tenant_id`/`user_id`)
- atomic version authoring (`createPipelineVersion`: lock prior version `FOR UPDATE`, compute next version, insert, supersede, insert rules)
- exactly-one-default helpers: `hasAnySystemDefault`, `clearSystemDefaultLocked`, `resolveSystemDefaultFlag`
- create/update/delete all transaction-backed
- processor catalog passthrough from `docprocessing.RegisteredProcessors()`
- error codes `CWB_KB_DAG_001`–`CWB_KB_DAG_304`

### 2. Route wiring

File:

- `ChenWeb/server/api/routes.go`

Added under the authenticated `/api/v1/kb/` group, adjacent to the legacy
pipeline-rules routes:

```go
apiGroup.GET("/kb/doc-process-dags", kbhandler.ListDocProcessDAGs)
apiGroup.POST("/kb/doc-process-dags", kbhandler.CreateDocProcessDAG)
apiGroup.GET("/kb/doc-process-dags/:name", kbhandler.GetDocProcessDAG)
apiGroup.PUT("/kb/doc-process-dags/:name", kbhandler.UpdateDocProcessDAG)
apiGroup.DELETE("/kb/doc-process-dags/:name", kbhandler.DeleteDocProcessDAG)
apiGroup.GET("/kb/doc-process-processors", kbhandler.ListDocProcessProcessors)
```

### 3. Validation guard

Files:

- `ChenWeb/server/api/doc-processing/pipeline_version_validate.go`
- `ChenWeb/server/api/doc-processing/pipeline_version_validate_test.go`

Added the empty-processor check at the top of `ValidatePipelineVersion` (DR8
checks are vacuous over an empty set, so this is checked first), plus
`TestValidatePipelineVersionRejectsEmptyProcessorSet`.

### 4. Frontend client and page

Files:

- `ChenWeb/web/src/lib/components/home3/doc-process-dag-client.ts` — typed API client (`listDags`, `getDag`, `createDag`, `updateDag`, `deleteDag`, `listProcessors`, `defaultRuleFor`), shared error extraction from `error_msg`
- `ChenWeb/web/src/lib/components/home3/doc-process-dag-view.svelte` — the page (search, list, editor, detail, delete confirm)
- `ChenWeb/web/src/lib/components/home3/nav-rail.svelte` — `System Admin > Doc Process Pipeline > Doc Process DAG`
- `ChenWeb/web/src/lib/components/home3/content-panel.svelte` — routes the menu id to the new view

Implemented page behavior:

- search (300 ms debounce), summary cards, DAG cards with default badge
- create/modify editor: name (create-only), display name, description,
  system-default toggle (disabled while editing the current default), a
  processor checkbox grid from the catalog, and a per-processor gate row with
  `effect` (require/enable/skip) and `depends_on_processors` checkboxes
- client-side guards: name required on create, ≥1 processor before save
- detail panel showing processors, gates, and bindings

### 5. Tests

- `doc_process_dag_handler_test.go` — 16 sqlmock-backed tests (list, get,
  get-not-found, create auto-marks first default, create leaves incumbent
  default untouched, duplicate-name rejection, empty-processor rejection
  before DB, cycle rejection before DB, incumbent-default clearing, rules
  written, processor change authors new version, cosmetic change does not new
  version, unset-sole-default rejection, delete-default rejection, atomic
  delete, processor catalog)
- `pipeline_version_validate_test.go` — empty-processor-set rejection test

## Verification

Backend verification completed with:

```bash
cd ChenWeb
go build ./server/api/kbhandler/ ./server/api/doc-processing/
go vet ./server/api/kbhandler/
go test ./server/api/kbhandler/ -run 'DocProcessDAG' -count=1
go test ./server/api/doc-processing/ -run 'ValidatePipelineVersion' -count=1
```

Frontend verification completed with:

```bash
cd ChenWeb/web
bun run build
```

Results:

- backend packages build and vet clean
- all Doc Process DAG handler tests and validation tests pass
- the frontend production build succeeds with zero new errors
  (pre-existing failures in unrelated kbhandler/doc-processing tests and a
  pre-existing `svelte-check` error were confirmed present at the parent
  commit via a `jj restore` experiment, independent of this change)

### Live smoke test

Authenticated smoke test against the running dev server (backend `:8080`,
Kratos on `:4433`), using a temporary Kratos identity that was created for the
test and deleted afterward:

| Step | Result |
|---|---|
| Create DAG with 2 processors + 2 gate rules | HTTP 200, version 1, rules persisted with `depends_on_processors` |
| Create with a rule edge to a processor not in the set | **Rejected before DB write** (DR8 closure) |
| Search `smoke` / search miss | matches DAG / 0 results |
| Get by name / missing name | detail + rules + bindings / 404 |
| Duplicate-name create | rejected (`CWB_KB_DAG_112`) |
| PUT processors (add a third) | new version authored (v1→v2); list shows newest only |
| Flip system default onto the DAG | single default; previous default cleared |
| Delete the default DAG | rejected (`CWB_KB_DAG_304`) |
| Unset the only default | rejected (`CWB_KB_DAG_211`) |
| Restore original default, then delete the (now non-default) DAG | HTTP 200, `deleted: 2` (both versions) |
| DB integrity after delete | 0 orphaned `pipeline_rules`, 0 orphaned `pipeline_bindings`, 0 remaining `smoke-test-dag` rows |

## Documentation Impact

Documents that reflect or are affected by this implementation:

- ADR 2026081001 (§3.8 DR8, §3.10 DR10) — this change implements the DR10
  composite-object surface and the create-time DR8 validation for the DAG
  management path.
- OpenSpec change `doc-process-dag-management` (proposal / design / spec /
  tasks) — written for this implementation and matching the shipped code.
- The legacy `kb.pipeline_policies`-based handlers remain in place; the
  ADR's retirement of `kb.pipeline_policies` is a separate in-progress effort
  (seven files in the ChenWeb working copy that drop the `policy_id` filter in
  favor of the `active` flag were pre-existing dirty and are **not** part of
  this change).

## Recommended Follow-up

- Complete and commit the pending `kb.pipeline_policies` retirement (the
  pre-existing dirty files) so the legacy filter disappears end-to-end.
- A frontend for authoring conditional gate predicates (ADR DR5) remains out of
  scope; the page currently accepts an optional JSON predicate.
- The ADR's follow-on topological-sort execution engine that consumes
  `depends_on_processors` is unchanged — today's `ExecutionOrder()` remains a
  fixed phase-bucket concatenation.
