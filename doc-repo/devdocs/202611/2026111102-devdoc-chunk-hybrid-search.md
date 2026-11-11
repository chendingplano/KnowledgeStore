# Chunk hybrid search — retrieve original document passages

**Date:** 2026-11-11 \
**Scope:** Source-chunk indexing, long-passage retrieval, backfill and source changes. \
**Code root:** `ChenWeb/server/api/doc-processing/`, `ChenWeb/server/api/kbsearch/`, `ChenWeb/server/api/kbhandler/`

**Traceability — openspec:**
- `ChenWeb/openspec/changes/chunk-hybrid-search/proposal.md` — why this exists
- `ChenWeb/openspec/changes/chunk-hybrid-search/design.md` — implementation decisions
- `ChenWeb/openspec/changes/chunk-hybrid-search/tasks.md` — validation and implementation checklist
- `ChenWeb/openspec/changes/chunk-hybrid-search/specs/chunk-hybrid-search/spec.md` — the behavioral contract while the change remains unarchived. Update the spec when behavior changes, not just this explanation.

## Summary

Search can now return the original passages produced by document chunking. A passage can be found even if its wording was omitted from a generated topic or summary. The existing search combines matching words with similarity in meaning; chunks use that same engine and retain their source-line references.

Long passages, such as protected tables, are embedded in overlapping windows. Search uses their best matching window and returns the passage once. If the embedding service fails, word-based search still works, and embedding backfill can repair the missing vectors later.

Rechunking replaces the document's search rows together. Source rewriting, chunking and saved-chunk backfill coordinate through a per-document PostgreSQL advisory lock; a separate generation check rejects delayed writes when input paths change. Buffered text is checked against the finalized canonical file before it can become searchable. Chunk source locks hold a connection from the centralized pool across the operation, without holding a long database transaction. Waiting callers release their connections, and bounded pools admit at most half their connections as lock holders, preserving capacity for store work. Pools limited to one connection report a configuration error immediately.

## Where things live

- Search: `GET /api/v1/kb/search?q=...&artifact_types=chunk` or `/api/v1/kb/chunks/search?q=...`. Add `input_record_id` for one document. The existing Chunks list remains at `/api/v1/kb/chunks`.
- Existing documents: authenticated `POST /api/v1/kb/search/backfill-chunks?limit=20&after_record_id=0`. Use `result.next_record_id` while `result.has_more` is true; inspect `result.errors` and retry failed documents explicitly with `input_record_id`. A published document can still need embedding repair: embedding errors are best-effort.
- Storage: project migration `20261111000001_add_chunk_hybrid_search.sql` creates the chunk search partition, additional embedding windows, source generations and input-change invalidation trigger. Normal server startup runs the migration; it does not run corpus-wide embedding calls.
- Implementation: `search_indexing_chunks.go` builds source rows; `chunk_search_backfill.go` reads saved artifacts; `chunk_embeddings.go` owns atomic publication and embedding repair; `search_registry.go` merges window matches into the existing ranking.
- Reusable code: [Artifact Search](../../modules/module-artifact-search.md) and [Compact Document Lines](../../modules/module-compact-document-lines.md).

## Known limitations

- Backfill requires existing `.chunks` files and their canonical source lines. Missing or stale files are reported; boundaries are never silently rebuilt.
- Direct file edits outside the supported pipeline require explicit rechunking/reindexing. There is no filesystem watcher attached to each query.
- Retrieval examines bounded nearest-neighbor candidate lists. Several matching windows from one large chunk can reduce the number of distinct chunks considered.
- Existing low-effort result totals count lexical matches, so they can undercount passages found only by meaning.
- There is no new chunk-search frontend in this change. The API and existing global search callers can retrieve the new type.

## Validation

An opt-in `TestChunkSearchPostgresIntegration` uses a disposable database through `PG*` variables (`CHUNK_SEARCH_INTEGRATION=1`). It verifies migration up/down/up with ParadeDB and pgvector, matches beyond the first embedding window, one result per chunk, source filters, embedding recovery, generation rejection and source-lock serialization. Focused tests also cover chunking success/failure, rollback, missing/stale artifacts and stale buffered text. Broader-suite unrelated failures are recorded in the OpenSpec task log.
