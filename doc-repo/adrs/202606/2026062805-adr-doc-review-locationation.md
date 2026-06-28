# ADR 2026062805 — Document Review Finding Normalization and Localization

**Date:** 2026-06-28 \
**Status:** Proposed \
**Component:** ChenWeb, Doc Processor — document_review i18n \
**Authors:** Chen Ding

## Context

The document-review pipeline currently stores finding prose directly as returned
by the reviewer LLM and translates findings lazily when a user requests a
non-English report language.

This causes several problems:

1. Findings may be stored in mixed source languages, especially Chinese.
2. Lazy translation makes report reads slower and less predictable.
3. Translation can fail at read time, blocking report display.
4. Evidence is sometimes treated like display prose even though it should remain
   verbatim source text.
5. The current `metadata` shape is too narrow for future multilingual support.

Most reviewed documents are in Chinese, and some reviewer prompts already emit
Chinese findings. We therefore need a pipeline that can:

1. preserve the original source-language prose,
2. standardize the canonical stored prose to English,
3. precompute configured display-language translations automatically, and
4. support additional target languages later without redesigning the schema.

## Decision

Adopt a two-stage i18n pipeline for review findings:

1. **Normalization stage** at persistence time:
   detect the source language of `title`, `description`, and `suggestion`;
   convert the canonical stored fields to English; preserve the original
   source-language prose in metadata when the source language is not English.
2. **Localization stage** immediately after normalization:
   generate translations for every configured display language and store them in
   metadata before the review run is marked complete.

`evidence` MUST remain unchanged and MUST NOT be translated.

`finding_type` remains a stable machine code and MUST NOT be translated by the
LLM. User-facing labels for finding types should be derived separately.

## Data Model

The canonical database columns remain:

- `title`
- `description`
- `suggestion`
- `evidence`

After this change:

- `title`, `description`, and `suggestion` are canonical English.
- `evidence` remains the original verbatim text.

Finding i18n metadata is stored in `kb.doc_review_findings.metadata` under the
following shape:

```json
{
  "i18n": {
    "schema_version": 1,
    "source_language": "zh",
    "source_language_confidence": 0.98,
    "canonical_language": "en",
    "canonical_origin": "translated",
    "translations": {
      "en": {
        "title": "Canonical English title",
        "description": "Canonical English description",
        "suggestion": "Canonical English suggestion",
        "provenance": "canonical"
      },
      "zh": {
        "title": "原始中文标题",
        "description": "原始中文说明",
        "suggestion": "原始中文建议",
        "provenance": "original_extraction"
      }
    }
  }
}
```

Notes:

1. `translations` is keyed by BCP-47-ish language code such as `en`, `zh`,
   `ja`, `fr`.
2. `provenance` records where a translation came from, such as `canonical`,
   `original_extraction`, `llm_translation`, or `human_edit`.
3. Legacy top-level `metadata["zh"]` entries remain readable for backward
   compatibility, but new writes MUST use `metadata.i18n.translations`.

## Workflow

For each finding produced by a reviewer:

1. Run normalization.
2. If the finding prose is already English:
   keep the canonical columns unchanged and record `source_language = en`,
   `canonical_origin = original`.
3. If the finding prose is Chinese or another non-English language:
   translate `title`, `description`, and `suggestion` into English;
   overwrite the canonical columns with the English text;
   save the original source-language prose under
   `metadata.i18n.translations[source_language]`;
   set `canonical_origin = translated`.
4. Populate `metadata.i18n.translations["en"]` from the canonical English text.
5. For each configured display language other than `en`:
   if that language already exists as the preserved source language, reuse it;
   otherwise translate from canonical English and store the result.

This translation step is automatic and happens during review persistence, not on
demand when a report is read.

## Prompting Rules

Two prompts are required:

1. **Normalization prompt**
   produces:
   - detected `source_language`
   - `source_language_confidence`
   - canonical English `title`, `description`, `suggestion`
   - preserved source-language prose when the source is non-English
2. **Localization prompt**
   translates canonical English prose into a specific target language

Prompt constraints:

1. Never translate `evidence`.
2. Never translate `finding_type`.
3. Preserve severity, location, and confidence semantics.
4. Preserve technical meaning exactly.
5. If the source language is already the target language, reuse the stored
   source text instead of re-translating.

## Consequences

### Positive

1. All findings have one stable canonical language for downstream processing.
2. Original reviewer wording is preserved when it is not English.
3. Report reads become fast and deterministic because translations already
   exist.
4. Translation failures move to review-processing time, where they are easier
   to observe and retry.
5. The schema can support more target languages later without changing the main
   table columns.

### Negative

1. Review processing becomes more expensive because translation happens
   proactively.
2. A review run may fail during normalization/localization instead of succeeding
   with partially untranslated findings.
3. Operators must provision a translation-capable model whenever configured
   display languages require it.

## Implementation Notes

1. Automatic normalization/localization should be integrated into finding
   persistence so report reads only select stored translations.
2. The report/request read path should apply cached translations only; it should
   not perform fresh LLM translation for new findings.
3. Existing lazy-translation data should remain readable during migration.
4. Tests must cover:
   - English-source findings
   - Chinese-source findings
   - preserved untranslated evidence
   - automatic population of configured languages
   - backward compatibility with legacy metadata

## Status

Accepted for implementation on 2026-06-28.
