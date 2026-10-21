---
Date: 2026/10/22
Contributors: ChatGPT
---

There are many openly available hierarchical classification datasets, similar to ICS and CCS. Some are general-purpose taxonomies, while others specialize in scientific disciplines, products, industries, medicine, engineering, or regulatory subjects.

There are three types of categories:

1. Classification systems: Primarily hierarchical categories, like ICS and CCS.
2. Controlled vocabularies and thesauri: Categories with labels, synonyms, definitions, and semantic relationships, often represented in SKOS.
3. Ontologies and knowledge graphs: Richer models containing classes, entities, properties, and typed relationships.

The second type is particularly important for SemOS: it combines category hierarchies with enough semantic information to support category generation, normalization, merging, and mapping.

## 1. Category Datasets

| Dataset                             | Domain                         | Hierarchical     | Downloadable | Format            |
| ----------------------------------- | ------------------------------ | ---------------- | ------------ | ----------------- |
| Wikidata                            | General knowledge              | Yes, graph-based | Yes          | RDF, JSON         |
| MeSH                                | Medicine, biology              | Yes              | Yes          | XML, RDF          |
| AGROVOC                             | Agriculture, food, environment | Yes              | Yes          | RDF, SKOS         |
| EuroVoc                             | Law, policy, industry, science | Yes              | Yes          | RDF, SKOS         |
| UNSPSC                              | Products and services          | Yes              | Restricted   | Licensed datasets |
| NAICS                               | Economic activities            | Yes              | Yes          | CSV, Excel        |
| CPC                                 | Goods and services             | Yes              | Yes          | Excel, CSV        |
| ACM Computing Classification System | Computer science               | Yes              | Yes          | XML, RDF          |
| GACS                                | Agriculture                    | Yes              | Yes          | SKOS/RDF          |
| QUDT                                | Quantities, units, dimensions  | Yes, ontology    | Yes          | RDF, OWL          |

Downloadable does not necessarily mean unrestricted redistribution or modification. Licenses differ, and some classifications have restrictions.

## 2. Additional datasets worth considering

The following are especially relevant if you want to construct a broad, reusable category system rather than classify only standards.

| Dataset  | What it provides                                                                    | Resource                                                                                                                                                                                    |
| -------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AGROVOC  | Multilingual agricultural concepts, labels, definitions, broader/narrower relations | [FAO AGROVOC](https://agrovoc.fao.org/?utm_source=chatgpt.com)                                                                                                                              |
| EuroVoc  | Multilingual concepts covering law, policy, economics, technology, and government   | [Download RDF](https://interoperable-europe.ec.europa.eu/collection/eu-semantic-interoperability-catalogue/solution/eurovoc/distribution/eurovoc-skosrdf/rdf-export?utm_source=chatgpt.com) |
| MeSH     | Medical terminology, hierarchical trees, synonyms, descriptor records               | [Download MeSH](https://www.nlm.nih.gov/databases/download/mesh.html?utm_source=chatgpt.com)                                                                                                |
| ISIC     | International classification of economic activities                                 | [UN classifications](https://unstats.un.org/unsd/classifications/econ/?utm_source=chatgpt.com)                                                                                              |
| CPC      | Hierarchical classification of goods and services, plus correspondence tables       | [Download CPC](https://unstats.un.org/unsd/classifications/Econ/CPC?utm_source=chatgpt.com)                                                                                                 |
| ESCO     | Occupations, skills, qualifications, and their relationships                        | [Download ESCO](https://esco.ec.europa.eu/en/use-esco/download?utm_source=chatgpt.com)                                                                                                      |
| ChEBI    | Chemical entities, names, synonyms, and ontology relationships                      | [ChEBI](https://www.ebi.ac.uk/chebi/?utm_source=chatgpt.com)                                                                                                                                |
| ENVO     | Environment types, habitats, environmental materials                                | [ENVO GitHub](https://github.com/EnvironmentOntology/envo?utm_source=chatgpt.com)                                                                                                           |
| EDAM     | Bioinformatics operations, data types, topics, and formats                          | [EDAM GitHub](https://github.com/edamontology/edamontology?utm_source=chatgpt.com)                                                                                                          |
| Wikidata | Broad concepts and subclass relationships, multilingual labels and aliases          | [Wikidata dumps](https://www.wikidata.org/wiki/Wikidata:Database_download?utm_source=chatgpt.com)                                                                                           |

EuroVoc has an official SKOS/RDF export, while MeSH offers both XML and RDF distributions.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://interoperable-europe.ec.europa.eu\&sz=32)

Interoperable Europe Portal

+1

&#x20;The UN also provides classification files and correspondence tables useful for mapping between taxonomy versions.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://unstats.un.org\&sz=32)

Classifications on economic statistics

+1



## 3. Which datasets are most valuable for SemOS?

Given SemOS focuses on standards, technical knowledge, medical documents, metrics, and product classification, we can prioritize:

ICS + CCS — Primary document classification

Keep these as external reference taxonomies for standards. They provide established subject classifications and metadata compatibility.

EuroVoc — Broad semantic categories

Particularly useful for regulations, policy, economics, environmental protection, and technical subject areas.

MeSH — Medical domain knowledge

Useful for your medical standards corpus, especially concept normalization and synonym resolution.

CPC — Product and service classification

Useful when extracting products, equipment, materials, and service categories from standards.

Wikidata — General concept enrichment

Useful for alternative names, multilingual labels, broader concept discovery, and entity disambiguation. Its graph needs filtering before being used as a clean taxonomy.

## 4. An architectural consideration: Category trees vs. category graphs

### 4.1 Category trees vs. category graphs
A useful category system is not necessarily a tree.

For example, consider Temperature Monitoring Equipment. It could reasonably belong under:

- Medical equipment
- Measurement instruments
- Cold-chain technology
- Environmental monitoring

Rather than forcing it into one parent category, SemOS could support multiple parents, forming a directed acyclic graph (DAG), with cycle detection.

### 4.2 Is-a classification and other relationships
We should distinguish between is-a classification and other relationships such as part-of, used-for, and regulated-by. These should not all become parent-child links.

### 4.3 Stable IDs
For dynamically merging and splitting categories, preserve stable internal IDs and maintain versioned relationships and mappings. SKOS is particularly useful here, but note that `skos:broader` is not automatically equivalent to `rdfs:subClassOf`.

### 4.4 Categories as Knowledge Base
Use existing datasets not only as categories to import, but also as reference 
knowledge for category generation. When SemOS proposes a new category, it can 
first search these vocabularies for an existing equivalent or broader concept, 
then decide whether to reuse, specialize, or create a genuinely new category. 
This reduces duplication and makes the hierarchy more consistent as it grows.