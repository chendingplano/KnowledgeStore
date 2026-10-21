---
Date: 2026/10/23
Contributors: ChatGPT, Chen Ding
---

# Overview

A Standards Document Model defines the attributes, structure, semantics, and relationships of a standards document, such as ISO, IEC, ASTM, IEEE, ANSI, or GB/T standards.

Standard Document Model captures not only bibliographic metadata (title, authors, publication date), but also the characteristics that distinguish standards from ordinary documents: standard identifiers, issuing organizations, classifications, editions, normative status, applicability, provisions, and relationships to other standards.

The model should distinguish between document-level attributes and the knowledge artifacts extracted from the document.

## 1. Proposed document model

The following is a comprehensive model. Attributes are grouped by purpose, and most should be optional 
because different standards organizations publish different metadata.

### 1.1 Identification

| Attribute         | Description                     | Example                                   |
| ----------------- | ------------------------------- | ----------------------------------------- |
| `document_id`     | Internal unique identifier      | UUID                                      |
| `document_type`   | Document type                   | standard                                  |
| `standard_number` | Official standard identifier    | ISO 9001                                  |
| `designation`     | Full designation including year | ISO 9001:2015                             |
| `title`           | Official document title         | Quality management systems — Requirements |
| `subtitle`        | Additional title                | Optional                                  |
| `short_title`     | Abbreviated title               | QMS Requirements                          |
| `language`        | Document language(s)            | en, zh                                    |
| `doi`             | Digital Object Identifier       | Optional                                  |
| `official_url`    | Official publication URL        | URL                                       |
| `isbn`            | ISBN, if assigned               | Optional                                  |
| `identifiers`     | Alternative identifiers         | National adoption identifiers             |

Important distinction: `standard_number` identifies a standard across editions, while `designation` typically identifies a particular edition.

For example, ISO 9001 and ISO 9001:2015 should not be treated as identical identifiers.

### 1.2 Organizations and contributors

| Attribute                 | Description                                |
| ------------------------- | ------------------------------------------ |
| `issuing_organization`    | Organization publishing the standard       |
| `developing_organization` | Organization responsible for developing it |
| `technical_committee`     | Responsible technical committee            |
| `subcommittee`            | Responsible subcommittee                   |
| `working_group`           | Responsible working group                  |
| `authors`                 | Named individual authors, if any           |
| `editors`                 | Editors, if identified                     |
| `contributors`            | Other contributors                         |
| `adopting_organization`   | Organization adopting another standard     |

Unlike academic papers, standards typically identify responsible organizations and committees rather than individual authors.

These fields should ideally reference normalized organization entities instead of storing only organization names.

### 1.3 Publication and lifecycle

| Attribute           | Description                                     |
| ------------------- | ----------------------------------------------- |
| `publication_date`  | Official publication date                       |
| `edition`           | Edition number                                  |
| `version`           | Version or revision identifier                  |
| `revision_date`     | Date of revision                                |
| `effective_date`    | Date requirements take effect, where applicable |
| `withdrawal_date`   | Date withdrawn                                  |
| `status`            | Published, withdrawn, superseded, draft, etc.   |
| `development_stage` | Draft, committee draft, final draft, etc.       |
| `previous_edition`  | Previous edition                                |
| `next_edition`      | Subsequent edition                              |
| `amendments`        | Published amendments                            |
| `corrigenda`        | Published technical corrections                 |
| `review_date`       | Latest periodic review date                     |
| `confirmation_date` | Date reaffirmed or confirmed                    |

`status` and `development_stage` should be modeled separately. For example, a published standard can be active or withdrawn, while a draft may be at a particular development stage.

Also, the lifecycle status of a standard can change without changing the original document.

### 1.4 Classification and subject

| Attribute                  | Description                                | Example                            |
| -------------------------- | ------------------------------------------ | ---------------------------------- |
| `ics_codes`                | International Classification for Standards | 03.120.10                          |
| `ccs_codes`                | Chinese Classification for Standards       | Optional                           |
| `national_classifications` | Other national classification codes        | Optional                           |
| `subject_areas`            | General subject categories                 | Quality management                 |
| `topics`                   | Topics covered by the standard             | Quality assurance, process control |
| `keywords`                 | Normalized search keywords                 | quality_management                 |
| `industry_sectors`         | Relevant industries                        | Manufacturing, services            |
| `products`                 | Products addressed by the standard         | Medical devices                    |
| `processes`                | Processes addressed                        | Quality management                 |
| `technologies`             | Technologies addressed                     | Optional                           |

SemOS distinguishes official classifications (ICS, CCS) from SemOS-generated semantic categories, topics, and keywords.

Official classifications represent the publisher's or classification system's organization of knowledge. Generated categories represent SemOS's interpretation of the document.

### 1.5 Scope and applicability

These are especially important for standards.

| Attribute               | Description                                                       |
| ----------------------- | ----------------------------------------------------------------- |
| `scope`                 | Official scope statement                                          |
| `purpose`               | Intended purpose of the standard                                  |
| `objectives`            | Primary objectives                                                |
| `applicability`         | Situations in which the standard applies                          |
| `exclusions`            | Explicit exclusions                                               |
| `target_audience`       | Intended users                                                    |
| `geographic_scope`      | International, regional, national, etc.                           |
| `jurisdictions`         | Jurisdictions where it is applicable or adopted                   |
| `regulated_entities`    | Organizations or entities subject to requirements                 |
| `conformity_assessment` | Relevant testing, inspection, certification or assessment methods |

An important distinction is that a standard's geographic origin does not necessarily determine its legal applicability.

For example, an ISO standard is international in origin, but its requirements do not automatically become legally mandatory in every country.

### 1.6 Normative characteristics

| Attribute                | Description                                                     |
| ------------------------ | --------------------------------------------------------------- |
| `standard_type`          | Terminology, specification, test method, code of practice, etc. |
| `normative_character`    | Requirements, recommendations, guidance, or mixed               |
| `conformance_model`      | How conformity is determined                                    |
| `conformance_subjects`   | Products, processes, organizations, systems, etc.               |
| `normative_references`   | Documents incorporated as normative references                  |
| `informative_references` | Non-normative supporting references                             |
| `normative_sections`     | Sections containing normative content                           |
| `informative_sections`   | Informative sections or annexes                                 |
| `definitions`            | Terms and definitions introduced or adopted                     |
| `requirements`           | Extracted mandatory provisions                                  |
| `recommendations`        | Extracted recommended provisions                                |

Note that `normative_character` does not mean legal enforceability. A standard may contain normative requirements while remaining voluntary unless a law, regulation, contract, or other authority makes compliance obligatory.

### 1.7 Document structure

| Attribute           | Description                       |
| ------------------- | --------------------------------- |
| `abstract`          | Official abstract or summary      |
| `foreword`          | Foreword                          |
| `introduction`      | Introduction                      |
| `table_of_contents` | Structural outline                |
| `sections`          | Chapters, clauses, and subclauses |
| `annexes`           | Normative and informative annexes |
| `bibliography`      | Bibliographic references          |
| `figures`           | Figures and diagrams              |
| `tables`            | Tables                            |
| `formulas`          | Mathematical formulas             |
| `page_count`        | Number of pages                   |
| `section_count`     | Number of sections                |

These attributes describe the physical and logical structure of the standard.

For SemOS, sections, tables, formulas, and figures should have their own identifiers and source locations to support precise citation and extraction.

### 1.8 Relationships

Standards have rich relationships with other standards and documents.

| Relationship               | Meaning                                              |
| -------------------------- | ---------------------------------------------------- |
| `revises`                  | Revises a previous edition                           |
| `replaced_by`              | Replaced by another standard                         |
| `amends`                   | Modifies another standard                            |
| `corrects`                 | Corrects errors in another publication               |
| `adopts`                   | Adopts an international or regional standard         |
| `equivalent_to`            | Equivalent under defined adoption criteria           |
| `normatively_references`   | Cites a document normatively                         |
| `informatively_references` | Cites a document informatively                       |
| `part_of`                  | Belongs to a multipart standards series              |
| `supplements`              | Supplements another standard                         |
| `conflicts_with`           | Has potentially conflicting requirements             |
| `implemented_by`           | Implemented by a specification, procedure, or policy |
| `cited_by_regulation`      | Referenced by a legal or regulatory instrument       |

These are typed relationships between documents or standard editions, rather than simple string arrays.

Some relationships are official publication facts, while others, such as `conflicts_with`, may be SemOS-inferred relationships that require supporting evidence.

### 1.9 Document provenance and processing

These are operational metadata for SemOS rather than properties of the published standard.

| Attribute             | Description                                   |
| --------------------- | --------------------------------------------- |
| `source_url`          | Location from which the document was obtained |
| `source_file`         | Original file path                            |
| `file_format`         | PDF, DOCX, HTML, XML, etc.                    |
| `file_hash`           | Content checksum                              |
| `ingestion_date`      | Date imported into SemOS                      |
| `extraction_method`   | Parser or extraction pipeline                 |
| `extraction_version`  | Extraction software or model version          |
| `processing_status`   | Pending, processed, failed, etc.              |
| `metadata_confidence` | Confidence in extracted metadata              |
| `provenance`          | Source evidence for extracted attributes      |

This distinction prevents document facts from becoming entangled with ingestion and processing state.

## 2. Recommended JSON representation

For implementation, use a compact document-level schema and store complex collections, such as provisions, metrics, terms, and references, as separately managed artifacts.

```

{
  "document_type": "standard",
  "document_id": "uuid",

  "identification": {
    "standard_number": "ISO 9001",
    "designation": "ISO 9001:2015",
    "title": "Quality management systems — Requirements",
    "subtitle": null,
    "language": ["en"],
    "identifiers": [],
    "official_url": null
  },

  "organizations": {
    "issuing_organization": "ISO",
    "developing_organization": null,
    "technical_committee": "ISO/TC 176",
    "subcommittee": "ISO/TC 176/SC 2",
    "working_group": null,
    "authors": []
  },

  "publication": {
    "publication_date": "2015-09",
    "edition": 5,
    "status": "published",
    "lifecycle_status": "superseded",
    "effective_date": null,
    "withdrawal_date": null,
    "review_date": null
  },

  "classification": {
    "ics_codes": ["03.120.10"],
    "ccs_codes": [],
    "subject_areas": ["quality_management"],
    "topics": [],
    "keywords": [],
    "industry_sectors": [],
    "products": [],
    "processes": []
  },

  "scope": {
    "scope_text": null,
    "purpose": null,
    "applicability": [],
    "exclusions": [],
    "target_audience": [],
    "geographic_scope": "international",
    "jurisdictions": []
  },

  "normative": {
    "standard_type": "requirements",
    "normative_character": "requirements",
    "conformance_subjects": ["organization"],
    "normative_references": [],
    "informative_references": []
  },

  "structure": {
    "abstract": null,
    "sections": [],
    "annexes": [],
    "tables": [],
    "figures": [],
    "formulas": []
  },

  "relationships": [],

  "artifacts": {
    "provisions": [],
    "metrics": [],
    "terms": [],
    "definitions": [],
    "references": []
  },

  "provenance": {
    "source_url": null,
    "source_file": null,
    "file_hash": null,
    "ingestion_date": null,
    "extraction_version": null
  }
}

```

Illustrative record using ISO 9001:2015. Null and empty fields indicate information not populated in this example. The lifecycle status is illustrative of the edition's status as of October 2026 and should be verified against the publisher's live catalog.

## 3. Design recommendations for SemOS

**Principle 1**

Distinguish metadata from extracted knowledge. A standard's title, designation, publication date, and issuing organization are metadata. Its requirements, definitions, metrics, and procedures are knowledge artifacts. The document model can reference these artifacts without embedding all their contents.

**Principle 2**

Preserve evidence and provenance. For extracted or inferred fields such as applicability, subject areas, and conflicts, record the originating document location, extraction method, and confidence. This makes metadata auditable.

**Principle 3**

Support multiple values and classifications. A standard may have several ICS codes, multiple national adoption identifiers, several topics, and multiple relationships. Avoid assuming one-to-one mappings where the domain permits one-to-many relationships.

**Principle 4**

Distinguish official facts from SemOS-generated interpretations. For example, `ics_codes` may come directly from the official catalog, while `topics` and `keywords` may be generated by an LLM. Both are useful, but their provenance and authority differ.

## 4. Ontology

In Mesh (refer to topic-ontology-categories-MeSH.md), ontology is organized around 
descriptors, qualifiers, concepts, terms.
A document is a descriptor. Its attributes are modeled as aspects. A standard may have multiple
concepts. A concept can be described by multiple terms. Relations are also formally defined.

| Name          | Ontology Entity |
| ------------- | --------------- |
| Document      | descriptor      |
| Attributes    | qualifier       |
| Artifacts     | descriptor      |
| Topics        | concept         |
| Relations     | relation        |
|

Treat the Standards Document Model primarily as an identity, metadata, classification, and relationship model, with links to independently extracted knowledge artifacts. This will make it reusable across standards organizations, compatible with SemOS's existing extraction pipeline, and extensible to other document types such as regulations, technical specifications, and scientific papers.