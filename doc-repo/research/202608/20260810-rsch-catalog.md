# Catalog Subsystem

Catalog subsystem treats the catalog as an identity layer plus an evidence-backed claim layer, 
not as a table of canonical records that gets repeatedly overwritten.**

Internet datasets bootstrap identity and baseline facts. The SemOS corpus contributes additional 
claims and relationships. Automated reconciliation decides most cases deterministically or probabilistically. LLMs help where semantic reasoning is genuinely needed. Humans handle the 
residual ambiguous cases, but nothing should depend on human review to continue operating.

**Catalog Entity**

A Catalog Entity is a persistent SemOS representation of an identifiable thing for which 
multiple sources may provide identifiers, names, attributes, classifications, and relationships.

Examples include:

* medical device model
* drug ingredient or clinical drug
* chemical substance
* organization
* manufacturer
* standard
* standard edition
* regulation
* software product
* protocol
* material
* organism
* instrument
* measurement method
* database
* dataset

This is intentionally broader than a commercial “product catalog.”

A catalog entry is extensional:

> “Acme X200 is a particular medical-device model.”

rather than intensional:

> “Infusion pump is a class of medical device with these typical properties, specifications, uses, constraints, etc.”

These should therefore remain distinct:

```text
Ontology / Category
       ↑
   instance-of
       |
Catalog Entity
       |
       +---- identifiers
       +---- names / aliases
       +---- attributes
       +---- relations
       +---- claims
       +---- evidence
```

SKOS makes essentially the same conceptual distinction between a concept and its lexical labels,
supporting preferred, alternative and hierarchical relationships such as broader/narrower. ([W3C][1]) 
We would borrow some SKOS semantics, but would **not** force the whole SemOS catalog into SKOS.

## Catalog Entities and Occurrences
Suppose Internet source A says:

```text
Product: ABC-100
Manufacturer: MedCo
Category: Ventilator
Weight: 7.2 kg
```

A SemOS standard says:

```text
The MedCo ABC-100 ventilator has a nominal weight of 7.5 kg.
```

Another source says:

```text
ABC100
Manufacturer: MedCo Corporation
Weight: 7.3 kg
```

A conventional ETL system tries to produce:

```json
{
  "name": "ABC-100",
  "manufacturer": "MedCo",
  "weight": 7.3
}
```

But information has been lost: **why is 7.3 considered correct?**

Instead wewould store:

```text
entity: semos:device/019ab...

claims:

manufacturer = semos:org/MedCo
    source = GUDID
    confidence = 1.0

weight = 7.2 kg
    source = web-catalog-A

weight = 7.5 kg
    source = standard-X, page 84

weight = 7.3 kg
    source = manufacturer-page
```

Then calculate a **canonical projection**:

```text
canonical.weight = 7.3 kg
```

according to a property-specific resolution policy.

So:

```text
       evidence
          ↓
source records → claims → entity
                      ↓
             canonical projection
```

The canonical value is therefore **derived state**, not the truth stored destructively in the database.

This is very close to the reason W3C PROV distinguishes entities, activities and agents: provenance 
lets consumers evaluate reliability and derivation rather than merely seeing the final value. ([W3C][2])

For SemOS, this property is extremely valuable.

## 3. Architecture

The architecture consists of three conceptual layers:

```text
┌──────────────────────────────────────────────────────┐
│ L2  SemOS Catalog                                    │
│                                                      │
│ canonical entities                                   │
│ identities / aliases / relationships / projections   │
└────────────────────────▲─────────────────────────────┘
                         │ reconciliation
┌────────────────────────┴─────────────────────────────┐
│ L1  Evidence + Claims                                │
│                                                      │
│ normalized claims                                    │
│ mappings                                             │
│ provenance                                           │
│ confidence                                           │
│ conflicts                                            │
└──────────────▲────────────────────▲──────────────────┘
               │                    │
        normalize/extract      extract/link
               │                    │
┌──────────────┴─────────┐  ┌──────┴──────────────────┐
│ L0 Internet Sources    │  │ L0 SemOS Corpus         │
│                        │  │                         │
│ APIs                   │  │ standards               │
│ dumps                  │  │ regulations             │
│ JSON-LD/RDF            │  │ technical docs          │
│ CSV/XML                │  │ manuals                 │
│ web pages              │  │ papers/etc.             │
└───────────────────────┘  └──────────────────────────┘
```

**Internet ingestion and corpus enrichment converge into the same claim/evidence layer**.


## Catalog Resources from the Internet

```text
authoritative bulk dataset
        ↓
authoritative API
        ↓
authoritative structured web data
        ↓
high-quality aggregator
        ↓
ordinary webpages
        ↓
LLM extraction from arbitrary text
```

Wikidata provides complete structured dumps and its structured data is CC0. ([Wikidata][3])

For SemOS's medical-heavy corpus, some particularly interesting starting points are:

| Domain            | Possible seed           |
| ----------------- | ----------------------- |
| General entities  | Wikidata                |
| Medical devices   | FDA GUDID / AccessGUDID |
| Drugs             | RxNorm                  |
| Chemicals         | PubChem                 |
| Organisms         | NCBI Taxonomy           |
| Publications      | Crossref                |
| Research datasets | DataCite                |

AccessGUDID is especially interesting because the FDA's GUDID contains 
device-identification information, has APIs, and allows bulk downloads of the 
database. ([AccessGUDID][4])

RxNorm provides normalized clinical-drug names and mappings to multiple pharmacy 
vocabularies, with both downloadable releases and a REST API. ([National Library 
of Medicine][5]) PubChem similarly exposes identifiers, synonyms, properties and 
programmatic PUG-REST access. ([PubChem][6])

NCBI Taxonomy provides persistent taxonomy IDs, names and classifications and 
supports bulk taxonomy data. ([NCBI][7])

### Source Registry

Before importing a single entity, create a catalog-source registry.

```sql
catalog_source
--------------
source_id
name
publisher
source_type
base_url

domain
entity_types[]

access_method
  dump
  api
  sparql
  jsonld
  csv
  scrape

authority_level
license
license_url
redistribution_allowed

update_frequency
last_checked_at
last_successful_sync_at

adapter
adapter_version

trust_profile JSONB
metadata JSONB
```

Explicitly model **authority per property**, rather than simply saying:

```text
FDA trust = 0.99
Wikidata trust = 0.80
```

because authority is contextual.

For example:

```text
GUDID:
    device_identifier       authoritative
    manufacturer            authoritative
    marketing status        authoritative
    chemical composition    weak/not applicable

manufacturer website:
    model number             authoritative
    dimensions              authoritative
    clinical classification medium

Wikidata:
    aliases                  strong
    cross identifiers        useful
    technical specifications variable
```

This will become important during reconciliation.

DCAT is worth borrowing here — not as the schema for individual catalog entities, 
but for describing the **datasets being ingested**. DCAT 3 is explicitly a 
vocabulary for interoperable descriptions of catalogs, datasets, distributions 
and data services. ([W3C][8])

### Preserve the raw source

Never convert:

```text
Internet → canonical catalog
```

directly.

Use:

```text
Internet
   ↓
source snapshot
   ↓
source records
   ↓
normalized claims
```

Such as:

```text
catalog_source_snapshot
-----------------------
snapshot_id
source_id
source_version
retrieved_at
content_hash
adapter_version
storage_uri
status
```

and:

```text
catalog_source_record
---------------------
record_id
snapshot_id
source_key
source_entity_type
raw_data JSONB
raw_hash
```

## Canonical catalog entity

Keep the actual entity small:

```sql
catalog_entity
--------------
entity_id UUID
entity_type
status
created_at
updated_at
```

```text
status =
    active
    deprecated
    merged
    split
    unresolved
```

An entity ID should be SemOS-owned:

```text
semos:catalog:019acd...
```

and **must not be based on the identifier of an external provider**.

Do not use:

```text
entity_id = wikidata:Q1234
```

because Wikidata is merely one assertion about identity.

Instead:

```text
SemOS entity E10027

identifiers:
    wikidata = Q1234
    gudid.di = 00812345678901
    gtin = 00812345678901
```

GS1's GTIN is one example of an identifier namespace for trade items; Schema.org and GS1 both model GTINs explicitly. ([GS1][9])

---

## Identifiers deserve first-class status


```sql
catalog_identifier
------------------
entity_id
namespace
value
normalized_value
identifier_type

source_id
source_record_id

valid_from
valid_to

status
confidence
```

Examples:

```text
doi:10.1000/...
wikidata:Q123
rxnorm:RXCUI-12345
pubchem.cid:2244
ncbi.taxid:9606
gtin:00312345678906
iso:13485
```

And define per namespace:

```text
normalization
uniqueness
case sensitivity
check digit rules
entity type compatibility
version semantics
```

A valid exact identifier match should usually dominate fuzzy matching.

## Entity Granularity

This is an area where many knowledge graphs go wrong.

For example:

```text
ISO 13485
```

might mean:

```text
standard family
ISO 13485:2016 edition
a particular corrected edition
a PDF document representing that edition
```

Those are not the same thing.

Similarly:

```text
Drug:
    ingredient
    ingredient + strength
    clinical drug
    branded drug
    package

Medical device:
    product family
    model
    trade item / GTIN
    device identifier
    physical instance
```

Before building reconciliation rules, define **identity profiles**:

```yaml
entity_type: medical_device_model

identity:
  strong:
    - manufacturer + model_number

  external:
    - gudid_di
    - gtin

  supporting:
    - brand
    - device_category
    - dimensions
```

versus:

```yaml
entity_type: standard_edition

identity:
  strong:
    - issuing_body + standard_number + edition

  supporting:
    - title
    - publication_date
```

This avoids a large class of false merges.

---

## Names and aliases

Will support SKOS's distinction between:

```text
preferred label
alternative label
hidden/search label
```

SKOS explicitly supports preferred and alternative labels, and alternative labels 
naturally cover synonyms and abbreviations. ([W3C][1])

SemOS could extend it:

```sql
catalog_name
------------
entity_id
name
normalized_name
language
script

name_type:
    preferred
    alias
    abbreviation
    acronym
    trade_name
    former_name
    translated_name
    spelling_variant
    search_variant

source_id
confidence
```

This can later plug directly into the keyword-alias resolver architecture you have been designing.

---

##  Claims - the Real Unit of Knowledge

Generic claim structure:

```sql
catalog_claim
-------------
claim_id

subject_entity_id
predicate

object_type
object_value JSONB
object_entity_id

source_type
    internet
    corpus
    inference
    human

source_id
source_record_id
evidence_id

confidence

valid_from
valid_to

observed_at

status
    asserted
    disputed
    superseded
    rejected
```

Example:

```json
{
  "subject": "device:123",
  "predicate": "weight",
  "object": {
    "value": 7.2,
    "unit": "kg"
  },
  "source": "manufacturer-X",
  "confidence": 0.98
}
```

Relationships are just claims where the object is another entity:

```text
ABC-100 --manufactured-by--> MedCo

ABC-100 --classified-as--> ventilator

ABC-100 --successor-of--> ABC-90
```

SemOS might materialize relationships separately for graph traversal, but 
conceptually they remain assertions.

---

## Reconciliation Pipeline

This is the heart of the subsystem.

```text
new source record
       ↓
1 normalization
       ↓
2 deterministic resolution
       ↓
3 candidate generation
       ↓
4 candidate scoring
       ↓
5 adjudication
```

### Stage 1 — Normalize

Cheap, deterministic transformations:

```text
MedCo, Inc.
MEDCO INC
MedCo Incorporated
```

might produce:

```text
medco inc
```

but **do not throw away the originals**.

Normalize:

* Unicode
* punctuation
* whitespace
* casing
* units
* known identifier syntax
* dates
* manufacturer suffixes
* language/script

---

### Deterministic resolution first

Resolve without LLM whenever possible.

For example:

```text
same valid GTIN
    → exact match

same RxCUI
    → exact match

manufacturer ID + identical model
    → very strong match

same DOI
    → exact match
```

This stage should probably resolve a very large portion of high-quality structured sources.

It should be cheap, fast and reproducible.

## Candidate Generation

Candidate generation should be broad. Anything unresolved enters **candidate retrieval**.

For example:

```text
query:
    "Philips IntelliVue MX450"
```

candidate generation could use:

```text
exact aliases
+
trigram
+
BM25
+
identifier fragments
+
category restrictions
+
manufacturer restrictions
+
embeddings
```

## Candidate Scoring 
Candidate scoring should use evidence, not just string similarity. Suppose:

```text
New record:
MedCo X100 portable ventilator
```

Candidates:

```text
E1: MedCo X100 ventilator
E2: MedCo X100 monitor
E3: MegaMed X100 ventilator
```

Calculate features:

```text
name_similarity
manufacturer_match
model_number_match
identifier_match
category_match
attribute_compatibility
geographic_match
temporal_match
relationship_compatibility
```

Then:

```text
P(same_entity | evidence)
```

A transparent weighted scorer works:

```text
model number exact              +0.30
manufacturer exact              +0.25
name similarity                 +0.15
category match                  +0.10
identifier exact                +1.00
major attribute contradiction   -0.50
manufacturer contradiction      -0.70
```

The major advantage is debuggability.

---

## The LLM

Use LLMs after candidate generation:

```text
record R

possible identities:
    E17
    E92
    E105

evidence:
    ...
```

Ask:

```text
Determine whether R refers to E17, E92, E105, or none. Identify supporting and contradicting evidence. Do not infer identity merely from similar wording.
```


Have it return:

```json
{
  "decision": "E17",
  "confidence": 0.91,
  "supporting_evidence": [...],
  "contradictions": [...],
  "reason": "..."
}
```

This should be relatively cheap and more reliable.


## Human Involvement 
Human involvement can be important, but optional.
Mechanisms should be planted to flag human involvement.

We may define thresholds:

```text
score >= 0.98
    → automatically resolve

0.80 <= score < 0.98
    → LLM adjudication

0.55 <= score < 0.80
    → unresolved / optional human review

score < 0.55
    → create new entity
```

Most importantly:

```text
unresolved ≠ pipeline failure
```

A record can remain:

```text
resolution_state = ambiguous
```

and still exist in the knowledge base.

Future data may resolve it automatically.

The system should never force a match. This rule is critical.

The possible reconciliation outcomes should be:

```text
MATCH
NEW_ENTITY
AMBIGUOUS
CONFLICT
```

not merely:

```text
MATCH / NO MATCH
```

Sometimes SemOS should explicitly say:

```text
possible:
   E123: 0.62
   E981: 0.58

state = ambiguous
```

and carry on.

That uncertainty is knowledge.

---

# 19. Store mappings themselves

A useful model comes from SSSOM, the Simple Standard for Sharing Ontology Mappings. SSSOM treats a mapping as an assertion with metadata including its justification, confidence and provenance. ([Mapping Commons][10])

I'd borrow that idea:

```sql
catalog_mapping
---------------
source_record_id
entity_id

mapping_type:
    exact_identifier
    exact_key
    lexical
    structural
    semantic
    manual

confidence
justification
resolver
resolver_version
status
created_at
```

This makes reconciliation explainable.

## Corpus Enrichment

Once the Internet bootstrap exists, the interesting SemOS-specific work begins.

For each catalog entity:

```text
Catalog Entity
      ↓
construct search profile
      ↓
search SemOS corpus
      ↓
find mentions
      ↓
resolve mention → entity
      ↓
extract claims
      ↓
attach evidence
```

Example search profile:

```json
{
  "entity": "ABC-100",
  "names": [
    "ABC-100",
    "ABC100"
  ],
  "manufacturer": [
    "MedCo",
    "MedCo Corporation"
  ],
  "identifiers": [
    "008123456..."
  ],
  "categories": [
    "ventilator"
  ]
}
```

That gives SemOS many retrieval handles.

---

## Enrichment should be property-directed

Don't simply ask an LLM:

> “Tell me everything this document says about ABC-100.”

Instead catalog profiles define interesting properties:

```yaml
medical_device:
  properties:
    - manufacturer
    - intended_use
    - indications
    - contraindications
    - dimensions
    - weight
    - operating_temperature
    - accuracy
    - compatible_accessories
    - regulatory_class
    - standards_conformance
```

Your existing **category objects** can actually supply this information.

For example:

```text
Category:
    pulse oximeter

possible_attributes:
    measurement_range
    spo2_accuracy
    pulse_rate_range
    operating_temperature
    display_type
    alarm_support
```

Then when SemOS encounters:

```text
Acme PX200
```

it already knows **which facts are worth looking for**.

This creates a powerful feedback loop:

```text
Category ontology
       ↓
expected properties
       ↓
catalog extraction
       ↓
catalog entities
       ↓
better category knowledge
```

That is one of the strongest reasons to keep catalogs and categories separate but connected.

---

# 22. Evidence should point all the way into the corpus

For a SemOS-derived claim, store something like:

```json
{
  "document_id": "...",
  "artifact_id": "...",
  "page": 37,
  "line_start": 883,
  "line_end": 886,
  "quote_hash": "...",
  "extractor": "catalog-property-extractor-v3",
  "model": "...",
  "extracted_at": "..."
}
```

Ideally:

```text
entity
  ↓
claim
  ↓
evidence
  ↓
document location
```

Then an LLM can retrieve:

> ABC-100 operating temperature = 5–40°C

and immediately inspect the supporting source.

---

# 23. Conflict resolution should be claim-specific

This is where I would avoid a common mistake:

```text
trusted source wins
```

Instead define property policies.

Example:

```yaml
property: manufacturer
resolution:
  order:
    - official_regulatory_registry
    - manufacturer
    - curated_reference_database
    - corpus
    - general_web
```

Different property:

```yaml
property: performance_under_load
resolution:
  prefer:
    - independent_test
    - technical_standard
    - peer_reviewed_study
    - manufacturer
```

Another:

```yaml
property: common_name
resolution:
  prefer:
    - corpus_frequency
    - curated_terminology
```

Canonicalization is therefore:

```text
canonical_value =
    resolver(
        predicate,
        competing claims,
        provenance,
        recency,
        authority,
        confidence,
        consistency
    )
```

not:

```text
canonical_value = latest_value
```

---

# 24. Some conflicts shouldn't be resolved

Consider:

```text
Source A:
operating temperature = 0–40°C

Source B:
operating temperature = 5–45°C
```

They might actually refer to:

```text
different revisions
different markets
different configurations
different measurement methods
```

So first ask:

> Are these actually competing claims?

Claims should support qualifiers:

```json
{
  "value": [0, 40],
  "unit": "C",
  "qualifiers": {
    "model_revision": "2",
    "market": "US"
  }
}
```

This is another reason a flat catalog table eventually becomes painful.

---

# 25. Temporal knowledge needs to be built in from day one

Distinguish:

```text
observed_at
valid_from
valid_to
```

Example:

```text
Manufacturer name:
MedCo Ltd
valid 2005–2022

MedCo Health Inc
valid 2022–
```

Both are true.

Likewise:

```text
standard edition
product status
regulatory classification
ownership
brand name
```

can change.

Internet synchronization should therefore **add new evidence and close validity ranges**, not blindly overwrite old values.

---

# 26. Canonical projection

Applications still need a convenient record.

So build:

```text
catalog_entity_profile
```

perhaps as a materialized projection:

```json
{
  "id": "semos:...",
  "type": "medical_device",
  "name": "ABC-100",
  "aliases": [...],
  "manufacturer": {...},
  "identifiers": {...},
  "categories": [...],
  "attributes": {...},
  "relations": [...],

  "_quality": {
    "completeness": 0.87,
    "conflicts": 2,
    "unresolved_claims": 1
  }
}
```

Applications normally query this.

When they need reasoning:

```text
GET entity/:id/claims
GET entity/:id/evidence
GET entity/:id/conflicts
```

This gives you both:

```text
easy consumption
+
deep explainability
```

---

# 27. Validation profiles

I would attach a schema/profile to each catalog entity type:

```yaml
medical_device:
  required:
    - name

  recommended:
    - manufacturer
    - model

  identifiers:
    - gtin
    - gudid_di

  attributes:
    weight:
      type: quantity

    intended_use:
      type: text

    manufacturer:
      type: entity_ref
      target: organization
```

SHACL offers a useful conceptual precedent here: it defines reusable shapes containing cardinality, datatype and other constraints for validating structured graphs. ([W3C][11])

You don't need RDF or SHACL itself. A SemOS-native profile system may be simpler.

---

# 28. Search indexing

Because catalog data will often be used for resolution, I would build multiple projections.

### Exact identifier index

```text
namespace + normalized identifier → entity
```

Extremely fast and high precision.

### Lexical index

```text
preferred names
aliases
abbreviations
model numbers
manufacturer
categories
```

BM25/trigram.

### Semantic index

Embeddings for:

```text
name
description
category context
functional description
```

### Graph index

Useful relations:

```text
manufacturer
parent product
category
successor
component
standard
related drug
```

This matches your SemOS architecture well:

```text
exact IDs
+
BM25
+
semantic retrieval
+
graph traversal
```

rather than trying to make a single retrieval mechanism solve identity.

---

# 29. Catalog exploration becomes very useful for LLMs

Eventually the LLM-facing filesystem might expose:

```text
/catalog/
    medical-devices/
        ventilators/
            medco/
                abc-100/
                    profile.md
                    identifiers.json
                    claims.json
                    relations.json
                    evidence/
```

But I would treat this as a **virtual projection**, not physical storage.

For example:

```text
/catalog/by-id/gudid/0081234...
/catalog/by-name/abc-100
/catalog/by-category/ventilator
/catalog/by-manufacturer/medco
```

all resolve to the same underlying entity.

That fits particularly well with SemOS's path-oriented exploration model.

---

# 30. Internet enrichment itself can become iterative

Once the catalog exists, Internet collection should stop being:

```text
crawl Internet → import everything
```

and become:

```text
known entity
   ↓
detect missing information
   ↓
find targeted source
   ↓
retrieve evidence
   ↓
extract claims
```

For example:

```text
ABC-100

known:
✓ manufacturer
✓ category
✓ identifiers
✓ dimensions

missing:
? operating range
? successor
? discontinued date
```

SemOS can specifically seek those gaps.

This is considerably more efficient.

---

# 31. I would build an explicit Quality/Knowledge State

For every entity:

```json
{
  "identity_confidence": 0.99,
  "completeness": 0.72,
  "source_count": 6,
  "corpus_document_count": 14,
  "conflicting_claim_count": 3,
  "ambiguous_mapping_count": 1,
  "last_verified": "..."
}
```

At a claim level:

```text
SUPPORTED
SINGLE_SOURCE
CONFLICTED
OUTDATED
INFERRED
AMBIGUOUS
```

This makes it possible for an LLM to distinguish:

> “SemOS knows the weight.”

from:

> “SemOS found three incompatible values for the weight.”

That distinction is critical for trustworthy reasoning.

---

# 32. Human review becomes an "ambiguity queue"

Instead of putting humans in the pipeline:

```text
pipeline → human → pipeline
```

make review asynchronous:

```text
pipeline
   |
   +---- resolved → catalog
   |
   +---- uncertain → catalog + ambiguity queue
```

Cases could be prioritized by:

```text
ambiguity × usage frequency × importance
```

For example:

```text
0.95 identity ambiguity
but entity never used
→ low priority

0.65 ambiguity
entity occurs in 18,000 documents
→ high priority
```

A human decision then becomes another provenance-backed mapping assertion—not a magical database edit.

---

# 33. Let later evidence automatically revisit ambiguity

This is important.

Suppose today:

```text
Record R

E1 = 0.67
E2 = 0.64
```

SemOS leaves it unresolved.

Next month a document arrives containing:

```text
ABC-100, GTIN 123456...
```

and E1 has that GTIN.

The reconciliation scheduler should now automatically reconsider R:

```text
R → E1 = 1.00
```

So ambiguity should be **eventually resolvable knowledge state**.

---

# 34. Suggested database model

I would probably start with approximately these tables:

```text
kb.catalog_sources

kb.catalog_snapshots
kb.catalog_source_records

kb.catalog_entities
kb.catalog_entity_types

kb.catalog_identifiers
kb.catalog_names

kb.catalog_claims
kb.catalog_relations
kb.catalog_evidence

kb.catalog_mappings

kb.catalog_conflicts
kb.catalog_review_cases
```

Plus perhaps:

```text
kb.catalog_entity_profiles
kb.catalog_property_definitions
kb.catalog_resolution_policies
```

I would resist prematurely creating separate tables such as:

```text
medical_devices
drugs
chemicals
organizations
standards
```

unless query volume eventually demands typed physical projections.

Use:

```text
generic core
+
type profiles
+
materialized projections
```

first.

---

# 35. Proposed end-to-end pipeline

Putting everything together:

```text
                        INTERNET
                            │
                ┌───────────┴───────────┐
                │ Source Registry       │
                │ license / authority   │
                └───────────┬───────────┘
                            │
                        harvest
                            │
                    Raw Snapshots
                            │
                    Source Records
                            │
                       normalize
                            │
               ┌────────────┴────────────┐
               │                         │
       deterministic match        candidate search
               │                         │
               │                    BM25 / trigram
               │                    embedding
               │                    graph
               │                         │
               └────────────┬────────────┘
                            │
                       adjudicate
                     rules → LLM
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
       MATCH            NEW ENTITY         AMBIGUOUS
         │                  │                  │
         └──────────────────┴──────────┬───────┘
                                      │
                               Catalog Identity
                                      │
                             SemOS corpus search
                                      │
                               entity mentions
                                      │
                              claim extraction
                                      │
                         Evidence-backed Claims
                                      │
                        conflict / consistency
                                      │
                            canonical projection
                                      │
              ┌───────────────────────┴────────────┐
              │                                    │
        LLM / SemOS search                 optional humans
                                             ambiguity queue
```

---

# 36. Standards I would borrow from—but not necessarily implement

There is a surprisingly good set of established ideas here.

I would borrow:

* **DCAT:** source/dataset/distribution metadata rather than catalog entity representation. DCAT 3 is specifically intended for interoperable web data catalogs. ([W3C][8])
* **SKOS:** preferred labels, alternative labels and conceptual hierarchy. ([W3C][1])
* **PROV-O:** explicit provenance and derivation. ([W3C][2])
* **SSSOM:** mapping assertion + justification + confidence + provenance. ([Mapping Commons][10])
* **SHACL:** type-specific validation profiles and constraints. ([W3C][11])
* **OpenRefine Reconciliation API:** the separation between candidate matching/reconciliation and the underlying database is worth studying. OpenRefine defines reconciliation as matching records to external entities and explicitly supports candidate-oriented reconciliation. ([OpenRefine][12])

But I would **not make RDF a prerequisite**.

SemOS can implement these semantics naturally in PostgreSQL/JSONB and expose RDF later if interoperability requires it.

---

# 37. A particularly important consequence for SemOS

I think this catalog can become more than another dataset.

Today a normal RAG request roughly looks like:

```text
query
  ↓
documents/chunks
  ↓
answer
```

Once Catalog exists:

```text
query
  ↓
identify entities
  ↓
Catalog
  ├── aliases
  ├── identifiers
  ├── categories
  ├── relations
  └── known attributes
        ↓
form richer investigative searches
        ↓
SemOS corpus
```

For example:

```text
"requirements applying to ABC-100"
```

may expand through the catalog:

```text
ABC-100
→ manufacturer MedCo
→ category infusion pump
→ FDA class II
→ aliases ABC100 / Model X100
→ conforms-to IEC 60601 family
```

Those become **search pivots**, rather than merely facts to print in an answer.

This directly supports the “candidate discovery → investigative exploration” model we discussed recently.

---

# 38. My recommended implementation sequence

I would **not** start with the LLM enrichment part.

I would implement the subsystem in roughly this order:

1. **Entity model + identity profiles.** Establish the difference between entity types such as organization, product family, product model, device identifier, standard and edition.
2. **Source registry + snapshots + raw records.** Make ingestion reproducible and license-aware.
3. **Identifiers + aliases.** These provide the strongest immediate resolution capability.
4. **Deterministic reconciliation.** External identifier, source key and strong compound-key matching.
5. **Candidate search.** Trigram/BM25 first; embeddings where they actually add value.
6. **Claim + evidence model.** Do this before corpus enrichment.
7. **Canonical projection.** Make catalogs convenient for downstream consumers.
8. **Corpus entity linking and claim extraction.**
9. **LLM adjudication of ambiguous matches/conflicting claims.**
10. **Optional human ambiguity queue.**
11. **Feedback loop that re-evaluates old ambiguous mappings as new evidence arrives.**

That produces useful functionality very early without committing SemOS to expensive LLM-based processing.

---

## The design principle I would use

The entire subsystem can be summarized by one invariant:

> **SemOS owns identities; sources own assertions.**

An external catalog does not become SemOS truth. A document does not become SemOS truth. An LLM does not become SemOS truth. A human correction does not even erase previous truth.

They all contribute **evidence-backed assertions about persistent SemOS entities**.

From those assertions, SemOS computes its current best view.

That gives you four properties that are difficult to retrofit later: **provenance, conflict tolerance, incremental enrichment, and reversible reconciliation**. And those properties are especially valuable in SemOS because the catalog is not merely intended for human browsing—it can become the entity/identity substrate that BM25, semantic retrieval, graph traversal, alias resolution, corpus extraction, and LLM reasoning all share.

[1]: https://www.w3.org/TR/skos-reference/?utm_source=chatgpt.com "SKOS Simple Knowledge Organization System Reference"
[2]: https://www.w3.org/TR/prov-o/?utm_source=chatgpt.com "PROV-O: The PROV Ontology"
[3]: https://www.wikidata.org/wiki/Wikidata%3ADatabase_download?utm_source=chatgpt.com "Wikidata:Database download"
[4]: https://accessgudid.nlm.nih.gov/resources/developers/device_lookup_api?utm_source=chatgpt.com "Device Lookup API - AccessGUDID - NIH"
[5]: https://www.nlm.nih.gov/research/umls/rxnorm/index.html?utm_source=chatgpt.com "RxNorm - National Library of Medicine - NIH"
[6]: https://pubchem.ncbi.nlm.nih.gov/docs/pug-rest?utm_source=chatgpt.com "PUG REST - PubChem - NIH"
[7]: https://www.ncbi.nlm.nih.gov/guide/taxonomy/?utm_source=chatgpt.com "Taxonomy - Site Guide - NCBI - NIH"
[8]: https://www.w3.org/TR/vocab-dcat-3/?utm_source=chatgpt.com "Data Catalog Vocabulary (DCAT) - Version 3"
[9]: https://www.gs1.org/gs1-web-vocabulary?utm_source=chatgpt.com "GS1 Web Vocabulary"
[10]: https://mapping-commons.github.io/sssom/dev/?utm_source=chatgpt.com "A Simple Standard for Sharing Ontology Mappings (SSSOM)"
[11]: https://www.w3.org/TR/shacl/?utm_source=chatgpt.com "Shapes Constraint Language (SHACL)"
[12]: https://openrefine.org/docs/technical-reference/reconciliation-api?utm_source=chatgpt.com "Reconciliation API"
