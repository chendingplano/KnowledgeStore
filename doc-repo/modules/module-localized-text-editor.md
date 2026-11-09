# Module: Localized Text Editor

**Module ID:** `20261102-02`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — used by the WPI editor's Properties panel (OpenSpec `wpi-property-editors`)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/value-editors`
**Created:** 2026-11-02
**Devdocs:** [2026102701-devdoc-wpi-editor](../devdocs/202610/2026102701-devdoc-wpi-editor.md)

## 1. What it is

Edits text people read, such as a label or a page name. A pulldown chooses *Plain text* (one string for every language) or *English and Chinese* (one field per language, stored as `{"en": …, "zh-cn": …}`). A language left empty is left out of the stored map, so the languages can be filled in one at a time. Value editor ID: `localized-text`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/LocalizedTextEditor.svelte` | Localized Text Editor |

## 3. Interface

It follows the value-editor contract of [Property Editor](module-property-editor.md)
(`value-editors/types.ts`): props `id`, `label`, `value` (any JSON value, or `undefined` for
unset), `options` (`ValueEditorOptions`), an optional `check(value)` that returns a message when
the property's own rule refuses a value, and `onChange(value | undefined)`, which is called only
with values that pass; `undefined` unsets the value.

The pulldown has the ID `id`; the plain field `<id>-text`; the language fields `<id>-en` and `<id>-zh-cn`. Switching to *Plain text* keeps the English text.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `id` | required | Element ID of the main control; a `<label for>` can point at it |
| `label` | required | The property's label, used for accessible names |
| `value` | required | The current value; `undefined` when unset |
| `onChange` | required | Receives each valid new value; `undefined` unsets |
| `check` | optional | The property's own rule; a message refuses the value |
| `options.rows` | `1` | Rows of each text field |
| `options.emptyAction` | optional | Label of a button that stores the empty string (e.g. *Use empty text*) |
| `options.commitOnBlur` | `false` | Apply plain text on leaving the field instead of on every key |

## 5. Usage

```svelte
<LocalizedTextEditor id="prop-page-page_name" label="Page name" value={page.page_name} options={{ rows: 1 }} onChange={(v) => setPageName(v)} />
```

In a property editor definition it is chosen by its value editor ID; the renderer passes the props.

## 6. Behaviour and conventions

Text stays selectable. All text goes through Paraglide (English and Chinese). Colours come from
the canvas theme variables (`--cv-*`) with plain fallbacks, so the editor works in light and dark
themes and outside the canvas. It depends on the shared files of
[Property Editor](module-property-editor.md) (`DraftField.svelte`, `values.ts`, `types.ts`,
`value-editors.css`).

## 7. Scope and limits

Only English and Chinese, the two languages ChenWeb supports. The text check (`check`) sees the whole map after each change.
