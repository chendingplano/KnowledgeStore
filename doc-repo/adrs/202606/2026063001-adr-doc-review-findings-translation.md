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

### TR8 — Prompt files

Two prompt files govern translation behavior:

| File | Prompt name constant | Used for |
|------|---------------------|---------|
| `prompts/prompt-doc-review-finding-translation-v1.md` | `doc-review-finding-translation` | First translation attempt |
| `prompts/prompt-doc-review-finding-translation-retry-v1.md` | `doc-review-finding-translation-retry` | Retry when first attempt returned untranslated content |

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
