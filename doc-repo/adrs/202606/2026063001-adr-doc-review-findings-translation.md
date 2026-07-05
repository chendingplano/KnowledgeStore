# ADR 2026063001 — Document Review Finding Translation: Schema and Behavior

**Date:** 2026-06-30 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-reviews/finding_translation.go` \
**Authors:** Chen Ding \
**Tags:** doc review, i18n, translation, metadata schema

---

## Change Logs

* 2026/06/30, ADR Created. Documents the finding translation design and resolves the `i18n`
  wrapper question raised during bug investigation `2026062601-bug-translate-findings`.
* 2026/07/05, Clarified that reviewer output may declare its source `language`. When present,
  that value is used to store the original finding prose under `metadata.<language>`; when
  absent, it defaults to `en`.
* 2026/07/05, Clarified that `DOC_REVIEW_REPORT_LANGUAGE` accepts either a single JSON string
  such as `"en"` or a JSON array such as `["en", "zh"]`; the same parsed language list drives
  report variants and auto pre-translation targets.
* 2026/07/05, Clarified that `DOC_REVIEW_TRANSLATION = "on-demand"` performs no save-time
  LLM normalization or localization; reviewer-authored prose is stored as-is with its declared
  source language.

---

## Context

Document review findings produced by the reviewer pipeline (see
`2026061801-adr-document-review.md`) are stored in `kb.doc_review_findings`.
Each finding has a `metadata` JSONB column that is used to cache per-language
translations of the finding's prose fields (`title`, `description`, `suggestion`).

When the report page is loaded with a non-English language (e.g. `zh`), the backend:

1. Reads existing cached translations from `metadata`.
2. For findings not yet translated, calls the LLM translator
   (model from `TRANSLATION_MODEL_NAME`) with the source finding content.
3. Saves the translation back into `metadata`.
4. Returns the localized findings to the frontend.

During the bug investigation (`2026062601-bug-translate-findings`), several defects
were found and fixed in the translation pipeline. In the process, the `metadata` schema
evolved beyond the original flat shape and gained an `i18n` wrapper with additional
provenance and source-language fields. This ADR records the intended schema and resolves
whether the `i18n` wrapper is warranted.

---

## Decision

### TR1 — Flat language-keyed schema with top-level metadata

The `metadata` column shape for translation storage is:

```json
{
  "schema_version": 1,
  "source_language": "en",
  "source_language_confidence": 1.0,
  "canonical_language": "en",
  "canonical_origin": "original",
  "en": {
    "title": "Misspelling of 'Laboratory'",
    "description": "The word 'aboratory' is missing the initial 'L', which is a clear typo.",
    "suggestion": "Laboratory instruments and equipment—Taxonomy",
    "provenance": "canonical"
  },
  "zh": {
    "title": ""Laboratory"的拼写错误",
    "description": "单词"aboratory"缺少首字母"L"，这是一个明显的拼写错误。",
    "suggestion": "实验室仪器设备—分类法",
    "provenance": "llm_translation"
  }
}
```

Language-keyed translation objects sit **directly at the top level** of `metadata`,
alongside the global metadata fields. There is no `i18n` wrapper and no inner
`translations` object.

### TR2 — The `i18n` wrapper is removed

The `i18n` wrapper that appeared during bug investigation:

```json
{
  "i18n": {
    "translations": { "en": {...}, "zh": {...} },
    "schema_version": 1,
    ...
  }
}
```

serves no purpose that justifies the extra nesting. Reasons for removal:

- The `metadata` column on `kb.doc_review_findings` has no other consumers: all
  content in it is translation-related. A namespace wrapper adds indirection without
  preventing a conflict.
- Go code that reads `metadata["zh"]` is simpler than `metadata["i18n"]["translations"]["zh"]`.
  PostgreSQL JSONB operators are similarly cleaner at one level (`metadata->'zh'` vs.
  `metadata->'i18n'->'translations'->'zh'`).
- The global metadata fields (`schema_version`, `source_language`, etc.) work equally
  well at the top level; wrapping them under `i18n` provides no grouping benefit.

All existing code (Go) and database queries MUST use the flat schema from TR1.
Any row already stored with the `i18n` wrapper shape is treated as legacy and is
re-translated on next access (the `likelyUntranslatedForLanguage` check will detect
that the expected path is missing and retry).

### TR3 — Global metadata fields

| Field | Type | Purpose |
|-------|------|---------|
| `schema_version` | int | Schema version; currently `1`. Increment if the shape changes incompatibly. |
| `source_language` | string | BCP-47 code of the language the reviewer originally wrote the finding in (e.g. `"en"`). |
| `source_language_confidence` | float | Confidence of the source-language detection, `0.0–1.0`. `1.0` when set explicitly by the reviewer. |
| `canonical_language` | string | Language of the authoritative / canonical content. Normally equals `source_language`. |
| `canonical_origin` | string | How the canonical content was determined. `"original"` = the finding was authored in this language; `"llm_translation"` = the canonical was itself produced by the translator. |

### TR4 — Per-translation object fields

Each language-keyed object contains:

| Field | Type | Purpose |
|-------|------|---------|
| `title` | string | Translated title of the finding. |
| `description` | string | Translated description. |
| `suggestion` | string | Translated suggestion. |
| `provenance` | string | `"canonical"` if this is the authoritative source content; `"llm_translation"` if it was produced by the LLM translator. |

`finding_type` is **not** included in the per-translation object. It is `snake_case`
English metadata, not prose, and is excluded from target-language character checks
and equivalence comparisons (see Fix 11 in the bug doc).

### TR5 — Lazy translation at per-language, per-request level

Translations are populated on demand, not eagerly:

- When the report page is loaded with language `zh`, only `zh` translations are
  fetched or generated. Other languages are not pre-translated.
- A translation is cached once successfully generated. Subsequent requests for the
  same finding in the same language use the cache.
- A cached translation is considered stale and retried if:
  1. The cached prose fields are byte-identical to the English source (Fix 4).
  2. The cached prose fields do not contain target-language characters for any
     non-empty field (Fix 10, using AND-with-skip-empty logic from Fix 13).

When `DOC_REVIEW_TRANSLATION = "auto"`, save-time pre-translation uses the language
list parsed from `DOC_REVIEW_REPORT_LANGUAGE`. The variable accepts both forms:

```bash
DOC_REVIEW_REPORT_LANGUAGE="en"
DOC_REVIEW_REPORT_LANGUAGE='["en", "zh"]'
```

If the variable is absent, empty, or yields no valid language codes, the pipeline
falls back to `["en"]`.

When `DOC_REVIEW_TRANSLATION = "on-demand"`, save-time translation is fully disabled:
the pipeline does not call the normalization prompt and does not call the localization
prompt. The row columns store the reviewer-authored prose as-is, and `metadata` records
the declared source language as both `source_language` and `canonical_language`.

### TR6 — Self-translation for findings already in the target language

If a finding's prose fields are already written in the target language (detected by
`findingInTargetLanguage`), the LLM is skipped entirely:

1. The source content is saved as the cached translation under that language code,
   with `provenance: "canonical"`.
2. The finding is returned unchanged.

This prevents the prompt-direction bug (Fix 8, Fix 9) where sending a Chinese finding
to the translator with `language: "zh"` caused Chinese→English output.

### TR7 — Translation concurrency and context handling

`localizeFindings` runs one goroutine per finding:

- A `context.WithCancel` allows the first goroutine error to cancel remaining
  in-flight LLM calls.
- DB saves use `context.WithoutCancel(ctx)` so that a sibling goroutine's
  cancellation does not prevent a successful translation from being persisted
  (Fix 15).
- Results are collected in an order-preserving buffered channel.

### TR8 — Reviewer-declared source language

Reviewer prompts MAY include a `language` field on each finding. This field is the
language of the prose emitted by the reviewer for `title`, `description`, and
`suggestion`, not the report display language.

When saving a finding:

1. If `language` is present, the pipeline treats it as the finding's source language.
2. If `language` is missing, empty, or invalid, the source language defaults to `en`.
3. The raw reviewer prose is stored under the matching top-level language key in
   `kb.doc_review_findings.metadata`.
4. In `auto` mode, canonical storage is English: the row columns `title`,
   `description`, and `suggestion` store canonical English content after normalization.
5. In `on-demand` mode, canonical storage is the reviewer-authored source language:
   the row columns store the raw reviewer prose and no save-time LLM call is made.

Example: `prompt-review-provisions-v3.md` instructs the reviewer to emit Chinese
`title`, `description`, and `suggestion`, plus `"language": "zh"`. If
`DOC_REVIEW_TRANSLATION = "auto"` and `DOC_REVIEW_REPORT_LANGUAGE = "en"` or
`DOC_REVIEW_REPORT_LANGUAGE = ["en"]`, this means the Chinese finding is normalized
to English for canonical row columns and the original Chinese prose is stored in:

```json
{
  "schema_version": 1,
  "source_language": "zh",
  "canonical_language": "en",
  "canonical_origin": "translated",
  "en": {
    "title": "Undefined acceptance criteria",
    "description": "The requirement states a condition but does not define acceptance criteria.",
    "suggestion": "Add measurable acceptance criteria.",
    "provenance": "canonical"
  },
  "zh": {
    "title": "未定义验收标准",
    "description": "该要求陈述了条件，但没有定义验收标准。",
    "suggestion": "补充可衡量的验收标准。",
    "provenance": "original_extraction"
  }
}
```

If the same reviewer output is saved with `DOC_REVIEW_TRANSLATION = "on-demand"`,
no normalization call is made and the stored metadata is:

```json
{
  "schema_version": 1,
  "source_language": "zh",
  "source_language_confidence": 1,
  "canonical_language": "zh",
  "canonical_origin": "original",
  "zh": {
    "title": "未定义验收标准",
    "description": "该要求陈述了条件，但没有定义验收标准。",
    "suggestion": "补充可衡量的验收标准。",
    "provenance": "canonical"
  }
}
```

This is intentionally independent of `DOC_REVIEW_REPORT_LANGUAGE`: report languages
choose which cached translations are displayed or generated; the reviewer output
`language` records the language the LLM actually used when authoring the finding.

### TR9 — Prompt files

The normalization/localization prompt files govern translation behavior:

| File | Prompt name constant | Used for |
|------|---------------------|---------|
| `prompts/prompt-doc-review-finding-normalize-v*.md` | configured by `REVIEW_FINDING_NORMALIZE_PROMPT` | Normalize reviewer output into canonical English and detect/source-preserve the original language |
| `prompts/prompt-doc-review-finding-normalize-retry-v*.md` | configured by `REVIEW_FINDING_NORMALIZE_RETRY_PROMPT` | Retry when normalization output is not valid canonical English |
| `prompts/prompt-doc-review-finding-localize-v*.md` | configured by `REVIEW_FINDING_LOCALIZE_PROMPT` | Translate canonical English into a requested display language |
| `prompts/prompt-doc-review-finding-localize-retry-v*.md` | configured by `REVIEW_FINDING_LOCALIZE_RETRY_PROMPT` | Retry when localized output remains untranslated |

Key prompt invariants (Fix 9):
- The `language` field in the JSON input **is** the target language, not the source.
- If a field's content is already in the target language, output it unchanged.
- For `zh`, prose must be in Simplified Chinese.

---

## Consequences

### Positive

- The schema is simpler; Go and SQL code that accesses translations requires one
  fewer level of key traversal.
- The `provenance` field per translation, and `source_language` / `canonical_origin`
  at the top level, make data lineage auditable without adding structural complexity.
- `schema_version` allows a future incompatible change to be detected and handled.

### Negative / Risks

- Rows stored under the old `i18n` wrapper shape will be silently retranslated on
  next access; this causes extra LLM calls for already-translated findings until
  the database is fully migrated.
- Source-language detection is currently `zh`-only (Han character check).
  Extending to other scripts (Hiragana/Katakana, Hangul, Arabic, etc.) requires
  updating `findingInTargetLanguage` and `translationInTargetLanguage`.
- The AND-with-skip-empty check in `translationInTargetLanguage` does not detect
  mixed-language content within a single field (e.g., a description with both
  Chinese and English sentences). A stronger check (per-sentence language detection)
  is a future improvement.

---

## References

- `2026061801-adr-document-review.md` — Core document review pipeline ADR (DR1–DR17)
- `2026062203-adr-generate-doc-review-report.md` — Report generation ADR
- `2026062601-bug-translate-findings.md` — Bug investigation: all 16 fixes to the
  translation pipeline that motivated this ADR
- `ChenWeb/server/api/doc-reviews/finding_translation.go` — Implementation
- `ChenWeb/prompts/prompt-doc-review-finding-translation-v1.md`
- `ChenWeb/prompts/prompt-doc-review-finding-translation-retry-v1.md`
