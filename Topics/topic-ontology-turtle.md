---
Date: 2026/10/21
Contributor: ChatGPT
---

# Overview
Turtle (Terse RDF Triple Language) is a human-readable syntax for representing RDF (Resource Description Framework) data. It is widely used in knowledge graphs, ontologies, and Semantic Web technologies such as RDF, RDFS, OWL, and SKOS.

Turtle files typically use the `.ttl` extension.

Turtle is not a separate data model. It is a serialization format for RDF, much like JSON is a serialization format for structured data.

## 1. The basic concept: RDF triples

RDF represents knowledge using triples:

$$(\text{Subject},\ \text{Predicate},\ \text{Object})$$

For example:

> Alice works for Acme Corporation.

This becomes:

```
@prefix ex: <http://example.org/> .

ex:Alice ex:worksFor ex:Acme .
```

Here:

- `ex:Alice` is the subject (an entity).
- `ex:worksFor` is the predicate (a relationship).
- `ex:Acme` is the object (another entity).
- `.` terminates the statement.

## 2. Turtle syntax features

Turtle offers several shortcuts that make RDF more readable.

### 2.1 Prefixes

Instead of repeating long URIs, Turtle allows namespace prefixes:

```
@prefix ex: <http://example.org/> .
@prefix schema: <https://schema.org/> .

ex:Alice schema:name "Alice" .
```

Here, `ex:Alice` expands to `http://example.org/Alice`.

### 2.2 Multiple properties of the same subject

Use a semicolon (`;`) to separate predicates:

```
ex:Alice
    schema:name "Alice" ;
    schema:age 30 ;
    schema:worksFor ex:Acme .
```

This represents three triples.

### 2.3 Multiple objects of the same predicate

Use a comma (`,`) to separate objects:

```
ex:Alice
    schema:knows ex:Bob, ex:Charlie, ex:David .
```

This represents three `schema:knows` triples.

### 2.4 Types and classes

The keyword `a` is shorthand for `rdf:type`:

```
ex:Alice a schema:Person .
ex:Acme a schema:Organization .
```

### 2.5 Literals and data types

Turtle supports typed values and language tags:

```
ex:Alice
    schema:name "Alice"@en ;
    schema:age 30 ;
    schema:birthDate "1990-05-15"^^<http://www.w3.org/2001/XMLSchema#date> .
```

### 2.6 Blank nodes

Blank nodes represent entities without explicitly assigned identifiers:

```
ex:Alice schema:address [
    schema:addressLocality "Dallas" ;
    schema:addressCountry "US"
] .
```

The address is represented as an anonymous RDF node.

## 3. Turtle and OWL

Turtle is particularly important because OWL ontologies are frequently written in Turtle syntax.

For example, consider an ontology defining employees and organizations:

```
@prefix ex: <http://example.org/> .
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

# Define classes
ex:Person a owl:Class .
ex:Employee a owl:Class .
ex:Organization a owl:Class .

# Employee is a subclass of Person
ex:Employee rdfs:subClassOf ex:Person .

# Define a relationship
ex:worksFor a owl:ObjectProperty ;
    rdfs:domain ex:Employee ;
    rdfs:range ex:Organization .

# Define instances
ex:Alice a ex:Employee ;
    ex:worksFor ex:Acme .

ex:Acme a ex:Organization .
```

This ontology expresses more than simple relationships. It also defines logical semantics.

For example, an OWL reasoner can infer that:

- Alice is a `Person`, because every `Employee` is a `Person`.
- The subject of `worksFor` is an `Employee`.
- The object of `worksFor` is an `Organization`.

Importantly, `rdfs:domain` and `rdfs:range` are inference rules, not database validation constraints.

## 4. Turtle vs. JSON vs. JSON-LD

| Feature              | Turtle             | JSON                     | JSON-LD                       |
| -------------------- | ------------------ | ------------------------ | ----------------------------- |
| Primary purpose      | RDF representation | General data interchange | RDF representation using JSON |
| Native triples       | Yes                | No                       | Yes                           |
| Graph relationships  | Native             | Application-defined      | Native                        |
| Ontology support     | Yes                | Not inherently           | Yes                           |
| Human readability    | High               | High                     | Moderate–high                 |
| SPARQL compatibility | Yes                | Requires conversion      | Yes                           |

Turtle and JSON-LD can represent the same RDF graph, even though their syntax differs.

## 5. How Turtle relates to SemOS

For your SemOS knowledge base, Turtle could serve as a standard interchange format for your ontology and knowledge graph.

For example, suppose SemOS extracts knowledge from technical standards:

```
@prefix semos: <https://semos.example/ontology/> .
@prefix kb: <https://semos.example/kb/> .

kb:ISO12345 a semos:Standard ;
    semos:definesMetric kb:TemperatureAccuracy ;
    semos:specifiesRequirement kb:REQ001 .

kb:TemperatureAccuracy a semos:Metric ;
    semos:unit "°C" .

kb:REQ001 a semos:Requirement ;
    semos:appliesTo kb:DataLogger .
```

This structure allows you to model standards, metrics, requirements, products, and their relationships.

However, you do not need to store your knowledge graph in Turtle. You could keep your entities and relationships in PostgreSQL or your existing file-based knowledge base, then export them as Turtle when interoperability with RDF/OWL tools is useful.

The important distinction is:

- RDF defines the graph data model.
- Turtle defines how that graph is written as text.
- RDFS/OWL define vocabulary and logical semantics.
- SHACL defines constraints for validating RDF graphs.
- SPARQL provides a query language for RDF graphs.

For SemOS, I would consider RDF/OWL concepts for ontology design, but treat Turtle as an optional serialization format rather than a required storage architecture.&#x20;
