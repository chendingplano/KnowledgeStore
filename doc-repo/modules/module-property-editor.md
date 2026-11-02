# Module: Property Editor

**Module ID:** `20261102-01`
**Type:** frontend · **Language:** svelte · **Version:** 1.1.0
**Status:** active — used by the WPI editor's Properties panel (OpenSpec `wpi-property-editors`)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/property-editor`
**Created:** 2026-11-02

## 1. What it is

The form the WPI Editor shows in its right-hand Properties panel for the selected page, pane,
panel or element. It is drawn while the app runs from a *definition* (data that lists the
entity's groups and, for each property, its label, value editor and the data that editor needs)
and a *source* (what reads and writes the entity). No entity has a Svelte file of its own: adding
a property means adding a line to a definition. Every editor looks the same: a title, groups that
fold when their heading is clicked, and for each property a label, *Reset*, the value editor, an
info icon with the help tip at the editor's upper right, and any error, warning or note.

The module also holds the value-editor contract and the simple value editors. The non-trivial
editors are catalogued separately (Localized Text Editor, Ordered Multi-Picker, Color Picker,
Length Editor, Data Source Editor, Column List Editor, Validation Rules Editor). The definitions
themselves belong to [Web Page Interpreter (frontend)](module-web-page-interpreter-frontend.md)
(`web/src/lib/wpi/properties/`). The rules every property editor follows are in devdoc
2026102701 §1.3.9.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/property-editor/PropertyEditor.svelte` | The renderer: title, groups, property rows, Other group, focus reporting |
| `ChenWeb/web/src/lib/components/shared-ui/property-editor/HelpTip.svelte` | Info icon at the value editor's upper right; hover or focus shows the tip |
| `ChenWeb/web/src/lib/components/shared-ui/property-editor/editors.ts` | The value editor component for each value editor ID |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/types.ts` | `ValueEditorProps` and `ValueEditorOptions`: the contract every value editor follows |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/values.ts` | Pure parsing and value helpers (lengths, numbers, JSON, lists, colours, languages) |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/values.test.ts` | Tests for `values.ts` (`bun test`) |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/value-editors.css` | Shared look of the value editors |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/DraftField.svelte` | Text field that keeps typed text, applies only valid text, and on leaving with invalid text shows why with *Abandon Edit* and *Stay Edit* |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/TextEditor.svelte` | One line of text; empty unsets |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/MultilineTextEditor.svelte` | Longer text |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/NumberEditor.svelte` | A number within `min`/`max`, optionally whole |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/SwitchEditor.svelte` | On or off |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/ValuePicker.svelte` | One value from `choices`, in a pulldown; `emptyLabel` adds an unset choice |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/StringListEditor.svelte` | A list of words as comma-separated text |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/ReadOnlyValue.svelte` | A value shown but not edited |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/JsonEditor.svelte` | Any value as JSON text; text that does not parse is kept as a string |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/SortOrderEditor.svelte` | Sort columns, each ascending or descending |

## 3. Interface

`PropertyEditor.svelte` props:

- `title: string` — the heading, e.g. "Element: input".
- `def: EditorDef` — `{ groups: GroupDef[], otherHelp? }`; a group is `{ id, label(), help?(),
  properties: PropertyDef[], visible?(ctx) }`; a property is `{ name, label?(), helpTip?(),
  editor?, options?, read?, write?, computed?, readOnly?, visible?(ctx), validate?(value, ctx),
  warn?(value, ctx), note?() }` (`web/src/lib/wpi/properties/types.ts`). A property without
  `editor` gets the common-sense editor (`common-sense.ts`).
- `source: PropertySource` — `get`, `isSet`, `fixed`, `required`, `helpTip`, `defaultValue`,
  `set(name, value | undefined)`, `names` (attributes for the Other group), `resettable(name)`.
- `context` — what definitions may look at besides the entity's values: `triggerActions`,
  `pageLayouters`, `position`, `pane`, `flowConfig`, `leaf`, `paneIdProblem`.
- `idPrefix: string` — each property's control gets the ID `<idPrefix>-<name>`.
- `onEditStart?()`, `onEditEnd?()` — called when focus enters a property and leaves it, so the
  caller can record one undo step per focus.
- `children?` — a snippet drawn between the title and the groups (the pane editor's tree).

Value editors take `ValueEditorProps` (`id`, `label`, `value`, `options`, `check?`, `onChange`).

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `title` | required | The heading |
| `def` | required | The entity's definition |
| `source` | required | Reads and writes the entity |
| `context` | required | Lists and canvas facts definitions use |
| `idPrefix` | required | Prefix of the controls' IDs |
| `onEditStart` | optional | Focus entered a property |
| `onEditEnd` | optional | Focus left it |
| `children` | optional | Snippet between title and groups |

## 5. Usage

```svelte
<PropertyEditor
	title={m.propertiespanel_element_title({ name: 'input' })}
	def={elementEditor('input')}
	source={elementSource(attrs, elementClass, moduleFallbacks('input'), (next) => onNode(node.id, { ...node.data, attrs: next }))}
	context={{ triggerActions, pageLayouters: [], pane: 'main', flowConfig, position }}
	idPrefix={`prop-${node.id}`}
	onEditStart={() => editSession.start()}
	onEditEnd={() => editSession.end()}
/>
```

`canvas/WpiProperties.svelte` shows the four real uses (element, page, pane, panel).

## 6. Behaviour and conventions

- A valid value is applied at once. Invalid typed text is kept, not applied and not flagged
  while the field has focus. On leaving the field (or Enter) with invalid text, the text stays
  and under the value editor appear the reason and "This value is not applied." with two
  buttons: *Abandon Edit* (show the stored value again) and *Stay Edit* (focus back in the
  field) (`aria-invalid`, `role="alert"`). A change from elsewhere, such as undo, drops the
  typed text. Warnings describe applied values (`role="status"`).
- Groups are `<details open>`; clicking the summary folds them. Hidden properties keep their values.
- Text is selectable (`select-text`); all text goes through Paraglide; colours use the `--cv-*`
  canvas variables.

## 7. Scope and limits

- Definitions are code, not descriptors; drawing editors from descriptors with WPI is later work.
- Date, time and button-type pickers and standalone database/schema pickers are not built; add
  them when a property needs one, and catalogue them unless they are very simple.
