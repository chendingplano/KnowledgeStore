# Benchmark Browser Setup Page Implementation

**Date:** 2026-07-22 \
**Status:** Implemented \
**Component:** ChenWeb `home3`, benchmark admin API, benchmark setup orchestration \
**Authors**: Codex \

## Change Logs
* 2026/07/22, Document created.

## Purpose

This document records the implementation completed for the browser-driven
benchmark setup and operations flow.

It complements:

- ADR 2026071301 — `doc-processor-benchmark`
- Spec 2026071301 — `benchmark-system`
- Misc 2026072101 — `benchmark-user-manual`

It focuses on:

- what was implemented
- what user workflow changed
- what benchmark scope is implemented today
- what extensibility the current implementation preserves
- what was verified
- what was intentionally not implemented yet

## Summary

The main benchmark system had already been implemented as a CLI-driven workflow.
This change adds a browser-driven administrative surface so an operator can set
up and run benchmark work from `home3` without manually invoking shell
commands.

The new page lives at:

- `home3 > System Admin > Benchmark > Setup`

The page provides:

- persisted benchmark admin configuration
- browser-visible setup state for each major step
- browser-triggered execution for unfinished steps
- background job tracking for longer operations
- recent benchmark activity and outputs

This implementation does not replace the benchmark engine. It wraps the
existing benchmark system in a browser-friendly admin layer.

## Scope Implemented

### 1. Browser-admin benchmark configuration

Implemented behavior:

- benchmark setup values can now be edited in the browser
- those values are persisted in the database
- the page reloads the saved configuration on refresh

Persisted fields include:

- experiment path
- dataset root
- artifact root
- work root
- evidence root
- store ID
- owner
- tenant ID
- metrics model name
- allow-dirty flag
- report format
- report output path
- default compare variant names

### 2. Browser-visible setup and operation state

The page shows a stateful step sequence that includes both setup and execution
operations:

- runtime configuration
- benchmark roots
- working copy check
- validate
- run
- report
- compare

For each step, the UI shows:

- current state
- short explanation
- detected values when available
- completed or failed time when available

### 3. Browser-triggered benchmark actions

The page can trigger:

- one specific step
- the next unfinished step

Short checks run immediately through the admin service. Longer operations are
tracked as jobs.

### 4. Job-backed long-running operations

The browser admin layer introduces persisted benchmark admin jobs for actions
such as:

- working copy validation
- experiment validation
- benchmark execution
- report generation
- compare generation

The page polls active jobs and refreshes setup state after completion.

### 5. `home3` navigation integration

The implementation adds the benchmark page to the existing `home3` System Admin
navigation rather than creating a separate app surface.

## Main Code Changes

### 1. Added benchmark admin persistence tables

Files:

- `ChenWeb/server/api/appdatastores/table-doc-benchmark-admin-config.go`
- `ChenWeb/server/api/appdatastores/table-doc-benchmark-admin-jobs.go`
- `ChenWeb/server/api/database/createtables.go`

Implemented behavior:

- persist benchmark admin configuration
- persist benchmark admin job history and results
- create these tables during normal table creation

### 2. Added benchmark admin orchestration layer

Files:

- `ChenWeb/server/api/doc-benchmark-admin/types.go`
- `ChenWeb/server/api/doc-benchmark-admin/store.go`
- `ChenWeb/server/api/doc-benchmark-admin/service.go`

Implemented behavior:

- load and save benchmark config
- inspect current setup state
- classify step state
- create and update background jobs
- reuse the existing benchmark engine for validate/run/report/compare

Architectural note:

- this is a thin admin orchestration layer over the benchmark system
- it is not a second benchmark engine

### 3. Added benchmark admin HTTP endpoints

File:

- `ChenWeb/server/api/docbenchmarkadminhandler/handler.go`

Route wiring:

- `ChenWeb/server/api/routes.go`

Implemented API surface:

- `GET /api/v1/admin/benchmark/config`
- `PUT /api/v1/admin/benchmark/config`
- `GET /api/v1/admin/benchmark/setup-state`
- `POST /api/v1/admin/benchmark/steps/:stepId/run`
- `POST /api/v1/admin/benchmark/run-next`
- `GET /api/v1/admin/benchmark/jobs`
- `GET /api/v1/admin/benchmark/jobs/:jobId`

### 4. Added frontend service client

File:

- `ChenWeb/web/src/lib/services/docBenchmarkAdminService.ts`

Implemented behavior:

- typed frontend access to the benchmark admin endpoints
- shared request and response handling for the setup page

### 5. Added benchmark setup page and supporting UI

Files:

- `ChenWeb/web/src/lib/components/home3/benchmark-setup-view.svelte`
- `ChenWeb/web/src/lib/components/home3/benchmark-step-card.svelte`
- `ChenWeb/web/src/lib/components/home3/benchmark-job-list.svelte`
- `ChenWeb/web/src/lib/components/home3/content-panel.svelte`
- `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`

Implemented behavior:

- top-level benchmark config editor
- step cards with run buttons
- recent activity panel
- `System Admin > Benchmark > Setup` navigation entry

## Benchmark Scope Confirmed by Current Implementation

The current implementation is not metrics-only.

Today’s implemented benchmark scope is:

- `chunking`
- `extract_metrics`

This matches the current benchmark engine and dataset contract.

Important distinction:

- `chunking` is implemented as a first-class scored benchmark processor
- `extract_metrics` is implemented as a first-class scored benchmark processor
- metric extraction also runs its dependency closure in production execution
- the browser setup page does not narrow that scope; it exposes the existing
  benchmark engine

## Future Extensibility Confirmed by Current Implementation

Your thinking is consistent with the current design and implementation.

### 1. Future per-artifact benchmarks are consistent with the current system

The current benchmark framework is processor-specific and adapter-based. That
means future benchmark work for additional artifact families fits the existing
architecture.

Examples that fit the current design direction:

- provisions benchmark
- inventory items benchmark
- semantic projections benchmark
- entity relation benchmark

Each new benchmark family would still require real implementation work, such
as:

- adding a benchmark processor identity
- extending dataset validation to recognize the new expected-output section
- adding adapter capture and reconciliation logic
- adding scorer logic
- adding report aggregation support where needed
- expanding fixture generation and reviewed datasets

So the framework is extensible, but those future benchmarks are not already
implemented.

### 2. Multi-artifact benchmarks are also consistent with the current system

The current system already supports experiments that involve more than one
processor in the same benchmark run.

Current example:

- one benchmark experiment can include both `chunking` and `extract_metrics`

This means the design already supports the broader idea of a benchmark that
includes multiple artifacts or processors in one experiment, as long as each
participating processor has:

- dataset applicability
- expected output
- adapter support
- scoring support

Important limitation:

- the current system reports processor-specific quality vectors
- it does not collapse heterogeneous artifact quality into one combined
  “pipeline quality” score

That is intentional and aligns with the ADR.

## What This Implementation Does Not Change

This implementation does not:

- add new benchmark processors beyond `chunking` and `extract_metrics`
- add provisions or inventory benchmark adapters
- add human/LLM-judge scoring
- add job cancellation
- add live log streaming in the page
- add multiple saved benchmark profiles
- replace the CLI as a debugging or fallback path

## Verification

Backend verification completed with:

```bash
cd ChenWeb
go test ./server/api/doc-benchmark-admin ./server/api/docbenchmarkadminhandler ./server/api/doc-benchmark -count=1
```

Frontend verification completed with:

```bash
cd ChenWeb/web
APP_BASE_URL=http://localhost:5173 npm run check
```

Result:

- the new backend packages compiled and passed
- the benchmark engine package still passed
- the frontend check passed with zero new errors from this implementation
- pre-existing warnings remain elsewhere in the frontend codebase

## Documentation Impact

This implementation adds a browser-driven administrative path for operating the
benchmark system.

Documents that should reflect this:

- the benchmark ADR should explicitly keep the “future processor-family
  extensibility” interpretation
- the benchmark user manual remains useful, but it still describes the CLI path
  more directly than the new browser workflow

## Recommended Follow-up

Recommended next follow-up items:

- add explicit docs for browser-based benchmark operations
- add tests for the new benchmark admin layer
- add provisions and inventory-item benchmark proposals as separate scoped
  changes rather than bundling them into this implementation
- decide whether multi-artifact benchmark reports need cross-processor summary
  presentation beyond the current processor-specific vectors
