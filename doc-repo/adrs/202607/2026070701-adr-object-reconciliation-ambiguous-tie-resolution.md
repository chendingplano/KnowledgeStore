# ADR 2026070701 - Object Reconciliation: Resolve and Alarm on Ambiguous Ties

**Date:** 2026-07-07 \
**Status:** Accepted — DR1-DR5 implemented and committed 2026/07/07; DR6 (manual resolution admin page) implemented and committed 2026/07/07; DR7 implemented and committed 2026/07/08 (migration for `ambiguous_resolved` not yet confirmed applied to any live database; backfill endpoint and admin page not yet run/used against the ~40 existing rows) \
**Component:** ChenWeb — `server/api/doc-processing`, `server/api/kbhandler`, `server/api/routes.go`, `web/src/lib/components/home3` \
**Authors**: Chen Ding \
**Tags:** object reconciliation, kb.artifact_objects, kb.object_nodes, provisions, data quality, observability, admin UI \

## 1. Change Logs
* 2026/07/07, ADR created; documents the bug found and fixed for the
  "~40 provisions with null object_id" investigation.
* 2026/07/07, DR6 added: a human-reviewable "Resolve Ambiguous Objects" admin
  page (System Admin → Database Maintenance) as a per-row, field-editable
  complement to the DR5 bulk backfill endpoint. See spec/plan in References.
* 2026/07/07, AD4 implemented: two-column layout with dirty-field highlighting, "Use this" automatically sets reconcile status to matched, and kb.object_audit_log audit trail.
* 2026/07/08, DR7 added: use an LLM adjudicator for ambiguous artifact-object
  resolution, including bounded field completion/correction, object-node
  merge/repoint semantics, audit logging, and confidence-gated resolution.

## 2. Context

ADR 2026070101 (Object Centric Design) [1] introduced `kb.artifact_objects` as
the evidence layer linking extracted artifacts (metrics, provisions, inventory
items) to canonical objects in `kb.object_nodes`, via `ObjectReconciler.ReconcileOne`.
Per `extract-provisions-spec.md` §3.1.5 [2], every provision's artifact-object
row is expected to carry a resolved `object_id` so that indexing can write the
`belong_to` edge from the object to `kb.object_nodes` in `kb.artifact_connections`.

The user reported roughly 40 rows in `kb.provisions`-linked `kb.artifact_objects`
with `object_id IS NULL`, which per the spec should never happen. Investigation
(`ChenWeb/server/api/doc-processing/artifact_objects.go:93-130`) traced this to
`ObjectReconciler.ReconcileOne`, which has three branches:

1. Exactly one candidate scoring ≥ 1 → matched, gets `object_id`.
2. **Two or more candidates tied for the top score → `reconcile_status = "ambiguous"`,
   but `ObjectID` is left empty. No candidate is picked and no new node is
   created.**
3. Otherwise → creates a new `kb.object_nodes` row, gets `object_id`.

Branch 2 is a dead end. `ObjectNodeSQLStore.FindCandidates`
(`object_nodes.go:84-89`) only ever scores candidates at exactly `1.0` (exact
name match) or `0.85` (lexical match), so ties at `0.85` are common — any
object mention with two or more similarly-named existing nodes hits this path.

The empty `ObjectID` flows through `reconcileArtifactObjects` →
`ArtifactObjectSQLStore.ReplaceObjectsForRecord`, where `nullEmpty()`
(`artifact_objects.go:414`) turns `""` into SQL `NULL`. Nothing in the pipeline
surfaced this:

- No log line or metric was ever emitted for the ambiguous outcome, in
  `ReconcileOne` or in the three callers (`persistProvisionObjects` /
  equivalent in `extract-metrics.go`, `extract-inventory-items.go`).
- `indexArtifactObjectConnections` (`artifact_object_connection_indexing.go:85`)
  silently filters these rows out with
  `WHERE COALESCE(ao.object_id, '') <> ''` — the `belong_to` edge required by
  spec §3.1.5 is simply never written, no error.
- `IndexProvisionsForRecord` (`search_artifact_indexing.go:86`) discarded the
  edge count returned by `indexArtifactObjectConnections` entirely, unlike the
  metrics indexer (`metric_indexing.go:148,156-159`), which logs it — so even
  the "fewer edges than objects" signal was invisible for provisions.
- No test covered the ambiguous branch.
- Unlike entities and inventory items, which have a periodic reconciliation
  pass that revisits `pending` rows (`semantic_clustering.go:398`,
  `inventory_item_semantic_clustering.go:315`), nothing ever revisits
  `reconcile_status = 'ambiguous'` object rows. They are permanently stuck.

This bug is not provision-specific: `ReconcileOne` is shared by metrics and
inventory items, so the same silent-null pattern can affect their
`kb.artifact_objects` rows too, even though the user only observed it via
provisions.

A heavier prior-art pattern exists for a conceptually similar problem: entity
reconciliation (`entity-reconciliation.go`, `semantic_clustering.go`) runs a
full corpus-level pipeline from ADR 2026061701 — SQL blocking, rule
thresholds, LLM adjudication for the ambiguous middle band, human review
queue, its own `kb.reconcile_runs` / `kb.entity_merge_candidates` tables. That
pipeline is not wired into any `cmd` in this codebase (confirmed via
`grep -rn "&Reconciler{" server/cmd`) — it is unused scaffolding, not a
running system. Replicating it for object-node ties was judged disproportionate
to the actual problem (a provision mentioning one object, tied between two
similarly-named existing nodes), so this ADR takes a lighter approach (AD1).

## 3. Decision

### 3.1 DR1 — Alarm on every ambiguous outcome
`reconcileArtifactObjects` (`object_nodes.go:178-212`) now takes a
`logger ApiTypes.JimoLogger` parameter. Whenever `ReconcileOne` returns
`ObjectReconcileAmbiguous`, it logs `Warn("object reconciliation ambiguous", ...)`
with `input_record_id`, `artifact_type`, `artifact_id`, `object_name`,
`top_score`, and the tied candidate `object_id:canonical_name` pairs. All
three callers (`extract-provisions.go`, `extract-metrics.go`,
`extract-inventory-items.go`) pass their processor's `p.Logger`.

### 3.2 DR2 — Fix the discarded edge-count log for provisions
`IndexProvisionsForRecord` (`search_artifact_indexing.go`) now captures the
return value of `indexArtifactObjectConnections` and logs
`"provision indexing object edges"` with `record_id` and `object_edges`,
matching the pattern already used by the metrics indexer. This makes a
drop in written edges (relative to object row count) visible per run, not
just via a full-table scan after the fact.

### 3.3 DR3 — Always reach a terminal resolution; never leave `ambiguous` + `NULL` indefinitely
New function `ResolveAmbiguousArtifactObjects` in
`ChenWeb/server/api/doc-processing/object_ambiguous_resolution.go` re-attempts
resolution for every row at `reconcile_status = 'ambiguous'`:

- Re-runs `FindCandidates`. If the tie has broken naturally since the row was
  written (new nodes created or removed in the meantime), it matches normally
  (`reconcile_status = 'matched'`).
- If still tied, applies a **deterministic tie-break** (DR4) and marks
  `reconcile_status = 'ambiguous_resolved'` — distinguishable from a clean
  match, but no longer `NULL`.
- If zero candidates remain (e.g. rejected/merged away since), it creates a
  new `kb.object_nodes` row (`reconcile_status = 'new'`).

Every row loaded by this job leaves with an assigned `object_id`. This is the
core fix: the original per-record path can still produce a fresh `ambiguous`
row (see DR-Alternatives below for why that path is intentionally left as-is),
but nothing is ever permanently null-and-silent again — the backlog is always
drainable.

### 3.4 DR4 — Deterministic tie-break rule
`pickTieBreakCandidate` (`object_ambiguous_resolution.go`) picks the candidate
that shares the most `normalized_names` with the artifact object
(`normalizedNameOverlapCount`), falling back to the lexicographically smallest
`object_id` for stability across repeated runs (so re-running the job is
idempotent for a row whose candidate set hasn't changed).

### 3.5 DR5 — Expose as a repeatable admin endpoint, not a new background job runner
`POST /kb/objects/resolve-ambiguous?limit=` (`kbhandler/resolve_ambiguous_objects_handler.go`,
registered in `routes.go`) mirrors the existing
`POST /kb/search/backfill-embeddings` pattern (`kbsearch.BackfillEmbeddings` /
`kbhandler.BackfillSearchEmbeddings`): a pure, bounded-`limit` function wrapped
in a thin HTTP handler, safe to call repeatedly until `scanned = 0`. This
reuses an established convention in the codebase instead of introducing a new
job-scheduling mechanism.

### 3.6 DR6 — Human-reviewable admin page for manual resolution
DR5's endpoint is bulk and blind: it applies the DR4 deterministic tie-break
(or a natural match, or a new node) to every loaded row without a human ever
seeing the evidence. That closes the "permanently null" problem but doesn't
help the case where the heuristic pick is *wrong* — e.g. the two tied
candidates are actually different objects, or one candidate's `canonical_name`
has a typo that a human would fix in five seconds but a name-overlap heuristic
never will.

A new page, **System Admin → Database Maintenance → Resolve Ambiguous
Objects** (`web/src/lib/components/home3/resolve-ambiguous-objects-view.svelte`),
gives a human that path:

- **Left panel** lists every `kb.artifact_objects` row at
  `reconcile_status = 'ambiguous'` (`GET /kb/objects/ambiguous`).
- Selecting a row (`GET /kb/objects/ambiguous/:id`) shows the artifact object
  alongside its candidate `kb.object_nodes` — reusing `FindCandidates` (the
  same query DR5's endpoint uses) rather than a new query — ranked by score,
  with one candidate marked **Recommended** via the same `pickTieBreakCandidate`
  function DR4 already defined (extracted into a shared `fetchSortedCandidates`
  helper so both paths can't drift on ranking behavior).
- The admin can edit fields on **either side**: the artifact object's name/
  type/role/aliases/description/`object_id`/`reconcile_status`/
  `reconcile_confidence` (`PATCH /kb/objects/artifact-objects/:id`), and any
  candidate node's canonical name/aliases/description
  (`PATCH /kb/object-nodes/:object_id`) — two independent PATCH calls on Save,
  not a combined transaction, matching this codebase's existing per-table
  update-handler convention (`UpdateMetric`).
- A **"Use this"** button on a candidate copies its `object_id` into the
  artifact object's `object_id` field as a shortcut; the admin still chooses
  the resulting `reconcile_status` explicitly (no automatic status change),
  so a save can equally express "this is the object" (`ambiguous_resolved`),
  "no valid object exists" (`rejected`, `object_id` left empty), or a plain
  data correction with the row left `ambiguous` for later.
- Setting a non-empty `object_id` stamps
  `ext_info.reconcile_method = "manual_admin"` (merged into existing
  `ext_info`, not overwritten) — a fourth provenance value alongside DR5's
  `tie_break_deterministic` and `ReconcileOne`'s `exact_name` / `lexical_name`
  / `new_node`, so downstream consumers can distinguish a human decision from
  a heuristic one.
- Prev/Next/Cancel buttons carry dirty-state confirmation (save-or-discard
  prompts before navigating away or discarding in place); Help explains the
  `reconcile_status` values and the Recommended badge inline.

This does not replace DR5: the bulk endpoint remains the fast path for the
common case (tie breaks naturally or the heuristic pick is obviously right);
DR6 is the path for the remainder that need actual judgment, and for
correcting the data (typos, near-duplicate nodes) that caused the tie in the
first place rather than just picking around it.

No new database migration was required — DR6 reuses the `ambiguous_resolved`
CHECK-constraint value DR5's migration already added.

### 3.7 DR7 - Use LLM to Resolve Ambiguous Object Nodes

For doc processors that extract artifact objects, when `ReconcileOne` finds
ambiguous candidate object nodes (`kb.object_nodes`), package the ambiguous
artifact object together with its matching object-node candidates and call the
model named by `RESOLVE_AMBIGUOUS_OBJECT_MODEL_NAME`. This LLM adjudication is
the first automated resolution attempt for a fresh ambiguous row; DR5's
deterministic tie-break remains the repeatable fallback/backfill path when LLM
resolution is disabled, unavailable, or below confidence.

The LLM output is constrained to the following actions.

Complete or correct only these `kb.artifact_objects` fields:

- `object_name_en`, if empty
- `object_name_zh`, if empty
- `acronyms`, if there are meaningful acronyms for the object
- `object_type`, using a type that is generic enough to be reusable but not so
  broad that it loses meaning
- `description`

Complete or correct only these `kb.object_nodes` fields:

- `canonical_name_en`, if empty
- `canonical_name_zh`, if empty
- `object_type`, using a type that is generic enough to be reusable but not so
  broad that it loses meaning
- `description`

The model must also return:

- groups of candidate object nodes that represent the same object, with a
  confidence for each proposed same-object group
- the selected object node for the artifact object, with a resolution
  confidence
- enough rationale/provenance for an audit entry without storing the full
  prompt payload in normal row fields

Processing the LLM output:

- Field updates are allowlisted to the fields above. Any accepted update also
  refreshes derived `normalized_names` and `search_document` values that depend
  on the edited fields; embeddings are regenerated through the existing search
  embedding backfill path rather than synchronously inside reconciliation.
- If the LLM proposes merged object nodes, it must identify the survivor
  `object_id` and the loser `object_id` values. Applying a merge reuses the
  existing object-node merge semantics: repoint all `kb.artifact_objects`
  rows from each loser object id to the survivor object id, set each loser
  node's `canonical_object_id` to the survivor, set each loser node's
  `reconcile_status = 'merged'`, and merge
  `{"merged_to":"<survivor_object_id>", "merge_time":"<timestamp>"}` into
  each loser node's `ext_info`.
- If the artifact object is resolved with confidence greater than or equal to
  `RESOLVE_AMBIGUOUS_MIN_CONFIDENCE` (default `0.85`), set its `object_id` to
  the selected survivor/current object id, set `reconcile_status =
  'ambiguous_resolved'`, set `reconcile_confidence` to the LLM confidence, and
  merge `ext_info.reconcile_method = "llm_ambiguous_resolution"` plus the
  model name into `ext_info`.
- If confidence is below `RESOLVE_AMBIGUOUS_MIN_CONFIDENCE`, leave the artifact
  object at `reconcile_status = 'ambiguous'` with no `object_id`; it remains
  available for DR5 deterministic backfill or DR6 human review.
- All applied updates to `kb.artifact_objects` and `kb.object_nodes`, including
  merge/repoint operations, are logged to `kb.object_audit_log`.

## 4. Matching Algorithm Reference

The candidate-selection path used by both `ObjectReconciler.ReconcileOne` and
the Resolve Ambiguous Objects admin page is intentionally simple and lexical.
The page does **not** run a second, different ranking algorithm: it reuses the
same `FindCandidates` + tie-break logic that the backend uses for automated
resolution.

### 4.1 Candidate retrieval

`ObjectNodeSQLStore.FindCandidates` builds a `normalized_names` bundle for the
artifact object from:

- `object_name`
- `object_name_en`
- `object_name_zh`
- `aliases`
- `acronyms`

Each value is normalized by trimming, lowercasing, converting punctuation
(`.`, `_`, `-`, `/`) to spaces, and collapsing repeated whitespace. For
example, `SBP`, `sbp`, and `sbp ` all normalize to `sbp`.

The SQL then returns every `kb.object_nodes` row whose own
`normalized_names` overlaps that artifact bundle, or whose `canonical_name`,
`canonical_name_en`, or `canonical_name_zh` exactly equals the artifact
object's raw `object_name`. Rejected and merged nodes are excluded.

### 4.2 Candidate scoring

After retrieval, each candidate is scored with only two possible values:

- `1.0` / `exact_name`: object types are compatible **and** the artifact and
  candidate share at least one normalized name.
- `0.85` / `lexical_name`: retrieved by the SQL filter, but the stronger
  type-and-name condition above did not hold.

`objectTypesCompatible` is permissive: blank and `other` types are treated as
compatible with anything, otherwise the normalized `object_type` strings must
match.

### 4.3 Ambiguous ties and recommendation

If two or more candidates share the top score, the row is considered
`ambiguous`. The admin page still shows all returned candidates, but marks one
as **Recommended** using `pickTieBreakCandidate`:

- prefer the candidate with the largest overlap count between the artifact's
  `normalized_names` and the candidate's `normalized_names`
- break any remaining tie by lexicographically smallest `object_id`

### 4.4 Why a semantically different node can still appear

Because retrieval is lexical, a semantically broader or different concept can
still qualify if it shares a normalized alias/acronym. In the reported example
for `收缩压 / systolic blood pressure`, the `高血压 / Hypertension` node was
returned because it carried the acronym `SBP`, which normalizes to `sbp` and
therefore overlaps the artifact object's `normalized_names`. It appeared as a
candidate for lexical reasons, not because the system concluded that
hypertension and systolic blood pressure are the same concept.

### 4.5 Admin-page field highlighting

The Resolve Ambiguous Objects page highlights the editable fields on each
candidate node that visibly contributed overlap with the artifact object:
canonical names, aliases, and acronyms. `object_type` is treated only as
supporting context: it may be highlighted and listed alongside a real lexical
overlap, but a candidate whose only agreement is `object_type` is shown as
`Matches: none` and is not counted as a match. This UI hint is derived from
the same normalization rules above so that the page can answer "what matched?"
directly, especially in cases where the only visible lexical overlap is an
acronym such as `SBP`.

### 4.6 Alternative Decisions

#### 4.6.1 AD1: Full corpus-level LLM-adjudicated reconciliation pipeline (mirror entities)
Rejected. The entity pipeline (ADR 2026061701) is ~350+ lines of
block→adjudicate→apply→enrich orchestration with its own tables and an LLM
adjudicator, and is not even wired into a `cmd` today. Building the equivalent
for object-node ties — a much smaller-scale problem (single-object mentions
tied between two candidates, not corpus-wide entity deduplication) — would be
disproportionate scope for the gap being closed. Discussed with the user
directly; deterministic tie-break was preferred for DR1-DR5 (see conversation
record). DR7 does not revive the full corpus-level pipeline: it adds a bounded,
per-artifact LLM adjudication step over the same small `FindCandidates` set,
with no new reconcile-run tables or corpus-wide clustering job.

#### 4.6.2 AD2: Auto-pick a candidate at write time (no distinct ambiguous state)
Rejected. Collapsing branch 2 into an immediate deterministic pick at
`ReconcileOne` time would lose the chance for the tie to resolve *naturally*
as more documents are ingested and candidate nodes gain more aliases/evidence.
Keeping a distinct `ambiguous` backlog that a separate, repeatable job drains
preserves that option while still guaranteeing termination.

#### 4.6.3 AD3: Logging/alarm only, no resolution job
Considered as a minimal first cut. Rejected as the final scope because it
would leave `kb.artifact_objects.object_id` permanently `NULL` for these rows,
which keeps violating spec §3.1.5's expectation that provisions link to
`kb.object_nodes` — the `belong_to` connection edges would still never be
written for them. Logging alone converts a silent bug into a *visible* but
still-uncorrected one; the user chose to also close the gap.

#### 4.6.4 AD4: Modifications
1. Show the records in two columns (currently it shows all records in one column): Left shows the selected record, Right has two regions: Top Region and Bottom Region. Top Region is a quick reference list, with three columns: Canonical Name, Description, and Action (a button 'Use this'). Bottom Region lists the ones from `kb.object_nodes`
2. When clicking 'Use this', set the object_id (already done) and change 'Reconcile Status' to 'matched'.
3. Show the dirty fields in a different color, such as red.
4. Add a log to log the operations performed on `kb.object_nodes` and `kb.artifact_objects`

### 4.7 Database Migrations

`ChenWeb/project_migrations/20260707000001_allow_ambiguous_resolved_reconcile_status.sql`

```sql
-- +goose Up
ALTER TABLE kb.artifact_objects
    DROP CONSTRAINT IF EXISTS chk_kb_artifact_objects_reconcile_status;

ALTER TABLE kb.artifact_objects
    ADD CONSTRAINT chk_kb_artifact_objects_reconcile_status
        CHECK (reconcile_status IN ('pending', 'matched', 'new', 'ambiguous', 'ambiguous_resolved', 'rejected'));
```

Extends the existing `chk_kb_artifact_objects_reconcile_status` CHECK
constraint (added in `20260702000002_create_kb_artifact_objects.sql`) to
allow the new `ambiguous_resolved` value. `Down` restores the original
constraint list. No column changes; `object_id` was already nullable.

### 4.8 Data Formats

`kb.artifact_objects.ext_info` gains a `reconcile_method` value of
`"tie_break_deterministic"` when a row is resolved via DR4, alongside the
existing `"exact_name"`, `"lexical_name"`, and `"new_node"` values already
written by `ReconcileOne` / `CreateNode`. DR6 adds a fifth value,
`"manual_admin"`, stamped when a human sets `object_id` via the admin page.
DR7 adds `"llm_ambiguous_resolution"` for confidence-gated LLM decisions and
stores the model name in `ext_info`.

`kb.object_nodes.ext_info` gains merge provenance for LLM-applied object-node
merges:

```json
{"merged_to":"<survivor_object_id>", "merge_time":"<timestamp>"}
```

The same merge also sets `canonical_object_id` on the loser node and repoints
artifact-object rows to the survivor; `ext_info` is provenance, not the source
of truth for following redirects.

### 4.9 Environment Variables

- `OBJECT_RECONCILE_EMBEDDING_ENABLED` / `OBJECT_RECONCILE_MAX_CANDIDATES`:
  existing options reused via the reconciler passed in (constructed the same
  way processors already do, through the now-exported
  `ObjectReconcileOptionsFromEnv()` — renamed from the package-private
  `objectReconcileOptionsFromEnv()` so `kbhandler` can construct a reconciler
  for the new endpoint).
- `RESOLVE_AMBIGUOUS_OBJECT_MODEL_NAME`: model used by DR7 for LLM adjudication
  of ambiguous artifact objects and candidate object nodes.
- `RESOLVE_AMBIGUOUS_MIN_CONFIDENCE`: minimum confidence required for DR7 to
  apply an artifact-object resolution. Default: `0.85`.

## 5. Implementation

### 5.1 Code Changes

- `ChenWeb/server/api/doc-processing/artifact_objects.go` — add
  `ObjectReconcileAmbiguousResolved = "ambiguous_resolved"` constant.
- `ChenWeb/server/api/doc-processing/object_nodes.go` — `reconcileArtifactObjects`
  gains a `logger` parameter and logs on ambiguous outcomes; rename
  `objectReconcileOptionsFromEnv` → `ObjectReconcileOptionsFromEnv` (exported).
- `ChenWeb/server/api/doc-processing/extract-provisions.go`,
  `extract-metrics.go`, `extract-inventory-items.go` — pass `p.Logger` into
  `reconcileArtifactObjects`; use the renamed `ObjectReconcileOptionsFromEnv`.
- `ChenWeb/server/api/doc-processing/search_artifact_indexing.go` —
  `IndexProvisionsForRecord` logs the `object_edges` count.
- `ChenWeb/server/api/doc-processing/object_ambiguous_resolution.go` (new) —
  `AmbiguousObjectRow`, `AmbiguousObjectStore`, `ResolveAmbiguousResult`,
  `ResolveAmbiguousArtifactObjects`, `pickTieBreakCandidate`,
  `normalizedNameOverlapCount`, and `ArtifactObjectSQLStore.LoadAmbiguous` /
  `.UpdateResolution` (implementing `AmbiguousObjectStore`).
- `ChenWeb/server/api/kbhandler/resolve_ambiguous_objects_handler.go` (new) —
  `ResolveAmbiguousObjects` HTTP handler.
- `ChenWeb/server/api/routes.go` — registers
  `POST /kb/objects/resolve-ambiguous`.
- `ChenWeb/project_migrations/20260707000001_allow_ambiguous_resolved_reconcile_status.sql` (new).

Verification:

```bash
cd /Users/cding/Workspace/ChenWeb
go build ./...
go vet ./server/api/doc-processing/... ./server/api/kbhandler/...
go test ./server/api/doc-processing -run 'TestReconcileArtifactObject|TestResolveAmbiguousArtifactObjects|TestPickTieBreakCandidate|TestArtifactObjectSQLStore|TestIndexProvisionsForRecordLogsObjectEdgeCount|TestIndexArtifactObjectConnectionsWritesObjectIDEdges'
```

All 12 targeted tests pass; `go build ./...` and `go vet` are clean. The
pre-existing `go test ./server/api/doc-processing` failures (summary/topic/
entity/relation tests, ~19 tests) were verified to predate this change via
`git stash` — reproduced identically with this change stashed out — and are
unrelated pre-existing test debt, not introduced by this ADR.

### 5.2 DR6 Code Changes

- `ChenWeb/server/api/doc-processing/object_ambiguous_resolution.go` — add
  `AmbiguousObjectSummary`, `ArtifactObjectSQLStore.ListAmbiguousSummaries` /
  `.LoadByID`, `RankAmbiguousCandidates`, and a `fetchSortedCandidates` helper
  shared with (extracted from) `ResolveAmbiguousArtifactObjects` so both
  paths rank candidates identically.
- `ChenWeb/server/api/doc-processing/object_ambiguous_resolution_test.go` —
  tests for the above (sqlmock + a stub `ObjectNodeStore`).
- `ChenWeb/server/api/kbhandler/ambiguous_objects_handler.go` (new) —
  `ListAmbiguousObjects`, `GetAmbiguousObjectDetail` (GET), `UpdateArtifactObject`,
  `UpdateObjectNode` (PATCH) HTTP handlers, plus DTOs (`artifactObjectDTO`,
  `objectNodeCandidateDTO`, `ambiguousObjectSummaryDTO`) that intentionally
  omit `source_line_spans` / `ext_info` from the wire format.
- `ChenWeb/server/api/kbhandler/ambiguous_objects_handler_test.go` (new) —
  sqlmock tests for the two PATCH handlers (the two GET handlers are thin
  wrappers over already-tested doc-processing functions and have no
  dedicated test file, matching the existing `ResolveAmbiguousObjects`
  handler's precedent).
- `ChenWeb/server/api/routes.go` — registers `GET /kb/objects/ambiguous`,
  `GET /kb/objects/ambiguous/:id`, `PATCH /kb/objects/artifact-objects/:id`,
  `PATCH /kb/object-nodes/:object_id`.
- `ChenWeb/web/src/lib/components/home3/resolve-ambiguous-objects-client.ts`
  (new) — typed fetch wrappers, editable-field whitelists, and pure
  diff/navigation helpers (`buildArtifactObjectPatch`, `buildObjectNodePatch`,
  `neighborAmbiguousId`).
- `ChenWeb/web/src/lib/components/home3/resolve-ambiguous-objects-client.test.ts`
  (new) — `bun test` / `node:test` coverage for the above.
- `ChenWeb/web/src/lib/components/home3/resolve-ambiguous-objects-view.svelte`
  (new) — the two-panel Svelte 5 view: left list, right Artifact Object +
  Related Object Nodes editable blocks, dirty-tracking, Prev/Next/Cancel/
  Save/Help with confirm modals.
- `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`,
  `content-panel.svelte` — add the "Resolve Ambiguous Objects" nav entry
  under System Admin → Database Maintenance and its dispatch.
- No new migration (reuses DR5's `ambiguous_resolved` CHECK value).

DR6 Verification:

```bash
cd /Users/cding/Workspace/ChenWeb
go build ./...
go vet ./server/api/...
go test ./server/api/doc-processing/... ./server/api/kbhandler/...
cd web
bun test src/lib/components/home3/resolve-ambiguous-objects-client.test.ts
bun run check
```

Backend build/vet clean; this ADR's own tests plus the new `LoadByID` /
`ListAmbiguousSummaries` / `RankAmbiguousCandidates` / `UpdateArtifactObject` /
`UpdateObjectNode` tests all pass. `go test` on the wider
`doc-processing`/`kbhandler` packages shows pre-existing, unrelated failures
(summary/topic/entity/relation/search-registry domain) confirmed via a
baseline-commit worktree check to predate this change — not introduced by
DR6. Frontend: 8/8 `bun test` pass; `bun run check` shows zero errors in any
file this ADR touches (41 pre-existing errors elsewhere, unrelated). A
headless-browser (Playwright) walkthrough with the two GET endpoints
network-mocked confirmed end-to-end: list rendering, panel population, "Use
this", dirty-tracking, the Prev/Next 3-button confirm modal, the Cancel
discard-confirm modal, Help, the Save PATCH payload shape, and queue-drain
(a resolved row disappearing from the left panel with the next row
auto-selected).

### 5.3 DR7 Code Changes

- `ChenWeb/server/api/doc-processing/object_ambiguous_llm.go` (new) — DR7 LLM
  decision DTOs, JSON parser, structured-output contract, env-based resolver
  construction from `RESOLVE_AMBIGUOUS_OBJECT_MODEL_NAME`, min-confidence
  loading from `RESOLVE_AMBIGUOUS_MIN_CONFIDENCE` (default `0.85`), decision
  validation, confidence gating, provenance stamping, survivor mapping, and
  artifact-object field completion.
- `ChenWeb/server/api/doc-processing/object_ambiguous_llm_sql.go` (new) —
  transactional object-node field updates, derived `normalized_names` /
  `search_document` refresh, loser-to-survivor artifact-object repointing,
  loser node `canonical_object_id` / `reconcile_status = 'merged'` updates,
  `ext_info.merged_to` / `merge_time`, and `kb.object_audit_log` entries.
- `ChenWeb/server/api/doc-processing/object_nodes.go` — keep the existing
  `reconcileArtifactObjects` wrapper and add `reconcileArtifactObjectsWithLLM`
  so ambiguous ties call DR7 when configured, while failed or low-confidence
  attempts fall back to the existing `ambiguous` backlog.
- `ChenWeb/server/api/doc-processing/extract-provisions.go`,
  `extract-metrics.go`, `extract-inventory-items.go` — construct the optional
  DR7 resolver from env and pass it through the shared reconciliation path for
  provisions, metrics, and inventory items.
- `ChenWeb/project_migrations/20260708000001_extend_object_audit_log_actions.sql`
  (new) — extends `kb.object_audit_log.action` to allow the existing/new
  `create_node` and `merge_nodes` audit actions.

DR7 Verification:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-processing -run 'TestApplyAmbiguousObjectLLMDecision|TestObjectNodeSQLStoreApplyAmbiguousObjectLLMNodeChanges|TestParseAmbiguousObjectLLMDecisionReadsExpectedShape|TestReconcileArtifactObjects(LogsWarnOnAmbiguousTie|UsesLLMForAmbiguousTie)'
go test ./server/api/doc-processing -run 'TestReconcileArtifactObject|TestResolveAmbiguousArtifactObjects|TestPickTieBreakCandidate|TestArtifactObjectSQLStore|TestRankAmbiguousCandidates|TestObjectNode|TestFindCandidates|TestApplyAmbiguousObjectLLMDecision|TestParseAmbiguousObjectLLMDecision|TestObjectNodeSQLStoreApplyAmbiguousObjectLLMNodeChanges'
go test ./server/api/kbhandler -run 'Test.*ObjectAudit|TestMergeObjectNodes|TestUpdateObjectNode|TestUpdateArtifactObject|TestCreateObjectNode|TestRebind'
go vet ./server/api/doc-processing/... ./server/api/kbhandler/...
go build ./...
```

All targeted DR7/object-resolution tests pass. `go build ./...` and `go vet`
on the affected backend packages are clean. Full-package
`go test ./server/api/doc-processing` and `go test ./server/api/kbhandler`
still show unrelated pre-existing failures in summary/search/category handler
tests; the targeted DR7/object-resolution tests above are green.

## 6. Operational Behaviors

`ResolveAmbiguousArtifactObjects` / `POST /kb/objects/resolve-ambiguous?limit=`
is safe to call repeatedly: each call loads up to `limit` (default 200) rows
still at `reconcile_status = 'ambiguous'`, resolves each one, and returns a
`{scanned, matched, tie_broken, created, failed}` summary. A caller (human or
a future cron) should call it in a loop until `scanned = 0` to drain the
backlog, the same operational pattern already used for
`/kb/search/backfill-embeddings`.

Per-record processing (`extract_provisions`, `extract_metrics`,
`extract_inventory_items`) now has an optional DR7 LLM adjudication step after
a fresh ambiguous result is detected. If the LLM resolves the row above
`RESOLVE_AMBIGUOUS_MIN_CONFIDENCE`, the row is written as
`ambiguous_resolved` with a non-null `object_id`. If the LLM is disabled,
unavailable, returns invalid output, or produces confidence below the threshold,
the row remains `ambiguous` with `object_id IS NULL`, and the DR1 warning log
still makes the condition visible immediately.

This ADR does not itself run the backfill against any database — the
migration has not been applied and the endpoint has not been invoked against
the ~40 existing rows. That is a separate, explicit operational step for
whoever applies this change.

**DR6:** the admin page is a human-driven complement to the bulk endpoint and
the DR7 LLM path, not a replacement for either. There is still no cron or
scheduled job. Rows sit at `ambiguous` until one of three things happens: DR7
resolves them during/after extraction, `/kb/objects/resolve-ambiguous` applies
the repeatable backfill behavior, or a human opens the admin page and resolves
them one at a time. The admin page's candidate list per row is exactly whatever
`FindCandidates` returns (typically 2-5 nodes); if a row's true match isn't in
that set, the page can't currently reach it — a separate node-search UI would
be needed for that case, and is out of scope here.

**DR7:** LLM adjudication is confidence-gated and fail-open to the existing
ambiguous backlog. It must not silently force a low-confidence choice just to
avoid a null `object_id`; low-confidence rows remain reviewable by DR5/DR6.
Applied LLM field edits, object-node merges, and artifact-object resolutions
must be auditable through `kb.object_audit_log`.

## 7. Consequences

Positive:

- Closes the spec §3.1.5 violation: every provision (and, going forward,
  metric/inventory-item) artifact-object row reaches a real `object_id`,
  so the `belong_to` edge to `kb.object_nodes` gets written.
- Future ambiguous ties are alarmed immediately instead of discovered only by
  auditing `object_id IS NULL` counts.
- Reuses the codebase's existing backfill-endpoint convention rather than
  introducing new job infrastructure.
- Fix applies uniformly to provisions, metrics, and inventory items, since all
  three share `ReconcileOne` / `reconcileArtifactObjects`.
- **DR6:** gives a human review path for the ambiguous backlog — an admin can
  now inspect the actual candidate evidence, fix the underlying data
  (typos, near-duplicate node names) instead of just picking around it, and
  produce an `ambiguous_resolved` row with real judgment behind it
  (`ext_info.reconcile_method = "manual_admin"`), directly addressing this
  same tradeoff list's concern about heuristic-only provenance for rows a
  human actually reviews.
- **DR7:** gives a bounded automated semantic-review path before falling back
  to deterministic or human resolution. It can complete missing bilingual names
  and descriptions, merge true duplicate object nodes, and resolve an artifact
  object with explicit LLM provenance when confidence is high enough.

Tradeoffs:

- `ambiguous_resolved` rows carry varied provenance: deterministic tie-break,
  LLM adjudication, or human review. `ext_info.reconcile_method` distinguishes
  `tie_break_deterministic` (heuristic), `llm_ambiguous_resolution` (LLM), and
  `manual_admin` (human-reviewed). Downstream consumers that care about match
  quality should filter on `reconcile_status` / `reconcile_confidence` /
  `ext_info.reconcile_method`, not assume all non-null `object_id` rows are
  equally trustworthy.
- The backlog-drain endpoint is a manual/cron-triggered step, not automatic.
  Rows can still sit at `ambiguous` (now alarmed, but still `object_id IS NULL`)
  when DR7 is disabled or below threshold, until someone calls the endpoint or
  resolves the row through the DR6 admin page; there is still no scheduled job
  driving the fallback paths.
- DR6's candidate list per row is exactly whatever `FindCandidates` returns
  (typically 2-5 nodes) — if the true match isn't among them, the admin page
  can't currently reach it.
- DR7 can update canonical object-node fields and merge nodes, so its
  implementation has a larger blast radius than DR4/DR5. The allowlist, merge
  repoint transaction, confidence threshold, and `kb.object_audit_log` entries
  are required controls, not optional implementation details.
- Does not address the heavier, still-unused entity-style reconciliation
  pipeline; if corpus-wide object deduplication is needed later, that remains
  a separate, larger initiative (AD1).

## 8. Tests

New/updated, all passing:

- `TestReconcileArtifactObjectsLogsWarnOnAmbiguousTie` — DR1.
- `TestIndexProvisionsForRecordLogsObjectEdgeCount` — DR2.
- `TestPickTieBreakCandidatePrefersMoreNormalizedNameOverlap`,
  `TestPickTieBreakCandidateFallsBackToLexicographicObjectID` — DR4.
- `TestResolveAmbiguousArtifactObjectsAppliesTieBreakWhenStillTied`,
  `TestResolveAmbiguousArtifactObjectsMatchesWhenTieResolvedNaturally`,
  `TestResolveAmbiguousArtifactObjectsCreatesNodeWhenNoCandidatesRemain` — DR3.
- `TestArtifactObjectSQLStoreLoadAmbiguousReadsRow`,
  `TestArtifactObjectSQLStoreUpdateResolutionWritesRow` — SQL store layer.
- Existing `TestReconcileArtifactObjectExactAliasMatch`,
  `TestReconcileArtifactObjectCreatesNodeWhenNoMatch`,
  `TestIndexArtifactObjectConnectionsWritesObjectIDEdges` re-verified green
  after the signature change to `reconcileArtifactObjects`.

DR6, new/updated, all passing:

- `TestArtifactObjectSQLStoreListAmbiguousSummariesReadsRows`,
  `TestArtifactObjectSQLStoreLoadByIDReadsRow`,
  `TestArtifactObjectSQLStoreLoadByIDReturnsNotFoundForMissingRow` —
  the two new store methods.
- `TestRankAmbiguousCandidatesMarksRecommended`,
  `TestRankAmbiguousCandidatesReturnsEmptyRecommendedWhenNoCandidates` —
  the new ranking function (and, by extension, the extracted
  `fetchSortedCandidates` helper it shares with `ResolveAmbiguousArtifactObjects`).
- `TestUpdateArtifactObjectSuccessStampsExtInfoWhenObjectIDSet`,
  `TestUpdateArtifactObjectRejectsInvalidReconcileStatus`,
  `TestUpdateArtifactObjectRejectsNullObjectName`,
  `TestUpdateArtifactObjectNotFound` — the `PATCH /kb/objects/artifact-objects/:id`
  handler, including the `ext_info.reconcile_method = "manual_admin"` stamp.
- `TestUpdateObjectNodeSuccess`, `TestUpdateObjectNodeRejectsNullCanonicalName`,
  `TestUpdateObjectNodeNotFound` — the `PATCH /kb/object-nodes/:object_id` handler.
- `resolve-ambiguous-objects-client.test.ts` (8 tests, `bun test`) — the
  frontend fetch wrappers and pure diff/navigation helpers.

DR7, new/updated and passing:

- LLM response validation: reject unknown field edits, missing confidence,
  selected ids outside the candidate set, and malformed same-object groups.
- High-confidence LLM resolution: updates the artifact object to
  `ambiguous_resolved`, sets `object_id`, records `reconcile_confidence`, and
  stamps `ext_info.reconcile_method = "llm_ambiguous_resolution"`.
- Low-confidence or failed LLM resolution: leaves the artifact object
  `ambiguous` with no `object_id`.
- LLM-applied object-node merge: repoints loser artifact-object rows to the
  survivor, sets `canonical_object_id`, marks losers `merged`, merges
  `ext_info.merged_to` / `merge_time`, and writes `kb.object_audit_log`.

## 9. Documentation Impact

- `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-spec.md`
  §3.1.5 describes the `kb.artifact_objects.object_id` → `kb.object_nodes.object_id`
  link but does not currently mention the `ambiguous` / `ambiguous_resolved`
  reconcile states, the DR7 LLM adjudication path, or that resolution can be
  deferred and later corrected by deterministic backfill or human review. **Not
  updated by this ADR** — flagged as a follow-up so the spec doesn't go stale
  relative to this behavior.
- No update made to `extract-metrics-spec.md` / inventory item spec; the fix
  is behaviorally identical for those processors (shared `ReconcileOne`) but
  the specs were not audited for the same gap in this session.
- ADR 2026070101 DR4 ("remains ambiguous/pending") is extended, not
  contradicted, by this ADR: `pending` (never attempted) and `ambiguous`
  (attempted, tied, and not yet resolved above threshold) both remain valid
  transient states; this ADR adds the mechanisms that make the backlog visible
  and drainable.
- DR6's design and implementation are recorded in full in [4] and [5]
  (the design spec and implementation plan referenced below) rather than
  duplicated here; this ADR summarizes the decision and its consequences.
  `extract-provisions-spec.md` §3.1.5 still has the same not-yet-updated gap
  noted above — DR6 and DR7 both increase the importance of that follow-up.

## 10. References
- [1] `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
- [2] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-spec.md` §3.1.5
- [3] `ChenWeb/server/api/doc-processing/entity-reconciliation.go`,
  `semantic_clustering.go` (prior art considered and rejected, AD1)
- [4] `ChenWeb/docs/superpowers/specs/2026-07-07-resolve-ambiguous-objects-admin-page-design.md`
  (DR6 design spec)
- [5] `ChenWeb/docs/superpowers/plans/2026-07-07-resolve-ambiguous-objects-admin-page.md`
  (DR6 implementation plan, task-by-task)
