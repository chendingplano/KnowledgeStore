---
title: Semantic-Web Standards in SemOS — User Manual
language: en
format: markdown
version: 1.0
status: current
author: Not specified
owner: Not specified
audience: Ontology curators, system administrators, knowledge-base operators, and application owners
create-time: 2026-08-16T06:18:03-05:00
last-modify-time: 2026-08-16T06:18:03-05:00
keywords: SemOS, semantic web, RDF, OWL, SKOS, SHACL, QUDT, ontology, terminology import, ontology modules, Turtle, profiles
---

# Semantic-Web Standards in SemOS

## 1. What this page explains

SemOS uses semantic-web standards selectively. It does not treat RDF, OWL, SKOS, and SHACL as one package that must either be installed completely or rejected completely.

This page explains what a user or operator can expect today:

- standards-inspired modeling conventions are built into the SemOS data model;
- selected published vocabularies can be imported as governed database content;
- profile rules can produce SHACL shapes for future interchange; and
- PostgreSQL plus SQL/Go remains the operational system of record and evaluator.

The goal is to gain the useful parts of the standards without changing review semantics or introducing infrastructure that current applications do not need.

## 2. The four levels

| Level | What it means in practice | Current SemOS status |
|---|---|---|
| **Modeling discipline** | Use proven distinctions when defining terms, labels, measurements, evidence, and provenance. | **Adopted.** The distinctions are represented in SemOS tables and governed modules. |
| **Data** | Import selected external vocabularies and preserve their identifiers and provenance. | **Adopted selectively.** QUDT is imported from Turtle into the `quantity` ontology module. |
| **Serialization and interchange** | Publish SemOS content as RDF/Turtle, JSON-LD, or SHACL for another system. | **Deferred as a product workflow.** SHACL emitters exist for profile rules, but there is no general export package yet. |
| **Runtime** | Use an RDF triple store, OWL reasoner, or SPARQL endpoint to run the application. | **Not adopted.** Applications evaluate scoped, closed-world review rules directly in SQL/Go. |

These levels are independent. Importing QUDT data does not mean SemOS runs a triple store. Having a SHACL emitter does not mean SHACL is the live validation engine.

## 3. Modeling discipline: what users can rely on

The standards are used as design guidance for durable distinctions in the database.

### Vocabulary labels and mappings

SemOS keeps the role of a label separate from the identity of a term. A preferred label, an alternative label, and a search-only label are not interchangeable. External relationships also retain their strength: exact equivalent, close or related, broader, and narrower.

A similar spelling or a successful search match does not automatically become an exact identity mapping. Similarity finds candidates; governed identity requires the appropriate evidence and approval.

### Measurements and quantities

SemOS keeps separate concepts for the property being observed or required, the object or feature of interest, the procedure or context, the quantity kind, the unit, and the resulting value or requirement.

For example, “display luminance,” “the display module,” “the test procedure,” “candela per square metre,” and “500 cd/m²” are different parts of a measurement assertion. Keeping them separate allows units to be normalized without changing the metric's meaning.

### Evidence and provenance

SemOS keeps the source entity, processing activity, and responsible agent distinct. A term imported from an external catalog, an assertion extracted from a document, and a human approval are different records with different provenance.

## 4. Data level: importing published vocabularies

The current implementation stores governed ontology content in PostgreSQL. External files such as QUDT Turtle are temporary import input; they are parsed, validated, and written into versioned database content. There is no data-only Git repository that must be edited to activate a vocabulary.

### QUDT in the `quantity` module

QUDT is the current concrete example of selective adoption. The importer reads the QUDT Turtle catalog and recognizes quantity kinds, units, and dimension vectors. Deprecated entries are skipped. Imported terms keep mappings to their original QUDT IRIs, so source identity and provenance remain available.

The imported content is placed in the `quantity` ontology module. A release is then created and activated through the module lifecycle. Only content included in an active release is available to downstream consumers.

The QUDT import is also connected to the **External Terminology Resources** administration workflow. For operational details, see [External Terminology Resources — User Manual](external-terminology-resources.md).

### How an administrator imports a resource

The exact resource list and permissions depend on the deployment, but the current workflow is:

1. Open **System Admin → Resources → External Terminology Resources**.
2. Choose the resource and select **Download**. The system stores the source artifact and creates a draft manifest for license and provenance review.
3. Open **Review External Resources** and inspect the downloaded resource.
4. Select **Approve** only after the source, release, and license are acceptable.
5. For QUDT, approval imports supported catalog content into the governed `quantity` module and activates a module release when approved content is ready.

Select **Disapprove** when the source should not be imported. Disapproval does not import the resource.

### What approval does not mean

Approval of an external resource does not mean every source statement has become an exact SemOS identity. The adapter preserves source identifiers and relationship types, and governance rules determine which mappings can authorize identity.

An unchanged, already registered source release may be treated as an idempotent replay. Changed content under an existing release is rejected rather than silently replacing the earlier content.

## 5. Serialization and interchange

RDF, Turtle, JSON-LD, OWL, and SHACL are not currently the primary storage format or a general export workflow for SemOS users.

The implementation does include SHACL emitters alongside profile-rule evaluators. A supported rule can therefore describe both how SemOS evaluates it natively and a corresponding SHACL shape that may be published later.

This is an extension seam, not a claim that an external SHACL validator currently determines production review results. Some complex SemOS semantics do not have a compact SHACL equivalent; for example, a rule may require agreement across multiple assertions, while an emitted shape currently captures only the presence requirement.

There is currently no general user action that exports the whole ontology, profiles, assertions, or review scope as a standards-complete RDF/JSON-LD package. Treat an external-consumer request as a separate integration requirement.

## 6. Runtime: why SemOS does not use a triple store or OWL reasoner

The live SemOS application uses PostgreSQL, SQL, and Go services. Profile and review rules operate on a frozen, scoped set of facts, terms, assertions, releases, and applicability context.

This is important for completeness and compliance review. If a required fact is absent from the reviewed scope, the system must distinguish between a failed requirement, an inapplicable requirement, and evidence that is insufficient to decide.

An open-world reasoner is not, by itself, the right mechanism for that distinction. SemOS therefore uses explicit scope and completeness declarations with native evaluators. Do not infer that an item is absent merely because it was not found in a partial graph.

There is no supported SPARQL endpoint, production OWL 2 DL reasoner, or triple-store deployment in the current application runtime.

## 7. What users should do in common situations

### “I need standard units and quantity meanings.”

Use the governed QUDT import and confirm that the `quantity` module release is active. Do not create a second local unit vocabulary unless the operator has confirmed that the required concept is not provided by governed content.

### “I found a similar external term.”

Treat it as a candidate mapping. Check the source identifier, definition, scope, language, and relationship strength. Similarity alone is not proof of exact equivalence.

### “I need to validate a SemOS profile outside the application.”

Confirm which profile rules have SHACL emitters and which SemOS semantics they cover. The emitted shape is a projection for interchange; native SQL/Go evaluation remains authoritative for the current application.

### “I need RDF or SPARQL for a new integration.”

This is not an enabled default capability. Define the external consumer, required serialization, profile version, source identifiers, and validation expectations before planning the integration. The database model and release identifiers keep a future projection possible without migrating the operational store.

## 8. Current boundaries and terminology

| Term | Meaning in the current implementation |
|---|---|
| **RDF** | A future interchange/projection target and the graph model used by imported Turtle sources; not the operational database format. |
| **SKOS** | A source of vocabulary and mapping distinctions used by SemOS modeling and terminology governance; not a standalone SKOS server. |
| **QUDT** | A selectively imported external quantity vocabulary stored in the governed `quantity` module. |
| **SHACL** | A shape language supported by profile-rule emitters for future publication; not the current production evaluator. |
| **OWL** | Not used as the production reasoning runtime. |
| **PROF** | Not currently exposed as a user-facing profile publication workflow. |
| **SPARQL / triple store** | Not part of the current runtime. |

The implementation status can change as new consumers appear. Re-check current release and integration documentation before promising standards-based interchange to another system.

## Change Log

| Version | Timestamp | Responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.0 | 2026-08-16T06:18:03-05:00 | Not specified | Initial manual | Converted ADR Section 3.14 into a user-facing guide based on the current ontology, terminology-import, QUDT, profile-rule, and runtime implementation. |
