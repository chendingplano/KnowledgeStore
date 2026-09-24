# Requirements for embedding page

- Document ID: `2026092301-requirement`
- Status: Proposed
- Date: 2026-09-23
- Audience: Product owners, subject-matter experts, designers, developers, testers, and operators

## 1. Purpose

- Let users test the embedding
- Let users test the embedding similarity
- Users can control whether to save the embedding to the database

## 2. Features

### 2.1 Page Setup
- Add the page to 'ChenWeb/development, System Admin => LLM => Embedding'
- The page style should be the same as the one 'System Admin => LLM => LLM Accounts"

### 2.2 Test Embedding

The page let's users:
- Enter content to embed. The field should be multi-line text field
- A toggle button to Save or Not Save to database
- A pulldown menu to select an embedding model. Embedding models are configured in 'ChenWeb/.models.toml'. 
  Models in 'ChenWeb/.models.toml' has an attribute: 'model_type'. Currently, it supports two values:
  'llm' for normal LLMs and 'embedding' for embedding models.
- Need to create a 'testbed.embedding_1024' to store the embedding results with dimension = 1024; 'testbed.embedding_1536' for dimension = 1536; 'testbed.embedding_768' for dimension = 768. If a model with other than these three dimensions, report errors.
- The page should have a list that lists the records in the embedding tables, with the following actions: 
  - a pulldown menu to select table
  - clear: delete all records in the currently selected table (need to prompt the user before actually them the records)
  - each record has two actions: 'delete', 'edit'.
- The embedding record list
