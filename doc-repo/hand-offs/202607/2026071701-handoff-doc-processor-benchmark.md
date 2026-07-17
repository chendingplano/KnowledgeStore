# Document Processor Benchmark Session Handoff

Date: July 17, 2026

## Scope

This session completed the first end-to-end document-processor benchmark run for the checked-in synthetic benchmark corpus, fixed several benchmark usability issues, and documented the concrete commands needed to continue analysis.

Primary focus:

- make the benchmark runnable from the ChenWeb CLI;
- align benchmark artifact handling with the production document processors;
- diagnose and explain resume/provenance failures;
- remove hard-coded benchmark model refs and switch them to environment-driven configuration;
- produce a successful benchmark experiment run and capture its experiment ID.

## Final benchmark result

A successful benchmark run completed with:

- `experiment_id = 9f2f359f-d952-43f4-ac6b-e4e169501a04`
- variants:
  - `chunk-large`
  - `chunk-small`
  - `metrics-alt`
  - `metrics-baseline`

CLI success payload:

```json
{"dirty":false,"experiment_id":"9f2f359f-d952-43f4-ac6b-e4e169501a04","variants":["chunk-large","chunk-small","metrics-alt","metrics-baseline"]}
```

## What changed in code and config

### 1. Benchmark artifact root now matches production runtime behavior

The benchmark CLI was updated so `run --artifact-root ...` also sets the process-local `ARTIFACT_DIR` env var before production runtime initialization. This avoids the benchmark adapters and the production processors writing to different artifact roots.

Relevant area:

- `server/cmd/doc-benchmark/main.go`

### 2. Resume/provenance conflict is now explained clearly

A resumed benchmark run can legitimately fail if the stored run provenance no longer matches the current executable/dirty-state combination. Previously this surfaced as:

```text
benchmark store: expected one row affected, got 0
```

This was changed to return a descriptive error explaining that the run cannot resume because stored provenance and current provenance differ.

Relevant area:

- `server/api/doc-benchmark/store_application.go`
- `server/api/doc-benchmark/store_application_test.go`

### 3. Benchmark metric model override is now env-driven

The benchmark experiment loader now supports `${ENV_VAR}` expansion inside variant override values. This was added specifically so benchmark model refs are not hard-coded in experiment TOML files.

The example experiments now use:

- `DOC_BENCHMARK_METRICS_MODEL_NAME`

instead of the previously hard-coded `deepseek-chat`.

Relevant areas:

- `server/api/doc-benchmark/experiment.go`
- `server/api/doc-benchmark/experiment_test.go`
- `benchmark/doc-processors/experiments/example.toml`
- `benchmark/doc-processors/experiments/example-20260717-clean.toml`

## Important runtime facts discovered during this session

### Dirty working copy policy

The benchmark runner rejects a dirty working copy unless `--allow-dirty` is passed. This is intentional. A dirty run is treated as non-reproducible.

### Existing failed experiment from earlier the same day

An earlier benchmark experiment created on July 17, 2026 at approximately `08:47:45` already existed in the database with partially completed variant runs. That earlier experiment had been created from a `dirty=true` working copy. After the user committed their work, the current run became `dirty=false`, which caused provenance mismatch on resume.

Rather than mutating the old experiment, a fresh experiment file name was used to force creation of a new benchmark experiment identity.

### Model-name failure root cause

The benchmark initially failed with:

```text
variant metrics-alt: (MID_26042105) model "deepseek-chat" not found in /Users/cding/Workspace/ChenWeb/.models.toml
```

Root cause:

- the experiment TOML hard-coded `deepseek-chat`;
- the local runtime setup did not define that model ref;
- the benchmark should follow environment/config, not bake in workstation-specific model names.

## Commands used successfully

### Validate experiment

```sh
DOC_BENCHMARK_METRICS_MODEL_NAME=deepseek-flash-chen \
go run ./server/cmd/doc-benchmark validate \
  --experiment benchmark/doc-processors/experiments/example-20260717-clean.toml
```

### Run benchmark

```sh
export DOC_BENCHMARK_METRICS_MODEL_NAME=deepseek-flash-chen

go run ./server/cmd/doc-benchmark run \
  --experiment benchmark/doc-processors/experiments/example-20260717-clean.toml \
  --artifact-root "$ARTIFACT_DIR/doc-benchmark"
```

Note:

- `BENCHMARK_STORE_ID` was not required because the default `1` was acceptable.
- `BENCHMARK_WORK_ROOT` was not required because the default `.benchmark/work` under the ChenWeb repo was acceptable.
- `BENCHMARK_EVIDENCE_ROOT` was not required because the default `.benchmark/evidence` under the ChenWeb repo was acceptable.
- `ARTIFACT_DIR` was already provided externally by the user environment:
  - `/Users/cding/Apps/SemOS/Artifacts`

## Next recommended commands

### Generate a full report

```sh
go run ./server/cmd/doc-benchmark report \
  --experiment-id 9f2f359f-d952-43f4-ac6b-e4e169501a04 \
  --format markdown \
  --output "$ARTIFACT_DIR/doc-benchmark/report-9f2f359f-d952-43f4-ac6b-e4e169501a04.md"
```

### Compare the metric variants

```sh
go run ./server/cmd/doc-benchmark compare \
  --experiment-id 9f2f359f-d952-43f4-ac6b-e4e169501a04 \
  --baseline metrics-baseline \
  --candidate metrics-alt \
  --format markdown \
  --output "$ARTIFACT_DIR/doc-benchmark/compare-metrics-9f2f359f-d952-43f4-ac6b-e4e169501a04.md"
```

### Compare the chunk-size variants

```sh
go run ./server/cmd/doc-benchmark compare \
  --experiment-id 9f2f359f-d952-43f4-ac6b-e4e169501a04 \
  --baseline chunk-small \
  --candidate chunk-large \
  --format markdown \
  --output "$ARTIFACT_DIR/doc-benchmark/compare-chunk-9f2f359f-d952-43f4-ac6b-e4e169501a04.md"
```

## Files and docs that matter

Operational runbook:

- `docs/doc-processor-benchmark-operations.md`

Schema reference:

- `docs/database/doc-processor-benchmark-schema.md`

Benchmark experiment files:

- `benchmark/doc-processors/experiments/example.toml`
- `benchmark/doc-processors/experiments/example-20260717-clean.toml`

Primary benchmark CLI:

- `server/cmd/doc-benchmark/main.go`

Primary benchmark persistence and experiment parsing:

- `server/api/doc-benchmark/store_application.go`
- `server/api/doc-benchmark/experiment.go`

## Testing completed during the session

Focused benchmark tests passed after the fixes:

```sh
go test ./server/api/doc-benchmark -run 'TestExperimentOverrideExpandsEnvVariableValues|TestExperimentOverrideRejectsMissingEnvVariableValue|TestStoreAttachResolvedRuntimeAndFinalizeOnlyAfterAllCasesTerminal|TestAttachRunProvenanceReturnsResumeConflictDetails' -count=1
```

Earlier in the same implementation effort, broader benchmark package tests were also run successfully:

```sh
go test ./server/api/doc-benchmark ./server/cmd/doc-benchmark ./benchmark/doc-processors/generator -count=1
```

## Known follow-up items

- The benchmark has completed, but the report and compare outputs still need to be generated and reviewed.
- The example experiment currently assumes `DOC_BENCHMARK_METRICS_MODEL_NAME` is set in the environment. That is intentional, but whoever runs it must know to provide it.
- The runner still executes variants serially within one CLI process; the database model supports safe state transitions, but fully isolated parallel variant workers are not enabled yet.
- The checked-in synthetic corpus is still the starter corpus. Real evaluation quality depends on expanding datasets and reviewed `expected.json` coverage.

## Recommended handoff summary

If another engineer picks this up, the shortest path is:

1. Confirm `DOC_BENCHMARK_METRICS_MODEL_NAME` points to a valid local model ref in `.models.toml`.
2. Use `experiment_id = 9f2f359f-d952-43f4-ac6b-e4e169501a04`.
3. Generate the report and both compare outputs.
4. Review whether `metrics-alt` beats `metrics-baseline` and whether chunk-size changes helped or hurt.
5. If another clean rerun is needed, reuse the env-driven experiment file and avoid resuming stale experiments whose provenance was created from a different dirty/executable state.
