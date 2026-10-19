# Embedding
## 1. Late Chunking - Overview

In late chunking, we do not actually embed paragraphs or chunks. Given a document, it embeds only 
once: the entire document, which generates H = [$h_1$, $h_2$, ..., $h_n$], where $h_i$ is the 
embedding of the i-th token of the document. Now, if we want to generate the embedding for a 
chunk, we can retrieve the corresponding element in H, sum the vectors into one vector and 
then divide it by N, where N is the number of tokens in the chunk.

### 1.1 Algorithm
#### 1.1.1 Embedding
Given a document containing $n$ tokens, the transformer produces:

$$
H=[h_1,h_2,\ldots,h_n]
$$

where each $h_i$ is a contextualized token embedding.

The word contextualized is important: $h_i$ is not simply the embedding of token $i$ in 
isolation. It incorporates information from other tokens in the document through the 
transformer's attention mechanism.

Also, $H$ refers to the token-level **hidden states** of the embedding model, before its final pooling operation.

#### 1.1.2 Generate chunk embeddings using mean pooling

Suppose chunk $C$ corresponds to tokens 100 through 199.

Its embedding is:

$$
E_C=\frac{1}{100}\sum_{i=100}^{199}h_i
$$

This is exactly what you described.

For example, a document with 10,000 tokens could produce:

Document: 10,000 tokens

Transformer (one forward pass)

H: 10,000 contextualized token vectors

Mean pool: [E1, E2, ..., E20]

One transformer pass, followed by independent pooling for each chunk.
The result is 20 chunk embeddings, assuming 500 tokens per chunk.

#### 1.1.3 One important practical limitation

This only works directly if your embedding model exposes token-level representations.

For example, a typical embedding API returns:

$$
\operatorname{Embed}(\text{document})\rightarrow \mathbb{R}^{d}
$$

It returns a single vector, not $H$.

Late chunking requires:

$$
\operatorname{Transformer}(\text{document})\rightarrow \mathbb{R}^{n\times d}
$$

You then perform the pooling yourself, generally followed by any normalization required by the embedding model.

If the entire document cannot fit within the model's context window, you process larger 
windows separately.

The key benefit: You pay for one transformer forward pass over the document (or window), 
then generate as many contextualized chunk embeddings as needed through inexpensive 
pooling operations.

### 1.2 Commonly Used Embedding Models
Embedding models can be divided into two major categories:

1. Commercial embedding models — accessed through APIs, such as OpenAI, Google, and Cohere.
2. Open-weight embedding models — run locally or on your own servers, such as BGE, E5, GTE, and Qwen Embedding.

For SemOS, we evaluate them along four dimensions: 
- retrieval accuracy, 
- multilingual support (especially English and Chinese), 
- computational cost, 
- and support for late chunking.

#### 1.2.1 Common commercial embedding models

| Provider  | Models                                             | Main strengths                                            |
| --------- | -------------------------------------------------- | --------------------------------------------------------- |
| OpenAI    | `text-embedding-3-small`, `text-embedding-3-large` | Reliable general-purpose embeddings, multilingual         |
| Google    | `gemini-embedding-001`                             | Multilingual, retrieval, classification                   |
| Cohere    | `embed-v4.0`, Embed Multilingual                   | Enterprise retrieval, multilingual and multimodal support |
| Voyage AI | `voyage-3-large`, `voyage-3.5`, `voyage-code-3`    | High-quality retrieval, code search                       |
| Jina AI   | `jina-embeddings-v3`, `jina-embeddings-v4`         | Multilingual, long-context, document retrieval            |

For example, OpenAI's models have these specifications:

| Model                    | Default dimensions | Maximum input | API price / 1M tokens |
| ------------------------ | ------------------ | ------------- | --------------------- |
| `text-embedding-3-small` | 1,536              | 8,192 tokens  | $0.02                 |
| `text-embedding-3-large` | 3,072              | 8,192 tokens  | $0.13                 |

Both support configurable output dimensions, but neither exposes token-level hidden states through the standard embedding API.

#### 1.2.2 Common open-weight embedding models

These are especially relevant if you want to run embeddings locally and experiment with late chunking.

| Model family                                                                                                  | Typical models                      | Characteristics                                         |
| ------------------------------------------------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------- |
| [Qwen3 Embedding](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B?utm_source=chatgpt.com)                    | 0.6B, 4B, 8B                        | Strong multilingual retrieval, including Chinese        |
| [BGE-M3](https://huggingface.co/BAAI/bge-m3?utm_source=chatgpt.com)                                           | BGE-M3                              | Multilingual, dense, sparse, and multi-vector retrieval |
| [E5](https://huggingface.co/intfloat/multilingual-e5-large-instruct?utm_source=chatgpt.com)                   | multilingual-e5-large-instruct      | Multilingual semantic search                            |
| [GTE](https://huggingface.co/Alibaba-NLP/gte-multilingual-base?utm_source=chatgpt.com)                        | gte-multilingual-base, GTE-Qwen     | Multilingual retrieval, several model sizes             |
| [Jina Embeddings](https://huggingface.co/jinaai/jina-embeddings-v3?utm_source=chatgpt.com)                    | jina-embeddings-v3                  | Long-context multilingual embeddings                    |
| [Sentence Transformers](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2?utm_source=chatgpt.com) | all-MiniLM-L6-v2, all-mpnet-base-v2 | Small, fast, widely used baselines                      |
| [Nomic Embed](https://huggingface.co/nomic-ai/nomic-embed-text-v1.5?utm_source=chatgpt.com)                   | nomic-embed-text-v1.5               | Efficient general-purpose retrieval                     |

The [MTEB leaderboard](https://leaderboard.mteb.org/?utm_source=chatgpt.com) is a useful place to compare these models. It supports filtering by language, task, model size, and architecture, rather than relying on a single overall score.

**Models that support late chunking**

| Model                | Late chunking feasibility       | Notes                                                |
| -------------------- | ------------------------------- | ---------------------------------------------------- |
| OpenAI embedding API | No, via standard API            | Returns final pooled vectors                         |
| BGE-M3               | Yes, with custom implementation | Token-level hidden states available locally          |
| multilingual-E5      | Yes, with custom implementation | Encoder architecture suitable for contextual pooling |
| GTE multilingual     | Yes, with custom implementation | Requires appropriate pooling and token alignment     |
| Jina Embeddings v3   | Yes, with custom implementation | Long-context encoder, suitable candidate             |
| Qwen3 Embedding      | Possible, but requires care     | Causal architecture and model-specific pooling       |

A particularly important point: Qwen3 Embedding uses a causal transformer architecture. Its token representations do not automatically incorporate information from following tokens. Consequently, simply averaging token representations is not necessarily equivalent to the model's trained embedding behavior.

Models based on bidirectional encoders, such as BGE-M3 and multilingual-E5, are more straightforward starting points for experimenting with late chunking.

Also, the fact that an architecture permits custom token pooling does not guarantee that late-chunked vectors will outperform its standard embeddings.

#### 1.2.3 Models for SemOS

[Qwen IA - Suite de modelos de lenguaje de Alibaba Cloud](https://images.openai.com/static-rsc-4/wDD9nK6dE97GsQ5vEzRgKYoxUuxEtIY-N12SfyVm4syJFQV4zhNtaHPPwnYKpzJJMrWcA_zCmUVkSYiz21ZlAOspMgo0BNypfB9mjPG5sgkcBkIJ4e74-3-Nw3b9r9X8Z7lnKRFC3orEXKdA_8TjL4dYbsfomT7PiBz26UH2dHc?purpose=inline)

[Qwen3-Embedding-0.6B](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B?utm_source=chatgpt.com)

A strong local baseline for English/Chinese semantic retrieval. Small enough to experiment with on your Mac. I would first use its standard embedding method rather than custom late chunking.

[BGE — BGE  documentation](https://images.openai.com/static-rsc-4/H_41IChh1k4U_UitHaRaZ0A80fgW7diA9kLbmGJR43Bvucylfqo7r75p9b_bNM2IgRFL6EfCQ2Vq44XmoafTfZEScBcFeQcsgxOjcd2bnx7A6M0_qM4uj2zmaYwtkqJLoGDhZ9Poi3KCK0rixlg57iJJ3up9P6s_vzxXRCXkc9o?purpose=inline)

[BAAI/bge-m3](https://huggingface.co/BAAI/bge-m3?utm_source=chatgpt.com)

My preferred starting point for late-chunking experiments. Its bidirectional encoder and multilingual capabilities are relevant to technical standards and regulations. It also offers sparse and multi-vector representations.

[Medium](https://images.openai.com/static-rsc-4/PRcifKLh_DSoPn_euHv6rqJb90snk408XfIVDJ7hpRtZQACzJ-FnXRSRBE0z3KgZuqrr2_J7Dcc2biFipWOMT5s8NtRICgFi3PkDDJPoBlX7i1OmGDnHPgiKHqbuVXONGPtfwZ2kLwR7B_kXfeVA-bTVfFr_ZpTbUww0qHJYKXM?purpose=inline)

[jina-embeddings-v3](https://huggingface.co/jinaai/jina-embeddings-v3?utm_source=chatgpt.com)

Another good candidate for contextualized chunk embeddings, particularly when working with longer sections. Check its model-specific task adapters and pooling requirements.

I would benchmark these against your existing OpenAI embedding pipeline on the same SemOS retrieval queries.

The most useful experiment would be to compare three configurations using the same local encoder:

1. Standard chunk embeddings: Each chunk encoded independently.
2. Late chunking: Encode a larger section once, then pool token representations for each chunk.
3. Contextualized text embeddings: Prepend document title, section hierarchy, and relevant definitions before independently embedding each chunk.

Measure Recall\@10, nDCG\@10, embedding throughput, and incremental reindexing cost.

For your use case, I would pay particular attention to provisions and metrics that depend on definitions or conditions elsewhere in the document. That is where late chunking has the most plausible advantage over independent chunk embeddings.

#### 1.2.4 Comparison of BGE-M3 and Jina Embedding 3
BGE-M3 and Jina Embeddings v3 are both strong multilingual embedding models, but they emphasize different capabilities.

- BGE-M3 emphasizes flexible retrieval: dense embeddings, sparse lexical retrieval, and multi-vector retrieval in one model.
- Jina Embeddings v3 emphasizes task-specific embeddings through LoRA adapters, long-context processing, and multilingual retrieval.

For SemOS, particularly your interest in late chunking, I would lean toward Jina v3 for initial late-chunking experiments, but BGE-M3 for experimenting with hybrid retrieval.

##### 1.2.4.1 Architecture and specifications

| Feature                     | BGE-M3                               | Jina Embeddings v3        |
| --------------------------- | ------------------------------------ | ------------------------- |
| Developer                   | BAAI                                 | Jina AI                   |
| Base architecture           | XLM-RoBERTa                          | XLM-RoBERTa               |
| Parameters                  | \~568M                               | \~572M                    |
| Maximum input               | 8,192 tokens                         | 8,192 tokens              |
| Dense embedding dimensions  | 1,024                                | 1,024                     |
| Multilingual                | 100+ languages                       | 89 languages              |
| Bidirectional attention     | Yes                                  | Yes                       |
| Dense retrieval             | Yes                                  | Yes                       |
| Sparse lexical retrieval    | Native                               | Not a native output       |
| Multi-vector retrieval      | Native                               | Not a native output       |
| Task-specific LoRA adapters | No equivalent built-in adapter suite | Yes                       |
| Local inference             | Yes                                  | Yes                       |
| Late chunking               | Possible with custom code            | Possible with custom code |

Both are in roughly the same parameter class, so neither has an obvious size advantage for your M4 Pro Mac Mini.

##### 1.2.4.2 The most important architectural differences

BGE-M3: Three retrieval representations

BGE-M3 can generate three kinds of representations from the same text:

- Dense: A single 1,024-dimensional vector for semantic similarity.
- Sparse: Token-weight representations for lexical matching, conceptually similar to learned term weighting.
- Multi-vector: ColBERT-style token-level representations for fine-grained query-document matching.

These can be combined into a hybrid retrieval system.

For SemOS, however, you already use PostgreSQL lexical retrieval. BGE-M3's sparse retrieval would therefore be an additional option, not necessarily a replacement for your existing BM25 index.

*Jina v3: Task-specific LoRA adapters*

Jina v3 uses a common transformer backbone with five task-specific adapters:

| Adapter             | Purpose                  |
| ------------------- | ------------------------ |
| `retrieval.query`   | Encode search queries    |
| `retrieval.passage` | Encode indexed documents |
| `separation`        | Clustering               |
| `classification`    | Classification           |
| `text-matching`     | Semantic similarity      |

This is useful because the optimal representation for clustering is not necessarily the same as the optimal representation for retrieval.

Jina v3 also supports Matryoshka embeddings, allowing you to use reduced dimensions such as 256 or 512 instead of 1,024, potentially saving substantial vector storage.

**Which is better for late chunking?**

Both models have bidirectional attention and an 8,192-token context window.

But Jina v3 has an advantage: late chunking is explicitly supported and documented by Jina, whereas BGE-M3 requires a custom implementation.&#x20;

For Jina v3, you can conceptually use:

$$[ H=\operatorname{Transformer}\_{\text{passage}}(D) ]$$

Then, for each chunk $C_i$:

$$[ E_i=\operatorname{Normalize}\left(\operatorname{MeanPool}(H\_{C_i})\right) ]$$

For BGE-M3, the same idea is possible, but you need to take care to reproduce the appropriate representation and normalization. In particular, BGE-M3's normal dense output uses its trained pooling scheme, so mean-pooling token states produces a different representation.

Important: Jina v3's standard mean-pooling architecture makes late chunking conceptually straightforward, but you should still validate retrieval accuracy when combining late-chunked passage vectors with independently encoded query vectors.

##### 1.2.4.3 Licensing is a major difference

This may be decisive if SemOS becomes a commercial product.

| Model   | License      | Commercial self-hosting                    |
| ------- | ------------ | ------------------------------------------ |
| BGE-M3  | MIT          | Generally permitted                        |
| Jina v3 | CC BY-NC 4.0 | Requires separate commercial authorization |

These are the licenses published for the model weights.

##### 1.2.4.4 Recommendation for SemOS

Prioritize them as follows:

| SemOS requirement               | Preferred model       |
| ------------------------------- | --------------------- |
| Late chunking experimentation   | Jina v3               |
| English/Chinese retrieval       | Benchmark both        |
| Hybrid dense + sparse retrieval | BGE-M3                |
| Clustering and categorization   | Jina v3 worth testing |
| Commercial self-hosting         | BGE-M3                |
| Reduced embedding dimensions    | Jina v3               |
| Simple production deployment    | BGE-M3                |

One additional consideration: both models were released in 2024. Jina has since introduced newer embedding generations, so I would not automatically choose Jina v3 for a new production deployment in 2026 without comparing newer models.

For your immediate late-chunking research, Jina v3 is a sensible starting point. For production SemOS, BGE-M3 is attractive because of its permissive license and hybrid retrieval capabilities. The final choice should depend on retrieval benchmarks using your own standards and regulatory documents, not just general-purpose MTEB rankings.

#### 1.2.4.5 Custom Implementation of Late Chunking
BGE-M3's underlying transformer can produce the array $H$, but its standard embedding API does not return $H$ directly.

You need to do two things:

1. Retrieve $H$: Access the transformer model's token-level hidden states, rather than its final pooled embedding. With Hugging Face Transformers, this is typically available as `outputs.last_hidden_state`, with shape `[batch_size, sequence_length, 1024]`.
2. Calculate each chunk embedding: Identify the token positions belonging to the chunk and perform mean pooling:

$$[ E_C = \frac{1}{N}\sum\_{i=a}^{b}h_i ]$$

where $N=b-a+1$.

In production, you must align chunk boundaries with token positions and exclude special tokens and padding from pooling.

One caveat specific to BGE-M3: Its standard dense embeddings use CLS-token pooling rather than mean pooling. Therefore, this custom late-chunking implementation produces vectors using a different pooling strategy from the model's original training configuration. Retrieval quality is not guaranteed to match its standard embeddings.

So, in summary:

- Is $H$ available? Yes, through the underlying transformer.
- Do you need custom code? Yes, to access $H$, map chunks to token ranges, and pool the corresponding vectors.
- Is it complicated? No, the pooling itself is only a few lines of code.
- Will it work well? That requires benchmarking, especially because BGE-M3 was not specifically trained for mean-pooled late-chunk embeddings.

##### 1.2.4.6 Comparison of BGE-M3 and Jina Embedding 3
For BGE-M3, I would distinguish two approaches:

- Conventional chunk-based embedding: Split the document into chunks, then independently encode each chunk using BGE-M3's standard embedding method.
- Late chunking: Encode a larger document section once, obtain contextualized token vectors $H$, then pool the token vectors belonging to each chunk.

The main advantage of late chunking is better cross-chunk context. The main disadvantages are greater implementation complexity, more difficult incremental updates, and—particularly important for BGE-M3—a mismatch with its standard embedding pooling method.

**1. Pros and cons**

| Dimension                     | Conventional BGE-M3      | BGE-M3 with late chunking            |
| ----------------------------- | ------------------------ | ------------------------------------ |
| Retrieval context             | Only the chunk itself    | Context from surrounding chunks      |
| Pronoun/reference resolution  | Limited                  | Potentially better                   |
| Standard model compatibility  | Fully compatible         | Custom pooling required              |
| Retrieval quality             | Established baseline     | Must be experimentally validated     |
| Embedding computation         | Independent chunk passes | Larger shared-context passes         |
| Peak memory                   | Lower                    | Higher for long windows              |
| Incremental updates           | Re-embed changed chunks  | May need to re-embed entire windows  |
| Parallel processing           | Easy                     | Parallelism at window level          |
| Implementation                | Simple                   | Requires token alignment and pooling |
| Sparse/multi-vector retrieval | Natively supported       | Requires separate handling           |

The most important question is whether the retrieval improvements justify the additional engineering cost.

**The biggest concern: BGE-M3 uses CLS pooling**

This is the most important technical consideration.

BGE-M3's conventional dense embedding is:

$$[ E\_{\text{standard}}=\operatorname{Normalize}(h\_{\text{CLS}}) ]$$

It uses the hidden state of the special `[CLS]` token, which is trained to represent the input sequence.&#x20;

Late chunking normally uses:

$$[ E\_{\text{late}}=\operatorname{Normalize}\left(\frac{1}{N}\sum\_{i=a}^{b}h_i\right) ]$$

These are fundamentally different representations.

Although both produce 1,024-dimensional vectors, BGE-M3 was trained to use CLS pooling for its standard dense retrieval, not arbitrary mean-pooled spans.

This creates two risks:

- The late-chunked vectors might be less effective than conventional BGE-M3 embeddings.
- Query embeddings produced using CLS pooling might not align well with mean-pooled document embeddings.

The second issue is particularly important. Both vectors occupy the same dimensional space, but that does not guarantee their cosine similarity is a well-calibrated relevance measure.

The original late-chunking research demonstrates improvements for several embedding models and retrieval tasks, but that is not evidence that this particular modification improves BGE-M3.

**2. Performance: Is late chunking faster?**

Potentially, but not necessarily.

Consider a document containing 8,192 tokens, divided into 16 chunks of 512 tokens.

Conventional approach:

- 16 transformer passes, each processing 512 tokens.
- The passes can be batched together.
- Each chunk produces one embedding.

Late chunking:

- One transformer pass processing 8,192 tokens.
- Obtain 8,192 contextualized token vectors.
- Mean-pool each group of 512 token vectors.

Late chunking performs fewer forward passes, but each pass processes a much longer sequence.

For full attention, the attention-related computation scales approximately quadratically with sequence length.

Illustrative attention-score computation

16 × 512 tokens versus 1 × 8,192 tokens

05101520ConventionalLate chunking

Relative attention-score matrix elements only; not measured runtime or total transformer FLOPs.

The theoretical attention-score work is approximately 16 times greater for the single 8,192-token pass. However, actual runtime also depends on projection layers, hardware utilization, batching, and attention implementation.

Therefore, one forward pass does not automatically mean less computation.

On your M4 Pro, I would benchmark 2,048- and 4,096-token late-chunking windows before attempting the maximum 8,192 tokens.

**3. Incremental updates are another significant disadvantage**

Suppose a document has 100 chunks.

With conventional embeddings, changing C25 requires regenerating only E25.

With late chunking, if C21–C30 were contextualized together, changing C25 can change the contextualized representations of all ten chunks.

You may need to regenerate E21–E30.

This is particularly relevant for SemOS because you maintain structured knowledge extracted from documents and support incremental ingestion.

The difference is:

$$[ \text{Conventional update cost}\approx O(\text{changed chunks}) ]$$

$$[ \text{Late-chunking update cost}\approx O(\text{affected windows}) ]$$

For immutable standards and regulations, this may not matter much. For frequently updated documents, it matters considerably.

**4. What I would actually test in SemOS**

I would compare three methods, all using BGE-M3.

| Method            | Document encoding                                                | Chunk embedding                 |
| ----------------- | ---------------------------------------------------------------- | ------------------------------- |
| A. Conventional   | Independently encode C3                                          | CLS of C3                       |
| B. Contextual CLS | Encode C2 + C3 + C4, with C3 explicitly identified as the target | CLS of the contextualized input |
| C. Late chunking  | Encode C2 + C3 + C4 together                                     | Mean-pool token vectors of C3   |

Method B is an interesting alternative. It preserves BGE-M3's trained CLS pooling mechanism while providing additional context. However, it still represents the whole input sequence and relies on the model recognizing C3 as the target; this is not guaranteed without appropriate training.

Method C is genuine late chunking but introduces the pooling mismatch discussed earlier.

For a fair benchmark, I would measure Recall\@10 and nDCG\@10 on queries that require context outside the target chunk, as well as on ordinary self-contained queries. I would also measure indexing time and query latency.

**5. Recommendation**

For SemOS, I would keep conventional BGE-M3 embeddings as the production baseline, and treat late chunking as an experimental optimization.

There is a simpler alternative that I suspect may be particularly effective for your corpus:

Instead of embedding only the extracted provision:

> The equipment shall comply with the requirements of Section 5.2.

Embed an enriched representation:

> Document: ISO XXXX Section: Temperature Monitoring Equipment Equipment: Continuous temperature data logger Requirement: The equipment shall comply with the requirements of Section 5.2.

This retains BGE-M3's standard embedding behavior while incorporating explicit semantic context.

Because SemOS already extracts document structure, topics, references, and definitions, you can often construct this context without another LLM call.

Bottom line: Late chunking is conceptually attractive, but BGE-M3's CLS pooling makes it a less natural choice for the technique. I would first test contextualized conventional embeddings, then benchmark genuine late chunking to see whether it delivers additional retrieval accuracy.

== Scalability
Most vector stores require loading the entire database in memory.
This presents a serious memory problems when the vector size grows big.

In general, avoid creating a huge global vector store. Instead, organize
vectors in a hierarchy, such as through:
- Categories
- Keywords
- Topics
- And so on

=== Category
Given a query, use LLMs to generate the categories for the query and then
search the category store for the categories. If not found, we can either
use an LLM to explore the category store to the possible categories or
use a decision model to pick the possible categories.

Leaf categories contain up to maximum N vectors, where N defaults to 10,000.
If the average size of leaf nodes is 1,000, 1 billion vectors will generate
1 million categories. 

If the average inner node size is 20:
- 1 level: 20
- 2 levels: 400
- 3 levels: 8,000
- 4 levels: 160,000
- 5 levels: 3,200,000

This means that the category tree may have 5 levels.