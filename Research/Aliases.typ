#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

*Change History*
#table(
  columns: 2,
  align: left,
  [Date], [Remarks],
  [2026/04/23], [Ontology, file name: Ontology.typ],
)

#pagebreak()

#show heading: it => {
  set text(fill: blue) if it.level == 1
  if it.numbering != none {
    counter(heading).display(it.numbering)
    h(0.5em) // Adds a little gap after the number
  }
  it.body
}

#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "Aliases"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

#let frontmatter = (
  created: "2026/07/04",
  logical_name: "Aliases",
  file_id: "2026070401",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/07/04",
  keywords: ["Aliases"],
)

= Aliases

== Alias Datasets
Below are some of the alias datasets (from ChatGPT):
```text
| Dataset                 | Domain            | Alias Types                 | Coverage            |
| ----------------------- | ----------------- | --------------------------- | ------------------- |
| Wikidata                | General knowledge | aliases, alternate names,                         |    
|                         |                   | abbreviations, multilingual | Excellent           |
| DBpedia                 | General knowledge | redirects, alternate labels | Good                |
| Wikipedia Redirects     | General           | redirects, common spellings | Excellent           |
| UMLS                    | Medical           | synonyms, abbreviations     | Excellent (medical) |
| SNOMED CT               | Medical           | preferred terms, synonyms   | Excellent (medical) |
| MeSH                    | Medical           | entry terms                 | Excellent           |
| WordNet                 | English           | synonyms (semantic,         | Good                |
|                         |                   | not aliases)                | Good                |
| GeoNames                | Geographic        | alternate place names       | Excellent           |
| OpenStreetMap/Nominatim | Geographic        | multilingual names          | Good                |
| OpenCorporates          | Companies         | legal names, previous names | Good                |
| VIAF                    | People            | name variants               | Excellent           |
```

=== Wikidata (probably the best general solution)

If you search for

```
IBM
```

you might get

```
International Business Machines
I.B.M.
IBM Corp.
Big Blue
```

Each item has

- label
- aliases
- descriptions
- multilingual aliases

Example:

```
Q37156

Label:
Apple

Aliases:
Apple Inc.
Apple Computer
Apple Computer Inc.
```

or

```
Q95

Label:
Google

Aliases:
Google LLC
Google Inc.
```

Advantages

- huge
- multilingual
- actively maintained
- machine readable

This is an excellent source of common aliases.

Wikipedia can be downloaded, about 150–200 GB compressed for the full JSON dump
and has weekly incremtnal dumps.

We can self-host it.

Options include:

- Blazegraph
- Virtuoso
- GraphDB
- Jena Fuseki

Many organizations simply import the JSON dump into PostgreSQL or another 
database instead of running a SPARQL server.

For SemOS, we would probably extract only:

```
QID
label
aliases
description
instance-of
subclass-of
```

which reduces the size dramatically.

=== Wikipedia Redirects

Wikipedia contains millions of redirects.

Example

```
USA
United States
US
U.S.
U.S.A.
America
```

all redirect to

```
United States
```

Likewise

```
NYC
New York City
New York, NY
```

It can be downloaded (the XML dump).

Extract

```
redirect title
target page
```

Result:

```
USA
→ United States

IBM Corp
→ IBM

COVID19
→ COVID-19
```

This becomes a simple alias table.

=== DBpedia

DBpedia extracts

- redirects
- labels
- alternative names
- disambiguations

For example

```
AI

Artificial intelligence
A.I.
```

Downloadable RDF files. Most people either

- import into Virtuoso
- import into GraphDB

or convert to another format.

Since we already use Wikidata, we would not prioritize DBpedia 
unless you specifically want its ontology.

=== UMLS (Medical)

Very useful for SemOS because you've mentioned your corpus is largely medical standards.

Download is available after free registration and acceptance of the license.

The download includes relational files such as:

```
MRCONSO.RRF
MRREL.RRF
MRSTY.RRF
```

These are straightforward to load into PostgreSQL.

The key table, `MRCONSO`, already contains multiple names for the same concept:

```
CUI

Term

Language

Preferred?

Source
```

This is extremely valuable since SemOS has medical documents.

Searching

```
heart attack
```

returns

```
myocardial infarction
MI
cardiac infarction
acute myocardial infarction
```

All refer to the same concept.

This is much richer than a simple synonym dictionary.

=== SNOMED CT

SNOMED provides

```
Preferred term

Synonyms

Fully specified name
```

Example

```
Hypertension

High blood pressure
HTN
```

=== MeSH

Each descriptor contains

```
Preferred term

Entry terms
```

Example

```
COVID-19

2019 Novel Coronavirus Disease
Coronavirus Disease 2019
COVID19
```

=== WordNet

WordNet is often misunderstood.

It gives semantic synonyms rather than aliases.

Example

```
car

automobile
auto
machine
motorcar
```

These are lexical synonyms, not necessarily names referring to the same entity.

It can be downloaded (tiny). Many libraries embed it directly.

=== GeoNames

For

```
Beijing
```

you get

```
北京
Peking
Pei-ching
```

Likewise

```
Munich

München
```

Useful if processing addresses or locations.

It can be downloaded:

```
allCountries.zip
```

Contains

```
id

name

alternate_names

lat

lon
```

Very easy to import.

== Embedding-Based Alias Search

Embeddings work surprisingly well. For example

```
heart attack
```

is very close to

```
myocardial infarction
```

Likewise

```
IBM
```

is close to

```
International Business Machines
```

However embeddings are not guaranteed to find exact aliases.

For example

```
Apple
```

may retrieve

```
Microsoft
Google
Amazon
```

instead of

```
Apple Inc.
```

because embeddings capture semantic similarity rather than identity.

Therefore embeddings should complement, not replace, an alias dictionary.

=== Alias Tables for Search Systems

Search engines such as Elasticsearch, Apache Solr, and Manticore Search often support synonym or alias dictionaries.

For example:

```
IBM =>
International Business Machines

NYC =>
New York City

HTN =>
Hypertension

MI =>
Myocardial infarction

COVID19 =>
COVID-19
```

At query time,

```
IBM revenue
```

can automatically expand to

```
IBM
International Business Machines
```

improving recall without requiring the user to know the canonical form.

=== SNOMED CT

Distributed as RF2 files. These are plain text files.

Typical deployment:

```
RF2
    Concept
    Description
    Relationship
```

Many hospitals import them into PostgreSQL.

FHIR servers can also expose them.

=== MeSH

Download XML.

Contains

```
Descriptor

Entry Terms

Tree Numbers
```

Very easy to parse.


== API availability

```text
| Dataset   | Good API? | Production-ready? |
| --------- | --------- | ----------------- |
| Wikidata  | Yes       | Yes               |
| DBpedia   | Yes       | Mostly            |
| UMLS      | Yes       | Yes               |
| MeSH      | Yes       | Yes               |
| GeoNames  | Yes       | Yes               |
| Wikipedia | Limited   | Not ideal         |
| SNOMED    | Depends   | Mostly FHIR       |
| WordNet   | No        | Local only        |
```

For large-scale indexing, however, public APIs are generally too slow and may impose rate limits.

== Alias Engine
SemOS would not rely on a single global alias dataset. Instead, it builds a layered alias knowledge base:

1. *General entities:* Use *Wikidata* and *Wikipedia redirects* to normalize 
company names, organizations, products, and common abbreviations.
2. *Medical terminology:* Use *UMLS*, *SNOMED CT*, and *MeSH* to capture clinical synonyms, abbreviations, and preferred terms.
3. *Corpus-derived aliases:* Extract aliases directly from document collection. Standards frequently define terms explicitly, for example:

   - "Artificial Intelligence (AI)"
   - "Time To First Byte (TTFB)"
   - "Large Language Model (LLM)"
   - "International Organization for Standardization (ISO)"
4. *LLM-assisted discovery:* Use an LLM to propose additional candidate aliases from context, then validate them before adding them to your knowledge base. This can uncover organization-specific abbreviations and domain jargon that public datasets do not contain.

This hybrid approach is particularly well-suited to SemOS because it combines 
authoritative external knowledge with aliases that are specific to the 
standards and technical documents in your corpus. It also aligns well with 
existing ontology and artifact extraction pipeline: aliases can become 
first-class knowledge objects linked to metrics, products, provisions, 
organizations, and other extracted entities, rather than being treated 
as simple string substitutions.

SemOS emphasis on BM25 + semantic retrieval + graph traversal, and desire to expose 
knowledge buried in documents, we would build a dedicated *Alias Service* rather 
than treating aliases as simple string lists.

For example:

```
Alias Sources
─────────────
Wikidata
Wikipedia Redirects
UMLS
SNOMED
MeSH
Corpus Extraction
LLM Discovery
Manual Curation
```

↓

```
Normalized Alias Graph

Alias
Canonical Form
Source
Confidence
Language
Entity Type
Relationship Type
Validity
```

↓

```
SemOS APIs

FindAliases(term)

Resolve(term)

Normalize(term)

Canonicalize(term)

SuggestAliases(term)
```

↓

```
RAG / Search / Extraction
```

This fits naturally with the existing ontology-centric approach. Instead of a flat 
alias table, aliases become graph objects with provenance, confidence, language, 
and source metadata. That lets us reason about *why* two terms are considered equivalent, 
prioritize authoritative sources (for example, UMLS over an LLM-generated suggestion 
in the medical domain), and evolve the alias graph over time as your corpus grows. 
This richer model would integrate well with SemOS existing artifact and category 
extraction pipeline.

