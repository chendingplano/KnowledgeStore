# Research - Resources for Keyword Module

Date: 2026/08/05

**UMLS is arguably the most successful example of a much broader class of resources**: **domain semantic knowledge systems**. Every mature discipline has attempted something similar, although few are as comprehensive as UMLS.

A useful way to classify them is by what they unify.

| Type                  | Purpose                        | Examples            |
| --------------------- | ------------------------------ | ------------------- |
| Controlled vocabulary | Standardize names              | AGROVOC, GEMET      |
| Taxonomy              | Hierarchical classification    | ACM CCS, MSC        |
| Ontology              | Rich semantics and relations   | Gene Ontology, FIBO |
| Knowledge graph       | Entities + relations           | Wikidata, DBpedia   |
| Terminology system    | Concepts + synonyms + mappings | UMLS, RxNorm        |
| Authority file        | Canonical names                | VIAF, ORCID         |

Below are some of the major examples.

## Life sciences

Besides UMLS, biology probably has the richest ecosystem.

* Gene Ontology

  * genes
  * biological processes
  * molecular functions
  * cellular components

* ChEBI

  * chemicals
  * metabolites

* NCBI Taxonomy

  * organisms

* UniProt

  * proteins

These are all linked together.

## Agriculture

AGROVOC

Maintained by the Food and Agriculture Organization.

Contains

* crops
* pests
* fertilizers
* diseases
* geography
* food
* forestry
* fisheries

Very similar in spirit to UMLS.

## Environment

GEMET

Covers

* pollution
* climate
* biodiversity
* ecosystems
* sustainability

## Chemistry

There isn't one giant UMLS-like resource, but several complementary ones.

Examples

* ChEBI
* PubChem
* CAS Registry

## Finance

Finance has multiple standards instead of one unified terminology.

Examples

* FIBO
* LEI
* FIX

FIBO is probably the closest to UMLS because it defines concepts and relationships rather than only identifiers.

## Geography

Several global resources exist.

Examples

* GeoNames
* OpenStreetMap
* Getty Thesaurus of Geographic Names

## Computer science

Instead of one terminology system, computer science has several specialized ones.

Examples

* ACM Computing Classification System
* DBpedia
* Wikidata

Programming languages themselves also have standardized specifications and registries.

## Library science

Libraries have been solving terminology problems for decades.

Examples

* Library of Congress Subject Headings
* Getty Art & Architecture Thesaurus
* VIAF

These work much like UMLS for books, people, and cultural heritage.

## Engineering

Engineering is much more fragmented.

Examples include

* ISO terminology databases
* IEC Electropedia
* buildingSMART dictionaries
* industrial product ontologies

Unlike medicine, there is no universally adopted "Engineering UMLS."

## Cross-domain resources

Several systems attempt to unify concepts across *all* domains.

### Wikidata

Probably the closest thing to a universal semantic graph.

Each entity has

* an identifier
* aliases
* multilingual names
* relationships
* external identifiers

Example

```
Q12136
Myocardial infarction

aliases:
- Heart attack
- MI
- Cardiac infarction

linked to:
UMLS
SNOMED
ICD
MeSH
Wikipedia
...
```

### Schema.org

A lightweight ontology used by search engines.

### DBpedia

Extracts structured knowledge from Wikipedia.

## Conclusion

These resources are particularly relevant and important to the Keyword model, 
though some are for ontology, categories, not specific to the Keyword model. 
If we extend the concept of 'Keyword' to 'Resources', the content provided 
in this document are 'Resources', some resources are for the Keyword module,
while others are more at the semantic layer. The ontology subsystem should
clearly separate 'Resources' and 'Mechanisms'. 

They illustrate different layers of semantic normalization. UMLS itself can be 
viewed as a combination of several components:

* **Canonical concepts**: each concept has a stable identifier (CUI).
* **Lexical layer**: synonyms, abbreviations, acronyms, and multilingual names all map to the same concept.
* **Semantic layer**: concepts are assigned semantic types (e.g., Disease, Drug, Procedure).
* **Relationship layer**: concepts are connected through typed relations.
* **Crosswalk layer**: concepts are mapped to external vocabularies such as SNOMED CT, ICD, and LOINC.

domain-independent semantic normalization framework**: instead of being specific to medicine, it could 
support arbitrary domains by allowing pluggable vocabularies, ontologies, and crosswalks. Such a 
framework would combine canonical concepts, aliases, semantic types, relationships, and external 
mappings into a unified model, effectively serving as a "UMLS for any domain."
