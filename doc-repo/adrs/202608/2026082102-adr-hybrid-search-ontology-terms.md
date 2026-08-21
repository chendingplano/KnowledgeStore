# ADR 2026082102 — Hybrid Search for `kb.ontology_terms`: A Dedicated Lexical + Semantic Index Over the Governed Term Catalog

**Date:** 2026-08-21 \
**Status:** Proposed \
**Component:** ChenWeb — `kb.ontology_terms`, `kb.ontology_term_labels`, `server/api/ontology/terms/`, `server/api/ontology/names/resolver.go`, `server/api/kbsearch/`, `server/api/kbhandler/` \
**Authors:** Chen Ding (with Claude) \
**Tags:** ontology, hybrid search, governed terms, pgvector, tsvector, RRF

## 1. Change Logs

* 2026/08/21, ADR created. Proposes hybrid (lexical + semantic, RRF-fused) search over
  the governed term catalog, following the same fusion pattern already implemented and
  accepted for `kb.search_artifacts` (spec `2026060201`), but as a separate, dedicated
  index rather than a new `kb.search_artifacts` partition — see DR1/DR2 for why.

## 2. Context

### 2.1 The catalog has no way to be found except by exact string equality

`kb.ontology_terms` (created `20260731000014`) is the governed vocabulary of the
ontology platform (ADR `2026072901`): classes, properties, quantity kinds, units,
dimensions, and — since ADR `2026081201` — auto-promoted `metric_definition` terms.
Human-readable text lives one join away, in `kb.ontology_term_labels`
(`prefLabel`/`altLabel`/`hiddenLabel`, per-language). Today, the **only** way any code
path finds a term by name is `names.Resolver`'s `releasedTermSQL`
(`server/api/ontology/names/resolver.go:400`): pull every label row for the requested
`term_kind`/`module_id`/`lang`, and compare **in Go** against a full NFKC-normalized,
case-folded key. The code's own comment is explicit that this is deliberate and
incomplete: "never SQL `LOWER`... and never `Exact` (trim-space only)" — not even
case-insensitive `ILIKE`, let alone partial match, ranking, or synonym expansion beyond
whatever literal `altLabel` rows exist. Two terms colliding on the same normalized key
are treated as ambiguous and the match is withheld outright.

That design is *correct* for what it is used for today: `EnsureAcceptedOrCreate`
(alignment.go) and `MatchUnitLabel` both need a yes/no "does an already-released term
exist for this exact surface" answer to decide whether to create a new governed term —
ADR `2026081201` DR1 states this outright: "Concept→term resolution is a deterministic
existence check... not a second fuzzy-matching pass." **This ADR does not change that
path.** The gap is elsewhere: there is no way for a *human* — or any tool assisting a
human — to search the catalog by meaning. `ListOntologyTerms`
(`kbhandler/ontology_terms_handler.go`) filters only by `module_id`/`status`, no `q`
parameter exists anywhere.

### 2.2 The catalog is big enough, and messy enough, that this now matters

Two facts, both already on the record in sibling ADRs, establish that exact-match
findability has stopped being adequate:

- **Scale.** ADR `2026081201` §4 retracts the original "a domain has on the order of
  hundreds of terms" assumption (ADR `2026072901` §3.24/DR23): auto-promoted
  `metric_definition` terms now grow **roughly 1:1 with distinct concepts
  encountered**, not a bounded catalog size. Separately, the QUDT import already
  contributes 2,843 units + 1,125 quantity-kinds + 245 dimensions (4,213 terms) under
  the `quantity` module, plus 20 `core` terms.
- **Quality.** ADR `2026081701` §2.1's 2026-08-17 production survey found 182
  auto-promoted `metric_definition` terms, of which 55 are label-only (no definition,
  no permitted units) and only 7 have permitted units recorded. ADR `2026081201` §5 OD2
  asks, unresolved: *"Does reconciliation need to merge/relink terms, not just
  concepts?"* — an open admission that auto-created terms can already be duplicating
  one another with no tool to find the duplicates.

Both problems are retrieval problems: a curator (or a future reconciliation job) needs
to ask "is there already a term that means roughly this?" and get ranked candidates
back — synonyms, near-misses, and Chinese/English gaps included — not a binary
exact-match miss.

### 2.3 Precedent already exists, one layer down

ADR `2026072901` §4.6 (AD6) and its 2026/08/08 changelog confirm that `pg_trgm` +
`pgvector` are already installed server-wide and that tier-5 (trigram fuzzy) and tier-6
(offline multilingual embedding) matching are real, working code — but scoped entirely
to the **keyword lexicon** (`kb.keyword_concepts`), never to `kb.ontology_terms`. The
platform's own terminology contract (`2026072901` §3.16) already classifies
"search/embedding similarity" as legitimate **candidate-generation evidence that never
activates identity** — the same posture this ADR takes: search surfaces candidates for
a human (or a future reconciliation tool) to act on; it does not decide identity itself.
That non-authoritative framing also matches DR7 of ADR `2026072701`: "search and graph
tables are derived projections... not the system of record."

## 3. Decision

### DR1 — Scope: retrieval only, over `kb.ontology_terms` proper; not a new resolution path, not a new identity source

This ADR adds a **find-by-meaning** capability for humans and future tooling to browse
and search the governed catalog. It explicitly does **not**:

- change `names.Resolver`'s exact-match term-creation/alignment path (ADR `2026081201`
  DR1 stands unmodified — deterministic existence checks stay deterministic);
- decide term or concept identity — a search hit is a suggestion, never an automatic
  merge or activation (consistent with `2026072901` §3.16);
- cover `kb.ontology_candidates` (pre-promotion candidates still awaiting review) —
  searching the candidate queue for pre-promotion duplicate detection is a related but
  separate capability, noted as OD1 below and left out of scope here to keep this ADR
  to the catalog the user named.

### DR2 — A dedicated `kb.ontology_term_search` table, not a new `kb.search_artifacts` partition

**Alternative considered and rejected:** add `ontology_term` as a new `artifact_type`
partition of `kb.search_artifacts`, reusing its RRF machinery directly. Rejected
because `kb.search_artifacts.input_record_id BIGINT NOT NULL REFERENCES kb.inputs(id)`
(`20260522000002`) has never been relaxed in any migration, and for good reason — every
existing artifact type is extracted *from* one source document. Governed terms are not:
QUDT-imported terms have no source document at all, and an auto-promoted
`metric_definition` term is synthesized from a *triggering* metric occurrence but
represents a concept that may recur across arbitrarily many documents. Forcing a
sentinel `input_record_id` to satisfy the constraint would misrepresent what the row
is. `kb.ontology_terms`/`kb.ontology_term_labels` remain the system of record either
way (DR7, ADR `2026072701`); the cleaner projection is a table shaped for what it
actually indexes.

**Decision:** a new, dedicated, rebuildable table:

```sql
CREATE TABLE kb.ontology_term_search (
    id              BIGSERIAL PRIMARY KEY,
    term_id         TEXT NOT NULL UNIQUE,
    version         INT NOT NULL,
    term_kind       TEXT NOT NULL,
    module_id       TEXT NOT NULL,
    status          TEXT NOT NULL,
    search_document TEXT NOT NULL,
    search_vector   tsvector GENERATED ALWAYS AS (to_tsvector('simple', search_document)) STORED,
    embedding_text  TEXT,
    embedding       vector(1536),
    create_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    modify_time     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_kb_ontology_term_search_vector    ON kb.ontology_term_search USING GIN (search_vector);
CREATE INDEX idx_kb_ontology_term_search_embedding ON kb.ontology_term_search USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_kb_ontology_term_search_module    ON kb.ontology_term_search (module_id, status);
```

One row per `term_id` (unique), always reflecting the current indexable version —
reindexing does `INSERT ... ON CONFLICT (term_id) DO UPDATE`, not append. `superseded`
and `rejected` terms are **not** indexed (dead ends; excluded at reindex time). Every
other status — `draft`, `in_review`, `approved`, `included_in_release`,
`auto-promoted` — **is** indexed, deliberately wider than the resolver's
`included_in_release`/`auto-promoted`-only filter: a curator reviewing a new candidate
needs to search against terms still in review too, not only already-live ones. `status`
is returned so callers can filter narrower (e.g. a public-facing consumer would filter
to `included_in_release`/`auto-promoted` only; that's a query-time `WHERE`, not an
indexing-time decision).

### DR3 — `search_document` composition

Built at reindex time from `kb.ontology_terms.{definition, scope}` plus every
`kb.ontology_term_labels` row for that `term_id` (all languages, all label roles),
mirroring the repeat-weighting convention `entities_search_weights` etc. already
establish in `config.toml`:

```toml
[ontology_terms_search_weights]
pref_label   = 2.0
alt_label    = 1.6
hidden_label = 1.0
definition   = 1.2
scope        = 0.8
```

`prefLabel` (the canonical name) is weighted highest; `altLabel` rows — the SKOS
synonym slot — are the main lever for closing the synonym/Chinese-English gaps §2.1
describes, since they already exist in the schema today but are invisible to any
scoring mechanism until now.

### DR4 — Write path: reindex on every write to `kb.ontology_terms`/`kb.ontology_term_labels`

A single choke point, `ReindexOntologyTermSearch(ctx, db, termID)`
(proposed: `server/api/ontology/terms/search_indexing.go`), called from every site that
creates or changes a term or its labels:

- `candidates.PromoteToContent` (`ontology/candidates/promote.go`) — the human-reviewed
  promotion path.
- `keywords.AlignmentsStore.EnsureAcceptedOrCreate` (`ontology/keywords/alignment.go`)
  — the auto-promotion path (ADR `2026081201` DR1/DR3).
- Any future admin term/label edit endpoint (none exists yet).

Embedding follows the existing best-effort contract from `kbsearch.embedRegistryRows`:
gated by the existing `SEARCH_SEMANTIC_ENABLED` flag (`kbsearch.SemanticSearchEnabled()`
— **no new flag**, this reuses the same capability switch and the same
`EMBEDDING_MODEL_NAME`/`EmbeddingDim=1536` as `kb.search_artifacts`), truncated the same
way, and never fails the caller — a failed or disabled embed leaves `embedding` NULL
and the row still fully lexically searchable.

### DR5 — Read path: RRF fusion, same shape as `queryHybridSearchResults`, tsvector-only lexical backend

New query function mirroring `kbhandler.queryHybridSearchResults`'s two-CTE structure
exactly: a lexical CTE (`search_vector @@ tsquery`, `ts_rank_cd`, `ROW_NUMBER()`) and a
semantic CTE (`embedding IS NOT NULL`, ordered by `embedding <=> $query_embedding`,
`ROW_NUMBER()`), `FULL OUTER JOIN`ed on `term_id` with the identical RRF formula and
constant, `rrfK = 60`. Given `kb.ontology_term_labels` carries `lang` explicitly and the
project's documents are bilingual, the lexical CTE reuses the existing
`containsCJKText` + `ILIKE` fallback (`kbhandler/search_registry.go`) rather than
relying on `to_tsvector('simple', ...)` alone, which under-tokenizes CJK text — the
same reason that fallback exists for `kb.search_artifacts`.

**Lexical backend: plain PostgreSQL `tsvector`, not ParadeDB.** `kb.search_artifacts`
defaults to ParadeDB BM25 because that registry spans the full document corpus; the
ontology term catalog is thousands of rows, not the corpus's scale, so BM25's operational
cost (a second index type, a startup health check, a second query path) buys nothing
here. One backend, no `SEARCH_LEXICAL_BACKEND` branch, kept simple per the project's
simplicity-first guidance.

New endpoint: `GET /api/v1/kb/ontology/terms/search?q=&module_id=&term_kind=&status=`,
additive alongside the existing filter-only `ListOntologyTerms` (which is unchanged —
callers that don't need ranking keep using it).

### DR6 — Backfill

The catalog already has real content predating this feature (§2.2: 182 auto-promoted
terms, 4,213 QUDT terms, 20 core terms) — none of it has a `kb.ontology_term_search`
row until backfilled. One-time endpoint mirroring the existing
`POST /kb/search/backfill-embeddings` shape:

```
POST /api/v1/kb/ontology/terms/backfill-search
     ?module_id=       (optional; empty = every module)
     ?limit=           (rows per call; default 200)
```

Selects terms with no `kb.ontology_term_search` row (or, with a `reembed_all` flag,
every term), builds `search_document`, and — independently of
`SEARCH_SEMANTIC_ENABLED` — populates lexical fields immediately, embeddings only if
the flag is on. This mirrors `kbsearch.BackfillEmbeddings`'s existing independence
between the two.

## 4. Consequences

- Curators gain a real search box over the governed catalog for the first time;
  `ListOntologyTerms` stops being the only listing surface.
- Provides the retrieval primitive ADR `2026081201`'s OD2 ("does reconciliation need to
  merge/relink terms") would need, but does not itself build a merge/reconciliation
  workflow — that remains open, tracked separately (§5 OD2).
- `names.Resolver`'s exact-match term-creation path is untouched; no change to
  auto-promotion behavior or its guarantees.
- New write-path cost: every `PromoteToContent` and `EnsureAcceptedOrCreate` call now
  also reindexes one row into `kb.ontology_term_search`, plus one best-effort embedding
  call when the flag is on — bounded, since both paths already write one term/label set
  per call.
- New maintenance surface: a second tsvector+HNSW index pair, alongside
  `kb.search_artifacts`'s eleven. Same backfill-then-flip rollout order as the original
  hybrid search feature (spec `2026060201`).
- Does not (yet) cover `kb.ontology_candidates` (§5 OD1) or `kb.ontology_term_headers`/
  `..._revisions` (the append-only identity-foundation pair from `20260818000009`) — the
  index targets the legacy `kb.ontology_terms`/`..._labels` write path, which remains
  the one every mutation path in DR4 actually writes to today.

## 5. Open Decisions

- **OD1 — Should `kb.ontology_candidates` also get hybrid search?** Would let a curator
  (or an automated check) catch a near-duplicate *before* promotion rather than after.
  Same pattern would apply; deferred to keep this ADR scoped to the catalog table the
  user asked about.
- **OD2 — Does this feed a "suggest merge" UI or job for reconciliation?** ADR
  `2026081201` OD2 asks whether reconciliation needs to merge/relink terms; this ADR
  supplies the "find similar terms" primitive such a feature would need but does not
  design the feature itself.
- **OD3 — Multilingual embedding model.** Inherited, not re-decided here: spec
  `2026060201`'s Future Work already flags that the current general OpenAI embedding
  model may need to become a multilingual model (bge-m3 / multilingual-e5) if Chinese
  semantic recall underperforms — the same open question applies identically to this
  index, since it reuses the same model/flag.
- **OD4 — Exact `ontology_terms_search_weights` values.** DR3's table is a starting
  point (mirrors existing weight conventions), not tuned against real query traffic —
  expect adjustment once curators actually use the search box.

## 6. Implementation

Not yet implemented — Status: Proposed. To be filled in once built (see other ADRs'
§6 for the expected format: migration IDs, file list, any deviations found during
implementation).

## 7. References

- `KnowledgeStore/doc-repo/specs/202606/2026060201-spec-hybrid-search.md` — the
  `kb.search_artifacts` hybrid search implementation this ADR's RRF/embedding pattern
  is modeled on (DR2, DR5).
- `KnowledgeStore/doc-repo/adrs/202607/2026072701-adr-ontology-identity-and-assertions.md`
  — DR7 ("search and graph tables are derived projections, not the system of record"),
  the architectural basis for DR2's rejection of reusing `kb.search_artifacts`.
- `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`
  — §3.16 terminology contract (search/embedding as non-authoritative candidate
  evidence), §4.6/AD6 (`pg_trgm`+`pgvector` already installed), §3.24/DR23 (retracted
  scale assumption).
- `KnowledgeStore/doc-repo/adrs/202608/2026081201-adr-auto-promoted-governed-terms.md`
  — DR1 (exact-match term-creation path, unchanged by this ADR), §4 (1:1 catalog
  growth), §5 OD2 (the reconciliation gap this ADR's index becomes a prerequisite for).
- `KnowledgeStore/doc-repo/adrs/202608/2026081701-adr-canonical-metric-classes-instances-and-semantic-relations.md`
  — §2.1 production survey (182 auto-promoted terms, quality breakdown) motivating
  §2.2.
- `KnowledgeStore/doc-repo/adrs/202608/2026082004-adr-metric-ontology-analysis-page.md`
  — existing read-model precedent over `kb.ontology_terms`; its "similar text alone is
  not a join" caution is exactly the identity/retrieval distinction DR1 draws.
