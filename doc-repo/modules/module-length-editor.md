# Module: Length Editor

**Module ID:** `20261102-05`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — used by the WPI editor's Properties panel (OpenSpec `wpi-property-editors`)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/value-editors`
**Created:** 2026-11-02

## 1. What it is

Edits a width, height, gap or margin: an allowed keyword (`auto`, `elastic`) or a non-negative number with an allowed unit. A number typed without a unit means px (`240` is stored as `240px`); a percentage is at most 100. A half-typed value is not flagged while typing; an invalid one is never applied, and on leaving the field the editor says why and offers *Abandon Edit* and *Stay Edit*. Value editor ID: `length`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/LengthEditor.svelte` | Length Editor |

## 3. Interface

It follows the value-editor contract of [Property Editor](module-property-editor.md)
(`value-editors/types.ts`): props `id`, `label`, `value` (any JSON value, or `undefined` for
unset), `options` (`ValueEditorOptions`), an optional `check(value)` that returns a message when
the property's own rule refuses a value, and `onChange(value | undefined)`, which is called only
with values that pass; `undefined` unsets the value.

Stores a string such as `240px`, `1.5rem`, `50%` or `auto`; empty unsets.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `id` | required | Element ID of the main control; a `<label for>` can point at it |
| `label` | required | The property's label, used for accessible names |
| `value` | required | The current value; `undefined` when unset |
| `onChange` | required | Receives each valid new value; `undefined` unsets |
| `check` | optional | The property's own rule; a message refuses the value |
| `options.keywords` | `[]` | Keywords allowed besides lengths |
| `options.units` | `["px", "rem", "em", "%"]` | Units allowed |
| `options.commitOnBlur` | `false` | Apply on leaving the field instead of on every key |

## 5. Usage

```svelte
<LengthEditor id="prop-page-width" label="Width" value={page.width} options={{ keywords: ['auto'], units: ['px', 'rem', 'em', '%'] }} onChange={(v) => setPage('width', v)} />
```

In a property editor definition it is chosen by its value editor ID; the renderer passes the props.

## 6. Behaviour and conventions

Text stays selectable. All text goes through Paraglide (English and Chinese). Colours come from
the canvas theme variables (`--cv-*`) with plain fallbacks, so the editor works in light and dark
themes and outside the canvas. It depends on the shared files of
[Property Editor](module-property-editor.md) (`DraftField.svelte`, `values.ts`, `types.ts`,
`value-editors.css`).

## 7. Scope and limits

No `calc()`, `vw` or `vh`; add units to `parseLength` in `values.ts` if the interpreter learns them.
