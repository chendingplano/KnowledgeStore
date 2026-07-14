# Bug: doc-structure line cards stay dark in light mode (a persisted default that is a dark hex)

Date: 2026-07-14
Status: fixed-verified — the reported symptom was exercised in a browser in both modes;
some secondary surfaces of the same component were not (see "Still worth doing")
System: `ChenWeb` web frontend (SvelteKit), `/home3/doc-structure`
Component: `web/src/lib/components/home3/doc-structure-view.svelte`,
`web/src/lib/components/home3/doc-structure-settings.js`
Related: [doc-2026071402-bug-knowledge-store-cards-ignore-light-mode](2026071402-bug-knowledge-store-cards-ignore-light-mode.md)
(same defect class), [doc-2026071403-bug-record-browser-owns-a-palette-instead-of-inheriting-one](2026071403-bug-record-browser-owns-a-palette-instead-of-inheriting-one.md)
(named this as an open audit item), [doc-2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3](2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3.md)
(made it reachable)

## Summary

The `LINES` list on `/home3/doc-structure` — the middle column, and the single
densest thing on the page — rendered as dark slabs on a cream page in light mode.
The row text is theme-aware and flipped to dark ink, so the line content sat dark
ink on a near-black card.

This is the third instance of one rule, and the first one found in a host view's
*own* content column rather than in a shared component. doc-2026071403 predicted
it in as many words: "each host's *own* content column is still unaudited."

The cause is the same shape as the `neon` card preset in doc-2026071402, with one
twist that made it more durable: the offending value is not merely a hardcoded
constant in CSS, it is a **persisted user setting whose default is a dark hex**.

## Symptom

1. Open `/home3/doc-structure` in light mode (the default on a light-mode OS).
2. The page shell, header, the `kb.inputs` record column (fixed in doc-2026071403),
   and the PDF pane are all correctly light.
3. The `LINES` cards between them are near-black rounded slabs, with their `L1`,
   `PARAGRAPH` / `HEADING-1` and content text in dark ink on top.

## Root Cause

`.line-card` does not read a theme token. It reads a settings-derived one:

```css
.line-card { background: var(--line-record-bg); }
```

`--line-record-bg` is fed from the persisted per-user settings object:

```js
export const DOC_STRUCTURE_RECORD_DEFAULT_BACKGROUND = '#1C212C';   // the default
```
```svelte
--line-record-bg:{recordBackground || DOC_STRUCTURE_RECORD_DEFAULT_BACKGROUND};
```

`#1C212C` is not an arbitrary colour. It is **exactly the dark-mode value of
`panelBgAlt`** in the same file:

```js
let panelBgAlt = $derived(darkMode ? '#1C212C' : '#F0EADB');
```

So the intent had always been "the cards are the alt panel surface" — but the
value was snapshotted as a constant instead of referenced as a token, and the
snapshot was taken in dark mode. It could not flip, because a `const` has no
`darkMode` to depend on. Everything else in the row (`--text-primary`,
`--text-muted`, `--brass`) is a real token and did flip. Hence dark ink on a dark
card.

The same file also hardcoded dark literals in its Settings and delete dialogs
(`#171c26`, `#1a202b`, `#2a3140`, text `#f3eedf`), and an error box whose text was
`#f3b7ac` — a *light* pink chosen for a dark background, which in light mode was
near-invisible on its own pale pink fill.

### Why a persisted default is worse than a hardcoded constant

doc-2026071402's `neon` slab was wrong in CSS, so editing the CSS fixed it for
everyone. This one is wrong in **stored state**. Every user who has ever opened
this page has `{"recordBackground":"#1C212C"}` sitting in `localStorage` under
`chenweb:doc-structure:<user>:settings`. Making the *default* theme-aware would
have fixed nothing for them: their stored value would still be read back and still
be a dark hex, and the bug would look "unfixed" while the code looked right.

A theme-blind value that has been persisted needs a **migration**, not just a new
default.

## Fix

The record background becomes a genuine override — absent by default — instead of
a colour that merely happens to equal the theme.

1. **The default is now "follow the theme"**, represented as the empty string:

   ```js
   export const DOC_STRUCTURE_RECORD_THEME_BACKGROUND = '';
   ```
   ```svelte
   --line-record-bg:{recordBackground || 'var(--panel-bg-alt)'};
   ```

   With nothing stored, the cards *are* `--panel-bg-alt` — cream in light, `#1C212C`
   in dark. Dark mode is byte-identical to before.

2. **The legacy value is migrated, not honoured.** `mergeDocStructureSettings`
   maps a stored `#1C212C` back to theme-following, case-insensitively. This is
   safe precisely because that value was the default: nobody ever *chose* it, so
   nothing a user actually picked is discarded. Any other hex is kept as the
   deliberate override it is.

3. **The override is reversible.** The settings dialog's colour picker had no way
   back to the default once touched, which is what would have made a
   "follow the theme" state unreachable in practice. A `Follow theme` button next
   to the picker clears the override; the picker itself now displays the resolved
   theme colour (`recordBackground || panelBgAlt`) when no override is set.

4. **The rest of the component's mode-blind literals become tokens** — the same
   treatment doc-2026071403 applied to the record browser. Sixteen new `$derived`
   values (crimson, error fill/text, the dialog section/field/input surfaces, the
   disabled-button greys) replace the hardcoded darks in the Settings dialog, the
   delete dialog, the error boxes, and the `Select` button — which had been
   hardcoding *dark-mode* brass (`#d4a24c`) rather than reading `--brass`.

What remains hardcoded is deliberately mode-neutral: translucent brass tints,
dark ink (`#1d1508`) on brass buttons, white on the crimson destructive button,
and the modal scrim.

## Verification

- `npx tsx --test doc-structure-settings.test.js`: 7 pass. Three new tests cover
  the theme default, the legacy `#1C212C` migration (both cases), and that an
  explicit override survives while still being clearable.
  Two failures remain, **pre-existing and unrelated**: the `lineListWidth` clamp
  tests expect a 760 max while the source says 960. Identical on the parent
  commit; untouched here.
- `npx svelte-check`: 0 errors (23 warnings in 12 files — unchanged baseline).
- `npx vite build`: succeeds.
- **Exercised in a browser** (Playwright, `prefers-color-scheme` light and dark).
  Computed style of `.line-card` through the real cascade:

  | mode | `--line-record-bg` | `.line-card` background | text |
  |---|---|---|---|
  | light | `#F0EADB` | `rgb(240, 234, 219)` cream | `rgb(26, 20, 16)` dark ink |
  | dark | `#1C212C` | `rgb(28, 33, 44)` | `rgb(237, 231, 211)` |

  The cards now read as letterpress rows matching the rest of the page, and dark
  mode is unchanged. The Settings dialog was opened in both modes and is cream in
  light, dark in dark, with the `Follow theme` button correctly disabled while no
  override is set.

### Still worth doing

The browser check ran against a backend that returned `500` for `kb.inputs` (the
Playwright context is unauthenticated), so the line rows were injected into the
real `.line-list` with the real scope class rather than loaded from the API. The
CSS cascade being exercised is therefore genuine — that is the entire bug — but
these were *not* seen with real data:

- the delete-line dialog and the PDF line-selection dialog (both retokenized here),
- the renumber error box,
- the page at large with a real record loaded (e.g. record 416).

## Change Record

Files changed:
- `web/src/lib/components/home3/doc-structure-view.svelte`
- `web/src/lib/components/home3/doc-structure-settings.js`
- `web/src/lib/components/home3/doc-structure-settings.test.js`

## Documentation Impact

What knowledge changed:

- The rule from doc-2026071402 and doc-2026071403 now has a third form, and this
  is the one to remember: **a theme-blind value that is persisted needs a
  migration, not just a better default.** Fixing the default alone leaves every
  existing user broken while the code reads as correct.
- A user-configurable colour must default to *absent* (meaning "inherit the
  theme"), never to a literal that happens to match one mode. The tell for this
  defect: a default constant whose value is character-for-character equal to one
  branch of a `$derived(darkMode ? … : …)` — as `#1C212C` was to `panelBgAlt`.
- Any such override needs a documented way back to the default, or the
  theme-following state is unreachable after the first click.
- `doc-structure-view.svelte` now defines these tokens beyond the eight standard
  letterpress ones: `--crimson`, `--crimson-line`, `--crimson-faint`,
  `--error-bg`, `--error-text`, `--dialog-section-bg`, `--dialog-field-bg`,
  `--dialog-field-line`, `--dialog-input-bg`, `--dialog-input-line`,
  `--dialog-input-text`, `--btn-disabled-*`. If another `/home3` host needs the
  same, these are the names to reuse.

Docs affected / updated:
- This bug report.
- `bugs/OPEN.md` — doc-2026071403 left "each host's own content column is still
  unaudited" open. `doc-structure` is now audited and fixed; the remaining hosts
  are not (see Stale docs).

Stale docs:
- None, but the audit doc-2026071403 opened is still only partly done. The other
  eight views that embed the record browser (`metrics`, `chunks`, `summary-tree`,
  `provisions`, `semantic-projections`, `inputs`, `inventory-items`,
  `kb-extraction`) have **not** had their own content columns checked for this
  same defect. `doc-structure` was the one in the screenshot; it is unlikely to
  be the only one.

Intentionally left undocumented / not fixed:
- `kb-input-search-dialog.svelte` — still reads no tokens and takes no `darkMode`
  prop, exactly as doc-2026071403 recorded. Reachable from this page's `Search`
  button. Not investigated, still very likely broken in light mode.
- The heavy drop shadows (`rgba(0,0,0,0.55)`) on the dialogs are tuned for a dark
  page and are heavier than a light theme wants. Cosmetic; out of scope, as in
  doc-2026071402.
- The `.pvw-*` PDF-toolbar rules read `var(--pvw-*, <fallback>)` tokens owned by
  `pdf-view-window.svelte`, not by this view. Left alone.
