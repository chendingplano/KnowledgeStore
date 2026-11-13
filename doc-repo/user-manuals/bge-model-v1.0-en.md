# BGE Models: A User Manual

| Field | Value |
| --- | --- |
| title | BGE Models: A User Manual |
| language | en |
| format | markdown |
| version | 1.0 |
| status | Draft |
| author | Codex |
| owner | Not specified |
| audience | People evaluating or using semantic search and document retrieval |
| create-time | 2026-11-13T10:20:24-06:00 |
| last-modify-time | 2026-11-13T10:20:24-06:00 |
| keywords | BGE, BAAI, BGE-M3, embeddings, semantic search, multilingual search, retrieval, reranking |

## What BGE can help you do

BGE is a family of models from the Beijing Academy of Artificial Intelligence (BAAI) that can help a search system find text relevant to a question. This guide focuses on **BGE-M3**, a multilingual member of the family mentioned in the workspace's embedding research. Other BGE models have different capabilities and limits; check their model cards before choosing one.

BGE is useful when a question and a relevant document use different words. For example, a search for “how long must temperature records be kept?” might find a passage about retention of monitoring logs even if that passage does not repeat the question exactly. This is an illustrative example, not a guaranteed result.

BGE-M3 is an embedding and retrieval model, not a chat assistant. It does not itself write an answer or confirm that a document is correct. A search application can use its results as material for a person or a separate answering system to review.

## Key terms

- **Embedding:** A numerical representation of text. A search system can compare embeddings to estimate how related two pieces of text are.
- **Query:** The question or phrase a person searches for.
- **Retrieval:** Finding candidate passages or documents for a query.
- **Reranking:** Reordering candidates using an additional relevance assessment. BGE rerankers are separate models.
- **Token:** A piece of text used by a model; it is not necessarily a whole word.

## How a search uses BGE

1. The application prepares documents, often dividing them into passages called chunks.
2. It uses the selected BGE model to represent those passages and stores the representations in a searchable index.
3. When someone searches, the application represents the query and compares it with the indexed passages.
4. It presents promising results, optionally after a separate reranker has reordered them.
5. The reader checks the original passage and its context before relying on it.

The application determines the interface, filters, display, privacy arrangements, and whether reranking is enabled. BGE alone does not provide a complete search application. Ask your system administrator which model and features your installation uses.

## Choosing a model and retrieval approach

BGE-M3 supports multiple languages and three retrieval representations. The application must be built to use the relevant representation; installing the model does not automatically enable every mode.

| Approach | What it looks for | When it can be useful |
| --- | --- | --- |
| Dense | Similarity between compact representations of meaning | Finding passages that use different wording from the query |
| Sparse | Weighted terms associated with the text | Finding passages where particular terms matter |
| Multi-vector | Comparisons involving multiple token-level representations | More detailed matching where the application supports it |

A search system may combine approaches. Test the choices on your own questions and documents: a more elaborate setup can require more storage or processing and does not guarantee better results for every collection.

For BGE-M3, the published dense embedding has **1,024 dimensions**, and the model card lists a maximum sequence length of **8,192 tokens**. The application may impose a lower limit or truncate text. Other BGE models have different dimensions and limits. [BAAI's BGE-M3 model card](https://huggingface.co/BAAI/bge-m3) lists the variants and specifications.

## Using a BGE-powered search

Enter a clear question or short description of the information you need. Include distinctive terms, such as an equipment type or section number, when they matter. Review the returned passage and open its source to check the surrounding text, document version, and applicability. If a result is missing, try a synonym, a more specific query, or an exact identifier; available filters depend on the application.

For a multilingual collection, try the query in the language most natural to you, then verify that the result means what you need in its original context. Multilingual support does not guarantee equal quality across all languages or subject areas.

A reranker may improve the order of the candidates already found, but it cannot recover a passage that the initial retrieval never supplied. See the [BGE reranker documentation](https://bge-model.com/Introduction/reranker.html).

## Understanding results and limits

A high similarity or relevance score is a ranking signal, not a probability that a passage is true, current, or applicable. Scores depend on the model and retrieval method; do not assume a threshold transfers between systems. Results can omit relevant material or rank an unrelated passage highly, especially for ambiguous questions, exact identifiers, or specialized language.

Check the source document rather than treating a result as an authoritative answer. If an answer is generated from retrieved passages, check the cited passages too. Confirm with your administrator where documents and queries are processed and stored before using sensitive information: privacy depends on the deployment, not on the BGE name alone.

## Common problems

| What you see | What to check |
| --- | --- |
| Relevant document is missing | Confirm it was indexed, the index is current, and your access and filters allow it; try alternate wording. |
| A long document produces incomplete results | Ask whether text was chunked, truncated, or limited before indexing. |
| Results mention the subject but miss an exact clause or identifier | Include the identifier and use an exact-term search or filter if the application offers one. |
| Results are poor after a model change | Ask whether documents were re-indexed with a compatible model and configuration; test against representative queries. |
| A foreign-language result seems close but uncertain | Read the original context and seek a reliable translation or subject expert. |

## Further reading

- [BAAI BGE-M3 model card](https://huggingface.co/BAAI/bge-m3): published capabilities, specifications, and usage details.
- [BGE documentation on rerankers](https://bge-model.com/Introduction/reranker.html): how reranking fits into retrieval.
- Workspace research: `KnowledgeStore/Research/embedding.md` discusses BGE-M3 and experimental late chunking. Late chunking requires custom handling and should be evaluated against ordinary embeddings for the actual collection.

## Change Log

| Version | Timestamp | Author | Reason and summary |
| --- | --- | --- | --- |
| 1.0 | 2026-11-13T10:20:24-06:00 | Codex | Initial manual explaining BGE and BGE-M3 for search users. |
