# Module: Pick Table

**Module ID:** `20261029-01`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — used by the WPI editor: inside the data-source editor, and as the `table-picker` value editor and element class
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/database-picker`
**Created:** 2026-10-29
**Devdocs:** [2026102701-devdoc-wpi-editor](../devdocs/202610/2026102701-devdoc-wpi-editor.md)

## 1. What it is

Pick Table lets a user choose a database, schema and table through a cascading menu. It lists databases allowed by the WPI configuration and supports pointer and keyboard navigation.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/database-picker/TablePicker.svelte` | Cascading picker UI and catalog retrieval. |
| `ChenWeb/web/src/lib/components/shared-ui/database-picker/table-catalog.ts` | Catalog grouping and legacy reference helpers. |
| `ChenWeb/web/src/lib/components/shared-ui/database-picker/table-catalog.test.ts` | Catalog grouping tests. |

## 3. Interface

`value: string` is the currently selected table, or an empty string. `onSelect(value: string): void` receives a `database.schema.table` reference. Existing shorter references can be displayed unchanged.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `value` | required | Current table reference. |
| `onSelect` | required | Selection callback. |

The server reads `[wpi].databases_to_show` from ChenWeb configuration. The authenticated `/api/v1/wpi/table-catalog` endpoint supplies databases and their tables.

## 5. Usage

```svelte
<script lang="ts">
  import TablePicker from '$lib/components/shared-ui/database-picker/TablePicker.svelte';
  let table = $state('');
</script>
<TablePicker value={table} onSelect={(value) => (table = value)} />
```

## 6. Behaviour and conventions

Labels use Paraglide and the control uses the canvas theme variables. Catalog requests are asynchronous, time out after 20 seconds, and offer retry on failure. The menu supports hover, click and keyboard navigation.

## 7. Scope and limits

The component depends on ChenWeb's authenticated WPI catalog API and database configuration. Move the component and its API contract into `shared/` if multiple projects adopt it.
