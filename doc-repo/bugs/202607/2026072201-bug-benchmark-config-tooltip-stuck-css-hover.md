# Bug: Benchmark config help tooltip pops up far from the `?` icon (stuck CSS `:hover`)

Date: 2026-07-22\
Status: fixed-verified\
System: `ChenWeb` web frontend (Svelte 5), System Admin → Benchmark → Setup\
Component: `ChenWeb/web/src/lib/components/home3/benchmark-setup-view.svelte` (the `?` help tooltips on the "Benchmark config" fields)

## Summary

Moving the mouse into the "Benchmark config" card — from the side, **far from any
of the small `?` icons** — made a field's help tooltip pop up (and stay up). It
felt "too sensitive": you never had to reach the icon.

This was a **second** attempt at the bug. An earlier commit
(`bc402ecd`, "fix benchmark config tooltip hover target") had already restructured
the markup so the tooltip panel is a *sibling* of the `?` button inside a 14×14
`.help-anchor`, revealed by the CSS adjacent-sibling rule
`.help-tip:hover + .tooltip { display: flex }`. That markup fix was correct and
live in the browser (verified) — but the symptom persisted, because the real
cause was not the markup structure.

## Root Cause

**A stuck / stale CSS `:hover` flag on the tiny `.help-tip` button**, combined with
revealing the tooltip *purely* from that flag.

The tooltip was shown only by `.help-tip:hover + .tooltip`. The browser kept the
`:hover` style flag set on the 14×14 button even when the cursor had moved far away
(never clearing it on leave). Because the reveal was 100% dependent on that flag,
the tooltip stayed/appeared with the cursor nowhere near the icon.

Two aggravating factors specific to this layout made it easy to trigger and very
visible:

- `.field` is a **column flex** (`display:flex; flex-direction:column`), so its
  default `align-items: stretch` stretches the child `.field-label` to the **full
  column width** (~318px) even though its content (label text + 14px icon) is tiny.
  So there is a wide invisible label band across the whole row that the cursor
  sweeps through on the way in.
- The reveal toggled an **adjacent sibling's `display`** (`none` → `flex`) on
  `:hover`. Toggling `display` (a layout-affecting property) in response to
  `:hover` is a known trigger for Chromium's stuck-`:hover` behavior.

Net effect: brush anywhere along that wide row, the `:hover` flag lands on the
icon and never clears, and the panel is stuck open.

### The decisive evidence (this is the reusable part)

The trap: `getBoundingClientRect` said the icon was 14×14 at `x≈673`, but the
cursor was at `x≈934` — 260px away — and the tooltip was up. It *looked* like the
icon had a giant invisible hit area. It does not. The truth came from comparing
**two browser APIs that must agree but didn't**:

- `document.querySelectorAll(':hover')` (the **style** hover chain) →
  `[… config-grid, LABEL.field, SPAN.field-label, BUTTON.help-tip]` — lists the
  button as hovered.
- `document.elementsFromPoint(x, y)` (the **physical** hit-test at the cursor) →
  `[SPAN.field-label, LABEL.field, config-grid, …]` — **no button**. The cursor is
  physically over the stretched `.field-label`, not the icon.

When those two disagree — `:hover` includes the trigger but `elementsFromPoint`
does not — the `:hover` flag is **stale/stuck**, full stop.

A second, equally diagnostic tell showed up earlier in the same investigation:
`button.matches(':hover') === true` while its **parent** `.help-anchor`
`.matches(':hover') === false`. That is **impossible** for a genuine pointer
hover — `:hover` always applies to an element *and its entire ancestor chain*. A
child hovered while its parent is not ⇒ the flag is stuck, not real.

(Also ruled out along the way, so you don't re-check them: no global `.tooltip`
CSS collision — every other `.tooltip` in the repo is scoped to its own component,
and `app.css`/Tailwind v4 defines none; the button had no `::before`/`::after`,
no overflow, `pointer-events:auto`, clean 14px box; not `:focus`/`:focus-visible`;
not a stale build — the fixed markup and CSS were confirmed live via a build
marker logged from the component itself.)

## Fix

Stop depending on the flaky CSS `:hover` flag. Drive the tooltip from explicit
**pointer/focus events on the exact trigger element**, toggling state, and reveal
via a class:

- Removed `.help-tip:hover + .tooltip` (and its `:focus-visible` sibling variant).
- Added `let openHelp = $state<string | null>(null)` and, on each `?` button:
  `onmouseenter`/`onmouseleave` (mouse) + `onfocus`/`onblur` (keyboard a11y),
  each setting/clearing `openHelp` to that field's key.
- Tooltip panel now uses `class:open={openHelp === key}` with CSS
  `.tooltip.open { display: flex }`.

```svelte
<button
  type="button"
  class="help-tip"
  aria-label={`${field.label} help`}
  onmouseenter={() => (openHelp = String(field.key))}
  onmouseleave={() => { if (openHelp === String(field.key)) openHelp = null; }}
  onfocus={() => (openHelp = String(field.key))}
  onblur={() => { if (openHelp === String(field.key)) openHelp = null; }}
>
  <CircleHelpIcon size={14} />
</button>
<span class="tooltip" class:open={openHelp === String(field.key)} style="…">…</span>
```

**Why this works when CSS `:hover` didn't:** `mouseenter`/`mouseleave` are
boundary-crossing *events* dispatched against the **real hit-target** (the same
target `elementsFromPoint` reports — which was correct all along). They do not
consult the `:hover` *style* flag, so a stuck flag can't keep the panel open.
`mouseleave` fires reliably on exit even in the cases where the `:hover` style
never clears.

## How to diagnose this class of bug again

Symptom shape: a CSS-`:hover`-revealed element (tooltip / popover / dropdown /
menu) appears or **stays visible while the cursor is not over its trigger** —
especially when the trigger sits inside a container stretched wider than itself
(flex `align-items: stretch`, grid cell, full-width label).

1. **Do not trust `getBoundingClientRect` vs pointer coords alone.** It will make
   you chase a phantom "huge hit area." Measure what the browser actually thinks.
2. **Compare the two hover truths** at the moment the element is wrongly visible:
   - `Array.from(document.querySelectorAll(':hover')).map(e => e.tagName + '.' + e.className)`
   - `document.elementsFromPoint(x, y)` (plural)
   Sample both on a `requestAnimationFrame` after the visibility change (not
   synchronously inside the `mousemove` handler — mid-event reads are unreliable).
   - Disagreement (`:hover` lists the trigger, `elementsFromPoint` doesn't) ⇒
     **stuck `:hover`** ⇒ switch to JS `mouseenter`/`mouseleave`.
   - A child matching `:hover` while its parent does not ⇒ same conclusion.
3. **Edge-triggered logger** (log only when the set of visible panels changes, so
   the console isn't flooded) is the right instrument. Sketch:
   ```js
   let last = '';
   window.addEventListener('mousemove', (e) => {
     const vis = [...document.querySelectorAll('.tooltip')]
       .filter(p => getComputedStyle(p).display !== 'none');
     const key = vis.map(v => v.previousElementSibling?.getAttribute('aria-label')).join('|');
     if (key === last) return; last = key;
     const px = e.clientX, py = e.clientY;
     requestAnimationFrame(() => {
       console.log('hoverChain', [...document.querySelectorAll(':hover')].map(el => el.tagName + '.' + (el.className||'').split(' ')[0]));
       console.log('physical  ', document.elementsFromPoint(px, py).map(el => el.tagName + '.' + (el.className||'').split(' ')[0]));
     });
   });
   ```
   Add a one-time build marker (`console.log` of icon count / computed size) so you
   can prove the *fixed* source is actually the running code before chasing the CSS.
4. **Prefer JS events over CSS `:hover` for reveal** whenever the trigger is small,
   lives inside a stretched container, and the reveal toggles a layout property
   (`display`) on a sibling. That combination is the stuck-`:hover` recipe.

## Verification

- User confirmed in-browser: moving into the config far from any `?` no longer
  shows a tooltip; hovering directly on a `?` shows it and leaving hides it;
  keyboard Tab to a `?` shows it on focus and hides on blur.
- All debug instrumentation was removed from the component after the fix.

## Change Record

Code fix in `ChenWeb/web/src/lib/components/home3/benchmark-setup-view.svelte`
only (markup handlers + `openHelp` state + one CSS rule swap). Applied against a
live `mise dev` (Vite HMR) on staging (`dingbo.bzton.cn`); no rebuild/redeploy
step involved. At fix time the ChenWeb web tree also had an unrelated pre-existing
modified file (`doc-review-results-view.svelte`) — left untouched. Not yet
committed at the time this record was written (awaiting user go-ahead on `jj`).

## Documentation Impact

What knowledge changed:
- When a CSS-`:hover`-revealed popover shows while the cursor isn't on its trigger,
  suspect a **stuck `:hover` style flag**, and confirm it by diffing
  `querySelectorAll(':hover')` against `elementsFromPoint()` — don't chase hit-area
  geometry. The robust fix is JS `mouseenter`/`mouseleave` (+ `focus`/`blur`), not
  more CSS tweaking.

Which docs/specs/tests are affected:
- None found. No shared tooltip/popover component or convention exists; each
  component rolls its own `.tooltip`.

Which docs were updated:
- This bug record only.

Which docs may still be stale:
- The earlier fix commit `bc402ecd` ("fix benchmark config tooltip hover target")
  addressed markup structure but not the underlying `:hover`-flag dependency; its
  message reads as if the hover issue was solved. This record supersedes that
  understanding.

What was intentionally left undocumented:
- The same `.help-tip:hover + .tooltip` pattern may exist in the other `.tooltip`
  components listed during triage (`FormItemInput.svelte`, `form-twocolumn.svelte`,
  `AddResourceForm.svelte`, etc.). They were not audited or changed here — flag for
  follow-up if the symptom appears elsewhere.
