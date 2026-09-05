## 1. Overview
[GLiNER](https://github.com/urchade/GLiNER/blob/main/docs/intro.md?utm_source=chatgpt.com) and [GLiREL](https://github.com/jackboyla/GLiREL?utm_source=chatgpt.com) are **lightweight information-extraction models** designed to do something LLMs are good at—extract arbitrary entities and relationships from text—but with much smaller models and more deterministic, structured outputs.

For something like **SemOS**, they are particularly interesting because they sit between traditional fixed-schema NLP models and full LLM extraction.

### 1.1 GLiNER: arbitrary Named Entity Recognition

**GLiNER = Generalist Model for Named Entity Recognition.**

Traditional NER models are trained with a fixed schema:

```text
PERSON
ORGANIZATION
LOCATION
DATE
```

If you suddenly ask such a model to extract `medical_device`, `measurement`, or `standard`, it generally cannot do so without retraining.

GLiNER instead lets you supply the entity types **at inference time**. For example:

```text
Text:
"The ISO 13485 standard specifies requirements for quality
management systems used by medical device manufacturers."

Entity types:
["standard", "medical device", "organization", "requirement"]
```

Conceptually, GLiNER can return:

```text
ISO 13485
    type: standard

medical device
    type: medical device
```

GLiNERR is not a generative model. It cannot detect entities not in the provided
entity types. The good news is that we do not need to provide a list of 'entities'
but only 'entity types'. 

**Entities and Entity Types**

Entity types identify types of entities, not individual entities. In thea bove example,
['PERSON', 'ORGANIZATION', 'LOCATION', 'DATE'] are entity types. 'Michael' is an entity
of 'PERSON', 'Mary' is also an entity of 'PERSON'. In most cases, a domain should not
have too many entity types but can have unlimited entities.

So it is essentially **zero-shot / open-schema NER**. It uses a relatively small bidirectional Transformer rather than a generative LLM. ([GitHub][1])

That distinction matters. With an LLM you might prompt:

```text
Extract all standards, products, organizations, metrics...
Return JSON.
```

GLiNER turns this into something closer to a discriminative classification problem:

```text
text + candidate labels
          ↓
       GLiNER
          ↓
(span, label, confidence)
```

It is therefore generally cheaper, faster, easier to run locally, and less prone to producing invented entities than generative extraction. The project specifically targets CPU and consumer-hardware deployment and also supports ONNX. ([GitHub][2])

---

### GLiREL: arbitrary Relation Extraction

**GLiREL = Generalist Model for Relation Extraction.**

It applies roughly the same idea to **relationships between entities**.

Suppose GLiNER has already found:

```text
[ISO 13485]        standard
[medical devices]  product
[ISO]              organization
```

You can give GLiREL candidate relationship types such as:

```text
["published by",
 "applies to",
 "supersedes",
 "references",
 "requires"]
```

and it can produce something conceptually like:

```text
ISO 13485
    --published by--> ISO

ISO 13485
    --applies to--> medical devices
```

More formally, it predicts triples:

```text
(head entity, relation, tail entity)
```

The project's example takes already identified entities plus candidate relation labels and scores possible relations between them. ([GitHub][3])

So you can think of the original pair as:

```text
                     document
                        │
                        ▼
                    GLiNER
                        │
                 identify entities
                        │
                        ▼
        ┌───────────────┴──────────────┐
        │                              │
    ISO 13485                   medical devices
        │                              │
        └────────── GLiREL ────────────┘
                        │
                        ▼
             "applies to"
```

This is already very close to a **knowledge-graph extraction pipeline**.

### Why these models are interesting

The important idea isn't merely that GLiNER performs NER and GLiREL performs relation extraction. Traditional models have done those things for decades.

The interesting property is **runtime-defined schemas**.

| Approach            | Entity/relation schema     | Generative? | Typical compute |
| ------------------- | -------------------------- | ----------: | --------------: |
| Traditional NER/RE  | Fixed at training          |          No |             Low |
| **GLiNER / GLiREL** | **Specified at inference** |      **No** |  **Low–medium** |
| LLM extraction      | Specified in prompt        |         Yes |            High |

For example, your SemOS pipeline might define a fairly specialized vocabulary:

```text
Entities:
- standard
- provision
- product
- metric
- unit
- organization
- technical concept
- test method

Relations:
- applies_to
- defines
- measures
- has_unit
- requires
- references
- supersedes
- conflicts_with
```

GLiNER/GLiREL potentially let you change these labels without training a dedicated classifier for every ontology revision.

There is one important 2026 wrinkle: **GLiNER itself has expanded beyond NER**. The current project includes a `RelEx` architecture capable of **joint NER + relation extraction**, explicitly targeting knowledge-graph construction. So today I would not automatically architect a new system as `GLiNER → separate GLiREL`; I would benchmark standalone GLiREL against GLiNER's newer joint relation-extraction models. ([GitHub][4])

For **SemOS specifically**, I think these models are worth investigating as a **first-pass extraction layer before an LLM**: use a small discriminative model to cheaply generate high-recall entity/relation candidates across the corpus, then reserve an LLM for normalization, ambiguity resolution, ontology mapping, causal interpretation, and difficult cases. That could substantially change the cost/determinism tradeoff of the extraction pipeline you've been designing.

[1]: https://github.com/urchade/GLiNER/blob/main/docs/intro.md?utm_source=chatgpt.com "GLiNER/docs/intro.md at main · urchade/GLiNER · GitHub"
[2]: https://github.com/urchade/gliner?ref=www.awesomepython.org&utm_source=chatgpt.com "GitHub - urchade/GLiNER at www.awesomepython.org · GitHub"
[3]: https://github.com/jackboyla/GLiREL/blob/main/quickstart.py?utm_source=chatgpt.com "GLiREL/quickstart.py at main · jackboyla/GLiREL · GitHub"
[4]: https://github.com/urchade/GLiNER/blob/main/README.md?utm_source=chatgpt.com "GLiNER/README.md at main · urchade/GLiNER · GitHub"
