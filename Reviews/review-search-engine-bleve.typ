#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

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
    "Review - Template"
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

#let frontmatter = (
  file_type: "typst",
  logical_name: "review-search-engine-beleve",
  file_id: "20260928",
  source: "",
  content_type: "review",
  document_date: "2026/09/28",
  keywords: [search engine, lucene, bleve],
)

= Overview
Bleve is an *embedded search/indexing library written in Go*. Conceptually, it is closer to *Lucene 
as a library* than to Elasticsearch/OpenSearch as a server: your Go application imports Bleve, 
creates an index, inserts documents, and executes searches directly in-process. It supports indexing 
arbitrary Go structures or JSON and has first-class field types for text, numbers, dates, booleans, 
geospatial data, IP addresses, and—more recently—vectors. The project is mature (started in 2014), 
Apache-2.0 licensed, and is actively maintained; the repository currently describes itself as a 
“text/numeric/geo-spatial/vector indexing library for Go.”

At the traditional information-retrieval level, Bleve provides most of what you would expect 
from a serious full-text engine: analyzers/tokenizers, stemming and multilingual text analysis, 
term/match/phrase/prefix/regexp/wildcard/fuzzy queries, ranges, Boolean composition, highlighting, 
facets, pagination, and query-time boosting. Its original scoring model is TF-IDF, but current 
releases also support *BM25*. BM25 is configured at the index-mapping level, and Bleve even has 
a “global scoring” mechanism for sharded `IndexAlias` searches: it can first gather corpus-level 
statistics across shards and then run the actual search so BM25 statistics are not computed 
independently on each shard.

Internally, the main index implementation is called *Scorch*. Scorch uses an immutable *segmented 
index* architecture: incoming batches create new index segments; updates/deletions are represented 
by bitsets that mark older documents as obsolete; readers operate against immutable index snapshots; 
and background segment merging prevents the number of segments from growing indefinitely. This is 
conceptually similar to the segment-oriented architecture behind Lucene and LSM-like storage systems. 
An inverted index maps terms to postings lists, while snapshots give queries a stable point-in-time 
view even while indexing continues. This architecture is important because Bleve isn't simply wrapping 
a SQL database—it implements a genuine search-engine indexing layer.

A particularly significant recent development is that Bleve is no longer merely a lexical search engine. 
Since v2.4 it supports *approximate nearest-neighbor vector search*, implemented by embedding FAISS 
indexes inside Scorch segments. Current documentation supports cosine, dot-product, and L2 similarity, 
vectors up to 4096 dimensions, several IVF/quantization configurations, multi-vector fields, 
filtered vector searches, and optional NVIDIA GPU acceleration. Bleve also supports *hybrid lexical + 
vector search*. Besides simply adding lexical and vector scores, newer versions provide *Reciprocal 
Rank Fusion (RRF)* and *Relative Score Fusion (RSF)*, which is especially relevant when BM25 and 
vector similarities have incompatible score distributions.

So architecturally, you can think of it roughly as:

```text
Your Go application
        │
        ▼
      Bleve
 ┌─────────────────────────────┐
 │ Query / mapping API         │
 │                             │
 │ Text analysis               │
 │ BM25 / TF-IDF               │
 │ Boolean / phrase / fuzzy    │
 │ Geo / facets                │
 │                             │
 │ Vector kNN ──────► FAISS    │
 │ Hybrid ───────► RRF / RSF   │
 └──────────────┬──────────────┘
                │
              Scorch
                │
      immutable index segments
      + postings + vectors
      + segment merging
```

For *SemOS*, Bleve is interesting because it can potentially collapse several pieces of search 
infrastructure into one embedded component: *BM25/exact retrieval + structured filtering + vector 
retrieval + hybrid fusion*, all callable directly from Go without deploying Elasticsearch, 
OpenSearch, Manticore, or a separate vector DB. You would still need to generate embeddings 
externally—Bleve indexes and searches vectors; it is not an embedding model. Its strongest 
architectural attraction for SemOS is therefore not merely “another BM25 implementation,” but 
that it gives SemOS a relatively self-contained Go-native retrieval engine suitable for the 
*candidate-generation* layer of an investigative/exploratory search system.

One caveat is worth emphasizing: vector support pulls in *FAISS/C++*, so the vector configuration 
is materially less “pure Go” than ordinary Bleve full-text search. Building vector-enabled Bleve 
requires the FAISS shared library and a Go build tag, and GPU support is specifically CUDA/NVIDIA 
oriented. For a Mac M4 deployment, I would therefore regard Bleve's lexical/BM25 side as 
straightforward, while examining the FAISS/vector build path carefully before assuming it will 
be as frictionless as the rest of Bleve.

For SemOS architecture, the most useful next comparison would probably be *Bleve vs PostgreSQL 
BM25/pgvector vs Manticore*, because those three represent distinctly different deployment models: 
embedded library, database-centric search, and standalone search server.

== Memory Issue
Bleve has the same problem as Milvus does: loading the entire vectors into memory.
*Bleve's vector search is backed by FAISS, and FAISS fundamentally expects its vector indexes 
to reside in RAM while they are being searched.* So Bleve does not solve the hundreds-of-GB 
vector problem by transparently searching vectors directly from disk. FAISS's own documentation 
explicitly says that its indexes are stored in RAM. ([GitHub][1])

Bleve does persist its Scorch segments to disk; this prevents the *entire Bleve index* from 
being permanently held in Go heap memory. ([GitHub][2]) However, the vector portion of those 
segments is implemented using embedded FAISS indexes. Bleve's documentation says that text 
and vector indexes are co-located within Scorch segments, but this does not turn FAISS into 
a disk-native ANN engine. ([GitHub][3])

== Solution 1: Quantization and Compression
The main mitigation is *compression/quantization*. Bleve currently offers several vector-index 
modes, including `recall`/`latency` using Flat + IVF with SQ8, `memory_efficient` using 
Flat + IVF with *SQ4*, and newer binary/RaBitQ configurations. ([GitHub][3]) For a 
1,536-dimensional float32 embedding, the rough raw size is:

```text
float32: 1536 × 4 = 6144 bytes/vector

100 million vectors
≈ 614 GB raw

SQ8: ~1 byte/dimension
≈ 154 GB (+ index overhead)

SQ4: ~0.5 byte/dimension
≈ 77 GB (+ index overhead)
```

FAISS documents roughly these same storage relationships: Flat uses `4*d` bytes/vector, SQ8 
approximately `d+8`, and SQ4 approximately `d/2+8`. ([GitHub][4]) Compression therefore 
helps substantially, but it changes *"hundreds of GB of RAM" into "tens or hundreds of GB 
of RAM"*, rather than fundamentally eliminating the RAM dependency.

== Solution 2: Do not create gigantic vector store
If your requirement is:

```text
> I may eventually have 500 GB or 2 TB of embeddings on SSD, but only 48 GB RAM; search them without loading the vector index into RAM.
```

then *I would not choose Bleve/FAISS specifically to solve that problem*. Bleve is attractive for 
your SemOS architecture for other reasons
- BM25
- filters
- structured fields
- lexical+vector hybrid search
- RRF/RSF
- embedded Go deployment

but its vector implementation inherits FAISS's memory-oriented architecture. ([GitHub][3])

There is, however, another architectural possibility that I think fits SemOS better:

```text
                 SemOS query
                      │
                      ▼
            ┌──────────────────┐
            │ Candidate search │
            │                  │
            │ BM25 / keywords  │
            │ metadata         │
            │ categories       │
            │ graph / links    │
            └────────┬─────────┘
                     │
                 1K–100K
                candidates
                     │
                     ▼
            vector similarity
            over candidates
                     │
                     ▼
                 reranking
```

In other words, *don't make global ANN over every embedding the primary retrieval mechanism*. Use 
your increasingly rich SemOS structure to reduce the corpus first, and apply vector similarity to 
the resulting candidate set. Bleve itself supports pre-filtered vector search, which follows 
this general idea: apply a Bleve filter to narrow candidates before kNN. ([GitHub][3])

That distinction becomes quite important at SemOS scale. If you have 100M chunks, a global 
100M-vector ANN index is expensive regardless of whether you use Milvus or Bleve. But if 
BM25/categories/entities/document relationships reduce 100M chunks to, say, *20,000 plausible 
candidates*, computing exact cosine similarity against 20,000 vectors is trivial. You can 
then keep the large embedding corpus in a disk-oriented representation rather than requiring 
the entire ANN structure in RAM.

So relative to your original Milvus problem:

```text
|                    | Milvus            | Bleve + FAISS          | Candidate-first SemOS      |
| ------------------ | ----------------- | ---------------------- | -------------------------- |
| Global ANN         | Yes               | Yes                    | Usually unnecessary        |
| Large vector index | Yes               | *Yes*                  | *Potentially no*           |
| RAM requirement                                                                              |
| Disk-native        | Yes/separate      | *Yes*                  | Yes                        |
| lexical index                                                                                |
| BM25               | Yes               | *Yes*                  | Yes                        |
| Vector compression | Yes               | *Yes*                  | Optional                   |
| Hybrid retrieval   | Yes               | *Yes, RRF/RSF*         | Natural                    |
| 500 GB vectors     | Requires careful  | *Not an obvious fit*   | *Architecturally feasible* |
| / 48 GB RAM        | indexing/tiering                                                        |
```

Given the direction you've been taking SemOS—especially the distinction between *candidate 
discovery and investigative exploration*—I think the more interesting question is no longer 
*"Can Bleve replace Milvus?"* It is *"Can SemOS eliminate the need for a global vector database 
altogether?"* I think that's worth examining, because it could simplify your architecture 
considerably while fitting the retrieval model you've been developing.

=== Similarity Search Candidates

Assume non-vector search picks 20,000 candidates. How fast a normal machine (server)
calcuates the cosine similarities of 20,000 vectors with dimension = 1536.

The short answer is: *20,000 exact similarities is actually a very small computation on a 
modern CPU*. The bigger issue is usually getting those 20,000 vectors from storage into memory.

*1. Do we calculate similarity N times?*

Yes. Suppose your query embedding is `q`, and candidate generation produces 20,000 candidate 
chunks with embeddings (v_1,...,v_20000). You calculate:

$$
\operatorname{sim}(q,v_i),\qquad i=1,\ldots,20000
$$

So that is *20,000 vector comparisons*.

But cosine similarity becomes particularly cheap if you normalize embeddings when you store them:

$$
\hat v=\frac{v}{\|v\|}
$$

and normalize the query once. Then:

$$
\cos(\hat q,\hat v)=\hat q\cdot\hat v
$$

Thus you don't really need 20,000 full cosine calculations involving norms and divisions. You need 
*20,000 dot products*.

For a 1,536-dimensional embedding, that's:

```text
20,000 × 1,536
= 30,720,000 float multiplications
+ roughly the same number of additions
```

~31 million elements is tiny by modern numerical-computing standards, especially because 
AVX2/AVX-512 can process multiple float32 values per instruction.

*2. How long would 20,000 comparisons take?*

There are two very different answers depending on *where the vectors are*.

If the 20,000 vectors are already contiguous in RAM, we're talking about *milliseconds, not seconds*.

As a useful real-world reference, SimSIMD reports about *8.2 million 1,536-dimensional float32 cosine 
operations/sec* on an Intel Sapphire Rapids CPU with its optimized SIMD implementation. Even its 
ordinary C implementation reports ~882,000/sec. ([PyPI][1])

That would imply approximately:

```text
| Implementation             | 20K × 1536-d comparisons |
| -------------------------- | -----------------------: |
| Highly optimized SIMD      |                  ~2–5 ms |
| Good optimized native code |                ~10–25 ms |
| Ordinary C implementation  |                   ~23 ms |
| Poor/scalar implementation |       perhaps 50–200+ ms |
```

These should be treated as *order-of-magnitude estimates*, not a promise for a particular server. 
CPU generation, memory layout, compiler, implementation, and whether the data is cache-resident 
all matter substantially.

There is also a useful sanity check from Elasticsearch's recent SIMD work. On AMD Turin, it 
measured FAISS AVX-512 at about *23 ns for a single 1,024-dimensional float32 dot product* 
in its microbenchmark. ([Elastic][6]) That demonstrates just how cheap the arithmetic itself 
can become with optimized SIMD.

*The real bottleneck: reading the vectors*

This is where your original Milvus concern comes back in a different form.

A 1,536-dimensional float32 vector occupies:

```text
1,536 × 4 bytes
= 6,144 bytes
≈ 6 KB
```

So 20,000 candidate vectors occupy:

```text
20,000 × 6 KB
≈ 120 MB
```

If they're already in RAM, scanning ~120 MB is trivial. But if your hundreds-of-GB vector corpus 
stays on SSD, every query potentially needs to fetch some portion of that 120 MB.

Suppose your SSD can actually deliver 3 GB/s for the access pattern:

```text
120 MB / 3 GB/s ≈ 40 ms
```

At 1 GB/s:

```text
≈ 120 ms
```

And *random I/O can be much worse*. If your 20,000 candidate IDs correspond to vectors 
scattered randomly throughout a 500-GB file/database, you can't simply divide 120 MB by 
sequential SSD bandwidth. IOPS and page amplification become important.

So the architecture becomes:

```text
Query
  │
  ├── BM25
  ├── metadata
  ├── categories
  ├── graph
  │
  ▼
20,000 candidate IDs
  │
  │    potentially expensive
  ▼
retrieve 20K embeddings from disk
  │
  │    relatively cheap
  ▼
20K exact dot products
  │
  ▼
Top 100
  │
  ▼
LLM / reranker / exploration
```

The arrow I'd worry about is *candidate IDs → embeddings*, not *embeddings → cosine scores*.

*There is another important optimization*

You don't necessarily have to use 1,536-dimensional float32 vectors for this second-stage ranking.

For example:

```text
                         20K candidates

1536-d float32      ~123 MB/query
768-d float32        ~61 MB/query
384-d float32        ~31 MB/query

1536-d float16       ~61 MB/query
768-d float16        ~31 MB/query
384-d float16        ~15 MB/query

1536-d int8          ~31 MB/query
768-d int8           ~15 MB/query
384-d int8           ~7.7 MB/query
```

And SIMD makes lower-precision comparisons extremely fast. SimSIMD's published 1,536-d benchmark, 
for example, reports roughly 16M int8 cosine operations/sec on x86. ([PyPI][5])

This suggests a potentially powerful design for SemOS:

```text
                        FULL CORPUS
                    100M+ documents
                           │
               ┌───────────┴───────────┐
               │ Candidate generation  │
               │                       │
               │ BM25                  │
               │ metadata              │
               │ categories            │
               │ entities/graph        │
               └───────────┬───────────┘
                           │
                       ~20,000
                           │
                  cheap embeddings
                  (384/768-d, f16/int8)
                           │
                    exact SIMD scan
                           │
                         ~500
                           │
                  full precision /
                    reranking / LLM
                           │
                         ~20
```

Notice something important here: *there is no ANN index at all*.

*One qualification about N=20,000*

I wouldn't hard-code 20,000. It should be a *candidate budget*.

For example, an easy query might produce:

```text
BM25 strong matches        1,200
category matches           2,500
graph expansion              600
metadata                     400
                         --------
union/deduplicate          ~3,400
```

There is little reason to inflate that artificially to 20K.

A difficult exploratory query might warrant 50K or 100K candidates. Even 100K × 768 float32 is only ~307 MB of vector data. The arithmetic is still manageable; storage access becomes progressively more important.

So I'd formulate the key insight as:

> *Once conventional/structured retrieval reduces the search space by several orders of magnitude, exact vector search becomes cheap enough that ANN may no longer be necessary.*

That is a materially different architecture from Milvus. Milvus needs an ANN structure because it must solve *query → nearest neighbors over the whole vector corpus*. SemOS may already possess enough lexical, categorical, metadata, and graph structure to solve the much easier *candidate set → exact semantic ranking* problem.

And that leads to an interesting next technical question: *how should those hundreds of GB of embeddings actually be stored on disk so retrieving 5K–50K arbitrary candidate vectors is fast?* Memory-mapped fixed-width files, PostgreSQL, RocksDB, columnar storage, and candidate-ID-aware layouts behave quite differently here. That storage problem may ultimately matter much more than the cosine computation itself.

== References
[1]: https://github.com/facebookresearch/faiss/wiki/Guidelines-to-choose-an-index?utm_source=chatgpt.com "Guidelines to choose an index · facebookresearch/faiss Wiki · GitHub"

[2]: https://github.com/blevesearch/bleve/blob/master/docs/persister.md?utm_source=chatgpt.com "bleve/docs/persister.md at master · blevesearch/bleve · GitHub"

[3]: https://github.com/blevesearch/bleve/blob/master/docs/vectors.md?utm_source=chatgpt.com "bleve/docs/vectors.md at master · blevesearch/bleve · GitHub"

[4]: https://github.com/facebookresearch/faiss/wiki/Faiss-indexes?utm_source=chatgpt.com "Faiss indexes · facebookresearch/faiss Wiki · GitHub"

[5]: https://pypi.org/project/simsimd/6.5.14/?utm_source=chatgpt.com "simsimd · PyPI"
[6]: https://www.elastic.co/search-labs/blog/elasticsearch-vector-search-simdvec-engine?utm_source=chatgpt.com "How we built Elasticsearch simdvec to make vector search one of the fastest in the world | Elasticsearch Labs"

