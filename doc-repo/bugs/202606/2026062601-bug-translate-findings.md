# Bug: doc-review finding translation can stay in English for `zh`

Date: 2026-06-26
System: `ChenWeb` document review report
Page: `/home3/doc-review-report/[report_id]`

## Summary

The document review report page supports a `Language` selector. When the user selects a non-English language such as `zh`, the system is supposed to:

1. read translated finding fields from `kb.doc_review_findings.metadata`,
2. translate missing findings with `TRANSLATION_MODEL_NAME`,
3. save the translated result back into `metadata`,
4. return the localized findings to the frontend.

We found that this flow was only partially working. Some findings were translated correctly, while other findings remained in English even though:

- the language selector showed `zh`,
- the backend translation path was running,
- the translation model environment variable was set,
- the LLM call succeeded.

## Current implementation

### Frontend

File:
- `ChenWeb/web/src/routes/home3/doc-review-report/[id]/+page.svelte`

Behavior:

1. The page loads a report by report id.
2. It reads `report.request_id`.
3. On language change it calls:
   - `GET /api/v1/doc-review/requests/:request_id?language=zh`
4. The returned `findings` list is rendered in the left panel.

Related service:
- `ChenWeb/web/src/lib/services/docReviewService.ts`

### Backend request path

Files:
- `ChenWeb/server/api/doc-reviews/handler.go`
- `ChenWeb/server/api/doc-reviews/controller.go`
- `ChenWeb/server/api/doc-reviews/finding_translation.go`

Behavior:

1. `handler.GetRequest(...)` reads query param `language`.
2. `controller.GetRequestWithFindings(...)` loads the review request and the findings for that request's `review_run_id`.
3. If language is non-English, `localizeFindings(...)` runs.
4. For each finding:
   - check `metadata[language]`,
   - if present, apply it,
   - otherwise call the LLM translator,
   - save translation to `kb.doc_review_findings.metadata`,
   - return the localized finding.

### Translation storage shape

Translations are stored in:

- table: `kb.doc_review_findings`
- column: `metadata`

Expected shape:

```json
{
  "zh": {
    "finding_type": "string",
    "title": "string",
    "description": "string",
    "suggestion": "string"
  }
}
```

### Translation model path

The doc-review translator uses:

- env var: `TRANSLATION_MODEL_NAME`
- model definitions: `MODEL_DEF_FILE`
- current model in use during debugging: `deepseek-v4-flash`
- prompt name: `doc-review-finding-translation`
- call location: `MID-CWB-DR-TRANSLATE`

The translator currently uses the shared `OpenAIJSONClient` compatibility layer and asks for a JSON object with:

- `finding_type`
- `title`
- `description`
- `suggestion`

## Problems observed

### Problem 1: language list initially only showed `en`

This was caused by app config values from `config.local.toml` being stomped by shared config loading. That issue was fixed separately by isolating app-level viper state.

Result:
- the dropdown now correctly shows both `en` and `zh`.

### Problem 2: silent English fallback hid backend failures

Earlier behavior:

- if translation setup failed, or
- if translation generation failed,

the backend quietly returned the English source finding.

This made the page look like the language selector was ignored.

Fix applied:

- non-English translation failures now surface as real errors instead of silently falling back.

### Problem 3: stale `zh` cache entries contained English text

We found rows where `metadata->'zh'` existed, but the stored values were still English.

Example:
- finding id `1493`

Earlier backend behavior:

- if `metadata["zh"]` existed, it was accepted as valid,
- no retry happened,
- English text was rendered while `zh` was selected.

Fix applied:

- cached translations that are effectively identical to the source are treated as stale,
- the backend retries translation instead of trusting the cache.

### Problem 4: the model sometimes returns English even on retry

This is the key current bug.

Using the archived LLM usage bodies under:

- `/Users/cding/Apps/llm-logs/...`

we confirmed that the model sometimes returns a valid JSON object that still leaves prose in English.

Important examples:

- finding `1493`: retry returned correct Chinese and was saved.
- finding `1496`: retry returned correct Chinese and was saved.
- finding `1498`: retry returned correct Chinese and was saved.
- finding `1500`: retry returned correct Chinese and was saved.
- finding `1503`: retry returned valid JSON, but `title`, `description`, and `suggestion` were still English.
- finding `1505`: also reported as untranslated during later debugging.

This means the failure is not:

- missing env var,
- missing model config,
- request routing,
- DB persistence for successful cases.

The failure is:

- model inconsistency on this translation task.

### Problem 5: one failing finding can block the whole localized response

`localizeFindings(...)` currently localizes the findings sequentially.

If a later finding fails translation after retries, the request returns an error instead of partial localized content. This is truthful, but it means:

- some earlier findings may already have been successfully retranslated and saved,
- yet the user still sees an overall failure for the page request.

## Debugging evidence gathered

### Verified environment

Observed env:

```text
TRANSLATION_MODEL_NAME=deepseek-v4-flash
```

So the main issue was not a missing env var.

### Verified database state

For request/report under document `387`:

- report page points to request `30`
- request `30` has review run `387_review_20260625T234321.660708`
- findings for that run exist
- some `metadata->'zh'` values were correct Chinese
- some `metadata->'zh'` values were still English

### Verified raw LLM response

For `MID-CWB-DR-TRANSLATE`, archived raw output for finding `1503` showed a successful JSON object whose prose remained English.

That established the real root cause.

## Fixes applied so far

### 1. Surface translation failures

Behavior changed from:

- silent English fallback

to:

- explicit backend error for non-English translation failures.

### 2. Add language reload logs

Frontend now logs language reload attempts and results in the browser console.

### 3. Add backend fetch/localization logs

Backend now logs:

- request id,
- language,
- finding count,
- localization failures.

### 4. Detect stale cached translations

If cached `zh` content is identical to the source English content, it is treated as stale and retranslated.

### 5. Retry when the model echoes English

If the first translation attempt returns content still identical to the English source, the backend now retries with a stricter instruction:

- prior output was invalid,
- for `zh`, natural-language prose must be in Simplified Chinese,
- do not echo the source English sentence.

### 6. Include prompt/model identity in error reporting

When localization errors are reported, logs/errors now include:

- prompt name: `doc-review-finding-translation`
- model name: current translation model, such as `deepseek-v4-flash`

This is important because the failure is model-behavior-sensitive.

## Remaining risks

1. The second attempt still uses the same model.
   - If the model is stubborn, the second attempt may still fail.

2. The current untranslated-content detector is conservative.
   - It only catches cases where translated fields are effectively unchanged from source.
   - It does not detect low-quality partial translations where only a small portion remains English.

3. Full-request failure is still all-or-nothing.
   - A single bad finding can make the whole localized request fail.

4. Existing bad cached entries remain in the database until re-requested and successfully repaired.

## Recommended next improvements

### Option A: add translation fallback model

Best next engineering step:

- keep `TRANSLATION_MODEL_NAME` as primary,
- add a second env/config value for translation fallback,
- if the primary model returns untranslated prose after retry, send the same request to a stronger translation model.

This is likely the most reliable fix.

### Option B: allow partial localized response with per-finding error markers

Alternative behavior:

- return successfully localized findings,
- mark failed findings with an error status or source-language indicator,
- show a warning banner instead of failing the entire request.

This improves UX but changes the API contract.

### Option C: add offline repair job

Background repair process could:

1. scan `kb.doc_review_findings.metadata`,
2. find cached translations identical to source English,
3. retranslate them,
4. rewrite bad cache entries.

This would clean up already-stored bad translations.

## Files involved

- `ChenWeb/server/api/doc-reviews/finding_translation.go`
- `ChenWeb/server/api/doc-reviews/finding_translation_test.go`
- `ChenWeb/server/api/doc-reviews/controller.go`
- `ChenWeb/server/api/doc-reviews/handler.go`
- `ChenWeb/web/src/routes/home3/doc-review-report/[id]/+page.svelte`
- `ChenWeb/web/src/lib/services/docReviewService.ts`

## Current conclusion

The translation feature is implemented correctly at the routing, persistence, and request-flow levels after recent fixes. The remaining production issue is model reliability:

- `deepseek-v4-flash` sometimes returns a syntactically valid translation JSON payload whose prose is still English.

The system now detects and retries that case, but a stronger fallback model is the most likely next step if this continues.
