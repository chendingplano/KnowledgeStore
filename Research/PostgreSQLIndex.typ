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
    "PostgreSQL Index"
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
  created: "2026/06/03",
  logical_name: "PostgreSQL Index",
  file_id: "20260600301",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/06/03",
  keywords: ["Full Text Search", "BM25", "tsvector"],
)

= tsvector
`tsvector` is PostgreSQL's internal data type for full-text search indexing. 
It stores a document as a normalized collection of searchable terms (called lexemes) instead of raw text.

Think of it as PostgreSQL's equivalent of a search-engine index entry for a single document.

Suppose you have this text:

```text
The quick brown fox jumps over the lazy dog
```

Convert it to a `tsvector`:

```sql
SELECT to_tsvector('english',
    'The quick brown fox jumps over the lazy dog');
```

Result:

```text
'brown':3
'dog':9
'fox':4
'jump':5
'lazi':8
'quick':2
```

1. Stop words were removed

   * `the`
   * `over`

2. Words were stemmed

   * `jumps` → `jump`
   * `lazy` → `lazi`

3. Positions were recorded

   * `quick` appears at position 2
   * `fox` appears at position 4

The result is a `tsvector`.

The results are then indexed, which makes the query much faster.

```sql
SELECT
  to_tsvector('english',
      'Continuous temperature monitoring is required.')
  @@
  plainto_tsquery('temperature monitoring');
```

Result:

```text
true
```

A common pattern to use tsvector:

```sql
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    title TEXT,
    content TEXT,
    search_vector TSVECTOR
);
```

Populate:

```sql
UPDATE documents
SET search_vector =
    to_tsvector('english',
        coalesce(title,'') || ' ' ||
        coalesce(content,''));
```

Set field weights (optional):

```sql
search_vector =
    setweight(to_tsvector(title), 'A') ||
    setweight(to_tsvector(keywords), 'A') ||
    setweight(to_tsvector(summary), 'B') ||
    setweight(to_tsvector(content), 'D');
```

Where:
#table(
  columns: 2,
  align: left,
  [Weight], [Importance],
  [A], [Highest],
  [B], [High],
  [C], [Medium],
  [D], [Lowest]
)

Create index:

```sql
CREATE INDEX idx_documents_search
ON documents
USING GIN(search_vector);
```

Search:

```sql
SELECT *
FROM documents
WHERE search_vector @@ plainto_tsquery('temperature monitoring');
```

Ranking Results

PostgreSQL can score matches:

```sql
SELECT
    id,
    ts_rank(search_vector,
            plainto_tsquery('vaccine temperature alarm')) AS score
FROM documents
WHERE search_vector @@
      plainto_tsquery('vaccine temperature alarm')
ORDER BY score DESC;
```

Documents matching important weighted fields receive higher scores.

tsvector is keyword-based search, with certain fuzziness. PostgreSQL full-text search performs:

* tokenization
* normalization
* stemming
* stop-word removal

For example:

```sql
SELECT to_tsvector('english',
    'Continuous temperature monitoring is required');
```

Produces:

```text
'continu'
'monitor'
'requir'
'temperatur'
```

Then:

```sql
SELECT plainto_tsquery('temperature monitoring');
```

Produces:

```text
'temperatur' & 'monitor'
```

Therefore:

#table(
  columns: 3,
  align: left,
  [Query], [Document], [Match?],
  [temperature], [temperatures], [Yes],
  [monitor], [monitoring], [Yes],
  [monitoring], [monitored], [Usually yes],
  [temperature], [heat], [No],
  [monitoring], [surveillance], [No],
)

So it is lexeme matching, not exact string matching.

But PostgreSQL FTS is not semantic search. If documents contain:

```text
continuous thermal observation
```

and query is:

```text
temperature monitoring
```

there is no match.

No synonym expansion. No embeddings. No semantic similarity. No LLM reasoning.
This is fundamentally different from vector search.

*Weights*

Field weights are important, but that is not all. Field weights are only one component.
PostgreSQL's `ts_rank()` considers:

*A. Term frequency*

More occurrences → higher score.

Document A:

```text
temperature monitoring
```

Document B:

```text
temperature monitoring
temperature monitoring
temperature monitoring
```

B scores higher.

*B. Document coverage*

Query:

```text
temperature monitoring alarm
```

Document A:

```text
temperature monitoring
```

Document B:

```text
temperature monitoring alarm
```

B scores higher.


*C. Field weights*

Matches in:

```text
title
keywords
summary
content
```

can contribute differently.

*D. Position information*

Some ranking functions can benefit from term proximity.

For example:

```text
temperature monitoring
```

is usually better than

```text
temperature ... 500 words ... monitoring
```

Suppose all fields have equal weight.

Query:

```text
vaccine temperature alarm
```

Document A:

```text
vaccine temperature alarm
```

Document B:

```text
vaccine storage temperature alarm monitoring system excursion alarm
```

B may score higher because:

* more matching terms
* higher term frequency

even with identical weights.

So scores are not meaningless without weights.
Weights merely allow you to inject domain knowledge.

*Must a query "temperature monitoring" contain both keywords?*

Usually yes. Because:

```sql
plainto_tsquery('temperature monitoring')
```

becomes:

```text
'temperatur' & 'monitor'
```

The `&` means AND.

Therefore:

#table(
  columns: 2,
  align: left,
  [Document], [Match?],
  [temperature monitoring], [Yes],
  [temperature only], [No],
  [monitoring only], [No],
  [temperature alarm monitoring], [Yes]
)

But you can change this behavior

```sql
to_tsquery('temperature | monitoring')
```

Matches either.

= Tantivy
Tantivy is one of the most important search engine projects that many PostgreSQL BM25 extensions are built upon.
Tantivy is a Lucene-like full-text search engine library written in Rust.
Tantivy itself is not a search server. It is a library that applications embed.

Historically:

```text
Lucene
    ↑
Elasticsearch
Solr
OpenSearch
```

Lucene is extremely powerful but:

- Java-based
- Large codebase
- Difficult to embed into Rust systems

The Rust community wanted:

```text
Lucene-quality retrieval
+
Rust performance
+
Rust safety
```

So Tantivy was created.

Its goal is essentially:

```text
"Build Lucene in Rust"
```

Suppose you have:

```text
Document 1:
temperature monitoring system

Document 2:
vaccine cold chain alarm

Document 3:
continuous monitoring calibration
```

Tantivy builds an inverted index:

```text
temperature
    -> Doc1

monitoring
    -> Doc1
    -> Doc3

vaccine
    -> Doc2

alarm
    -> Doc2
```

When searching:

```text
temperature monitoring
```

it quickly finds candidate documents and computes BM25 scores.

Conceptually:

```text
Raw Documents
      ↓
Tokenizer
      ↓
Analyzer
      ↓
Inverted Index
      ↓
BM25
      ↓
Top-K Results
```

This is almost identical to Lucene.

*Features*

Tantivy provides:

- Tokenization

```text
Temperature Monitoring
```

becomes:

```text
temperature
monitoring
```

- Stemming

```text
monitor
monitoring
monitored
```

becomes:

```text
monitor
```

- Phrase Search

```text
"temperature monitoring"
```

- BM25 Ranking

This is the core ranking algorithm.

- Fast Top-K Retrieval

Tantivy implements algorithms such as:

```text
Block-Max WAND
```

to avoid scoring every document. 

Architecture:

```text
PostgreSQL
     ↓
Extension
     ↓
Tantivy
```

So:

```sql
SELECT *
FROM documents
WHERE ...
```

actually leverages Tantivy underneath.

*Comparison with Lucene*

```text
| Feature            | Lucene    | Tantivy   |
| ------------------ | --------- | --------- |
| Language           | Java      | Rust      |
| Mature             | Extremely | Mature    |
| BM25               | Yes       | Yes       |
| Phrase search      | Yes       | Yes       |
| Facets             | Yes       | Yes       |
| Ecosystem          | Huge      | Smaller   |
| Embeddable in Rust | Poor      | Excellent |
```

For most retrieval workloads:

```text
Lucene ≈ Tantivy
```

in terms of search quality.

*Comparison with PostgreSQL tsvector*

Suppose your query is:

```text
vaccine temperature alarm
```

PostgreSQL:

```text
tsvector
GIN
ts_rank
```

Tantivy:

```text
Inverted Index
BM25
Block-Max WAND
```

*The Most Important Insight*

For SemOS, the biggest value of Tantivy is not that it is "faster".
The biggest value is:

```text
Better lexical retrieval quality.
```

In fact, many RAG systems today are effectively:

```text
BM25 (Lucene/Tantivy)
+
Embeddings
+
Reranker
```

and Tantivy provides the BM25 layer. That's why projects like ParadeDB chose Tantivy 
instead of relying solely on PostgreSQL's native `tsvector`/`ts_rank` stack.

= BM25 and tsvector

`tsvector` is a document representation and indexing mechanism. BM25 is a ranking algorithm.
They solve different parts of the retrieval problem.


A search engine typically consists of:

```text
Document
    ↓
Tokenization
    ↓
Inverted Index
    ↓
Candidate Retrieval
    ↓
Ranking
    ↓
Results
```

For PostgreSQL:

```text
Document
    ↓
to_tsvector()
    ↓
GIN Index
    ↓
@@ query
    ↓
ts_rank()
```

For a BM25 search engine:

```text
Document
    ↓
Analyzer
    ↓
Inverted Index
    ↓
BM25
    ↓
Results
```

Notice that:

```text
tsvector ≈ inverted index entry
BM25 ≈ ranking algorithm
```

They are not direct competitors.

tsvector does not itself define how documents are scored.
It provides `ts_rank()` and `ts_rank_cd()`. These use:

- term frequency
- field weights
- document coverage
- proximity

However, they are not BM25.

Historically PostgreSQL implemented its own ranking formulas before BM25 became the industry standard.

*Where BM25 Is Better*

BM25 additionally uses:

*IDF (Inverse Document Frequency)*

Rare terms are more valuable.

Suppose:

100,000 documents contain:

```text
temperature
```

Only 10 documents contain:

```text
thermocouple
```

Query:

```text
temperature thermocouple
```

BM25 gives much more importance to:

```text
thermocouple
```

because it is highly discriminative.

---

*Document Length Normalization*

Consider:

Document A

```text
50 words
```

Document B

```text
50,000 words
```

Both contain:

```text
temperature monitoring
```

BM25 penalizes the huge document.

Reason:

A match inside a gigantic document is less meaningful.

This is one of BM25's biggest advantages.

PostgreSQL partially accounts for document size, but not as aggressively or as effectively as BM25.

As a result:

```text
Elasticsearch
OpenSearch
Solr
Lucene
```

generally produce better rankings than vanilla PostgreSQL FTS.

The situation has changed somewhat since PostgreSQL 15+
There are now PostgreSQL extensions implementing BM25 directly.
Examples include:

- ParadeDB
- pg_search
- pg_bm25
- Tantivy-based extensions

Many provide:

```sql
SELECT *
FROM documents
ORDER BY bm25_score DESC;
```

inside PostgreSQL.

So today you can get true BM25 ranking while staying entirely within PostgreSQL.

*Option 1: Plain PostgreSQL FTS*

```sql
tsvector
+
GIN
+
ts_rank
```

Pros:

- Built-in
- Simple
- Fast
- No extra infrastructure

Cons:

- Ranking quality weaker than BM25

*Option 2: PostgreSQL + BM25 Extension*

```sql
BM25
+
PostgreSQL
```

Pros:

- Better ranking
- No separate search cluster

Cons:

- Additional extension dependency

This is probably the sweet spot for SemOS.

*Option 3: Elasticsearch/OpenSearch*

Pros:

- Best lexical retrieval
- Rich analyzers
- Synonyms
- Faceting
- Aggregations

Cons:

- Another distributed system
- More operational complexity

In the near term, we may want to do it:
```text
Candidate Generation: BM25 (PostgreSQL)
Candidate Expansion:  Graph Traversal
Candidate Reranking:  Embeddings / LLM
```

In the long term, we may want to do it:
```text
Candidate Generation: ElasticSearch + Embedding
Candidate Expansion:  Graph Traversal
Candidate Reranking:  Embeddings / LLM
```

= ParadeDB
ParadeDB provides true BM25 inside PostgreSQL. It is built on Tantivy and supports full-text, 
faceted, and hybrid search workflows directly over Postgres tables. `pg_bm25` is essentially 
the older name/lineage; current ParadeDB packaging is `pg_search`. ([PGXN: PostgreSQL Extension Network][1])

#table(
  columns: 3,
  align: left,
  [Option], [Recommendation], [Why],
  [ParadeDB `pg_search`], [#1], [Best balance of effectiveness, maturity, BM25 quality, query features, and Postgres integration.],
  [Timescale `pg_textsearch`], [#2 / watch closely], [Very promising, simple syntax, configurable BM25, Block-Max WAND, partition support; but newer. ([GitHub][2])], 
  [VectorChord-BM25], [#3], [Interesting for high-performance BM25 and RAG-style systems; less obviously general-purpose than `pg_search`. ([GitHub][3])],
  [PL/pgSQL \ BM25 implementations], [Avoid unless \ necessary ], [Useful only when Rust extensions cannot be installed; not where effectiveness/performance is the priority. ([GitHub][4])]
)

```sql
CREATE EXTENSION pg_search;
```

Then index separate SemOS fields with deliberate weighting:

```text
title / metric_name       high
curated_keywords          very high
semantic_projection       high
summary                   medium
raw_content               lower
```

One important caveat: BM25 effectiveness depends heavily on how you prepare the text fields. 
For SemOS, the biggest quality gain may come not from choosing among BM25 extensions, but from 
indexing your extracted keywords, aliases, categories, provisions, metrics, and semantic 
projections as first-class searchable fields.

Use ParadeDB `pg_search` for BM25, plus embedding for semantic search, then fuse results 
with RRF. ParadeDB explicitly supports this hybrid pattern inside Postgres. ([paradedb.com][5])

= Handle Chinese
For Chinese, do not rely on PostgreSQL’s default `english` or `simple` text search configuration. 
Chinese needs word segmentation because English text has spaces but Chinese does not. For ' 温度监测报警',
we need a word segment algorithm to break it down to, say:

```text
温度 / 监测 / 报警
```

PostgreSQL’s default parser is not designed for this; Chinese full-text search typically needs a 
Chinese tokenizer/parser such as Jieba or zhparser/SCWS. PostgreSQL’s own docs describe FTS as 
parser/configuration-based, and Chinese-specific extensions exist to provide segmentation. ([PostgreSQL][6])

Use ParadeDB `pg_search` with Jieba tokenizer for BM25. ParadeDB documents a `jieba` tokenizer for Chinese 
and says it uses dictionary plus statistical models, generally better for ambiguous Chinese word 
boundaries than simpler CJK tokenizers, though slower. ([docs.paradedb.com][7])

Conceptually:

```sql
-- Example shape, exact syntax depends on your pg_search version
CREATE INDEX metric_search_idx
ON kb.metric_search_docs
USING bm25 (
  metric_id,
  (metric_name::pdb.jieba),
  (keywords_text::pdb.jieba),
  (description::pdb.jieba),
  (context::pdb.jieba),
  (source_text::pdb.jieba)
)
WITH (key_field = 'metric_id');
```

Index both Chinese and English when available. For example:

```text
中文关键词: 温度监测, 冷链, 报警, 疫苗储存, 超温
English keywords: temperature monitoring, cold chain, alarm, vaccine storage, temperature excursion
```

This helps because users may query in either language.

`zhparser` is a PostgreSQL Chinese parser based on SCWS. ([PGXN: PostgreSQL Extension Network][8])

For Chinese, the extracted keywords are especially important. They act as your own controlled 
segmentation and synonym layer.

= Search Design: Unified `kb.search_artifacts`

Use `PostgreSQL` + `ParadeDB pg_search` (BM25 + Jieba) + `pgvector` (embeddings).

Design search as an *artifact object retrieval* system over a single unified table, not
as full-text search over one text column. Every searchable artifact — metrics, summaries,
semantic projections, provisions, topics, entities — is projected into one table
`kb.search_artifacts`, partitioned by `artifact_type`. The authoritative artifact tables
(`kb.metrics`, etc.) remain the source of record; a search hit carries
`(artifact_type, artifact_id)` so callers can join back for full detail.

Lexical and semantic retrieval are two independent, complementary paths:

- *Lexical* (`pg_search` BM25 + Jieba) — token/keyword matching, replaces `tsvector`.
- *Semantic* (`pgvector`, embedding + cosine) — meaning-based matching; handles synonyms
  and cross-lingual mismatch that BM25 cannot.

Results from both are fused with Reciprocal Rank Fusion (RRF). Neither path requires the
other; `tsvector` is not used anywhere in this design.

== Keep authoritative artifact tables; project them into one search table

Each artifact type keeps its own authoritative table. `kb.metrics` below is one example
(summaries, semantic projections, provisions, topics, and entities each have their own).
The metric table fields:

```sql
	id                      bigserial NOT NULL,
	input_record_id         int8 NOT NULL,
	event_id                text NULL,
	metric_name             text NULL,
	source_line_spans       jsonb NULL,
	metric_subject          text NULL,
	metric_desc             text NULL,
	metric_context          text NULL,
	metric_keywords         jsonb NULL,
	location_type           text NULL,
	metric_unit             text NULL,
	formula_or_definition   text NULL,
	threshold_or_target     text NULL,
	measurement_frequency   text NULL,
	confidence              float8 NULL,
	is_explicit_metric      bool NULL,
	reasoning_tags          jsonb NULL,
	ext_info                jsonb NULL,
	created_at              timestamptz DEFAULT now() NOT NULL,
	metric_name_en          text NULL,
	metric_subject_en       text NULL,
	metric_desc_en          text NULL,
	metric_context_en       text NULL,
	metric_keywords_en      jsonb NULL,
	model_name              text NULL,
	prompt_name             text NULL,
	metric_unit_en          text NULL,
	table_name_or_section   text NULL,
	metric_value            text NULL,
	value_data_type         text NULL,
	value_range_type        text NULL,
	value_class             text NULL,
	value_class_en          text NULL,
	metric_id               text NULL,
	category_paths          jsonb NULL,
	category_paths_en       jsonb NULL,
	search_document         text NULL,
	search_vector           tsvector NULL,
	CONSTRAINT              metrics_pkey PRIMARY KEY (id)
```

For search, select the most important fields:

```text
metric_name
metric_name_en
metric_subject
metric_subject_en
metric_keywords
metric_keywords_en
metric_desc
metric_desc_en
metric_context
source_text
metric_unit
metric_unit_en
value_class
value_class_en
threashold_or_target
document title / category / standard name
```

== Build one flattened search row per artifact

Do *not* use a materialized view: ingestion is per-record and asynchronous (JetStream),
and a materialized view cannot refresh a single record. Instead each doc processor
*upserts* one flattened row into `kb.search_artifacts` at the end of its run (replacing the
per-type `tsvector` reindex step in the doc-processor capsule).

```sql
CREATE TABLE kb.search_artifacts (
    id                bigserial PRIMARY KEY,
    artifact_type     text  NOT NULL,   -- 'metric' | 'summary' | 'semantic_projection' | ...
    artifact_id       text  NOT NULL,   -- source row id, e.g. kb.metrics.metric_id
    input_record_id   int8  NOT NULL,

    -- weighted lexical fields (zh + en), fed to the BM25 index via jieba
    title             text, title_en        text,
    keywords          text, keywords_en      text,
    description       text, description_en   text,
    context           text, context_en       text,
    source_text       text,

    -- semantic
    embedding_text    text,              -- synthetic doc that gets embedded (see below)
    embedding         vector(1536),      -- pgvector; EMBEDDING_MODEL_NAME = gpt-embedding-small

    created_at        timestamptz DEFAULT now() NOT NULL
) PARTITION BY LIST (artifact_type);
```

Each artifact type maps its own columns onto these generic fields when it upserts
(for a metric: `metric_name` -> `title`, `metric_keywords` -> `keywords`, and so on).

== Lexical index: BM25 + Jieba

ParadeDB BM25 indexes do not propagate from a partitioned parent the way B-tree does, so
create the BM25 index *on each partition* (this also gives free partition pruning when a
query filters by `artifact_type`). For one partition:

```sql
CREATE INDEX search_artifacts_metric_bm25
ON kb.search_artifacts_metric
USING bm25 (
    id,
    (title::pdb.jieba),
    (keywords::pdb.jieba),
    (description::pdb.jieba),
    (context::pdb.jieba),
    (source_text::pdb.jieba)
)
WITH (key_field = 'id');
```

== Field weights (BM25)

Keywords are the strongest signal (your curated, controlled-vocabulary layer), so boost
them highest:

```sql
WHERE id @@@ paradedb.boolean(
  should => ARRAY[
    paradedb.match('keywords',    :query, boost => 10),
    paradedb.match('title',       :query, boost => 8),
    paradedb.match('description', :query, boost => 5),
    paradedb.match('context',     :query, boost => 2),
    paradedb.match('source_text', :query, boost => 1)
  ]
)
```

== Semantic search (`pgvector`)

BM25 is purely lexical and will not solve semantic mismatch. The query `vaccine temperature
alarm` should match artifact text `cold-chain excursion notification`, but BM25 misses it
unless the keywords happen to bridge the gap. Embeddings + cosine similarity close this
gap, and also bridge Chinese <-> English, which token-based BM25 cannot.

The `embedding` column on `kb.search_artifacts` (above) holds the vector; index it with
HNSW for ANN search:

```sql
CREATE INDEX search_artifacts_metric_hnsw
ON kb.search_artifacts_metric
USING hnsw (embedding vector_cosine_ops);
```

Embeddings use `EMBEDDING_MODEL_NAME` (currently `gpt-embedding-small`, 1536 dims). Note it
is an OpenAI general model — adequate for Chinese, but weaker than a dedicated multilingual
model (bge-m3 / multilingual-e5). If Chinese semantic recall underperforms, the embedding
model is the first knob to turn.

The two paths combine as:

```text
BM25 candidates    (pg_search + jieba)
+
vector candidates  (pgvector cosine)
+
metadata filters   (artifact_type, input_record_id, ...)
+
final reranking
```

A good retrieval pipeline:

```text
User query
  ↓
Query normalization / expansion
  ↓
BM25 search over kb.search_artifacts   (lexical)
  +
Vector search over kb.search_artifacts (semantic)
  ↓
Merge with Reciprocal Rank Fusion (RRF)
  ↓
[ graph expansion — deferred, see future work ]
  ↓
Optional LLM / cross-encoder reranker
  ↓
Return top artifacts with evidence (join back to source table)
```

Lexical and semantic run in parallel as candidate *generators* (not semantic-as-rerank);
RRF fuses them. Graph expansion over artifact connections is intentionally left out of
this version and revisited later.

== Create a normalized embedding text

Do not embed only raw source text. Embed a synthetic, normalized artifact document and
store it in `kb.search_artifacts.embedding_text` before computing the vector:

```text
Name: Temperature monitoring alarm requirement
Keywords: vaccine storage, cold chain, temperature excursion, alarm, monitoring
Description: Measures whether vaccine storage equipment continuously monitors temperature and raises alarms during excursions.
Context: Applies to vaccine cold-chain storage and transportation.
Source: ...
```

This gives much better semantic retrieval than embedding raw extracted snippets only, and
works for every artifact type, not just metrics.

== Final Design

Unified architecture for all searchable artifacts:

```text
kb.metrics, kb.summaries, ...  = authoritative artifact records (source of truth)
kb.search_artifacts            = one flattened search row per artifact,
                                 partitioned by artifact_type
pg_search (BM25) + jieba       = lexical ranking (replaces tsvector)
pgvector (embedding + cosine)  = semantic ranking
RRF                            = fuse BM25 + vector results
```

Deferred to a later iteration: graph expansion over artifact connections
(weighted edges, bounded hops, re-scoring).

= References
[1]: https://pgxn.org/dist/pg_search/?utm_source=chatgpt.com "pg_search: Full text search for PostgreSQL using BM25 / ..."\

[2]: https://github.com/timescale/pg_textsearch?utm_source=chatgpt.com "timescale/pg_textsearch: PostgreSQL extension for BM25 ..."\

[3]: https://github.com/tensorchord/VectorChord-bm25?utm_source=chatgpt.com "supervc-stack/VectorChord-bm25: Native ..."\

[4]: https://github.com/jankovicsandras/plpgsql_bm25?utm_source=chatgpt.com "jankovicsandras/plpgsql_bm25: BM25 search ..."\

[5]: https://www.paradedb.com/blog/hybrid-search-in-postgresql-the-missing-manual?utm_source=chatgpt.com "Hybrid Search in PostgreSQL: The Missing Manual"\

[6]: https://www.postgresql.org/docs/current/textsearch.html?utm_source=chatgpt.com "Documentation: 18: Chapter 12. Full Text Search"\

[7]: https://docs.paradedb.com/documentation/tokenizers/available-tokenizers/jieba?utm_source=chatgpt.com "Jieba - ParadeDB"\

[8]: https://pgxn.org/dist/zhparser/?utm_source=chatgpt.com "zhparser: a parser for full-text search of Chinese / ..."

