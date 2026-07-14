# Open Bug Loops

Bug docs that are **not** in a terminal state. A bug doc explains what was
already done; it has no open/closed state of its own, so anything still owed —
an unrun verification, a deferred fix, a known-but-unfixed defect — is listed
here or it is forgotten.

Terminal (do not list here): `fixed-verified`, `wontfix`.
Listed here: `open`, `fixed-unverified`, or any doc with a "still worth doing".

Set `Status:` in the doc's header block. Remove the doc from this list when it
reaches a terminal state.

## Open

- [2026071404 — doc-structure line cards ignore light mode](202607/2026071404-bug-doc-structure-line-cards-ignore-light-mode.md)
  — `fixed-verified`, and the content-column audit that 2026071403 opened is now
  **closed**: all nine `/home3` host views have been swept and tokenized. Still
  owed: every view was verified with empty/error data (the browser session was
  unauthenticated, so `kb.inputs` returned `500`). The dialogs, tables, chunk
  cards and document frames were probed for computed values through the real
  cascade, but never seen populated with a real record.
- [2026071405 — kb.inputs search dialog owns a dark palette instead of inheriting one](202607/2026071405-bug-kb-input-search-dialog-ignores-light-mode.md)
  — `fixed-unverified`. The dialog reached from the `Search` button (noted open in
  2026071403/404) now takes a `darkMode` prop and inherits host tokens via `--sd-*`
  aliases; builds and type-checks. Still owed: browser verification of the
  data-populated surfaces (results table, record-detail dialog), which need an
  authenticated backend — `kb.inputs` returns `500` unauthenticated.
