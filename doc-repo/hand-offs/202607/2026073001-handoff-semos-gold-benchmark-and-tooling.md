# SemOS Ontology ADR + Gold Benchmark + Generalized Tooling — Session Handoff

Date: July 30, 2026

## Scope

This was a long, multi-phase session that started from a single ask — consolidate SemOS's ontology architecture into one ADR — and progressively built and empirically validated that architecture against a real "killer app": a ventilator display-module product/metric standards-comparison tool. In order:

1. Drafted and iterated ADR `2026072901-adr-semantic-platform-and-adaptive-pipeline.md`, consolidating 4 source documents into a layered ontology architecture (7 layers, governance/execution/access planes) plus keyword-management/knowledge-store routing decisions.
2. Built a synthetic "gold" benchmark corpus and comparator from scratch to validate that architecture against real (unmocked, paid) LLM extraction, wired to a fully isolated database/artifact setup.
3. Ran the full corpus for real, found and root-caused real `extract_metrics` recall-instability bugs, fixed two of three root causes via prompt iteration, and wrote up the investigation across three bug reports.
4. Generalized the one-off benchmark CLI into reusable multi-processor tooling (`gold-run` + `analyze`) with three `mise` tasks and an operations manual.

Nothing in this session was committed to any repo — see "Current repo state" below.

## Where the work lives

- **ADR:** `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-semantic-platform-and-adaptive-pipeline.md` — the architecture record (DR0–DR24). Read this first for *why* any of the rest of this exists.
- **Gold fixture:** `ChenWeb/benchmark/doc-processors/gold/display-module-v1/` — `gold.toml` (the hand-authored corpus), `generate.go`/`resolve.go`/`coverage.go` (+ tests), `README.md` (schema reference), `manifest.json`.
- **Comparator library:** `ChenWeb/server/api/ontology/comparison/` — `Constraint`/`Compare`/`EvaluateFamily` (DR21 strictness relation).
- **Benchmark execution CLI:** `ChenWeb/server/cmd/doc-benchmark/` — `gold_run.go` (generalized this session), `gold_analyze.go` (new this session), `main.go`/`main_test.go` (both modified).
- **Operations manual:** `KnowledgeStore/doc-repo/devdocs/202607/2026073002-devdoc-gold-benchmark-operations.md` — **read this before running anything**; covers the safety model (why never to point this at production), exact commands, output shapes, gotchas, and future-extension options.
- **Bug reports (the `extract_metrics` investigation):** `KnowledgeStore/doc-repo/bugs/202607/2026073001-*.md` (original recall-instability finding), `2026073002-*.md` (required-vs-best-effort coverage scoring reframe), `2026073003-*.md` (wrap-up/disposition — **this is the one to read if you only read one**, it links the other two and states what's still open).
- **New prompt versions:** `ChenWeb/prompts/prompt-extract-metric-candidates-v{6,7,8,9}.md`, `prompt-enrich-metrics-v4.md`, `prompt-analyze-benchmark-results-v1.md`. **None of these are wired into production** — `mise.local-bzton.toml` still pins `EXTRACT_METRIC_CANDIDATES_PROMPT=v4`/`ENRICH_METRICS_PROMPT=v2` (the pre-session versions), deliberately, per the disposition in bug `2026073003`.

## Current state: what's built and real-tested

- **ADR** is complete and internally consistent (DR0–DR24), with "Built:" annotations added as each piece below was actually constructed — it is not just a design document, it tracks its own implementation status.
- **Gold corpus**: 9 synthetic authority documents, 40 clauses, 36 expected-verdict rows, 9 metric definitions (1 distractor), 1 applicability object, 3 closed dimensions — all for a single subject document (`doc:ent-q-syn-001-2026`) representing one ventilator display-module product. Deliberately simple as a first cut — see the devdoc's §7 for concrete extension options (more conflicting standards, ground truth for other processors, more subject documents, additional domains).
- **Benchmark infrastructure**: fully isolated from production. Real `chenweb_test` Postgres database (same server as production `miner`, different name, freely disposable), real `ThirdParty-2/Data/{Artifacts,ArtifactWeb}` directories on the attached SSD (separate from any code checkout). Verified this session: dropping/recreating `chenweb_test` cleanly resolves goose migration-bookkeeping drift if it ever occurs (the devdoc's §6.1 documents the exact recovery steps, needed once this session after `chenweb_test` was found to have been dumped from production rather than cleanly migrated).
- **`gold-run` CLI**: generalized this session from a hardcoded `extract_metrics`-only tool to a `--processors <name,name|all>` tool covering all 11 processors `docprocessing.ProductionRuntime` knows, via a generic per-processor result-table registry (`processorResultTables` in `gold_run.go`) and a column-agnostic SQL row scanner. Verified end-to-end with a real, paid `extract_metrics` run against the smallest fixture document (record id 46) — correct output, correct artifact layout.
- **`analyze` CLI** (new): takes a `gold-run` JSON output file plus the same `--dataset`/`--case`, reconstructs each document's exact source text from the fixture, and asks a real LLM (`deepseek-flash-chen` by default) to write a Markdown coverage/correctness report — this is the only evaluation path that works for processors other than `extract_metrics`, since there's no hand-authored answer key for provisions/entities/relations/etc. Verified end-to-end with a real call against the same smoke-test record; produced a correct, well-grounded report.
- **Three `mise` tasks** (`mise.toml`): `gold-benchmark-run` (single/multi processor, `PROCESSOR=` required), `gold-benchmark-run-all` (thin wrapper, `PROCESSOR=all`), `gold-benchmark-analyze` (`RESULTS=` required). All three hardcode the benchmark DB/artifact paths as unconditional `export`s specifically so they can never silently inherit `mise.local.toml`'s real production values — verified this is necessary, not paranoia (see devdoc §2). Dry-run-tested across all 9 documents for both single- and all-processor variants; the required-var guards were confirmed to fail fast and clearly.
- **`extract_metrics` recall investigation**: root cause 1 (scope-language misclassification of "standard does not specify a limit" clauses) fixed and validated honestly (the `v7` fix was initially contaminated by literal-example reuse — user caught this — `v8`/`v9` fixed it properly with an unrelated example, confirmed real improvement). Root cause 2 (heading-tag interaction with the CN alarm clause) partially fixed (`v9`: 2/4 historical → 3/4). Root cause 3 (clauses failing in correlated pairs across identical calls) observed twice, independently, still unexplained. Full detail and the user's explicit decision to pause this line of work is in bug `2026073003`.

## Current repo state (uncommitted)

Nothing from this session has been committed — `jj status` shows the working copy still holds everything as pending changes (new files `A`, modified files `M`):

```
M mise.toml
A prompts/prompt-analyze-benchmark-results-v1.md
A prompts/prompt-enrich-metrics-v4.md
A prompts/prompt-extract-metric-candidates-v{6,7,8,9}.md
A server/api/doc-benchmark/{corpus_dataset,verdict_score}.go + tests
A server/api/ontology/comparison/{compare,constraint,doc,family,units}.go + tests
A server/cmd/doc-benchmark/{gold_run,gold_analyze}.go
M server/cmd/doc-benchmark/{main,main_test}.go
```

Parent commit is `zqvl 805c "working on phone login, not finished yet"` — i.e. this session's changes sit on top of an already-unfinished prior session's work, also uncommitted. **Whoever picks this up should decide deliberately how to split these into commits** (the phone-login work and this session's ontology/benchmark work are unrelated and probably shouldn't share a commit) rather than assume a single `jj commit` is correct.

All Go code builds and vets clean (`go build ./server/...`, `go vet ./server/...`) as of the end of this session. `go test ./server/cmd/doc-benchmark/...` has one pre-existing, unrelated failure (`TestValidateEmitsMachineReadableSnapshot` needs `DOC_BENCHMARK_METRICS_MODEL_NAME` set in the environment — an environmental gap, not a regression from this session's changes; it wasn't touched).

## Known follow-up items

- **Root cause 3** (correlated-pair clause failures) is unexplained — flagged, not investigated further, per the user's explicit decision to pause metrics-extraction optimization this session.
- **`v9`/`v4` prompts are not production defaults** — deliberately, pending validation against the full 9-document corpus (never run under `v9`/`v4` specifically; only the single problematic CN document was repeat-tested). This is the concrete next step if metrics-extraction work resumes.
- **No ground truth exists for any processor except `extract_metrics`** — `analyze`'s LLM-judged review is the only evaluation available for provisions/entities/relations/inventory-items/etc. today. Devdoc §7.3 flags this as the highest-value corpus extension.
- **The gold corpus is thin by design** (§ above) — devdoc §7 lists five concrete enrichment directions in rough order of effort: deepen existing documents, broaden within ventilator domain, add ground truth for other processors, add more subject documents (matrix comparison), or add an entirely new domain/case (the mechanism already supports this — `docbenchmark.LoadCorpusDataset` handles multiple cases per manifest today).
- **Nothing is committed** (see above) — decide on commit boundaries before this compounds further with unrelated work.

## Recommended handoff summary

If picking this up cold:

1. Read the ADR (`2026072901`) for the architecture, then bug `2026073003` for the metrics-investigation disposition, then the devdoc (`2026073002`) for how to actually run anything.
2. Decide on commits before doing anything else — the working copy currently mixes this session's work with a prior unfinished phone-login session.
3. If continuing metrics-extraction work: the concrete next step is running `v9`/`v4` against the full 9-document corpus (not just the one CN document that was repeat-tested), via `PROCESSOR=extract_metrics mise run gold-benchmark-run` with those prompt files set in the environment, then comparing against the historical baseline in bug `2026073001`.
4. If extending the corpus instead: start with devdoc §7.3 (ground truth for a second processor, e.g. `extract_provisions`) — it's the highest-value gap and has a clear template to follow (`expected_verdict`/`coverage.go` for metrics).
5. Either way, `mise run gold-benchmark-run-all -- --dry-run` is a free, safe way to confirm the whole pipeline still works before spending on a real run.
