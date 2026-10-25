---
Date: 2026/10/23
Contributors: ChatGPT
---

PostgreSQL supports disk-based vector storage and similarity search, primarily through the pgvector extension. Unlike vector search systems that rely heavily on keeping vector indexes in RAM, PostgreSQL can store both vectors and their indexes on disk and load only the necessary pages into memory.

However, there is an important distinction:

Disk-based vector storage does not necessarily mean disk-efficient vector search.

PostgreSQL provides several ways to search vectors, each with different memory requirements, I/O patterns, and performance characteristics.

## 1. How PostgreSQL stores vectors

Suppose you have 100 million document embeddings, each with 1,536 dimensions.

Using `pgvector`, you can create a table:

```
CREATE EXTENSION vector;

CREATE TABLE embeddings (
    id BIGSERIAL PRIMARY KEY,
    document_id BIGINT,
    embedding vector(1536)
);
```

PostgreSQL stores these vectors in ordinary database storage, using its standard mechanisms:

- Heap pages: Vector values are stored in PostgreSQL table pages, typically 8 KB each.
- TOAST: Large values can be stored out of line in separate TOAST storage.
- Shared buffers: Frequently accessed database pages are cached in PostgreSQL memory.
- Operating system page cache: Recently accessed disk pages can also remain cached in RAM.
- Disk: The complete dataset persists on disk, regardless of available memory.

For 100 million vectors:

$$100{,}000{,}000 \times (1536 \times 4 + 8) \approx 615.2\text{ GB}$$

That is approximately 573 GiB of raw `vector` values, excluding table overhead, indexes, and metadata.

You do not need 615 GB of RAM to store or query this dataset.

The real question is how PostgreSQL finds the nearest vectors without reading hundreds of gigabytes for every query.

## 2. Three approaches to disk-based vector search

PostgreSQL's `pgvector` supports three main approaches.

| Method       | Search mechanism     | Memory usage     | Search performance      |
| ------------ | -------------------- | ---------------- | ----------------------- |
| Exact search | Sequential scan      | Low              | Slow for large datasets |
| IVFFlat      | Cluster-based search | Moderate         | Fast, approximate       |
| HNSW         | Graph traversal      | Potentially high | Very fast when cached   |

### Method A: Exact search — scan vectors from disk

Without a vector index, PostgreSQL can execute:

```
SELECT id, embedding <=> $1 AS distance
FROM embeddings
ORDER BY distance
LIMIT 10;
```

Here, `<=>` calculates cosine distance.

PostgreSQL:

1. Reads table pages into memory as needed.
2. Calculates the distance between the query vector and each stored vector.
3. Maintains the 10 best candidates.
4. Returns the nearest 10.

Conceptual sequential scan: pages are processed incrementally rather than loading the entire dataset.

The memory footprint can be relatively small even for hundreds of millions of vectors. However, every query potentially reads the entire dataset, making disk I/O the dominant bottleneck when the data is not cached.

### Method B: IVFFlat — search selected clusters

IVFFlat divides the vector space into clusters (called lists).

When searching:

1. Compare the query vector with cluster centroids.
2. Select the nearest clusters.
3. Read vectors belonging to those clusters.
4. Calculate distances and return the best matches.

For example, suppose you have:

- 100 million vectors
- 10,000 clusters
- 10 clusters searched per query

Assuming balanced clusters, PostgreSQL examines approximately:

$$100{,}000{,}000 \times \frac{10}{10{,}000} =100{,}000$$

Instead of 100 million vectors, it examines approximately 100,000.

```
CREATE INDEX embeddings_ivf_idx
ON embeddings
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 10000);

SET ivfflat.probes = 10;
```

This example is illustrative; production `lists` and `probes` values need tuning for recall and latency.

Important: The index resides on disk, and PostgreSQL reads the selected index pages as needed. Performance depends on how much data must be read and how effectively it is cached.&#x20;

### Method C: HNSW — graph-based search

HNSW (Hierarchical Navigable Small World) constructs a graph in which each vector is connected to nearby vectors.

Searching is fundamentally different from scanning.

Instead of evaluating all vectors, HNSW navigates through the graph toward promising neighbors.

In PostgreSQL:

```
CREATE INDEX embeddings_hnsw_idx
ON embeddings
USING hnsw (embedding vector_cosine_ops);

SET hnsw.ef_search = 100;
```

HNSW indexes are stored on disk as PostgreSQL index relations. During a search, PostgreSQL loads graph pages through its buffer system.

However, HNSW traversal often involves nonsequential page accesses. If much of the graph is not cached, this can generate significant random disk I/O.

Consequently:

- HNSW works extremely well when its active graph pages fit in RAM.
- It can operate with a graph larger than RAM.
- Performance can deteriorate substantially when disk access becomes frequent.

The pgvector documentation explicitly notes that HNSW index construction slows when the graph exceeds the configured build memory.

## 3. A more explicitly disk-oriented approach: DiskANN

There is another PostgreSQL extension worth considering: pgvectorscale, which provides StreamingDiskANN.

DiskANN-style algorithms are designed to reduce the need to keep a large vector graph in memory.

The architecture separates frequently needed search structures from data that can remain on disk.

Example:

```
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS vectorscale CASCADE;

CREATE INDEX embeddings_diskann_idx
ON embeddings
USING diskann (embedding vector_cosine_ops)
WITH (
    storage_layout = 'memory_optimized',
    num_neighbors = 50,
    search_list_size = 100
);
```

StreamingDiskANN is intended for workloads in which the vector index is significantly larger than available RAM. It still benefits from memory caching, but its storage layout is designed with disk access in mind.

DigitalOcean Documentation

## 4. Comparison for very large datasets

Suppose the dataset contains 100 million embeddings occupying approximately 615 GB, while the machine has only 64 GB RAM.

| Method                | Can operate with 64 GB RAM? | Main limitation                           |
| --------------------- | --------------------------- | ----------------------------------------- |
| Exact sequential scan | Yes                         | Reads too much data per query             |
| IVFFlat               | Yes                         | Cluster selection and recall tradeoff     |
| HNSW                  | Yes                         | Random I/O and cache misses               |
| StreamingDiskANN      | Yes                         | SSD latency, cache behavior, index tuning |

All four approaches can operate without keeping every vector in memory. The important difference is the amount and pattern of disk I/O required to answer a query.

## 5. Global vector index

We should avoid using global vector indices, especially for HNSW. But if we combine HNSW + IVF,
this should not be an issue (see the next section). The content below discusses how to
avoid using global vector indices when we really need.

SemOS already have several retrieval mechanisms: keywords, BM25, metadata, categories, and graph relationships. These can reduce the number of vectors that need to be compared.

For example:

100 million vectors on disk
  -> BM25 + metadata + categories + graph
  -> 20,000 candidate vectors
  -> Exact cosine similarity
  -> Top 100 candidates
  -> Optional reranking
  -> Top 10 results

If the candidate set contains 20,000 vectors with 1,536 dimensions, the raw vectors occupy approximately 123 MB.

Computing 20,000 cosine similarities is generally inexpensive compared with reading those vectors from uncached disk pages.

This approach offers several advantages:

- No global HNSW graph to construct and maintain.
- Vector storage can grow well beyond RAM.
- Exact similarity ranking within the candidate set.
- Existing PostgreSQL indexes can reduce the search space.
- Vector search becomes one stage of a broader retrieval pipeline.

There is one important qualification: the results are exact within the 20,000 candidates, not necessarily across the entire 100-million-vector corpus. Candidate-generation recall becomes critical.

Also, fetching 20,000 scattered vectors may require many random disk reads. A compact, sequentially organized vector store or effective cache can substantially improve performance.

## 6. Hybrid Vector Store

SemOS will use HNSW + IVF. Initially, SemOS uses HNSW. When its vector store grows too big
(i.e., consuming too much memory), SemOS will switch to use IVF.

For a system that may eventually contain hundreds of gigabytes or terabytes of embeddings, I would evaluate three architectures:

1. PostgreSQL + pgvector + filtered exact search: Best when keyword, metadata, or graph retrieval reliably produces a manageable candidate set.
2. PostgreSQL + IVFFlat: A relatively simple disk-resident approximate index when broader semantic discovery is needed.
3. PostgreSQL + StreamingDiskANN: Worth evaluating when you need global approximate nearest-neighbor search but the index is much larger than RAM.

HNSW remains a strong option when the frequently accessed index pages can be cached.

The central engineering principle is:

PostgreSQL does not solve large-scale vector search simply by storing vectors on disk. It solves the storage problem through disk-backed relations and caching; the search problem is addressed separately through indexing, candidate pruning, and I/O-efficient access.

For SemOS, I would start by benchmarking filtered exact search against StreamingDiskANN, measuring p50/p95 latency, disk reads, recall, and memory consumption under both warm-cache and cold-cache conditions. That comparison will tell you whether a global vector index is actually necessary.