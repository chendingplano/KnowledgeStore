---
Date: 2026/11/12
Contributors: ChatGPT
---

# Summary: Faster Retrieval for Better, More Efficient RAG

Apple Machine Learning Research · November 5, 2026 · Based on ICML 2026 paper

The central idea is to replace part of conventional vector search with a small, trained neural network that learns where the best matching vectors are likely to be.

Instead of searching a vector database from scratch for every query, Apple proposes learning from previous queries and their exact retrieval results. This shifts some computation from query time to offline training.

The approach is called Amortized Maximum Inner Product Search (MIPS).

## 1. The problem Apple is trying to solve

Conventional approximate nearest-neighbor search (ANN) systems, such as FAISS IVF, often use clustering to accelerate retrieval.

For example, suppose we have:

- 2.6 million document embeddings.
- 128 clusters, each containing roughly 20,000 embeddings.
- A user query that needs to find the most relevant document.

The conventional IVF retrieval process is:

Query embedding

Compare with 128 centroids

Select the most promising clusters from Cluster 1, Cluster 2, 
Cluster 3, Cluster 4, ..., then search vectors in selected clusters

The weakness is that the centroid is not necessarily representative of the best matching document inside a cluster.

A cluster may contain an excellent match, but its centroid may be far from the query. Consequently, the search engine might skip the correct cluster.

Apple addresses this problem using two neural-network architectures.

## 2. Apple's two proposed approaches

SupportNet — Learn which cluster to search

Rather than comparing the query with cluster centroids, SupportNet predicts the best possible similarity score between the query and any vector inside each cluster.

It uses these predictions to select promising clusters more accurately.

KeyNet — Learn where the best vector is

Instead of predicting cluster scores, KeyNet directly predicts the embedding of the document most likely to match the query.

The predicted embedding replaces the original query embedding when searching an existing ANN index.

The distinction is important:

|               | SupportNet                       | KeyNet                         |
| ------------- | -------------------------------- | ------------------------------ |
| Input         | Query embedding                  | Query embedding                |
| Output        | Predicted best score per cluster | Predicted best-match embedding |
| Main purpose  | Cluster routing                  | Query transformation           |
| Integration   | Replaces centroid routing        | Preprocesses query before IVF  |
| Main strength | Routing and score estimation     | Fast retrieval                 |

Both are trained offline using query embeddings paired with ground-truth results obtained through exhaustive search.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://machinelearning.apple.com\&sz=32)

Apple Machine Learning Research



## 3. How the models work

### 3.1 SupportNet

Apple recognizes that MIPS can be expressed mathematically as a support function.

Given a collection of document vectors $K$ and query vector $q$:

$$ h_K(q)=\max\_{k\in K}q^\top k$$

This function returns the maximum inner product between the query and all vectors in the collection.

For each cluster $C_i$, SupportNet approximates:

$$\hat h_i(q)\approx\max\_{k\in C_i}q^\top k$$

Thus, instead of asking which centroid is most similar, it predicts which cluster contains the most similar individual vector.

SupportNet is trained using a neural-network architecture informed by convexity, exploiting the mathematical properties of support functions.

### 3.2 KeyNet

KeyNet learns a different mapping:

$$f\_\theta(q)\approx \underset{k\in K}{\operatorname{argmax}}\ q^\top k$$

In other words, given the query embedding, KeyNet predicts the vector of the best matching document.

The retrieval pipeline becomes:

```text
Original query vector $q$
           ↓
KeyNet: Predict best matching key vector
           ↓
Transformed query $\hat k$
           ↓
Existing FAISS IVF index
           ↓
Retrieved documents
```

This is particularly interesting because KeyNet does not need to replace the underlying vector database. It can act as a learned query transformation layer.

One important clarification: KeyNet does not directly return a document ID. It predicts a vector, and the existing retrieval index still performs the actual search.

## 4. Experimental results

Apple evaluated these methods using Natural Questions, with approximately 2.6 million passages and 128 clusters in the reported setup.

**Reported retrieval latency**

- SupportNet vs centroid routing: # 1.9×, faster at approximately 95% routing recall,
1.74 ms vs 3.36 ms
- KeyNet vs raw-query IVF: \~8× faster at 99% recall, 0.23 ms vs 1.8 ms

**Fraction of database scanned to reach 99% recall**
(Lower is better. KeyNet L versus raw-query IVF.)

- Raw query: 0.10%
- KeyNet: 0.01%

At the same 99% recall target, KeyNet scans roughly 11 times fewer keys than the conventional raw-query approach.

The reported speedups include neural-network inference overhead. However, they are benchmark results under the paper's experimental conditions, not a guarantee of equivalent gains in every production system.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://machinelearning.apple.com\&sz=32)

Apple Machine Learning Research



## 5. Why this approach is interesting

I see three particularly important ideas in this research.

First: Retrieval itself can be learned.

Traditional retrieval relies heavily on geometric indexing algorithms. Apple demonstrates that part of the search operation can instead be approximated by a neural network trained on examples of successful retrieval.

Second: Query distributions matter.

Traditional vector indexes are generally built around the distribution of document embeddings. However, user queries and documents often have very different characteristics.

Apple explicitly learns from the query distribution, which may be especially valuable in domain-specific RAG systems where queries exhibit recurring patterns.

Third: Retrieval computation can be amortized.

The expensive exhaustive searches are performed during offline training. Once the model is trained, subsequent queries benefit from the knowledge encoded in the network weights.

This is analogous to compiling repeated retrieval behavior into a reusable predictor.

## 6. Limitations and engineering considerations

The approach introduces several tradeoffs:

- Training cost: Generating ground-truth training examples requires expensive exhaustive retrieval.
- Database updates: Because the model learns a mapping for a particular collection of keys, significant changes to the database may require retraining.
- Query distribution shift: Performance may deteriorate when queries differ substantially from the training distribution.
- Model overhead: The neural network consumes memory and compute. The net benefit depends on the index, dataset, model size, and hardware.
- Recall versus relevance: The reported recall primarily measures whether approximate search recovers the exact MIPS result. It does not directly measure whether the retrieved passage actually answers the user's question.

Apple reports some robustness to mild query-distribution shifts, but that does not eliminate the need to evaluate the approach under real workloads.


## 7. Retrieval

SupportNet and KeyNet are two alternative approaches, not necessarily two consecutive stages in the same retrieval pipeline.

**SupportNet: Predict which clusters to search**

Given:

- $q$: query embedding
- $K$: collection of document embeddings
- $C_1,C_2,\ldots,C_m$: clusters partitioning $K$

SupportNet predicts a score for every cluster, rather than directly predicting a single cluster ID.

$$\text{SupportNet}(q)=[s_1,s_2,\ldots,s_m]$$

where:

$$s_i\approx\max\_{k\in C_i}q^\top k$$

The retrieval engine can then select the top 1, top 5, or top $n$ clusters based on these scores.

Therefore, SupportNet does not have to predict only one cluster. Selecting multiple clusters improves recall at the expense of additional search.

**KeyNet: Predict the best matching vector**

Given query embedding $v_1$, KeyNet predicts a new vector $v_2$:

$$v_2=\text{KeyNet}(v_1)$$

Ideally:

$$v_2\approx\underset{k\in K}{\operatorname{argmax}}\ v_1^\top k$$

In other words, KeyNet attempts to predict the embedding of the best matching document.

The original query $v_1$ is replaced with $v_2$ for approximate index navigation.

Importantly, $v_2$ is not guaranteed to be an actual vector in $K$. It is a neural-network prediction.

### 7.1 How they work together

```
q = v1
   |
 KeyNet
   |
v2 = predicted best vector
   |
 SupportNet
   |
Best cluster
   |
Search vectors in cluster
```

This is conceptually possible, but it is not the combined architecture Apple proposes.

Apple describes three configurations:

**A. SupportNet alone**

```text
q → SupportNet → Top clusters
```

Then search the selected clusters using the original query.

**B. KeyNet alone**

```text
q → KeyNet → IVF index
```

Use the predicted vector to navigate the conventional index.

**C. Proposed large-scale combination**

```text
Original query q
        ↓
Global SupportNet
        ↓
Selected clusters
        ↓
Per-cluster KeyNet
        ↓
Local vector search
```

SupportNet first, then a specialized KeyNet within each selected cluster.

Apple explicitly suggests the third configuration as a possible architecture for very large databases, rather than presenting it as the main experimentally validated pipeline.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://machinelearning.apple.com\&sz=32)

Apple Machine Learning Research

### 7.2 Distinction: retrieval versus scoring

There is a subtle issue with replacing $v_1$ with $v_2$.

Suppose KeyNet predicts $v_2$, and the index retrieves candidate vectors $k_1,k_2,k_3$.

The original retrieval objective remains:

$$k^n=\arg\max\_{k\in K}v_1^\top k$$


It is not:

$$\arg\max\_{k\in K}v_2^\top k$$

The transformed query is useful for finding candidates, but it changes the similarity geometry. Therefore, if you want to preserve the original MIPS objective when ranking multiple retrieved candidates, you should score them using $v_1$, not necessarily $v_2$.

This distinction is particularly relevant when using KeyNet for top-$k$ retrieval rather than finding only the single best vector.

## 8. Implications for SemOS

For SemOS, I think the most promising aspect is KeyNet as an optional retrieval accelerator.

Your system already combines lexical, metadata, and vector retrieval. KeyNet could be inserted into the semantic retrieval path without changing those other components.

Conceptually:

```
User query
    |
    +--> BM25 / keyword retrieval
    |
    +--> Metadata / graph retrieval
    |
    +--> Embedding model
              |
            KeyNet
              |
         Vector index
              |
         Candidates
    |
    v
Candidate fusion / reranking
    |
    v
Investigation / exploration
```

However, I would not prioritize implementing it immediately.

For a standards and technical-document corpus, two questions matter particularly:

1. Is vector retrieval actually the bottleneck? If query embedding, reranking, or LLM investigation dominates latency, accelerating ANN search may yield little end-to-end improvement.
2. Can representative training queries be obtained? Standards queries may vary substantially across domains, terminology, and technical specificity. KeyNet must learn the relevant query-to-document mapping rather than simply memorize common queries.

A useful experiment would compare raw-query ANN against KeyNet-assisted ANN using the same fixed corpus, measuring recall against exact MIPS, retrieval latency, end-to-end answer quality, and sensitivity to newly added documents.


## 9. Generating training data


We can use LLM to generate synthetic `(query, chunk)` pairs to train KeyNet or SupportNet.

For SemOS, this is especially attractive because your documents are already divided into chunks, and you have structured information such as topics, keywords, metrics, and summaries that can help generate realistic queries.

The LLM generates candidate training queries, but the actual training labels for KeyNet and SupportNet should be derived from the vector index using exact retrieval.

This is necessary because the LLM's intended target chunk is not necessarily the nearest vector under your embedding model.

### 9.1 Proposed training data generation pipeline

```text
             Document corpus
                     ↓
              LLM query generation
Generate multiple questions answerable from each chunk
                     ↓
          Synthetic (query, chunk) pairs
                     ↓
          Embedding + exact MIPS
Find actual nearest vectors and clusters
                     ↓
             KeyNet training
    Query vector → best matching vector
                     ↓
          SupportNet training
Query vector → best score per cluster
```

### 9.2 Generate realistic queries from each chunk

Suppose a chunk contains:

> The maximum permissible error of a pressure gauge shall not exceed ±0.5% of the full-scale measurement range under reference conditions.

You could ask an LLM to generate several types of queries:

| Query type       | Synthetic query                                                                      |
| ---------------- | ------------------------------------------------------------------------------------ |
| Direct question  | What is the maximum permissible error of a pressure gauge?                           |
| Technical search | Pressure gauge accuracy tolerance under reference conditions                         |
| Keyword search   | Pressure gauge MPE full-scale                                                        |
| Scenario         | Can a pressure gauge with 0.8% full-scale error pass the specified requirements?     |
| Comparative      | How is pressure gauge permissible error expressed relative to its measurement range? |

All five queries originate from the same chunk, but their embeddings may be quite different.

This is valuable because KeyNet must learn how query embeddings relate to document embeddings, not merely memorize similar wording.

You should also generate queries that combine information from multiple chunks, queries containing abbreviations or synonyms, and queries that are intentionally underspecified. These better approximate actual retrieval workloads.

### 9.3 Convert synthetic pairs into actual training labels

Suppose the LLM generates:

$$(q_i,c_i)$$

where $c_i$ is the chunk used to generate query $q_i$.

You embed both:

$$v_i=E\_{\text{query}}(q_i)$$

$$k_i=E\_{\text{document}}(c_i)$$

You might expect to train KeyNet directly using:

$$v_i\rightarrow k_i$$

But that is not necessarily the correct training target.

Why? Because the embedding model might consider another chunk $c_j$ more similar to the query than the source chunk $c_i$.

For Apple's method, the correct target is:

$$k_i^*=\arg\max\_{k\in K}v_i^\top k$$

Thus, your training example becomes:

$$(v_i,k_i^n)$$

This is precisely the approach Apple describes: sample queries, compute their ground-truth MIPS solutions using exhaustive search, and train the network to reproduce those solutions.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://machinelearning.apple.com\&sz=32)

Apple Machine Learning Research



For SupportNet, you would calculate a target score for every cluster:

$$s\_{ij}=\max\_{k\in C_j}v_i^\top k$$

and train on:

$$(v_i,[s\_{i1},s\_{i2},\ldots,s\_{im}])$$

One useful distinction is that your original `(query, chunk)` pairs are still valuable as semantic relevance labels. They tell you which chunk was intended to answer the question, even when the embedding model retrieves something else.

Keep both types of labels.

### 9.4 How many synthetic queries should you generate?

I would begin with a controlled experiment rather than generating millions of queries immediately.

For example, with 100,000 chunks:

| Parameter               | Initial experiment |
| ----------------------- | ------------------ |
| Chunks sampled          | 10,000             |
| Queries per chunk       | 5                  |
| Total synthetic queries | 50,000             |
| Training queries        | 40,000             |
| Validation queries      | 5,000              |
| Test queries            | 5,000              |

For evaluation, split by source document or document family before generating queries, so near-duplicate chunks do not leak between training and test sets. Keep the complete retrieval corpus available in all splits.

Use two evaluation metrics:

- MIPS recall: Does KeyNet-assisted retrieval recover the same best vector as exhaustive search?
- Semantic relevance: Does the retrieved chunk actually answer the query?

The first measures Apple's retrieval acceleration objective. The second measures what matters to SemOS.

### 9.5 The main risk: Synthetic query distribution

The greatest concern is not whether the LLM can generate plausible queries. It can.

The concern is whether those queries resemble real user queries.

For example, an LLM might generate:

> What is the maximum permissible error of a pressure gauge under reference conditions?

But an actual user might ask:

> Is a 0.8% pressure gauge accurate enough for this application?

These questions are related, but they can occupy different regions of embedding space.

KeyNet is explicitly trained to exploit a known query distribution. If your synthetic distribution differs significantly from real usage, the speedup or recall advantage may not generalize.

To address this, I recommend combining chunk-derived questions with synthetic user scenarios and, eventually, anonymized real query samples.

### 9.6 My recommendation for SemOS

I would implement synthetic query generation as a reusable dataset-building capability, independently of KeyNet and SupportNet.

That dataset could support several applications:

- Training and evaluating embedding models.
- Evaluating BM25 versus vector retrieval.
- Training rerankers.
- Evaluating retrieval recall and answer relevance.
- Training KeyNet and SupportNet.
- Evaluating query rewriting and expansion.

There is also an important strategic consideration: KeyNet optimizes the retrieval algorithm, not necessarily the quality of the embedding model.

If the embedding model's exact nearest neighbor is semantically wrong, a perfectly trained KeyNet will learn to retrieve that wrong neighbor faster.

Therefore, I would first establish a reliable synthetic query evaluation dataset, measure the quality and latency of your current retrieval system, and only then determine whether learned retrieval acceleration is worth introducing.

The synthetic `(query, chunk)` dataset is valuable regardless of whether you eventually adopt Apple's approach.

## 10. Conclusion

Apple's research demonstrates a shift from purely algorithmic vector search toward learned retrieval, where neural networks approximate parts of the retrieval process.

The two contributions are complementary: SupportNet predicts which clusters contain the best matches, while KeyNet predicts where the best matching embedding lies.

The broader insight is that a retrieval system does not always need to solve every search independently. When the document collection and query distribution are sufficiently stable, it can learn from previous exact searches and reuse that knowledge to make future retrieval significantly faster.

Source: [Apple Machine Learning Research — Faster Retrieval for Better, More Efficient RAG](https://machinelearning.apple.com/research/faster-retrieval?utm_source=chatgpt.com). The article also links to the underlying ICML 2026 paper, Amortizing Maximum Inner Product Search with Learned Support Functions.