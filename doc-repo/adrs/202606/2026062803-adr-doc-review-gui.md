# ADR 2026062803 — Document Review: Results View Summary Charts

**Date:** 2026-06-28 \
**Status:** Implemented \
**Component:** ChenWeb — `doc-review-results-view.svelte` \
**Authors:** Chen Ding \
**Tags:** doc review, GUI, svelte, charts, UX

---

## Change Logs

* 2026/06/28, ADR Created. Documents the replacement of the four static summary stat
  cards in the Document Review results view with four interactive visualization panels
  (DR-GUI-1 through DR-GUI-5). Implemented in
  `ChenWeb/web/src/lib/components/home3/doc-review-results-view.svelte`.

---

## Context

The Document Review results view (implemented in ADR 2026061801 §DR13) displayed four
plain stat cards once a review completed: Total Findings, High Severity count, Medium
Severity count, Low Severity count. These provided raw numbers but gave no visual
distribution insight and no breakdown by package or reviewer, making it hard to quickly
answer "where are findings concentrated?" and "which reviewers fired most?".

The `getRequest` API already returned a `packages: ReviewPackageInfo[]` array (key +
label for every configured review package), but the frontend was discarding it. The
`aspectStatuses: AspectStatus[]` array (already stored in state) contained the full
set of reviewers including those with zero findings.

---

## Decision

### DR-GUI-1 — Replace four stat cards with a 2×2 visualization grid

The four individual count cards are removed and replaced with four panels in a
`grid-template-columns: repeat(2, 1fr)` layout:

| Position | Panel |
|----------|-------|
| Top-left | Severity Distribution — donut chart |
| Top-right | By Package — donut chart + legend |
| Bottom-left | By Reviewer — donut chart + legend |
| Bottom-right | Review Metadata — compact info block |

This preserves the same horizontal footprint as the previous four-column layout while
providing substantially more information density.

### DR-GUI-2 — SVG donut charts, no external library

Charts are rendered as inline SVG using the `stroke-dasharray` / cumulative-rotation
technique. A single helper function `buildDonutSlices` computes the parameters:

```typescript
function buildDonutSlices(items: { count: number; color: string; label: string }[], r: number) {
    const total = items.reduce((s, i) => s + i.count, 0);
    if (total === 0) return [];
    const C = 2 * Math.PI * r;
    let cumAngle = -90;          // start at 12 o'clock
    return items.filter(i => i.count > 0).map(item => {
        const fraction = item.count / total;
        const dashLen = fraction * C;
        const startAngle = cumAngle;
        cumAngle += fraction * 360;
        return { color, label, count, strokeDasharray: `${dashLen} ${C}`, transform: `rotate(${startAngle}, 50, 50)` };
    });
}
```

Each slice is one `<circle cx="50" cy="50" r="35" stroke-width="16">` element. All
circles share the same center, radius, and stroke width inside a `viewBox="0 0 100 100"`
SVG rendered at 304×304 px. A background `<circle>` with `pointer-events: none` and
the `borderColor` stroke provides the empty-ring base.

**Rationale for no library:** consistent with the codebase's inline-style pattern; full
control over colors, sizing, and interactivity; zero new dependencies.

**Slice colors:**

- Severity: fixed semantic colors — High `#ef4444`, Medium `#f59e0b`, Low `#22c55e`.
- Packages and reviewers: a 10-color palette (`CHART_COLORS`) assigned by *alphabetical
  key order* of all non-empty items, so colors are stable when the sort order or
  selection changes.

### DR-GUI-3 — Hover tooltip rendered in the donut center

When the user hovers a slice, `onmouseenter` / `onmouseleave` on the SVG `<circle>`
elements update per-chart state (`hoverSev`, `hoverPkg`, `hoverRev`). While a slice is
hovered, two SVG `<text>` elements appear in the center of the donut:

- **Count** — large (`font-size="9"` in viewBox units ≈ 27 px displayed), in the
  slice's own color.
- **Label** — small (`font-size="4.5"` ≈ 14 px displayed), in `textSecondary` color,
  word-wrapped to two lines via `splitLabel` (DR-GUI-5).

Both text elements carry `style="pointer-events: none;"` to avoid blocking hover events
on the slice circles beneath them. The background ring circle also has
`pointer-events: none` so it does not intercept events intended for slices.

### DR-GUI-4 — Selectable legend entries

Each legend item in all three charts is a `role="button"` div with `onclick` /
`onkeydown` handlers. Clicking an entry toggles it in a per-chart `deselectedX: Set<string>`
state. When an entry is deselected:

- Its opacity drops to 0.35 and its label gets a `line-through` decoration.
- Its color swatch turns to `textMuted`.
- It is filtered out of the `activeItems` array fed to `buildDonutSlices`, so its
  slice disappears from the chart immediately.
- Clicking again re-adds it.

Toggle functions (`toggleSeverity`, `togglePackage`, `toggleReviewer`) create a new
`Set` on each call to trigger Svelte's reactivity.

Legend items are sorted by count descending (`sort((a, b) => b.count - a.count)`) so
the largest contributors appear at the top.

Packages and reviewers that have **zero findings** are not included in the pie or the
interactive legend, but appear in a dim "No findings: …" line below the scrollable
legend area. The full package list comes from `packages: ReviewPackageInfo[]` state,
now stored from the `getRequest` response (previously discarded). Zero-finding
reviewers come from `aspectStatuses` entries with `finding_count === 0`.

### DR-GUI-5 — Two-line label wrapping for tooltip text

Long package and reviewer names (e.g., "Technical & Compliance Standards",
"formatting consistency") previously overflowed the donut hole when shown as a single
truncated line. SVG `<text>` does not support CSS text wrapping, so a `splitLabel`
helper word-wraps the label into at most two lines:

```typescript
function splitLabel(label: string, maxLen = 18): string[] {
    if (label.length <= maxLen) return [label];
    const mid = label.lastIndexOf(' ', maxLen);
    if (mid > maxLen / 3) {
        const rest = label.slice(mid + 1);
        return [label.slice(0, mid), rest.length > maxLen ? rest.slice(0, maxLen - 1) + '…' : rest];
    }
    const rest = label.slice(maxLen);
    return [label.slice(0, maxLen), rest.length > maxLen ? rest.slice(0, maxLen - 1) + '…' : rest];
}
```

- Splits at the last word boundary within `maxLen` (18) characters.
- If no word boundary is found in the first third of `maxLen`, hard-splits at `maxLen`.
- The second line is truncated with `…` if it still exceeds `maxLen`.

When the label spans two lines, the count and label lines shift upward so the three
elements remain visually centered in the donut hole (count at `y="40"`, line 1 at
`y="51"`, line 2 at `y="58"`). One-line labels keep the original positions (count at
`y="44"`, label at `y="57"`).

Severity labels ("High", "Medium", "Low") are short enough that no splitting is needed;
they use a single text element with no truncation.

### DR-GUI-6 — Review Metadata panel

The fourth panel replaces the "Low Severity" count card with a compact key-value block:

| Field | Source |
|-------|--------|
| Start Time | `request.start_time` formatted with `toLocaleString()` |
| Time Used | `Math.round((end_time − start_time) / 1000)` seconds; `"—"` if `end_time` absent |
| Total Findings | `findings.length` |
| Non-Empty Packages | count of packages with ≥1 finding |
| Non-Empty Reviewers | count of reviewers with ≥1 finding |

Values are rendered in monospace to align columns visually.

---

## Implementation Files

| File | Change |
|------|--------|
| `ChenWeb/web/src/lib/components/home3/doc-review-results-view.svelte` | All changes — new state, derived values, helper functions, template |
| `ChenWeb/web/src/lib/services/docReviewService.ts` | No changes — `ReviewPackageInfo` type already existed; `getRequest` already returned `packages` |

---

## Alternatives Considered

**External chart library (e.g., Chart.js, ECharts):** rejected — adds a bundle
dependency and build complexity; the SVG `stroke-dasharray` donut is ~40 lines and
fully sufficient for this use case.

**CSS `conic-gradient` pie:** rejected — no per-slice hover events without additional
overlay elements; SVG circles give hover-per-slice for free.

**Floating div tooltip on hover:** considered for the label tooltip; rejected in favor
of the SVG center text approach, which stays contained within the chart element and
requires no absolute positioning relative to the cursor.
