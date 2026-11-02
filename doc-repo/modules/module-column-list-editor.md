# Module: Column List Editor

**Module ID:** `20261102-07`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — used by the WPI editor's Properties panel (OpenSpec `wpi-property-editors`)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/value-editors`
**Created:** 2026-11-02

## 1. What it is

Edits a list's columns: one row per column with its label, field and width, an *Add column* form and a remove button per column. An empty width is left out. Value editor ID: `column-list`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/ColumnListEditor.svelte` | Column List Editor |

## 3. Interface

It follows the value-editor contract of [Property Editor](module-property-editor.md)
(`value-editors/types.ts`): props `id`, `label`, `value` (any JSON value, or `undefined` for
unset), `options` (`ValueEditorOptions`), an optional `check(value)` that returns a message when
the property's own rule refuses a value, and `onChange(value | undefined)`, which is called only
with values that pass; `undefined` unsets the value.

Stores an array of `{ "label": …, "field": …, "width"?: … }`; no columns unsets the value.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `id` | required | Element ID of the main control; a `<label for>` can point at it |
| `label` | required | The property's label, used for accessible names |
| `value` | required | The current value; `undefined` when unset |
| `onChange` | required | Receives each valid new value; `undefined` unsets |
| `check` | optional | The property's own rule; a message refuses the value |

## 5. Usage

```svelte
<ColumnListEditor id="prop-list-columns" label="Columns" value={attrs.columns} options={{}} onChange={(v) => set('columns', v)} />
```

In a property editor definition it is chosen by its value editor ID; the renderer passes the props.

## 6. Behaviour and conventions

Text stays selectable. All text goes through Paraglide (English and Chinese). Colours come from
the canvas theme variables (`--cv-*`) with plain fallbacks, so the editor works in light and dark
themes and outside the canvas. It depends on the shared files of
[Property Editor](module-property-editor.md) (`DraftField.svelte`, `values.ts`, `types.ts`,
`value-editors.css`).

## 7. Scope and limits

Column labels are plain strings (devdoc 2026102601 §9); the field is typed, not picked from the source's fields.
