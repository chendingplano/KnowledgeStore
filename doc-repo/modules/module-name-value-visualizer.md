# Module: Name-Value Visualizer

**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/name-value/`
**Status:** In use by the MeSH Browser (Knowledge Base → Ontology → MeSH → MeSH Browser)
**Created:** 2026-10-24

## 1. What it is

A Svelte 5 component that shows one record as a list of name-value pairs: the field
names sit in a right-aligned left column, and each field's values are stacked in the
right column. This is the layout of the MeSH Browser's **Details** tab:

```
            MeSH Heading   130k protein, Tobacco mosaic virus
               Unique ID   C071899
   RDF Unique Identifier   https://id.nlm.nih.gov/mesh/C071899     ← external link
           Entry Term(s)   126-kDa protein, Tobacco mosaic virus
                           TMV 126-kDa protein, Tobacco mosaic virus
           Consider Also   Tobacco Mosaic Virus                     ← in-page link
```

Use it wherever a page shows the fields of a single record (a metric, a document, a
vocabulary entry, a configuration row) and the reader scans names to find a value.
It is not a table: it shows one record, not many.

## 2. Files

| File | Purpose |
|---|---|
| `name-value-visualizer.svelte` | The component. Renders a `<dl>` grid. |
| `name-value.ts` | Types (`NameValueItem`, `NameValueField`, `NameValueInput`) and `normalizeFields()`. |
| `name-value.test.ts` | Unit test for `normalizeFields()` (`bun test`). |

## 3. Data model

```ts
type NameValueItem = {
	text: string;          // what is shown
	href?: string;         // → external link, opens in a new tab
	onClick?: () => void;  // → in-page link button (e.g. open another record, switch tab)
	lang?: string;         // sets lang= on plain text (source-language vocabulary)
	mono?: boolean;        // monospace face, for identifiers and codes
};

type NameValueInput = {
	key: string;           // unique within the record; used as the {#each} key
	label: string;         // already localised (call m.*() before passing)
	values: (NameValueItem | string | null | undefined)[];
};
```

Each value renders one way: `href` wins, then `onClick`, otherwise plain text.

`normalizeFields()` (applied by the component) turns bare strings into items, drops
`null`/`undefined`/blank values, and then drops fields left with no values. Callers can
therefore pass optional fields without filtering them first.

## 4. Props

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `fields` | `NameValueInput[]` | — | The fields, in display order. |
| `labelWidth` | CSS length | `13rem` | Maximum width of the name column (minimum is 9rem). |
| `ariaLabel` | string | — | Accessible name for the list; pass an `m.*()` string. |

## 5. Usage

```svelte
<script lang="ts">
	import { m } from '$lib/paraglide/messages.js';
	import NameValueVisualizer from '$lib/components/shared-ui/name-value/name-value-visualizer.svelte';

	let { metric, openDoc } = $props();
	const fields = $derived([
		{ key: 'name', label: m.metric_name(), values: [metric.name] },
		{ key: 'id', label: m.metric_id(), values: [{ text: metric.id, mono: true }] },
		{ key: 'source', label: m.metric_source(),
		  values: [{ text: metric.docTitle, onClick: () => openDoc(metric.docId) }] },
		{ key: 'aliases', label: m.metric_aliases(), values: metric.aliases }
	]);
</script>

<NameValueVisualizer {fields} ariaLabel={m.metric_details()} />
```

Build the field list in `$derived` so labels follow a language switch without a reload.

### MeSH Browser adapter

`ChenWeb/web/src/lib/components/home3/mesh-record-details.svelte` keeps all MeSH
knowledge (field order in `buildRecordDetails()`, predicate→label map, link rules) and
converts `MeshProperty[]` to `NameValueInput[]` in `toFields()`:

- `rdfIdentifier` → `href` (NLM URL)
- `treeNumber` with an id → `onClick` switches to the MeSH Tree Structures tab
- any value with an id → `onClick` opens that record
- otherwise plain text with its `lang`

The component is used for the Details tab and for each concept's and term's metadata
on the Concepts tab.

## 6. Behaviour and conventions

- **Text selection:** the list carries `select-text`, so values can be copied even
  inside shells that set `select-none` (see workspace `CLAUDE.md` → Frontend).
- **i18n:** the component has no text of its own. Labels and `ariaLabel` must come from
  Paraglide (`m.*()`); value text is data and is shown as given.
- **Theme:** colours come from the page's CSS variables `--accent` (links) and fall back
  to `currentColor`, so it works in light and dark themes without its own tokens.
- **Layout:** long values wrap anywhere and keep line breaks (`white-space: pre-wrap`).
  Below 600px the name column shrinks to 35% of the width.
- **Keyboard:** links and link buttons are focusable and show a focus outline.

## 7. Scope and limits

Intentionally left out until a caller needs them: custom per-value render snippets,
showing empty fields with a placeholder, grouping fields under section headings, and
inline editing. If the component is needed by a project other than ChenWeb, move it to
`shared/svelte` (`@chendingplano/shared`) rather than copying it.
