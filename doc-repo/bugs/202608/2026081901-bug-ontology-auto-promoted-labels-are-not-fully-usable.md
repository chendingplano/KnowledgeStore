# Auto-promoted ontology labels are not fully usable and lose their language

Date: 2026-08-19

Status: confirmed; implementation in progress

System: ChenWeb SemOS ontology and metric identity resolution

Component: `extract_metrics`, auto-promotion, ontology label storage, name
resolver

Related: `ChenWeb/server/api/ontology/keywords/alignment.go`,
`ChenWeb/server/api/ontology/names/resolver.go`, and the Ontology Labels Guide.

## Summary

Auto-promotion is intended to make high-volume, document-derived ontology
labels usable without requiring a human to approve every label individually.
The `auto-promoted` status records that provenance and must function as an
approved label for runtime use.

Two defects violate that rule:

1. Auto-promotion writes every label with `lang = 'und'`, even when the label
   is visibly Chinese or English.
2. The name resolver treats only `included_in_release` terms and labels as
   usable. It therefore excludes otherwise usable `auto-promoted` content
   from exact governed-label resolution and preferred-label display.

## Observed failure

At 2026-08-19 10:04:59, processing record `416` failed while handling the
Chinese metric name `每户配备分类垃圾容器的数量`:

```text
auto-create term prefLabel: a prefLabel already exists for this term and language
```

The live `miner` database contained a matching preferred label for
`measurement:kwc_b5f5355d2860` with `lang = 'und'`, but no matching ontology
term or accepted alignment. The new auto-promotion attempt sees no accepted
alignment, attempts to recreate the term and label, then is stopped by the
orphaned preferred-label guard. Its transaction rolls back, so a retry alone
cannot resolve the record.

The investigation found 183 `auto-promoted` label rows without matching
ontology-term rows at the time of inspection. This is a data-repair concern
separate from the code fix.

## Expected behavior

- Auto-promoted labels and terms are usable in all runtime paths that accept
  human-approved/released governed content.
- The auto-promotion path assigns a useful label language when its text gives
  a deterministic script signal: Han text resolves to `zh`, Latin text to
  `en`, and only text without either supported signal remains `und`.
- Exact name resolution and preferred-label display include both
  `included_in_release` and `auto-promoted` ontology rows.
- Existing data is not silently changed by the code deployment. Repair of
  orphaned records remains an explicit, reviewed operational action.

## Root cause

`AlignmentsStore.EnsureAcceptedOrCreate` hard-codes `Lang: "und"` while
creating preferred and alternate labels. It receives the label text but never
resolves its language.

Separately, `names.Resolver` filters its governed exact-label query and
preferred-name lookup to `status = 'included_in_release'`. That predicate
conflicts with the auto-promotion design, whose term-usage guard already
accepts `auto-promoted` as immediately usable.

## Resolution plan

Implement deterministic script-based language resolution at the auto-promotion
boundary, widen the resolver’s usability predicates to include
`auto-promoted`, and add tests for Chinese, English, undefined-script, and
resolver visibility behavior. See
`ChenWeb/docs/superpowers/specs/2026-08-19-auto-promoted-label-language-design.md`.
