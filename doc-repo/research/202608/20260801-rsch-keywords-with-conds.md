# Keywords with Conditions

Date: 2026/08/01 \
Author: OpenAI

Can BM25 handle conditional keywords?

It is a fundamental limitation of lexical retrieval of not being able to handle conditions. The issue has been discussed decades in the area of information retrieval (IR) research.

1. **BM25 does not solve this problem.** It can alleviate it if enough contextual words exist, but it does not understand that *apple* refers to two different concepts.
2. **The conditional probability intuition is correct.** In fact, many modern retrieval systems (especially hybrid retrieval and LLM-assisted retrieval) are moving toward this idea, although usually not by modifying BM25 itself.

---

## 1. BM25 treats words as independent observations

BM25 is essentially a sophisticated bag-of-words model.

Given a query

```
apple
```

it computes a score approximately like

```
score =
  weight(apple in document)
```

It has **no concept** that

```
apple (fruit)
```

and

```
Apple Inc.
```

are different meanings.

To BM25,

```
Apple released the iPhone.
```

and

```
The apple contains vitamin C.
```

both contain the same token

```
apple
```

(the exact normalization depends on the tokenizer).

## 2. Adding another keyword helps—but only statistically

Suppose the user searches

```
apple company
```

BM25 becomes approximately

```
score =
    weight(apple)
  + weight(company)
```

Now documents like

```
Apple Inc. is a technology company.
```

receive a high score.

But documents like

```
The company grows apples.
```

also contain

```
company
apple
```

Therefore they also receive a non-zero score.

BM25 has no way of expressing

> company modifies apple

Instead it only knows

```
apple exists
company exists
```

Those are different things.

## 3. Why it often appears to work

Large collections exhibit statistical regularities.

For example,

```
Apple Inc.
```

frequently co-occurs with

```
technology
iphone
mac
ios
tim cook
software
```

whereas

```
apple (fruit)
```

co-occurs with

```
fruit
tree
juice
nutrition
orchard
```

Therefore BM25 indirectly distinguishes the meanings through surrounding vocabulary.

This is called **distributional evidence**.

It is not semantic understanding.

## 4. BM25 cannot express conditions

The query below is a semantic constraint:

> Find entries that mention apple as a company.

BM25 cannot represent

```
P(document | apple is company)
```

Instead it computes something closer to

```
P(document | apple, company)
```

where `apple` and `company` are just independent query terms.

Notice the difference: the desired query is

```
apple
subject-to
meaning = company
```

BM25 performs

```
apple AND company
```

Those are not equivalent.

# 5. Information retrieval has studied this problem extensively

This problem is called

* Word Sense Disambiguation (WSD)
* Query Disambiguation
* Entity Linking
* Named Entity Disambiguation

For example

```
Java
```

may mean

* Java language
* Java island
* Java coffee

Likewise

```
Mercury
```

may mean

* planet
* chemical element
* automobile
* Roman god

Pure BM25 cannot distinguish them.

---

# 6. What search engines actually do

Modern search engines rarely feed your raw query directly into BM25.

Instead they perform

```
Query
        │
        ▼
Query Understanding
        │
        ▼
Expanded Query
        │
        ▼
BM25
```

For example

User types

```
apple
```

The search engine may infer

```
Apple Inc.
```

and rewrite internally as

```
apple
iphone
mac
ios
tim cook
```

or

```
apple fruit
nutrition
```

depending on the user's history or other signals.

Google has done this for many years.

# 7. Conditional Probability

Suppose we define

```
Entity:
Apple Inc.
```

with aliases

```
Apple
Apple Computer
AAPL
```

Now the user asks

```
apple
```

The system first resolves

```
apple
```

↓

possible entities

```
Apple Inc.
Apple (fruit)
Apple Records
Apple Bank
```

Now the user selects

```
Apple Inc.
```

The actual retrieval query becomes

```
entity = Apple Inc.
```

This is very different from BM25.

The retrieval engine is no longer matching a word.

It is matching a concept.

This is exactly how entity search systems work.

SemOS already extracts structured artifacts, canonical keywords, aliases, ontology categories, and knowledge objects.

Rather than thinking of a query as

```
keyword
```

we can model it as

```
Canonical Object
```

For example

```
Object
--------
id: company/apple_inc

aliases:
    apple
    apple computer
    aapl

category:
    company
```

Another object

```
id: fruit/apple

aliases:
    apple

category:
    fruit
```

Then

```
apple
```

becomes

```
Resolve aliases
        │
        ▼
2 candidate objects
        │
        ▼
Retrieve by object
```

This is much richer than plain BM25 because the query is grounded in your ontology rather than an isolated token.

# 9. An even more probabilistic interpretation

The idea of conditional probability can be formalized as

```
P(Document | Meaning)
```

instead of

```
P(Document | Word)
```

The retrieval pipeline becomes

```
Word
   │
   ▼
Meaning Inference
   │
   ▼
Canonical Entity
   │
   ▼
Retrieve
```

or mathematically,

```
P(document | word)
```

can be decomposed into

[
P(document \mid word)
=====================

\sum_{m}
P(document \mid m),
P(m \mid word)
]

where (m) ranges over possible meanings (senses) of the word.

For the query "apple":

* (P(\text{Apple Inc.} \mid \text{apple}))
* (P(\text{fruit} \mid \text{apple}))
* (P(\text{Apple Records} \mid \text{apple}))

The system first estimates the probability of each meaning, then retrieves documents associated with that meaning. This decomposition is much closer to how modern semantic search, entity linking, and LLM-assisted retrieval operate than a pure BM25 model.

---

## 10. My recommendation for SemOS

Given your architecture, I would avoid trying to make BM25 itself understand ambiguity. Instead, let BM25 remain what it does best: a fast lexical retriever over normalized text. Build a semantic layer above it:

1. **Alias resolution**: map surface forms like "apple" to one or more canonical entities.
2. **Entity disambiguation**: use query context, surrounding terms, user interaction, or an LLM to estimate the intended entity when multiple candidates exist.
3. **Query rewriting**: translate the resolved entity into a retrieval expression, such as canonical IDs, aliases, categories, and related concepts.
4. **Hybrid retrieval**: execute BM25, vector search, graph traversal, and structured filters using the rewritten query.
5. **Result re-ranking**: score candidates with entity consistency, graph relationships, and semantic similarity.

This keeps BM25 simple and efficient while allowing SemOS to retrieve based on *meaning* rather than just matching words. That layered design also aligns well with your planned keyword alias resolver and ontology-based knowledge model.

