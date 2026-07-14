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

- **[2026071401 — light/dark mode not carried from /semos into /home3](202607/2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3.md)**
  — `fixed-unverified`. Builds and type-checks; never exercised in a browser.
  Owed: toggle mode on `/semos`, click `知识库`, confirm `/home3/knowledge` opens
  in the same mode; toggle inside `/home3`, return to `/semos`, confirm it
  persisted.

- **[2026071402 — knowledge store cards ignore light mode](202607/2026071402-bug-knowledge-store-cards-ignore-light-mode.md)**
  — `fixed-unverified`. Builds and type-checks; the light-mode card colors have
  not been seen rendered. Owed: confirm the near-white neon panel reads well on
  the cream page, the halo is not overpowering, the `ACTIVE` pill keeps contrast,
  and dark mode is unchanged.
  Also owed, and wider than the fix: the rest of `/home3` (`metrics`, `chunks`,
  `inputs`, `doc-structure`, `doc-review-report/[id]`) became reachable in light
  mode for the first time with 2026071401 and has never been audited for the same
  defect class — an opaque layer painted over a theme-aware one.

## Not classified

These predate the `Status:` convention and have not been assessed. They are
listed so they are not silently assumed closed, not because they are known open.

- [2026070701 — provision reviewer missed semantic match](202607/2026070701-bug-provision-reviewer-missed-semantic-match.md)
- [2026071001 — PDF highlight shows whole list instead of cited lines](202607/2026071001-bug-pdf-highlight-shows-whole-list-instead-of-cited-lines.md)
