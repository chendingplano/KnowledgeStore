--- 
Date: 2026/11/02
Contributors: ChatGPT, Chen Ding
---

SWRL (Semantic Web Rule Language) is a rule language designed to extend OWL with IF–THEN logical rules.

OWL is primarily used to define classes, properties, and logical constraints. SWRL adds the ability to express rules that derive new facts from existing facts.

## 1. A simple example

Suppose we have the following knowledge:

```
ex:John ex:worksFor ex:Google .
ex:Google ex:locatedIn ex:USA .
```

We want to derive:

> If a person works for an organization, and that organization is located in a country, then the person works in that country.

In SWRL:

```
worksFor(?person, ?org) ^
locatedIn(?org, ?country)
    -> worksIn(?person, ?country)
```

Here:

- `?person`, `?org`, `?country` are variables.
- `^` means logical AND.
- `->` means implication (IF–THEN).
- The left side is the rule body (conditions).
- The right side is the rule head (conclusion).

Given the two facts, a SWRL reasoner can infer:

```
ex:John ex:worksIn ex:USA .
```

## 2. How SWRL differs from OWL

| Feature                           | OWL                   | SWRL                                       |
| --------------------------------- | --------------------- | ------------------------------------------ |
| Define classes and properties     | Yes                   | Uses OWL definitions                       |
| Subclass relationships            | Yes                   | Can reference them                         |
| Domain/range inference            | Yes                   | Can express similar implications           |
| Property chains                   | Yes, OWL 2            | Yes, with rules                            |
| General conjunctive IF–THEN rules | Limited               | Yes                                        |
| Numeric comparisons               | Limited               | Yes, through built-ins                     |
| Arithmetic calculations           | Limited               | Yes, through built-ins                     |
| Decidability                      | OWL 2 DL is decidable | Unrestricted SWRL is generally undecidable |

SWRL is not a replacement for OWL. It is intended to work with OWL ontologies.

## 3. SWRL with numeric comparisons

Consider a technical standard:

> If a device operates above 100°C and contains pressurized fluid, it requires safety certification R17.

A SWRL rule might be:

```
Device(?d) ^
operatingTemperature(?d, ?temp) ^
swrlb:greaterThan(?temp, 100) ^
containsPressurizedFluid(?d, true)
    -> requiresCertification(?d, R17)
```

Given:

```
Device(DeviceA)
operatingTemperature(DeviceA, 120)
containsPressurizedFluid(DeviceA, true)
```

The reasoner derives:

```
requiresCertification(DeviceA, R17)
```

`swrlb:greaterThan` is a SWRL built-in function for numeric comparison. SWRL also provides built-ins for arithmetic, strings, dates, and other operations, although implementation support varies.

## 4. How SWRL reasoning works

OWL ontology: Classes, properties, axioms
SWRL rules: Conditions and conclusions
  => Knowledge base: Individuals, facts, relationships
  => OWL + SWRL reasoner: Apply axioms and rules to derive logical consequences
  => Inferred facts: New class memberships and relationships

A reasoner repeatedly applies applicable rules and ontology axioms until no additional facts can be derived, or until its execution strategy reaches another stopping condition.

Not every OWL reasoner supports SWRL. Commonly used tools include Protégé with SWRLTab and SWRL-capable reasoning integrations such as Drools-based engines. Support for particular SWRL constructs and OWL profiles must be checked.

## 5. An important limitation: SWRL uses the open-world assumption

Like OWL, SWRL generally operates under the open-world assumption.

This means that the absence of a fact does not imply the fact is false.

Suppose we have:

```
Device(DeviceA)
operatingTemperature(DeviceA, 120)
```

But no information about whether `DeviceA` contains pressurized fluid.

The rule cannot conclude that certification R17 is required. However, it also cannot conclude that R17 is not required.

This is important for compliance systems, where missing information must often be treated explicitly as an incomplete assessment.

Also, SWRL is primarily a monotonic inference language: adding knowledge does not normally invalidate previously entailed conclusions. It is not naturally suited to rules involving default negation, exceptions, or changing operational state.

## 6. SWRL versus Datalog

SWRL and Datalog have similar-looking rule syntax:

SWRL

```
worksFor(?p, ?o) ^
locatedIn(?o, ?c)
    -> worksIn(?p, ?c)
```

Datalog

```
worksIn(P, C) :-
    worksFor(P, O),
    locatedIn(O, C).
```

Their practical differences are significant:

| Aspect                      | SWRL                                             | Datalog                                                               |
| --------------------------- | ------------------------------------------------ | --------------------------------------------------------------------- |
| Primary purpose             | Extend OWL reasoning                             | Rule-based logical inference                                          |
| Integration with OWL        | Native design goal                               | Requires integration or translation                                   |
| Open-world semantics        | Generally yes                                    | Typically closed-world for database-style evaluation                  |
| Negation                    | No general negation-as-failure                   | Supported by many variants                                            |
| Recursive rules             | Supported, with restrictions depending on engine | Core strength                                                         |
| Large-scale data processing | Depends heavily on implementation                | Often efficient                                                       |
| Termination                 | Not guaranteed in unrestricted OWL + SWRL        | Guaranteed for finite function-free Datalog under standard evaluation |

## 7. Which is more suitable for SemOS?

For a knowledge system processing standards, regulations, and technical specifications, I would distinguish three use cases:

- OWL: Define the meaning of entities, categories, properties, and their logical relationships.
- SWRL: Derive facts using rules that operate directly over OWL individuals and properties.
- Datalog or a production rule engine: Execute potentially large collections of operational, compliance, and analytical rules.

SWRL is particularly attractive when you already have an OWL ontology and need additional logical inference capabilities.

However, if the objective is to extract rules from technical standards using LLMs and execute them deterministically, I would evaluate Datalog before committing to SWRL. It often offers a simpler operational model, especially for recursive queries and large structured datasets.

One caveat is that many regulatory requirements involve exceptions, time-dependent conditions, obligations, and missing evidence. Neither basic OWL nor basic SWRL fully addresses all of these requirements without additional modeling or execution mechanisms.

In summary: OWL defines formal knowledge semantics; SWRL adds rule-based inference over that knowledge. Together, they enable deterministic logical conclusions from structured facts—provided the facts and rules are correctly represented and the reasoning engine supports the required constructs.

## 8. Applications of OWL, SWRL and Datalog

SemOS will have a Reasoning Engine, which supports OWL, SWRL and Datalog. 

- Derive facts from the knowledge base
- Build a Factbase, a database for facts
- Build a Rulebase, a database for rules
- Search facts
- Search rules
- Detect conflict facts, rules
- Q/A Engine

### 8.1 Q/A Engine

Given a query, LLM derives rules. For each rule, if the rule holds
in the knowledge base, then we can derive facts the query needs.

Query:
```text
Which country does John work in?
```

the LLM derives the following rule:
```
isPerson(?p) ^
worksFor(?p, ?o) ^
locatedIn(?o, ?c)
  -> worksIn(?p, ?c)
```

If the three conditions hold in the knowledge base:
```text
isPerson("John")
worksFor("John", "Google")
locatedIn("Google", "US")
```

then we can derive: John works in US.

Build an all-inclusive rulebase is impractical, but for specific
applications or features, it can be very useful. This is especially
important in tech, standards, documentation, specification, laws
and regulations, etc.
