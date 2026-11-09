# Module: Data Source Editor

**Module ID:** `20261102-06`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — used by the WPI editor's Properties panel (OpenSpec `wpi-property-editors`)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/value-editors`
**Created:** 2026-11-02
**Devdocs:** [2026102701-devdoc-wpi-editor](../devdocs/202610/2026102701-devdoc-wpi-editor.md)

## 1. What it is

Edits where a WPI `list` gets its rows (its `source` action instance): a table chosen with [Pick Table](module-pick-table.md), its fields with [Pick Fields](module-pick-fields.md), a row limit, the action (`load` or `query`), the result (`list`) and the sort order (Sort Order editor of [Property Editor](module-property-editor.md)). Choosing a table starts a fresh field list and sets `load`/`list` when they are unset. Value editor ID: `data-source`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/DataSourceEditor.svelte` | Data Source Editor |

## 3. Interface

It follows the value-editor contract of [Property Editor](module-property-editor.md)
(`value-editors/types.ts`): props `id`, `label`, `value` (any JSON value, or `undefined` for
unset), `options` (`ValueEditorOptions`), an optional `check(value)` that returns a message when
the property's own rule refuses a value, and `onChange(value | undefined)`, which is called only
with values that pass; `undefined` unsets the value.

Stores the whole `source` object; other keys it holds (such as `args` or `where`) are kept. It uses `withSourceProperty`, `withSelectedTable`, `withSourceFields` and `withListSourceDefaults` from `canvas/element-attributes.ts`.

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
<DataSourceEditor id="prop-list-source" label="Data source" value={attrs.source} options={{}} onChange={(v) => set('source', v)} />
```

In a property editor definition it is chosen by its value editor ID; the renderer passes the props.

## 6. Behaviour and conventions

Text stays selectable. All text goes through Paraglide (English and Chinese). Colours come from
the canvas theme variables (`--cv-*`) with plain fallbacks, so the editor works in light and dark
themes and outside the canvas. It depends on the shared files of
[Property Editor](module-property-editor.md) (`DraftField.svelte`, `values.ts`, `types.ts`,
`value-editors.css`).

## 7. Scope and limits

It edits the `load`/`query` source of a list only; `where`, `params` and `args` are edited as JSON in the Node tab.
