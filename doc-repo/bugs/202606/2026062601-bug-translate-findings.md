# Bug: doc-review finding translation can stay in English for `zh`

Date: 2026-06-26
System: `ChenWeb` document review report
Page: `/home3/doc-review-report/[report_id]`

## Requirements
Translation: when the user selects a non-English language, it retrieves the 
translated version from `kb.doc_review_findings`. If a finding has not been 
translated yet, it uses TRANSLATION_MODEL_NAME model to translate it and save 
the translation to `kb.doc_review_findings.metadata`:
```json
{
    "<language_code>":
    {
        "finding_type": "string",
        "title": "string",
        "description": "string",
        "suggestion": "string"
     }
}
```

Translation MUST be implemented as lazy-translation at per reviewer per review 
request level.

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

**Initial fix (later found to be incomplete):**

- cached translations that are effectively **byte-identical** to the source English
  are treated as stale,
- the backend retries translation instead of trusting the cache.

**Remaining gap (discovered later):**

The byte-identical check only catches cases where the LLM echoed the input
exactly. If the LLM returned slightly different English text (rephrasing,
different spacing, etc.), the cached entry was treated as a valid
translation — even though it was still English. Finding `1624` exhibited
this: its cached `zh` entry contained English text that differed from the
source, so the retry logic never fired.

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

`localizeFindings(...)` originally localized the findings sequentially.

If a later finding fails translation after retries, the request returns an error instead of partial localized content. This is truthful, but it means:

- some earlier findings may already have been successfully retranslated and saved,
- yet the user still sees an overall failure for the page request.

### Problem 6: LLM prompt ambiguity causes Chinese→English translation

When a finding's content is already in Chinese and the user selects `zh`, the system
should recognize that no translation is needed. Instead, the prior code sent every
finding to the LLM regardless of source language.

The log for finding `1707` shows the problem clearly:

```
content={"description":"第0440类冷热源定义为...（中文）...",
         "finding_type":"undocumented_assumption",
         "language":"zh",
         "suggestion":"补充...（中文）...",
         "title":"未声明...（中文）..."}
response=map[description:(English), finding_type:(English), suggestion:(English), title:(English)]
```

**The finding was already in Chinese.** The input `language:"zh"` told the model
the **target** language, but the prompt used the ambiguous phrase
"the requested language" — the model interpreted it inconsistently and produced
English output.

Root causes:

- **No source-language detection:** the Go code did not check whether a
  finding's content was already in the target language before sending it to
  the LLM. A Chinese finding with `language: "zh"` was sent for translation
  when it shouldn't have been.
- **Ambiguous prompt phrasing:** the prompt said "Translate ... into the
  requested language" without making clear that the `language` field in the
  input JSON **is** the target language. The model could treat it as the
  source language instead, resulting in Chinese→English translation.

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

### 4. Detect stale cached translations (byte-identity check)

If cached `zh` content is byte-identical to the source English content, it is treated as stale and retranslated.

**Limitation (addressed later in fix 10):** non-identical English output
from the model (rephrased but still English) was not caught by this check.

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

### 7. Parallelize `localizeFindings` with goroutines

The original `localizeFindings` loop translated findings one at a time — each
LLM call blocked the next one from starting. With many findings this added
up to minutes of wall-clock time.

Changed to concurrent goroutines with:
- a buffered channel collecting indexed results (order-preserving),
- `context.WithCancel` to cancel in-flight translations on first error,
- `sync.WaitGroup` to wait for all goroutines to finish.

This reduces total latency from the sum of all translation times to the
time of the slowest single translation.

### 8. Detect findings already in target language and skip LLM call

**File:** `finding_translation.go`

Added two helpers:

- **`containsChineseChars(s)`** — detects CJK Unified Ideographs (Han
  characters) in a string.
- **`findingInTargetLanguage(f, language)`** — checks whether all
  natural-language prose fields (title, description, suggestion) of a
  finding are already written in the target language. Currently supports
  `zh` via Chinese character detection; returns `false` for other languages.

The `localizeFinding` function now checks `findingInTargetLanguage` **before**
calling the LLM. If the finding is already in the target language:

1. The source content is saved as the cached translation in
   `kb.doc_review_findings.metadata` (self-translation).
2. The finding is returned unchanged — no LLM call at all.

The `likelyUntranslatedForLanguage` cache-validity check was also updated:
when the source is already in the target language, byte-identical cached
content is treated as valid (not "untranslated"), so the self-translation
cache hit works correctly on subsequent requests.

### 9. Disambiguate translation prompt

The LLM prompt in `translateFindingAttempt` was rewritten to make the
direction of translation unambiguous:

- **Before:** `"Translate ... into the requested language. ... If language is zh, use Simplified Chinese."`
- **After:** `"Translate ... INTO the target language specified by the \"language\" field in the JSON input below. The \"language\" field IS the target language for translation — do NOT treat it as the source language. ... If the target language is zh, use Simplified Chinese. If any field's content is already in the target language, output it unchanged — do not translate it away from the target language."`

Key improvements:
- States explicitly that the `language` field **is** the target (not source).
- Adds instruction to keep already-in-target-language fields unchanged.
- Uses `INTO` capitalization and em-dash for emphasis.

### 10. Detect stale English cache even when text differs from source

**File:** `finding_translation.go`

The earlier fix for Problem 3 (byte-identical detection) had a gap:
stale English cache entries that differed from the source text were still
treated as valid translations. This affected findings (like `1624`) where
the LLM returned English text with slightly different wording or phrasing
rather than an exact echo.

Added `translationInTargetLanguage(tr, language)`: checks whether the
**cached/returned** translation content itself contains characters from
the target language (e.g., Chinese characters for `zh`).

Updated `likelyUntranslatedForLanguage` to use this check in the
"content differs from source" branch:

```
Before: content differs from source → valid translation (always)
After:  content differs from source AND has no target language chars → stale → retry
        content differs from source AND has target language chars → valid translation
```

This protects both cache-hit paths (stale English database entries) and
post-LLM paths (model returns English instead of target language).

### 11. Detect untranslated content more robustly and log richer context

**File:** `finding_translation.go`

Two improvements:

**a) Exclude `finding_type` from equivalence check:**

`equivalentLocalizedContent` previously compared all four fields (`finding_type`, `title`, `description`, `suggestion`) to determine if a cached/generated translation differed from the source. `finding_type` is user-visible metadata (often English `snake_case`) and is excluded from the target-language character checks in both `findingInTargetLanguage` and `translationInTargetLanguage`. This inconsistency meant `finding_type` being untranslated could influence the equivalence check.

**Change:** `equivalentLocalizedContent` now only compares the three prose fields (`title`, `description`, `suggestion`), consistent with the other two functions. If only `finding_type` stays in English but title/description/suggestion are correctly in the target language, the translation is treated as valid.

**b) Add original requested fields and values to WARN logs:**

Both WARN log sites (cached translation warning and LLM retry warning) now include:
- Source fields: `src_finding_type`, `src_title`, `src_description`, `src_suggestion`
- Cached/LLM output values: `cached_finding_type` / `cached_title` / `cached_description` / `cached_suggestion` (cache path) or `llm_finding_type` / `llm_title` / `llm_description` / `llm_suggestion` (LLM path)

This allows operators to compare what was requested vs what was cached/returned directly in the log output without needing to cross-reference the raw LLM archive.

**Example log output (previous):**
```
finding_id="1707" language="zh" title="未声明..."
```

**Example log output (now):**
```
finding_id="1707" language="zh"
src_finding_type="undocumented_assumption" src_title="未声明..." src_description="第0440类..." src_suggestion="补充..."
cached_finding_type="" cached_title="未声明..." cached_description="第0440类..." cached_suggestion="补充..."
```

### 12. Add per-finding decision logging for the entire localizeFinding flow

**File:** `finding_translation.go`

The `localizeFinding` function had three silent return paths where a finding
exited without any log entry:

1. **Cache valid** — the cached translation was accepted and applied, but
   there was no log to confirm this happened.
2. **Source already in target language** — the finding's prose fields already
   contained target-language characters, so the LLM was skipped. The only log
   was a WARN if the self-translation *save* failed.
3. **No valid cache** — when the cache was missing or stale, the code fell
   through to the LLM path without logging the transition.

**Change:** INFO-level logs have been added at each decision point:

| Log | When | Includes |
|-----|------|----------|
| `localizeFinding: using cached translation` | Cache is valid, applying it | `finding_id`, `language`, all four cached field values |
| `localizeFinding: no valid cached translation, proceeding` | Cache missing or stale, continuing | `finding_id`, `language` |
| `localizeFinding: source already in target language, skipping LLM` | Source prose already in target language | `finding_id`, `language`, all four source field values |
| `localizeFinding: proceeding to LLM translation` | About to call the LLM translator | `finding_id`, `language` |

This means every finding now produces a clear audit trail showing which
path was taken and why — making it possible to diagnose cases like
finding `1624` (cache hit with stale English content) without
reconstructing the flow from scattered WARN logs.

**Example: cache-hit path for a valid cached translation:**
```
localizeFinding: using cached translation
finding_id="7" language="zh"
cached_finding_type="" cached_title="缓存标题" cached_description="缓存描述" cached_suggestion=""
```

**Example: skip-LLM path for source already in target language:**
```
localizeFinding: source already in target language, skipping LLM
finding_id="1" language="zh"
src_finding_type="technical_error" src_title="中文标题" src_description="中文描述" src_suggestion="中文建议"
```

**Example: stale cache detection for finding 1624:**
```
WARN: cached finding translation appears untranslated; retrying
src_finding_type="undocumented_assumption" src_title="Assumes boundaries are self-evident" ...
cached_finding_type="undocumented_assumption" cached_title="Assumes boundaries not self-evident" ...
→ localizeFinding: no valid cached translation, proceeding
→ localizeFinding: proceeding to LLM translation
```

### 13. Tighten `translationInTargetLanguage` from OR to AND (skip-empty)

**File:** `finding_translation.go`

**Problem:** `translationInTargetLanguage` used OR logic (`||`) across the three
prose fields — if ANY ONE field contained target-language characters, the
entire cached translation was considered valid. This meant a cache entry
with a Chinese title but English description and suggestion (like finding
`1624`'s cached `zh` entry) was accepted as a valid translation.

For finding `1624`, the cached entry had:

| Field | Cached value | In Chinese? |
|-------|-------------|:-----------:|
| `finding_type` | `"未陈述的知识假设"` | ✅ |
| `title` | `"假设'预期应用'..."` | ✅ |
| `description` | `"The classification system relies on..."` | ❌ |
| `suggestion` | `"Add a clarification..."` | ❌ |

The Chinese title alone made `translationInTargetLanguage` return `true`,
and `likelyUntranslatedForLanguage` returned `false` — so the stale cache
was used without retrying translation.

**Change:** `translationInTargetLanguage` now uses AND-with-skip-empty
logic: every non-empty prose field must contain target-language characters.
Empty fields are skipped (a field that wasn't returned by the LLM doesn't
disqualify the translation). At least one non-empty field is required.

**Result:** For finding `1624`'s cached entry, the English description now
causes `translationInTargetLanguage` to return `false`, and the entry is
correctly flagged as stale and retranslated.

### 14. Demote stale-cache "retrying" log from WARN to INFO

**File:** `finding_translation.go`

**Problem:** The `logger.Warn("cached finding translation appears
untranslated; retrying", ...)` at what was line 274 fired whenever a cached
translation was detected as stale — *before* any LLM retry attempt. Since
the retranslation usually succeeds on the first try, operators saw a WARN
level message for what is actually routine cache maintenance.

For finding `1624`, the observable sequence was:

```
WARN: cached finding translation appears untranslated; retrying   ← looks alarming
INFO: localizeFinding: no valid cached translation, proceeding
INFO: localizeFinding: proceeding to LLM translation
INFO: finding translation start ...
INFO: finding translation end   ... (Chinese output, success)
```

The WARN was premature — the system hadn't even tried to translate yet,
and when it did, it succeeded.

**Change:** `logger.Warn` → `logger.Info` for this message. The stale-cache
detection is working correctly; it does not warrant operator attention. The
genuine failure case (when the LLM itself returns untranslated content after
retry) continues to use `logger.Warn`.

### 15. Use context.WithoutCancel for DB save in localizeFinding

**File:** `finding_translation.go`

**Problem:** `localizeFindings` (line 385) creates a cancellable context
(`context.WithCancel`) so that the first goroutine error cancels all
in-flight translations. However, the same cancelled context was used for
`saveFindingTranslation` — the DB persist call.

If goroutine A errored (e.g., its LLM call failed), it called `cancel()`.
Goroutine B may have completed its LLM call successfully but was about to
save to the database. With the cancelled context, `db.ExecContext`
returns `context.Canceled`, the save fails, and the new translation is
**not persisted**. But the error is swallowed at the save call site:

```go
if err := saveFindingTranslation(ctx, c.DB, f.ID, language, tr); err != nil {
    logger.Warn("finding translation save failed", ...)  // logged but error not returned
}
return applyFindingTranslation(f, tr), nil  // goroutine sees nil error, reports success
```

The goroutine reports success (nil error), the UI gets the Chinese text,
but the DB was never updated. On the next page load, the stale cache is
detected again, and the cycle repeats.

**Change:** Both `saveFindingTranslation` calls in `localizeFinding` now
use `context.WithoutCancel(ctx)` instead of `ctx`:

```go
saveFindingTranslation(context.WithoutCancel(ctx), c.DB, f.ID, language, tr)
```

This creates a derived context that shares the parent's values (tracing,
deadlines) but is NOT cancelled when the parent context is cancelled.
The save always proceeds regardless of other goroutine failures.

Additionally, an INFO log `"finding translation saved"` is emitted on
successful save, providing a positive confirmation trace for operators.

### 16. Move hardcoded prompts to files in ChenWeb/prompts/ with distinct names

**Files:**
- `finding_translation.go` — code changes
- `prompts/prompt-doc-review-finding-translation-v1.md` — base prompt (new)
- `prompts/prompt-doc-review-finding-translation-retry-v1.md` — retry prompt (new)

**Problem (two issues):**

1. **Same prompt name in logs for both attempts.** The log showed
   `prompt_name="doc-review-finding-translation"` for both the first attempt
   and the retry. The only differentiator was `is_retry=true/false`, which
   was easy to miss in noisy logs.

2. **Prompts hardcoded in Go source.** The base translation prompt (~5 lines)
   and the retry instruction were string literals inside
   `translateFindingAttempt`. Editing or reviewing them required modifying Go
   code, and there was no history/versioning of prompt iterations.

**Change:**

- Created two prompt files in `prompts/`:
  - `prompt-doc-review-finding-translation-v1.md` — the base instruction
  - `prompt-doc-review-finding-translation-retry-v1.md` — the base instruction
    with the retry admonition appended ("Your previous output was invalid...")

- Both prompts are loaded at startup in `newLLMFindingTranslator` via
  `os.ReadFile` from the `prompts/` directory (same pattern as other prompts
  in this project).

- A second prompt name constant `findingTranslationRetryPromptName =
  "doc-review-finding-translation-retry"` was added. The retry call now
  passes this name, so the log clearly distinguishes:

  ```
  prompt_name="doc-review-finding-translation"        is_retry=false
  prompt_name="doc-review-finding-translation-retry"  is_retry=true
  ```

- The `translationDebugFields` helper now accepts a `promptName` parameter
  so call sites can pass the correct name for the context.

## Remaining risks

1. The second attempt still uses the same model.
   - If the model is stubborn, the second attempt may still fail.

2. The untranslated-content detector now has two layers:
   - **Layer 1 (byte-identity):** catches cases where translated fields are
     effectively unchanged from source (exact LLM echo).
   - **Layer 2 (target-language check):** catches cases where the output
     differs from source but still lacks target-language characters (stale
     English from a model failure). Now uses AND (skip-empty) — every
     non-empty prose field must have target-language characters, so
     partial translations (Chinese title, English description/suggestion)
     are detected.
   - It still does not detect mixed-language content within a single
     field (e.g. description containing both Chinese and English).

3. Partial-response failure still returns an error.
   - A single bad finding can still make the whole localized request fail.
   - The parallelization makes this less wasteful (all translations start
     concurrently, so a failure doesn't block sequential work), but the
     response is still all-or-nothing.

4. Existing bad cached entries remain in the database until re-requested and successfully repaired.

5. Source-language detection is currently `zh`-only.
   - `findingInTargetLanguage` only checks for Chinese characters (Han).
   - Adding support for other languages (e.g. Japanese, Korean) would
     require extending the detection logic.

6. The prompt fix relies on model instruction-following.
   - While the prompt now unambiguously states the direction of translation,
     a model that ignores instructions could still produce English output
     when the target is `zh`. The Go-level skip (`findingInTargetLanguage`)
     is the primary defense for Chinese findings.

## Recommended next improvements

### Option A: add translation fallback model

Moderate remaining value (the prompt ambiguity and source-language detection
fixes already address the most common failure modes):

- keep `TRANSLATION_MODEL_NAME` as primary,
- add a second env/config value for translation fallback,
- if the primary model returns untranslated prose after retry, send the same request to a stronger translation model.

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

### Option D: extend source-language detection to other languages

`findingInTargetLanguage` currently only supports `zh` via Han character
detection. For other target languages (e.g. `ja`, `ko`), add script-range
detection (Hiragana/Katakana for Japanese, Hangul for Korean) so the LLM
skip works for findings already in those languages.

## Files involved

- `ChenWeb/server/api/doc-reviews/finding_translation.go` — main translation logic
- `ChenWeb/server/api/doc-reviews/finding_translation_test.go` — tests
- `ChenWeb/server/api/doc-reviews/controller.go` — caller of localizeFindings
- `ChenWeb/server/api/doc-reviews/handler.go` — HTTP handler
- `ChenWeb/web/src/routes/home3/doc-review-report/[id]/+page.svelte` — frontend page
- `ChenWeb/web/src/lib/services/docReviewService.ts` — frontend API service

## Current conclusion

The translation feature is implemented correctly at the routing, persistence, and request-flow levels after recent fixes. Key remaining issues addressed in this session:

1. **Sequential → parallel translation:** `localizeFindings` now translates
   all findings concurrently, significantly reducing wall-clock latency.

2. **Skip LLM for already-Chinese findings:** `findingInTargetLanguage`
   detects when a finding's prose is already in `zh` and skips the LLM call
   entirely, preventing Chinese→English translation.

3. **Prompt ambiguity fixed:** The LLM prompt now explicitly states that the
   `language` field IS the target language, not the source. Combined with
   the instruction to keep already-translated fields unchanged.

4. **Stale English cache detection strengthened:** `translationInTargetLanguage`
   detects when cached/generated output lacks target-language characters
   even if the text differs from the source. This catches the class of
   stale entries (like finding `1624`) that the byte-identity check missed.

The remaining production risk is model reliability:
- `deepseek-v4-flash` sometimes returns a syntactically valid translation
  JSON payload whose prose is still English.
- The system now detects and retries that case, and a stronger fallback
  model is the most likely next step if this continues.
