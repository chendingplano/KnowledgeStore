# Module: Color Picker

**Module ID:** `20261102-04`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.2
**Status:** active — used by the WPI editor's Properties panel (OpenSpec `wpi-property-editors`)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/value-editors`
**Created:** 2026-11-02

## 1. What it is

Edits a colour. A pulldown chooses *None* (unset), *Single color*, or, when allowed, *Light and dark* (stored as `{"light": …, "dark": …}`). Each colour has the browser's colour picker and a text field for any CSS colour (`rgba(…)`, names); the picker shows the nearest opaque colour while the typed CSS is kept. Switching mode keeps the colour already chosen. Value editor ID: `color`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/ColorPicker.svelte` | Color Picker |

## 3. Interface

It follows the value-editor contract of [Property Editor](module-property-editor.md)
(`value-editors/types.ts`): props `id`, `label`, `value` (any JSON value, or `undefined` for
unset), `options` (`ValueEditorOptions`), an optional `check(value)` that returns a message when
the property's own rule refuses a value, and `onChange(value | undefined)`, which is called only
with values that pass; `undefined` unsets the value.

The mode pulldown has the ID `id`; each colour's picker `<id>-<variant>-picker` and text field `<id>-<variant>`, where variant is `single`, `light` or `dark`.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `id` | required | Element ID of the main control; a `<label for>` can point at it |
| `label` | required | The property's label, used for accessible names |
| `value` | required | The current value; `undefined` when unset |
| `onChange` | required | Receives each valid new value; `undefined` unsets |
| `check` | optional | The property's own rule; a message refuses the value |
| `options.theme` | `false` | Offer separate light and dark colours |

## 5. Usage

```svelte
<ColorPicker id="prop-pane-main-background_color" label="Background color" value={pane.background_color} options={{ theme: true }} check={cssColorProblem} onChange={(v) => setPane('background_color', v)} />
```

In a property editor definition it is chosen by its value editor ID; the renderer passes the props.

## 6. Behaviour and conventions

Text stays selectable. All text goes through Paraglide (English and Chinese). Colours come from
the canvas theme variables (`--cv-*`) with plain fallbacks, so the editor works in light and dark
themes and outside the canvas. It depends on the shared files of
[Property Editor](module-property-editor.md) (`DraftField.svelte`, `values.ts`, `types.ts`,
`value-editors.css`).

The color dialog can be dragged by its heading. Clicking outside it closes it without
stealing focus; Escape and the close button also close it. After it is moved, other picker
instances open their dialogs at the same location for the rest of the page session. Its
resized width and height are also shared across picker instances for that session. The
position is kept visible and dimensions constrained when the viewport changes; these
settings are not persisted across reloads.

## 7. Scope and limits

Which CSS colours are accepted is the property's `check`; the editor itself accepts any text.
