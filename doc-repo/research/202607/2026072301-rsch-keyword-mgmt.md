# Proposed module: **Keyword Identity and Alias Resolver**

The module should not be modeled as a simple dictionary:

```text
variant → canonical string
```

It should be modeled as a **concept-oriented terminology system**:

```text
surface form → meaning/concept → preferred term
```

That distinction matters because the same string can denote multiple concepts:

```text
APC
├── activated protein C
├── antigen-presenting cell
├── adenomatous polyposis coli
└── asynchronous procedure call
```

Therefore, a keyword alone sometimes cannot be resolved safely. The resolver should return either:

1. one concept when the mapping is unambiguous;
2. several candidate concepts when the term is polysemous;
3. an unresolved result when evidence is insufficient.

This follows the general pattern used by concept-oriented terminology systems such as UMLS, where synonymous names are grouped under stable concept identifiers rather than merely replacing strings. UMLS also keeps separate identifiers for distinct strings, even when the strings ultimately belong to the same concept. ([uts.nlm.nih.gov][1])

---

## 1. Recommended conceptual model

Use four principal objects:

```text
Concept
  ├── Preferred term
  ├── Variant terms
  ├── Meanings and scope
  └── Relations to other concepts

Term
  ├── Original text
  ├── Normalized forms
  ├── Language
  └── Term type

Term assertion
  ├── Term refers to concept
  ├── Source and evidence
  ├── Confidence
  └── Status

Observation
  ├── Term appeared in artifact/document
  ├── Local context
  ├── Domain
  └── Frequency
```

This resembles SKOS’s separation between concepts, preferred labels, alternative labels, and hidden labels. SKOS is intentionally designed for thesauri, controlled vocabularies, taxonomies, and similar knowledge-organization systems. ([W3C][2])

### Concept

A concept represents one meaning, not one spelling.

```json
{
  "concept_id": "kwc_01J...",
  "preferred_term": "retrieval-augmented generation",
  "language": "en",
  "domain": "artificial intelligence",
  "concept_type": "method",
  "definition": "A method that retrieves external information to support generation.",
  "status": "active"
}
```

The `concept_id` must be immutable. The preferred term may change without changing the concept’s identity.

### Term

A term is an observed lexical form:

```json
{
  "term_id": "kwt_01J...",
  "text": "RAG",
  "language": "en",
  "term_type": "acronym",
  "normalized_text": "rag",
  "script": "Latn"
}
```

Different punctuation, casing, spacing, or Unicode representations may be separate raw terms while sharing one normalized lookup key.

### Term assertion

The assertion links a term to a concept:

```json
{
  "term_id": "kwt_rag",
  "concept_id": "kwc_retrieval_augmented_generation",
  "relation": "acronym_of",
  "confidence": 0.998,
  "status": "approved",
  "source": "document_explicit_definition"
}
```

Do not place `concept_id` directly on the term as a mandatory one-to-one relationship. A term such as `RAG` may map to multiple concepts.

### Observation

Each time a term is extracted from a document, preserve its context:

```json
{
  "observation_id": "kwo_01J...",
  "term_id": "kwt_rag",
  "artifact_id": "document-123",
  "context": "The RAG pipeline retrieves passages before generation.",
  "domain": "artificial intelligence",
  "section_path": ["Architecture", "Retrieval"],
  "count": 1
}
```

Observations provide the evidence needed during reconciliation and later context-aware resolution.

---

# 2. Important distinction: normalization is not alias resolution

The system should have two separate layers.

## Layer A: deterministic lexical normalization

This handles superficial differences without an LLM:

```text
PostgreSQL       → postgresql
postgre-sql      → postgre sql
ＲＡＧ            → rag
retrieval‐augmented generation
retrieval-augmented generation
```

Unicode defines canonical and compatibility normalization forms specifically to make equivalent textual representations comparable. Case folding is intended for caseless matching, although normalization may need to be reapplied after folding. ([Unicode][3])

Recommended derived forms:

```text
normalized_exact
normalized_compact
normalized_tokens
normalized_ascii
```

For example:

```json
{
  "text": "Retrieval-Augmented Generation",
  "normalized_exact": "retrieval-augmented generation",
  "normalized_compact": "retrievalaugmentedgeneration",
  "normalized_tokens": ["retrieval", "augmented", "generation"]
}
```

A practical pipeline:

```text
1. Trim Unicode whitespace
2. Normalize with NFKC
3. Apply Unicode case folding
4. Normalize again
5. Standardize dash and quote classes
6. Collapse repeated whitespace
7. Remove non-semantic terminal punctuation
8. Generate compact and tokenized forms
```

However, retain the original spelling permanently.

## Layer B: semantic consolidation

This determines whether:

```text
RAG
retrieval augmented generation
retrieval-augmented generation
retrieval augmented generation system
```

refer to the same concept.

This layer requires evidence, rules, external vocabularies, or an LLM. It must not be conflated with normalization.

---

# 3. Term relationship taxonomy

Do not represent every relationship as `alias_of`. Use explicit relation types:

| Relation                 | Example                              |
| ------------------------ | ------------------------------------ |
| `exact_synonym_of`       | heart attack → myocardial infarction |
| `acronym_of`             | RAG → retrieval-augmented generation |
| `abbreviation_of`        | approx. → approximately              |
| `spelling_variant_of`    | anaesthesia → anesthesia             |
| `transliteration_of`     | Beijing → Běijīng                    |
| `translation_of`         | 心肌梗死 → myocardial infarction         |
| `former_name_of`         | Twitter → X                          |
| `product_name_of`        | Postgres → PostgreSQL                |
| `deprecated_term_for`    | old technical term → current term    |
| `broader_than`           | database → relational database       |
| `narrower_than`          | PostgreSQL → database                |
| `related_to`             | RAG → vector search                  |
| `commonly_confused_with` | Java → JavaScript                    |

Only the first several relations normally support transparent replacement during lookup.

For example, `PostgreSQL` and `database` are related but are not aliases. Merging them would contaminate retrieval expansion.

---

# 4. Operating modes

Your two-mode design is sound, but I recommend separating it into three execution paths:

```text
1. Ingestion path
2. Working-mode resolver
3. Reconciliation-mode processor
```

## 4.1 Ingestion path

When SemOS encounters a keyword:

```text
input term
   ↓
normalize deterministically
   ↓
look up existing term
   ├── found → record observation
   └── missing → create pending term and observation
```

No LLM is called.

The ingestion path should also perform cheap deterministic discovery:

```text
"retrieval-augmented generation (RAG)"
"RAG (retrieval-augmented generation)"
"Retrieval Augmented Generation, hereafter RAG"
```

Explicit short-form/long-form definitions provide strong evidence and can often be accepted without an LLM.

Other deterministic signals include:

* identical normalized forms;
* known spelling transformations;
* known singular/plural variants;
* source vocabulary identifiers;
* document-defined abbreviations;
* user-curated mappings;
* imported terminology sources.

## 4.2 Working-mode resolver

Suggested API:

```http
POST /keyword-resolver/v1/resolve
```

```json
{
  "term": "RAG",
  "language": "en",
  "domain": "artificial intelligence",
  "context": "The system retrieves relevant chunks before sending them to the model.",
  "resolution_policy": "best_effort"
}
```

A response:

```json
{
  "status": "resolved",
  "concept_id": "kwc_...",
  "canonical_term": "retrieval-augmented generation",
  "variants": [
    "RAG",
    "retrieval augmented generation",
    "retrieval-augmented generation"
  ],
  "confidence": 0.997,
  "resolution_source": "approved_lexicon",
  "lexicon_version": 1842
}
```

For ambiguity:

```json
{
  "status": "ambiguous",
  "term": "APC",
  "candidates": [
    {
      "concept_id": "kwc_activated_protein_c",
      "canonical_term": "activated protein C",
      "domain": "hematology",
      "confidence": 0.47
    },
    {
      "concept_id": "kwc_antigen_presenting_cell",
      "canonical_term": "antigen-presenting cell",
      "domain": "immunology",
      "confidence": 0.42
    }
  ]
}
```

### Working-mode resolution ladder

Use the least expensive sufficient mechanism:

```text
1. Exact original-term match
2. Exact normalized-term match
3. Domain-qualified approved mapping
4. Document-local acronym mapping
5. Corpus/project-qualified mapping
6. Deterministic fuzzy candidate lookup
7. Return ambiguous or unresolved
```

Do not invoke an LLM at step 7.

The fact that acronym disambiguation needs context is well established: large acronym datasets contain many possible long forms, and both embedding-based and language-model approaches use contextual evidence to choose among them. GLADIS, for example, contains 1.5 million acronyms and 6.4 million long forms across general, scientific, and biomedical domains. ([arXiv][4])

---

# 5. Reconciliation mode

Reconciliation should not ask an LLM to scan the entire database freely. Use a staged pipeline:

```text
pending terms
   ↓
candidate generation
   ↓
candidate scoring
   ↓
LLM adjudication
   ↓
graph consistency checks
   ↓
automatic acceptance or review queue
   ↓
versioned commit
```

## Stage 1: select work units

Select pending terms based on value and evidence:

```text
priority =
    occurrence_frequency
  × document_importance
  × retrieval_impact
  × ambiguity_penalty
  × age_factor
```

A term appearing 20,000 times should be reconciled before a term seen once.

Group observations before sending anything to the LLM:

```text
RAG
- 14,213 AI contexts
- 47 textile contexts
- 12 unrelated contexts
```

Use representative context selection rather than including all occurrences:

* one or two common contexts;
* high-diversity contexts;
* contexts containing explicit definitions;
* contexts from high-authority documents;
* counterexamples from different domains.

## Stage 2: candidate generation

Candidate generation should be broad and cheap. Entity-resolution systems call this general step **blocking**: only plausible pairs are compared, avoiding all-pairs quadratic comparison. Blocking quality is normally evaluated by its ability to retain true matches while dramatically reducing comparisons. ([arXiv][5])

Generate candidates from several independent channels:

### Exact structural candidates

```text
normalized_exact equality
normalized_compact equality
same external vocabulary code
explicit acronym/long-form assertion
```

### Acronym candidates

For `RAG`, generate long forms whose token initials equal `RAG`:

```text
retrieval augmented generation
resource allocation graph
red amber green
```

Account for stop words:

```text
quality of service → QoS
Internet of Things → IoT
```

### Lexical candidates

Use:

* trigram similarity;
* token Jaccard similarity;
* edit distance;
* prefix/suffix patterns;
* singularization;
* reordered tokens;
* transliteration rules;
* multilingual dictionaries.

PostgreSQL’s `pg_trgm` provides trigram similarity functions plus GIN and GiST index operator classes for indexed approximate matching. PostgreSQL’s `fuzzystrmatch` also provides Levenshtein, Soundex, Metaphone, and Double Metaphone functions. ([PostgreSQL][6])

### Semantic candidates

For still-unresolved terms, use embeddings to retrieve candidate concepts. This is not necessarily an LLM call at reconciliation time if embeddings are generated as part of your existing corpus pipeline.

Embed a compact representation:

```text
term + inferred definition + domain + representative contexts
```

Search against:

```text
canonical term + aliases + concept definition + domain
```

Embedding similarity should generate candidates, not make the final merge decision.

### Graph candidates

Use co-occurrence and relation evidence:

```text
terms occurring in equivalent provision templates
terms linked to identical products
terms sharing standards identifiers
terms repeatedly used in apposition
```

---

## Stage 3: deterministic scoring

Score each candidate pair before involving an LLM:

```text
candidate_score =
    0.25 × lexical_similarity
  + 0.20 × acronym_compatibility
  + 0.20 × contextual_similarity
  + 0.15 × domain_compatibility
  + 0.10 × source_authority
  + 0.10 × cooccurrence_evidence
  - contradiction_penalties
```

These should not remain fixed universal weights. Calibrate them from reviewed reconciliation decisions.

Recommended decision bands:

```text
score ≥ 0.98
    auto-link only for deterministic-safe relation types

0.70 ≤ score < 0.98
    submit to LLM

score < 0.70
    retain unresolved unless the term is high priority
```

Some deterministic evidence can bypass the LLM:

```text
SNOMED code equality
UMLS CUI equality
explicit in-document abbreviation definition
human-approved mapping
```

---

## Stage 4: LLM adjudication

The LLM should classify a bounded candidate set. Do not ask it to invent a canonical mapping from the entire corpus.

Input:

```json
{
  "term": {
    "text": "APC",
    "language": "en",
    "contexts": [
      "APC deficiency increases thrombotic risk.",
      "Resistance to activated protein C was measured."
    ]
  },
  "candidates": [
    {
      "concept_id": "kwc_1",
      "preferred_term": "activated protein C",
      "definition": "...",
      "domain": "hematology",
      "variants": ["APC"]
    },
    {
      "concept_id": "kwc_2",
      "preferred_term": "antigen-presenting cell",
      "definition": "...",
      "domain": "immunology",
      "variants": ["APC"]
    }
  ]
}
```

Output:

```json
{
  "decision": "link_existing",
  "concept_id": "kwc_1",
  "relation": "acronym_of",
  "confidence": 0.995,
  "evidence": [
    {
      "context_index": 0,
      "reason": "The context discusses deficiency and thrombosis."
    },
    {
      "context_index": 1,
      "reason": "The long form is explicitly present."
    }
  ],
  "rejected_candidates": [
    {
      "concept_id": "kwc_2",
      "reason": "The immunology meaning does not fit the contexts."
    }
  ]
}
```

Allowed decisions should be constrained:

```text
link_existing
create_new_concept
split_by_context
mark_ambiguous
mark_not_a_keyword
defer_insufficient_evidence
```

### Critical requirement: support splitting

Suppose the database currently has:

```text
APC → activated protein C
```

Later, immunology documents introduce:

```text
APC → antigen-presenting cell
```

The correct action is not to overwrite the original mapping. It is to create two concepts and attach observations according to context.

---

# 6. Database design

A PostgreSQL design could look like this.

## Core concepts

```sql
CREATE TABLE kb.keyword_concepts (
    concept_id          uuid PRIMARY KEY,
    preferred_term_id   uuid,
    concept_type        text,
    domain_key          text,
    definition          text,
    language_code       text,
    status              text NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    version             bigint NOT NULL DEFAULT 1
);
```

## Terms

```sql
CREATE TABLE kb.keyword_terms (
    term_id              uuid PRIMARY KEY,
    term_text            text NOT NULL,
    language_code        text,
    script_code          text,
    normalized_exact     text NOT NULL,
    normalized_compact   text NOT NULL,
    normalized_tokens    text[],
    term_kind            text,
    status               text NOT NULL DEFAULT 'pending',
    first_seen_at        timestamptz NOT NULL DEFAULT now(),
    last_seen_at         timestamptz NOT NULL DEFAULT now(),
    occurrence_count     bigint NOT NULL DEFAULT 0,

    UNIQUE (term_text, language_code)
);
```

## Term-to-concept assertions

```sql
CREATE TABLE kb.keyword_term_assertions (
    assertion_id        uuid PRIMARY KEY,
    term_id             uuid NOT NULL
                        REFERENCES kb.keyword_terms(term_id),
    concept_id          uuid NOT NULL
                        REFERENCES kb.keyword_concepts(concept_id),
    relation_type       text NOT NULL,
    scope_type          text NOT NULL DEFAULT 'global',
    scope_key           text,
    confidence          real NOT NULL,
    decision_status     text NOT NULL,
    evidence_type       text,
    evidence_payload    jsonb,
    valid_from          timestamptz NOT NULL DEFAULT now(),
    valid_to            timestamptz,
    created_by          text NOT NULL,
    reconciliation_run_id uuid
);
```

`scope_type` is important:

```text
global
domain
corpus
project
document
section
```

A local acronym definition may supersede the global interpretation inside a document.

## Observations

```sql
CREATE TABLE kb.keyword_observations (
    observation_id      uuid PRIMARY KEY,
    term_id             uuid NOT NULL
                        REFERENCES kb.keyword_terms(term_id),
    artifact_id         uuid NOT NULL,
    chunk_id            uuid,
    context_text        text,
    domain_key          text,
    section_path        text[],
    source_authority    real,
    observed_at         timestamptz NOT NULL DEFAULT now(),
    metadata            jsonb
);
```

## Concept relations

```sql
CREATE TABLE kb.keyword_concept_relations (
    source_concept_id   uuid NOT NULL,
    target_concept_id   uuid NOT NULL,
    relation_type       text NOT NULL,
    confidence          real NOT NULL,
    decision_status     text NOT NULL,
    evidence_payload    jsonb,
    PRIMARY KEY (
        source_concept_id,
        target_concept_id,
        relation_type
    )
);
```

## Reconciliation queue

```sql
CREATE TABLE kb.keyword_reconciliation_queue (
    queue_id             uuid PRIMARY KEY,
    term_id              uuid NOT NULL,
    priority              double precision NOT NULL,
    reason_codes          text[] NOT NULL,
    candidate_snapshot    jsonb,
    status                text NOT NULL,
    attempt_count         integer NOT NULL DEFAULT 0,
    next_attempt_at       timestamptz,
    lease_owner           text,
    lease_expires_at      timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now()
);
```

## Audit log

Every merge, split, canonical-term change, acceptance, and rejection should be append-only:

```sql
CREATE TABLE kb.keyword_change_events (
    event_id          uuid PRIMARY KEY,
    event_type        text NOT NULL,
    object_type       text NOT NULL,
    object_id         uuid NOT NULL,
    before_state      jsonb,
    after_state       jsonb,
    evidence          jsonb,
    actor_type        text NOT NULL,
    actor_id          text,
    created_at        timestamptz NOT NULL DEFAULT now()
);
```

---

# 7. Indexing strategy

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE UNIQUE INDEX keyword_terms_exact_idx
ON kb.keyword_terms (normalized_exact, language_code);

CREATE INDEX keyword_terms_compact_idx
ON kb.keyword_terms (normalized_compact);

CREATE INDEX keyword_terms_trgm_idx
ON kb.keyword_terms
USING gin (normalized_exact gin_trgm_ops);

CREATE INDEX keyword_terms_tokens_idx
ON kb.keyword_terms
USING gin (normalized_tokens);

CREATE INDEX keyword_assertions_term_idx
ON kb.keyword_term_assertions
(term_id, decision_status, scope_type, scope_key);

CREATE INDEX keyword_assertions_concept_idx
ON kb.keyword_term_assertions
(concept_id, decision_status);
```

For very high-throughput resolution, build a read-optimized snapshot:

```text
lookup key:
    normalized term + language + scope/domain

value:
    concept candidates + preferred term + variants + confidence
```

Possible deployment:

```text
PostgreSQL = authoritative store
Redis/in-process map = working-mode lookup cache
Versioned snapshot = bulk/offline resolver
```

A versioned immutable snapshot allows all keyword resolutions within one extraction run to use the same terminology state.

---

# 8. Canonical-term selection

Canonical terms should be selected independently from concept clustering.

A concept may be established correctly while its preferred label remains uncertain.

Score preferred-term candidates using:

```text
canonical_score =
    source_authority
  + domain_standard_preference
  + explicit_preferred_label
  + corpus_frequency
  + linguistic_completeness
  + stability
  - abbreviation_penalty
  - deprecated_term_penalty
  - ambiguity_penalty
```

Recommended precedence:

```text
1. User-curated project terminology
2. Governing standard or authoritative terminology
3. Domain-specific controlled vocabulary
4. Widely accepted full form
5. Most stable, unambiguous corpus form
```

Do not automatically choose the most frequent form. The most frequent term may be an acronym or deprecated name.

Maintain preferred labels by language:

```text
concept: myocardial infarction

preferred_en: myocardial infarction
preferred_zh: 心肌梗死
aliases_en: heart attack, MI
aliases_zh: 心梗
```

Whether translations belong to one concept depends on meaning equivalence, not lexical similarity.

---

# 9. Merge and split safety

A naïve union-find implementation is dangerous because synonym decisions are not necessarily permanently transitive.

For example:

```text
A resembles B
B resembles C
```

does not imply:

```text
A is synonymous with C
```

Use union-find only for high-certainty equivalence edges, such as identical external concept identifiers or approved exact synonymy.

Before merging concepts, validate:

* incompatible domains;
* contradictory definitions;
* mutually exclusive external identifiers;
* different semantic types;
* conflicting units for metric concepts;
* broader/narrower rather than equivalent relationships;
* contexts that divide into clear clusters.

Every merge should be reversible. A merged concept should redirect to the surviving concept ID rather than being physically deleted. Stable identifiers and redirects are widely used in systems such as Wikidata to preserve references even when duplicate entities are consolidated. ([addshore][7])

Suggested tables:

```text
keyword_concept_redirects
keyword_concept_merge_events
keyword_concept_split_events
```

---

# 10. Token-efficiency strategy

The largest savings will come from limiting what reaches the LLM.

## Do not send

* every occurrence;
* all aliases of every candidate;
* full documents;
* low-scoring candidates;
* already-approved mappings;
* repeated unresolved pairs with no new evidence.

## Send

* one unresolved term;
* compact metadata;
* 3–10 candidates;
* representative contexts;
* explicit evidence;
* previous decision summary when applicable.

Cache adjudication by an evidence fingerprint:

```text
hash(
    term_id
  + candidate_concept_ids
  + representative_context_hashes
  + model_prompt_version
  + terminology_version
)
```

Do not rerun reconciliation unless one of these changes:

* new contexts appear;
* candidate concepts change;
* authoritative vocabulary data changes;
* the previous decision had low confidence;
* the prompt/model policy changes materially.

Batch terms only when they share candidate concepts or a common domain. Arbitrarily batching unrelated terms may reduce token cost but increase cross-item contamination and make retries harder.

---

# 11. Confidence model

Keep separate confidence dimensions:

```json
{
  "lexical_confidence": 0.99,
  "meaning_confidence": 0.91,
  "scope_confidence": 0.95,
  "canonical_label_confidence": 0.83,
  "overall_confidence": 0.88
}
```

A single scalar can conceal important uncertainty. For example:

```text
“MI” definitely expands to “myocardial infarction” in one document,
but may not be globally unambiguous.
```

Recommended statuses:

```text
pending
candidate
provisionally_resolved
approved
ambiguous
rejected
deprecated
superseded
needs_review
```

Suggested automatic acceptance policy:

```text
approved:
    deterministic authoritative evidence
    OR LLM confidence ≥ 0.98 with no contradictory evidence

provisional:
    LLM confidence ≥ 0.85

human review:
    high-frequency or high-impact term with conflicting evidence

ambiguous:
    multiple meanings remain plausible
```

In medical and regulatory corpora, false merges are generally more damaging than missed merges. Tune the system for high precision.

---

# 12. Evaluation

Create a reviewed gold set that includes:

* capitalization variants;
* punctuation variants;
* spelling variants;
* acronyms with one meaning;
* acronyms with multiple meanings;
* multilingual synonyms;
* related-but-not-equivalent terms;
* broader/narrower pairs;
* deprecated names;
* adversarial near matches.

Measure at least:

```text
Resolution precision
Resolution recall
Concept-clustering pairwise F1
False-merge rate
False-split rate
Ambiguity detection accuracy
Candidate-generation recall@K
Working-mode latency
LLM calls per 1,000 new terms
Tokens per reconciled concept
Reconciliation stability
```

Candidate recall is especially important. If the correct concept is not among the candidates, the LLM cannot select it.

Also track downstream impact:

```text
retrieval recall before/after alias expansion
irrelevant-result increase
duplicate extracted-artifact reduction
keyword-index compression
```

---

# 13. Recommended implementation phases

## Phase 1: safe deterministic resolver

Implement:

* concept/term/assertion separation;
* Unicode normalization;
* exact lookup;
* scoped resolution;
* explicit acronym extraction;
* approved aliases;
* unresolved queue;
* audit history.

Do not introduce automatic fuzzy merging yet.

## Phase 2: candidate generation

Add:

* `pg_trgm`;
* acronym initial matching;
* spelling transformations;
* corpus frequency;
* representative contexts;
* external terminology imports;
* candidate scoring.

## Phase 3: LLM reconciliation

Add:

* bounded candidate adjudication;
* structured output;
* confidence thresholds;
* evidence fingerprints;
* merge/split decisions;
* review queue;
* evaluation set.

## Phase 4: context-aware resolution

Add:

* domain-specific mappings;
* document-local acronym scopes;
* context embeddings;
* candidate ranking;
* multi-concept responses;
* retrieval-time expansion policies.

## Phase 5: self-improving reconciliation

Use approved decisions to train or calibrate:

* candidate-ranking weights;
* pairwise synonym classifier;
* domain-specific acronym classifier;
* automatic threshold policies.

A specialized classifier may eventually handle most routine pair decisions more cheaply than a general-purpose LLM. Research on UMLS vocabulary alignment similarly treats synonymy prediction as a dedicated supervised task rather than unrestricted generation. ([arXiv][8])

---

# 14. Final recommended architecture

```text
                           ┌─────────────────────┐
Documents / Extractors ───▶│ Keyword ingestion   │
                           └──────────┬──────────┘
                                      │
                           deterministic normalize
                                      │
                           ┌──────────▼──────────┐
                           │ Terminology database │
                           │                     │
                           │ concepts            │
                           │ terms               │
                           │ assertions          │
                           │ observations        │
                           │ change events       │
                           └──────┬────────┬─────┘
                                  │        │
                    working mode  │        │ reconciliation mode
                                  │        │
                      ┌───────────▼───┐    ▼
                      │ Lookup snapshot│ candidate generation
                      │ / cache        │    │
                      └───────────┬───┘ deterministic scoring
                                  │        │
                            resolve API    LLM adjudication
                                  │        │
                                  │  validation / review
                                  │        │
                                  └────────▼
                                 versioned commit
```

The central design principle is:

> **Resolve strings deterministically during normal operation, but reconcile meanings asynchronously through bounded, evidence-driven decisions.**

More specifically, I recommend:

1. Treat the canonical object as a **concept with a stable ID**, not a string.
2. Keep raw terms, normalized terms, and concept membership separate.
3. Allow one term to map to multiple concepts under different scopes.
4. Use deterministic normalization and explicit-definition extraction first.
5. Use blocking and candidate ranking before every LLM call.
6. Ask the LLM to adjudicate candidates, not search the entire database.
7. Preserve evidence, confidence, versioning, and reversible merge history.
8. Optimize for avoiding false merges, particularly for SemOS’s medical and standards corpus.

This architecture gives you a cheap, predictable working mode while allowing the lexicon to improve incrementally during reconciliation without putting an LLM in the request path.

[1]: https://uts.nlm.nih.gov/uts/umls/home?utm_source=chatgpt.com "UMLS Metathesaurus Browser"
[2]: https://www.w3.org/TR/skos-reference/?utm_source=chatgpt.com "SKOS Simple Knowledge Organization System Reference"
[3]: https://unicode.org/reports/tr15/?utm_source=chatgpt.com "UAX #15: Unicode Normalization Forms"
[4]: https://arxiv.org/abs/2302.01860?utm_source=chatgpt.com "GLADIS: A General and Large Acronym Disambiguation Benchmark"
[5]: https://arxiv.org/abs/1905.06167?utm_source=chatgpt.com "A Survey of Blocking and Filtering Techniques for Entity Resolution"
[6]: https://www.postgresql.org/docs/current/pgtrgm.html?utm_source=chatgpt.com "F.35. pg_trgm — support for similarity of text using trigram ..."
[7]: https://addshore.com/2015/04/redirects-on-wikidata/?utm_source=chatgpt.com "Redirects on Wikidata"
[8]: https://arxiv.org/abs/2204.12716?utm_source=chatgpt.com "UBERT: A Novel Language Model for Synonymy Prediction at Scale in the UMLS Metathesaurus"
