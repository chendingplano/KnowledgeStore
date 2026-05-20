# Research ResearchTopics — Implementation Notes

## Overview

The Research ResearchTopics page is a ChenWeb home3 feature that surfaces the Research Topic Bean (RTB) ontology defined in `research-topics.md` as a browsable, searchable UI. It lives under the **Knowledge Engineering** section in the home3 nav rail.

---

## File Locations

| File | Role |
|------|------|
| `ChenWeb/web/src/lib/components/home3/research-topics-view.svelte` | Main view component |
| `ChenWeb/web/src/lib/components/home3/nav-rail.svelte` | Nav registration |
| `ChenWeb/web/src/lib/components/home3/content-panel.svelte` | Render dispatch |
| `ChenWeb/server/api/kehandler/handler.go` | Go backend handler |
| `ChenWeb/server/api/routes.go` | Route registration |
| `ChenWeb/.env` | Environment variable definitions |

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ARTIFACT_DIR` | **Yes** | Absolute path to the root artifacts directory. RTB files are stored under `$ARTIFACT_DIR/ResearchTopics/`. Must be set before starting the server; the handler returns HTTP 500 if absent. |

### Storage layout

```
$ARTIFACT_DIR/
└── ResearchTopics/
    └── <bean_category>/          ← maps directly from the RTB's bean_category field
        ├── <bean_name>.json      ← full RTB metadata (all fields, used for listing)
        └── <bean_name>.<ext>     ← content artifact (.md / .typ / .text / .html)
```

**Example** — for a bean with `bean_category = "knowledge-engineering/ingestion"`,
`bean_name = "chunking-strategy-spec"`, `file_type = "Typst"`:

```
$ARTIFACT_DIR/ResearchTopics/knowledge-engineering/ingestion/chunking-strategy-spec.json
$ARTIFACT_DIR/ResearchTopics/knowledge-engineering/ingestion/chunking-strategy-spec.typ
```

### Current value (ChenWeb/.env)

```
ARTIFACT_DIR=/Users/cding/Workspace/ChenWeb/Data/artifacts
```

---

## API Endpoints

Both routes sit inside the authenticated `apiGroup` (`/api/v1`, requires JWT).

| Method | Path | Handler | Description |
|--------|------|---------|-------------|
| `GET` | `/api/v1/ke/research-topics` | `kehandler.List` | Walk `$ARTIFACT_DIR/ResearchTopics/**/*.json` and return all beans |
| `POST` | `/api/v1/ke/research-topics` | `kehandler.Create` | Validate, write metadata JSON + content artifact, return 201 |

### Create request body

```json
{
  "bean_name":         "chunking-strategy-spec",
  "research_title":    "Document Chunking Strategy",
  "research_subtitle": "Specification for Semantic and Structural Chunking Approaches",
  "bean_type":         "Spec",
  "file_type":         "Typst",
  "bean_category":     "knowledge-engineering/ingestion",
  "bean_desc":         "...",
  "bean_keywords":     ["chunking", "ingestion"],
  "authors":           ["Chen Ding"],
  "related_topics":    ["vector-embeddings-retrieval"],
  "content":           "= Document Chunking Strategy\n..."
}
```

Required fields: `bean_name`, `research_title`, `research_subtitle`, `bean_type`, `file_type`, `bean_category`.

### Error responses

| Status | Condition |
|--------|-----------|
| 400 | Missing required field, invalid `bean_type`/`file_type`, unsafe `bean_category` (path traversal) |
| 409 | A bean with the same `bean_name` already exists in the same `bean_category` |
| 500 | `ARTIFACT_DIR` not set, or filesystem write failure |

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
    { id: 'ke-research-topics', label: 'Research ResearchTopics' }
  ]
}
```

### content-panel.svelte

Three additions:

1. **Import** the view component:
   ```typescript
   import ResearchResearchTopicsView from '$lib/components/home3/research-topics-view.svelte';
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
     <ResearchResearchTopicsView {darkMode} />
   ```

---

## View Component — `research-topics-view.svelte`

### Layout

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

When no bean is selected the list fills the full width. Selecting a card opens the detail panel alongside it (list width transitions to 420px).

### Data loading

Beans are fetched from the API on mount. The component handles three non-happy-path states explicitly: loading spinner, error banner with a retry button, and an empty-state card that distinguishes "no beans exist yet" from "no beans match the current filter".

### New RTB modal

Clicking **+ New RTB** opens a modal over the view. All RTB fields are present:

- Required (disable submit until filled): `research_title`, `research_subtitle`, `bean_name`, `bean_type`, `file_type`, `bean_category`
- Optional: `bean_desc`, `bean_keywords`, `authors`, `related_topics`, `content`

`bean_keywords`, `authors`, and `related_topics` are entered as comma-separated strings and split into arrays before submission. `content` is sent verbatim and written to the artifact file. On success the new bean is prepended to the list without a full reload.

### Bean Type color coding

| Type | Color |
|------|-------|
| Thoughts | Amber `#FBBF24` |
| Design | Indigo `#818CF8` |
| Spec | Emerald `#34D399` |
| Implementation | Rose `#F87171` |
| Reading | Sky `#38BDF8` |

### Filtering

Two filters applied together via `$derived`:

- **Search** — matches `bean_name`, `research_title`, `bean_desc`, and `bean_keywords` (case-insensitive)
- **Bean Type chips** — "All" or any of the five `BeanType` values

### TypeScript types

```typescript
type BeanType = 'Thoughts' | 'Design' | 'Spec' | 'Implementation' | 'Reading';
type FileType = 'Markdown' | 'Typst' | 'Text' | 'HTML';

interface ResearchTopicBean {
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
  created_at?: string;
}
```

---

## Seed Data

20 RTBs covering common knowledge engineering topics were written directly to disk under `$ARTIFACT_DIR/ResearchTopics/knowledge-engineering/`. They span all five bean types and both `.md` and `.typ` file formats:

| Sub-category | Beans |
|---|---|
| `graphs` | knowledge-graph-fundamentals, graph-embedding-methods, knowledge-graph-completion, kgqa-implementation |
| `ontology` | ontology-design-patterns, ontology-alignment |
| `retrieval` | vector-embeddings-retrieval, vector-database-architecture, rag-system-design, semantic-similarity-metrics |
| `ingestion` | document-chunking-strategy, document-classification-thoughts, document-summarization-pipeline |
| `extraction` | named-entity-recognition, information-extraction-pipeline, entity-resolution |
| `structure` | topic-tree-construction, taxonomy-construction |
| `representation` | cross-lingual-knowledge-representation, provenance-tracking |

---

## Next Steps

- **Content rendering** — the `content` field is stored in the artifact file but not yet displayed in the detail panel; Markdown could be rendered with a lightweight parser, Typst as plain text
- **Edit flow** — no edit/delete UI yet; beans can only be created or modified directly on disk
- **`bean_category` navigation** — categories map to file paths; clicking a category badge could open a filtered view or the corresponding KnowledgeStore capsule directory
- **Pagination / sorting** — the list handler returns all beans unsorted; large collections will need server-side pagination or client-side virtual scrolling
