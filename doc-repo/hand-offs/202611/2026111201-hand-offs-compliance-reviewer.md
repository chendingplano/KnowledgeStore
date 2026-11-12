# Handoff: Compliance Review reviewer, phase 1 thin slice

**Date:** 2026-11-12
**Status:** Phase 1 thin slice implemented and committed (ChenWeb jj `smvt`, `vzxv`; KnowledgeStore `svsx`). Not run against a real document, model or live search index. Phases 2-6 of the research plan are not started.
**Scope:** `ChenWeb/server/api/doc-reviews/review-compliance.go`, `review-compliance_test.go`, the `compliance` entries in `aspects.go`, `review-document.go`, `review-config.go`, `ChenWeb/doc-review.local.toml`, two prompts in `ChenWeb/prompts/`.
**Specs and docs:** design `KnowledgeStore/doc-repo/research/202611/2026111103-rsch-compliance-reviewer.md`; what shipped `devdocs/202611/2026111201-devdoc-compliance-reviewer.md`. There is no OpenSpec change: the research document says one should be written before phase 2.

## What was done

1. New independent per-chunk reviewer `compliance` (P5). Per chunk: detect activities (no knowledge-base access), search the knowledge base per activity through `searchengine.Search` (provisions and chunks, reviewed record excluded, no `MinCosine`), one informational row per activity (`compliance_grounding_candidates` or `compliance_no_grounding`). Chunk 0 also detects the document-level activity.
2. Errors abort the reviewer; no block or document fallback; a completed empty search is a normal row.
3. Config block `[reviewers.compliance]` with new key `doc_activity_prompt` (field added to `ReviewAspectConfig`). `checked = false`.
4. Prompts `prompt-review-compliance-v1.md` and `prompt-review-compliance-document-activity-v1.md`.
5. Research document status line updated; devdoc written.

**Verification:** `go vet` and `go test` for `doc-reviews` pass (fake model and search). **Not run:** a live review, the real prompts against a model, the search against `miner` or production, the UI checkbox, the report rendering of the new rows.

## Decisions taken

- Scope chosen by the user: phase 1 thin slice only.
- Candidates are labelled candidates, not "grounding", because no analysis step accepts them yet.
- The document-level prompt name is configuration, not a Go constant.

## Open items

1. **Analysis prompt.** The research design needs a step that decides whether each candidate really governs the activity (applicability, requirement comparison, gaps). It does not exist; it needs its own versioned prompt and TOML key.
2. **Run once for real.** Pick one document, run the aspect, read the rows, and check the prompts produce the expected JSON. Check how the report and UI render `ResultKind = compliance_activity` rows and the aspect's label.
3. **Model setting.** `model = "deepseek-flash-processor"` was copied from the other reviewers. ChenWeb's rule is that model choices come from environment variables / `MODEL_DEF_FILE`; confirm this value is a resolved profile reference, not a bare model name.
4. **Phase 1 decisions from the research document (section 1.1)** are still open: evaluation documents, organization context, adjudicator, annotation budget. The production knowledge-base inventory (counts by source type, how many are indexed) has not been done; without it "none found" cannot be read.
5. **Scope and manifest.** Record the knowledge-base scope and index state per run, and allow narrowing by knowledge store or document group.
6. **Locale.** Row titles and the fixed sentence are English only.
7. **OpenSpec.** Write the change (applicability, evidence states, source authorization, failure semantics) before phase 2 work.
8. No reusable module was registered; the findings of the reusable-module search are in the research document, section 10.1.

## Gotchas

- Prompt files are resolved relative to the `ChenWeb` directory; tests therefore inject the prompt loader.
- `gofmt` also re-aligned about 30 lines of `review-config.go` when `doc_activity_prompt` was added; `review-document.go` and `aspects_test.go` were unformatted before this work and were left alone.
