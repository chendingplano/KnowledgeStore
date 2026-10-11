# extract_references — how documents are inter-connected, resolved down to sections and metrics

**Date:** 2026-10-10, revised 2026-10-11 \
**Status:** **Built (v1), 2026-10-11**, openspec change
`ChenWeb/openspec/changes/extract-references-processor/` (not archived). **The specs there are the
contract.** If behaviour changes, update them, not just this doc. Capsule pages:
`Capsules/coding-capsules/doc-processor/extract-references-spec.md` / `-impl.md`. Supersedes the
"keep reference rows inside `extract_metrics`" approach of devdoc 2026101001. The reference model
follows the user's diary, `KnowledgeStore/doc-repo/diary/diary-202610.typ`, §2026/10/11
"References". What v1 built and left out is listed in §0.
**Scope:** What the `extract_references` processor is for, the reference model (target type,
mechanism, relationship, scope), how a reference is resolved from a mention to a resource, a held
document, a location and a metric, how it works as a lower layer under the artifact extractors
(worked out for `extract_metrics`), the tables it owns, and how resolved metrics enter `kb.metrics`.
Open this before building the processor or before changing anything that reads `kb.metrics` row
counts.
**Code root:** `ChenWeb/server/api/doc-processing/extract-references.go`, `reference_*.go` (the resolver interface is in `reference_resolver.go`; the metric family's resolver is in `reference_metric_resolver.go`),
registered in `ChenWeb/server/cmd/doc-processor/main.go`. Pipeline rules:
`KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`.

## 0. What v1 built (2026-10-11)

**Built:**
- The processor: detection and labels, identifier parsing, normativity, resource catalog (R1),
  own-document attachment, holdings with access (R2).
- The resolver contract with "whoever comes second resolves".
- The metric family: step 5 in `extract_references`, step 6 in `extract_metrics`.
- Resolved rows `<rec>_rfm_<n>` in `kb.metrics`, protected from `extract_metrics`.
- Every `kb.metrics` reader updated, with a guard test.
- Table row provenance and column-labelled evidence, using the same grid and row hashes as
  `extract_metrics`; different occurrences on one table line have distinct mention keys.
- Deletion contract.
- Benchmark exclusion (`gold_run.go`, `score_io.py`).

**Different from this design:**
- **Matching (§6.2)** is a deterministic, versioned code policy (`metric_reference_match/v1`: name,
  subject and locator similarity). There is no embedding or LLM judge yet, and no
  `shared.decision_policies` entry. Uncertain matches go to `needs_review`.
- **No `Withdraw` operation.** `Apply` replaces, and deleting a mention cascades. The interface has
  `Pending` for targets that are not held or not processed yet.
- **R3 (location)** is not built. The locator is stored, and the metric resolver uses it to narrow
  candidates (`criteria_set` = the metrics of the located table or section).
- **R1/R3 candidates** (`kb.ref_resolution_candidates`) are not built. Unresolvable identities are
  marked `unnamed`.
- **Dashboard:** no change needed. It lists every processor in `required_processors`.

**Not built (follow-ups):** reference search partition and document-graph page, candidate review
page, contradictions admin page, resolvers for provisions / entities / inventory items,
reference/entity reconciliation, `extract_references` in `default_processors` (left to the user).

**Verified:** unit tests, all server tests, and live runs on records 753, 373 and 362, with a
synthetic step 5/6 check (362 → 373). Not verified: a non-Chinese document (none has its files on
the development machine), and a full `extract_metrics` LLM re-run as step 6 trigger.

## 1. Summary

**Who it is for.** Anyone who holds a body of documents and wants to
know how those documents are connected. Standards are one case. The same need exists for
regulations, contracts, specifications, research papers, technical reports and documents, 
manuals, internal policies, software documentation and product data sheets, in any 
language and any domain.

**What it does.** Documents point at other things all the time: a standard requires compliance
with another standard, a permit takes emission limits from an annex of a directive, a paper builds
on earlier papers and uses a public dataset, a design document links to a repository, a policy
quotes a regulation. `extract_references` reads each document and records every such reference.
It records **what** is referenced (a publication, a standard, a law, a web page, a dataset, a piece
of software, a section or a single value), **how** it is written (a DOI, a standard number, `[12]`,
"Smith et al., 2024", a URL, "see Section 4.2"), **what the relationship is** (cites, requires,
complies with, defines, uses, supersedes, and so on), and **how precisely** it points (a whole
document, a clause, one value).

**Finding a reference is separate from resolving it.** First the processor finds the mention
("ISO 13485:2016, Clause 7.5"). Then, step by step, it works out what the mention points to:
- **the resource**: the one standard or paper, however it was written;
- **the user's own copy**, if one exists in the knowledge store;
- **the exact place** in that document;
- **the matching metric**, when the reference borrows a value.

When the system is not sure, it keeps the candidates and asks a person. It does not guess.

**What people get.** A map of their documents: what each document depends on, who relies on a
given document, which references point at editions that have been replaced, which cited documents
they do not hold yet, and, for limits and other values, the actual metric behind a clause like
"shall meet the requirements of GB 7959".

`extract_metrics` is unchanged. It records only what a document itself states.

**Independent of the other doc processors.** `extract_references` reads the document itself and
uses no output of `extract_metrics`, `extract_provisions`, `extract_entity_relation` or any other
processor. Two processors may find the same thing: a person cited as an author is a reference
here and an entity in `extract_entity_relation`; a clause that takes a limit from another document
is a reference here and a set-aside row in `extract_metrics`. Reconciling those overlaps is a
separate piece of work and is not part of this design.

**A lower layer.** The artifact extractors build on `extract_references`, never the other way round.
These are `extract_metrics`, `extract_provisions`, `extract_entity_relation`,
`extract_inventory_items` and future ones. `extract_references` finds and resolves references down
to the place in the target document. Each artifact extractor resolves the references that concern
its own kind of artifact. §5 describes how the layers work together, and §6 works this out for
`extract_metrics`.

## 2. The plan, as given (2026-10-10)

The rest of this doc refers to these steps by number.

1. Keep `extract_metrics` as it is: clauses that take their value from another document stay set
   aside (dropped), as today.
2. Create a new doc processor, `extract_references`, that retrieves a document's references,
   following the doc-processor capsule.
3. Create the tables needed to store the references.
4. Determine the reference types.
5. **Outgoing resolution.** For each reference that points to metrics in another document, check
   the cited document. If `extract_metrics` has processed it, resolve the reference to the
   matching metrics there. Add the resolved metrics to `kb.metrics`, carrying the ids of the
   metrics they reference.
6. **Incoming resolution.** When a document is processed, find the documents that reference it,
   resolve their metric references against it, and update `kb.metrics` as needed.

**Clarified 2026-10-11:** step 5 is what the **reference extractor** does when it processes a
document. Step 6 is what the **metric extractor** does when it processes a document. The same pair
of steps applies to every artifact extractor, for example provision references with
`extract_provisions` (§5).

The diary section of 2026-10-11 widened step 4 from "reference types" to a full reference model,
and added two principles: detecting a mention is separate from resolving it, and a resource's
identity is separate from where it is found.

## 3. Reference model

A **reference** is one place where a source document points at something. The model has four
independent dimensions plus three labels that standards and requirement documents
need.

| Dimension | Question | Stored as |
|---|---|---|
| **Target type** | What kind of thing is referenced? | `target_type` + `target_subtype` |
| **Mechanism** | How is the reference written in the text? | `mechanism` |
| **Relationship** | How does the source relate to the target? | `relationships` (one or more) |
| **Scope** | How precisely does it point inside the target? | `target_scope` + `target_locator` |
| Target content | Which kind of content of the target is used? | `target_content` |
| Form and normativity | Is it a list entry, and is it a formal normative reference? | `ref_form`, `normativity` |
| In a requirement | Is it cited inside a requirement of the source? | `in_requirement` |

### 3.1 Target type: twelve categories, extensible subtypes

Extraction uses the twelve top-level categories. It does not use a separate schema per type.
**Subtypes are a governed vocabulary** per target type, seeded from the lists below. Every target
type also has the subtype `others`. A reference whose subtype is not in the vocabulary gets
`others`, and the label the extractor proposed is kept in `target_subtype_label`. Curators can then
add frequent labels to the vocabulary. New subtypes need no schema change.

| `target_type` | Examples of subtypes |
|---|---|
| `document` | report, specification, manual, file, internal document, document collection |
| `web_resource` | website, web page, blog post, online article, wiki page, forum post, online documentation, web archive |
| `publication` | journal article, conference paper, preprint, thesis, book chapter, review article, dataset paper, research protocol |
| `standard` | international, national, industry standard; technical specification; internet standard (RFC); draft; amendment; corrigendum; conformance profile |
| `legal` | law, regulation, directive, administrative rule, legal code provision, court decision, regulatory guidance, treaty, bill |
| `general_publication` | book, encyclopedia or dictionary entry, handbook, magazine or newspaper article, white paper, press release, catalog |
| `software` | repository, source file or element, commit, release, package, API, API endpoint, configuration, container image |
| `data` | dataset, database, database record, statistical series, spreadsheet, data repository, knowledge-graph entity, ontology concept |
| `media` | image, diagram, chart, audio, video, presentation or slide, transcript, map, geospatial layer |
| `communication` | email or thread, chat message, meeting record, decision record (ADR), memo, workspace page |
| `business_record` | organization, product, product model, product specification or data sheet, patent, trademark, contract, procurement document, certification, audit report, safety data sheet, test report |
| `other` | person, event, location, concept or term, definition, measurement or metric, formula, procedure, experiment, physical sample, clinical trial record |

Each type has `others` in addition to the subtypes listed.

### 3.2 Mechanism: how the reference is written

The mechanism is never the target type. A URL, a DOI or a file path is an identifier or a locator
of a target, not a kind of target.

| `mechanism` | Example |
|---|---|
| `url`, `hyperlink` | `https://example.com/report.pdf`, `[documentation](url)` |
| `doi`, `isbn`, `issn`, `arxiv_id`, `pmid` | `10.1145/1234567`, `arXiv:2609.15364`, `PMID: 12345678` |
| `standard_number`, `rfc_number` | `ISO 13485:2016`, `GB/T 755`, `RFC 9110` |
| `legal_citation` | `21 CFR § 820.10`, `Regulation (EU) 2016/679` |
| `patent_number` | `US12345678B2` |
| `repository_path`, `file_path`, `relative_path`, `anchor` | `github.com/org/repo`, `docs/architecture.md`, `../specs/design.pdf`, `#section-3` |
| `numbered_citation`, `author_year`, `citation_key`, `footnote` | `[12–15]`, `(Smith et al., 2024)`, `[@smith2024]`, superscript `¹` |
| `named_reference` | "as defined in ISO 9001", "the Personal Information Protection Law" |
| `structural_reference` | "see Section 4.2", "Table 2" (inside the same document) |
| `indirect_reference` | "according to the previous report" |
| `identifier` | `Q42`, `CVE-2025-1234` |
| `cross_reference_field` | a Word or PDF cross-reference field |

A `numbered_citation`, `author_year`, `citation_key` or `footnote` is first resolved to the source
document's own reference list entry, which carries the real identifier. An `indirect_reference` is
resolved from context and always produces candidates, never a silent match.

**Internal references** (`structural_reference` to the same document) are recorded with
`internal = true`. They link sections and tables of one document, which helps when a clause says
"other parameters shall meet Table 2". Inter-document views exclude them by default.

### 3.3 Relationship: one or more per reference

Relationships are not mutually exclusive: a paper can both cite and contradict another paper. Some
relationships are **asserted** by the source text and found at extraction. Others are **derived**
by the system after resolution and are never taken from one document's wording alone.

| `relationship` | Meaning | Example | How it is found |
|---|---|---|---|
| `cites` | source cites target | a paper cites another paper | asserted |
| `references` | general mention, nothing more specific | a document mentions another document | asserted (default) |
| `quotes` | reproduces target content | a report quotes a regulation | asserted |
| `defines_in` | a definition originates in the target | "the terms of ISO 9000 apply" | asserted |
| `based_on` | derived from the target | a procedure based on a guideline; a national adoption of an ISO standard | asserted |
| `implements` | implements a target specification | software implements RFC 9110 | asserted |
| `complies_with` | claims compliance with the target | "this product complies with IEC 60335-1" | asserted |
| `requires` | depends on a requirement in the target | "emissions shall not exceed the limits of Annex II" | asserted |
| `supersedes` | replaces an earlier target | "this edition replaces GB/T 755-2008" | asserted |
| `amends` | modifies the target | an amendment to a regulation | asserted |
| `supports`, `refutes` | evidence for or against a claim | a study supports / refutes a prior conclusion | asserted |
| `extends` | builds on the target | research extends previous work | asserted |
| `uses` | uses a resource: dataset, software, method | a paper uses a dataset; "measured according to ISO 3744" | asserted |
| `depends_on` | dependency | a package depends on a library | asserted |
| `derived_from` | produced from the target | a chart derived from a dataset | asserted |
| `see_also` | related resource | "NOTE See also ISO 14253-1" | asserted |
| `contradicts` | conflicts with the target | two documents give different limits for the same metric | **derived**, flagged for an admin |
| `same_as`, `version_of`, `part_of` | identity, version and containment | DOI and URL of one paper; a draft of a specification; a clause of a standard | **derived** (from the resource catalog) |

**Contradictions are flagged, never settled automatically.** When the system derives `contradicts`
(for example, two documents give different limits for the same quantity), it records a flag with
both sides and their evidence. An admin page lists every flag so an admin can resolve it. That
page and its storage are specified separately.

`based_on` with national adoptions of international standards also records the degree of
correspondence when the document states it (`IDT` identical, `MOD` modified, `NEQ` not equivalent,
ISO/IEC Guide 21-1), e.g. "GB/T 755-2019 / IEC 60034-1:2017, MOD".

### 3.4 Scope and target content: how precisely, and what is used

| `target_scope` | Example |
|---|---|
| `collection` | the ISO 9000 family, a GitHub organization |
| `document` | ISO 13485:2016 |
| `section` | ISO 13485:2016 Clause 7.5; Annex II; Table 1 |
| `requirement` | one normative statement or paragraph |
| `data_element` | one sentence, table cell, value or metric |

`target_locator` holds the place within the target ("Clause 7.5", "Table 1, Class II", "Figure 5",
"Equation 7", "§ 820.10").

`target_content` says which kind of content of the target the source uses. It is what decides
whether a reference touches metrics:

| `target_content` | The source uses… | Example |
|---|---|---|
| `criterion` | the limit or required value of **one named measurable quantity**, which the source does not state itself | "Faecal coliform count shall meet the requirements of GB 7959" |
| `criteria_set` | the limits of a **set** of quantities, found by a locator or a placeholder | "Other parameters shall meet Class II of Table 1 of GB 7959"; "shall meet the Class B limits of CISPR 32" |
| `method` | how something is measured, tested, sampled or computed | "rated power determined in accordance with GB/T 755" |
| `term` | the meaning of terms | "'consumer' as defined in Directive 2011/83/EU" |
| `requirements` | a body of requirements as a whole, with no named quantity | "The supplier shall be certified to ISO 9001" |
| `data` | data or findings, which the source states itself and credits to the target | "an emission factor of 2.31 kg CO2 per litre (IPCC 2006)" |
| `general` | nothing specific | "for a review, see [3]" |

These two labels replace the seven "reference types" of the previous revision. Each old type is
now a combination: `value` = `requires` + `data_element` + `criterion`; `value_set` = `requires` +
`section` + `criteria_set`; `method` = `uses` + `method`; `definition` = `defines_in` + `term`;
`requirements` = `requires` or `complies_with` + `requirements`; `source` = `cites` or `quotes` +
`data`; `background` = `see_also` + `general`.

### 3.5 Form, normativity and requirements

Two conventions of standards are named directly because standards bodies share them (ISO/IEC
Directives Part 2, CEN/CENELEC, ASTM, IEEE, and national rules such as GB/T 1.1). Both are
recognised by their purpose, never by a fixed heading string.

- **Normative references** are documents the source **lists explicitly and formally** as
  normative, in a section dedicated to them. Examples are "Normative references" (ISO/IEC
  Directives Part 2, clause 2), "Referenced documents" (ASTM), "Applicable documents" and
  规范性引用文件. The section is a list of documents that, by its heading and introductory statement,
  are indispensable for applying the source.
- **Terms and definitions** is a section that exists only to define terms. Glossaries and the
  "Definitions" article of a regulation or contract count too. A reference in such a section, or a
  statement that the terms of a cited document apply, gets `defines_in` + `term`.

Labels:

- `ref_form`: `listed` (an entry of a reference list: normative references, bibliography,
  reference list, further reading) or `in_text`. A target cited both ways gives one listed row and
  one in-text row per occurrence. Each in-text row points to its list entry (`list_entry_id`).
- `normativity`: `normative` (listed in the normative references list, or an in-text reference to
  such a document), `informative` (listed only in an informative list), or `unlisted` (in no list).
  **It comes from the lists only, never from wording.**
- `in_requirement`: true when the reference sits inside a requirement of the source ("shall",
  "must", 应). Binding references are common in documents that have no normative references list,
  such as regulations, contracts and specifications. They are `unlisted` with
  `in_requirement = true`, and they are not counted as normative references.
- `list_mismatch`: only when the source has a normative references list. `not_listed` means
  cited inside a requirement but missing from the list. `never_cited` means a list entry the text
  never uses. Both are drafting defects of the source and are recorded, not corrected.

Table references retain their source rows in `kb.ref_mentions.source_table_rows`, with the same
`{line, rows, row_hash}` JSONB representation used by metrics. The prompt reports logical row
citations (`116#r1`); code validates them and computes hashes from the source grid. Captions and
selected rows become evidence. Explicit rows take precedence; absent valid row citations, the
metrics evidence-matching and small-table fallback selects rows. Prose references have no table
provenance. Re-run extraction to populate existing records. The references API exposes the rows.

## 4. Detection and resolution

Detecting a mention and resolving it are separate operations. Resolution runs
in levels, and each level can stop with candidates for a person to choose from.

| Level | Maps… | to… | Possible outcomes |
|---|---|---|---|
| **D. Detection** | text | a mention with its labels and the identifiers it contains | (always) |
| **R1. Resource** | a mention | one canonical resource in the catalog, plus a version if cited | `resolved` · `candidates` · `new_resource` |
| **R2. Holding** | a resource version | a document in `kb.inputs` the citing user can access | `held_processed` · `held_not_processed` · `not_held` · `edition_mismatch` · `edition_ambiguous` |
| **R3. Location** | a `target_locator` | a section, table or element of the held document | `located` · `candidates` · `not_found` |
| **R4. Metric** | a `criterion` / `criteria_set` reference | metrics of the held document | steps 5–6, see "Metric references" |

### 4.1 Identity is separate from location

The same paper can appear as an arXiv URL, a DOI, a publisher page and a local PDF. The same
standard is cited as `GB/T 755`, `GB/T755-2019` or by its title. They resolve to **one resource**,
and each identifier, edition and copy stays recorded:

- a **resource** is the conceptual work (ISO 13485; the paper "…" by Smith et al.);
- a **version** is an edition, revision, draft or amendment state (ISO 13485:2016; Revision 2;
  draft v1.3). Versions carry `supersedes` / `version_of` links and a status (current, withdrawn,
  draft) where known;
- an **identifier** is any way to name or locate the resource or one version: standard number, DOI,
  URL, arXiv id, ISBN, legal citation, repository path, file path, or a `kb.inputs` record id (the
  user's own copy).

Normalization depends on the identifier kind: standard numbers keep prefix, number and part apart
from the edition (`GB/T755` → `GB/T 755`; in `ISO 14253-1`, `-1` is a part). DOIs are
case-folded. Legal citations are normalized by jurisdiction, act type and number. URLs are kept as
given. Standards have one edition convention: an **undated** citation means the latest edition
(ISO/IEC Directives Part 2, GB/T 1.1). Elsewhere, a citation without version or date that matches
several versions is `edition_ambiguous`.

The citing document needs a reliable identity too. `kb.inputs.doc_no` is often empty: 753
(GB/T 46121-2025) has none even after `extract_metadata`. The processor links each processed
document to its resource and version, taking the identifier from metadata, the first page or the
filename.

### 4.2 Access: resolution never crosses what a user may see

Customers keep private documents. Resolution must not leak them:

- **The catalog is shared across all customers** for resources known by public identifiers (a
  standard number, a DOI, a legal citation, a public URL). Each resolution then helps the next
  customer. A shared entry holds only public facts: identifiers, title, issuer, editions and their
  status. It never records which customer cites or holds the resource. A resource known only from a
  private source (an internal file path, a company policy) is scoped to that knowledge store.
- **R2 (holding)** links a reference to a `kb.inputs` record only if the citing document's owner
  can access that record (same user or knowledge store, or an active grant).
- **Incoming resolution** (step 6) and "who cites this document" views follow the same rule. A
  user never learns that someone else's private document cites theirs.

## 5. Layering: the reference extractor and the artifact extractors

### 5.1 Two layers

`extract_references` is the **lower layer**. It knows that documents point at things. It knows
which resource a reference means, whether the user holds a copy, and which place in that copy it
points to (D and R1–R3 in §4). It knows nothing about metrics, provisions, entities or inventory
items. It never reads their tables, and it never needs one of those extractors to have run.

The **artifact extractors** sit above it. Each one knows its own kind of artifact, and so it is the
only one that can tell which artifact in the target document a reference means (R4). Each artifact
family takes the references whose content is its kind:

| Artifact family | Extractor | Takes references with | Artifact table | Status |
|---|---|---|---|---|
| metrics | `extract_metrics` | `target_content` = `criterion` or `criteria_set` | `kb.metrics` | designed in §6 |
| provisions | `extract_provisions` | `target_content` = `requirements`, scope `section` or `requirement` | `kb.provisions` | to be designed |
| entities | `extract_entity_relation` | target types for persons, organizations, products, locations, events | `kb.entities` | to be designed; also where the reference/entity overlap is reconciled |
| inventory items | `extract_inventory_items` | to be defined | `kb.inventory_items` | to be designed |
| future extractors | … | their own `target_content` / `target_type` | their own | — |

A reference that no family takes (a `method`, a `term`, `general`) is still fully recorded and
resolved down to R3. It just has no artifact to point at yet.

### 5.2 Steps 5 and 6 for any artifact family

For an artifact family F, with A the referencing document and B the referenced one:

- **Step 5, on the reference side.** When `extract_references` processes A, it looks at each of A's
  references that F takes. If the target B is held and already has F artifacts, the reference is
  resolved against them.
- **Step 6, on the artifact side.** When F's extractor processes B, it first writes B's artifacts.
  Then it looks up the references from other documents that point at B and that F takes, and
  resolves them against the new artifacts.

Both steps use **the same resolver**, the one family F provides. So the result does not depend on
which document was processed first.

### 5.3 The resolver contract

The lower layer defines one interface, and each artifact family implements it and registers it.
The dependency is inverted: the reference layer calls family code through the interface but never
imports it.

| Operation | Does |
|---|---|
| `Takes(mention)` | whether this family handles the reference (by `target_content`, `target_type`, scope) |
| `Resolve(mention, target record)` | ranks candidate artifacts of the target with scores, by the family's own matching rules and decision policy |
| `Apply(mention, outcome)` | writes the links (`kb.reference_artifact_links`) and anything the family adds to its own table for the referencing document. For metrics, that is the resolved rows of §6.3 |
| `Withdraw(mention or target)` | removes what `Apply` wrote when the reference or the target is processed again |

The reference layer calls every registered resolver in step 5. Each artifact extractor calls its own
resolver in step 6. The reference layer never writes an artifact table, and an artifact extractor
never parses references.

### 5.4 Whoever comes second resolves

Documents are processed in any order, and processors in Phase B run at the same time. Three events
can make a reference resolvable. Each handler first commits its own writes, then looks for the
other side:

| Event | Handled by | Looks for |
|---|---|---|
| A's references are written | `extract_references` on A | A's references into held documents that already have artifacts → step 5 |
| B is linked to its resource, so it becomes "held" | `extract_references` on B | other documents' references waiting on B's resource. For each one, if B already has artifacts of a family that takes it → step 5 on A's behalf |
| B's artifacts of family F are written | F's extractor on B | references into B that F takes → step 6 |

Because each side writes before it looks, when A and B are processed at the same time at least one
of them sees the other. If both do, nothing is duplicated: writes are upserts keyed on (mention,
target artifact key).

As a result, there is no ordering between `extract_references` and any artifact extractor, and all
of them stay in Phase B. If `extract_references` is not configured, step 6 finds nothing and the
artifact extractor works exactly as it does today.

### 5.5 Re-runs

| What is re-run | What happens |
|---|---|
| `extract_references` on A | A's references are rebuilt. Resolvers `Withdraw` what they applied for A's old references, then step 5 runs again. Human decisions reattach by `mention_key` |
| F's extractor on B (the target) | B's artifacts are renumbered. Step 6 re-resolves every reference into B that F takes, and rewrites links and rows. Confirmed links reattach by the target artifact's stable key, or become `stale` and are flagged |
| F's extractor on A (the referencing document) | It must not delete what `Apply` wrote into A. For metrics, the delete skips resolved rows (§6.3) |

## 6. Metric references: the metric family (steps 5–6)

This section is the metric family's side of §5. It covers which references the metric resolver
takes, how it matches them, and what it writes. `extract_references` runs it in step 5, and
`extract_metrics` runs it in step 6, right after it has written a document's metrics.

### 6.1 Deciding that a reference points at metrics

Only references with `target_content` = `criterion` or `criteria_set` can resolve to metrics. The
decision is made in two stages, and the second can confirm or weaken the first.

**1. The source text, read by the LLM at detection.** A reference has `criterion` only when it
passes three tests:

- **It names a measurable quantity of an object**: something with a value on a unit or scale
  (faecal coliform count, moisture content, NOx emission, sound power). A process, activity,
  product or management system as a whole is not one.
- **It takes the criterion for that quantity**, meaning the limit, grade or required value, and not
  the way it is measured. "Shall comply with / meet / not exceed the requirements or limits of X"
  takes a criterion. "Measured / determined / tested / calculated in accordance with X" takes a
  `method`, even when a quantity is named. 753_drp_49 ("rated power of the fan motor, determined in
  accordance with GB/T 755") names a quantity and is still `method`.
- **The source does not state the value itself.** If it does, the content is `data`.

It is `criteria_set` when the text names a set of criteria instead of one quantity (a placeholder,
or a locator such as a table or class). Text that takes "the requirements" of a whole document, with
no quantity and no locator, is `requirements` and never adds metrics. Copying every metric of a
document because a clause says "comply with X" would claim far more than the clause does.

The prompt carries these tests with examples from several domains and languages, not a word list.
The phrases quoted above are hints, as in the decision policy (devdoc 2026100801).

**2. The target document, once held and processed.** A `criterion` reference expects the target
to hold a metric for the named quantity. If none is found, and the target has no metrics of that
kind at all (GB/T 755, a rating and method standard, is an example), the reference is marked
`no_match` with `type_doubtful` and goes to review. It is never quietly retyped.

### 6.2 Matching

For a metric reference whose target is `held_processed`:

1. Candidates come from the target's `kb.metrics` (not its own resolved rows: no chains in v1) and
   its `kb.metrics_dropped` definitions, narrowed by the R3 location when there is one.
2. They are scored on the same governed term (`metric_definition_term_id` / `keyword_concept_id`),
   name, alias and subject match in the source and target languages, bge-m3 similarity of
   `search_document`, and an LLM judge for the top few.
3. One or more candidates at or above the policy threshold → `resolved`, and resolved rows are
   written. This also holds for a `criteria_set` that resolves to many metrics: there is no extra
   confirmation step. Otherwise → `needs_review` with the top candidates kept. No candidates →
   `no_match`.
4. A person confirming or rejecting a candidate sets `confirmed` / `rejected`. Confirmed links
   write rows like resolved ones.

Thresholds are a versioned policy in `shared.decision_policies`, calibrated on real references
from more than one domain and language before they are trusted.

### 6.3 Resolved metrics in `kb.metrics` (steps 5–6)

1. **Owned by the metric resolver.** The rows are written through `Apply` from either step.
   `extract_metrics`' delete
   (`DELETE FROM kb.metrics WHERE input_record_id = $1`) becomes `… AND ref_mention_id IS NULL`,
   so a re-run of the referencing document keeps resolved rows. The resolver replaces only its own rows, per
   reference.
2. **Own id namespace.** Resolved rows use `<rec>_rfm_<n>` and never collide with `<rec>_mtc_<n>`.
3. **The source's context, the target's value.** Subject, context, section and
   `source_line_spans` and `source_table_rows` come from the referencing text. Value, unit, range type, condition and value
   class come from the target metric.
4. **Stable keys.** Target rows are renumbered when the target is re-processed, so every link also
   stores a fingerprint of record, section, normalized name, subject and condition. Human
   decisions survive re-runs through it. A confirmed link whose key disappears becomes `stale` and
   is flagged.
5. **Idempotent.** Two documents that reference each other can be processed at the same time.
   Writes are upserts keyed on (mention, target metric key).

**Every reader of `kb.metrics` sees these rows.** About 50 Go files read the table, so each one
needs an explicit default:

| Reader | Default for resolved rows |
|---|---|
| Benchmark scoring | **never scored** (decided 2026-10-11) |
| Phase D `normalize_assertions` | excluded until provenance can say "value asserted by B, applied by A" |
| Class contracts, conformance, comparisons | excluded, or counted once at the target |
| Search index, hybrid links | indexed, labelled as a reference, linked to the original |
| Metric list and explorer pages | shown with a "from <target>" badge and a link |

The openspec change lists every reader.

## 7. Pipeline placement

| Part | Tier | Depends on | Does |
|---|---|---|---|
| `extract_references` | Phase B (configurable) | `chunking` | D and R1–R3, outgoing and incoming (§5.4, first two events); step 5 through the registered resolvers |
| `extract_metrics` (and every artifact extractor) | Phase B, as today | `chunking` | its own extraction, then step 6 through its own resolver (§5.4, third event) |

- Detection uses `canonicalChunkInputText`, so it shares the DeepSeek cached prefix with the other
  chunk processors (capsule §6.2). Reference lists and identifiers that a pattern can read exactly
  (DOI, URL, standard number) are parsed in code, and the LLM handles the rest.
- `extract_references` depends on nothing but `chunking`, in line with its independence (§1).
- **No ordering is needed** (§5.4). Step 5 can write resolved rows into A's `kb.metrics` while
  `extract_metrics` runs on A, because its delete skips resolved rows and the two use different id
  namespaces (§6.3).
- **A Dev Mode re-run of `extract_metrics` alone still resolves.** Step 6 is part of
  `extract_metrics`, so waiting references into the document are resolved and stale rows are
  rewritten. The step is cheap when nothing waits.
- Not being sure is a review state, not a failure. The run succeeds, WARN lines are logged, and the
  run log reports counts per state.

## 8. Tables (proposed, goose migrations, created at start-up)

### 8.1 `kb.ref_mentions`: one row per reference occurrence; rebuilt on each run of the source

| Column | Meaning |
|---|---|
| `id`, `input_record_id`, `event_id`, `run_id`, `ref_id` (`<rec>_ref_<n>`) | identity, provenance |
| `section`, `source_line_spans`, `evidence` | where, and the exact text |
| `ref_form`, `list_kind`, `list_entry_id` | `listed` · `in_text`; `normative` · `informative`; link to the list entry |
| `normativity`, `in_requirement`, `list_mismatch` | see "Form, normativity and requirements" |
| `mechanism`, `cited_raw`, `identifiers` (jsonb `[{kind, value}]`) | how it is written; as written; parsed identifiers |
| `target_type`, `target_subtype`, `target_subtype_label` | governed type and subtype (`others` if not in the vocabulary); the extractor's own label |
| `target_title`, `target_version` | what is referenced, as stated |
| `relationships` (text[]) | asserted relationships |
| `target_scope`, `target_locator`, `target_content` | how precisely, where, what is used |
| `metric_name`, `metric_subject`, `condition` (+ `_en`) | the named quantity, for `criterion` |
| `internal` | true for references inside the same document |
| `confidence` | detection confidence |
| `resource_id`, `version_id`, `r1_state` | R1 result |
| `target_input_id`, `r2_state`, `target_section`, `r3_state` | R2 and R3 results |
| `metric_state` | `not_applicable` · `pending_target` · `resolved` · `needs_review` · `no_match` · `confirmed` |
| `mention_key` | stable fingerprint, so human decisions survive re-runs |

### 8.2 `kb.ref_resources`, `kb.ref_resource_versions`, `kb.ref_resource_identifiers`: the catalog

| Table | Holds |
|---|---|
| `kb.ref_resources` | one conceptual resource: `target_type`, `target_subtype`, canonical title (original + `_en`), issuer or authors, `visibility` (`public` or a knowledge store id) |
| `kb.ref_resource_versions` | editions, revisions, drafts, amendments: label, date, status, `supersedes_version_id`, adoption degree |
| `kb.ref_resource_identifiers` | every identifier of a resource or version: `kind` (standard number, DOI, URL, arXiv, ISBN, legal citation, repository, file path, `kb_input`) and normalized `value`; unique per (kind, value, visibility) |

A `kb_input` identifier is how a user's own copy is attached to a resource version. That attachment
is never `public`.

### 8.3 `kb.reference_artifact_links`: mention → candidate or resolved target artifact, for every family

| Column | Meaning |
|---|---|
| `id`, `ref_mention_id` | the reference |
| `artifact_family` | `metric` · `provision` · `entity` · `inventory_item` · … (the resolver that wrote it) |
| `target_input_id`, `target_artifact_id`, `target_artifact_key` | the target artifact (positional id + stable key) |
| `rank`, `score`, `match_method` | `term` · `name` · `embedding` · `llm_judge` · `human` |
| `status` | `candidate` · `resolved` · `confirmed` · `rejected` · `stale` |
| `policy_id`, `policy_version`, `decided_by`, `decided_at` | decision provenance |
| `resolved_artifact_id` | the row the family added to the referencing document, if any (for metrics, `<rec>_rfm_<n>` in `kb.metrics`) |

### 8.4 `kb.metrics`: new columns, null on every `extract_metrics` row

`ref_mention_id` (non-null marks a resolved reference row), `ref_input_record_id`,
`ref_metric_id`, `ref_metric_key`.

Candidates for R1 and R3 are stored the same way as metric candidates (rank, score, status), in
`kb.ref_resolution_candidates` keyed by mention and level.

## 9. What people can ask

The point of the processor is to answer questions about how a body of documents is connected. With
the tables above, each of these is one query or one page:

- **Dependencies.** What does this document depend on? Show its normative references, or
  everything it requires, uses or complies with.
- **Impact.** Who relies on this document, this clause, this dataset, this API? Filter by
  relationship and normativity.
- **Versions.** Which of my documents cite an edition that has been superseded or withdrawn?
- **Gaps.** Which referenced resources do I not hold yet? These are `not_held` resources, ranked by
  how many of my documents reference them.
- **Traceability.** Which requirements in my documents trace to which clause of which regulation or
  standard?
- **Values.** What is the actual limit behind "shall meet the requirements of X"? The answer comes
  from the resolved metric rows.
- **Drafting checks.** Which documents cite in requirements without listing the document as a
  normative reference, or list one they never use?

Search support:
- indexes on (`input_record_id`, `normativity`), (`resource_id`, `relationship`) and
  (`target_type`);
- a `kb.search_artifacts` partition `reference` (capsule §12.3: BM25 + embeddings), filterable by
  target type, relationship, normativity, `in_requirement` and resolution states;
- a document graph page (EN/ZH via Paraglide, selectable text) with Normative / Informative /
  Unlisted badges.

## 10. Processor contract (capsule §12 checklist)

- `extract_references` is configurable and depends on `chunking`. Its status entry
  (`operation: "extract_references"`) carries counts per target type, relationship and resolution
  state.
- `CheckAndHandleStop` at every LLM call boundary. Logging through `kb.doc_proc_logs` with
  `CreateDefaultLogger`.
- Deletion contract (ADR 2026072301): deleting a record deletes its mentions, links and resolved
  rows, and its `kb_input` identifiers. Links **into** it become `stale`, and those mentions go back
  to `not_held`.
- The resolver interface (§5.3) lives in the reference layer. `extract_metrics` implements the
  metric resolver, registers it, and calls it as step 6 after writing a document's metrics.
- Dashboard: add `extract_references` to `ALL_PROCESSOR_IDS`, `PIPELINE_FINAL_OPS` and the stage map.
- A review page for every `candidates` / `needs_review` state.

## 11. Decisions (2026-10-11)

| Question | Decision |
|---|---|
| Share `public` catalog entries across all customers? | **Yes**, public facts only (§4.2) |
| Confirm a `criteria_set` that fans out to many metrics before writing rows? | **No**, resolved rows are written like any other (§6.2) |
| Score resolved metric rows in the benchmark? | **No**, never (§6.3) |
| `contradicts` | **Flagged**, and an admin page lists all flags for an admin to resolve; specified separately (§3.3) |
| Subtypes | **Governed vocabulary** per target type, with an `others` subtype (§3.1) |

Still open, to be addressed separately:
- the resolvers of the other artifact families: provisions, entities, inventory items (§5.1);
- reconciling references with what other processors extract, e.g. persons and organizations found
  as entities by `extract_entity_relation` (§1);
- the contradictions page and its storage (§3.3).

## 12. Known limitations (by design)

- Only documents in `kb.inputs` that the citing user can access are resolved to. Other resources
  stay in the catalog as `not_held`.
- No metric chains in v1. If B's metric itself references C, A resolves to B's row only.
- Only `criterion` and `criteria_set` references add rows to `kb.metrics`. All other references
  live in the reference tables.
- The source's wording is the evidence. Nothing is fetched from the web to resolve a reference.
- `extract_metrics` is unchanged. Value delegations stay in `kb.metrics_dropped`
  (`delegated_requirement`), next to the resolved rows.
