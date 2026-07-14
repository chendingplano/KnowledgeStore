# Doc Processor Benchmark System

**Date:** 2026-07-13
**Status:** Approved design
**Source:** `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`

## 1. Goal

Build a ChenWeb-native benchmark system for comparing document-processor prompts,
models, and configurations against the same reproducible dataset. Version 1 defines a
framework that can support every doc processor, but implements benchmark adapters and
scorers only for `chunking` and `extract_metrics`.

The official benchmark path exercises the real doc-processing controller and persisted
artifacts. It measures processor behavior as deployed, including prompt and model
configuration, upstream dependencies, deduplication, storage, latency, token use, and
prompt-cache behavior.

The benchmark is an experiment and comparison tool in v1. It is not a release gate and
does not automatically select a winning configuration.

## 2. Design Principles

1. **Same data, attributable comparison.** Compare variants only against the same
   immutable dataset and scorer versions.
2. **Exact labels by construction.** V1 fixtures are generated deterministically from
   templates whose chunk boundaries and metric facts are known, rather than using an
   LLM to create ground truth.
3. **Production-path fidelity.** Invoke the existing `ControlService` and score the
   artifacts and database rows it persists. JetStream delivery is not part of output
   quality and is not included.
4. **Processor-specific quality.** Do not collapse heterogeneous processors into one
   pipeline-wide score. Each processor exposes a metric vector and diagnostics.
5. **Immutable provenance.** A result is meaningful only with its dataset, code,
   prompt, model, configuration, scorer, and artifact hashes.
6. **Failures remain visible.** A failed, timed-out, or invalid case is never silently
   removed from a report.
7. **Deterministic scoring first.** V1 does not use an LLM judge.

These principles follow the same broad experiment pattern used by current evaluation
systems: versioned datasets, immutable runs, per-example results, aggregate metrics,
and configuration comparisons. See [MLflow evaluation datasets][mlflow-datasets],
[MLflow experiment tracking][mlflow-tracking], [LangSmith dataset versioning][langsmith-datasets],
and [Promptfoo assertions and metrics][promptfoo-metrics]. ChenWeb owns the execution
and scoring core because generic prompt harnesses do not naturally represent its
asynchronous, multi-stage, database-backed processor pipeline.

## 3. Scope

### 3.1 V1 processors

| Processor | Why it is a pilot | Official outputs scored |
|---|---|---|
| `chunking` | Deterministic boundary and invariant evaluation | `.chunks` artifact and `kb.chunks` run metadata |
| `extract_metrics` | Structured LLM extraction with matching, grounding, and field quality | `kb.metrics`, `.metrics` artifact, processor logs, and LLM usage |

The framework defines extension boundaries for future processors, but v1 must not add
placeholder scorers or schemas for them.

### 3.2 Primary use case

An operator defines two or more named variants that differ in prompt reference, model
definition reference, or processor configuration. A model definition resolves to its
provider, model, temperature, seed, and other provider parameters, so choosing different
named model definitions is how v1 compares providers and model parameters. The
benchmark runs each variant over the same synthetic dataset and reports paired quality,
latency, token, cache, and cost deltas.

## 4. System Architecture

The system has five components with narrow interfaces.

| Component | Responsibility | Input | Output |
|---|---|---|---|
| Fixture repository | Store immutable synthetic inputs, expected outputs, tags, and hashes | Committed dataset files | Validated dataset version |
| Experiment orchestrator | Expand variants, schedule/resume work, start isolated workers, and aggregate results | Experiment TOML | Run and comparison records |
| Benchmark worker | Seed a benchmark input, initialize one variant, invoke `ControlService`, and capture real outputs | One immutable variant and a case/repetition set | Captured case runs |
| Processor adapter/scorer | Retrieve canonical actual output, normalize it, compare it with expected output, and emit diagnostics | Expected and actual processor artifacts | Versioned score records |
| Result store/reporter | Persist provenance and emit JSON and Markdown comparisons | Runs, scores, usage, and artifact references | Auditable reports |

The benchmark code must depend on production processor interfaces. Production
processors must not import benchmark packages.

Each v1 processor adapter has the same logical contract:

- `Applicable(expected)` identifies whether the case has gold output for the processor.
- `AllowedOverrides()` returns typed, non-secret configuration keys.
- `ResolvedConfig(initializedProcessor)` returns the effective production values and
  prompt/model content hashes.
- `Capture(recordID)` reads and serializes every official output and telemetry source.
- `Reconcile(capture)` returns canonical actual output or `invalid_output` with a diff.
- `Score(expected, actual, scorerVersion)` returns scalar components and diagnostics.
- `Cleanup(recordID)` deletes only that adapter's temporary production rows in declared
  dependency order.

These methods are independently testable; the worker owns orchestration, timeout,
attempt lifecycle, and artifact hashing.

## 5. Repository Layout

The implementation should use the following logical layout; exact Go file boundaries
may be refined in the implementation plan without changing the contracts in this spec.

```text
ChenWeb/
├── benchmark/doc-processors/
│   ├── datasets/<dataset-id>/<version>/
│   │   ├── manifest.json
│   │   ├── cases/<case-id>/input.lines.txt
│   │   └── cases/<case-id>/expected.json
│   └── experiments/<experiment-name>.toml
├── server/cmd/doc-benchmark/
└── server/api/doc-benchmark/
```

The input is a canonical seven-field, tab-separated Line File. The implementation must
use the filename or extension expected by existing input-loading code if it requires a
different name.

Large captured artifacts live under a benchmark-specific artifact root outside the
committed dataset tree. The database stores their paths and SHA-256 hashes.

Runtime storage has two disjoint configured roots:

- `BENCHMARK_WORK_ROOT/<experiment-id>/<attempt-id>/` contains disposable copies and
  production pipeline artifacts. Cleanup may remove only this tree.
- `BENCHMARK_EVIDENCE_ROOT/<experiment-id>/<run-id>/<case-id>/<attempt-id>/` contains
  immutable captured inputs, expected output, canonical actual-output JSON/files, logs,
  diagnostics, reports, exact prompt contents, redacted resolved model definitions, and
  the serialized scorer/normalization configuration. Capture copies through a temporary
  file, fsyncs, renames, hashes, and then marks the evidence verified. Cleanup never
  removes this tree.

The roots must resolve to different non-overlapping absolute directories.
V1 applies no automatic retention expiry to verified evidence. Any future evidence
purge/retention policy requires a separate design; `clean` is not an evidence purge.

## 6. Synthetic Dataset Contract

### 6.1 Manifest

`manifest.json` contains at least:

```json
{
  "schema_version": 1,
  "dataset_id": "doc-processors-synthetic-core",
  "dataset_version": "1.0.0",
  "generator_version": "1.0.0",
  "seed": 20260713,
  "cases": [
    {
      "case_id": "metric-duplicate-overlap-001",
      "input": "cases/metric-duplicate-overlap-001/input.lines.txt",
      "expected": "cases/metric-duplicate-overlap-001/expected.json",
      "processors": ["chunking", "extract_metrics"],
      "tags": ["overlap", "duplicate-mention", "multiple-units"]
    }
  ]
}
```

The dataset hash is SHA-256 over an unambiguous byte stream. The stream begins with the
UTF-8 bytes `chenweb-doc-benchmark-dataset-v1\n`, followed by an unsigned 64-bit
big-endian entry count. Entries are `manifest.json` plus the unique set of every
referenced input and expected-output file, ordered by cleaned, forward-slash relative
path in ascending UTF-8 byte order. Every entry, including the manifest, is encoded as
an unsigned 64-bit big-endian path length, path bytes, unsigned 64-bit big-endian
content length, and raw content bytes. The validator rejects absolute paths, `..`,
symlinks, paths outside the dataset directory, and duplicate normalized references. The
manifest does not store its own computed hash. Formatting-only changes intentionally
change the dataset hash.

Dataset versions are immutable. Any fixture or expected-output change requires a new
SemVer 2.0.0 version, even when the change is believed to be a correction. Dataset
relative paths and case IDs are restricted to ASCII letters, digits, `.`, `_`, `-`, and
`/` for paths, eliminating cross-platform Unicode path-normalization differences.

### 6.2 Fixture generation

Fixtures are produced from deterministic parameterized templates. The generator emits
both the canonical line file and expected JSON from the same structured case definition.
Generated fixture files are committed so benchmark execution does not depend on the
generator or on an external service.

Dataset adequacy is coverage-driven. Every chunking rule and every core metric behavior
must have:

- a positive case;
- a negative or near-miss case;
- a boundary or interaction case where applicable; and
- stable tags used for slice reports.

Initial tags include `toc`, `boundary`, `final-small-chunk`, `long-list`, `overlap`,
`reordered-lines`, `no-metric`, `negative-metric`, `duplicate-mention`,
`multiple-metrics`, `multiple-units`, `implicit-metric`, and `multilingual`.

The validator rejects duplicate case IDs, unknown tags, missing files, stale or invalid
line references, unsupported schema versions, and out-of-range expected metric source
spans. Semantic support is guaranteed by generation from the same structured fact
definition and reviewed fixture content; the validator does not pretend to prove prose
semantics.

`processors` is the case applicability list. It must be non-empty and exactly match the
processor sections present in `expected.json`. For a selected processor, its applicable
population is the cases that list that processor. A run creates work only for cases
applicable to at least one selected processor; dependencies may still execute even when
they are not independently scored. Reports use a separate `total_cases` and
`total_case_repetitions` for each processor. Cases applicable to none of the selected
processors are reported as filtered before execution and never appear as skipped or
failed work.

During pre-run validation, the orchestrator computes raw SHA-256 for every case input and
expected file and stores the sorted `(relative_path, hash)` map in the experiment
snapshot. It also canonicalizes `case_tags` by validating, de-duplicating, and sorting
them. For each selected processor it expands and sorts the exact applicable sampling
units `(case_id, repetition)` and hashes that list with the same length-framed encoding
used for dataset entries. The stored map of processor to case-set hash is the
compatibility identity. Workers compare case files to the stored per-file hashes;
comparisons require equal case-set hashes, not merely equivalent-looking filter text.

### 6.3 Expected output

Each `expected.json` may contain one or both processor sections:

```json
{
  "schema_version": 1,
  "chunking": {
    "protected_groups": [
      {"group_id": "list-1", "kind": "non_numeric_list", "split_policy": "never", "lines": [2, 3]}
    ],
    "chunks": [
      {"sequence": 1, "overlap_lines": [], "normal_lines": [1, 2, 3]}
    ]
  },
  "extract_metrics": {
    "metrics": [
      {
        "gold_id": "m1",
        "metric_name": "Maximum response time",
        "metric_subject": "service endpoint",
        "metric_value": "200",
        "metric_unit": "ms",
        "is_explicit_metric": true,
        "source_lines": [2, 3]
      }
    ]
  }
}
```

Gold IDs are dataset-local identifiers and are not expected to match `kb.metrics.metric_id`.
Expected metric objects may include other stable `kb.metrics` fields when a case is
designed to test them.

`protected_groups.split_policy` is `never` or `expected`. `never` requires all listed
lines to remain in one normal chunk. `expected` is used for intentionally splittable
large numerical lists and treats the expected chunk assignment as the asserted policy.

## 7. Experiment Configuration

An experiment TOML declares the immutable intent of a comparison:

```toml
name = "metrics-model-comparison"
dataset = "doc-processors-synthetic-core@1.0.0"
processors = ["chunking", "extract_metrics"]
repetitions = 3
case_tags = []
timeout = "20m"
max_parallel_cases = 2
max_parallel_variants = 1
max_attempts = 2
attempt_lease = "25m"
allow_upstream_variation = false
retain_workspaces = false

[[variants]]
name = "baseline"

[variants.overrides]
CHUNK_SIZE = "300"
CHUNK_OVERLAP_PERCENT = "20"
EXTRACT_METRIC_CANDIDATES_PROMPT = "prompts/prompt-extract-metric-candidates-v3.md"
EXTRACT_METRIC_CANDIDATES_MODEL_NAME = "deepseek-chat"
ENRICH_METRICS_PROMPT = "prompts/prompt-enrich-metrics-v3.md"
ENRICH_METRICS_MODEL_NAME = "deepseek-chat"
METRIC_ENRICH_GROUP_SIZE = "5"
```

The exact prompt filename in checked-in examples must reference a real prompt and follow
ChenWeb prompt naming rules. The example above is a format example, not authorization to
create that particular prompt.

Configuration requirements:

- Variant names are unique within an experiment.
- Each benchmark adapter exposes `AllowedOverrides()` and `ResolvedConfig()`. The former
  is the versioned allow-list of non-secret settings for that processor; the latter is
  read from the fully initialized production processor and is the authoritative resolved
  snapshot, including production defaults. The validator rejects keys outside the union
  of the adapters in the selected processors' transitive dependency closure. V1's
  complete allow-list is:

  - `chunking`: `CHUNK_SIZE`, `CHUNK_OVERLAP_PERCENT`.
  - `extract_metrics`: `EXTRACT_METRIC_CANDIDATES_PROMPT`,
    `EXTRACT_METRIC_CANDIDATES_MODEL_NAME`,
    `EXTRACT_METRIC_CANDIDATES_MODEL_FALLBACK`, `ENRICH_METRICS_PROMPT`,
    `ENRICH_METRICS_MODEL_NAME`, `EXTRACT_METRICS_MODEL_NAME`,
    `METRIC_MERGE_RESOLVE_PROMPT`, `METRIC_MERGE_RESOLVE_MODEL_NAME`,
    `METRIC_MERGE_RESOLVE_MODEL_FALLBACK`, `METRIC_ENRICH_GROUP_SIZE`, and
    `EXTRACT_METRICS_MAX_TASKS`.

  All other keys are rejected in v1. Secret-bearing keys are never allow-listed. An
  `extract_metrics` experiment therefore resolves and hashes both the metric and
  `chunking` adapters even when `chunking` is not independently scored.
- Secrets are read from the worker environment and are never written to TOML, database
  snapshots, logs, or reports.
- The stored snapshot includes the prompt path and content hash, provider, model,
  requested model parameters from the selected model definition, relevant processor
  settings, concurrency settings, requested seed when the model definition supports it,
  and all defaults after resolution. V1 has no independent `provider`, `temperature`, or
  `seed` TOML fields; the model-reference override selects those values as one validated
  production configuration.
- A run stores both the requested model identifier and the provider-returned identifier
  when available.
- A run stores the Git commit ID, jj change/commit IDs when available, a dirty-worktree
  flag, and the SHA-256 of the worker executable. Official comparisons reject a dirty
  worktree by default. An explicit `--allow-dirty` run remains valid for exploration but
  is visibly marked non-reproducible.
- Model output may remain nondeterministic even when a seed and temperature are fixed;
  repetitions quantify that variation rather than claiming bit-for-bit reproducibility.

Chunking-only experiments default to one repetition. Experiments containing
`extract_metrics` default to three repetitions. `timeout` defaults to 20 minutes;
`max_parallel_cases` and `max_parallel_variants` default to 1; an empty `case_tags`
selects all applicable cases, while a non-empty list selects cases containing every
listed tag. Durations use Go duration syntax. `max_attempts` defaults to 2 and must be at least 1.
`attempt_lease` defaults to `timeout + 5 minutes` and must be longer than `timeout`.
`retain_workspaces` defaults to false. Workers heartbeat a running execution or rescore
attempt at least once per minute. All resolved defaults are stored in the experiment
and run snapshots.

## 8. Execution Flow

### 8.1 Orchestrator

The orchestrator:

1. Validates the experiment, fixture schemas, prompt paths, and content hashes.
2. Resolves the selected processors plus their transitive production dependencies. For
   each active variant, it starts an isolated worker in a pre-run handshake, bounded by
   `max_parallel_variants`; the worker initializes that dependency closure once and
   returns the authoritative `ResolvedConfig`, prompt/model hashes, and executable hash.
   The handshake start permit is released as soon as that response arrives, even though
   the initialized worker waits for its run ID. Execution authorization separately
   admits at most `max_parallel_variants` waiting workers, avoiding deadlock when the
   limit is 1.
3. Validates override policy and upstream pinning against those resolved snapshots, then
   computes dataset, code, configuration, prompt, and scorer hashes.
4. Creates the experiment and immutable variant runs and returns their IDs to the
   waiting workers. A replacement worker after a crash must re-resolve and match the
   stored hash before receiving work.
5. Expands every run into processor-applicable case/repetition work.
6. Records attempt results as workers complete.
7. On resume, expires stale leases, then creates only missing or permitted retry
   attempts under the stored run snapshot.
8. Aggregates and writes JSON and Markdown reports.

Different variants run in separate OS processes. This prevents unsafe mutation of
process-global environment configuration and ensures each production processor is
initialized exactly once from its variant snapshot.

### 8.2 Worker

For each fresh execution attempt, the worker:

1. Verifies the dataset hash and case-file hashes.
2. Creates a disposable workspace under `BENCHMARK_WORK_ROOT` and a separate immutable
   evidence directory under `BENCHMARK_EVIDENCE_ROOT`.
3. Allocates a case attempt, inserts a temporary `kb.inputs` record using
   benchmark-prefixed filenames, and inserts the exact ownership mapping in
   `kb.benchmark_workspaces`.
4. Copies the canonical fixture input into the location expected by the production
   loader.
5. Invokes `ControlService` directly with `operation: ["chunking"]` or
   `operation: ["chunking", "extract_metrics"]`.
6. Waits for a terminal state with the experiment timeout.
7. Captures status, `.chunks`, `kb.chunks`, `kb.metrics`, `.metrics`, doc-processor logs,
   LLM token/cache usage, latency, and errors as applicable.
8. Copies canonical evidence out of the workspace and database into the evidence
   directory and verifies its hashes before scoring.
9. Runs the versioned processor scorers.
10. Commits the case result before cleanup.

If scoring fails after capture and hash verification, a retry is a `rescore` attempt.
It references the original execution attempt, re-verifies the immutable artifact
hashes, and reruns only normalization/reconciliation/scoring; it creates no `kb.inputs`
row and makes no LLM call. The same rescore rule applies to any infrastructure failure
or stale lease after verified capture. A failure before verified capture retries as a
fresh `execution` attempt with a new input record and workspace.

JetStream message delivery is excluded because the benchmark measures processor output
quality, not event transport. Calling the production controller retains dependency
ordering, persistence, deduplication, status updates, and post-processing behavior.

### 8.3 Upstream attribution for metrics

`extract_metrics` always runs through its real `chunking` dependency with pinned
chunking settings. The benchmark publishes:

- end-to-end metric scores across all completed cases;
- conditional metric scores for cases whose chunking output passed required invariants;
  and
- an `upstream_invalid` diagnostic on cases where chunking may have affected metric
  extraction.

The system must not discard end-to-end results when chunking is wrong. Conditional
scores are an attribution aid, not a replacement headline.

For the default component comparison, every metric-extraction variant must resolve to
the same chunking configuration hash. The validator rejects differing upstream hashes.
Setting `allow_upstream_variation = true` permits a deliberate end-to-end pipeline
comparison; its report labels metric deltas as pipeline deltas and does not present the
conditional metric score as evidence about the metric prompt/model alone.

## 9. Chunking Scorer

The scorer parses only explicit `lines:` rows as normal chunk payload and treats
`overlap:` rows as overlap metadata, matching the chunking capsule.

Eligible normal lines are canonical input records whose case-folded `line_type` is not
`toc`. Ineligible lines are every input line excluded by that rule plus any line number
not present in the input. Source order is physical canonical-file order, not numeric
subtraction between line numbers. Expected output may include `protected_groups`, each
an ordered line set representing a table, formula, or list block whose split behavior is
asserted by that fixture.

A chunk boundary is the final normal line in source order for every non-final chunk.
Boundary and overlap evaluation uses exact line identities; v1 has no tolerance window.

Hard invariants are: contiguous chunk sequence numbers starting at 1; no ineligible
normal lines; every eligible line assigned exactly once as a normal line; normal lines
preserve source order; no overlap on the first chunk; every overlap line comes from the
immediately preceding chunk's normal lines; non-final normal payload byte size is at
least 80% of the resolved `CHUNK_SIZE`; overlap trimming follows the capsule's 20%/one
line rule; and fixture-declared protected groups obey their expected split policy.
Boundary placement and exact expected overlap are quality comparisons but are not
additional hard invariants. The scorer publishes stable rule IDs for all invariant
violations.

The sequence invariant applies when chunks exist. When the input has no eligible lines,
an empty expected and actual chunk array is valid and exact case pass is 1. When eligible
lines exist, an empty actual array violates the exactly-once coverage invariant and
exact case pass is 0.

Payload byte checks call the same production `lineRawForChunking`/`lineRawByteSize`
logic used by `BuildChunks`; the benchmark must not reimplement byte accounting.
`CHUNK_OVERLAP_PERCENT` controls the desired line overlap, while the 20%/one-line rule
is the production safety cap measured against `CHUNK_SIZE`; the latter remains 20%
regardless of the configured desired overlap percentage.

### 9.1 Metrics

| Metric | Definition |
|---|---|
| Exact chunk-sequence match | Actual and expected ordered chunks have identical normal and overlap line sets |
| Exact case pass rate | Proportion of cases with an exact chunk-sequence match and no hard invariant violation |
| Boundary precision/recall/F1 | Exact non-final end-boundary matches over actual and expected boundary sets |
| Normal-line coverage | Expected eligible normal lines present in at least one actual normal payload |
| Missing-line rate | Expected eligible normal lines absent from actual normal payloads |
| Extra-line rate | Ineligible or unexpected lines present in actual normal payloads |
| Duplicate normal-line rate | Normal-line assignments beyond the first, excluding declared overlap metadata |
| Reordered-line rate | Adjacent actual normal-line pairs that violate canonical source order |
| Overlap correctness | Precision/recall/F1 over expected versus actual `(chunk_sequence, line_number)` overlap assignments |
| Rule violations | Counts by rule, including TOC inclusion, undersized non-final chunks, sequence gaps, and split protected lists |

The primary chunking vector is exact case pass rate, boundary F1, normal-line coverage,
duplicate normal-line rate, overlap F1, and hard rule-violation count. No weighted
chunking composite is required.

Rate definitions and empty cases are fixed as follows:

- Normal-line coverage and missing-line rate divide by the number of eligible input
  lines. When there are none, coverage is 1 and missing rate is 0 only if the actual
  output has no normal lines; otherwise both are 0 and 1 respectively.
- Extra-line rate divides unexpected normal-line assignments by all actual normal-line
  assignments; an empty actual output has rate 0.
- Duplicate normal-line rate divides eligible assignments beyond the first by all
  actual eligible normal-line assignments; an empty denominator has rate 0.
- Reordered-line rate divides reversed adjacent normal-line pairs by all adjacent pairs;
  fewer than two assignments has rate 0.
- Boundary and overlap precision/recall use exact set intersection. If both sets are
  empty, precision, recall, and F1 are 1. If only the predicted set is empty, all three
  are 0. If only the expected set is empty, precision and F1 are 0 and recall is 1.
- Exact case pass is 1 only when the ordered normal and overlap line sets exactly match
  expected and no hard invariant is violated; otherwise it is 0.
- Rule-violation metrics report both cases-with-any-violation and raw counts by rule;
  raw counts are never averaged into the primary quality vector.

For every set metric outside its explicit empty-set case, precision is
`TP / (TP + FP)`, recall is `TP / (TP + FN)`, and F1 is the harmonic mean of precision
and recall.

### 9.2 Diagnostics

For each mismatch, the scorer records expected and actual chunk sequence, boundary,
missing/extra lines, overlap differences, and violated rule IDs. Diagnostics reference
line numbers and artifact hashes so the mismatch can be reproduced.

## 10. Metric Extraction Scorer

### 10.1 Normalization

Normalization is deterministic and versioned. V1 normalization includes:

- Unicode NFKC normalization, Unicode case folding, whitespace collapse, and leading
  and trailing Unicode whitespace/punctuation removal for textual identity fields;
- tokenization into maximal Unicode letter-or-number sequences; name and subject
  similarity is Jaccard similarity over the resulting token sets;
- base-10 decimal parsing without binary floating-point comparison; numerically equal
  decimals agree, while unparsable values agree only by normalized-text equality;
- a checked-in v1 unit alias map; units agree only when their normalized alias-map
  values are equal, with unknown units compared as normalized text; and
- sorted, de-duplicated source line sets.

SQL NULL, a missing JSON field, and an absent optional field all normalize to
`absent`. An empty or whitespace-only present string normalizes to `empty`. Neither
`absent` nor `empty` counts as exact agreement for edge eligibility or contributes text
similarity; token-set Jaccard is 0 when either token set is empty, including when both
are empty. Field accuracy still distinguishes gold `absent` from gold `empty` when a
fixture explicitly asserts the field.

The complete v1 unit alias map is:

| Canonical | Case-folded aliases |
|---|---|
| `ms` | `ms`, `msec`, `millisecond`, `milliseconds`, `毫秒` |
| `s` | `s`, `sec`, `second`, `seconds`, `秒` |
| `%` | `%`, `pct`, `percent`, `percentage`, `百分比` |
| `count` | `count`, `counts`, `item`, `items`, `次`, `个` |
| `byte` | `byte`, `bytes` |
| `kb` | `kb`, `kilobyte`, `kilobytes` |
| `mb` | `mb`, `megabyte`, `megabytes` |
| `gb` | `gb`, `gigabyte`, `gigabytes` |
| `°c` | `°c`, `celsius`, `摄氏度` |
| `°f` | `°f`, `fahrenheit`, `华氏度` |

Unit aliases normalize with NFKC, case folding, and whitespace trim/collapse but do not
strip punctuation or symbols; this preserves `%` and `°`. V1 intentionally omits
ambiguous single-letter byte aliases and does not convert quantities between units.

V1 does not attempt open-ended semantic equivalence or arbitrary unit conversion. A
normalization that changes scoring behavior requires a new scorer version.

### 10.2 Predicted-to-gold matching

The scorer constructs candidate edges between predicted and gold metrics. An edge is
eligible when the source-line sets intersect or at least two non-empty, present values
among normalized name, subject, value, and unit agree exactly. V1 edge weight is:

```text
0.35 * source-line Jaccard
+ 0.20 * name token-set Jaccard
+ 0.15 * subject token-set Jaccard
+ 0.20 * value agreement (0 or 1)
+ 0.10 * unit agreement (0 or 1)
```

Only eligible edges with weight at least `0.60` may be accepted. A deterministic
maximum-total-weight one-to-one bipartite match chooses the assignment. When multiple
global assignments have equal total weight, choose the lexicographically smallest
ordered list of `(gold_id, prediction_input_index)` pairs. `prediction_input_index` is
the zero-based order read from the canonical database query in section 11.

The v1 unit aliases, weights, eligibility rule, threshold, and tie-breaking rule are the
scorer configuration. They are checked into the benchmark scorer package as data,
covered by tests, serialized into the run snapshot, and included in the scorer hash.
Changing any of them creates a new scorer version.

Accepted matches are true positives. Unmatched predictions are false positives and
unmatched gold metrics are false negatives.

### 10.3 Metrics

| Metric | Definition |
|---|---|
| Detection precision/recall/F1 | Set metrics over accepted matches, unmatched predictions, and unmatched gold metrics |
| Exact value/unit accuracy | Matched metrics whose normalized value and unit both match gold |
| Value accuracy | Matched metrics whose normalized value matches gold |
| Unit accuracy | Matched metrics whose normalized unit matches gold |
| Source grounding precision/recall/F1 | Line-set agreement for accepted prediction/gold pairs |
| Stable-field accuracy | Per-field exact normalized accuracy over accepted matches where gold specifies the field |
| Duplicate prediction rate | Unmatched predictions whose best edge to any gold has weight at least `0.60`, divided by all predictions |
| Unsupported metric rate | Unmatched predictions whose best edge to every gold is below `0.60`, divided by all predictions |
| Explicit/implicit accuracy | Accuracy of `is_explicit_metric` over matched metrics with a gold label |

Field accuracy denominators include only accepted matches for which gold specifies that
field. Reports must always show the numerator and denominator, preventing sparse fields
from appearing deceptively strong.

For deterministic false-positive classification, compute every unmatched prediction's
best eligible edge to any gold metric, including gold metrics already assigned. It is a
duplicate when that best edge has weight at least `0.60`; otherwise it is unsupported.
Duplicate and unsupported rates divide their respective counts by total predictions;
when there are no predictions both rates are 0. These labels are mutually exclusive and
cover all unmatched predictions. “Unsupported” therefore means unsupported by the
complete synthetic gold set under scorer v1; it does not claim an open-ended semantic
judgment over prose.

Set-metric empty behavior is also fixed. If predictions and gold are both empty,
detection precision, recall, and F1 are 1. With no predictions and non-empty gold, all
three are 0. With predictions and empty gold, precision and F1 are 0 and recall is 1.
Matched-only field, value/unit, grounding, and classification metrics with a zero
denominator are stored as null with numerator and denominator 0; they are not converted
to perfect scores.

Grounding precision/recall/F1 pools line-level true-positive, false-positive, and
false-negative assignments only across accepted metric matches. When there are no
accepted matches, all three grounding metrics are null. Detection empty-set rules do
not apply to grounding.

The primary metric vector is detection precision/recall/F1, exact value/unit accuracy,
source grounding F1, duplicate prediction rate, and unsupported metric rate. No weighted
metric-extraction composite is required.

### 10.4 Diagnostics

Each case report includes accepted match pairs with component weights, unmatched gold
metrics, unmatched predictions, field-level differences, suspected duplicates, and
unsupported source spans. The diagnostic record identifies the scorer version and
normalization version.

## 11. Result Storage

All project schema changes use goose migrations. Table names below are the required
logical model; column details may be refined during implementation planning while
preserving the stated provenance and immutability contracts.

### 11.1 Canonical actual outputs

Adapters reconcile every official output before scoring:

- For `chunking`, the `.chunks` artifact is canonical for ordered normal and overlap
  line assignments. `kb.chunks` is canonical for run metadata. The adapter reconstructs
  the table's ordered line arrays and requires them to agree with the artifact. It runs:

  ```sql
  SELECT id, chunking_method, chunking_size, overlap_percent, notes,
         overlap_lines, normal_lines, chunk_lines, create_time, update_time
  FROM kb.chunks
  WHERE source_record_id = $1
  ORDER BY id ASC
  ```

  The adapter requires exactly one row for the fresh benchmark input and parses
  `normal_lines` and `overlap_lines` as ordered arrays indexed by chunk sequence.
- For `extract_metrics`, `kb.metrics` is canonical for scored metric rows. The query is
  exactly:

  ```sql
  SELECT to_jsonb(m) AS row
  FROM kb.metrics AS m
  WHERE m.input_record_id = $1
  ORDER BY m.metric_id COLLATE "C" ASC NULLS LAST, m.id ASC
  ```

  This order defines
  `prediction_input_index`. The `.metrics` artifact must agree after normalization on
  `metric_id`, `metric_name`, `metric_subject`, `metric_value`, `metric_unit`,
  `is_explicit_metric`, and `source_line_spans`. These are the v1 stable core fields;
  other fields are captured and may be scored when gold specifies them but do not make
  reconciliation fail.
- Production logs and LLM usage records are canonical for timing, token, and cache
  telemetry but never override quality output.

A missing canonical source or a disagreement between database and file representations
is `invalid_output`. The adapter captures both representations and a reconciliation diff
before returning that status; it must not silently select the more favorable output.

Before cleanup, adapters serialize database-only canonical rows to versioned JSON,
including column names, nulls, and query order, and store the captured file and hash as a
benchmark artifact.

### 11.2 Tables

| Table | Purpose | Required identity/provenance |
|---|---|---|
| `kb.benchmark_experiments` | User intent and original matrix | experiment ID, name, dataset ID/version/hash, request TOML/hash, timestamps |
| `kb.benchmark_runs` | One immutable variant execution | run ID, experiment ID, variant, lifecycle, code revision, configuration/prompt/scorer hashes, resolved snapshot, aggregate usage/runtime |
| `kb.benchmark_case_runs` | One logical case repetition | case-run ID, run ID, case ID, repetition, derived lifecycle, selected attempt ID |
| `kb.benchmark_case_attempts` | Append-only execution/rescore history | attempt ID, case-run ID, attempt number, kind, source execution attempt ID, immutable `input_record_id_snapshot`, lifecycle, lease/heartbeat, failure class, timings, usage, actual provider/model IDs |
| `kb.benchmark_workspaces` | Persistent ownership guard for DB/file cleanup | execution attempt ID, nullable input record ID FK, canonical working directory, allocation nonce, cleanup state/error |
| `kb.benchmark_scores` | Normalized scalar metrics | attempt or run ID, processor, scorer version, metric, slice, direction, nullable value, numerator, denominator |
| `kb.benchmark_artifacts` | Captured input, expected, actual, log, diagnostic, and report files | attempt/run owner ID, artifact kind, path, SHA-256, size |

Required constraints include:

- unique `(run_id, case_id, repetition)`;
- unique `(case_run_id, attempt_number)` and at most one selected attempt per case run;
- unique workspace execution attempt and unique non-null workspace input record ID;
- append-only completed run and case-result payloads;
- foreign keys from scores and artifacts to their owners;
- no database secret fields; and
- indexes for experiment/run lookup, case diagnostics, processor/metric comparisons,
  and resumable lifecycle queries.

`kb.benchmark_workspaces.input_record_id` references `kb.inputs(id)` with `ON DELETE SET
NULL`. Its row is the sole authority that an input record and working directory belong
to the benchmark. The workspace row persists after cleanup with `cleanup_state =
"cleaned"`; attempts retain the immutable numeric input ID and captured evidence.

The module registers its tables/migrations through the existing ChenWeb startup and
migration conventions. Benchmark rows are not mixed with `kb.doc_proc_logs`; the
benchmark captures references and normalized usage from those production logs.

## 12. Failure and Cleanup Semantics

Case-run lifecycle values distinguish at least:

- `pending`;
- `running`;
- `success`;
- `processor_failed`;
- `timed_out`;
- `invalid_output`;
- `infrastructure_failed`;
- `scorer_failed`; and
- `canceled`.

A missing or conflicting official processor artifact is `invalid_output`.
`infrastructure_failed` is reserved for benchmark harness, worker-process, database,
or filesystem failures outside the processor's quality result. Every
`infrastructure_failed` attempt is retryable subject to verified-capture routing and the
attempt budget; configuration/validation failures occur before attempts are created.

Rules:

1. Every applicable case repetition has a nullable `processor_success`: 1 for a
   reconciled, scoreable output; 0 for processor failure, timeout, missing artifact, or
   invalid output; and null while infrastructure/scorer failure leaves quality
   unobserved. Quality failures are represented by that metric, their failure class, and
   null processor-quality metrics. They are never converted to zero for lower-is-better
   rates, which would make failure look perfect.
2. Reports show `processor_success` and `scored_case_repetitions /
   total_case_repetitions` before other quality metrics. Quality aggregates use only
   scoreable outputs and expose that coverage; failed outputs therefore cannot disappear
   behind an unlabeled average.
3. Infrastructure and scorer failures leave `processor_success` null. They do not
   fabricate a quality score, mark the comparison incomplete, and the report must
   not claim one variant is better while any compared variant has unscored work.
4. Caller cancellation closes the active attempt as `canceled`, leaves
   `processor_success` null, selects that attempt, and marks the run incomplete. It is
   not retried by automatic resume. Re-running canceled work requires a new experiment
   run, preserving the original operator decision and history.
5. Resume reuses only the same immutable run snapshot and fills missing work. A
   retryable `infrastructure_failed` or `scorer_failed` attempt appends the next attempt
   number under the same logical case run. Attempts are never overwritten. The first
   terminal non-retryable attempt becomes `selected_attempt_id`; if all permitted
   retries fail, the latest attempt is selected and the case remains incomplete.
   Retry kind depends on evidence state, not only the failure label: if the failed or
   stale attempt has a verified capture (directly or through its source execution
   attempt), append a rescore attempt over that evidence; otherwise append a fresh
   execution attempt. Thus a stale rescore and a post-capture infrastructure failure
   never rerun the LLM. `scorer_failed` is retryable only with verified capture.
   Processor-quality outcomes are non-retryable within a run; rerunning one creates a
   new run.
   A live orchestrator appends an allowed retry immediately after recording the failed
   attempt. Resume applies the identical rule to previously recorded failures and stale
   leases.
6. Reports read scores and artifacts only from the selected attempt while retaining the
   full attempt history for audit. When the selected attempt is a rescore, its source
   execution attempt supplies the captured input/actual/log artifacts; the report follows
   that explicit reference and verifies the stored hashes again.
7. First failure details are retained together with later cleanup errors.
8. No logical case run may exceed the resolved `max_attempts`, counting execution and
   rescore attempts together. On resume, a `running` attempt whose heartbeat is older
   than its resolved `attempt_lease` is atomically closed as `infrastructure_failed`
   with reason `stale_lease`; a retry is appended only when the attempt budget remains.
   A non-stale running attempt is left untouched.

After a terminal attempt commits, the worker automatically cleans temporary production
rows and working files when evidence is verified and `retain_workspaces = false`.
When retention is true, only the explicit `clean` command performs it. Cleanup first
locks and verifies the matching
`kb.benchmark_workspaces` ownership row, then calls the processor adapters' explicit
cleanup routines in reverse topological dependency order, all within the same database
transaction, deletes the exact `kb.inputs` row, commits, and finally
removes the working directory. No cleanup query may use a broad filename, timestamp, or
age predicate. Deleting the input sets the workspace input ID to null but preserves the
workspace row and its canonical directory authority. After filesystem removal, cleanup
marks that row `cleaned`; if removal fails, it records the error and leaves it
`files_pending`, so `clean` can verify and retry the same path. Immutable attempts,
captured JSON/files, scores, hashes, and the input ID snapshot remain. A database cleanup
failure rolls back that cleanup transaction. Failed capture or failed hashing performs
no automatic cleanup. The normal `clean` path requires verified evidence hashes.
`clean --discard-unverified --attempt-id <id>` is the explicit recovery path when
capture never completed; it requires a single attempt ID and deletes only disposable
production/workspace state, records that unverified evidence was discarded, and never
deletes verified evidence. Capture uses attempt-scoped `.partial` names in the evidence
directory; these are not valid evidence until the verified marker commits. The
unverified-discard path may remove only that attempt's exact `.partial` entries after
the same root/path/nonce checks.

Immediately before any recursive workspace removal, cleanup resolves the configured
work root and stored workspace path, requires the workspace to be a strict descendant
of that root, `lstat`s every path component from the root downward, rejects symlinks or
root replacement, and verifies an allocation-time marker containing the attempt ID and
random workspace nonce. The work and evidence roots are checked again for
non-overlap. Any failed check stops cleanup and records an error; exact database
ownership alone is not sufficient authorization to remove a filesystem path.

## 13. Statistical Comparison

Chunking normally has one repetition. LLM-backed metric extraction defaults to three.
The sampling unit is one applicable `(case_id, repetition)`. A repeated case has the
same weight on every repetition; variants are paired only on the same case and
repetition. Every score declares its aggregation kind and direction in the versioned
scorer definition:

- **Binary/rate macro:** exact case pass, processor success, and scalar per-output rates
  aggregate as the arithmetic mean across non-null sampling units. Reports also show
  median and population standard deviation.
- **Count-derived micro:** detection, boundary, overlap, and grounding
  precision/recall/F1 are recomputed from pooled numerators and denominators, not
  averaged from per-case F1 values. Reports may also show the macro distribution as a
  diagnostic, clearly labeled `macro`. Scorers emit the additive components required
  for recomputation (`tp`, `fp`, and `fn`, or their named equivalent) as score rows.
- **Matched-field micro:** value, unit, value/unit, field, and explicit/implicit
  accuracies sum correct and eligible counts across sampling units. A zero pooled
  denominator yields null, never 0 or 1.
- **Raw counts:** failure classes and rule violations are summed and also reported as
  cases-with-any/count-total; they are not averaged as quality scores.
- **Operational measures:** latency, tokens, cache tokens, and cost report count, sum,
  mean, median, and population standard deviation over completed attempts.

For detection, boundary, and overlap precision/recall recomputed from pooled counts, the
empty-set rules in sections 9 and 10 apply after pooling. Pooled grounding is null when
there are no accepted matches, as required by section 10. Every aggregate stores and displays its numerator,
denominator, number of non-null sampling units, applicable total, and aggregation kind.

For a headline micro metric, the headline variant delta is `variant_B_pooled_micro -
variant_A_pooled_micro`. A separate distribution of per-sampling-unit deltas may be
reported only under a `paired_macro_diagnostic` label; it includes arithmetic mean,
median, population standard deviation, and `paired_units / applicable_units`. Binary
and scalar macro metrics use that paired distribution as their headline delta. V1 does
not calculate confidence intervals or hypothesis tests and does not make an automatic
winner decision. Slice reports use the same formulas over processor-applicable cases
carrying the selected tag.

Runs with different dataset hashes, scorer versions, or incompatible case filters are
not directly comparable by default. An explicit override may produce a report, but the
report must carry a prominent incompatibility warning and omit winner-like language.

## 14. Operator Interface

V1 provides a CLI:

```bash
go run ./server/cmd/doc-benchmark validate \
  --experiment benchmark/doc-processors/experiments/metrics-model-comparison.toml

go run ./server/cmd/doc-benchmark run \
  --experiment benchmark/doc-processors/experiments/metrics-model-comparison.toml

go run ./server/cmd/doc-benchmark compare --experiment-id <id> \
  --baseline <variant> --candidate <variant>
go run ./server/cmd/doc-benchmark report --experiment-id <id> \
  --format json --output <path>
go run ./server/cmd/doc-benchmark clean --experiment-id <id>
```

Command contracts:

- `validate` performs no pipeline or database mutations.
- `run` creates or resumes an experiment identified by the experiment content hash; a
  changed configuration creates a new experiment/run identity.
- `compare` compares named variants or runs and refuses incompatible results unless an
  explicit `--allow-incompatible` override is provided.
- `report` writes machine-readable JSON and human-readable Markdown.
- `clean` removes only retained temporary production data and working artifacts, not
  immutable benchmark results or captured evidence.

V1 has no web UI or public HTTP API.

## 15. Report Contract

Every report contains:

1. Experiment, dataset, code, prompt, configuration, normalization, and scorer
   provenance.
2. Completion coverage and failure taxonomy before quality metrics.
3. Per-processor primary metric vectors.
4. Paired variant deltas.
5. Per-tag/slice results with sample sizes.
6. Lowest-scoring cases with captured artifact and diagnostic references.
7. Latency, input/output/cache tokens, prompt-cache hit/miss tokens, and estimated cost.
8. Explicit incompatibility or incomplete-comparison warnings.

Cost is calculated from a versioned pricing snapshot stored with the report. Raw token
counts remain authoritative because provider pricing can change.

Reports show Pareto trade-offs rather than computing one cross-processor score. For
example, an operator can see that one metric model improves recall while increasing
unsupported predictions, latency, and cost.

## 16. Concurrency and Isolation

- Variant configuration isolation is provided by separate worker processes.
- Case parallelism is bounded by `max_parallel_cases` and existing doc-processor/LLM
  concurrency controls.
- Every case has a distinct `kb.inputs` row and artifact directory.
- Claiming a logical case run and allocating its next attempt are transactional. Attempt
  writes are idempotent only while that attempt is non-terminal; a terminal attempt is
  append-only.
- Database uniqueness constraints, not in-process locks, protect run/case identity.
- Benchmark runs must not reuse production document artifacts or processor results.
- The report records concurrency settings because they affect latency and prompt-cache
  behavior.

## 17. Verification

### 17.1 Fixture and scorer tests

- Manifest/schema validation and canonical dataset hashing.
- Duplicate ID, unknown tag, missing file, stale reference, and invalid source-span
  rejection.
- Chunk boundary, coverage, duplication, reordering, overlap, and rule-violation scoring.
- Metric normalization and deterministic bipartite matching, including stable ties.
- Per-field numerator/denominator handling and aggregate math.
- Scorer-version changes when matching or normalization behavior changes.

### 17.2 Mutation tests

The suite must prove the benchmark detects deliberate defects:

- shifted, missing, extra, and reordered chunk lines;
- incorrect overlap and split protected lists;
- missing and extra metrics;
- wrong metric values and units;
- duplicate metrics;
- unsupported/hallucinated source spans; and
- incorrect explicit/implicit classification.

### 17.3 Integration tests

- Run a fixture through the production controller and score persisted `.chunks`,
  `kb.chunks`, `kb.metrics`, and `.metrics` outputs.
- Verify configuration and prompt isolation between variants.
- Verify deterministic chunking output and hashes for identical inputs/configuration.
- Verify timeout, process crash, partial failure, cancellation, resume, and cleanup.
- Verify stale execution and rescore leases choose retry kind from verified-capture
  state, and post-capture infrastructure failure never reruns the LLM.
- Verify cleanup without captured hashes requires the explicit unverified-discard path,
  rejects symlink/path escapes, and never removes immutable evidence.
- Verify canonical queries ignore unrelated `kb.chunks` and `kb.metrics` rows.
- Verify interrupted writes do not produce terminal partial results.
- Verify concurrent workers cannot claim the same case repetition.
- Verify secrets are redacted from snapshots, logs, diagnostics, and reports.
- Validate goose migrations and down migrations.

### 17.4 Acceptance criteria

V1 is accepted when it can:

1. Compare at least two chunking configurations and two metric-extraction
   configurations over the same immutable dataset.
2. Exercise the production controller and score its persisted outputs.
3. Retain or explicitly account for every case/repetition outcome.
4. Detect every mutation listed in section 17.2.
5. Report quality, latency, token use, prompt-cache use, and cost with full provenance.
6. Audit and deterministically re-run normalization, reconciliation, and scoring for any
   result from verified evidence. Replaying production inference additionally requires
   checking out the stored clean VCS revision and supplying credentials externally; LLM
   output is not promised to be bit-identical. Dirty exploratory runs remain explicitly
   non-reproducible.
7. Refuse or prominently mark incomplete and incompatible comparisons.

## 18. Documentation Impact

Implementation changes the following knowledge:

- This design becomes the source for benchmark architecture and scoring contracts.
- A database schema document must describe the benchmark tables and retention model.
- Operator documentation must describe dataset creation, experiment configuration,
  commands, reports, failure recovery, and cleanup.
- The doc-processor capsule must reference benchmark invocation, provenance capture,
  and the implemented pilot processors.
- Processor specs remain authoritative for output semantics; benchmark scorer changes
  must follow those specs rather than silently redefining quality.

No existing processor prompt or runtime behavior changes merely by adopting this spec.
Until implementation, the doc-processor capsule, schema docs, and operator docs remain
unchanged rather than partially documenting unavailable behavior.

## 19. Out of Scope for V1

- PDF parsing/OCR quality.
- Human-annotated production documents.
- LLM-as-judge scoring.
- A combined pipeline-wide quality score.
- CI release gating.
- A browser dashboard.
- Automatic prompt optimization.
- External MLflow, LangSmith, or Promptfoo integration.
- Evaluators for processors other than `chunking` and `extract_metrics`.
- Automated retention or purge of verified benchmark evidence.

## 20. References

- Doc Processor Capsule:
  `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- Chunking Capsule:
  `KnowledgeStore/Capsules/coding-capsules/chunking/+CAPSULE.md`
- Extract Metrics Spec:
  `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`
- Canonical Line File Spec:
  `KnowledgeStore/doc-repo/specs/202604/2026042101-spec-line-file.md`
- [MLflow: Building evaluation datasets][mlflow-datasets]
- [MLflow: Experiment tracking][mlflow-tracking]
- [LangSmith: Manage and version datasets][langsmith-datasets]
- [Promptfoo: Assertions and metrics][promptfoo-metrics]

[mlflow-datasets]: https://mlflow.org/docs/latest/genai/datasets/
[mlflow-tracking]: https://mlflow.org/docs/latest/ml/tracking/
[langsmith-datasets]: https://docs.langchain.com/langsmith/manage-datasets
[promptfoo-metrics]: https://www.promptfoo.dev/docs/configuration/expected-outputs/
