# Module: Ordered Multi-Picker

**Module ID:** `20261102-03`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — used by the WPI editor's Properties panel (OpenSpec `wpi-property-editors`)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/value-editors`
**Created:** 2026-11-02

## 1. What it is

Chooses several values from a fixed list and their order: tick a value to include it, use the arrows to move it. The chosen values come first, in order. An unset value means all choices, in their listed order. Value editor ID: `ordered-multi-picker`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/OrderedMultiPicker.svelte` | Ordered Multi-Picker |

## 3. Interface

It follows the value-editor contract of [Property Editor](module-property-editor.md)
(`value-editors/types.ts`): props `id`, `label`, `value` (any JSON value, or `undefined` for
unset), `options` (`ValueEditorOptions`), an optional `check(value)` that returns a message when
the property's own rule refuses a value, and `onChange(value | undefined)`, which is called only
with values that pass; `undefined` unsets the value.

Stores an array of the chosen strings. A value cannot be unticked when that would leave fewer than `minItems`.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `id` | required | Element ID of the main control; a `<label for>` can point at it |
| `label` | required | The property's label, used for accessible names |
| `value` | required | The current value; `undefined` when unset |
| `onChange` | required | Receives each valid new value; `undefined` unsets |
| `check` | optional | The property's own rule; a message refuses the value |
| `options.choices` | required | The values offered, in their default order |
| `options.choiceLabel` | optional | Shown text for a value |
| `options.minItems` | `0` | The fewest values that must stay chosen |

## 5. Usage

```svelte
<OrderedMultiPicker id="prop-tabs" label="Tabs" value={attrs.tabs} options={{ choices: ['chat', 'dialog'], choiceLabel: tabLabel, minItems: 1 }} onChange={(v) => set('tabs', v)} />
```

In a property editor definition it is chosen by its value editor ID; the renderer passes the props.

## 6. Behaviour and conventions

Text stays selectable. All text goes through Paraglide (English and Chinese). Colours come from
the canvas theme variables (`--cv-*`) with plain fallbacks, so the editor works in light and dark
themes and outside the canvas. It depends on the shared files of
[Property Editor](module-property-editor.md) (`DraftField.svelte`, `values.ts`, `types.ts`,
`value-editors.css`).

## 7. Scope and limits

Choices are fixed strings; it does not search or add new values.
