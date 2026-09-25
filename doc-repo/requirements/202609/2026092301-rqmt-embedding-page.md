# Requirements for embedding page

- Document ID: `2026092301-rqmt`
- Status: Implemented and Tested
- Date: 2026-09-23
- Audience: Product owners, subject-matter experts, designers, developers, testers, and operators

## 1. Purpose

- Let users test embedding models and inspect their vectors.
- Let users search for similar saved embeddings and compare saved vectors pairwise.
- Let users control whether generated embeddings are saved to the database.

## 2. Features

### 2.1 Page Setup

- Add the page at `ChenWeb/development, System Admin => LLM => Embedding`.
- Match the page style to `System Admin => LLM => LLM Accounts`.

### 2.2 Model Selection and Input Limits

- Read embedding model entries from `ChenWeb/.models.toml`; list entries where `model_type = "embedding"`.
- Each model entry supplies `model_name`, `dimension`, and optionally `max_chars`.
- `dimension` must be 768, 1024, or 1536. Reject other dimensions with an error.
- `max_chars` controls the maximum Unicode character count accepted for the input. If omitted or zero, use 6000. Show the remaining allowance as **Remaining Bytes** and prevent submission when the input exceeds the limit.
- Send provider-specific output-dimension parameters only when supported. Check the returned vector length against the configured dimension.

### 2.3 Generate Embeddings

- Provide a multi-line content field and a **Save embedding to database** checkbox.
- Generate an embedding for the selected model. Save the result only when the checkbox is selected.
- Attribute embedding calls to the authenticated user and record the call reason and location for hosted and locally hosted models.

### 2.4 Similarity Search

- Allow users to search saved vectors using the content field and selected embedding model.
- Search only records in the matching dimension table that were embedded with the same `.models.toml` model key; vectors from different model keys are not comparable, even if their dimensions match.
- Provide a configurable **Top N** result count, defaulting to 10.

### 2.5 Embedding Tables and Metrics

Create these tables in the `testbed` schema:

| Table | Vector dimension |
| --- | ---: |
| `testbed.embedding_768` | 768 |
| `testbed.embedding_1024` | 1024 |
| `testbed.embedding_1536` | 1536 |

Each table stores the model key and name, source content, embedding vector, and creation/update timestamps. It also stores:

- `time_ms`: elapsed time for the embedding client call, including rate-limit waiting and the provider request.
- `num_chars`: Unicode character count of the submitted content.
- `num_tokens`: provider-reported input token count when available; otherwise use the shared embedding token estimator.

New, edited, and regenerated records populate these metrics. Existing records receive zero defaults when the metrics migration is applied; historical content is not re-embedded automatically.

### 2.6 Embedding Records

- List records from the table selected by the selected model's dimension.
- Filter records by model key/name and paginate the list (20 records per page).
- **Clear records** deletes every record in the currently selected dimension table, regardless of model key. Prompt for confirmation first.
- Each record supports **Delete**, **Edit**, and **Regenerate**. Editing content regenerates the vector and metrics. Regenerate embeds the existing content again.

### 2.7 Pairwise Comparison

- Provide a checkbox column for selecting up to five records.
- Compare every selected pair using cosine similarity. At least two records are required.
- Only records embedded with the selected model key can be selected for comparison.

## 3. Known Limitations

- Storage tables support only dimensions 768, 1024, and 1536.
- Model-key scoping is intentional: separate `.models.toml` keys are treated as different embedding spaces even if they refer to the same provider model.
- Token counts are estimates when a provider does not report usage. Historical records keep zero metric values until regenerated.
