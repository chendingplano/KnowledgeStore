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

- [2026071401 — light/dark mode not carried from semos to home3](202607/2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3.md)
  — `fixed-unverified`: the mode store itself has still not been exercised in a
  browser end to end (toggle on `/semos` → `知识库` → `/home3`, and back).
- [2026071402 — knowledge store cards ignore light mode](202607/2026071402-bug-knowledge-store-cards-ignore-light-mode.md)
  — `fixed-unverified`: the light-mode `neon` slab values are a judgment call that
  has not been seen rendered.
- [2026071403 — record browser owns a palette instead of inheriting one](202607/2026071403-bug-record-browser-owns-a-palette-instead-of-inheriting-one.md)
  — `fixed-unverified` across nine views. All nine have since been seen in a
  browser in both modes (in 2026071404), but with empty/error data states, not
  with a real record loaded.
- [2026071404 — doc-structure line cards ignore light mode](202607/2026071404-bug-doc-structure-line-cards-ignore-light-mode.md)
  — `fixed-verified`, and the content-column audit that 2026071403 opened is now
  **closed**: all nine `/home3` host views have been swept and tokenized. Still
  owed: every view was verified with empty/error data (the browser session was
  unauthenticated, so `kb.inputs` returned `500`). The dialogs, tables, chunk
  cards and document frames were probed for computed values through the real
  cascade, but never seen populated with a real record.
- `kb-input-search-dialog.svelte` reads no theme tokens and takes no `darkMode`
  prop (noted in 2026071403, still true). Reachable from the `Search` button on
  every view that embeds the record browser. Never investigated.

## Not classified

These predate the `Status:` convention and have not been assessed. They are
listed so they are not silently assumed closed, not because they are known open.

- [2026070701 — provision reviewer missed semantic match](202607/2026070701-bug-provision-reviewer-missed-semantic-match.md)
- [2026071001 — PDF highlight shows whole list instead of cited lines](202607/2026071001-bug-pdf-highlight-shows-whole-list-instead-of-cited-lines.md)
