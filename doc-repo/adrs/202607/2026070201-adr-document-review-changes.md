# ADR 20260702 — Document Review: Artifact Reviewer Context, Prompt-Cache Layout, and Missing-Metric Detection

**Date:** 2026-07-02 \
**Status:** Accepted — Stages 1-5 implemented 2026/07/03; Stage 6 open \
**Component:** ChenWeb — `server/api/doc-reviews`, `prompts`, `doc-review.local.toml` \
**Authors:** Chen Ding \
**Tags:** doc review, artifact reviewers, prompt cache, DeepSeek, metrics, provisions, inventory items, missing requirements

---

## Change Logs

* 2026/07/02, ADR created from the investigation of review request #27 (record 387)
  and the follow-on design discussion on artifact reviewer context, DeepSeek
  prompt-cache layout, prompt quality, and object-anchored missing-metric detection.
* 2026/07/03, resolved the two open questions (AR2: multi-window spans map to the
  window containing the span start; AR3: no per-window group cap — concurrency is
  bounded by the run-level semaphore). Rewrote AR6 to match the implemented object
  indexing ([8]–[10]: `belong_to` edges in `kb.artifact_connections`, one-to-many
  artifact → object mentions) and unblocked its implementation (Stage 5 now depends
  on Stage 4, not on pending object data).
* 2026/07/03, **Stages 1-4 implemented** in ChenWeb `server/api/doc-reviews`:
  AR1 TOML/`buildReviewers` precedence notes; AR2 window-first layout
  (`review-artifact-window.go`: canonical `buildChunkInputs` windows, span-start
  mapping, `context_truncated` flag); AR3 window-grouped seed → stagger → remainder
  execution (`runArtifactUnitsWindowGrouped`); AR4 cross-record
  `get_artifact_context` tool + tool-use enabled for the three artifact reviewers
  (max_tool_turns=4, max_tool_tokens=24000); AR5 prompt v2 files and
  `related_artifact_id`/`related_record_id` in the findings schema (persisted in
  the findings metadata JSONB). Matched payloads now carry `source_doc_authority`
  (heuristic standard/regulation/peer classification) and `match_rank` instead of
  raw RRF confidence. Stage 5 (AR6 `metrics_completeness`) and Stage 6 (AR7 A/B)
  remain open.
* 2026/07/03, **Stage 5 (AR6) implemented** — object-anchored missing-metric
  detection (`review-metrics-completeness.go`): builds per-object rosters from
  `kb.artifact_objects` (metric_id → object_id) and `kb.artifact_connections`
  (`source_type='metric'`, `target_id=<object_id>`, `relation_method='object_id'`);
  one LLM call per object with the doc's attached metrics vs. peer documents'
  metrics for the same (and comparable) objects; tool-use with `search_metrics`
  for the mandatory absence-verification step (AR6 §4), `get_artifact_context`
  for screened candidates; `prompt-review-metrics-missing-v1.md`; wired into
  `doc-review.local.toml` as `metrics_completeness` (P5, tool-use enabled,
  max_tool_turns=4). Stage 6 (AR7 object-anchored batching A/B) remains open.

---

## Context

### Trigger: review request #27 goroutine investigation

Review request #27 (record 387, "Review for Regulated" tier, 6 aspects, 6 chunks)
was expected to fan out 6 goroutines per reviewer (one per chunk) through the
prompt-cache scheduler (ADR 2026061801 §DR8a). Instead, only one reviewer fanned
out in Phase 1 and one in Phase 3. Investigation showed this is **by design**, but
it exposed several real problems.

The six selected aspects split into two kinds:

| Aspect | `Input` | Execution path |
|---|---|---|
| `legal_compliance` | `per-chunk` (TOML) | prompt-cache scheduler (Phase 1 seed, 6 goroutines) |
| `regulatory_compliance` | `per-chunk` (TOML) | prompt-cache scheduler (Phase 3, 6 goroutines) |
| `metrics` | `artifact` (hardcoded) | `runReviewersLegacy` → `ReviewDocument` (1 goroutine) |
| `provisions` | `artifact` (hardcoded) | `runReviewersLegacy` → `ReviewDocument` (1 goroutine) |
| `entities` | `artifact` (hardcoded) | `runReviewersLegacy` → `ReviewDocument` (1 goroutine) |
| `inventory_items` | `artifact` (hardcoded) | `runReviewersLegacy` → `ReviewDocument` (1 goroutine) |

The four artifact reviewers (ADRs 2026063002–2026063005) are **not text
reviewers**: their unit of work is one extracted artifact (a metric, provision,
entity, or inventory item) compared against semantically-matched artifacts from
OTHER documents. They fan out internally via `runReviewerConcurrent`, one LLM
call per artifact that has at least one cross-document match. Routing them
around the chunk scheduler is correct; what is wrong is what those calls contain
and how they are laid out.

### How an artifact review call works today (metrics as the example)

1. `loadRecordMetrics` loads the document's extracted metrics from `kb.metrics`.
2. `buildMatches` finds candidate related metrics in other documents via three
   branches: live hybrid search (`FindSimilarArtifactsOnTheFly`), shared category
   key, and shared entity edges. Capped at `METRIC_REVIEW_MAX_MATCHES` (20).
3. For each metric with ≥1 match, one LLM call receives a JSON payload of
   `metric_under_review` (structured fields only: name, subject, value, unit,
   value_class, categories) plus up to 20 `matching_metrics` (same shape, plus
   `source_record_id`, `source_filename`, `match_via`, `confidence`).
4. The call uses `newDocReviewLLMJSONInput` with `DocumentFirst = true`: the
   per-metric payload is placed **before** the reviewer rubric.

Provisions and inventory items follow the same pattern (provisions at least
carry the normative sentence in the `provision` field; metrics and inventory
items carry no source text at all).

---

## Problems

**P1 — Stale, misleading configuration.** `doc-review.local.toml` declares
`input = "per-chunk"` for `metrics`, `provisions`, `entities`, and
`inventory_items`, but `buildReviewers` hardcodes `Input: "artifact"` in each
runner's `ReviewerConfig`, and the scheduler only consults the TOML when
`cfg.Input` is empty. The config file silently lies; this directly caused the
request-#27 confusion.

**P2 — No source context in artifact review calls.** The LLM receives only the
structured extraction. Yet all three prompts instruct it to dismiss differences
"explained by different subjects, conditions, or contexts" — a rule it cannot
apply, because conditions, tolerances, test setups, and applicability qualifiers
live in the surrounding text that was stripped at extraction time. Combined with
the prompts' "better to miss a borderline conflict than to flag a false
positive" rule, the model is systematically biased toward suppression: both
false negatives (real conflicts dismissed for lack of context) and false
positives (condition-explained differences flagged) are structural.

**P3 — Zero prompt-cache reuse for artifact reviewers.** `DocumentFirst = true`
puts the unique per-artifact payload first in the user message. DeepSeek's
context cache is prefix-based; a unique prefix on every call means ~0 cache-hit
tokens across the ~dozens of calls per aspect (observable in the
`cache_hit_tokens` field already logged per call). The DR8a document-first
layout is correct for chunk reviewers (shared chunk → cross-reviewer reuse) but
inverted for artifact reviewers, whose only stable content is the rubric.

**P4 — Consistency-only scope.** The prompts check only cross-document
*conflict*. Corroborations, outliers (a value outside the range every peer
document uses), currency signals (the matched document is a newer edition of the
same standard), and near-miss coverage gaps are explicitly discarded ("Do NOT
report … restatements or corroborations"). For a paid deep-research-style
review, that discards signal the customer pays for.

**P5 — No source-authority model.** A conflict with a governing national
standard (GB/ISO/IEC) and a conflict with a peer internal document are treated
identically. The payload carries `source_filename` but no document type or
authority rank, so severity cannot reflect what matters most (compliance gaps
against governing standards).

**P6 — Confidence-scale trap.** Hybrid-search RRF scores are inherently tiny
(the prompt's own example shows `confidence: 0.0123`). The prompts call it a
"weak signal" but never explain the scale; the model plausibly reads 0.0123 as
"essentially unrelated" and dismisses valid candidates.

**P7 — No missing-artifact detection.** ADR 2026061801 names detecting what a
document *should have but doesn't* as the central value proposition (DR6). The
artifact reviewers cannot detect absence: a per-metric call structurally cannot
see what is missing, and no expectation model exists at the metric level yet.

**P8 — Unstructured cross-references in findings.** Findings reference the
conflicting artifact only in free-text `evidence`. The report generator and GUI
cannot link a finding to the matched artifact/record without parsing prose.

---

## Decision

Decisions are numbered AR1–AR7 (Artifact Reviewer).

### AR1 — Configuration tells the truth

Change `doc-review.local.toml` to declare `input = "artifact"` for `metrics`,
`provisions`, `entities`, and `inventory_items`. Document (in the TOML comments
and in `review-document.go`) that a non-empty `ReviewerConfig.Input` set in
`buildReviewers` takes precedence over the TOML `input` field, so a future
reader is not misled again.

### AR2 — Source window auto-included, chunk-first, byte-identical to the scheduler windows

Every artifact review call includes the source passage of the artifact under
review, placed **first** in the user message (before the rubric), so that calls
sharing a window share a cacheable prefix:

```text
system:  stable one-liner                      (never changes → always cached)
user:    <DOCUMENT_INPUT>
         canonical chunk-window JSON            (cached across reviewers and
                                                 across artifacts in the window)
         </DOCUMENT_INPUT>
         <REVIEW_TASK>
         reviewer rubric                        (cached within reviewer+window)
         artifact_under_review + matches        (unique tail — the only
                                                 regularly-paid tokens)
         </REVIEW_TASK>
```

Critically, the included window is **not** an ad-hoc ±N-line slice: it is the
canonical 200-line window produced by `buildChunkInputs` (same lines, same
`doc_context` envelope, byte-identical serialization). The per-chunk reviewers
in the same run (e.g. `legal_compliance`, `regulatory_compliance`) send those
exact windows as prefixes, so artifact reviewer calls ride on a cache those
reviewers have **already warmed** — in a mixed run, even the first artifact call
per window is typically a cache hit.

Mapping: an artifact maps to the window containing the start of its
`line_spans`. If a span crosses a window boundary, use the window containing the
span start; do not concatenate windows (a concatenation is a new, uncacheable
prefix).

Secondary benefit: with the source passage visible, the reviewer can also flag
extraction errors (extracted value disagrees with the passage) — findings that
protect every downstream consumer of the artifact.

Multi-window spans (decided): an artifact whose line spans cross window
boundaries is always mapped to the window containing its span start — the same
rule as above, applied uniformly. Windows are non-overlapping fixed slices, so
no alternative single window is a better fit, and any concatenated or ad-hoc
slice is a new, uncacheable prefix. Two mitigations for the truncated tail
context:

1. The unique tail of the payload carries `context_truncated: true` plus the
   artifact's full line span, so the model knows the window ends mid-artifact
   and does not misreport the truncation as an extraction error.
2. The AR4 tool `get_artifact_context` may be called on the artifact under
   review itself to retrieve the truncated remainder (within the same tool
   budget).

### AR3 — Chunk-grouped scheduling for artifact review units

Artifact review units are grouped and ordered by their source window, and
executed with the same seed → stagger (`LLM_CALL_STAGGER`) → remainder pattern
the prompt-cache scheduler uses: one unit per window fires first to plant (or
confirm) the prefix, the window's sibling units follow. Since metrics and
inventory items cluster heavily in spec tables and rosters, the grouping factor
is expected to be high.

Group size (decided): no per-window cap. The cache is keyed by prefix, not by
group — 50 artifacts in one window share the same cached prefix whether they
run as one group or five, so splitting a window's units into multiple groups
buys nothing: each sub-group would either waste its own seed + stagger wait on
an already-warm prefix, or complicate the scheduler with seedless groups.
Sibling bursts are already bounded by the run-level semaphore
(`maxDocReviewerTasks` / `MaxConcurrent`) plus `LLM_CALL_STAGGER`. If cost
control for pathological documents is ever needed, the right knob is a
per-aspect unit budget (a separate config item), not a group-size cap.

### AR4 — Matched-artifact context on demand via a cross-record tool

Do **not** eagerly load source passages for the up-to-20 matched candidates
(most are hybrid-search noise; eager loading multiplies input tokens ~20× and
dilutes attention). Instead:

- Add one new tool to the DR10a catalog:
  `get_artifact_context(record_id, artifact_id)` → the ±10–20 lines around the
  artifact's `line_spans` in its source document. Unlike the record-scoped core
  tools, this tool is cross-record; it serves metrics, provisions, entities, and
  inventory items alike. It may also be called on the artifact under review
  itself, e.g. to retrieve context truncated at a window boundary (AR2).
- Enable the tool-use path (DR10b) for the artifact reviewers with a modest
  budget: `max_tool_turns = 3–5`, bounded `max_tool_tokens`. The investigation
  here is shallow — verify or dismiss specific screened candidates — not
  open-ended research.

This is the screen-then-verify pattern: structured views suffice to screen
("3 of 20 candidates plausibly describe the same quantity"); source context is
retrieved only for the survivors. Tool-result turns are unique tokens and do not
disturb the AR2 prefix strategy.

### AR5 — Prompt v2 for metrics, provisions, inventory items

Produce `prompt-review-metrics-v2.md`, `prompt-review-provisions-v2.md`,
`prompt-review-inventory-items-v2.md` with these changes:

1. **Recall stance.** Replace "better to miss a borderline conflict than to flag
   a false positive" with: confirmed conflicts → `finding_type: "issue"`;
   plausible-but-unverified discrepancies → `finding_type: "observation"` with
   `confidence < 0.5`. Suppression at review time is irreversible; filtering
   observations is a display decision.
2. **Broadened checks (still cross-document).** In addition to conflicts, report
   outlier values relative to the peer set, currency signals (matched document
   supersedes / is superseded), and systematic patterns across matches.
3. **Source authority.** Extend the matched payload with a document
   type/authority field (standard / regulation / peer specification / internal
   document). Instruct the model to weight severity by authority: a conflict
   with a governing standard is the compliance-gap case.
4. **Confidence scale.** Normalize match scores to 0–1 before sending, or
   replace with rank; explain the field in the prompt either way.
5. **Insufficient-information outlet.** When relatedness cannot be determined
   from the provided fields and tool budget is exhausted (or tools are
   unavailable), emit an observation stating what context would be needed,
   rather than staying silent.
6. **Structured cross-references.** Add `related_artifact_id` and
   `related_record_id` to the findings schema so the report generator and GUI
   can link cross-document findings without parsing `evidence` prose.
7. **Source-window instructions (AR2).** Teach the prompt the new input layout:
   the `<DOCUMENT_INPUT>` window is the extraction context of the artifact under
   review; use it to judge conditions/qualifiers and to verify the extraction
   itself.

The `entities` reviewer and its prompt are **out of scope** for this ADR
(separate discussion planned).

### AR6 — Object-anchored missing-metric detection

Detecting absence requires an expectation model. The object-centric design
(ADR 2026070101) provides it: each extraction processor writes object mentions
to `kb.artifact_objects` (one artifact → one or more object mentions),
reconciliation links mentions to canonical `kb.object_nodes` via
`artifact_objects.object_id`, and at index time each processor adds `belong_to`
edges to `kb.artifact_connections` (artifact family → object node, contributing
artifact IDs in `extra_info`). Given an object node, all related metrics,
provisions, and inventory items across documents are reachable through these
edges.

The canonical object is therefore the anchor, and the union of artifacts
(`metrics`, `provisions`, `inventory_items`) that peer documents attach to
comparable objects is the expectation roster.

Refer to [8], [9] and [10] for how these indexes are built.

Below is the algorithm to retrieve artifacts through object:
- For a given metric/provision/inventory_item:
  - Retrieve its artifact id: <artifact_id>
  - Retrieve <object_id> = `kb.artifact_objects.object_id` by `kb.artifact_objects.artifact_id` = <artifact_id>
  - Retrieve all metrics/provisions/inventory_items <artifact_ids> from `kb.artifact_connections` where `kb.artifact_connections.source_type` = T AND `kb.artifact_connections.target_id` = <object_id> 

Decisions taken now:

1. **Separate pass, separate prompt.** Missing-metric detection is
   **object-centric** (one object, its full metric set in this document, vs. the
   metric sets peers attach to comparable `kb.object_nodes`), not metric-centric.
   It runs as a second pass inside the metrics reviewer (or a sibling aspect,
   e.g. `metrics_completeness`) with its own prompt file
   (`prompt-review-metrics-missing-v1.md`). The AR5 conflict prompts are **not**
   adapted for it — without the object→metric data the model has no basis for
   absence claims, and hedged language would degrade conflict findings.
2. **Finding type.** `finding_type: "missing_metric"`, alongside DR6's
   `missing_requirement` / `missing_provision`. The report template surfaces it
   with the compliance-gap highlights.
3. **Support signals, not mechanical flagging.** The payload carries how many
   comparable objects across how many peer documents attach the metric, and the
   authority of those documents (AR5 §3). The model judges expectedness relative
   to `doc_context`; "one peer has it" is not "you must have it."
4. **Verify absence before claiming it.** Extraction and object-linking both
   have recall gaps: the metric may exist in the document but lack the edge.
   Before emitting `missing_metric`, the reviewer must search the document's own
   metric roster by name/synonym — the record-scoped `search_metrics` tool
   (DR10a) exists for exactly this. This distinguishes "missing from the
   document" from "missing an edge in the graph."
5. **Provenance requirement.** The object→metric linkage must carry evidence
   (line spans, confidence) for findings to cite. ADR 2026070101 §DR2 already
   mandates this on `kb.artifact_objects`; this ADR records the review-side
   dependency on it.
6. **Extension path.** The same pattern extends to provisions (object → expected
   provisions) and inventory items (item → expected `normalized_specs`) once
   metrics proves it out.

The object tables, reconciliation, and `belong_to` indexing are implemented for
metrics, provisions, and inventory items ([8], [9], [10]); this pass is now
unblocked and proceeds as Stage 5.

### AR7 — Batching: one artifact per call in Phase 1; object-anchored batching later

Keep one artifact per LLM call for now: batching risks attribution errors
(findings citing the wrong `metric_id`), whole-batch loss on one malformed JSON
response, attention dilution, and coarser per-unit progress reporting. With
documents normally under ~50 metrics, call-count overhead is acceptable, and
AR2/AR3 already amortize the dominant token cost through the cache.

When batching is revisited, batch **semantically by object** (AR6's unit of
work, 3–5 artifacts sharing an object/category per call) rather than
arbitrarily — conflicts are often systematic, and object grouping serves both
the conflict and the missing-metric passes. Validate with an A/B comparison
against per-artifact calls before switching.

---

## Implementation Plan

| Stage | Scope | Depends on |
|---|---|---|
| 1 | AR1 TOML truth-fix; AR2 layout change (window-first) | — |
| 2 | AR2 window mapping + AR3 chunk-grouped seed/stagger scheduling | Stage 1 |
| 3 | AR5 prompt v2 files + findings-schema `related_artifact_id`/`related_record_id` | Stage 1 |
| 4 | AR4 `get_artifact_context` tool + enable tool-use for artifact reviewers | Stage 3 |
| 5 | AR6 missing-metric pass (`metrics_completeness`) | Stage 4 (tool-use for absence verification) |
| 6 | AR7 object-anchored batching evaluation (A/B) | Stage 5 |

Stages 1–2 are the immediate cost fix; Stage 2's window inclusion is the largest
quality lift per token. Cache effectiveness is verified with the
`cache_hit_tokens` / `cache_miss_tokens` fields already logged per call
(ADR 2026061801 §DR8a rule 5).

---

## Consequences

**Positive:**

- Artifact review calls gain the extraction context they need to apply their own
  prompts' condition rules — fewer structural false negatives and false
  positives.
- DeepSeek prefix-cache hit rate for artifact reviewers goes from ~0 to
  window-grouped reuse, riding on prefixes the per-chunk reviewers already
  warmed in the same run.
- Extraction errors become detectable as a review byproduct.
- Findings become linkable (structured related-artifact references) and
  authority-weighted.
- A concrete, feasible path to missing-metric detection — the pipeline's central
  value proposition — anchored on the object-centric design.

**Negative / cost:**

- Input tokens per artifact call grow by one 200-line window (mostly cache-hit
  tokens after the first call per window).
- Tool-use for artifact reviewers adds turns and latency for the candidates that
  warrant verification (bounded by `max_tool_turns` / `max_tool_tokens`).
- A new cross-record tool widens the reviewer tool surface beyond the
  record-scoped DR10a core set; it must be scoped to read-only line access.
- Prompt v2 rollout requires re-baselining expected findings for existing test
  documents (recall stance intentionally surfaces more observations).

---

## Tests

- Scheduler: artifact units are grouped by window; exactly one seed per window
  fires before the stagger; siblings follow; `cache_hit_tokens > 0` on sibling
  calls against a live DeepSeek endpoint (integration; unit tests assert
  ordering only).
- Window mapping: artifact spans inside a window map to it; spans crossing a
  boundary map to the window containing the span start; the serialized window is
  byte-identical to `buildChunkInputs` output for the same lines.
- `get_artifact_context`: returns ±N lines around the artifact's spans for a
  foreign record; rejects unknown artifact ids; read-only.
- Prompt v2 schema: findings parse with `related_artifact_id` /
  `related_record_id`; `observation` findings carry `confidence < 0.5`.
- AR6 (when implemented): a metric present in the document but unlinked to the
  object does **not** produce `missing_metric` (absence verification via
  `search_metrics`); a metric absent from both roster and text does.

---

## Documentation Impact

- ADR 2026061801: add a change-log entry noting that DR8a's document-first
  layout is refined for artifact reviewers by this ADR (window-first with the
  canonical scheduler windows), and that artifact reviewers gain tool-use.
- ADRs 2026063002 / 2026063003 / 2026063005 (metrics, provisions, inventory
  items): note prompt v2 and the input-layout change.
- ADR 2026070101: note the review-side dependency (AR6) on `kb.artifact_objects`
  evidence fields.
- `doc-review.local.toml`: corrected `input` values with an explanatory comment
  (AR1).

---

## References

[1] ADR 2026061801 — Document Review: LLM-Powered Multi-Aspect Review Pipeline \
[2] ADR 2026062804 — Document Review: `kb.doc_review_runs` — First-Class Run Table \
[3] ADR 2026063002 — Cross-Document Metric Consistency Reviewer \
[4] ADR 2026063003 — Cross-Document Provision Consistency Reviewer \
[5] ADR 2026063005 — Cross-Document Inventory-Item Consistency Reviewer \
[6] ADR 2026070101 — Object Centric Design \
[7] DeepSeek Context Caching — https://api-docs.deepseek.com/guides/kv_cache \
[8] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md \
[9] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-spec.md \
[10] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-inventory-items-spec.md
