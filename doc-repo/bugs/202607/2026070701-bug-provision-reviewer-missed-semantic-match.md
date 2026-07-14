# Bug: provision reviewer can miss semantically close cross-document matches

Date: 2026-07-07\
Status: fixed-verified\
System: `ChenWeb` provision review / cross-document artifact matching\
Component: `server/api/doc-reviews` and `server/api/doc-processing`

## Summary

The provision reviewer for `244_prv_17` did not surface the semantically close
provision `415_prv_15` even though the two provisions describe nearly the same
requirement:

- `244_prv_17`
  - `prov_name`: `报告核签要求`
  - `prov_desc`: `规定动态血压报告需由执业医师核签`
- `415_prv_15`
  - `prov_name`: `报告核签要求`
  - `prov_desc`: `要求动态血压报告必须由主治医师及以上职称的医师审核签字。`

This caused the reviewer to miss a likely cross-document comparison candidate.

## Symptom

During provision review, `244_prv_17` was expected to retrieve
`415_prv_15` through the live semantic match path
`FindSimilarArtifactsOnTheFly(...)`, but the candidate was absent from the
review payload.

## Root Cause

The reviewer itself was functioning as designed. The issue was in provision
search indexing.

When registry rows were built for `kb.search_artifacts`, the provision path
constructed a weighted search string from a reduced field set:

- `prov_name`
- `provision_type`
- `prov_desc`
- `keywords`
- `category_paths`

If that weighted text was non-empty, the richer stored provision
`search_document` was effectively discarded.

That richer stored text can contain additional wording and paraphrases that are
important for semantic retrieval. In this case, losing text such as
`审核签字` made the live search less likely to connect it to another provision
phrased as `核签`.

## Fix

Updated provision registry row construction so the final indexed
`SearchDocument` preserves both:

1. the weighted provision search text, and
2. the stored provision `search_document`

instead of replacing the stored text whenever the weighted text is present.

Code change:

- `ChenWeb/server/api/doc-processing/search_indexing.go`

Regression test added:

- `ChenWeb/server/api/doc-processing/search_indexing_test.go`

New test coverage verifies that provision registry rows retain stored wording
such as `审核签字`.

## Verification

Targeted verification passed:

- `go test ./server/api/doc-processing -run 'TestBuildProvisionRegistryRows(AppliesConfiguredWeightsToSearchDocument|PreservesStoredSearchDocument)$'`
- `go test ./server/api/doc-reviews -run 'TestAssembleProvisionMatches|TestReviewProvision'`
- `go test ./server/api/doc-reviews`

Additional note:

- `go test ./server/api/doc-processing` still has unrelated pre-existing
  failures in summary-id tests such as `TestBuildSummaryID`,
  `TestBuildSummaryTree`, and `TestValidateSummaryArtifacts...`.

## Change Record

Implementation change committed in `ChenWeb` with:

- `bd304413731f` `Preserve stored provision search text for reviewer matching`

## Documentation Impact

What knowledge changed:
- The provision reviewer miss was caused by provision search indexing, not by
  reviewer-side deduping or prompt behavior.

Which docs/specs/tests are affected:
- Bug record updated here.
- Provision registry search-document behavior is now covered by regression
  tests in `search_indexing_test.go`.

Which docs were updated:
- This bug record.

Which docs may still be stale:
- Any internal notes that describe provision semantic matching as using only
  weighted `prov_name`/`prov_desc` text would now be incomplete.

What was intentionally left undocumented:
- No broader ADR was added because this was a surgical bug fix, not an
  architectural change.
