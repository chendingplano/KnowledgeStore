# Operating the Gold Ventilator-Display Benchmark
**Date:** 2026-07-30\
**Scope:** `ChenWeb/benchmark/doc-processors/gold/display-module-v1` (the synthetic "呼吸机 display module" corpus, ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` DR12/DR22) and its execution tooling, `ChenWeb/server/cmd/doc-benchmark` (`gold-run`, `analyze` subcommands) plus the three `mise` tasks that wrap them.\
**Audience:** Written so both a human and Claude Code can run this benchmark end-to-end without re-deriving the safety rules or re-discovering the gotchas below — several of which were hit for real while building this tooling.

## 1. What this benchmark is

The gold corpus is nine **synthetic** authority documents (national/international/EU/US/enterprise standards, all fictional — `cn-gb-syn-*`, `intl-iso-syn-*`, `ent-q-syn-*`, etc.) describing a ventilator display module, hand-authored in `gold.toml` alongside their exact expected metrics and verdicts. Because the fixture is synthetic, the exact source text of every document is known precisely — this is what makes automated scoring and LLM-based review possible without a human re-reading each document.

Two independent evaluation paths exist over this same corpus:

1. **Deterministic, metrics-only scoring** (`server/api/doc-benchmark/verdict_score.go`, `benchmark/doc-processors/gold/display-module-v1/{resolve,coverage}.go`) — exact comparison against `gold.toml`'s hand-authored `expected_verdict` rows and per-clause `expectation` (required vs. best-effort). This is the precise path, but it only exists for `extract_metrics`. See bug reports `2026073001`–`2026073003` (`KnowledgeStore/doc-repo/bugs/202607/`) for the investigation that used it.
2. **Generic, LLM-judged review** (`analyze`, §4 below) — works for *any* processor, because the LLM is given the exact source text directly and reads for plausibility, rather than needing a hand-authored answer key. Lower precision than path 1, but the only option for provisions/entities/relations/inventory-items/etc., which have no gold answer key today.

This doc covers the **execution tooling** common to both: how to run the corpus through real processors and get either raw data or an LLM report out of it. It does not re-explain the deterministic scorers' internals — see the files above and ADR `2026072901-adr` DR21/DR22 for those.

### 1.1 Is this benchmark ventilator-specific?

Both, in a specific way — the **tooling is domain-agnostic**, but the **current gold corpus is deliberately written for ventilators**, not incidental filler:

- **Mechanism** (`gold-run`, `analyze`, `docbenchmark.CorpusDataset`, the `gold.File`/`Clause`/`MetricDefinition` Go types): fully generic. Nothing in the code references ventilators, displays, or medical devices — it reads whatever `manifest.json` + `gold.toml` `--dataset`/`--case` points at, generates CDM documents from generic `clause`/`text_template` entries, and runs them through real processors. A different domain can be added as a new dataset/case with zero code changes (this is exactly why the `DATASET_ROOT`/`CASE_ID` overrides in §3.3 exist).
- **Content** (`benchmark/doc-processors/gold/display-module-v1/gold.toml`): specifically authored for a ventilator display module — the 9 documents are synthetic GB/ISO/IEC/EU/FDA/enterprise standards about display brightness, contrast, alarms, touch response, etc., and the metrics/verdicts are hand-written against that specific content.

This was a deliberate choice, not an accident: per ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md`, one of the architecture's open decisions (OD1) was picking a concrete pilot domain to validate the whole ontology/comparison design against, and it was resolved to ventilator/medical-device (呼吸机/医疗器械) — a real-world case with genuine cross-standard comparison complexity (national vs. international vs. enterprise specs disagreeing on the same metric), rather than a toy example. The `v1` in the directory name and `display-module` in the dataset ID both signal this is expected to be one instance of a pattern, not the only one ever intended — see §7 for how to add more.

So: today, running this benchmark *is* running a ventilator benchmark, because that's the only fixture that exists. Nothing about the tooling stops a second `gold.toml` for a different product category from being added later and reusing every command this doc describes, unchanged.

## 2. Safety model — read this before running anything

**This benchmark must never touch the production database or production artifact directories.** `ChenWeb/mise.local.toml` (and its host-specific sibling `mise.local-bzton.toml`) set `PG_DB_NAME=miner`, `ARTIFACT_DIR=/Users/cding/Apps/SemOS/Artifacts`, `ARTIFACT_WEB_DIR=/Users/cding/Apps/SemOS/ArtifactWeb` — these are **real, working production values**, not placeholders.

Instead, this benchmark runs against:
- **Database:** `chenweb_test` (a disposable Postgres database, same server as production, different name)
- **Artifacts:** `ThirdParty-2/Data/Artifacts` and `ThirdParty-2/Data/ArtifactWeb` (on the attached SSD at `~/Workspace/ThirdParty-2/Data/`, a pure-data directory unrelated to any code checkout)

All three `mise` tasks below (`gold-benchmark-run`, `gold-benchmark-run-all`, `gold-benchmark-analyze`) **hardcode** `PG_DB_NAME`/`ARTIFACT_DIR`/`ARTIFACT_WEB_DIR` to these benchmark values as unconditional `export` statements in the task body — **not** `${VAR:-default}` fallbacks. This is deliberate: because `mise.local.toml` already exports the production values into every task's environment before the task body runs, a fallback-only-if-unset pattern would silently keep the *production* values (since they're never actually "unset" from mise's point of view) instead of overriding them. If you ever edit these tasks, preserve the unconditional `export`, or you will point the benchmark at production without any error or warning.

**Never edit `mise.local.toml`/`mise.local-bzton.toml` for this purpose.** All isolation is done via env var overrides at invocation time, inside the task body — this is why the tasks work correctly regardless of which values happen to be in the ambient shell.

Both the `chenweb_test` database and the `ThirdParty-2/Data` artifact directories are themselves disposable — nothing written there needs preserving between benchmark runs, and both can be wiped/recreated if state gets confusing (§6.1).

Every non-dry-run invocation makes **real, paid LLM calls** (DeepSeek, currently `deepseek-v4-flash-300` / `deepseek-flash-chen` depending on which processor). There is no mocking. Cost scales with `documents × processors`. Always try `--dry-run` (or a `--document` filter, §3.3) before a full run you haven't run before.

## 3. `gold-run` — execute the corpus through real doc processors

**Working directory: `ChenWeb/`.** All three `mise` tasks (and any manual `go run ./server/cmd/doc-benchmark ...` invocation) must be run from the `ChenWeb` repo root — that's where `mise.toml` lives, and every path inside the tasks (`benchmark/doc-processors/gold/display-module-v1`, `./server/cmd/doc-benchmark`) is relative to it.

```bash
cd ~/Workspace/ChenWeb
```

### 3.1 Single processor

```bash
PROCESSOR=extract_metrics mise run gold-benchmark-run
```

This is a thin wrapper (`mise.toml`) around:

```bash
cd ~/Workspace/ChenWeb
export PG_DB_NAME=chenweb_test
export ARTIFACT_DIR=/Users/cding/Workspace/ThirdParty-2/Data/Artifacts
export ARTIFACT_WEB_DIR=/Users/cding/Workspace/ThirdParty-2/Data/ArtifactWeb
go run ./server/cmd/doc-benchmark gold-run \
  --dataset benchmark/doc-processors/gold/display-module-v1 \
  --case display-module-v1 \
  --artifact-root "$ARTIFACT_DIR" \
  --artifact-web-root "$ARTIFACT_WEB_DIR" \
  --processors "$PROCESSOR"
```

`PROCESSOR` is required — the task fails fast with a clear message if unset. Valid values are any of the 11 names in §3.2, comma-separated for more than one (e.g. `PROCESSOR=extract_metrics,extract_provisions`), or the literal `all`.

### 3.2 Every processor at once

```bash
mise run gold-benchmark-run-all
```

Equivalent to `PROCESSOR=all mise run gold-benchmark-run` (it literally delegates to that task — no duplicated logic to drift out of sync). Runs, per document, every processor `docprocessing.ProductionRuntime` knows:

```
generate_summaries, generate_topics, extract_doc_metadata,
extract_semantic_projections, extract_structured_knowledge,
extract_entity, extract_relation, extract_inventory_items,
extract_metrics, extract_provisions, generate_scene_blocks
```

(`static_analyzer` and `chunking` always run too — they're mandatory prerequisites forced on by `docprocessing.resolveRequiredProcessors` regardless of what's requested, so there's no flag for them.)

Not every processor has a queryable per-record result table — see the note in §3.4 about `generate_summaries`/`generate_topics`.

### 3.3 Useful extra flags (pass through after `--`)

```bash
# Smoke-test on the smallest document before spending on all nine:
PROCESSOR=extract_metrics mise run gold-benchmark-run -- --document "doc:ent-mkt-syn-2025"

# Free dry run: generates documents, writes kb.inputs rows + line files,
# skips the LLM/RunEvent step entirely. Always safe, no cost.
PROCESSOR=all mise run gold-benchmark-run -- --dry-run

# Point at a different corpus case as more documents/cases get added later
# (today there is only one case, "display-module-v1", in one dataset root):
DATASET_ROOT=benchmark/doc-processors/gold/some-new-case CASE_ID=some-new-case \
  PROCESSOR=extract_metrics mise run gold-benchmark-run
```

`doc:ent-mkt-syn-2025`, `doc:ent-q-syn-001-2019`, `doc:ent-q-syn-002-2024`, and `doc:intl-iec-syn-60601-1-8-2020` are the four one-line, one-block documents in the fixture — cheapest to use for a smoke test. `doc:cn-gb-syn-9706-1-2020`, `doc:eu-harm-syn-2021`, and `doc:ent-q-syn-001-2026` are the largest (8 blocks each).

### 3.4 Reading the output

`gold-run` prints one JSON object to stdout (all the INFO-level logging goes to stderr — redirect stdout alone to capture just the result):

```bash
PROCESSOR=extract_metrics mise run gold-benchmark-run > /tmp/run.json 2>/tmp/run.log
```

Shape:

```jsonc
{
  "dry_run": false,
  "results": [
    {
      "document": "doc:cn-gb-syn-9706-1-2020",
      "record_id": 47,
      "line_file": "/Users/cding/Workspace/ThirdParty-2/Data/Artifacts/0/47/doc:cn-gb-syn-9706-1-2020_gold-run.txt",
      "line_count": 8,
      "block_count": 8,
      "results": {
        "extract_metrics": [ { /* one map per kb.metrics row, every column, verbatim */ } ]
      }
      // "run_error": "..."   <- present instead of "results" if RunEvent failed for this document
    }
  ]
}
```

`entry.results` has one key per requested processor:
- An **array of row maps** (every column from that processor's output table — see the registry in `server/cmd/doc-benchmark/gold_run.go`'s `processorResultTables`) for the 9 processors with a registered per-record table: `extract_metrics` → `kb.metrics`, `extract_provisions` → `kb.provisions`, `extract_entity` → `kb.entities`, `extract_relation` → `kb.relations`, `extract_inventory_items` → `kb.inventory_items`, `extract_semantic_projections` → `kb.semantic_projections`, `extract_structured_knowledge` → `kb.knowledges`, `generate_scene_blocks` → `kb.scene_objects`, `extract_doc_metadata` → `kb.inputs` (the row itself, since this processor writes columns directly onto `kb.inputs` rather than a child table).
- The **string** `"not applicable: no per-record result table registered for this processor"` for `generate_summaries`/`generate_topics` — their output is chunk-derived artifacts, not a queryable per-record row set. If you need to inspect their output, do it directly against the DB/artifact files; this tool won't do it for you.

### 3.5 Artifact layout

Every document gets a real `kb.inputs` row (type `'cdm'`, `parser_name='gold-run'`) and files at `<ARTIFACT_DIR>/<recordID/1000>/<recordID>/` — `theme.typ`, `<doc-key>_gold-run.typ` (rendered Typst source), `<doc-key>_gold-run.txt` (the line file every processor actually reads), plus whatever each processor writes there (`*.chunks`, etc.). This deliberately mirrors the bucketing formula real PDF-origin documents use elsewhere in `docprocessing` (`recordID / 1000`), so a CDM-origin gold-run record's artifact directory is indistinguishable in layout from a real upload's — this was a real bug caught and fixed earlier (see `prepareGoldInput`'s doc comment in `gold_run.go`).

## 4. `analyze` — LLM-judged extraction-quality report

```bash
RESULTS=/tmp/run.json mise run gold-benchmark-analyze
```

Wraps:

```bash
go run ./server/cmd/doc-benchmark analyze \
  --dataset benchmark/doc-processors/gold/display-module-v1 \
  --case display-module-v1 \
  --results "$RESULTS" \
  [--output "$OUTPUT"]
```

This is a **pure post-processing step over `gold-run`'s own JSON** — it never touches the database itself. For each document in `$RESULTS`, it reconstructs that document's exact source text from `gold.toml`'s clauses (the same prose the processors actually saw) and pairs it with that document's raw processor-result rows, then sends both to a real LLM (model ref `deepseek-flash-chen` by default, override with `--model` or `ANALYZE_BENCHMARK_MODEL_NAME`) using the externalized prompt `prompts/prompt-analyze-benchmark-results-v1.md`. It asks the LLM to judge, per document/processor: coverage (is anything in the source text missing from the output?), correctness (does any row assert something the source doesn't say?), and wording faithfulness — and to write a Markdown report, not just restate the JSON.

`OUTPUT` is optional (`OUTPUT=/tmp/report.md mise run gold-benchmark-analyze`) — omitted, the report goes to stdout.

Because it's a second real LLM call (over the *whole* results file in one prompt, not per-document), keep `$RESULTS` reasonably sized — for a full 9-document × 11-processor run this will be a large single call. If that ever becomes a real accuracy problem (the model losing track of later documents in a long input), split `$RESULTS` and run `analyze` once per chunk; nothing about the tool requires a single call across the whole corpus, that's just the simplest thing that worked when it was built.

Important: `analyze` has **no answer key** for anything except `extract_metrics` (§1) — it judges plausibility against source text via close reading, which is real evidence but not the same guarantee as the deterministic scorers. Treat its report as a first-pass triage, not a final verdict, especially for processors it hasn't been validated against yet.

## 5. Prerequisites checklist

- `chenweb_test` database exists, owned by `admin`, migrated (§6.1 if it isn't).
- `~/Workspace/ThirdParty-2/Data/Artifacts` and `.../ArtifactWeb` exist (`mkdir -p` if not — they're plain directories, nothing special).
- `typst` on `PATH` (`gold-run` calls `exec.LookPath("typst")` and fails immediately if missing).
- Real LLM credentials resolvable — `.models.toml` (`MODEL_DEF_FILE`, defaults to `ChenWeb/.models.toml`) must have the model refs used (`deepseek-v4-flash-300`/`deepseek-flash-chen` by default across processors; check `mise.local-bzton.toml`'s `*_MODEL_NAME` entries for the exact ref each processor is currently pinned to).
- Environment loaded via `mise` (either run the tasks through `mise run ...` directly, which loads the environment automatically, or `eval "$(mise env)"` first if invoking `go run ./server/cmd/doc-benchmark ...` by hand outside a task). Without this, `bootstrap()` panics on `missing APP_HOST env variable` — this isn't a benchmark-specific issue, it's the same config bootstrap every ChenWeb binary uses.

## 6. Troubleshooting / gotchas actually hit while building this

### 6.1 `chenweb_test` migration state looks broken (e.g. `pq: column "desc" does not exist`)

If `chenweb_test` was created by dumping/restoring production data rather than a clean goose migration replay, goose's own bookkeeping table can be inconsistent with the schema, causing a migration replay to fail partway. Since this database is explicitly disposable (§2), the fix is to drop and recreate it rather than debug the migration history:

```sql
-- terminate connections first
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'chenweb_test';
DROP DATABASE chenweb_test;
CREATE DATABASE chenweb_test OWNER admin;
```

Then re-run any `gold-benchmark-*` task — `bootstrap()` runs `goose` migrations automatically on every invocation, so the schema rebuilds itself from a clean `CREATE DATABASE`. Confirm `vector`/`pg_search`/`pg_trgm` extensions are available on the Postgres server beforehand (they should already be, since it's the same server instance as production).

### 6.2 Stray `doc-benchmark` binary appears in the repo root

`go build ./server/cmd/doc-benchmark/...` (or `.../doc-benchmark/`) with no `-o` flag drops a compiled binary named `doc-benchmark` directly in the current directory (a single-`main`-package build target defaults its output name to the last path element). Build into `.cache/` instead, which is gitignored:

```bash
go build -o ./.cache/doc-benchmark.exe ./server/cmd/doc-benchmark/
```

Or just use `go run ./server/cmd/doc-benchmark ...` (what the mise tasks do) — no binary left behind either way.

### 6.3 `--processors`/`PROCESSOR` validation errors

`gold-run` validates the processor list eagerly and lists every known name in the error message if something is misspelled or unknown — e.g. `unknown processor "extract_entities"` (the real name is singular, `extract_entity`). The full valid list is in §3.2 above and in `gold_run.go`'s `allGoldProcessors`.

### 6.4 Interpreting an empty/`"not applicable"` result for a processor

Don't treat this as a failure by itself. A one-line document (§3.3's four small fixtures) genuinely has little to extract, and `generate_summaries`/`generate_topics` are never fetched at all (§3.4) — check the actual source text and the processor's actual scope before concluding something is broken.

## 7. Future extension: enriching the gold corpus

The corpus as it stands today is intentionally simple — this was a reasonable, deliberate first cut, not a design ceiling. As of 2026-07-30 it is: 9 authority documents, 40 clauses total, 36 expected-verdict rows, 9 metric definitions (1 unused distractor), 1 applicability object, 3 closed dimensions — and the largest single document is only 8 short blocks. That was enough to validate the mechanism end to end (§1) and to drive the `extract_metrics` recall investigation (bug reports `2026073001`–`2026073003`), but it's thin as a real quality benchmark. The options below are roughly ordered by how much new machinery each one needs, from "just add rows to `gold.toml`" to "add a new case/corpus."

### 7.1 Deepen the existing documents (no new machinery)

Add more `[[clause]]` entries to existing authority documents, and more `[[expected_verdict]]` rows to match. Concretely useful additions the current fixture doesn't stress yet:
- **Genuine cross-standard conflicts** — two authority documents giving incompatible values for the same metric (the `strictness`/verdict model, ADR `2026072901-adr` DR21, has a whole `conflict` outcome that nothing in the current corpus actually exercises).
- **More `best_effort` vs. required boundary cases** — the `expectation` field (added this session, bug `2026073002`) currently only has real coverage from the ventilator display's brightness/alarm/contrast clauses; more genuinely-vague-vs-genuinely-decidable pairs would stress-test the coverage scorer itself.
- **Deliberately awkward prose** — numbered-clause-carries-content patterns (like the `6.3.2.2` alarm clause bug `2026073003` found), multi-claim sentences (like the brightness-clause fixture defect noted in `2026073001`), inconsistent metric-name wording across documents (P4 in the bug reports) — these are exactly the shapes that broke `extract_metrics` for real; more of them, deliberately, makes the benchmark harder in the way that matters rather than harder in an arbitrary way.

This tier only touches `gold.toml` — no Go code changes. Verify with the existing package tests before spending on a real run:

```bash
cd ~/Workspace/ChenWeb
go test ./benchmark/doc-processors/gold/display-module-v1/... ./server/api/doc-benchmark/...
```

(`generate_test.go` checks the CDM round-trip still renders correctly; `resolve_test.go` checks every metric/document produces the expected verdict rows; `coverage_test.go` checks the `expectation`-aware scoring — all three need to keep passing as clauses are added.)

### 7.2 Broaden within the ventilator domain

Add more authority documents (new standards bodies, or a second *revision* of an existing standard — e.g. a GB 9706.1 successor — to exercise supersession/versioning, which nothing in the corpus currently models), or extend beyond the display module into other ventilator subsystems (alarm system, battery, humidifier) as new metric families sharing the same `gold.toml` mechanism. Still no new machinery, just more of the same schema — see `README.md` in `display-module-v1/` for the full field reference.

### 7.3 Add ground truth for processors other than `extract_metrics`

This is probably the highest-value extension. Today, only `extract_metrics` has a real answer key (`expected_verdict`); every other processor (`extract_provisions`, `extract_entity`, `extract_relation`, `extract_inventory_items`, etc.) can only be evaluated via `analyze`'s LLM-judged plausibility read (§4), which is real evidence but explicitly lower-precision than exact scoring. Adding a hand-authored expected-rows table for, say, `extract_provisions` (analogous to `expected_verdict`) plus a deterministic scorer for it (analogous to `coverage.go`/`verdict_score.go`) would let a future session hold that processor to the same precision bar `extract_metrics` was held to this session.

### 7.4 More subject documents (matrix-style comparison)

The corpus currently resolves one subject document (`doc:ent-q-syn-001-2026`) against the authority corpus. Adding more subject documents (representing different concrete products) would let the benchmark exercise genuine many-products-vs-many-standards comparison — closer to the actual "killer app" (product/metric standards-comparison tool) this whole framework was built to validate.

### 7.5 A second corpus case or domain entirely

`docbenchmark.LoadCorpusDataset` already supports multiple `cases` in one `manifest.json` (`server/api/doc-benchmark/corpus_dataset.go`) — each case just needs its own `case_id` and its own `gold` TOML path (which can live in a subdirectory, doesn't have to be `display-module-v1/gold.toml` specifically). This is the mechanism §1.1 refers to for adding a non-ventilator domain: create a new directory (e.g. `benchmark/doc-processors/gold/some-other-product/gold.toml`) following the same schema, add a manifest entry (either in a new `manifest.json`/dataset root, or as an additional case in the existing one), and point `DATASET_ROOT`/`CASE_ID` (§3.3) at it. No changes needed to `gold-run`, `analyze`, or the mise tasks — they're already dataset/case-parameterized.

## 8. Related documents

- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` — DR12 (metrics-as-pilot), DR21 (strictness/verdict vocabulary), DR22 (comparison matrix as an L7 service) motivate why this corpus and its deterministic scorer exist.
- Bug reports `2026073001`, `2026073002`, `2026073003` (`KnowledgeStore/doc-repo/bugs/202607/`) — the `extract_metrics`-specific recall-instability investigation that used path 1 (§1) exclusively; useful background on what the deterministic scorer can and can't tell you, and why `analyze` (path 2) was built to cover the other processors.
- `benchmark/doc-processors/gold/display-module-v1/README.md` — the fixture's own internal documentation (clause/metric/verdict schema in `gold.toml`).
