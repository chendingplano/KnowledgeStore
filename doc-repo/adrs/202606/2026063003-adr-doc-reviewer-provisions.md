# ADR 2026063003 — Provisions Document Reviewer

**Date:** 2026-06-30 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-reviews`, `server/api/doc-processing` (connection loader), `prompts` \
**Authors**: Chen Ding\
**Tags**: Document Reviewer, Provisions, Cross-Document Consistency

## 1. Change Logs
* 2026/06/30, ADR Created (copied from ADR 2026063002 — metric reviewer)
* 2026/06/30, Fleshed out and implemented. Corrected copy-paste artifacts from the
  metric ADR (provision vs metric naming), confirmed the provision data model
  (`kb.provisions`, id column `prov_id`, category field `category_paths`), filled all
  empty sections. Status Proposal → Accepted.
* 2026/06/30, Branch A correctness fix (mirrors ADR 2026063002): `hybrid_search` edges
  are directional, so the doc provision is on the `target` side of any edge created by a
  document indexed later. Branch A now unions outbound (P=source) and inbound (P=target)
  edges via `LoadConnectionsByTarget`, resolving the opposite endpoint as the match and
  excluding any endpoint with `record_id = record_id`.
* 2026/07/01, Branch A migrated to **on-the-fly** (supersedes the precomputed-edge
  decision in DR1 and the 2026/06/30 correctness fix): semantic provision↔provision
  similarity is no longer materialized as `hybrid_search` / `semantically_related` edges.
  Branch A calls `docprocessing.FindSimilarArtifactsOnTheFly` (same lexical + pgvector RRF
  acceptance policy) per doc provision at review time. Live search is always fresh and
  direction-free, so the A1/A2 inbound/outbound union and `LoadConnectionsByTarget` are no
  longer used by this reviewer. (Note: no provision artifact-indexing step ever wrote these
  edges, so the precomputed Branch A was in practice empty; on-the-fly makes it functional.
  The metric reviewer, ADR 2026063002, made the same change.)
* 2026/07/03, ADR 2026070201 (AR2/AR3/AR5) implemented for this reviewer: prompt v2
  (`prompt-review-provisions-v2.md`), window-first input layout, window-grouped
  seed/stagger execution, `source_doc_authority` + `match_rank` in the matched
  payload, structured `related_artifact_id`/`related_record_id` in findings, and
  tool-use with `get_artifact_context`.
* 2026/07/05, synced with implemented object-centric design (ADR 2026070101): provision
  extraction persists and reconciles artifact objects through the shared
  `kb.artifact_objects` / `kb.object_nodes` contract, and provision indexing writes
  `object_id` / `belong_to` graph edges.
* 2026/07/05, clarified the reviewer goal to match ADR 2026063002: for each
  provision-under-review, retrieve relevant cross-document provisions from the database,
  then ask the LLM to review the provision with that context. Object-anchored retrieval is
  a match branch. The old document-level entity branch is removed because it retrieves
  provisions related to entities in the document-under-review, not necessarily provisions
  relevant to the provision-under-review.
* 2026/07/09, added the current **Provision Review Harness** description based on
  `review-provisions.go`, `review-tool-loop.go`, `review-artifact-window.go`,
  `doc-review.local.toml`, and `prompt-review-provisions-v4.md`.
* 2026/07/09, implemented the analysis-persistence correction: provision `analyses`
  are review results and are stored as first-class rows in
  `kb.doc_review_findings`, not only in the reviewer-specific
  `kb.doc_review_provision_analyses` side table.

## 2. Context
When a document is added to the knowledge base, the system extracts metrics, entities,
relations, provisions and other artifacts from the document via the doc processors
(refer to [1]).

This document reviewer assumes the document-under-review, identified by `record_id`
(`kb.inputs.id`), has already been processed by all doc processors. The reviewer is
configured as `reviewers.provisions` (group P5) in [2].

### 2.1 Relationship to the metric reviewer (ADR 2026063002)

This reviewer is the provisions analogue of the metric reviewer [4] and shares its
architecture: it is an **artifact-based, cross-document consistency** reviewer, not a
text reviewer. It does not read the document body; it loads the document's extracted
**provisions** and compares each against semantically-related provisions in *other*
documents, discovered through live hybrid search over `kb.search_artifacts`. It uses
`Input="artifact"`, so the prompt-cache scheduler routes it to `runReviewersLegacy`
which calls `ReviewDocument` directly (no scheduler/strategy changes).

### 2.2 Provision-specific facts (differ from metrics)

- Provisions live in `kb.provisions`; the artifact id column is **`prov_id`**
  (format `"<record>_prv_<n>"`, globally unique, like `metric_id`). Connection
  `source_id`/`target_id` for provision endpoints equal `prov_id`.
- The artifact type discriminator is `"provision"` (`searchArtifactProvision`).
- Provision indexing hydrates provision rows into `kb.search_artifacts`, writes
  shared-line/category/object graph edges, and writes object-node `belong_to` edges
  through ADR 2026070101. Semantic provision<->provision similarity is not consumed from
  materialized `hybrid_search` edges by this reviewer; Branch A computes it live.
- Provisions carry **`category_paths`** (JSONB array), not `metric_categories`. The
  category field remains useful in prompts and future ranking, but this reviewer does not
  use category overlap as a broad attachment heuristic.
- Unlike the metric reviewer there is **no corpus-wide category-sibling branch** (metric
  Branch B). Provisions match via (A) live hybrid search and (B) object-anchored retrieval.
  (Rationale under Alternative Decisions.)

## 3. Decision
### 3.1 DR1 — Reviewer logic

The reviewer builds, for each provision extracted from the document-under-review, a
list of **matching provisions** from live semantic search plus object-anchored graph
retrieval, then issues one LLM call per provision. The high-level flow is: given a
provision-under-review, find relevant provisions already in the database, then ask the
LLM to review the provision-under-review with the document context and matching
provisions. Pseudocode:

```text
matches := map[provision] -> []matchingProvision   # keyed by the doc's own provision

# Branch A: provision <-> semantically related provisions, computed LIVE (no materialized edges).
# A single hybrid search per doc provision finds close provisions across the whole corpus
# regardless of when the other document was indexed, so there is no direction to union.
for each provision P extracted from the document-under-review (kb.provisions WHERE input_record_id = record_id):
   hits := FindSimilarArtifactsOnTheFly(
              selfType='provision', selfID=P.prov_id,
              candidateType='provision', maxLinks=PROVISION_REVIEW_MAX_MATCHES)
   resolve each hit (record_id, prov_id) -> a kb.provisions row

   append resolved provisions to matches[P]   (deduped by matching prov_id;
                                               same-document hits excluded)

   # Branch B: object-anchored provisions for the provision-under-review
   objectLinks := kb.artifact_objects ao
      JOIN kb.object_nodes onode ON onode.object_id = ao.object_id
      WHERE ao.source_record_id = record_id
        AND ao.artifact_type = 'provision'
        AND ao.artifact_id = P.prov_id
        AND ao.object_id IS NOT NULL

   for each object node O linked to P:
      peerObjectIDs := O.object_id plus comparable object nodes
                       (same object_type, overlapping normalized_names,
                        reconcile_status <> 'rejected')

      peerEdges := kb.artifact_connections WHERE
         relation_method = 'object_id'
         AND relation_name = 'belong_to'
         AND source_type = 'provision'
         AND target_type = 'object_node'
         AND target_id IN peerObjectIDs

      resolve peerEdges.extra_info.artifact_ids -> kb.provisions rows
      append resolved provisions to matches[P]   (deduped by prov_id;
                                                  same-document hits excluded)

# LLM comparison (parallel)
for each provision P in matches where len(matches[P]) > 0:
   launch one LLM call (configured model + prompt) with:
       - the provision under review (P)
       - all matching provisions (deduped, capped at MaxMatchesPerProvision)
   parse findings; tag Pass="P5", Aspect="provisions"
```

Dedup/cap rules (identical to the metric reviewer):
- A matching provision is identified by its `prov_id`; duplicates across branches are
  collapsed.
- Same-document matches (`record_id = record_id`) are excluded — the reviewer is strictly
  cross-document.
- `matches[P]` is capped at `MaxMatchesPerProvision` (default 20), highest-confidence
  first.

LLM calls run through the artifact-review window-grouped executor (bounded by
`REVIEW_MAX_TASKS`); stop requests are honored at each call boundary (refer to [3] and
the doc-processor stop contract). When `max_tool_turns > 0`, the reviewer uses the
tool-use loop with configured read-only tools.

All Branch A/B retrieval happens before the LLM call and before any tool-use loop. The
LLM receives the provision-under-review plus the already-retrieved matching provisions in
its input payload. Tools are only an optional follow-up mechanism for additional context;
they are not responsible for discovering the object-anchored matches.

### 3.3 Tool Use
`reviewers.provisions` already receives the provision under review, matched cross-document
provisions, source_context for each match, authority hints, and the source window.
The LLM’s only legitimate follow-up need is: “show me more source lines around this
artifact so I can verify scope/conditions before raising or suppressing a conflict.”

That is exactly what [get_artifact_context (line 528)](/Users/cding/Workspace/ChenWeb/server/api/doc-reviews/review-tools.go:528) does. It is also intentionally cross-record, unlike
the core tools.

We would not expose these by default:
- search_provisions / get_provision: scoped only to the document under review, while the reviewer’s cross-document candidates are already retrieved deterministically before the LLM loop.
- search_entities, get_entity, get_entity_relations: likely to pull the model into broad exploratory reasoning and create noisy provision findings.
- search_metrics, get_metric: useful for metrics reviewers, but not for provision consistency unless we design an explicit mixed provision/metric reviewer.
- get_chunk_summary: too abstract for conflict verification.
- get_chunk_lines: tempting, but mostly redundant because the reviewer already gets a ~200-line source window and get_artifact_context can fetch artifact-centered lines. Add only if logs show repeated “needed wider current-document context” failures.

The implemented tool set is `["get_artifact_context", "get_document_metadata"]`.
`get_document_metadata(record_id)` reads `kb.inputs.doc_metadata` plus scalar input fields
and returns the document title, document number, filename, publication/implementation
dates, language, extracted metadata, and the same `authority_class` heuristic used in the
matched-provision payload. This supports currency and authority checks without opening
broad search.

### 3.3 Provision Review Harness

Document review is an agentic application: the deterministic code prepares evidence,
budgets, tools, and storage boundaries, while the LLM is the reviewer brain that decides
what the evidence means. The provision reviewer makes that split explicit. The "harness"
is the code path around each LLM review turn; it does not only send a prompt. It builds
the artifact work units, places each unit in a bounded multi-turn conversation, validates
tool calls and JSON responses, normalizes findings, persists per-match analyses, and
decides what to do when the model or a dependency misbehaves.

The current harness is configured by `reviewers.provisions` in `doc-review.local.toml`:
- `input="artifact"`,
- `model="deepseek-flash-chen"`,
- `prompt="prompt-review-provisions-v4.md"`,
- `max_tool_turns=4`,
- `max_tool_tokens=24000`,
- `tools=["get_artifact_context", "get_document_metadata"]`.

Because the input is `artifact`, `buildReviewers` routes the reviewer through the
legacy/document runner that
calls `provisionsReviewer.ReviewDocument` directly, rather than through the ordinary
chunk/block scheduler. The reviewer still reuses the scheduler's canonical windows for
cache layout and source context.

The outer loop is deterministic and provision-centric:

```text
load provisions for record_id
cap with PROVISION_REVIEW_MAX_PROVISIONS, when set
for each provision:
  retrieve matching provisions with live hybrid search and object-anchor retrieval
  dedupe, exclude same-record matches, cap with PROVISION_REVIEW_MAX_MATCHES
hydrate source_context for each matched provision
load canonical ~200-line artifact review windows
build one review unit per provision
run units window-grouped: seed one unit per window, stagger, then run the remainder
```

Each review unit is one agentic review of one provision-under-review. The user message is
assembled with the AR2 window-first layout:

```text
<DOCUMENT_INPUT>
{canonical source window JSON}
</DOCUMENT_INPUT>

<REVIEW_TASK>
{prompt-review-provisions-v4.md}

# ARTIFACT REVIEW INPUT
{provision_under_review, artifact_line_spans, context_truncated, matching_provisions}
</REVIEW_TASK>
```

When no source window can be resolved, the harness sends only `<REVIEW_TASK>...`.
If a provision span crosses the selected window boundary, the payload includes
`context_truncated=true`; the prompt tells the model not to treat this as an extraction
error and to use `get_artifact_context` when more context is needed.

The prompt is part of the harness contract, not decorative text. Version 4 requires two
separate outputs:

- `analyses`: one comparison record for every entry in `matching_provisions`, even when
  there is no issue.
- `findings`: only the reportable issues or observations.

This matters because "no finding" is not the same as "no review happened." The raw parsed
payload is returned alongside normalized findings so the harness can preserve both output
streams. Findings are normalized into `ReviewFinding`, tagged with `Pass="P5"`,
`Aspect="provisions"`, and `ArtifactID=<prov_id>`, and defaulted to
`finding_type="issue"`, `severity="low"`, and the provision source line spans when the
model omits those fields. Cross-document links stay structured through
`related_artifact_id` and `related_record_id`.

#### Implemented Solution — Store Analyses as Review Results

The implementation parses `analyses` from the provision prompt payload, converts each
analysis into a first-class `ReviewFinding`, and returns those rows from `reviewProvision`
alongside reportable issues/observations. The outer review runner therefore persists
analyses to the canonical `kb.doc_review_findings` table using the normal findings store.
The existing `kb.doc_review_provision_analyses` write remains as a compatibility read
model while report/API readers migrate.

The storage contract is:

- Every `analyses[]` entry becomes one `kb.doc_review_findings` row.
- Analysis rows use `pass="P5"`, `aspect="provisions"`, `artifact_id=<prov_id>`,
  `related_artifact_id=<analysis.related_artifact_id>`, and
  `related_record_id=<analysis.related_record_id>`.
- Analysis rows use `finding_type="analysis"` so they are distinguishable from
  `issue` and `observation` findings.
- Analysis rows use `severity="info"` and `confidence=1.0` unless the prompt later emits
  an explicit confidence for analyses.
- `title` should be deterministic, e.g.
  `Provision comparison: <prov_id> vs <related_artifact_id>`.
- `description` should be `analysis.summary`.
- `evidence` should identify the compared provisions and, when cheap to include, the
  relationship and source filename. The summary remains the human-readable conclusion.
- `suggestion` should be empty for benign analyses. If the analysis says it rises to a
  finding, the suggestion belongs on the corresponding reportable finding, not on the
  analysis row.
- `metadata` should include `result_kind="provision_analysis"` and
  `analysis_relationship=<same_subject|related_subject|unrelated>`, alongside the existing
  related-artifact metadata.

The mapping is intentionally lossy only in presentation, not in identity: the important
query keys (`run_id`, `input_record_id`, `aspect`, `artifact_id`,
`related_artifact_id`, `related_record_id`) are native `doc_review_findings` fields or
existing metadata-derived fields. A report, API response, or UI can therefore retrieve all
provision review results from one table and split them by `finding_type`.

`kb.doc_review_provision_analyses` is now a compatibility/read-model table rather than the
source of truth. There are two migration phases:

1. **Dual-write transition (current):** write analyses to `kb.doc_review_findings` and
   continue writing `kb.doc_review_provision_analyses` until the Typst report and any
   API/UI readers consume analysis rows from `doc_review_findings`.
2. **Single-write after readers move:** stop inserting into
   `kb.doc_review_provision_analyses`; either leave the table for historical runs or add a
   backfill migration/view that derives its shape from `doc_review_findings` rows where
   `aspect='provisions'` and `finding_type='analysis'`.

Dual-write is operationally safer: existing reports keep working while the canonical table
starts receiving complete results. After a backfill and reader migration, the side table
can be deprecated.

This change also makes count semantics explicit at the row level. Consumers that need
issue counts can filter out `finding_type="analysis"`; coverage views and per-provision
report sections can include it.

With `max_tool_turns > 0` and a resolved chat client, each unit uses
`runToolUseReviewWithPayload`. The conversation starts with a small common system message:
"You are a document review engine. Return strict JSON findings only unless you need to
call an available tool." The first user message is the window-first review task above,
and the available tool definitions are adapted from the configured tool registry. For the
current provisions reviewer, the only exposed tool is `get_artifact_context`; the model
can use it to verify source lines around an artifact when the included `source_context`
or source window is insufficient.

The inner multi-turn loop is:

```text
for turn in 1..MaxToolTurns:
  call the tool-capable model with messages and tool definitions
  record LLM usage and turn_count metadata
  if the model requested tools:
    append assistant tool_calls
    execute each tool call
    append each tool result as a tool-role message
    if MaxToolTokens is exhausted, break to finalization
    continue
  if the model returned parseable JSON with a findings key:
    return normalized findings plus raw payload
  otherwise:
    ask one final no-tools repair/finalization call and return or fail
finalize without tools
```

A model response is treated as either tool calls or findings, never both. Tool calls take
precedence. The harness validates tool names and required arguments, scopes execution by
`record_id`, and converts tool failures into JSON error payloads for the model to read
and recover from; a bad tool call does not abort the review unit by itself.

If the turn budget or token budget is exhausted, the harness force-finalizes. It appends a
final user instruction telling the model that the investigation budget is spent and that
it must return strict JSON of the form `{"findings":[...]}`, using only evidence already
collected. This finalization call is made without tools. A valid `{"findings":[]}` is a
normal outcome. If the final response is malformed, the harness performs a repair pass for
common JSON failures or for DSML-style text tool calls emitted after tools are closed; if
that repair also fails, the unit logs the parse error and returns no findings for that
provision.

Error handling is intentionally local to the provision unit where possible:

- Missing database handle, provision-load failure, or match-build failure aborts the
  reviewer because the harness cannot establish the review evidence.
- No extracted provisions or no review units is a logged zero-finding outcome.
- Source-window load failure degrades to payload-only review; it is logged but not fatal.
- Payload marshal failure, one-shot LLM failure, tool-loop failure, analysis persistence
  failure, and malformed final JSON are logged and isolated to the current provision.
- Stop requests are checked before turns and unit execution; completed findings are
  returned with `ErrPipelineStopped` when the stop is observed.

This design keeps the LLM in the reasoning seat while keeping the application in charge of
repeatability, cost, and persistence. The LLM can ask for context over several turns, but
the harness decides which tools exist, how many turns and tokens are allowed, how responses
are parsed, what defaults are applied, and how partial failures affect the review run.

### 3.3 Alternative Decisions
- **Add a corpus-wide category-sibling branch (as in the metric reviewer):** deferred.
  Provision `category_paths` are hierarchical path strings (e.g. `"safety/electrical"`),
  not flat category keys, so a `?|` overlap match is noisier for provisions than for
  metric category keys. Live semantic search (Branch A) already captures cross-document
  provision similarity well. Can be added later if recall proves insufficient.
- **Live hybrid search at review time:** originally rejected by analogy to the first
  metric ADR, then accepted on 2026/07/01. This is now Branch A.
- **Document-level entity branch:** removed from the reviewer design. It used
  entity->provision edges for all entities extracted from the document-under-review, then
  attached targets by category-path overlap. That is a weak provision-under-review
  relevance signal compared with live hybrid search and object-anchored retrieval.
- **Tool-use (agentic) reviewer (`max_tool_turns > 0`):** originally not adopted, then
  implemented by ADR 2026070201 AR4/AR5. Current configuration uses
  `max_tool_turns = 4`, `get_artifact_context`, and `get_document_metadata`.

### 3.4 Database Migrations
The reviewer reads `kb.provisions`, `kb.search_artifacts`, `kb.artifact_objects`,
`kb.object_nodes`, and object-id `kb.artifact_connections` edges; writes reportable
findings to `kb.doc_review_findings` (run-scoped via `run_id`, [5]); and should also write
each provision comparison analysis to `kb.doc_review_findings` as
`finding_type="analysis"`.

No new table is required for analysis rows if the implementation uses the existing
`doc_review_findings` columns plus metadata. If strict metadata keys are enforced in code,
extend the finding metadata envelope/reserved keys with:

```json
{
  "result_kind": "provision_analysis",
  "analysis_relationship": "same_subject | related_subject | unrelated"
}
```

`kb.doc_review_provision_analyses` currently exists as a reviewer-specific side table. It
should be treated as transitional. Keep it during dual-write and deprecate it after
reports/API/UI readers can derive provision analyses from `kb.doc_review_findings`.

Provision object extraction/reconciliation tables and object-id connection partitions
are owned by ADR 2026070101, not by this reviewer ADR.

### 3.5 Data Formats

**Provision view (loaded from `kb.provisions`)** — the "provision under review":

```json
{
  "prov_id": "1001_prv_3",
  "prov_name": "Pressure relief requirement",
  "provision_type": "requirement",
  "provision": "The system shall include a pressure relief valve rated for 1.6 MPa.",
  "provision_subject": "pressure relief",
  "category_paths": ["safety/pressure", "equipment/valve"]
}
```

**Matching provision** — same shape plus match provenance:

```json
{
  "provision": { ... provision view ... },
  "source_record_id": 2002,
  "source_filename": "GB_50316_pipe_design.pdf",
  "match_via": "hybrid_search | object_anchor",
  "match_rank": 1,
  "source_doc_authority": "standard"
}
```

**Finding output** — the standard review-finding JSON (`ReviewFinding`); the reviewer
sets `Pass="P5"`, `Aspect="provisions"`, defaults `finding_type="issue"`,
`severity="low"`, and `location` from the provision's `source_line_spans` when the model
leaves them empty.

**Analysis output** — the mandatory comparison-analysis JSON from
`prompt-review-provisions-v4.md`; each entry should be converted into a
`kb.doc_review_findings` row:

```json
{
  "pass": "P5",
  "aspect": "provisions",
  "severity": "info",
  "finding_type": "analysis",
  "title": "Provision comparison: 1001_prv_3 vs 2002_prv_9",
  "description": "The provisions govern the same pressure relief requirement but use different rating thresholds...",
  "evidence": "relationship=same_subject; provision_under_review=1001_prv_3; related=2002_prv_9",
  "location": "88-90",
  "suggestion": "",
  "confidence": 1.0,
  "artifact_id": "1001_prv_3",
  "related_artifact_id": "2002_prv_9",
  "related_record_id": 2002,
  "metadata": {
    "result_kind": "provision_analysis",
    "analysis_relationship": "same_subject"
  }
}
```

### 3.6 Environment Variables
- `REVIEW_MAX_TASKS` (existing) — bounds the per-provision LLM fan-out.
- `PROVISION_REVIEW_MAX_MATCHES` (new, optional, default `20`) — cap on matching
  provisions per doc provision.
- `PROVISION_REVIEW_MAX_PROVISIONS` (new, optional, default `0` = no cap) — cap on the
  number of doc provisions reviewed.

## 4. Implementation

### 4.1 Code Changes

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-reviews/review-provisions.go` | `provisionsReviewer` implementing `Reviewer` (`Name()="provisions"`, `Group()="P5"`, `Strategy()=StrategyDocument`). `ReviewDocument` loads provisions, builds matches from live `FindSimilarArtifactsOnTheFly` plus object-anchored provision rosters, hydrates source context, and runs window-grouped artifact review units. Tool-use is enabled when configured. |
| `ChenWeb/server/api/doc-reviews/review-document.go` | Resolves `provisions`/P5 runtime, budget, and tool config; appends the `provisionsReviewer` runner with `cfg.Input="artifact"`. `ReviewFindingsSQLStore` remains the canonical writer for rows in `kb.doc_review_findings`; converted analysis rows now pass into the same store. |
| `ChenWeb/server/api/doc-reviews/models.go` / finding metadata helpers | Add metadata support for `result_kind="provision_analysis"` and `analysis_relationship`, while preserving existing i18n and related-artifact metadata. |
| `ChenWeb/server/api/doc-reviews/review-tools.go` | Adds `get_document_metadata(record_id)`, a narrow read-only metadata tool over `kb.inputs` / `doc_metadata`. It is registered but not part of `coreToolNames`; reviewers must opt in via TOML. |
| `ChenWeb/server/api/doc-processing/search_artifact_indexing.go`, `extract-provisions.go` | Reindex provisions in `kb.search_artifacts`, persist/reconcile provision objects, and index provision object-node edges under the shared object contract. |
| `ChenWeb/doc-review.local.toml` | `reviewers.provisions`: `input="artifact"`, `model="deepseek-flash-chen"`, `prompt="prompt-review-provisions-v4.md"`, `max_tool_turns=4`, `max_tool_tokens=24000`, `tools=["get_artifact_context", "get_document_metadata"]`. |
| `ChenWeb/prompts/prompt-review-provisions-v4.md` | Current prompt (requires per-match `analyses` plus reportable `findings`; instructs when to use source-context vs document-metadata tools). |
| `ChenWeb/server/api/doc-reviews/typst_report.go`, `controller.go`, result summary UI | Follow-up reader migration: treat `finding_type="analysis"` as coverage/comparison evidence and filter it out where a view wants issue counts only. |
| `ChenWeb/server/api/doc-reviews/review-provisions_test.go` | **New** tests (assembly branches/dedup/exclusion/cap; reviewProvision payload + tagging). |

Target resolution maps live-search hit ids and object-edge artifact ids to
`kb.provisions` rows. Because `prov_id` is globally unique (`"<record>_prv_<n>"`),
resolution batches by `prov_id` (`WHERE prov_id = ANY($1)`), like the metric reviewer.

## 5. Operational Behaviors
- **No provisions / no matches:** returns zero findings (logged, not an error).
- **Dependency:** meaningful after `extract_provisions` has populated `kb.provisions`,
  `kb.search_artifacts`, and the ADR 2026070101 object graph: artifact-object
  persistence, object-node reconciliation, and object `belong_to` indexing.
- **Parallelism & stop / idempotency:** identical to the metric reviewer and all
  reviewers — concurrent per-provision calls under `REVIEW_MAX_TASKS`, stop at the next
  boundary, findings and analysis rows written under the current `run_id` (prior run
  findings deleted by `PostProcessIndex`).
- **Analysis visibility:** analyses are complete review-output rows. Consumers that need
  issue-only counts can filter `finding_type='analysis'`; coverage views can include it.

## 6. Consequences
**Positive**
- Cross-document provision consistency: conflicting/contradictory requirements,
  prohibitions, or obligations across the corpus that no single-document reviewer can
  see.
- Live hybrid search avoids stale/directional semantic edges while reusing the shared
  lexical/vector search registry and existing reviewer plumbing.
- Object-anchored matching retrieves provisions tied to the same canonical object as the
  provision-under-review, improving relevance over document-level entity co-occurrence.
- Storing analyses in `kb.doc_review_findings` makes the review result query model
  complete: a consumer can reconstruct both "what was flagged" and "what was checked" from
  the same run-scoped table.

**Negative / cost**
- Per-provision live search adds read-time search cost; bounded by
  `PROVISION_REVIEW_MAX_PROVISIONS` and `MaxMatchesPerProvision`.
- Per-provision LLM fan-out bounded by `PROVISION_REVIEW_MAX_PROVISIONS` and
  `MaxMatchesPerProvision`.
- No category-sibling recall path (deferred); some related provisions that lack a
  live semantic-search hit will not be compared.
- Object-anchored recall depends on provision object extraction and reconciliation
  quality. Provisions without a reconciled `object_id` rely on live hybrid search only.
- Analysis rows will increase `kb.doc_review_findings` row counts substantially, so
  summaries must filter by `finding_type` instead of treating every row as a reportable
  issue.

## 7. Tests
- Branch A: a doc provision with a live hybrid-search hit to a cross-document provision
  -> one LLM call, finding tagged `P5`/`provisions`.
- Branch B: an object-anchored provision in another document is attached to the
  provision-under-review through `kb.artifact_objects` -> `kb.object_nodes` ->
  `kb.artifact_connections`.
- Dedup: a target reached via both branches appears once.
- Same-document exclusion: a target with `target_record_id = record_id` is dropped.
- Cap: `MaxMatchesPerProvision` truncates to highest-confidence matches.
- No matches → no LLM call, no findings.
- `reviewProvision` payload contains `provision_under_review` + `matching_provisions`;
  findings get `Pass=P5`/`Aspect=provisions` and default severity/type/location.
- `analyses` entries are converted into `ReviewFinding`/storage rows with
  `finding_type="analysis"`, `severity="info"`, `ArtifactID=<prov_id>`, structured
  related artifact fields, and `metadata.result_kind="provision_analysis"`.
- Storage tests verify analysis metadata is written through `kb.doc_review_findings`.

## 8. Documentation Impact
- `doc-processor/+CAPSULE.md` [1]: no pipeline-table change (provisions review is an
  aspect, not a doc processor).
- This ADR + `prompt-review-provisions-v4.md` are the current design/behavior records.
  Shares the live-search and reviewer-integration design with ADR 2026063002 [4].
- Intentionally left undocumented here: exact live-search RRF weighting (owned by
  `search_artifact_indexing.go` / extract-provisions spec); the deferred
  category-sibling branch. Object extraction/reconciliation policy is documented by ADR
  2026070101 [7].

## 9. References
- [1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- [2] `ChenWeb/doc-review.local.toml`
- [3] `KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md` (run model) and `ChenWeb/server/api/doc-reviews/review_cache_scheduler.go` (dispatch)
- [4] ADR 2026063002 — Metric Document Reviewer (shared architecture, connection loader)
- [5] ADR 2026062804 — `kb.doc_review_runs` run model (run-scoped findings)
- [6] Extract Provisions Spec: `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-spec.md`
- [7] `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
