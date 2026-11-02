# Module: Icon Library Frontend

**Module ID:** `20261102-10`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — exported from the shared Svelte library; not yet used by a ChenWeb screen
**Project:** shared
**Location:** `shared/svelte/src/lib/components/icons/`
**Created:** 2026-11-02

## 1. What it is

`Icon` shows a library icon by name. `IconSearchPicker` lets a person search the library by keyword or description and pick one. Not for the older upload-based `IconPicker`/`IconManager`.

## 2. Files

| File | Purpose |
|---|---|
| `shared/svelte/src/lib/components/icons/Icon.svelte` | renders an icon inline, sized and coloured by its container |
| `shared/svelte/src/lib/components/icons/IconSearchPicker.svelte` | search box and results grid |
| `shared/svelte/src/lib/stores/iconLibrary.ts` | `searchIcons`, `getIconSvg` (cached) |
| `shared/svelte/src/lib/components/icons/index.ts`, `shared/svelte/src/lib/index.ts` | exports |

## 3. Interface

- `<Icon name size={20} class />`: unknown names show a dashed placeholder.
- `<IconSearchPicker bind:value onSelect(name, icon) labels locale limit={48} columns={6} />`; `labels = { placeholder, empty, error }`, `locale` is `en` or `zh-cn` (chooses which description appears in the tooltip).
- `searchIcons(query, { category, limit, signal })`, `getIconSvg(name)`.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `size` | `20` | icon size in px |
| `limit` | `48` | results per search |
| `columns` | `6` | grid columns |
| `locale` | `en` | tooltip language |

## 5. Usage

```svelte
<script>
  import { IconSearchPicker, Icon } from '@chendingplano/shared';
  import { m } from '$lib/paraglide/messages.js';
  let icon = $state('');
</script>
<IconSearchPicker bind:value={icon}
  labels={{ placeholder: m.icon_search_placeholder(), empty: m.icon_search_empty(), error: m.icon_search_error() }} />
<Icon name={icon} size={24} />
```

## 6. Behaviour and conventions

The picker allows text selection. The shared library has no translations of its own, so the host app passes `labels` (Paraglide in ChenWeb). Search is debounced (250 ms) and cancels stale requests. SVG is inlined; the server has already cleaned it. Icons use `currentColor`.

## 7. Scope and limits

No category filter UI yet, and no upload UI for custom icons (API only). The ChenWeb page-designer `icon-picker` field is not yet connected to it.
