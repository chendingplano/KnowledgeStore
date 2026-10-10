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

Documents lean on other documents all the time. A standard takes a limit from another standard
("faecal coliform count shall meet the requirements of GB 7959"). A permit takes emission limits
from an annex of a directive. A test report follows a method published elsewhere. A paper takes a
figure from an earlier study. `extract_metrics` keeps working as it does today. It records only
what the document itself states, and it sets clauses that take their value from elsewhere aside.

A new processor, `extract_references`, reads the same document separately and lists every place
where it cites another document: entries of its reference lists, "comply with" clauses, method
citations, definitions taken from elsewhere, and clauses that take a limit from the cited
document. It records what each citation takes from the cited document (one of seven types). It also
records whether the cited document is one of this document's **normative references**, meaning it is
formally listed as such. People can then search for a document's normative references, or for every
document that lists a given document as a normative reference.

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

Resolution (steps 5–6) applies only to `value` and `value_set` citations, the ones whose cited
content is a metric's criterion (see "Reference model"). Method citations ("determined in
accordance with GB/T 755") point at a method, not a metric. They
are recorded and may later link to `extract_test_methods` output, but they add no row to
`kb.metrics`. 753_drp_49 is this case.

### P6. Document identity comes before any metric matching

Cited documents are identified in different ways across domains. Each citation records the kind
of identifier (`cited_id_kind`) and is normalized by the rules for that kind:

| `cited_id_kind` | Examples | Normalization and edition |
|---|---|---|
| `standard` | ISO 3744:2010, GB/T 755, EN 1838, ASTM D638-14 | publisher prefix + number + part, edition kept apart (`GB/T755` → `GB/T 755`; in `ISO 14253-1`, `-1` is a part, while a 4-digit year after a dash or colon is the edition). Standards convention (ISO/IEC Directives Part 2, GB/T 1.1): an **undated** citation means the latest edition |
| `legal_act` | Regulation (EU) 2016/679, 40 CFR Part 60, 中华人民共和国固体废物污染环境防治法 | jurisdiction + act type + number or official title; amendments recorded as cited |
| `persistent_id` | DOI, ISBN, arXiv id | the identifier itself, case-normalized |
| `bibliographic` | Smith et al. (2019), numbered [14] resolved through the reference list | author + year + title from the list entry |
| `url` | a web page or dataset link | the URL as given |

A dated citation of a different edition than the one in `kb.inputs` is flagged `edition_mismatch`
and never resolved silently. Where a domain has no edition convention, a citation without a
version or date that matches several editions is flagged `edition_ambiguous`.

The citing document needs a reliable identifier too. `kb.inputs.doc_no` is often empty: 753
(GB/T 46121-2025) has none even after `extract_metadata`. So the processor writes its own document's
normalized identifier to a column it can rely on. If `extract_metadata` left `doc_no` empty, it
takes the identifier from the first page or the filename.

### P7. "Not confident" is a review state, not a failure

The run succeeds. The citation is marked `needs_review`, its ranked candidates are stored, a WARN
log line is written, and the run log reports counts per state. The thresholds belong to a
versioned policy in `shared.decision_policies`, calibrated on real citations.

## Reference model (step 4)

`extract_references` must work on any document in any language and domain: standards,
regulations, contracts, specifications, scientific papers, technical reports, manuals. The model
below therefore describes what a citation **does**, not the words one language uses for it. Two
conventions are named directly because standards bodies share them (ISO/IEC Directives Part 2,
CEN/CENELEC, ASTM, IEEE, and national rules such as GB/T 1.1): a **normative references** list and
a **terms and definitions** section. Both are recognised by their purpose, never by a fixed heading
string.

A **citation** is one place where the document points to another document. Pointers inside the
same document (a table, annex or clause of this document) are not citations. Every citation gets
these labels:

| Label | Question it answers | Values |
|---|---|---|
| `ref_form` | How does the citation appear? | `listed` · `in_text` |
| `normativity` | Is the cited document formally a normative reference of this document? | `normative` · `informative` · `unlisted` |
| `in_requirement` | (in-text only) Is it cited inside a requirement of this document? | true · false |
| `ref_level` | (in-text only) Which part of this document does it apply to? | `document` · `section` · `clause` · `table_item` |
| `ref_type` | (in-text only) What does this document take from the cited document? | the seven types below |

### Form

- **`listed`**: an entry in a reference list, i.e. a section whose only content is a formal list of
  cited documents. This covers the normative references list as well as a bibliography, reference
  list or further-reading list.
- **`in_text`**: a citation anywhere else: body text, tables, notes, examples, footnotes, annexes,
  or the terms and definitions section.

A document cited both ways gives one `listed` row and one `in_text` row per occurrence. Each
`in_text` row points to its list entry (`list_entry_id`). A list entry never cited in the text has
only its form and normativity.

### Normativity

A **normative reference** is a document that this document **lists explicitly and formally** as
normative, i.e. an entry in a section dedicated to normative references. In standards this is the
"Normative references" clause (ISO/IEC Directives Part 2, clause 2), also called "Referenced
documents" (ASTM), "Applicable documents" (some specifications) or 规范性引用文件 (GB/T 1.1). The
section is recognised by its purpose: a list of documents that, by its heading and introductory
statement, are indispensable for applying this document.

| Normativity | Meaning |
|---|---|
| `normative` | an entry in the normative references list, or an in-text citation of a document in that list |
| `informative` | an entry only in an informative list (bibliography, references, further reading), or an in-text citation of such a document |
| `unlisted` | an in-text citation of a document that is in no list of this document |

**Normativity comes only from the lists, never from wording.** Wording that makes a citation
binding ("shall comply with", "must be measured according to", 应符合) is recorded separately as
`in_requirement`. Binding citations are common in documents that have no normative references list
at all, such as a regulation citing another regulation or a contract citing a specification. They
are `unlisted` with `in_requirement = true`. They are not normative references in the formal sense.

When the document **has** a normative references list, two mismatches are flagged (`list_mismatch`)
and never corrected, because they are drafting defects in the source document:

- `not_listed`: cited inside a requirement, but missing from the normative references list.
- `never_cited`: a normative references entry that the text never cites.

### Level (in-text only)

| Level | The citation applies to |
|---|---|
| `document` | the whole document ("This document is used together with ISO X") |
| `section` | one chapter or section ("The tests in Clause 5 are carried out according to ISO Y") |
| `clause` | one clause, paragraph, sentence or list item |
| `table_item` | one row or cell of a table |

### Type (in-text only): the seven types

These seven types are the complete list. Each in-text citation has **exactly one** type. A sentence
that takes two things from the same document, for example a method and a limit, gives two
citations.

| Type | What this document takes from the cited document | Examples | Resolves to |
|---|---|---|---|
| `value` | the criterion (limit, required value, grade) for **one named measurable quantity**, which this document does not state itself | "Faecal coliform count shall meet the requirements of GB 7959" · "NOx emissions shall not exceed the limit values in Annex II of Directive 2010/75/EU" | **metrics** (steps 5–6) |
| `value_set` | the criteria for a **set** of quantities, identified by a locator in the cited document (a table, class, grade or clause) or a placeholder ("other parameters", "all limits") | "Other parameters shall meet Class II of Table 1 of GB 7959" · "shall meet the Class B limits of CISPR 32" | **metrics** of that table / class |
| `method` | how a quantity is measured, tested, sampled, calculated or determined | "rated power determined in accordance with GB/T 755" · "sound power measured according to ISO 3744" · "samples analysed as described in [12]" | document (later: test method) |
| `definition` | the meaning of terms | "For the purposes of this document, the terms and definitions given in ISO 9000 apply" · "'consumer' as defined in Directive 2011/83/EU" | document (later: term) |
| `requirements` | a body of requirements taken as a whole, with no named quantity and no locator | "Collection shall comply with CJJ 184" · "The supplier shall be certified to ISO 9001" · "Processing shall comply with Regulation (EU) 2016/679" | document or section |
| `source` | nothing: this document **states the content itself** (a value, data, finding, claim) and credits the cited document as its origin | "an emission factor of 2.31 kg CO2 per litre (IPCC 2006)" · "prevalence was 12 % [14]" | document. The value is an ordinary `extract_metrics` row |
| `background` | nothing specific: further reading, related work, "see also" | "NOTE See also ISO 14253-1" · "for a review, see [3]" | document |

Notes on the types:

- **`value` versus `source`**: the test is whether the value is written in this document. If it is,
  the citation is `source` and `extract_metrics` already keeps the metric. If it is not, the
  citation is `value`. Standards mostly produce `value`; papers and reports mostly produce
  `source`.
- **`value_set`** is kept apart from `value` because it can fan out to many metrics, and the
  locator (`cited_locator`) must be found in the cited document first.
- **Terms and definitions section.** A section that exists only to define terms ("Terms and
  definitions" in standards, ISO/IEC Directives Part 2 clause 3; a glossary; the "Definitions"
  article of a regulation or contract). A citation in such a section, or a statement that the terms
  of a cited document apply, is `definition`. Like the normative references list, it is recognised
  by its purpose (it only defines terms), not by its heading.

### Deciding that a citation references metrics

Only `value` and `value_set` citations reference metrics. The decision is made in three stages.
Each stage can confirm or weaken the one before it.

**1. The citing text, read by the LLM at extraction (Phase B).** A citation is `value` only when
it passes all three tests:

- **It names a measurable quantity of an object**: something with a value on a unit or scale
  (faecal coliform count, moisture content, NOx emission, sound power). This is the same test
  `extract_metrics` uses. A process, activity, product or management system as a whole is not one
  ("Collection shall comply with CJJ 184" is `requirements`).
- **It takes the criterion for that quantity**, meaning the limit, grade or required value, and
  not the way it is measured. "Shall comply with / meet / not exceed the requirements or limits of
  X" takes a criterion. "Measured / determined / tested / calculated in accordance with X" takes a
  method, so the citation is `method` even when a quantity is named. 753_drp_49 ("rated power of
  the fan motor, determined in accordance with GB/T 755") names a quantity and is still `method`.
- **This document does not state the value itself.** If it does, the citation is `source`.

It is `value_set` when the text names a set of criteria instead of one quantity: a placeholder or
a locator in the cited document. Text that takes "the requirements" of a whole document, with no
quantity and no locator, is `requirements` and never adds metrics, even when the cited document is
mostly limits. Copying every metric of a document because a clause says "comply with X" would
assert far more than the clause does.

The LLM returns the type, the named quantity (`metric_name`, `metric_subject`, `condition`), the
`cited_locator`, and `type_confidence`. The prompt carries these tests with examples in several
languages and domains, not a word list. Phrases like the ones quoted above are hints, not rules, as
in the decision policy (devdoc 2026100801).

**2. Agreement with `extract_metrics` (resolution, Phase C).** `extract_metrics` makes its own
call on the same text. A row set aside as `delegated_requirement` (with a `cited_doc:` tag) in
`kb.metrics_dropped`, at overlapping `source_line_spans`, means it also saw a named quantity whose
value lives in a cited document. If the two agree, the decision stands. If they disagree (one says
`value`, the other a method citation, an inspection requirement, or no row at all), the citation
goes to `needs_review` instead of being resolved automatically. The comparison is logged in both
directions, which also measures how well each processor does.

**3. The cited document, once it is processed.** A `value` citation expects the cited document to
hold a metric for the named quantity. If candidate search finds none, and the cited document has no
metrics of that kind at all, the type itself is doubtful. GB/T 755, a rating and method standard, is
an example. Then the citation becomes `no_match` with the note `type_doubtful` and goes to review. It
is never quietly retyped. The cited document's governed `document.doc_kind` is an extra signal for
the reviewer, not a rule.

Until stage 3 can run (cited document missing or not processed), the type rests on stages 1–2 and
is shown as such.

## Tables (proposed, goose migrations, created at start-up)

### `kb.doc_references`: one row per citation occurrence, rebuilt on each run of the citing document

| Column | Meaning |
|---|---|
| `id`, `input_record_id`, `event_id`, `run_id`, `ref_id` (`<rec>_ref_<n>`) | identity, provenance |
| `ref_form` | `listed` · `in_text` |
| `list_kind` | for `listed`: `normative` (the normative references list) · `informative` (bibliography, references, further reading) |
| `normativity` | `normative` · `informative` · `unlisted` (derived from the lists only) |
| `in_requirement` | for `in_text`: cited inside a requirement of this document |
| `list_entry_id` | for `in_text`: the list entry of the same cited document (null if none) |
| `list_mismatch` | `not_listed` · `never_cited` · null (only when the document has a normative references list) |
| `ref_level`, `ref_type`, `type_confidence` | for `in_text`, see "Reference model" |
| `section`, `source_line_spans`, `quote` | where and what was said |
| `cited_raw`, `cited_id_kind`, `cited_doc_key`, `cited_edition`, `cited_locator` | as written; kind of identifier (P6); normalized id; edition or null; table/clause/class in the cited document |
| `metric_name`, `metric_subject`, `condition` | the named quantity, for `value` citations (Chinese + `_en`) |
| `target_input_id`, `target_state` | resolved `kb.inputs.id`; `unknown_document` · `not_processed` · `no_metrics` · `processed` · `edition_mismatch` · `edition_ambiguous` |
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

People will want to ask "which normative references does this document have?" and "which
documents list GB/T 755 as a normative reference?", with or without the informative and unlisted
citations. To support this:

- **Indexed columns** on `kb.doc_references`: (`input_record_id`, `normativity`) for one
  document's references, and (`cited_doc_key`, `normativity`) for "who cites X".
- **Full-text search**: a `kb.search_artifacts` partition `doc_reference` (capsule §12.3, BM25 +
  embeddings), one row per citation. Title is the cited identifier and its title, context is the
  quote and section. `normativity`, `ref_type` and `ref_level` are filterable fields, and the
  default filter shows all citations.
- **API and page**: one read endpoint filtered by citing document, cited document, `normativity`,
  `ref_type`, `in_requirement` and `resolution_state`. The pages show a Normative / Informative /
  Unlisted badge on every citation, with a normative-only toggle (EN/ZH, selectable text).

Normativity is shown and filtered as stored. A binding but unlisted citation (`unlisted` with
`in_requirement = true`) is never counted as a normative reference. A separate "cited in a
requirement" filter finds those.

## Matching (same logic as devdoc 2026101001 R8)

For a `value` / `value_set` citation whose target is `processed`:

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

- Whether `value_set` fan-out needs a confirmation step before rows are written. A table can
  hold dozens of metrics.
- Whether resolved rows should ever be scored by the benchmark (a later gold version) or stay
  outside it.
- Initial policy thresholds (calibrate on the first resolved set, e.g. records 416, 642, 753).

## Known limitations (by design)

- Only documents in `kb.inputs` processed by `extract_metrics` can be resolved against. Citations
  to anything else wait in `pending_target`.
- No chains in v1. If B's metric is itself a reference to C, A's citation resolves to B's row only.
- `method`, `definition`, `requirements`, `source` and `background` citations are recorded but add nothing to `kb.metrics`.
- `extract_metrics` is unchanged. It still sets value delegations aside (`delegated_requirement`),
  and they remain visible in `kb.metrics_dropped` next to the resolved rows.
