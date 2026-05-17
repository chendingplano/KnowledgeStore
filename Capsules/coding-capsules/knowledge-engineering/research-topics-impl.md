# Research Topics — Implementation Notes

## Overview

The Research Topics page is a ChenWeb home3 feature that surfaces the Research Topic Bean (RTB) ontology defined in `research-topics.md` as a browsable, searchable UI. It lives under the **Knowledge Engineering** section in the home3 nav rail.

---

## File Locations

| File | Role |
|------|------|
| `ChenWeb/web/src/lib/components/home3/research-topics-view.svelte` | Main view component |
| `ChenWeb/web/src/lib/components/home3/nav-rail.svelte` | Nav registration |
| `ChenWeb/web/src/lib/components/home3/content-panel.svelte` | Render dispatch |

---

## Navigation Registration

### nav-rail.svelte

A new top-level nav item was added to `mainNav` under the **Workspace** group, after the existing Knowledge System entry:

```typescript
{
  id: 'knowledge-engineering',
  label: 'Knowledge Engineering',
  icon: BrainIcon,           // @lucide/svelte/icons/brain
  group: 'Workspace',
  children: [
    { id: 'ke-research-topics', label: 'Research Topics' }
  ]
}
```

The `BrainIcon` was imported alongside the existing Lucide icon imports.

### content-panel.svelte

Three additions were made:

1. **Import** the view component:
   ```typescript
   import ResearchTopicsView from '$lib/components/home3/research-topics-view.svelte';
   ```

2. **Section icon and description** entries:
   ```typescript
   // sectionIcons
   'knowledge-engineering': BrainIcon

   // sectionDesc
   'knowledge-engineering': 'Manage research topic beans: articles, thoughts, designs, specs, and readings.'
   ```

3. **Render branch** in the if-else chain:
   ```svelte
   {:else if activeMenu?.childId === 'ke-research-topics'}
     <ResearchTopicsView {darkMode} />
   ```

---

## View Component — `research-topics-view.svelte`

### Layout

The view uses a master-detail split:

```
┌─────────────────────────────────────────┐
│  Header: title, subtitle, "+ New RTB"   │
│  Search bar + Bean Type filter chips    │
├───────────────────────┬─────────────────┤
│  Bean list (cards)    │  Detail panel   │
│  (shrinks when bean   │  (opens on      │
│   is selected)        │   selection)    │
└───────────────────────┴─────────────────┘
```

When no bean is selected the list fills the full width. Selecting a card opens the detail panel alongside it; the list width transitions to 420px.

### Bean Type Color Coding

Each `bean_type` has a distinct accent color applied to its icon badge and type chip:

| Type | Color |
|------|-------|
| Thoughts | Amber `#FBBF24` |
| Design | Indigo `#818CF8` |
| Spec | Emerald `#34D399` |
| Implementation | Rose `#F87171` |
| Reading | Sky `#38BDF8` |

### Filtering

Two filter mechanisms are applied together via a `$derived` expression:

- **Search** — matches against `bean_name`, `research_title`, `bean_desc`, and `bean_keywords` (case-insensitive)
- **Bean Type chips** — "All" or any of the five `BeanType` values

### Detail Panel

Selecting a card renders the full RTB attribute set:

- Attribute grid (2-column): bean_name, bean_type, file_type with extension, bean_category, authors
- Description block
- Keywords (pill chips with accent tint)
- Related topics (monospace list items)

### Design Tokens

The component mirrors the home3 palette exactly, using the same `darkMode`-derived variables as every other home3 view:

```typescript
let pageBg      = $derived(darkMode ? '#171B26' : '#F2F4F7');
let cardBg      = $derived(darkMode ? '#1F2333' : '#FFFFFF');
let accent      = $derived(darkMode ? '#818CF8' : '#6366F1');
// … etc.
```

### TypeScript Types

```typescript
type BeanType = 'Thoughts' | 'Design' | 'Spec' | 'Implementation' | 'Reading';
type FileType = 'Markdown' | 'Typst' | 'Text' | 'HTML';

interface ResearchTopicBean {
  id: string;
  bean_name: string;
  bean_desc?: string;
  bean_keywords?: string[];
  bean_type: BeanType;
  related_topics?: string[];
  research_title: string;
  research_subtitle: string;
  file_type: FileType;
  bean_category: string;
  authors?: string[];
  content?: string;
}
```

All fields match the ontology defined in `research-topics.md`. Optional fields (`bean_desc`, `bean_keywords`, `related_topics`, `authors`, `content`) are guarded with `?.` and omitted from the detail panel when absent.

---

## Current State

The view ships with five hardcoded sample beans covering all five `BeanType` values and all four `FileType` values. No backend API is wired yet.

---

## Next Steps

- **API integration** — connect to a `/api/knowledge-engineering/research-topics` endpoint; replace `SAMPLE_BEANS` with a fetch-on-mount pattern matching the pattern used in `diary-view.svelte`
- **Create / Edit flow** — the "+ New RTB" button is rendered but not yet wired; needs a modal or inline form
- **Content rendering** — the `content` field is part of the type but not displayed; Markdown and Typst content could be rendered inline in the detail panel
- **`bean_category` navigation** — categories map to file paths in the KnowledgeStore; clicking a category could open the corresponding capsule directory
