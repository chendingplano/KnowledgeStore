# extract_references — a doc processor that records cross-document references and resolves metric references

**Date:** 2026-10-10 \
**Status:** Design, **not built**. Supersedes the "keep reference rows inside `extract_metrics`"
approach of devdoc 2026101001. Its review findings on reference kinds, document identity, stable
keys and confidence policy still apply and are reused here. Build it through an openspec change in
`ChenWeb/openspec/changes/`. Then, per the doc-processor capsule §12.1, write
`extract-references-spec.md` / `-impl.md` and update this doc.
**Scope:** What the new `extract_references` processor does, the tables it owns, the reference
types, how metric references are resolved in both directions, and how resolved metrics enter
`kb.metrics`. Open this before building the processor or before changing anything that reads
`kb.metrics` row counts.
**Code root (to be):** `ChenWeb/server/api/doc-processing/extract-references.go` (+ resolver),
registered in `ChenWeb/server/cmd/doc-processor/main.go`. Pipeline rules:
`KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`.

## Summary

Standards lean on other standards all the time: "粪大肠菌群数应达到 GB 7959 的要求" means the limit
is in GB 7959. `extract_metrics` keeps working as it does today. It records only what the
document itself states, and it sets these clauses aside.

A new processor, `extract_references`, reads the same document separately and lists every place
where it cites another document: the normative-reference list, "comply with" clauses, test-method
citations, and clauses that take a limit from the cited document. It sorts each citation by type
and marks it as **normative** (binding for applying the document) or **informative** (background
only), so people can search for a document's normative references or for every document that
normatively cites a given standard.

For citations that take a **metric's value** from another document, it looks up that document. If
the cited document has already been processed by `extract_metrics`, it finds the matching metrics
there and adds them to the citing document's metrics. Each added metric is marked as coming from a
reference and carries the id of the original. If it cannot find a match it is sure of, it stores
the best candidates and marks the citation for a person to decide.

The same lookup also runs backwards. When a document is processed, the processor finds the
earlier documents that cite it and resolves their waiting citations.

## The plan, as given (2026-10-10)

The rest of this doc refers to these steps by number.

1. Keep `extract_metrics` as it is: clauses that take their value from another document stay set
   aside (dropped), as today.
2. Create a new doc processor, `extract_references`, that retrieves a document's references to
   other documents, following the doc-processor capsule
   (`KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`).
3. Create the tables needed to store the references.
4. Determine the reference types.
5. **Outgoing resolution.** When the processor handles a document, for each reference that points
   to metrics in another document: check the cited document. If `extract_metrics` has processed it,
   resolve the reference to the matching metrics there (the matching logic of devdoc 2026101001).
   Add the resolved metrics to `kb.metrics`, carrying the ids of the metrics they reference.
6. **Incoming resolution.** When the processor handles a document, find the documents that cite
   it. Resolve their metric references against this document and update `kb.metrics` as needed.

## Review of the plan

The six steps are accepted. Separating references from `extract_metrics` is the better design: it
keeps "metrics this document states" clean and gives references a home of their own, including the
many that are not about metrics. Seven points need care.

### P1. Where it runs in the pipeline: extraction in Phase B, resolution after `extract_metrics`

Phase B processors run at the same time with no ordering (capsule §7.3). Resolution cannot run
there, because:

- `extract_metrics` **deletes every `kb.metrics` row of the record** on each run
  (`DELETE FROM kb.metrics WHERE input_record_id = $1`, `extract-metrics.go`). Metrics added to
  document A by resolution would be wiped by A's own `extract_metrics` if that ran later.
- Incoming resolution (step 6) needs this document's own metrics, which exist only after
  `extract_metrics` finishes.

So the processor has two parts:

| Part | Tier | Depends on | Does |
|---|---|---|---|
| `extract_references` | Phase B (configurable) | `chunking` | LLM extraction + typing of citations, document identity, writes `kb.doc_references` |
| resolution | Phase C post-process (`PostProcessIndexer`, `PostProcessDependsOn` the metrics indexer) | `extract_references` and this record's `extract_metrics` | outgoing + incoming resolution, writes `kb.reference_metric_links` and resolved rows into `kb.metrics` |

Extraction uses `canonicalChunkInputText` so it shares the DeepSeek cached prefix with
`extract_metrics` (capsule §6.2).

### P2. Incoming resolution must also be triggered by `extract_metrics`, not only by `extract_references`

Step 6 ties "who cites me" to running `extract_references` on the cited document. But a cited
document often gets its metrics later or again, through a Dev Mode re-run of `extract_metrics`
alone. Then the waiting citations would never resolve, and earlier resolved rows would point at
deleted metrics. The resolution step must therefore run after a successful `extract_metrics`
**or** `extract_references` of a record. It is cheap when there is nothing to do.

### P3. Copying resolved metrics into `kb.metrics`: the rows must be clearly owned and survive re-runs

Step 5 adds the cited document's metrics to the citing document's `kb.metrics`. This works if
these rules hold:

1. **Owned by the resolver, not by `extract_metrics`.** `extract_metrics`' delete becomes
   `… AND ref_doc_reference_id IS NULL`, so a re-run of the citing document keeps resolved rows.
   The resolver deletes and re-inserts only its own rows, per citation.
2. **Own id namespace.** `extract_metrics` numbers rows by position (`<rec>_mtc_<n>`). Resolved
   rows use `<rec>_rfm_<n>` so the two never collide.
3. **The citing document's context, the cited document's value.** A resolved row is not a raw
   copy. Subject, context, section and `source_line_spans` come from the **citing clause** ("堆肥产品
   的粪大肠菌群数…"). Value, unit, range type, condition and value class come from the **cited
   metric**. The cited document is evidence, never the source text of this row.
4. **Re-run of the cited document.** Its `kb.metrics` rows are deleted and renumbered, so the
   stored target ids go stale. Incoming resolution (P2) then re-resolves and rewrites every
   resolved row derived from it. Human decisions survive through stable metric keys: a fingerprint
   of record, section, normalized name, subject and condition (devdoc 2026101001 R6). A confirmed
   link whose key no longer exists becomes `stale` and is flagged.
5. **Idempotent under concurrency.** Two records that cite each other can be processed at the same
   time. Inserts are keyed on (citation, target metric key) with upsert semantics, so outgoing and
   incoming passes never duplicate rows.

### P4. Every reader of `kb.metrics` sees the new rows, so the default must be explicit

About 50 Go files read `kb.metrics`. Resolved rows are the citing document's requirements, but
their value was not written in this document. Each reader must decide:

| Reader | Default for resolved rows |
|---|---|
| Benchmark scoring (`score_io`, doc-benchmark adapter) | **excluded.** Gold 6.0.0 X16 excludes delegations and forbids importing values; a later gold version may score them separately |
| Phase D `normalize_assertions` (semantic assertions) | **excluded** until provenance can say "value asserted by B, applied by A". Otherwise B's value is recorded as A's claim |
| Class contracts, per-instance conformance, comparisons | excluded, or counted once at the cited document |
| Search index / hybrid links | indexed, labelled as a reference, linked to the original |
| Metric list and explorer pages | shown, with a "from GB 7959" badge and a link to the original |

The openspec change must list every reader, not only these.

### P5. Which citations resolve to metrics

Resolution (steps 5–6) applies only to **value** citations, the ones whose cited content is a
metric's limit. Method citations ("按 GB/T 755 确定") point at a test method, not a metric. They
are recorded and may later link to `extract_test_methods` output, but they add no row to
`kb.metrics`. 753_drp_49 is this case.

### P6. Document identity comes before any metric matching

The rules of devdoc 2026101001 R4 apply: normalize identifiers (`GB/T755` → `GB/T 755`; a dash
before a 4-digit year is the edition, `-1` in `ISO 14253-1` is a part), treat an undated citation
as the latest edition, and flag `edition_mismatch` instead of resolving silently. In-document
pointers (`表2`, `附录B`) are not citations. `kb.inputs.doc_no` is the match key but is often
empty: 753 (GB/T 46121-2025) has none even after `extract_metadata`. So the processor also writes
its own document's normalized identifier to a column it can rely on. If `extract_metadata` left
`doc_no` empty, it takes the identifier from the title page or filename.

### P7. "Not confident" is a review state, not a failure

The run succeeds. The citation is marked `needs_review`, its ranked candidates are stored, a WARN
log line is written, and the run log reports counts per state. The thresholds belong to a
versioned policy in `shared.decision_policies`, calibrated on real citations.

## Reference types (step 4)

Each citation gets three independent labels: a **normativity** (is it binding), a **level** (where
it sits) and a **type** (what it borrows).

### Normativity

Whether a reference is normative is separate from what it borrows. A method citation or a value
citation can each be normative or informative. So normativity is its own label, stored on every
citation, and searchable on its own (see "Searching references").

| Normativity | Meaning | How it is recognised (GB/T 1.1, ISO/IEC Directives Part 2) |
|---|---|---|
| `normative` | the cited document, or the cited part of it, is required for applying this document | listed in the normative-reference clause (§2 规范性引用文件 / "Normative references"), **or** cited in a normative element of the body with requirement wording (应, 必须, 按…进行, "shall") |
| `informative` | cited only for background | listed in the bibliography (参考文献 / "Bibliography"), or cited only in a note (注), example (示例), footnote, informative annex (资料性附录) or with 参见 / 参考 / "see also" |
| `unknown` | cannot be told from the document | e.g. a non-standard document with no §2 list and no requirement wording |

How the two sources combine:

- A body citation of a document that is listed in §2 is `normative`. It is linked to its §2 entry
  (`list_entry_id`), so "all normative references of this document" is the §2 list together with
  where each entry is used.
- `normativity_basis` records why: `list` (the §2 or bibliography entry), `context` (the wording
  in the body), or `both`.
- **Mismatches are flagged, not corrected.** A document cited with requirement wording but missing
  from §2, or a §2 entry that the body never cites, is a drafting defect in the source document.
  Both are recorded (`list_mismatch`) and are useful to document review.

### Level and type

| Level | Meaning |
|---|---|
| `document` | an entry in the normative-reference list (§2 规范性引用文件) or the bibliography (参考文献), or a whole-document statement |
| `section` | a heading-level statement ("第 5 章的试验按 GB/T 1236 进行") |
| `clause` | one clause or list item |
| `table_item` | one row or cell of a table |

| Type | Borrows from the cited document | Example | Resolves to |
|---|---|---|---|
| `listing` | — (a list entry only; normativity tells §2 from bibliography) | §2 entry "GB/T 755 旋转电机 定额和性能" | document |
| `value` | a limit of a **named quantity** | 粪大肠菌群数应达到 GB 7959 的要求 | **metrics** (steps 5–6) |
| `value_table` | all limits in a named table or class | 其他指标应符合 GB 7959 表 1 中 II 级的规定 | **metrics** of that table/class |
| `method` | how a quantity is measured or determined | 额定功率按照 GB/T 755 确定 | document (later: test method) |
| `definition` | meaning of terms | 术语和定义见 GB/T 2900.1 | document (later: term) |
| `compliance` | a whole set of requirements, no named quantity | 收运过程应符合 CJJ 184 | document or section |
| `background` | nothing specific, only "see also" | 注：参见 ISO 14253-1 | document |

`value_table` is kept apart from `value` because it fans out to many metrics and needs the cited
table or class (`cited_locator`) to be identified first.

## Tables (proposed, goose migrations, created at start-up)

### `kb.doc_references`: one row per citation occurrence, rebuilt on each run of the citing document

| Column | Meaning |
|---|---|
| `id`, `input_record_id`, `event_id`, `run_id`, `ref_id` (`<rec>_ref_<n>`) | identity, provenance |
| `normativity`, `normativity_basis` | `normative` · `informative` · `unknown`; `list` · `context` · `both` |
| `list_entry_id` | for a body citation, the §2 / bibliography entry of the same document (null if none) |
| `list_mismatch` | `not_listed` (cited with requirement wording, missing from §2) · `never_cited` (§2 entry unused in the body) · null |
| `ref_level`, `ref_type`, `type_confidence` | see above |
| `section`, `source_line_spans`, `quote` | where and what was said |
| `cited_raw`, `cited_doc_key`, `cited_edition`, `cited_locator` | as written; normalized id; year or null; table/clause/class in the cited document |
| `metric_name`, `metric_subject`, `condition` | the named quantity, for `value` citations (Chinese + `_en`) |
| `target_input_id`, `target_state` | resolved `kb.inputs.id`; `unknown_document` · `not_processed` · `no_metrics` · `processed` · `edition_mismatch` |
| `resolution_state` | `not_applicable` (non-metric types) · `pending_target` · `resolved` · `needs_review` · `no_match` · `confirmed` |
| `citing_key` | stable fingerprint, so human decisions survive re-runs |

`unknown_document` rows together form the list of documents worth acquiring.

### `kb.reference_metric_links`: citation → candidate or resolved target metric

| Column | Meaning |
|---|---|
| `id`, `doc_reference_id` | link to the citation |
| `target_input_id`, `target_metric_id`, `target_metric_key` | cited metric (positional id + stable key) |
| `rank`, `score`, `match_method` | `term` · `name` · `embedding` · `llm_judge` · `human` |
| `status` | `candidate` · `resolved` · `confirmed` · `rejected` · `stale` |
| `policy_id`, `policy_version`, `decided_by`, `decided_at` | decision provenance |
| `resolved_metric_id` | the `<rec>_rfm_<n>` row created in `kb.metrics`, if any |

### `kb.metrics`: new columns, null on every `extract_metrics` row

| Column | Meaning |
|---|---|
| `ref_doc_reference_id` | the citation this row came from; **non-null marks a resolved reference row** |
| `ref_input_record_id`, `ref_metric_id`, `ref_metric_key` | the original metric in the cited document |

`kb.reference_metric_links` is the relation table. The `ref_*` columns repeat the link on the row so
list pages and filters need no join.

## Searching references

People will want to ask "which normative references does this standard have?" and "which
documents normatively cite GB/T 755?", with or without the informative ones. To support this:

- **Indexed columns** on `kb.doc_references`: (`input_record_id`, `normativity`) for one
  document's references, and (`cited_doc_key`, `normativity`) for "who cites X".
- **Full-text search**: a `kb.search_artifacts` partition `doc_reference` (capsule §12.3, BM25 +
  embeddings), one row per citation. Title is the cited identifier and its title, context is the
  quote and section. `normativity`, `ref_type` and `ref_level` are filterable fields, and the
  default filter shows all citations.
- **API and page**: one read endpoint filtered by citing document, cited document, `normativity`,
  `ref_type` and `resolution_state`. The pages show a "Normative / Informative" badge on every
  citation, with a normative-only toggle (EN/ZH, selectable text).

Normativity is shown and filtered as stored. A citation marked `unknown` appears only when the
filter includes it, never silently counted as normative.

## Matching (same logic as devdoc 2026101001 R8)

For a `value` / `value_table` citation whose target is `processed`:

1. Candidates come from the target's `kb.metrics` (excluding its own `ref_*` rows: no chains in
   v1) and its `kb.metrics_dropped` definitions, narrowed to `cited_locator` when one is given.
2. They are scored on: same governed term (`metric_definition_term_id` / `keyword_concept_id`),
   name/alias/subject match in both languages, bge-m3 similarity of `search_document`, and an LLM
   judge for the top few.
3. One or more candidates at or above the policy threshold → `resolved`, and resolved rows are
   written. Otherwise → `needs_review` with the top candidates stored as `candidate` links. No
   candidates at all → `no_match`.
4. A person confirming or rejecting a candidate sets `confirmed` / `rejected`. Confirmed links
   write rows like resolved ones.

## Processor contract (capsule §12 checklist)

- Name `extract_references`, configurable, `DependsOn: chunking`; status entry
  `operation: "extract_references"` with counts per `ref_type` and per `resolution_state`.
- Calls `CheckAndHandleStop` at every LLM call boundary. Logs through `kb.doc_proc_logs`.
- Deletion contract (ADR 2026072301): deleting a record deletes its `kb.doc_references`, their
  links and resolved rows. It also marks links **into** it `stale` and moves those citations back
  to `pending_target`.
- Dashboard: add to `ALL_PROCESSOR_IDS`, `PIPELINE_FINAL_OPS`, stage map.
- A review page for `needs_review` citations (EN/ZH via Paraglide), selectable text.

## Open decisions

- Whether `value_table` fan-out needs a confirmation step before rows are written. A table can
  hold dozens of metrics.
- Whether resolved rows should ever be scored by the benchmark (a later gold version) or stay
  outside it.
- Initial policy thresholds (calibrate on the first resolved set, e.g. records 416, 642, 753).

## Known limitations (by design)

- Only documents in `kb.inputs` processed by `extract_metrics` can be resolved against. Citations
  to anything else wait in `pending_target`.
- No chains in v1. If B's metric is itself a reference to C, A's citation resolves to B's row only.
- `method`, `definition` and `compliance` citations are recorded but add nothing to `kb.metrics`.
- `extract_metrics` is unchanged. It still sets value delegations aside (`delegated_requirement`),
  and they remain visible in `kb.metrics_dropped` next to the resolved rows.
