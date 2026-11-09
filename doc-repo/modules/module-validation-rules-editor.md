# Module: Validation Rules Editor

**Module ID:** `20261102-08`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — used by the WPI editor's Properties panel (OpenSpec `wpi-property-editors`)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/value-editors`
**Created:** 2026-11-02
**Devdocs:** [2026102701-devdoc-wpi-editor](../devdocs/202610/2026102701-devdoc-wpi-editor.md)

## 1. What it is

Edits a WPI input's `validation` object. For number inputs it shows minimum, maximum and step; for other inputs minimum length and pattern. Rules of the other kind are kept when the input type changes. Value editor ID: `validation`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/ValidationEditor.svelte` | Validation Rules Editor |

## 3. Interface

It follows the value-editor contract of [Property Editor](module-property-editor.md)
(`value-editors/types.ts`): props `id`, `label`, `value` (any JSON value, or `undefined` for
unset), `options` (`ValueEditorOptions`), an optional `check(value)` that returns a message when
the property's own rule refuses a value, and `onChange(value | undefined)`, which is called only
with values that pass; `undefined` unsets the value.

Stores an object of the rules that are set; no rules unsets the value.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `id` | required | Element ID of the main control; a `<label for>` can point at it |
| `label` | required | The property's label, used for accessible names |
| `value` | required | The current value; `undefined` when unset |
| `onChange` | required | Receives each valid new value; `undefined` unsets |
| `check` | optional | The property's own rule; a message refuses the value |
| `options.numberRules` | `false` | Show number rules instead of text rules |

## 5. Usage

```svelte
<ValidationEditor id="prop-input-validation" label="Validation" value={attrs.validation} options={{ numberRules: attrs.input_type === 'number' }} onChange={(v) => set('validation', v)} />
```

In a property editor definition it is chosen by its value editor ID; the renderer passes the props.

## 6. Behaviour and conventions

Text stays selectable. All text goes through Paraglide (English and Chinese). Colours come from
the canvas theme variables (`--cv-*`) with plain fallbacks, so the editor works in light and dark
themes and outside the canvas. It depends on the shared files of
[Property Editor](module-property-editor.md) (`DraftField.svelte`, `values.ts`, `types.ts`,
`value-editors.css`).

## 7. Scope and limits

The pattern is not tested as a regular expression here; the interpreter checks it.
