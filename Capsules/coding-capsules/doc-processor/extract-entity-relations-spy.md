# Production Entity and Relation Extraction Without Generative LLMs

Date: 2026-09-04  
Status: Draft for review  
Implementation target: `ChenWeb`

## 1. Summary

Build a production-ready entity and relation extractor as an alternative to the
existing LLM-based processor (Ref [2]). The new extractor will run locally and will not call a
generative LLM or an external model API.

The extractor will use smaller, task-specific language models. These models read text
in both directions and are trained specifically to find entity names and relationships.
They are not chat models and do not generate free-form answers.

The main design decisions are:

- Use a Python service in `ChenWeb/python/extract-entity-relations/` because the mature
  training and inference tools are in Python.
- Keep Go responsible for the existing document-processing workflow, database writes,
  artifact files, status, and indexing.
- Detect the language of each piece of text and route it to the best available model.
- Treat English and Simplified Chinese as first-class supported languages.
- Detect Traditional Chinese separately and route it through a measured Chinese or
  multilingual fallback until it independently qualifies for production support.
- Use a multilingual model as the fallback for other languages and mixed-language text.
- Discover entity mentions from their context. Do not require a master list of every
  entity name in advance.
- Extract the relationship wording from the source first, then map it to a standard
  relationship name when possible.
- Select and promote models using a human-reviewed test collection and a direct
  comparison with the existing extractor.
- Plan for domain-specific training instead of assuming a general model will be good
  enough for all ChenWeb documents.

The previous Go dictionary-and-rules proposal is superseded by this document. A
dictionary may still improve known names, but it is not the primary extraction method.

## 2. What Problem This Solves

The current entity and relation processor uses an LLM. It can recognize names that were
not listed beforehand and can understand many different ways of stating a relationship.
The replacement must preserve as much of that ability as practical while removing the
runtime dependency on generative LLMs.

A dictionary-only extractor cannot meet this goal. There are too many possible people,
organizations, products, systems, standards, materials, locations, and concepts to list
them all. It also cannot reliably understand a new name from the surrounding sentence.

The new extractor therefore learns patterns such as:

- which words form an entity name;
- what kind of entity it is;
- which two entities participate in a stated relationship; and
- which words express that relationship.

For example, it should be able to find a previously unseen service name because of how
the name is used in a sentence, not because that name already exists in a map.

## 3. Meaning of “No LLMs”

This design makes the following distinction:

- **Allowed:** compact, non-generative encoder models trained for entity recognition,
  span classification, relation classification, and language detection.
- **Not allowed:** chat models, instruction-following models, text-generation models,
  prompt-based extraction, or calls to hosted LLM APIs.

The production extractor must not silently fall back to an LLM. During development,
the existing LLM extractor may be run in an isolated benchmark so that its results can
be compared with the replacement. Human-reviewed annotations remain the source of
truth; the LLM output is only another system being measured.

Every third-party model must have its license, source, training-data description, and
known limitations recorded before it can be promoted. Some public extraction models
were trained with synthetic examples originally produced by LLMs. That history must be
visible in the model review. If such training provenance is considered unacceptable,
the model cannot be used even though its runtime is non-generative.

## 4. Goals

- Find as many genuine entity mentions as practical, including names never seen before.
- Extract explicit relationships and their subject and object.
- Approach the existing LLM extractor’s quality on the same human-reviewed documents.
- Support English and Simplified Chinese from the first production release.
- Handle documents that mix Chinese and English.
- Preserve the exact source lines and locations supporting every result.
- Produce accepted entity and relation data compatible with the existing
  `kb.entities`, `kb.relations`, search, and graph workflows, while staging unmapped
  relation candidates separately.
- Run locally on CPU, Apple Silicon, or NVIDIA GPU.
- Make model versions, confidence, language route, and source evidence auditable.
- Support repeated domain-specific training and safe model upgrades.

## 5. Non-Goals

- Perfect extraction of every real-world entity or relation.
- Treating a model prediction as unquestionable truth.
- Using a dictionary as a complete inventory of possible entities.
- Automatically merging similarly named entities into one real-world identity.
- Automatically translating every Chinese entity name into English.
- Publishing unsupported or weakly tested languages as production-quality.
- Replacing the existing search, graph indexing, and relation endpoint-linking systems.

Entity extraction and entity identity are separate problems. This service finds what
the document mentions. The existing keyword and reconciliation systems decide whether
two mentions refer to the same concept.

### Plain-language terms used below

- **Encoder model:** a compact model that reads and classifies text but does not write
  free-form answers.
- **Entity span:** the exact words or characters that name an entity.
- **Model backbone:** the reusable language-understanding part of a model.
- **Task head:** the smaller part trained to perform one job, such as finding entities.
- **Gold test set:** examples reviewed by people and kept unchanged for fair testing.
- **Hard negative:** a convincing-looking example that must not be extracted.
- **MPS:** Apple’s way of running PyTorch work on the Mac GPU.

## 6. Recommended Architecture

```text
ChenWeb Go document processor
        |
        | sends text plus line information
        v
Local Python extraction service
        |
        +-- detect language
        +-- route to English, Chinese, or multilingual models
        +-- find entity mentions
        +-- find relation mentions
        +-- map known relation meanings
        +-- return confidence and exact source locations
        |
        v
Go validation and consolidation
        |
        +-- entity identity/canonicalization
        +-- database and artifact writes
        +-- search and graph indexing
```

The Python service owns model loading and prediction only. It must not read or write
ChenWeb database tables. This keeps the model layer replaceable and leaves the existing
Go workflow as the single owner of stored data.

The service will load models once at startup and reuse them across requests. The Go
processor will send bounded text windows rather than entire large documents. Requests
include the original line numbers and page numbers so returned text locations can be
mapped back without guessing.

## 7. Why a Python Service Is Selected

Go remains the right language for ChenWeb’s orchestration and storage. Python is the
practical choice for the first model service because it has the most mature ecosystem
for training and serving the models under consideration. A future approved model may
be exported to another runtime, but that is an optimization rather than a starting
requirement.

Python provides:

- PyTorch and Hugging Face model support;
- spaCy components when useful;
- existing GLiNER and GLiREL implementations;
- support for Apple Metal, NVIDIA CUDA, and CPU inference;
- established training, evaluation, and model-export tools.

The service will follow the operational style of `ChenWeb/python/pdf-parser`: an
independent Python environment, a `pyproject.toml`, locked dependencies, tests, a
`mise.toml`, a start script, and a README.

Proposed directory:

```text
ChenWeb/python/extract-entity-relations/
├── pyproject.toml
├── uv.lock
├── README.md
├── mise.toml
├── start.sh
├── service.py
├── schemas.py
├── language_router.py
├── entity_extractor.py
├── relation_extractor.py
├── relation_mapper.py
├── model_registry.py
├── models/
│   └── model manifests, not untracked model binaries
├── training/
│   ├── prepare_data.py
│   ├── train_entities.py
│   ├── train_relations.py
│   └── evaluate.py
└── tests/
```

The exact filenames may change during implementation, but the boundaries should
remain: serving, language routing, extraction, relation mapping, training, and
evaluation are separate responsibilities.

## 8. Entity Extraction

### 8.1 Primary method

The primary entity detector is a trained model, not a name map. It examines words in
context and returns:

- the text that names the entity;
- the entity type;
- its exact start and end location;
- a confidence score; and
- the model and language route that produced it.

The detector must support overlapping or nested names where the selected model can
produce them. This matters for names that contain another meaningful name.

“Previously unseen” means a new name that belongs to one of the entity types the model
was asked and trained to recognize. It does not mean that the model can invent an
entirely new type or ontology on its own. For example, a model trained for people,
organizations, software systems, standards, and materials may recognize a new software
system name from context even though that name never appeared in its dictionary.

### 8.2 Optional dictionaries and rules

Known-name dictionaries, aliases, patterns, and suffix rules may be added as a
high-precision aid. They are useful for internal service catalogs, product lists,
standard numbers, chemical identifiers, or other controlled names.

They have three limited jobs:

1. an exact, reviewed dictionary or pattern may recover a known source span that the
   model missed;
2. correct the type of a known entity; or
3. link an observed name to a canonical identity after detection.

They must never be presented as the general solution. A mention that is not in a
dictionary can still be detected by the model. These dictionaries are versioned,
language-scoped, reviewed, and recorded in result provenance when they add or change a
mention.

### 8.3 Entity normalization

Detection happens before normalization. Once a complete mention is found, the Go side
may pass that surface to the existing keyword resolver to connect spelling variants or
aliases to one concept.

The keyword Tier 0–6 ladder must not run on every input token to decide what is an
entity. Its job is identity resolution after extraction. An exact, reviewed extraction
dictionary may add a source mention as described above; fuzzy keyword reconciliation
may only canonicalize a mention already found by the model or exact extraction rule.
It may not manufacture a new mention from similar-looking prose.

## 9. Relation Extraction

Relations use two stages so the system can preserve recall without losing governance.

### 9.1 Stage 1: find what the document says

The relation pipeline receives the detected entities and the surrounding text. It uses
three focused classifiers rather than one free-form generator:

1. A **relationship-word detector** marks the exact source words that express a
   possible relationship. These words are not limited to a registered verb list.
2. An **endpoint classifier** decides which nearby entity is the subject, which is the
   object, or that the text states no relationship between them.
3. A **qualifier classifier** records whether the statement is affirmative, negated,
   uncertain, conditional, or historical. Subject and object direction is owned by the
   endpoint classifier.

It returns:

- the subject entity mention;
- the object entity mention;
- the source words that express the relationship;
- the supporting source lines; and
- a confidence score.

This stage is open-vocabulary with respect to the source wording: the detected words do
not need to exist in a precompiled phrase list. It is not unlimited ontology discovery;
the later mapping stage still uses governed relationship meanings. Only relationships
supported by the text are extracted.

Version 1 promotes only mapped relationships that are affirmative and describe a
current fact. Negated, uncertain, conditional, and historical statements remain in
`kb.relation_candidates` with their qualifiers and evidence; they do not become
canonical graph edges. Supporting qualified graph edges later would require a separate
design so consumers cannot mistake them for current facts.

### 9.2 Stage 2: map to a standard relationship

The extracted wording and its context are then classified against a governed
relationship list. That requested label list is used only here; it does not limit the
relationship-word detector. For example, different English or Chinese phrases may all
mean `depends_on`.

The output keeps both:

- the original words from the document; and
- the normalized relationship key, when mapping succeeds.

An unmapped relationship is retained in `kb.relation_candidates` with its evidence. It
is not silently discarded, and it is not promoted to `kb.relations` or the canonical
graph under a guessed predicate. A mapped relationship is projected into the existing
`kb.relations` shape only when it is also affirmative and current. Reviewed candidates
can later expand the governed relationship vocabulary and supply new training
examples.

### 9.3 Keeping the number of pairs manageable

A paragraph containing many entities creates many possible subject-object pairs. The
service should first consider nearby entities, sentence boundaries, entity types, and
other inexpensive signals. The model then evaluates the plausible pairs. This protects
speed without reducing extraction to a fixed verb list.

The first candidate pass considers entities in the same sentence and the immediately
adjacent sentence. Wider document-level pairs are evaluated only when a non-generative
coreference component links a pronoun or repeated mention to an entity. These cases are
measured separately so same-sentence success cannot hide poor document-level recall.

## 10. Language Detection and Routing

Multilingual support will use detection followed by routing.

### 10.1 Detect language in small sections

Do not assign one language to an entire document and assume every line matches it.
Technical documents often contain Chinese prose, English product names, identifiers,
tables, and citations together.

The router uses document metadata as a hint, then examines each text window. It
returns one of these routes:

- English;
- Simplified Chinese;
- Traditional Chinese;
- mixed Chinese-English;
- another identified language; or
- unknown.

Language detection is recorded with a confidence score. Short identifiers such as
`API`, `M4`, or `GB/T 1234` inherit nearby context rather than being treated as a
standalone language sample.

Routing follows one versioned policy:

1. Clearly English windows use the English route.
2. Clearly Simplified Chinese windows use the Simplified Chinese route.
3. Clearly Traditional Chinese windows use its own qualified model when available;
   otherwise they use the Chinese/multilingual fallback and are marked non-production.
4. Mixed Chinese-English windows use the multilingual route once, rather than running
   two models and silently combining conflicting answers.
5. Low-confidence or unknown windows use the multilingual fallback and retain the
   `unknown` route label. They do not count as supported-language results.

The language detector, thresholds, and route priority are part of the model-policy
version. If two overlapping windows return the same source span and type, Go keeps one
result using this stable priority: qualified language model, mixed-language model,
multilingual fallback, then highest confidence.

### 10.2 Route to the best model

The initial model registry contains:

- an English entity and relation route;
- a Simplified Chinese entity and relation route;
- a multilingual fallback route; and
- a mixed-language route using the multilingual model selected by the versioned model
  policy.

English and Chinese may share the same base model while using separately trained task
heads. They may also become separate models if testing shows that specialization gives
materially better results. The public service response does not change when the model
behind a route changes.

The first production commitment is English plus Simplified Chinese. Traditional
Chinese remains a separately measured route until it passes its own data and quality
gate. Equal numerical quality between English and Chinese is not promised; each must
independently reach its required production floor and remain close to the existing
extractor on the same language.

### 10.3 Chinese-specific behavior

Chinese processing must not assume that spaces separate words. The model’s own
subword tokenizer handles the text, and the service maps predictions back to the exact
original Unicode characters and UTF-8 byte positions.

Chinese training and testing must cover:

- Chinese entity boundaries;
- technical terms and abbreviations;
- Latin product and organization names inside Chinese sentences;
- model numbers and standard identifiers;
- Chinese relationship wording and word order;
- Simplified and Traditional Chinese when both are claimed as supported; and
- mixed Chinese-English sentences.

### 10.4 Other languages

A multilingual model can provide useful fallback results, but fallback does not equal
production support. A language becomes officially supported only after it has its own
human-reviewed test data and passes the same quality gates.

Quality is reported separately for every supported language. A high English score may
not hide weak Chinese performance in a combined average.

## 11. Model Candidates and Selection

Model selection is evidence-driven. We will not build three complete production
systems merely to compare frameworks.

The first benchmark includes:

1. the existing LLM extractor as the current-system comparison;
2. multilingual GLiNER for entity detection;
3. GLiREL as an English governed-relation classification baseline; and
4. one supervised multilingual encoder pipeline, likely using Hugging Face directly or
   through spaCy.

GLiREL does not identify the exact source words expressing a relation, so it cannot
implement the complete open-wording pipeline by itself. It is also not accepted as the
Chinese relation model without Chinese evidence. Its published model and evaluation
are English-oriented. A multilingual relationship-word detector plus an endpoint and
mapping classifier using a backbone such as XLM-RoBERTa is the safer production
candidate.

spaCy and Hugging Face are not automatically separate model approaches. spaCy can use
a Hugging Face transformer underneath. The framework choice should be based on
accuracy, offset handling, training simplicity, export support, and operating cost.

If the initial supervised implementation is limited by spaCy’s abstractions, build a
custom Hugging Face span and relation classifier. Otherwise, avoid maintaining two
versions of the same model family.

Expected model sizes are below one billion parameters. Typical candidates range from
roughly 150 million to 600 million parameters. Models with several billion or tens of
billions of parameters are not part of this design.

## 12. Training Strategy

Domain-specific training is expected, not treated as a last-minute contingency.

### 12.1 Build a trusted data set

Create a human-reviewed collection containing representative ChenWeb documents:

- English documents;
- Chinese documents;
- mixed-language documents;
- different document types and domains;
- easy, difficult, and negative examples; and
- both common and rare entity and relation types.

Annotators mark entity spans, entity types, relation endpoints, original relationship
wording, normalized relationship keys, and source evidence. Written annotation rules
must explain ambiguous cases so different reviewers make consistent decisions.

Training, validation, and final test documents must come from separate source groups.
Near-duplicate pages from the same document family must not appear on both sides of a
split, because that would make results look better than they really are.

Before annotation starts, Phase 1 publishes an evaluation contract. Its initial target
is at least 1,000 entity mentions and 300 positive relation mentions for both English
and Simplified Chinese, plus at least 500 entity mentions and 150 positive relation
mentions for mixed Chinese-English text. Negative, uncertain, conditional, and
historical examples are included in addition. Each business-critical label needs at
least 50 final-test examples or must be reported as insufficiently tested. At least 20%
of the material is independently labeled by two reviewers; disagreements are resolved
before it enters the gold set.

### 12.2 Improve from real errors

After the first model is deployed in shadow mode, prioritize human review of:

- low-confidence predictions;
- disagreements with the existing extractor;
- new document domains;
- new languages;
- entity types with poor recall; and
- common false positives.

These reviewed examples become the next training set. Every training release keeps a
frozen final test set so progress cannot be claimed by repeatedly tuning to the test.

### 12.3 Promote models safely

Each released model has a small model card containing:

- model and tokenizer versions;
- supported languages and domains;
- training-data version;
- license and provenance;
- quality results by language and entity/relation type;
- hardware and speed measurements;
- known weaknesses; and
- checksum and release date.

The model registry points to an immutable approved version. Rollback changes the
registry pointer; it does not require rebuilding the service.

## 13. Evaluation and Acceptance

Human-reviewed annotations are the authority. The existing LLM extractor and each
candidate model run against the same unchanged test documents.

The evaluation reports, in plain terms:

- how many real entities were found;
- how many reported entities were correct;
- whether their boundaries and types were correct;
- how many real relations were found;
- whether the correct subject and object were linked;
- whether the original relationship wording was captured;
- whether normalized relationship mapping was correct;
- performance by language, domain, document type, and label; and
- processing time and memory use.

Formal precision, recall, and F1 scores are included for engineering review, but the
release report must also show concrete missed and incorrect examples.

Before replacing the current extractor, the new system must satisfy every row below on
English, Simplified Chinese, and mixed Chinese-English test sets separately:

| Measure | Initial release gate |
| --- | --- |
| Entity recall | at least 0.85 and no more than 5 percentage points below the existing extractor |
| Entity precision | at least 0.85 and no more than 5 percentage points below the existing extractor |
| Complete relation correctness | F1 at least 0.75 and no more than 5 percentage points below the existing extractor |
| Source-location correctness | at least 0.99 against the human-reviewed source spans |

“Complete relation correctness” requires the correct subject, object, direction, and
governed relationship key together. Raw relationship-word detection and mapping
accuracy are also reported separately so the failing stage is visible.

In addition, the new system must:

- produce stable results for the same model, configuration, and input;
- pass load, restart, timeout, and rollback tests; and
- meet the throughput and memory limits recorded in the Phase 1 evaluation contract.

The test report includes uncertainty ranges. A candidate passes the five-point margin
only when the result is large enough to be meaningful rather than ordinary test-sample
noise. The numerical gates above are initial targets and must be accepted or revised
before model training begins, never weakened after seeing a candidate’s final-test
score.

## 14. Hardware Plan

The service supports three compute routes:

- Apple Metal (`mps`) for the M4 Pro development machine;
- NVIDIA CUDA when a compatible GPU is available; and
- CPU as the universal fallback.

The current M4 Pro Mac mini with 48 GB unified memory is the first development and
benchmark machine. It is expected to handle inference and initial fine-tuning of the
sub-one-billion-parameter candidates, but that is a hypothesis the benchmark must
confirm. No NVIDIA purchase is required before those measurements exist.

If additional training speed is needed, first rent a CUDA machine for a limited run.
An RTX 4090-class 24 GB GPU and an RTX 5090-class 32 GB GPU are the first systems to
measure. Larger workstation or data-center GPUs are considered only if a selected
model cannot meet its memory or throughput target on those systems.

Model promotion records model artifact size, startup time, peak memory, per-window and
per-document latency, throughput, and safe concurrency. CPU and M4 measurements are
required. CUDA measurements are required only if CUDA becomes a production target. A
CPU fallback preserves functionality but is not considered healthy if it misses the
production throughput target.

## 14.1 MacMini

The MacMini with M4 Pro chip:

M4 Pro has a real GPU suitable for ML.
- Apple M4 Pro
- 16-core integrated GPU
- 48 GB unified memory
- Metal 4 support
PyTorch accesses it through Apple’s mps backend rather than NVIDIA CUDA. 
The 48 GB is shared by the CPU, GPU, operating system, and applications, 
so it is not identical to 48 GB of dedicated VRAM—but it provides 
substantial capacity for the sub-1B encoder models we are considering. 
Apple officially supports accelerated PyTorch training and inference 
through Metal/MPS, although it still describes the backend as beta. 
(Ref: Apple MPS documentation).

The Mac should be adequate for:
- Running GLiNER, GLiREL, and BERT-class inference.
- Fine-tuning small and medium encoder models.
- Developing the complete service.
- Running initial comparative benchmarks.
Some operations may be unsupported or slower under MPS and fall back to 
CPU. The Apple Neural Engine is separate; ordinary PyTorch code generally 
uses the GPU through MPS, not the Neural Engine.

**Probably do not need an expensive NVIDIA data-center GPU**

| Hardware	| Memory	| Recommendation |
|-----------|---------|----------------|
| M4 Pro Mac mini	| 48 GB unified	| Start here; likely adequate for development and modest fine-tuning |
| RTX 4090	| 24 GB VRAM	| Sufficient for nearly all models under consideration |
| RTX 5090	| 32 GB VRAM	| Best choice if buying a new dedicated training workstation |
| RTX A6000	| 48 GB VRAM	| Useful for larger batches and professional workloads, but probably unnecessary |
| RTX PRO 6000 Blackwell	| 96 GB VRAM	| Substantial overkill for the proposed models |
| H100/H200/B200	| Large data-center GPUs	| Not justified unless later training becomes much larger or distributed |

The RTX 4090 has 24 GB, while the RTX 5090 has 32 GB. (Ref: NVIDIA RTX 
4090 specifications, Ref: NVIDIA RTX 5090 specifications).

For this project:
- Do not purchase an NVIDIA GPU yet.
- Develop and benchmark on the M4 Pro.
- If CUDA compatibility or training speed becomes a problem, rent a 4090/5090-class cloud GPU for training runs.
- If eventually buying a dedicated machine, a 5090 offers useful 32 GB headroom. A used 4090 may be a better value if 24 GB is enough.
- The RTX PRO 6000 Blackwell’s 96 GB and ECC memory are useful for much larger models, multiple simultaneous models, or specialized production workloads—not our expected single-model training workload. NVIDIA RTX PRO 6000 specifications

## 14.2 The expected models sizes
The expected model sizes are normally less than 1B parameters.
Representative sizes:
- GLiNER small: 166M
- GLiNER medium: 209M
- GLiNER large: 459M
- Typical BERT/RoBERTa/DeBERTa encoders: roughly 100M–500M
- GLiREL model artifact: approximately 1.87 GB, also consistent with a sub-1B encoder-class model

The published GLiNER family ranges from 166M to 459M parameters. GLiNER model card GLiREL’s current large checkpoint is about 1.87 GB on disk. GLiREL model files

We are not proposing multi-billion or 10B+ models. Those would increase hardware costs and move the system closer to the large-model architecture we are explicitly trying to avoid.

Bottom line: your 48 GB M4 Pro is a sensible development and initial training machine for this project. We should benchmark it before considering additional hardware.

## 15. Service Contract

The first implementation uses versioned JSON over local HTTP. The service listens only
on loopback by default. A remote bind requires an explicit configuration plus transport
security and authentication. The service is supervised by the same operational tooling
used for other ChenWeb services.

The Go processor sends:

- a request ID and record ID;
- ordered text lines;
- line and page numbers;
- optional document-language metadata;
- the requested entity-type set and governed relation set; and
- the model-policy version.

The requested entity types guide entity classification. The governed relation set is
used only in relation mapping; it does not limit detection of the original relationship
wording.

The Python service returns entity mentions and relation candidates. Each result includes
the original source text, offsets, source lines, confidence, detected language, model
version, and any normalized type or relationship key.

The original UTF-8 line text is never normalized in place. Source locations use
half-open byte offsets—start included, end excluded—relative to that original line,
together with its line number. Multi-line evidence is a list of such segments. Go
verifies that every returned byte slice equals the returned source surface. Line spans
remain the authoritative location stored in the existing tables; exact offsets and
model-token alignment are retained in provenance. Results from overlapping windows are
deduplicated by record, line, byte range, type, and endpoints before IDs are assigned.

The service exposes simple health and readiness checks. Readiness becomes true only
after every required model is loaded and a small self-test succeeds.

Approved model files are installed before startup and verified by checksum. Production
startup never downloads a newer model from the internet. Request size, window count,
queue depth, concurrency, and timeout limits are configured and returned as clear
overload or validation errors; work is not accepted and then silently dropped.

All responses use a versioned schema. The Go wrapper rejects an unknown schema,
invalid offsets, impossible confidence values, missing relation endpoints, or a model
version different from the one requested.

## 16. Integration With the Existing Processor

Keep the existing logical operations:

- `extract_entity`;
- `extract_relation`; and
- the legacy `extract_entity_relation` compatibility path where still required.

Add a process-wide engine choice:

```text
ENTITY_RELATION_ENGINE=llm
ENTITY_RELATION_ENGINE=encoder_service
```

Only one engine writes the canonical entity and relation results for a record run.
During shadow evaluation, the new service writes to isolated benchmark output rather
than overwriting the LLM results.

Go continues to own:

- chunk and line-file loading;
- request cancellation and timeouts;
- entity consolidation and stable IDs;
- relation endpoint linking;
- database transactions;
- `.entities` and `.relations` artifacts;
- processor status;
- search indexing; and
- graph indexing.

The adapter maps model output into the current row shapes. Model-specific details go
into `ext_info`, including extraction engine, model version, language route, tokenizer
version, training-data version, and confidence details.

For non-English text, `_en` fields are filled only when a governed mapping supplies an
English value. The service does not invent an English translation. A normalized
relation key can still have a stable English label when that label comes from the
governed relation vocabulary.

All raw relation extractions first enter a new `kb.relation_candidates` staging table.
It stores the verbatim relationship words, endpoints, qualifiers, mapping status,
confidence, evidence, language, and model provenance. Only mapped, affirmative,
current candidates that pass validation are projected into the existing `kb.relations`
table and canonical graph. This is an intentional database change and requires a goose
migration during implementation.

## 17. Reliability and Failure Handling

Missing extraction is difficult to notice, so the new engine fails visibly rather than
reporting an empty successful result when its model service is unavailable.

- A service connection failure, unavailable required model, invalid response, or
  unprocessed text window fails the operation.
- A valid model response containing zero mentions is a successful zero-result window.
- Retries are bounded and use the same requested model version.
- A forced rerun keeps the previous good database rows until the replacement result is
  fully validated.
- Database replacement is transactional: either the complete new result is stored or
  the previous result remains.
- Artifact files are replaced atomically after successful validation.
- Cancellation stops queued and active requests promptly.
- The service never changes models silently after an out-of-memory or unsupported-
  device error. Device fallback is allowed only when the model policy explicitly lists
  it, and the resulting route is logged and must still meet its throughput target.

The first release may run one service instance. Before multiple replicas are enabled,
record-level ownership and model-version consistency must be enforced across replicas.

## 18. Logging and Monitoring

Each run records:

- record and request IDs;
- model and training-data versions;
- language route and confidence;
- number of text windows;
- entity and relation counts by type;
- mapped and unmapped relation counts;
- low-confidence and rejected counts;
- processing time and queue time;
- device type and peak memory where available; and
- failures and retry counts.

Routine logs must not contain full document text. The existing database rows and
artifacts retain the source evidence needed for review.

Operational dashboards should highlight sudden changes in result counts, language
distribution, confidence, failures, and processing time. Periodic human sampling is
required because a technically healthy model can still drift in quality when document
content changes.

Initial alerts cover service error rate, queue saturation, model-load failures,
unexpected language-route changes, and large extraction-count changes. The production
owner also owns the review queue for unmapped relations and sets a maximum review age;
otherwise the open-relation stage would accumulate evidence without improving the
governed graph.

## 19. Testing

Testing has four layers.

### 19.1 Service tests

- request and response validation;
- correct language routing;
- English, Chinese, mixed, other, and unknown-language cases;
- Unicode offsets and source-line mapping;
- CPU, MPS, and optional CUDA device selection;
- model loading, readiness, timeout, cancellation, and restart behavior;
- deterministic post-processing; and
- safe handling of zero results and malformed model output.

### 19.2 Extraction tests

- unseen entity names;
- overlapping and nested entities;
- aliases and known-name overrides;
- multiple entities and multiple relations in one sentence;
- negated statements;
- uncertain, conditional, and historical statements that must not become current graph edges;
- entity pairs with no relationship;
- open relationship wording;
- governed relationship mapping;
- Chinese text without spaces;
- mixed Chinese-English technical names;
- overlapping document chunks; and
- cross-sentence examples when that capability is enabled.

### 19.3 Go integration tests

- engine selection;
- service request construction;
- response and offset validation;
- compatibility with current entity and relation rows;
- stable IDs and consolidation;
- transactional replacement;
- artifact creation;
- status reporting; and
- existing search and graph indexing.

### 19.4 Model evaluation

Run the frozen human-reviewed test collection for every candidate and every proposed
model release. Store the detailed results as versioned artifacts so a later release can
be compared with any earlier one.

## 20. Delivery Plan

### Phase 1: define truth before choosing a model

1. Finalize the entity types, relation representation, and annotation guide.
2. Assemble representative English, Chinese, and mixed-language documents.
3. Create and review the first gold test set.
4. Measure the existing extractor on that set.
5. Approve the evaluation contract, model-license policy, annotation privacy rules,
   and ownership of the unmapped-relation review queue.

### Phase 2: build a replaceable model service

1. Create `ChenWeb/python/extract-entity-relations/` with the service contract, model
   registry, language router, tests, and device selection.
2. Add GLiNER as the first entity benchmark.
3. Add GLiREL as the English relation benchmark.
4. Add one supervised multilingual encoder pipeline.
5. Produce comparable quality and performance reports.

### Phase 3: train for ChenWeb documents

1. Select the best starting architecture.
2. Fine-tune entity and relation models with reviewed domain data.
3. Train and evaluate English and Simplified Chinese routes independently.
4. Add mixed-language examples and hard negative cases.
5. Repeat until the quality gate is met or the remaining gap is documented.

### Phase 4: integrate with Go

1. Implement the Go service client and response validation.
2. Reuse the existing consolidation, persistence, artifact, status, and indexing code.
3. Add the governed `kb.relation_candidates` migration and projection step.
4. Add isolated shadow output for side-by-side comparison.
5. Verify failure recovery and stable reruns.

### Phase 5: shadow rollout and promotion

1. Run the encoder service beside the existing extractor without changing canonical
   graph output.
2. Review disagreements and operational measurements.
3. Continue shadow operation for at least 500 representative documents and two weeks,
   including English, Simplified Chinese, and mixed Chinese-English documents.
4. Promote an immutable model bundle only after every required language passes.
5. Switch the engine in a controlled deployment.
6. Keep a quick rollback to the prior engine during the initial observation period.

Rollback is triggered by data-loss errors, invalid source locations, sustained service
errors above 1%, failure to meet the recorded throughput target, or a reviewed quality
sample falling below the release gate. The observation period ends only after two
additional weeks without a rollback trigger.

After stable promotion, the new production path has no LLM call or LLM fallback.

## 21. Main Risks

| Risk | Response |
| --- | --- |
| Chinese quality trails English | separate Chinese data, evaluation, and model route |
| General model misses domain terms | planned domain-specific training and known-name aids |
| High recall creates too many false positives | precision floor, negative examples, confidence calibration |
| Relation pairs grow too quickly | inexpensive pair filtering before model scoring |
| One overall score hides weak areas | report by language, domain, and label |
| A model upgrade silently changes the graph | immutable versions, shadow comparison, controlled promotion |
| Apple MPS lacks an operation | CPU fallback for development or temporary CUDA training |
| Third-party model license or provenance is unsuitable | mandatory model-card and license review |
| Unmapped open relations cannot enter the canonical graph safely | stage them in `kb.relation_candidates` until governed mapping |

## 22. Decisions Still Needed Before Implementation

The architecture is settled, but these details need explicit decisions during Phase 1:

1. The initial entity-type list and which types allow nesting or overlap.
2. The initial governed relation vocabulary.
3. Whether third-party checkpoints trained with LLM-generated synthetic annotations
   are acceptable when production inference itself is non-generative.
4. The exact production latency, throughput, memory, and queue limits.
5. The model-artifact repository, retention policy, and disaster-recovery owner.

These decisions affect training labels and storage, so they must be made before the
gold data set is annotated.

## 23. Knowledge and Documentation Impact

This design changes the prior conclusion that a Go rule engine is sufficient.

Documents that will need updates during implementation:

- `extract-entity-relation-spec.md`: describe the encoder-service engine and new
  provenance rather than an LLM-only processor;
- `+CAPSULE.md`: mark the alternate engine as non-LLM when selected;
- entity/relation implementation and test notes;
- service operations and model-training documentation; and
- the database specification for `kb.relation_candidates`.

The current LLM specification remains accurate for the existing engine until cutover.
It should not be rewritten as if the new service already exists.

## 24. Model Selections
Recommended approach: a pluggable Python inference service with an evidence-based model bake-off.

Three viable approaches:
1. GLiNER + GLiREL
   Encoder-only models supporting label-driven entity and relation extraction without enumerating entity names. Both can be fine-tuned for our domain. This offers the strongest initial open-world baseline, but production maturity must be validated. GLiNER, GLiREL paper
2. Fine-tuned spaCy transformer pipeline
   Use trainable span discovery/classification and a custom relation classifier sharing an encoder. spaCy supports overlapping span classification and transformer-backed components. It is mature operationally, but relation extraction requires custom training and implementation. SpanCategorizer, transformer component
3. Custom Hugging Face entity and relation models
   Maximum control over span detection, pair generation, loss functions, and inference optimization. Models can later be exported to ONNX for efficient local inference. This has the highest development and maintenance cost. ONNX token classification

Recommendation:
- Implement one stable Python service contract independent of model backend.
- Benchmark GLiNER/GLiREL and a fine-tuned spaCy/Hugging Face pipeline.
- Build a representative, human-annotated gold corpus from our documents.
- Compare them with the existing LLM extractor using strict entity-span F1, typed-entity F1, relation F1, end-to-end triple F1, latency, memory, and failure rate.
- Fine-tune the strongest candidate on domain data.
- Consider an ensemble only if it improves recall materially without unacceptable precision or latency loss.
- Require the non-LLM extractor to meet an explicit percentage of the existing extractor’s measured performance before replacing it.
The dictionary, alias, and keyword modules would operate after model extraction for canonicalization and high-precision augmentation—not as the primary entity detector.
Does this model-selection strategy look right? If approved, I’ll next present the service architecture and data flow before rewriting the design document.

A better benchmark plan is:
- Baseline: existing LLM extractor.
- Candidate A: GLiNER + GLiREL.
- Candidate B: one supervised, fine-tuned encoder pipeline, implemented with either spaCy or Hugging Face.
- Candidate C: build a custom Hugging Face pipeline only if spaCy’s abstractions limit accuracy, relation modeling, or deployment.

spaCy and Hugging Face are not entirely separate model families: spaCy can use Hugging Face transformer encoders. We should avoid implementing duplicate pipelines merely to compare frameworks.

**Hugging Face models and GPUs**

Hugging Face models do not strictly require GPUs.
   - Training: a GPU is strongly recommended for practical fine-tuning. CPU training is possible for small models and datasets but may be prohibitively slow.
   - Production inference: CPU is viable for smaller encoder models, especially with batching, ONNX Runtime, quantization, and bounded input windows.
   - High-throughput inference: a GPU will likely be preferable for larger models, long documents, or aggressive latency targets.
   - Relation extraction is potentially more expensive than NER because candidate entity pairs can grow quadratically, so pair pruning is important regardless of hardware.

Make the service device-independent:
- CPU must be supported as the deployment baseline.
- GPU acceleration is optional and configuration-driven.
- Model selection requires CPU and GPU benchmarks covering entity/triple F1, documents per minute, p95 latency, peak memory, and operating cost.
- Hardware is selected from measured workload requirements rather than made a mandatory architectural dependency.

## 24. References

1. [Doc Processor Capsule](+CAPSULE.md)
2. [Existing Entity and Relation Processor Spec](extract-entity-relation-spec.md)
3. [GLiNER multilingual model card](https://huggingface.co/urchade/gliner_multi-v2.1)
4. [GLiREL paper](https://aclanthology.org/2025.naacl-long.418/)
5. [XLM-RoBERTa documentation](https://huggingface.co/docs/transformers/main/model_doc/xlm-roberta)
6. [spaCy SpanCategorizer](https://spacy.io/api/spancategorizer)
7. [spaCy transformer component](https://spacy.io/api/transformer)
8. [Hugging Face ONNX Runtime support](https://huggingface.co/docs/optimum-onnx/en/onnxruntime/package_reference/modeling)
9. [Apple PyTorch Metal acceleration](https://developer.apple.com/metal/pytorch/)

Web sources accessed 2026-09-04.
