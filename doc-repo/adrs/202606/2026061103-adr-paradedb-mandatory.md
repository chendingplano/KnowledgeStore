# ADR: Make ParadeDB the mandatory default lexical backend

- DocID: `doc-2026061103`
- **Status:** Implemented
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** ParadeDB, BM25, Hybrid Search

# Change Logs
- 2026/06/11, ADR created
- 2026/06/11, ADR implemented (by Claude Code)

# Decision
Make ParadeDB mandatory (refer to [1]). `SEARCH_LEXICAL_BACKEND` now defaults to
`paradedb`. To fall back to PostgreSQL tsvector, explicitly set
`SEARCH_LEXICAL_BACKEND=postgres` (or `pg` / `tsvector`).

If `pg_search` is not installed the system will fail fast at startup with a fatal
error rather than crash on the first search query.

# Implementation

**`ChenWeb/server/api/kbhandler/search_registry.go`**
- `registryLexicalBackend()`: default case changed from `lexicalBackendPostgres` to
  `lexicalBackendParadeDB`; `postgres`/`pg`/`tsvector` are the explicit opt-out values.
- `CheckParadeDBInstalled(db *sql.DB) error`: queries `pg_extension` for `pg_search`
  and returns a descriptive error if absent.
- `CheckSearchBackend(db *sql.DB) error`: startup hook — no-ops when backend is
  postgres, otherwise delegates to `CheckParadeDBInstalled`.

**`ChenWeb/server/cmd/deepdoc/main.go`**
- Calls `kbhandler.CheckSearchBackend(project_db)` immediately after migrations
  complete; calls `os.Exit(1)` on failure (loc `CWB_DDM_200`).

# References
[1] KnowledgeStore/doc-repo/202606/2026060201-hybrid-search.md
