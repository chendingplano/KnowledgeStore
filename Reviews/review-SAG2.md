---
Date: 2026/11/06
Last Updated: 2026/11/08
Contributors: ChatGPT, Chen Ding, Claude Code
---

# Paper Review: SAG2 — Embedding-Free Multi-Hop Retrieval with BM25 and JEV

Yuchao Wu · Zleap AI · arXiv v1, October 15, 2026

Paper: [arXiv:2610.22588](https://arxiv.org/abs/2610.22588) ([HTML version](https://arxiv.org/html/2610.22588v1))\
Code: [SAG-Benchmark GitHub repository](https://github.com/Zleap-AI/SAG-Benchmark)

> **Verdict for SemOS (2026-11-08).** Do not adopt SAG2 as a whole, and do not drop vector
> search. Two of its concepts are worth testing inside our hybrid search
> ([2026060201-spec-hybrid-search](../doc-repo/specs/202606/2026060201-spec-hybrid-search.md)):
> scoring each candidate against the evidence found so far, and expanding the search with
> terms taken from the best candidates. Test them as a separate, higher-effort search mode, on a
> multi-hop benchmark we still have to build. See §6–§8.

## 1. Executive summary

SAG2 proposes a retrieval architecture that achieves strong multi-hop retrieval accuracy without
embeddings, a vector database, a precomputed knowledge graph, or LLM-based knowledge extraction
during ingestion.

Instead, it combines three components:

- **SQLite FTS5 + BM25:** lightweight lexical indexing and candidate retrieval.
- **JEV:** a hosted decision model (`typesafe/jev-1.13`, called through OpenRouter's decisions
  API) that answers, for each candidate passage, whether it is necessary evidence for the
  question. It is the same Jev family SemOS can already call (§6.1).
- **Iterative retrieval expansion:** rare terms from the best-scoring passages become new BM25
  queries, which find connected passages and progressively assemble an evidence chain.

The loop is implemented inside the search engine, not by an agent. It runs a fixed number of
rounds within a fixed judgment budget.

The central insight is that semantic understanding can be moved from document ingestion to query
time.

Traditional RAG systems perform substantial preprocessing, including generating embeddings and
potentially extracting entities, relationships, or knowledge graphs. SAG2 stores original text with
a lexical index and performs semantic evidence evaluation only when answering a query.

Its ingestion is simply storing chunks in a database with a full-text (BM25) index. The author uses
SQLite; SemOS uses PostgreSQL with ParadeDB. The concepts are the same. Plain PostgreSQL can insert
thousands of chunks per second, so ingestion in SAG2 is not an issue. One caveat for ParadeDB: bulk
rewrites land in mutable segments and slow BM25 down until the index is rebuilt (hybrid search spec
§12.1, handled by the hourly `maintain_bm25_indexes` job).

Reported results (Recall@10, %, 1,000 questions per dataset):

| Benchmark       | Passages | BM25  | NV-Embed-v2 | HippoRAG 2 | SAG   | SAG2  |
| --------------- | -------- | ----- | ----------- | ---------- | ----- | ----- |
| MuSiQue         | 11,656   | 54.41 | 77.27       | 73.76      | 83.37 | 86.62 |
| 2WikiMultiHopQA | 6,119    | 71.50 | 80.75       | 93.40      | 93.57 | 97.43 |
| HotpotQA        | 9,811    | 86.90 | 97.70       | 97.15      | 97.70 | 99.00 |

SAG2 has the highest Recall@5 and Recall@10 of the systems compared, including dense retrievers,
HippoRAG 2 and the original SAG. The margins over SAG are smaller than they first look:

- On MuSiQue, SAG2 leads SAG by only 0.32 points at Recall@5 (80.68 vs 80.36), and SAG is better at
  Recall@1 and Recall@2 (36.82 / 63.62 vs 34.30 / 62.18).
- The baseline numbers are copied from the earlier SAG paper, not re-run.
- The paper states that MuSiQue "was also used during method development".

On the much larger EnterpriseRAG-Bench (511,962 synthetic documents, 470 scored questions), document
Recall@10 was SAG2 81.1, BM25 68.4, vector search 46.0 and a Bash agent 55.8. It is the paper's only
large-scale result.

The interesting contribution is not simply replacing vector search with BM25. It is showing that
iterative, evidence-guided candidate discovery can matter more than better one-shot similarity
search.

## 2. How SAG2 works

SAG2 implements an iterative retrieval process in which each round uses evidence discovered in
previous rounds to find additional evidence.

![How SAG2 works](../Images/image_2026110601.png)

```text
  User question: original query
            ↓
  BM25 retrieval: initial 100 candidates
            ↓
  JEV evidence scoring: contextual relevance decisions   ←┐
            ↓                                             │ repeat up to 2 times
  Term-based expansion: select bridge terms and retrieve ─┘
            ↓
  Final evidence ranking: top passages for downstream LLM
```

Conceptual retrieval workflow. JEV evaluates evidence in successive rounds, while BM25 discovers
candidates through lexical connections.

### Step 1: Retrieve initial candidates using BM25

The original question is tokenized (Jieba plus handling of connected Latin tokens, NFKC
normalization, lowercasing and a fixed English/Chinese stopword list). Up to 80 distinct tokens are
OR-joined into one SQLite FTS5 query. No LLM is used, for example to extract keywords from the
query. (SemOS, by contrast, uses LLM query keywords; spec §8.1.)

The system retrieves the top 100 (configurable) matching passages. The top 5 BM25 passages always
stay in the candidate pool.

Its lexical index uses three weighted fields (heading is empty in the benchmarks):

| Field   | BM25 weight |
| ------- | ----------- |
| Title   | 2           |
| Heading | 2           |
| Body    | 1           |

No embeddings or neural models are needed at this stage.

### Step 2: Evaluate candidates using JEV

For each candidate passage, JEV answers one yes/no question: *"Is this candidate itself necessary
evidence in a fully supported answer chain for original_question?"* The probability of "yes" is the
score:

$$ s_r(d)=J(q,d;E_r)\in[0,1]$$

Where:

- $q$: original question
- $d$: candidate passage (title, heading if any, body)
- $E_r$: shared context for round $r$
- $s_r(d)$: evidence score

Scoring is pointwise (one score per candidate), but many candidates travel in one HTTP request.

The shared context is small and changes per round:

- Round 0: empty.
- Round 1: the seed passages kept from round 0 plus the first 10 new candidates.
- Round 2: the previous top 10 with their tentative scores.

An important distinction is that JEV is not evaluating semantic similarity. It evaluates whether a
passage supplies a necessary fact in a supported reasoning chain, including intermediate facts.

For example, consider the question:

> Which county contains the birthplace of person X?

The first relevant passage may identify the person's birthplace. A second passage may identify the
county containing that location.

The second passage may have almost no lexical overlap with the original question, but becomes
relevant once the birthplace is known. JEV can judge this relationship through the shared context.

JEV's architecture, parameter count and weights are not public.

### Step 3: Select expansion terms

This step is critical. SAG2 takes up to 10 high-scoring passages ("seeds") that have not yet been
used for expansion and extracts candidate terms from them: single tokens and multi-word names (runs
of capitalized words). There is no named-entity recognition. Each term gets a priority:

$$ a_r(t)=\max_{d \in \text{seeds}} \big(1+\log tf(t,d)\big)\cdot I(t)\cdot\big(1+g_q(t,d)\big)\cdot w_r(d)$$

- $tf(t,d)$: term frequency in the seed passage.
- $I(t)$: BM25-style inverse document frequency over body text (rarer terms weigh more).
- $g_q(t,d)$: overlap between the term's sentence and the question (the summed rarity of shared
  question tokens, best sentence).
- $w_r(d)=0.5+0.5\cdot s_r(d)/m_r$: the seed's JEV score relative to the round's best score $m_r$.

Terms made only of question tokens, and terms that occur in no document, are skipped. The top 20
(configurable) terms are used.

This is particularly important: JEV decides which passages are useful, but lexical statistics
decide which terms are used to find more passages. No LLM writes a new query.

### Step 4: Retrieve additional passages

Each selected term triggers a BM25 search. The results are interleaved by term rank and
deduplicated, up to 100 new candidates per round.

The new candidates are scored by JEV with the original question and the shared context.

### Step 5: Repeat and return evidence

SAG2 runs up to two expansion rounds, so at most three JEV scoring rounds. The budget is at most 340
passage judgments per question, including re-judgments; the observed average on MuSiQue was 331.

The final passages are ranked by JEV score (up to 100 returned). A greedy diversity rule (JEV score
plus TF-IDF overlap) then reorders the top ten only. It keeps the first result and the top-ten set,
so it can change Recall@5 but not Recall@10.

This is a bounded retrieval algorithm, not an open-ended autonomous agent. (The repository README
also reports an "Agentic SAG2" variant at MuSiQue Recall@10 95.39; it is not in the paper.)

## 3. Why iterative expansion matters

The paper's ablations on MuSiQue (%, 1,000 questions):

| Variant                          | R@5   | R@10  | All evidence @10 | Judgments |
| -------------------------------- | ----- | ----- | ---------------- | --------- |
| BM25                             | 47.47 | 54.41 | 17.40            | 0         |
| BM25 + JEV rerank only           | 60.78 | 67.93 | 36.00            | 99,925    |
| SAG2, 1 expansion                | 77.89 | 83.36 | 63.10            | 211,081   |
| SAG2, 2 expansions               | 80.68 | 86.62 | 69.50            | 331,325   |
| One-shot BM25 + JEV, same budget | 61.57 | 69.82 | 39.60            | 329,194   |
| SAG2 without shared context      | 66.32 | 76.25 | 52.20            | 330,990   |

"All evidence @10" is the share of questions whose supporting passages are all in the top 10.

![Evaluation Results](../Images/image_2026110602.png)

Three findings stand out.

First, JEV reranking alone is insufficient. Adding JEV to the initial BM25 results raises Recall@10
from 54.41% to 67.93%, but it cannot recover supporting passages missing from the original
candidate pool. In the full SAG2 output, 389 of the 1,000 questions have a supporting passage that
was outside the initial BM25 top 100.

Second, expansion produces the largest improvement. One expansion raises Recall@10 by 15.43 points,
to 83.36%. A second adds 3.26 points, to 86.62%.

Third, shared context is critical. Removing it from JEV's judgments drops Recall@10 from 86.62% to
76.25%.

The paper also compares SAG2 with one-shot BM25+JEV at about the same number of judgments (about
330,000): 86.62% vs 69.82%.

This is strong evidence that the improvement comes from discovering better candidates, not merely
from evaluating more of them.

Results by number of hops (MuSiQue, Recall@10):

| Hops | Questions | BM25  | SAG2  | SAG2 all evidence @10 |
| ---- | --------- | ----- | ----- | --------------------- |
| 2    | 518       | 61.68 | 92.86 | 87.07                 |
| 3    | 316       | 51.37 | 85.34 | 62.34                 |
| 4    | 166       | 37.50 | 69.58 | 28.31                 |

## 4. Infrastructure and computational costs

The paper reports the following results on MuSiQue:

- Index construction: 2.36 seconds for 11,656 passages (median of three builds, Apple M4 Pro,
  eight processes)
- SQLite index size: 25.87 MiB
- No stored embeddings
- Offline model cost: $0, no model calls during indexing
- Online model cost: $4.33 per 1,000 queries (JEV charges only)

That is about $0.0043 per query.

No latency is reported: the paper says service waiting time "was not separated from concurrent
execution". The cost figures exclude answer generation and machine rental.

## 5. Limitations

Despite the strong results, there are important qualifications.

**Dependence on JEV.** JEV is a hosted service: questions and candidate text are sent to it, and its
weights and architecture are not public. The paper calls the decision model "the principal
deployment limitation". SAG2 is embedding-free, but not neural-model-free or necessarily local.

**Lexical connectivity remains essential.** If two relevant passages share no useful terms, the
expansion may never connect them. Synonyms, aliases, abbreviations and cross-language terminology
are problems.

**No non-English evaluation.** The tokenizer handles Chinese (Jieba), but no Chinese or
cross-language benchmark was run.

**Multi-hop retrieval remains hard.** On MuSiQue four-hop questions, SAG2 reaches 69.58% Recall@10,
but only 28.31% of those questions have all supporting passages in the top 10.

**Retrieval, not answer quality.** The paper does not test whether the retrieved evidence improves
answer accuracy, reasoning correctness or hallucination rates.

**Comparisons are not fully controlled.** Baselines come from earlier papers, with different models
and compute budgets. MuSiQue was used during development, and there is no held-out split or private
corpus. The benchmark subsets are small (1,000 questions each), the larger EnterpriseRAG-Bench
corpus is synthetic, and its Bash agent baseline was not given equal compute.

## 6. Implications for SemOS

The question is whether SAG2 should be integrated with the hybrid search engine
([2026060201-spec-hybrid-search](../doc-repo/specs/202606/2026060201-spec-hybrid-search.md)): either
replace it with a lightweight index for candidate discovery that does not rely on a global vector
index, or borrow parts of it.

### 6.1 What SemOS already has

| SAG2                                         | SemOS today                                                                                                                                  |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| BM25 with the Jieba tokenizer                | The same: ParadeDB `pg_search` BM25 with Jieba (spec §8, §12)                                                                                |
| True per-field weights (title/heading/body)  | Approximated by repeating fields in one `search_document` (spec §7)                                                                          |
| No LLM on the query                          | LLM query keywords; BM25 Recall@10 0.47 → 0.80 (spec §8.1)                                                                                   |
| —                                            | Vector search (bge-m3) fused with RRF; vector alone 0.95 on the metric benchmark (spec §13.1)                                                |
| Bounded loop of rounds                       | Effort levels: medium 2, high 5 attempts (spec §8.3)                                                                                         |
| Each candidate scored with shared context    | Not done. The effort judge answers once for the top 10 fused results ("found?" plus matching IDs)                                           |
| JEV                                          | Jev provider ([devdoc 2026092501](../doc-repo/devdocs/202609/2026092501-devdoc-jev-provider.md)) and `jev_emulated` on any chat model ([devdoc 2026100502](../doc-repo/devdocs/202610/2026100502-devdoc-jev-emulated-decision-model.md)); not used by search yet |
| Term expansion from high-scoring passages    | Not done. The effort loop asks an LLM to write new queries                                                                                   |
| —                                            | Links SAG2 lacks: cited documents (`kb.ref_mentions`), artifact connections (`kb.metric_conns`, `kb.topic_conns`), the keyword lexicon      |

### 6.2 Why not replace hybrid search with SAG2

- **Cross-language queries.** SAG2 starts from a raw BM25 search. On our data, English queries over
  Chinese documents reach Recall@10 0.20 with raw BM25 (spec §8.1). If that first search misses,
  expansion has nothing to start from, and the paper has no cross-language evaluation. Vector search
  covers this gap today.
- **Our numbers point the other way.** On our metric benchmark, vector alone scores 0.95 and BM25
  with query keywords 0.80. That benchmark favours vector search by construction, but it is still
  the opposite of SAG2's premise.
- **The cost saving does not apply to us.** SAG2 saves by not running an LLM during ingestion. SemOS
  extracts artifacts with LLMs anyway, because the artifacts are the product. Embedding them with a
  local bge-m3 costs little next to that.
- **Our search units are smaller.** Term expansion needs passages with enough text (about 1,000
  characters in the paper's enterprise setup). Our units are extracted artifacts. Metric rows are
  short (label, value, condition) and offer few terms to expand on; scene blocks, provisions and
  summaries are closer to passages. There is no raw chunk partition in `kb.search_artifacts`.

### 6.3 Concepts worth adopting

#### A. Separate candidate discovery from evidence judgment

SAG2 makes a clean distinction between two operations:

- Candidate discovery: BM25 and lexical expansion.
- Evidence judgment: JEV evaluates how each candidate contributes to the current question.

For SemOS, this separation could be extended further:

| SAG2                    | Possible SemOS equivalent                                                       |
| ----------------------- | ------------------------------------------------------------------------------- |
| SQLite FTS5             | Hybrid search: ParadeDB BM25 + pgvector, fused with RRF                         |
| Original passages       | Artifacts in `kb.search_artifacts`: scene blocks, provisions, summaries, metrics |
| Expansion terms         | Keywords, aliases, entities, document references                                |
| JEV evidence scores     | Jev or `jev_emulated` evidence questions                                        |
| Shared evidence context | Investigative retrieval state                                                   |
| Passage expansion       | Keyword, metadata, category, reference and graph traversal                      |

#### B. Contextual evidence scoring

This fills the spec's open item "LLM / cross-encoder reranking" (§13). Ask each candidate one Jev
yes/no question — is it necessary evidence for the question, given the evidence found so far? —
and rank by the probability of "yes". This differs from the current effort judge, which answers
once for the top 10 and gives no per-candidate score.

The paper's ablations show both halves matter: per-candidate scores make expansion possible, and the
shared context is worth about 10 points of Recall@10.

#### C. Evidence-guided expansion, extended with structured links

This fills the spec's open item "graph-traversal expansion" (§13). SAG2 expands only through shared
lexical terms. SemOS already has richer associations: normalized keywords and aliases, cited
documents, artifact connections, categories and metrics.

For example, two passages might describe the same concept in different words. SAG2 may fail to
connect them for lack of lexical overlap; SemOS could connect them through a canonical keyword or
alias, or through a cited document, without embeddings.

Expansion stops when the evidence is sufficient or the budget is exhausted. This keeps SAG2's
lightweight retrieval philosophy while exploiting the structured information SemOS already maintains.

#### D. Investigative retrieval matters more than one-shot ranking

This is the most significant architectural lesson.

SAG2's results suggest that retrieval quality depends not only on how accurately a system ranks
passages, but also on whether the retrieval process can discover evidence that was initially
invisible to the search query.

That distinction is especially important for standards and regulations, where answering a question
may require following definitions, cross-references, exceptions, requirements and dependencies
across documents.

SAG2 provides experimental support for a bounded investigative retrieval loop, although the paper
does not show the same gains on standards or regulatory corpora.

### 6.4 Proposed design (if the experiment is positive)

1. **Start from the current hybrid RRF results**, not BM25 alone. Vector search covers the
   cross-language gap that would break SAG2's first step.
2. **Score candidates with a Jev evidence question** through the existing provider, with a small
   shared context like SAG2's.
   - Real Jev batches candidates into one request and cost about $0.004 per query in the paper.
   - `jev_emulated` makes one chat call per question per candidate — about 340 calls per search at
     its default concurrency of 4 — which is far too slow without batching.
3. **Expand from the top-scoring artifacts** with SAG2's term-priority formula on our BM25
   statistics, plus reference, connection and lexicon links.
4. **Expose it as its own effort level or Knowledge Desk agent tool**, not as the default
   `/kb/search`. Three scoring rounds put it in the same latency range as `effort=high` (20–27 s
   when all attempts run).

## 7. Recommended experiment

**Prerequisites:**

- **Clean the stale index rows.** On 2026-10-25, 5,621 of the 8,281 metric index rows belonged to
  records with no `kb.metrics` rows (spec §13.2). They would distort any measurement.
- **Build a multi-hop question set.** The live benchmark's generated questions have hop types, but
  each still targets exactly one metric, and `effort=high` already puts 10 of 12 sampled targets at
  rank 1. SAG2's gains come from finding the second and third hop, so we need questions that need
  two or more supporting artifacts (for example provision → cited standard → metric). Score them on
  recall of all supporting artifacts and on "all evidence in the top 10", as the paper does.

**Arms**, compared at a matched number of judgments (the paper's strongest control):

1. Current hybrid search (`effort=low`).
2. Hybrid + Jev evidence scoring, no expansion.
3. Hybrid + Jev + one and two term-expansion rounds.
4. Arm 3 plus structured expansion (references, connections, lexicon).
5. `effort=high`, as the existing iterative baseline.

Record latency and model cost per question alongside recall. Set the adoption bar before running:
a clear gain in all-evidence recall on multi-hop questions, acceptable latency and cost, and no
regression on the existing single-target questions.

## 8. Overall assessment

SAG2 is a meaningful contribution because it challenges two common assumptions in modern RAG
architecture:

1. High-quality retrieval necessarily requires embeddings.
2. Multi-hop retrieval necessarily requires a precomputed knowledge graph.

The paper shows that neither is strictly necessary for strong evidence recall on its benchmarks. Its
evidence is weaker than the headline suggests: one author, tuned partly on its own test set, copied
baselines, a hosted decision model, and no non-English or private-corpus results.

Embeddings and knowledge graphs are not obsolete. Rather, SAG2 shows that contextual evidence
evaluation and iterative candidate discovery can compensate for much of what expensive
preprocessing traditionally provides.

For SemOS, the decision is to keep the hybrid search and not adopt SAG2 as a whole. We will test its
two useful concepts — contextual evidence scoring and evidence-guided expansion, extended with our
structured links — as a higher-effort mode, on a multi-hop benchmark (§7).

The central takeaway is:

Index cheaply, retrieve iteratively, and use semantic reasoning to guide evidence discovery rather
than trying to encode all semantic relationships before queries arrive. For SemOS: keep the hybrid
index, and add the iterative, evidence-guided loop on top of it.

## Appendix: Verification notes

- Checked on 2026-11-08 against the arXiv HTML v1 (Sections 1–5 and Appendices A–B), the repository
  README, and part of `sag2/scripts/sag2.py`.
- Not checked: Appendix C (parameter table, exact JEV instruction) and Appendix D (token accounting).
  The PDF text could not be extracted.
- The README's numbers differ slightly from the paper's (BM25 Recall@10 54.50 vs 54.41; SAG2 86.61
  vs 86.62). This review uses the paper's numbers.
