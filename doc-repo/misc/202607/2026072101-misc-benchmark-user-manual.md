# Benchmark User Manual

**Date:** 2026-07-21  
**Audience:** ChenWeb engineers and operators  
**Scope:** Set up the document-processor benchmark system from scratch and run it through a complete, working benchmark cycle  
**Applies to:** ChenWeb document-processor benchmark V1 (`chunking` and `extract_metrics`)

---

## 1. Purpose

This manual explains how to set up and operate the ChenWeb document-processor benchmark system from a fresh environment to a fully functional benchmark workflow.

The benchmark system exists to answer questions that normal production logging does not answer well:

- whether a processor change improved or degraded output quality;
- whether a prompt or model change is worth its latency and cost;
- whether a candidate configuration regresses on specific document classes;
- whether benchmark evidence is reproducible and auditable.

V1 is intentionally narrow:

- it benchmarks the real production document-processing path;
- it scores only `chunking` and `extract_metrics`;
- it uses deterministic synthetic fixtures;
- it is an experiment and comparison tool, not a release gate.

---

## 2. Reference documents

This manual is derived from the following documents:

- `KnowledgeStore/doc-repo/specs/202607/2026071301-spec-benchmark-system.md`
- `KnowledgeStore/doc-repo/adrs/202607/2026071301-adr-doc-processor-benchmark.md`
- `KnowledgeStore/doc-repo/hand-offs/202607/2026071701-handoff-doc-processor-benchmark.md`
- `ChenWeb/docs/doc-processor-benchmark-operations.md`
- `ChenWeb/docs/database/doc-processor-benchmark-schema.md`

If this manual and code behavior disagree, code and the operational runbook in `ChenWeb/docs/` should be treated as the current operational source of truth.

---

## 3. What the benchmark system does

A benchmark run executes the production document processor against an immutable synthetic dataset and records both quality and operational evidence.

At a high level, one run does the following:

1. Validates the selected dataset and experiment definition.
2. Expands variants from the experiment TOML.
3. Creates benchmark experiment, run, case-run, and attempt records in `kb`.
4. Seeds temporary `kb.inputs` rows.
5. Invokes the real document-processing controller.
6. Captures production outputs such as `.chunks`, `.metrics`, `kb.chunks`, and `kb.metrics`.
7. Reconciles captured outputs into canonical actual output.
8. Scores actual output against `expected.json`.
9. Stores verified evidence and reportable scores.

This is important: the benchmark does not simulate the processor. It measures the same controller and persistence path used in production.

---

## 4. V1 architecture and boundaries

V1 consists of five logical parts:

- Fixture repository: committed synthetic datasets and expected outputs.
- Experiment orchestrator: parses experiment TOML, validates compatibility, creates run identities, and manages resume behavior.
- Benchmark worker: seeds one case, runs the real controller, and captures outputs.
- Processor adapter and scorer: processor-specific reconciliation and scoring.
- Result store and reporter: persists immutable provenance, scores, artifacts, JSON reports, and Markdown reports.

V1 processor coverage:

- `chunking`
- `extract_metrics`

V1 does not cover:

- other doc processors;
- LLM-as-judge scoring;
- CI gating;
- web UI;
- automatic evidence retention purge;
- multi-host distributed scheduling.

---

## 5. Prerequisites

Run all benchmark commands from the ChenWeb repository root.

You need the following before your first live run:

- a working ChenWeb checkout;
- Go installed and able to run the ChenWeb CLI;
- PostgreSQL available and configured for ChenWeb;
- ChenWeb `config.toml` and `.env` set up;
- shared-library configuration available as required by the document processor;
- provider credentials for any live model used by `extract_metrics`;
- prompt files and model definitions configured exactly as production expects;
- a valid local model reference for metric extraction in `.models.toml`;
- a clean working copy, unless you intentionally use `--allow-dirty`.

V1 benchmark runs reuse production initialization. That means `run`, `report`, `compare`, and `clean` all load ChenWeb configuration, initialize database handles, and apply pending Goose migrations.

`validate` is the exception: it is filesystem-only and does not require database or model access.

---

## 6. Required directories and environment variables

The benchmark uses three different storage locations, each with a different purpose.

### 6.1 Production artifact root

`ARTIFACT_DIR` is the artifact root used by production processors. Benchmark execution must use the same artifact root behavior as production. During the July 17, 2026 session, the CLI was updated so that `run --artifact-root ...` also sets process-local `ARTIFACT_DIR` before production runtime initialization.

This prevents benchmark adapters and production processors from writing to different places.

### 6.2 Benchmark work root

`BENCHMARK_WORK_ROOT` is disposable workspace storage.

Use it for:

- temporary copies;
- transient processor workspaces;
- cleanup-managed intermediate files.

This tree may be cleaned automatically after a verified terminal attempt.

### 6.3 Benchmark evidence root

`BENCHMARK_EVIDENCE_ROOT` is immutable evidence storage.

Use it for:

- captured inputs;
- expected outputs;
- canonical actual outputs;
- logs and diagnostics;
- exact resolved prompt and model snapshots;
- scorer and normalization configuration;
- reports and comparison artifacts.

This tree is never purged by normal `clean` operations.

### 6.4 Benchmark store isolation

Use a benchmark-only knowledge-store ID through `BENCHMARK_STORE_ID` or `--store-id` so temporary seeded inputs are isolated from unrelated knowledge-store activity.

### 6.5 Example environment

```sh
export ARTIFACT_DIR="$PWD/Data/kb/artifacts"
export BENCHMARK_STORE_ID=1
export BENCHMARK_WORK_ROOT="$PWD/.benchmark/work"
export BENCHMARK_EVIDENCE_ROOT="$PWD/.benchmark/evidence"
```

Rules:

- work root and evidence root must be absolute after resolution;
- they must be different directories;
- they must not overlap;
- they must not rely on unsafe symlinks.

---

## 7. Dataset and experiment layout

The V1 starter dataset is committed in the ChenWeb repository:

```text
benchmark/doc-processors/datasets/doc-processors-synthetic-core/1.0.0/
├── manifest.json
└── cases/<case-id>/
    ├── input.lines.txt
    └── expected.json
```

Each case has:

- `input.lines.txt`: the canonical seven-column line file consumed by the production controller;
- `expected.json`: the gold output for the applicable V1 processors.

The starter experiment files live here:

```text
benchmark/doc-processors/experiments/
```

The clean example experiment introduced in the July 17, 2026 handoff is:

```text
benchmark/doc-processors/experiments/example-20260717-clean.toml
```

That experiment defines four variants:

- `chunk-small`
- `chunk-large`
- `metrics-baseline`
- `metrics-alt`

The metrics variants intentionally resolve the model name from an environment variable instead of hard-coding a workstation-specific value.

---

## 8. Initial setup from scratch

This section is the shortest path from zero to a working system.

### Step 1: Prepare ChenWeb runtime configuration

From the ChenWeb repo root, confirm:

- `config.toml` is present and valid for your local environment;
- `.env` is present if your setup requires it;
- database connectivity works;
- prompt files referenced by the experiment exist;
- `.models.toml` contains the model reference you plan to use.

For `extract_metrics`, the example experiment expects:

```sh
export DOC_BENCHMARK_METRICS_MODEL_NAME=<your-valid-local-model-ref>
```

On July 17, 2026, a run initially failed because the experiment hard-coded `deepseek-chat`, but the local `.models.toml` did not define that model name. The env-driven model override exists specifically to avoid that failure mode.

### Step 2: Create benchmark roots

Create or choose three local roots:

- production artifact root;
- benchmark work root;
- benchmark evidence root.

Example:

```sh
mkdir -p "$PWD/Data/kb/artifacts"
mkdir -p "$PWD/.benchmark/work"
mkdir -p "$PWD/.benchmark/evidence"
```

Then export:

```sh
export ARTIFACT_DIR="$PWD/Data/kb/artifacts"
export BENCHMARK_WORK_ROOT="$PWD/.benchmark/work"
export BENCHMARK_EVIDENCE_ROOT="$PWD/.benchmark/evidence"
export BENCHMARK_STORE_ID=1
```

### Step 3: Ensure the working copy is in the intended state

By default, the benchmark runner rejects a dirty working copy.

Check status:

```sh
jj status
```

If the tree is intentionally dirty and you still want a non-reproducible experiment, pass:

```sh
--allow-dirty
```

Use that only for exploration. Clean runs are the normal path.

### Step 4: Validate the experiment before spending tokens

```sh
export DOC_BENCHMARK_METRICS_MODEL_NAME=<your-valid-local-model-ref>

go run ./server/cmd/doc-benchmark validate \
  --experiment benchmark/doc-processors/experiments/example-20260717-clean.toml
```

Validation checks:

- dataset manifest consistency;
- referenced files and hashes;
- processor applicability;
- tag and schema correctness;
- sampling settings;
- unsafe paths and symlinks;
- stale line references;
- unknown TOML fields.

`validate` does not call the model and does not touch the database.

### Step 5: Run the benchmark

```sh
go run ./server/cmd/doc-benchmark run \
  --config config.toml \
  --experiment benchmark/doc-processors/experiments/example-20260717-clean.toml \
  --artifact-root "$ARTIFACT_DIR/doc-benchmark" \
  --store-id "$BENCHMARK_STORE_ID"
```

Notes:

- `--artifact-root` should point at the benchmark artifact subtree you want under the production artifact root.
- The CLI now aligns benchmark and production artifact behavior by setting `ARTIFACT_DIR` process-locally before production initialization.
- If `BENCHMARK_WORK_ROOT` and `BENCHMARK_EVIDENCE_ROOT` are already exported, you usually do not need to pass them explicitly.

On success, the CLI returns JSON including:

- `dirty`
- `experiment_id`
- `variants`

An example successful result from July 17, 2026 was:

```json
{"dirty":false,"experiment_id":"9f2f359f-d952-43f4-ac6b-e4e169501a04","variants":["chunk-large","chunk-small","metrics-alt","metrics-baseline"]}
```

### Step 6: Generate reports

Generate a full Markdown report:

```sh
go run ./server/cmd/doc-benchmark report \
  --experiment-id <experiment-id> \
  --format markdown \
  --output "$ARTIFACT_DIR/doc-benchmark/report-<experiment-id>.md"
```

Optionally generate JSON too:

```sh
go run ./server/cmd/doc-benchmark report \
  --experiment-id <experiment-id> \
  --format json \
  --output "$ARTIFACT_DIR/doc-benchmark/report-<experiment-id>.json"
```

### Step 7: Compare variants

Compare metrics variants:

```sh
go run ./server/cmd/doc-benchmark compare \
  --experiment-id <experiment-id> \
  --baseline metrics-baseline \
  --candidate metrics-alt \
  --format markdown \
  --output "$ARTIFACT_DIR/doc-benchmark/compare-metrics-<experiment-id>.md"
```

Compare chunking variants:

```sh
go run ./server/cmd/doc-benchmark compare \
  --experiment-id <experiment-id> \
  --baseline chunk-small \
  --candidate chunk-large \
  --format markdown \
  --output "$ARTIFACT_DIR/doc-benchmark/compare-chunk-<experiment-id>.md"
```

At this point, the benchmark system is fully functional for V1 use.

---

## 9. Recommended first-run command sequence

If you want the shortest practical path, use this exact flow:

```sh
cd /path/to/ChenWeb

export ARTIFACT_DIR="$PWD/Data/kb/artifacts"
export BENCHMARK_STORE_ID=1
export BENCHMARK_WORK_ROOT="$PWD/.benchmark/work"
export BENCHMARK_EVIDENCE_ROOT="$PWD/.benchmark/evidence"
export DOC_BENCHMARK_METRICS_MODEL_NAME=<your-valid-local-model-ref>

mkdir -p "$ARTIFACT_DIR" "$BENCHMARK_WORK_ROOT" "$BENCHMARK_EVIDENCE_ROOT"

go run ./server/cmd/doc-benchmark validate \
  --experiment benchmark/doc-processors/experiments/example-20260717-clean.toml

go run ./server/cmd/doc-benchmark run \
  --config config.toml \
  --experiment benchmark/doc-processors/experiments/example-20260717-clean.toml \
  --artifact-root "$ARTIFACT_DIR/doc-benchmark" \
  --store-id "$BENCHMARK_STORE_ID"

go run ./server/cmd/doc-benchmark report \
  --experiment-id <experiment-id> \
  --format markdown \
  --output "$ARTIFACT_DIR/doc-benchmark/report-<experiment-id>.md"

go run ./server/cmd/doc-benchmark compare \
  --experiment-id <experiment-id> \
  --baseline metrics-baseline \
  --candidate metrics-alt \
  --format markdown \
  --output "$ARTIFACT_DIR/doc-benchmark/compare-metrics-<experiment-id>.md"

go run ./server/cmd/doc-benchmark compare \
  --experiment-id <experiment-id> \
  --baseline chunk-small \
  --candidate chunk-large \
  --format markdown \
  --output "$ARTIFACT_DIR/doc-benchmark/compare-chunk-<experiment-id>.md"
```

---

## 10. Resume, reproducibility, and provenance

The benchmark system is designed to make results attributable and reproducible.

Key rules:

- experiment identity is tied to the raw experiment request hash;
- run and case identities are stable for the same request and sampling units;
- stored provenance includes code state, dataset identity, runtime configuration, scorer inputs, and artifact hashes;
- repeating the same run command resumes missing or retryable work instead of creating unrelated duplicate runs.

### Resume conflict behavior

If stored provenance no longer matches the current executable or dirty-state combination, resume is rejected.

Earlier behavior surfaced this as:

```text
benchmark store: expected one row affected, got 0
```

As of the July 17, 2026 changes, that path now returns a descriptive resume-conflict error explaining that stored provenance and current provenance do not match.

Practical meaning:

- if the earlier experiment was created with `dirty=true` and the current tree is now clean, do not expect a transparent resume;
- if the executable or resolved runtime changed materially, use a new experiment request instead of forcing resume.

---

## 11. Attempt lifecycle and cleanup

Each case can move through visible benchmark outcomes such as:

- `success`
- `processor_failed`
- `timed_out`
- `invalid_output`
- `infrastructure_failed`
- `scorer_failed`
- `canceled`

Failures remain visible. The system does not silently drop failed cases from reports.

### Normal cleanup

Normal cleanup happens automatically after a verified terminal attempt unless retained intentionally.

To retry cleanup:

```sh
go run ./server/cmd/doc-benchmark clean --experiment-id <experiment-id>
```

### Explicit discard of unverified evidence

Only unverified evidence from a specific attempt may be discarded explicitly:

```sh
go run ./server/cmd/doc-benchmark clean \
  --attempt-id <attempt-id> \
  --discard-unverified
```

Normal cleanup:

- removes only owned disposable workspaces;
- deletes only benchmark-owned seeded production rows in controlled order;
- never purges verified evidence.

---

## 12. Database model summary

The benchmark schema lives under `kb`.

Core tables:

- `kb.benchmark_experiments`
- `kb.benchmark_runs`
- `kb.benchmark_case_runs`
- `kb.benchmark_case_attempts`
- `kb.benchmark_workspaces`
- `kb.benchmark_scores`
- `kb.benchmark_artifacts`

What they represent:

- experiments store immutable request and dataset identity;
- runs store one named variant and its resolved runtime/provenance;
- case runs store one `(variant, case, repetition)` work unit;
- attempts store execution and rescore history;
- workspaces store cleanup and ownership authority;
- scores and artifacts store reportable metrics and evidence references.

This matters operationally because benchmark reporting is based on selected attempts and verified evidence, not on ad hoc filesystem inspection.

---

## 13. Troubleshooting

### Dirty working copy rejected

Cause:

- the benchmark treats dirty code as non-reproducible.

Fix:

- commit the working copy with `jj`; or
- rerun with `--allow-dirty` only if exploratory results are acceptable.

### Model not found in `.models.toml`

Cause:

- `DOC_BENCHMARK_METRICS_MODEL_NAME` points to a model ref that does not exist locally.

Fix:

- update `.models.toml`; or
- point `DOC_BENCHMARK_METRICS_MODEL_NAME` at an existing local model definition.

### Artifact not found

Cause:

- benchmark and production processors are not writing to the same effective artifact root.

Fix:

- verify `ARTIFACT_DIR`;
- verify `run --artifact-root ...`;
- verify the target path is writable.

### Resume conflict after code or dirty-state changed

Cause:

- stored provenance differs from current provenance.

Fix:

- create a fresh experiment request;
- do not try to force resume across incompatible provenance states.

### Case file hash changed

Cause:

- the committed dataset version was modified in place.

Fix:

- restore the original dataset bytes; or
- publish a new dataset version directory.

### `scorer_failed`

Cause:

- deterministic scoring or reconciliation failed.

Fix:

- inspect verified evidence;
- fix scorer code;
- rerun so the system can rescore.

### `files_pending`

Cause:

- filesystem cleanup could not complete.

Fix:

- fix permissions or root-path problems;
- rerun `clean`.

---

## 14. Operational recommendations

Use these practices for reliable benchmark operations:

- keep datasets immutable once versioned;
- use env-driven model overrides instead of hard-coded workstation-specific names;
- treat `validate` as mandatory before any live benchmark run;
- use clean working copies for reportable experiments;
- isolate benchmark store IDs and artifact roots from unrelated work when possible;
- generate report and compare outputs immediately after a successful run;
- preserve experiment IDs in handoff notes for later analysis;
- expand the starter synthetic corpus before making strong quality claims.

---

## 15. Known V1 limitations

V1 is useful, but deliberately incomplete.

Current limitations:

- only `chunking` and `extract_metrics` are scored;
- variants currently execute serially in one CLI process;
- the starter corpus is still small and synthetic;
- there is no automatic release gating;
- verified evidence has no automatic retention expiry;
- there is no web UI;
- there is no pipeline-wide combined score.

These are design choices, not accidental omissions.

---

## 16. Definition of “fully functional” for V1

You can consider the benchmark system fully functional in your environment when all of the following are true:

- `validate` succeeds for the intended experiment;
- `run` completes and returns an `experiment_id`;
- benchmark evidence is written under the evidence root;
- report generation succeeds;
- at least one `compare` output succeeds;
- the selected variants can be interpreted from stored results without rerunning the model.

If those conditions are met, the V1 benchmark system is operational.

---

## 17. Example known-good run

A known successful benchmark run completed on July 17, 2026 with:

- `experiment_id = 9f2f359f-d952-43f4-ac6b-e4e169501a04`
- variants:
  - `chunk-large`
  - `chunk-small`
  - `metrics-alt`
  - `metrics-baseline`

That run is useful as a reference point when checking whether your local environment is wired correctly.

---

## 18. Final checklist

Before first use:

- ChenWeb config works.
- PostgreSQL works.
- prompts exist.
- model refs exist.
- roots are created and exported.
- working tree status is intentional.

Before every live run:

- run `validate`;
- confirm `DOC_BENCHMARK_METRICS_MODEL_NAME`;
- confirm `ARTIFACT_DIR`, `BENCHMARK_WORK_ROOT`, and `BENCHMARK_EVIDENCE_ROOT`.

After every successful run:

- save the `experiment_id`;
- generate report output;
- generate compare outputs;
- review quality, latency, cost, and failure visibility together.

# References
[1] `KnowledgeStore/doc-repo/specs/202607/2026071301-spec-benchmark-system.md`

[2] `KnowledgeStore/doc-repo/adrs/202607/2026071301-adr-doc-processor-benchmark.md`