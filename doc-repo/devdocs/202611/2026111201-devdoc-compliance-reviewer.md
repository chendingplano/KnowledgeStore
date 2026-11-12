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

1. **Detect activities.** One JSON call with the configured prompt over the chunk lines. The reviewer never reads the knowledge base in this step, so the activity list does not depend on what the knowledge base holds. Expected output: `{"activities":[{activity, source_text, line_start, line_end, actor, action, object, purpose, search_queries[]}]}`. A missing or non-array `activities`, a non-object entry, or an entry without `activity` or `source_text` is an error. `search_queries` is capped at 3; if absent, `source_text` is the query.
2. **Document-level activity (chunk index 0 only).** A second JSON call with the prompt named by `doc_activity_prompt`, same output shape (at most one activity, `object` is the document's subject). Its rows come first. If `doc_activity_prompt` is empty, chunk 0 fails with an error naming the key.
3. **Search.** For every query of every activity, `searchengine.Search` with `ArtifactTypes = ["provision","chunk"]`, `ExcludeRecordIDs = [reviewed record]`, limit 10, and no `MinCosine`. Results are de-duplicated per activity by artifact type and id.
4. **Report.** One row per activity (see below).

### Result rows

All rows are `ReviewFinding` with `Pass="P5"`, `Aspect="compliance"`, `Severity="info"`, `ResultKind="compliance_activity"`, `Evidence` = the quoted source text, `Location` = `line_start-line_end`, `Confidence=0` (not calibrated, not used).

| `FindingType` | Meaning | Content |
|---|---|---|
| `compliance_grounding_candidates` | The search returned at least one artifact | Description lists each as `[type id] record N title: snippet`; `RelatedArtifactID`/`RelatedRecordID` hold the top hit |
| `compliance_no_grounding` | The search completed and returned nothing | Fixed sentence stating this does not mean the activity is unregulated |

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
prompt = "prompt-review-compliance-v1.md"
doc_activity_prompt = "prompt-review-compliance-document-activity-v1.md"
```

`doc_activity_prompt` is a field of `ReviewAspectConfig` (`review-config.go`). Both prompts are in `ChenWeb/prompts/`; text is never in Go. Prompt files are read relative to the `ChenWeb` working directory (`loadPromptByRef`). The aspect is not in any tier list.

### Tests

`review-compliance_test.go`, with a fake model and a fake search function: no-grounding row and the exact search request, candidates de-duplicated across queries, search error and model error abort the chunk with the original error, malformed output rejected, no search when there are no activities, chunk 0 adds the document-level call, chunk 0 fails without the configured prompt, `ReviewDocument` errors. Nothing here runs against a real model or the real search index.

## Known limitations

- Candidates are raw search results. Nothing yet decides whether a rule applies (territory, role, edition, effective date), compares requirements with the document, or reports requirements the document omits. Research phases 3 and 4 add these.
- No run manifest or coverage report: the knowledge-base scope searched and how much of it is indexed are not recorded in the output. The search is not narrowed to a knowledge store or document group.
- Only indexed records can be found. Chunk rows need the chunk backfill; provision rows need `extract_provisions`. An unindexed record is invisible to the reviewer without any warning.
- Editions are not selected: a superseded standard can appear as a candidate next to its replacement.
- The document-level activity comes only from chunk 0, so a document whose subject is not stated in its opening chunk may get none.
- Rows are English-only, and the model's own output (activity names, queries) follows the document language as the prompts ask.
- Accuracy is unmeasured: there is no gold set, so retrieval recall and activity-detection quality are unknown.
- The prompts and the live model output shape have not been exercised outside unit tests.
