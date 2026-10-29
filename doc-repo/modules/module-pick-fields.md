# Module: Pick Fields

**Module ID:** `20261029-02`
**Type:** frontend · **Language:** svelte · **Version:** 1.1.0
**Status:** active — used by the WPI editor
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/database-picker`
**Created:** 2026-10-29

## 1. What it is

Pick Fields lists the columns of a chosen database table. Users check the fields to include and may edit both the column and attribute names in a resizable dialog. It is useful wherever a ChenWeb form builds WPI-style column mappings.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/database-picker/FieldPicker.svelte` | Field picker UI and column retrieval. |
| `ChenWeb/web/src/lib/components/shared-ui/database-picker/field-mappings.ts` | Selection and attribute mapping updates. |
| `ChenWeb/web/src/lib/components/shared-ui/database-picker/field-mappings.test.ts` | Mapping update tests. |

## 3. Interface

`table: string` is a table reference accepted by the WPI catalog. `fields: Json[]` contains mappings such as `{ column: 'id', attribute: 'id' }`. `onChange(fields: Json[]): void` receives the updated mappings. Checking a new column uses its name as the initial attribute. Existing mapping properties are retained when a column or attribute is edited. Empty or duplicate column names are not accepted.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `table` | required | Selected table reference; empty disables the picker. |
| `fields` | required | Current field mappings. |
| `onChange` | required | Mapping update callback. |

## 5. Usage

```svelte
<script lang="ts">
  import FieldPicker from '$lib/components/shared-ui/database-picker/FieldPicker.svelte';
  import type { Json } from '$lib/wpi/types';
  let table = $state('miner.kb.people');
  let fields = $state<Json[]>([]);
</script>
<FieldPicker {table} {fields} onChange={(value) => (fields = value)} />
```

## 6. Behaviour and conventions

The authenticated `/api/v1/wpi/table-columns` endpoint returns columns in database order. Requests are asynchronous, time out after 20 seconds, and offer retry on failure. Labels use Paraglide and the control uses canvas theme variables. Previously selected columns missing from the current table remain visible so the user can remove them. The dialog can be resized by dragging its lower-right handle or using arrow keys on that handle.

## 7. Scope and limits

The component depends on ChenWeb's WPI catalog API and mapping format. Move the component and its API contract into `shared/` if multiple projects adopt it.
