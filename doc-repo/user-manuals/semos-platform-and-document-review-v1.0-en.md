---
title: SemOS Platform and Document Review — User Manual
language: en
format: markdown
version: 1.0
status: current
author: Not specified
owner: Not specified
audience: Document reviewers, knowledge-base operators, ontology curators, and policy owners
create-time: 2026-08-12T19:04:37-05:00
last-modify-time: 2026-08-12T19:06:19-05:00
keywords: SemOS, document processing, document review, ontology, governed vocabulary, pipeline policy, knowledge store, metrics, evidence, requirements comparison
---

# SemOS Platform and Document Review — User Manual

## 1. What this platform helps you do

SemOS turns documents into reviewable, traceable knowledge. It helps you:

- process each document with the right set of extraction steps;
- avoid paying for or running processors that a document does not need;
- recognize the same thing when documents use different names;
- keep extracted evidence separate from approved meaning;
- review documents against versioned requirements; and
- compare requirements from several authorities while keeping the source clauses visible.

The central user outcome is an answer that can be explained:

> What did the system find, why did it process this document that way, which approved meaning does the result use, and where in the source document is the evidence?

This manual explains those outcomes in user language. The architecture record contains internal decision identifiers; this manual uses the capability names and actions instead.

## 2. The basic idea: evidence first, governed meaning second

SemOS keeps two things separate:

1. **Evidence** — what a document says, where it says it, and which processing run produced the result.
2. **Governed meaning** — the approved terms, relationships, rules, and requirements used to interpret that evidence.

An extracted product name, metric, unit, or relationship is therefore not automatically an approved ontology term. It remains evidence or a candidate until the appropriate governance process accepts it.

This separation protects the review record. If a model makes a mistake, the original text and the model's decision history remain available. A later correction does not rewrite the source document or silently change an old review.

## 3. Words you need to understand

| User-facing term | Meaning |
|---|---|
| **Knowledge store** | The project, tenant, or collection that provides the default scope for processing, names, and review. Two stores can intentionally use different meanings for the same short name. |
| **Facet** | A fact about a document used for routing or review, such as document kind, language, domain, jurisdiction, or whether it is normative. |
| **Pipeline** | A named set of document-processing steps, such as extracting metrics or provisions. |
| **Pipeline policy** | Versioned rules that decide which pipeline applies and whether an individual processor runs. |
| **Ontology term** | An approved, stable meaning such as a class, property, metric definition, unit, or quantity kind. A label can change without changing the term's identity; a material change in meaning requires a new term. |
| **Domain module** | A package of approved terms and rules for one subject area. Adding one is intended to be a data and release operation, not a code change. |
| **Assertion** | A qualified claim, such as “this product has this metric” or “this part is a component of that product.” It includes evidence, time, confidence, and other context needed to interpret the claim. |
| **Profile** | A versioned set of expectations for a review, such as which measurements a class of product must provide in a jurisdiction. |
| **Review scope** | The frozen set of releases, facts, rules, and context used for one review. |
| **Candidate** | A proposed term, label, mapping, rule, or other governed item awaiting the required approval. |

The database names may appear in diagnostics or API responses. For example, approved terms are stored in `kb.ontology_terms`, document facts in `kb.doc_facets` or `kb.doc_facet_values`, and pipeline policies in `kb.pipeline_policies`.

## 4. Processing a document

### 4.1 Put the document in the right knowledge store

The knowledge store is more than a folder. It supplies the default context for:

- which pipeline should process the document;
- how names and identities are resolved;
- which vocabulary is relevant; and
- which review rules may apply.

For example, a short name such as `ML` can have different meanings in different stores. Keeping the store as a scope boundary prevents one project's vocabulary from contaminating another project's results.

At ingestion, a document can also carry an explicitly requested pipeline. That request is retained for reruns of the same record.

### 4.2 Let SemOS learn the document facts it needs

The platform builds document facts in a cost-conscious order:

1. **Deterministic facts** are calculated from the document structure, such as language mix, page or table characteristics, unit density, heading structure, and document-number patterns.
2. **Metadata facts** come from already extracted information such as issuer, edition, publication date, and authority hints.
3. **Classification** uses a small language-model call only when a rule needs a fact that the cheaper steps did not determine. Typical examples are document kind, domain, normative status, and jurisdiction.

The model classifies the document into approved vocabulary. It does not decide directly whether a processor should run. Versioned policy rules make that decision from the recorded facts.

### 4.3 Understand how the pipeline is selected

The system considers these choices from strongest to weakest:

1. An explicit processor list in the request.
2. A pipeline explicitly requested when the document was added.
3. A run-specific override from an administrator or development tool.
4. A matching binding rule, with higher priority and narrower scope winning.
5. The knowledge store's default pipeline.
6. The system default pipeline.

After a pipeline is selected, individual processor rules decide whether each optional processor runs. A direct request or run override takes precedence over policy rules. Among policy rules, higher priority and more specific conditions win.

### 4.4 Check the execution plan before relying on the result

SemOS creates a plan before it runs the processors. The plan records:

- the policy version;
- the selected pipeline and the reason it was selected;
- the document facts used;
- each processor's decision: run, skip, or defer;
- the rule or override responsible; and
- the reason and expected cost.

Use the plan when someone asks:

- “Why were metrics extracted from this document?”
- “Why did the provisions processor not run?”
- “Which policy version produced these artifacts?”
- “What should change before we rerun the document?”

The plan is also what makes a historical run explainable after policy changes.

### 4.5 What happens when rules conflict

A conflict is a policy problem, not a document problem. Examples include two equally strong bindings choosing different pipelines or equally strong processor rules making incompatible choices.

By default, SemOS:

- stops the run before processors produce partial output;
- marks the run as failed;
- records an error in the alarms system; and
- names the conflicting rule or binding identifiers.

This behavior is deliberate. Choosing silently would produce artifacts under an uncertain plan and make the error harder to find.

An installation may enable fallback behavior. In that mode, SemOS tries a broader, less specific level, records a warning, and annotates the plan. Fallback should be used as an explicit operating choice, not as a substitute for repairing the policy.

### 4.6 What processing produces

The pipeline produces evidence-bearing artifacts such as document structure, metrics, provisions, entities, inventory items, or scene information. These artifacts remain tied to their source locations and processing history.

Semantic association is a later part of the processing flow. It normalizes artifacts into candidate claims, resolves their targets, validates them, and stores accepted assertions. A failure in this later step does not delete the artifacts already saved.

## 5. Managing approved vocabulary and domain content

### 5.1 Use the right kind of content

SemOS separates platform-wide meaning from domain-specific meaning:

- **Core content** defines shared ideas such as assertions, evidence, roles, time, quantities, and measurement patterns.
- **Domain content** defines a subject area such as medical devices, pumps, pressure vessels, or tax rules.

A domain module may use the shared contracts, but it may not quietly invent a new assertion kind, value form, predicate, or qualifier dimension. If the domain needs a new shared capability, that is a platform change that must be reviewed separately.

The benefit is practical: installing a domain module should change the available vocabulary and rules without requiring a new processor or application build.

### 5.2 Author, review, release, and activate

Treat governed content as versioned content, not as mutable labels in a live database.

The normal lifecycle is:

1. **Author** terms, labels, mappings, profiles, and rules through an approved authoring path.
2. **Review** content that came from an import, discovery process, or language model. Such proposals enter the candidate workflow.
3. **Validate** the approved staged content, including references, dependencies, and consistency.
4. **Release** an immutable snapshot with a deterministic checksum and pinned dependencies.
5. **Activate** the release as a separate, audited action.
6. **Rollback** by pointing activation back to an earlier release if needed; do not delete the release or its history.

Only an approved release can become production-active. A language model, importer, or discovery process cannot activate ontology content directly.

An accepted change to a released term does not mutate the old meaning. It creates a new version or replacement term, preserving the earlier version for historical reviews.

### 5.3 Keep relationships conservative

A label that looks similar is not automatically an exact equivalent. Supported relationship strengths have different meanings:

- **Exact** — the two identifiers represent the same meaning.
- **Close** — related enough to be useful, but not proven identical.
- **Broad / narrow** — one meaning covers a wider or narrower scope.
- **Related** — associated, without an identity claim.

Imports must preserve these distinctions. In particular, a `close`, `broad`, `narrow`, or `related` source relationship must not be promoted silently to an exact identity.

## 6. Resolving names and identity safely

SemOS uses one shared identity approach for objects, keywords, categories, and ontology terms. It normalizes names, generates candidates, scores them, records the decision, and supports later correction.

The practical rules are:

- keep the original surface text;
- derive lookup keys instead of treating a key as the identity itself;
- preserve ambiguity instead of hiding a tie;
- keep decisions and evidence in an append-only audit trail;
- record merges as tombstones rather than deleting the losing record; and
- never let automatic reconciliation override a locked human assertion or a `never_merge` decision.

For keywords, a common name can resolve quickly to a lexical concept. That lexical concept is still separate from the governed ontology term that defines its meaning. An explicit alignment is required to connect the two.

Similarity and embeddings are useful for finding candidates. They are not, by themselves, authority to activate identity, classification, mappings, or axioms.

## 7. Reviewing documents against requirements

### 7.1 Select the governing expectations

A profile states what should be present or true for a scope, such as:

- a product or part class;
- a jurisdiction;
- an operating context;
- an effective date; or
- a document or authority family.

Applicability rules use the same document facts and classification facts that pipeline routing uses. This keeps extraction and review aligned: a document is not reviewed against requirements whose supporting evidence the selected processing plan never attempted to collect.

### 7.2 Freeze the review scope

Before evaluation, SemOS freezes the review scope. It records the active module releases, profile and rule versions, applicability facts, context, and any explicitly closed dimensions.

This gives two important results:

- a historical review can be rerun against the same inputs; and
- later vocabulary or policy changes do not silently rewrite old findings.

### 7.3 Interpret review results

The review distinguishes outcomes such as satisfied, missing, conflicting, nonconforming, inapplicable, and indeterminate.

`Indeterminate` means the available identity, classification, condition, unit, or other evidence was not sufficient to decide. It is different from “missing.” Do not treat an unresolved fact as proof that a requirement failed.

Similarly, a claim that a standard has no requirement (`standard_absent`) is valid only when the relevant authority family and property were explicitly declared complete for that review. An incomplete document collection must produce `indeterminate`, not `standard_absent`.

## 8. Comparing requirements across standards

The comparison matrix belongs to the Document Review application. It is not another document processor.

To run a comparison, the application identifies:

- the target class or object;
- the set of metric definitions to display as rows;
- the authority families to display as columns;
- the organization whose requirements are being considered;
- the date, jurisdiction, and operating context;
- which dimensions are closed for “standard absent” conclusions; and
- the module releases and precedence policy to use.

A cell can contain many assertions from many documents and editions. The application may show one representative assertion, but it also keeps the remainder count, citations, line evidence, and underlying assertions queryable.

For numeric constraints, the comparison can determine whether one requirement is identical, equivalent after unit conversion, stronger, weaker, conflicting, or incomparable. Qualitative requirements without a decidable limit are shown as needing verification rather than being ranked by guesswork.

A recommendation such as “adopt the stricter requirement” is separate from the comparison verdict. Changing an organization's recommendation policy must not change the underlying factual verdict.

## 9. Finding the source clause

Every finding, assertion, and comparison result should lead back to a portable source line span. The viewer then converts that span to a page and highlight using the document's actual source format.

This keeps semantic data independent of whether the source was:

- an uploaded PDF with parser coordinates; or
- an authored or generated document with exact layout anchors.

Coordinates are not part of the meaning of an assertion. If a renderer or source version changes, the locator can detect that the old coordinates need to be recalculated.

## 10. What is available and what remains limited

The architecture record is a living decision record, and its status notes distinguish design from verified implementation. The following boundaries are important when operating the system:

| Capability | Status recorded by the source |
|---|---|
| Shared ontology storage, module release and activation lifecycle | Built in the platform; only the `core` module is confirmed released and active in the referenced live database. |
| Pipeline policies, bindings, processor gates, and execution-plan records | Built in part and in active use; the database-backed policy lifecycle and plan API are available. |
| Cost-aware document facets | Deterministic and metadata facet producers, plus routed document classification, are wired. |
| Full dependency-driven stage graph | Not built; current execution still uses the existing hard-coded phase structure while declarations and gates prepare for a later planner. |
| Semantic association | The metric and provision path is built; other artifact families remain future work. |
| Domain modules | The mechanism exists, but the planned medical-device pilot module has not been authored. |
| Keyword-to-governed-term alignment | The bridge exists, but a deployment still needs released metric-definition terms and approved vocabulary evidence. |
| Comparison caching and recommendation-policy storage | The comparison service and persistence exist; invalidating cache behavior and recommendation-policy storage are not yet built. |
| RDF, OWL, SHACL, SPARQL, and triple-store runtime | Not the production runtime. PostgreSQL plus SQL and APIs are the operational source of truth; standards are adopted selectively for modeling, import, or future export. |

Check the current implementation and deployment status before promising a workflow to users. The ADR is the design reference, but its status notes explicitly mark partial and deferred work.

## 11. Common questions

**Why did a processor not run?**

Open the execution plan. It shows the selected policy, the processor decision, the winning rule or override, and the reason. If the plan was blocked, inspect the named conflict in the alarms system.

**Why did the system use a language model?**

The model should be used only when cheaper document facts did not answer a required classification question. It classifies into governed values; policy rules make the processing decision.

**Can extracted text become an approved term automatically?**

No. Extracted text remains evidence. Imported, discovered, or model-generated proposals must pass the candidate and approval path before they can enter an active release.

**Can I change a released term in place?**

No. Create a new version or replacement term so historical reviews remain reproducible.

**Why did the system stop instead of choosing one pipeline?**

An unresolved routing conflict is treated as a policy defect. Blocking prevents partial, misleading output. Fallback can be enabled deliberately, but the policy should still be repaired.

**Why does a similar name not automatically mean the same thing?**

Similarity finds candidates; it does not prove identity. The system needs an accepted alignment, mapping, or domain decision, with evidence and provenance.

**Why is a result indeterminate instead of missing?**

The system could not establish the identity, classification, condition, unit, or completeness needed to decide. “Missing” should be used only when the relevant review scope is sufficiently closed and the required evidence is genuinely absent.

## 12. Reference

This manual is based on:

`KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`

The ADR remains authoritative for implementation details, exact status notes, open decisions, database structures, and future work.

## Change Log

| Version | Timestamp | Author / responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.0 | 2026-08-12T19:06:19-05:00 | Not specified | Initial manual | Translated the SemOS architecture decision into a user-focused guide for document processing, policy routing, governed content, review, comparison, and evidence tracing. |
