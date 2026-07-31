# SemOS P0 Store-Profile Benchmark Evidence
**Date:** 2026-07-31 04:45:22 CDT
**Scope:** SemOS P0 closeout evidence for `ChenWeb/benchmark/doc-processors/gold/display-module-v1`, using the offline `gold-run` plus `profile-report` workflow approved in `2026073005-spec-semos-p0-benchmark-led-closeout.md`.
**Artifact directory:** `/tmp/semos-p0-sGbZyXVy`

## 0. What P0 is

SemOS P0 is a **benchmark-led proof milestone**, not a full ontology-runtime milestone.

Its purpose is to establish one bounded claim with real execution evidence:

> different store/document profiles need different processor policies.

P0 therefore focused on the minimum implementation needed to:

- define a controlled benchmark corpus;
- run real ChenWeb document processors against it;
- classify benchmark documents into a few store-profile groups;
- aggregate the observed outputs by profile; and
- show, with provenance-bound evidence, that the three profiles want different processor mixes.

P0 does **not** mean that the full ontology platform is already built. In particular, P0 does not claim:

- production routing by profile is implemented;
- ontology runtime behavior is implemented;
- ontology governance/workflow tables are implemented;
- RDF/OWL/SHACL-style reasoning is implemented; or
- semantic correctness can be inferred from structural output counts.

### 0.1 P0 scope map

| Area | In P0 | Not in P0 |
|---|---|---|
| Benchmark execution | `gold-run`, `profile-report`, repeatable `mise` tasks, schema-versioned benchmark/report JSON | none |
| Corpus definition | synthetic ventilator display-module corpus, per-document `store_profile`, `document_kind`, `expected_processors` | additional real-world or multi-domain corpora |
| Evidence model | structural-yield aggregation by store profile | semantic adjudication of every extracted row |
| Processor policy proof | benchmark evidence that different profiles want different processor policies | live production routing or adaptive policy selection |
| Ontology platform | only the benchmark-side justification for future policy-awareness | ontology runtime, ontology storage model, policy compiler, reconciliation engine |
| Database impact | reuse existing ChenWeb document-processing tables and `kb.inputs` | new ontology-specific tables for governed terms, mappings, rules, reconciliation, runtime policy |

### 0.2 Why the benchmark can drive the real processors

The benchmark does not feed PDFs into the processor stack. Instead, P0 generates benchmark documents, creates real `kb.inputs` records for them, and generates the corresponding line files that the downstream document processors consume.

That distinction matters because it confirms the intended contract boundary:

- upstream of line-file generation, different input origins are possible;
- downstream of line-file generation, the processing pipeline is intended to stay the same.

So the benchmark path is:

```text
synthetic benchmark document -> generated line file -> normal doc-processing pipeline
```

while the ordinary PDF path is:

```text
PDF -> parsed/derived line file -> normal doc-processing pipeline
```

In that sense, the processor pipeline is input-format agnostic after the line-file stage, provided the generated line file satisfies the same contract as a PDF-derived one.

## 1. What was executed

### 1.1 ChenWeb source revision

- ChenWeb commit: `33cdcd2e52ee06bfc3bc2caf4d75aa11d1382dd9`

This is the revision that included the final machine-output isolation fix for benchmark commands (`fix: isolate benchmark command stdout`) and was the source tree used for the evidence run.

### 1.2 Exact benchmark commands

Executed from `ChenWeb/` with the task-defined environment overrides:

```bash
RESULTS=/tmp/semos-p0-sGbZyXVy/gold-run.json \
REPORT=/tmp/semos-p0-sGbZyXVy/profile-report.json \
mise run semos-p0-benchmark-evidence

RESULTS=/tmp/semos-p0-sGbZyXVy/gold-run.json \
OUTPUT=/tmp/semos-p0-sGbZyXVy/profile-report.md \
FORMAT=markdown \
mise run gold-benchmark-profile-report
```

These two commands have different jobs:

- The first command, `mise run semos-p0-benchmark-evidence`, runs the actual benchmark workflow. It invokes `gold-run` on the approved corpus case, executes the real processor set against the 9 benchmark documents, and writes:
  - `/tmp/semos-p0-sGbZyXVy/gold-run.json`
  - `/tmp/semos-p0-sGbZyXVy/profile-report.json`
- The second command, `mise run gold-benchmark-profile-report`, is a renderer over an already-finished `gold-run.json`. Here it was used only to generate the human-readable Markdown companion report:
  - `/tmp/semos-p0-sGbZyXVy/profile-report.md`

The tasks set these values unconditionally:

```bash
export PG_DB_NAME=chenweb_test
export ARTIFACT_DIR=/Users/cding/Workspace/ThirdParty-2/Data/Artifacts
export ARTIFACT_WEB_DIR=/Users/cding/Workspace/ThirdParty-2/Data/ArtifactWeb
export JIMO_LOG_STDIO=0
```

The executed case and processor set were:

- dataset: `doc-processors-corpus-display-module@1.1.0`
- case: `display-module-v1`
- selected processors:
  - `generate_summaries`
  - `generate_topics`
  - `extract_structured_knowledge`
  - `extract_entity`
  - `extract_relation`
  - `extract_inventory_items`
  - `extract_metrics`
  - `extract_provisions`

### 1.3 Where the benchmark documents are

The 9 benchmark documents are not stored as PDFs. They are synthetic authority documents defined in the checked-in corpus fixture:

- corpus root: `ChenWeb/benchmark/doc-processors/gold/display-module-v1`
- manifest: `ChenWeb/benchmark/doc-processors/gold/display-module-v1/manifest.json`
- source clauses and authority-document definitions: `ChenWeb/benchmark/doc-processors/gold/display-module-v1/gold.toml`

During the run, those fixture definitions are rendered into real processing inputs and inserted into existing ChenWeb processing tables. In this evidence run, the 9 completed benchmark documents corresponded to generated `kb.inputs` records with `record_id` values `83` through `91`.

P0 also generated the line files for those records. That is how the benchmark enters the real processor stack without needing source PDFs.

## 2. Artifact identity and hashes

- dataset ID: `doc-processors-corpus-display-module`
- dataset version: `1.1.0`
- case ID: `display-module-v1`
- case content hash: `sha256:16ed1dbb544e6bdf2cafa47b308eab0b1c6e415b7544a381ea4e25906e1da86b`

SHA-256:

- `gold-run.json`: `071de648a95aaf1534e4b3db1785bfaf0d4d31d64949880ba8338a12131b7e52`
- `profile-report.json`: `3c49d6a1d6efe87d3a04fc97b6c28f14ef472c9afc770f77e8886454d7d520b3`
- `profile-report.md`: `d5340f6460d7f627a3a2ab39c1c69ba37173c6def74fb7ae01fbd9930a22da37`

The `gold-run.json` and `profile-report.json` dataset content hashes matched exactly.

### 2.1 Where the generated benchmark files are

For this evidence run, the generated files were written outside the repositories under:

- `/tmp/semos-p0-sGbZyXVy/gold-run.json`
- `/tmp/semos-p0-sGbZyXVy/profile-report.json`
- `/tmp/semos-p0-sGbZyXVy/profile-report.md`

They are run artifacts, not source-controlled benchmark inputs.

### 2.2 Is the current benchmark generic or ventilator-specific?

As of 2026-07-31, the **current corpus content** is ventilator-specific: it is the synthetic ventilator display-module benchmark case.

At the same time, the **benchmark framework** was intentionally built to be generic. The reusable parts are:

- corpus loading;
- generated-document execution through `gold-run`;
- provenance-bound result envelopes;
- offline profile reporting; and
- repeatable task wrappers.

So the right reading is:

- today’s evidence corpus is narrowed to the ventilator use case;
- the benchmark mechanism is reusable for future corpora.

Future benchmark expansion can therefore add more use-case-specific document sets, more domains, and more profile shapes without changing the basic execution/reporting model.

## 3. Execution result

Validated `gold-run.json` summary:

- schema version: `2`
- `dry_run=false`
- documents: `9`
- completed documents: `9`
- failed documents: `0`

Validated `profile-report.json` summary:

- schema version: `1`
- aggregate rows: `24`
- profiles observed:
  - `narrative-research`
  - `product-specification`
  - `regulated-reference`
- aggregate failed processor-documents: `0`
- aggregate documents with output: `67`

The Task 9 structural assertions passed:

- exact canonical eight-processor list present
- 9 unique documents present in `gold-run.json`
- 3 exact store profiles present in `profile-report.json`
- 3 distinct expected processor/applicability vectors across profiles
- at least 2 different observed output-yield vectors across profiles

## 4. Per-profile evidence summary

All rows below are `evidence_kind = structural_yield`. They show where output existed and where the expected processor policy differs by store profile. They do **not** claim semantic correctness by themselves.

| Store profile | Document kind | Documents | Distinguishing pattern |
|---|---|---:|---|
| `narrative-research` | `marketing-narrative` | 1 | `generate_summaries` and `generate_topics` are `required`; structured extraction is mostly `useful` or `not_required`. Observed output: summary/topic both 1 row; structured knowledge 9 rows; entity 5; relation 2; metrics 1; provisions 0; inventory 0. |
| `product-specification` | `enterprise-standard` | 3 | `extract_inventory_items` and `extract_metrics` are `required`; `generate_summaries` is `not_required`; topic/entity/relation/provision/structured-knowledge are `useful`. Observed output: inventory 6 rows; metrics 11; provisions 10; relations 11; entities 14; structured knowledge 55; topics 8; summaries 5. |
| `regulated-reference` | `authority-standard` | 5 | `extract_provisions` is `required`; `extract_metrics`, `extract_structured_knowledge`, and `generate_topics` are `useful`; entity/relation/inventory/summary are `not_required`. Observed output: provisions 29 rows; metrics 26; structured knowledge 167; topics 26; relations 25; entities 62; inventory only 5 across 2/5 docs; summaries 13. |

Representative assessments:

- `narrative-research`:
  - `generate_summaries` → `required_output_observed`
  - `generate_topics` → `required_output_observed`
  - `extract_structured_knowledge` → `useful_output_observed`
- `product-specification`:
  - `extract_inventory_items` → `required_output_observed`
  - `extract_metrics` → `required_output_observed`
  - `generate_summaries` → `informational_not_required`
- `regulated-reference`:
  - `extract_provisions` → `required_output_observed`
  - `extract_metrics` → `useful_output_observed`
  - `extract_inventory_items` → `informational_not_required`

## 5. Deterministic gold result retained

Separate from the structural-yield report, the deterministic fixture check was re-run on 2026-07-31:

```bash
go test ./server/api/doc-benchmark \
  -run 'TestLoadCorpusDatasetAgainstRealFixture|TestScoreVerdictMatrixAgainstGoldFixturePerfectRun' \
  -count=1
```

Result: `PASS`.

What this test does:

- it loads the same checked-in synthetic gold corpus fixture through the benchmark loader;
- it reconstructs the expected verdict matrix from the fixture;
- it builds the corresponding actual verdict matrix for the “perfect run” case; and
- it verifies that `ScoreVerdictMatrix` still reports the unchanged exact match.

This is a regression guard for the deterministic DR22-style path. It does **not** evaluate the structural-yield profile report; it checks that the pre-existing exact verdict-scoring path still behaves identically after the P0 benchmark-closeout changes.

This preserves the existing exact gold comparison outcome:

- 36 expected verdict cells
- 36 matched verdict cells
- accuracy `1.0`

So the new store-profile evidence work did **not** regress the previously-approved deterministic DR22-style verdict path.

## 6. Bounded conclusion

In this section, the three profile labels are the benchmark’s coarse store-policy classes:

- `narrative-research`: documents whose main role is explanatory or narrative presentation, where summarization/topic extraction is important and many stricter structured extractors are optional.
- `product-specification`: product or enterprise specification documents, where operationally structured extractors such as metrics and inventory-style details matter much more.
- `regulated-reference`: authority/reference documents such as standards or regulatory-style texts, where provision extraction is central and some other structured outputs are useful but not always required.

They are not ontology classes in the full future-runtime sense. In P0 they are benchmark-side policy categories used to test whether different document families want different processor expectations.

This run supports the bounded P0 claim that the existing three store-shaped corpus profiles require different processor policies:

- `narrative-research` wants summarization-first treatment;
- `product-specification` depends on inventory/metric extraction;
- `regulated-reference` depends on provision-heavy authority extraction.

Because those differences are visible on one common corpus family under one provenance-bound run, P0’s benchmark-led closeout condition is met: store-aware policy is justified as a **P1 requirement** instead of remaining a purely conceptual architecture claim.

### 6.1 Relation to future ontology-enabled processing

P0 does not add ontology-specific processors. It only proves that profile-aware policy is justified.

If ontology-enabled behavior is fully implemented in later phases, the system will likely need additional semantic processing components beyond the current extraction-oriented processors. Examples include:

- concept or term alignment;
- canonicalization and synonym/variant resolution;
- mapping extracted items to governed ontology terms;
- ambiguity handling and review/reconciliation stages;
- ontology-aware enrichment or inference; and
- policy/rule application over extracted structures.

Whether those appear as new “doc processors” in the current pipeline, post-processors, or adjacent semantic jobs is still a later design choice. Functionally, however, a fuller ontology-enabled system will likely require more semantic processing stages than P0 includes.

## 7. Explicit non-claims

This evidence does **not** claim:

- any production routing decision has been implemented;
- row counts imply semantic correctness;
- any synthetic authority document is a real regulatory authority;
- any P2 ontology runtime or adaptive pipeline is already built.

The evidence is limited to provenance-bound structural yield on the approved synthetic benchmark.
