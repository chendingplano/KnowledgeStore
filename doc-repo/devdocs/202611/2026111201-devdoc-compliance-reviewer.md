# Compliance Review — per-chunk activity detection and knowledge-base grounding (phase 1)

**Date:** 2026-11-12 \
**Scope:** What the first, thin version of the Compliance Review aspect does today, how it is configured, and what it deliberately does not do yet. Open it before changing or extending the reviewer. The design it implements is the research document [2026111103-rsch-compliance-reviewer](../../research/202611/2026111103-rsch-compliance-reviewer.md), delivery phase 1; that document is the plan, this one records what shipped. \
**Code root:** `ChenWeb/server/api/doc-reviews/review-compliance.go`

## Summary

Compliance Review is a new, optional checkbox in the document-review screen. It reads a document in chunks and, for each chunk, lists the things the document describes that a rule could govern, for example "logs user activity in a database table". For each of those activities it searches the knowledge base for provisions and passages that might govern it, and reports what it found. If the search finds nothing, it says so. "Nothing found" only describes the knowledge base that was searched; it never means the activity is unregulated or that the document complies.

The first chunk also gets one extra step: the reviewer identifies what the document itself is (for example a product standard for a blood-pressure monitor) and searches for rules that apply to documents of that kind. Today the reviewer does not check whether a found rule really applies, does not compare its requirements with the document, and does not report missing requirements. Its rows are leads for a person to read, not verdicts.

## Details

### Where it runs

| Item | Value |
|---|---|
| Aspect name / group | `compliance` / `P5` (label "Compliance Review", priority "Review for Regulated", `aspects.go`) |
| Input | `per-chunk` only. `ReviewDocument` returns an error; there is no block or document fallback |
| Dispatch | The prompt-cache scheduler calls `processChunk` through the `chunkReviewer` interface (`review_cache_scheduler.go`) |
| Registration | `buildReviewers` in `review-document.go`, only when the model client, model name and prompt text resolve |
| Independence | It calls no other reviewer. It uses the shared scheduler, LLM client and `searchengine` |

### Per-chunk procedure (`processChunk`)

1. **Detect activities.** One JSON call with the configured prompt over the chunk lines. The reviewer never reads the knowledge base in this step, so the activity list does not depend on what the knowledge base holds. Expected output (minified): `{"activities":[{activity, line_start, line_end, object, search_queries[]}]}`; `actor`, `action`, `purpose` appear only when the text states them. The model does not repeat the quote: `source_text` is taken from the chunk lines `line_start..line_end` (capped at 400 characters), though a model-supplied `source_text` is still accepted. A missing or non-array `activities`, a non-object entry, or an entry without `activity` or any derivable `source_text` is an error. `search_queries` is capped at 3; if absent, `source_text` is the query.
2. **Document-level activity (chunk index 0 only).** A second JSON call with the prompt named by `doc_activity_prompt`, same output shape (at most one activity, `object` is the document's subject). Its rows come first. If `doc_activity_prompt` is empty, chunk 0 fails with an error naming the key.
3. **Search.** For every query of every activity, `searchengine.Search` with `ArtifactTypes = ["provision","chunk"]`, `ExcludeRecordIDs` = the reviewed record plus every record with the same `kb.inputs.md5` (a re-uploaded copy; looked up once per reviewed record), limit 10, and `MinCosine` from `min_cosine` (unset = no floor). Results are de-duplicated per activity by artifact type and id.
4. **Report.** One row per activity (see below).

### Token economy

The compliance calls are the most expensive review calls, so both directions are trimmed (call `llm-e4d68706` on record 416: 8,990 input and 25,716 output tokens, of which 19,029 were reasoning).

- **Reasoning off.** `thinking_type = "disabled"` in `[reviewers.compliance]` overrides the model profile for this reviewer only (`ReviewAspectConfig.ThinkingType`, `docprocessing.BuildReviewerLLMClientWithThinking`). Without it DeepSeek thinks by default.
- **Compact input (shared by all document reviewers).** `docprocessing.RawLinesToCompactJSON` (aliased as `rawLinesToJSON` in `doc-reviews`) encodes the lines as a table: a first row naming the columns (`flag, line_number, page_number, line_type, content`) and one bare value array per line. No field is dropped, so the other reviewers' prompts, which refer to those fields by name, still hold; only the per-line keys go (for call `llm-e4d68706` the document part went from 21.6 KB to about 11 KB of JSON). Topic extraction and other processors keep `rawLinesToJSON`. Because every reviewer sends the same text, the document-first prefix is shared again. Artifact-window reviewers use their own `blockLinesToJSON` and are unchanged.
- **Compact output.** Prompts `-v2`: minified JSON, no quote, empty fields omitted, flat bilingual keyword lists, at most 2 searches per activity, neighbouring lines merged into one activity.

### Result rows

All rows are `ReviewFinding` with `Pass="P5"`, `Aspect="compliance"`, `Severity="info"`, `ResultKind="compliance_activity"`, `Evidence` = the quoted source text, `Location` = `line_start-line_end`, `Confidence=0` (not calibrated, not used).

| `FindingType` | Meaning | Content |
|---|---|---|
| `compliance_grounding_candidates` | The search returned at least one artifact | Description lists each as `[type id] (cosine X) record N title: snippet` (cosine only when the search had a query vector); `RelatedArtifactID`/`RelatedRecordID` hold the top hit |
| `compliance_no_grounding` | The search completed and returned nothing (with a floor: nothing at or above it) | Fixed sentence stating this does not mean the activity is unregulated |

Titles are "Grounding candidates found: <activity>" and "Activity with no grounding candidates found: <activity>"; the document-level activity is labelled `document: <object>`. These titles and the fixed sentence are English only and are not yet passed through the finding translator or any locale path.

### Errors

Any failure (model call, malformed output, prompt load, search) is logged and returned from `processChunk`; the scheduler aborts the compliance reviewer and marks it failed. A completed search with no results is a normal row, not an error. An activity whose search did not run never produces a "no grounding" row.

### Configuration

`ChenWeb/doc-review.local.toml`:

```toml
[reviewers.compliance]
enabled = true
checked = false                 # not preselected in the UI
group = "P5"
input = "per-chunk"
model = "deepseek-flash-processor"   # same profile name the other reviewers use
prompt = "prompt-review-compliance-v2.md"
doc_activity_prompt = "prompt-review-compliance-document-activity-v2.md"
thinking_type = "disabled"
# min_cosine = 0.55            # optional relevance floor, 0..1 (rejected outside); unset = no floor
```

`doc_activity_prompt` is a field of `ReviewAspectConfig` (`review-config.go`). Both prompts (v2; v1 is superseded) are in `ChenWeb/prompts/`; text is never in Go. Prompt files are read relative to the `ChenWeb` working directory (`loadPromptByRef`). The checkbox appears in the UI only when the aspect is listed in a tier, because the screen builds each level's list from the tier lists. `compliance` is listed under `review-regulated` in `config.local.toml` (gitignored, so repeat it on every deployment; the config is read at start, restart the API after changing it). Without that entry the aspect exists in `/aspects` but no level shows it.

### Tests

`review-compliance_test.go`, with a fake model and a fake search function: no-grounding row and the exact search request, candidates de-duplicated across queries, search error and model error abort the chunk with the original error, malformed output rejected, no search when there are no activities, chunk 0 adds the document-level call, chunk 0 fails without the configured prompt, `ReviewDocument` errors. Nothing here runs against a real model or the real search index.

## Evaluation tooling (phase 2)

Built under openspec `compliance-reviewer-phase2`; it measures the reviewer, it does not change what the reviewer reports. Code: `ChenWeb/server/api/compliance-eval/` and the commands `compliance-snapshot`, `compliance-gold`, `compliance-score`.

- **Snapshot** (`testbed.compliance_eval_snapshots`, `..._records`): records which records a gold run may rely on, with each one's md5, chunk-index generation and chunk/provision artifact counts, plus the embedding model. It does not copy the corpus (that stays in `kb.search_artifacts_*`). `compliance-gold` refuses to start when any member drifted, and names it.
- **Gold labelling** (`compliance-gold`): documents come from `[compliance-review.covered-docs]` and `[compliance-review.uncovered-docs]` in `doc-review.local.toml` (record id = one-line reason), organization facts from `[compliance-review.organization]` (stored with the run; the reviewer does not read them yet). Two annotators and an adjudicator are model profiles named by `COMPLIANCE_REVIEWER_ANNOTATOR_1`, `COMPLIANCE_REVIEWER_ANNOTATOR_2`, `COMPLIANCE_ADJUDICATOR` (an unset variable or two equal annotators stops the run). Both annotators label activities per chunk; activities both found (span overlap) are kept, one-annotator activities go to the adjudicator. For each activity a pool of candidates is searched in the snapshot only (limit per query `-pool-limit`, default 50, no floor, the document and its md5 copies excluded); both annotators judge every candidate `governs` / `topical` / `unrelated`, the adjudicator settles disagreements and may mark `ambiguous`. An annotator that skips candidates is asked again for those only, three times, then the run fails. Rules and prompts are `prompts/prompt-compliance-gold-*-v1.md`; the rules file's SHA-256 is stored with the run. Nothing is saved unless the whole run succeeds.
- **Scoring** (`compliance-score -gold KEY -runs ID,...`): activity precision and recall by coverage (a reviewer row supports a gold activity when it overlaps at least half of the shorter span; one coarse row can cover many fine gold activities), grounding recall within the pool, precision of "no grounding", the share of those where gold had a governing record, and false grounding (candidates reported where gold has none). `-compare A,B` checks that two runs of one document have identical activity lists. Every score is LLM-adjudicated, and recall is bounded by the pool (a governing record that pooling missed is never judged).
- **What the first live run showed** (record 416, a deliberately poor 6-record snapshot, cheap model profiles): the annotators found 62 activities against the reviewer's 11 (reviewer precision 11/11, recall 56/62); all 996 pooled candidates were judged unrelated, which matched the snapshot (fitness-equipment standards for a waste-sorting document), and cosine reached 0.66 on passages both annotators judged unrelated. That is one run on an unrepresentative corpus, not a measurement of accuracy.
- **Not built:** restricting the reviewer's own search to a snapshot or document group (needed for the scope-stability check), the baseline run, choosing `min_cosine`, and a human review of a sample of labels.

## Known limitations

- Without `min_cosine` nothing is a "no grounding" case in practice: top-10 search always returns ten results (trial 2026-11-12, 151 of 151 activities got candidates, including near-miss topical neighbours). The floor value is not chosen yet; it needs the gold set (openspec `compliance-reviewer-phase2`). Only byte-identical copies are excluded; another edition or re-typeset file still appears.
- Candidates are raw search results. Nothing yet decides whether a rule applies (territory, role, edition, effective date), compares requirements with the document, or reports requirements the document omits. Research phases 3 and 4 add these.
- No run manifest or coverage report: the knowledge-base scope searched and how much of it is indexed are not recorded in the output. The search is not narrowed to a knowledge store or document group.
- Only indexed records can be found. Chunk rows need the chunk backfill; provision rows need `extract_provisions`. An unindexed record is invisible to the reviewer without any warning.
- Editions are not selected: a superseded standard can appear as a candidate next to its replacement.
- The document-level activity comes only from chunk 0, so a document whose subject is not stated in its opening chunk may get none.
- Rows are English-only, and the model's own output (activity names, queries) follows the document language as the prompts ask.
- Accuracy is unmeasured: there is no gold set, so retrieval recall and activity-detection quality are unknown.
- The prompts and the live model output shape have not been exercised outside unit tests.
