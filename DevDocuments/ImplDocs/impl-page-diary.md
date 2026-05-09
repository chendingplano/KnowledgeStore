# My Workspace — Diary Page

## Overview

The Diary page is a personal research-notes tool embedded in the `home3` workspace. It lets the user capture topics they are researching, attach multiple URLs, tag with keywords, record the source where they heard about the topic, and write freeform notes. All entries are persisted as plain JSON files on the server's local filesystem, organised by date.

The feature is accessible via **My Workspace → Diary** in the `home3` left nav rail.

---

## Entry Data Model

Each diary entry is stored as one JSON file. Fields:

| Field | Type | Description |
|---|---|---|
| `id` | `string` | UUID generated at creation time |
| `createdAt` | `string` | UTC timestamp in RFC 3339 Nano format |
| `topic` | `string` | Short title/subject of the entry |
| `urls` | `string[]` | Zero or more URLs associated with the topic |
| `keywords` | `string[]` | Free-form keyword tags |
| `source` | `string` | Where the user heard about the topic (e.g. "Hacker News", "colleague") |
| `content` | `string` | Freeform notes (plain text, newlines preserved) |

Example file:

```json
{
  "id": "3f2504e0-4f89-11d3-9a0c-0305e82c3301",
  "createdAt": "2026-05-08T14:32:00.000000000Z",
  "topic": "WASM component model",
  "urls": ["https://component-model.bytecodealliance.org/"],
  "keywords": ["wasm", "components", "bytecode-alliance"],
  "source": "Hacker News",
  "content": "The component model defines a portable, language-agnostic binary format..."
}
```

---

## File Layout on Disk

Entries are stored under the directory specified by the `DIARY_HOME_DIR` environment variable. The subdirectory hierarchy is:

```
$DIARY_HOME_DIR/
└── {YYYY}/           ← year
    └── {MM}/         ← month (zero-padded)
        └── {DD}/     ← day (zero-padded)
            └── {id}.json
```

Example:

```
$DIARY_HOME_DIR/2026/05/08/3f2504e0-4f89-11d3-9a0c-0305e82c3301.json
```

The server creates the year/month/day directories automatically on first write. The `DIARY_HOME_DIR` variable must be set before starting the server; the API returns HTTP 500 if it is missing.

---

## Backend — Go Handler

**Package:** `github.com/chendingplano/deepdoc/server/api/diaryhandler`

**File:** `server/api/diaryhandler/handler.go`

Five exported handler functions, all registered under the authenticated `/api/v1` Echo group:

| Method | Path | Handler | Description |
|---|---|---|---|
| `GET` | `/api/v1/diary` | `List` | Returns all entries, newest-first |
| `POST` | `/api/v1/diary` | `Create` | Creates a new entry, writes JSON file |
| `GET` | `/api/v1/diary/:id` | `Get` | Returns a single entry by ID |
| `PUT` | `/api/v1/diary/:id` | `Update` | Replaces mutable fields; `id` and `createdAt` are immutable |
| `DELETE` | `/api/v1/diary/:id` | `Delete` | Removes the JSON file |

`Get`, `Update`, and `Delete` scan the year/month/day tree to locate `{id}.json` without needing the date in the URL.

Route registration in `server/api/routes.go`:

```go
// Diary (My Workspace) endpoints
apiGroup.GET("/diary", diaryhandler.List)
apiGroup.POST("/diary", diaryhandler.Create)
apiGroup.GET("/diary/:id", diaryhandler.Get)
apiGroup.PUT("/diary/:id", diaryhandler.Update)
apiGroup.DELETE("/diary/:id", diaryhandler.Delete)
```

All endpoints require an authenticated session (enforced by `authmiddleware.AuthMiddleware` on the `apiGroup`).

---

## Frontend — Svelte Component

**File:** `web/src/lib/components/home3/diary-view.svelte`

The view has two columns rendered side-by-side inside a fixed-height flex container:

```
┌─────────────────────┬──────────────────────────────────────────┐
│  Entry List (276px) │  Detail / Form panel (flex-1)            │
│                     │                                          │
│  [New] button       │  Empty state  — no entry selected        │
│                     │  Form mode    — new entry or editing     │
│  ▾ May 2026         │  Detail mode  — read-only view           │
│    Thu May 8        │                                          │
│    • WASM component │                                          │
│    • Svelte runes   │                                          │
│  ▾ Apr 2026         │                                          │
│    ...              │                                          │
└─────────────────────┴──────────────────────────────────────────┘
```

### Left Panel — Entry List

- Entries are grouped by month (collapsible), then by day.
- Each day label shows the short weekday + date (e.g. "Thu May 8").
- Each entry shows the topic and creation time; source is shown if present.
- The selected entry is highlighted with the indigo accent tint and a left border.
- Clicking an entry loads it in detail mode in the right panel.

### Right Panel — Detail Mode

Shows the entry read-only:

- Topic as a heading, date and source in the subtitle line.
- Keywords as indigo chips.
- URLs as monospace link rows (open in new tab).
- Notes in a card with `white-space: pre-wrap`.
- **Edit** button switches to form mode. **Delete** button prompts for confirmation then removes the entry.

### Right Panel — Form Mode

Activated by clicking **New** or **Edit**. Fields:

| Field | Input type | Notes |
|---|---|---|
| Topic | `<input type="text">` | Single line |
| Source | `<input type="text">` | Single line |
| URLs | List of `<input type="url">` | Add/remove buttons; empty entries are stripped on save |
| Keywords | Chip input | Press Enter or comma to commit a chip; Backspace deletes the last chip |
| Notes | `<textarea>` | Resizable, 12 rows default |

**Save** calls `POST /api/v1/diary` for new entries or `PUT /api/v1/diary/:id` for edits. On success the list reloads and the panel switches back to detail mode. **Cancel** (edit only) discards changes and returns to detail mode.

---

## Nav Rail Integration

**File:** `web/src/lib/components/home3/nav-rail.svelte`

A new nav item is added to `mainNav` under the `"Personal"` group label:

```typescript
{
    id: 'my-workspace',
    label: 'My Workspace',
    icon: BookMarkedIcon,
    group: 'Personal',
    children: [
        { id: 'diary', label: 'Diary' }
    ]
}
```

Selecting **My Workspace → Diary** emits `{ itemId: 'my-workspace', childId: 'diary' }` to the parent page.

---

## Content Panel Routing

**File:** `web/src/lib/components/home3/content-panel.svelte`

`DiaryView` is rendered when `activeMenu.childId === 'diary'`:

```svelte
{:else if activeMenu?.childId === 'diary'}
    <DiaryView {darkMode} />
```

The `my-workspace` section icon (`BookMarkedIcon`) and description (`"Your personal workspace: diary, notes, and resources."`) are also registered in `sectionIcons` and `sectionDesc` so the breadcrumb topbar renders correctly.

---

## Configuration

| Environment variable | Required | Description |
|---|---|---|
| `DIARY_HOME_DIR` | Yes | Absolute path to the root directory where diary files are stored |

Set in the server's `.env` file, for example:

```
DIARY_HOME_DIR=/Users/cding/Diary
```

The directory does not need to exist in advance; it is created on the first write.

---

## Key Files

| File | Role |
|---|---|
| `server/api/diaryhandler/handler.go` | Go CRUD handler; reads/writes `DIARY_HOME_DIR` |
| `server/api/routes.go` | Route registration under `/api/v1/diary` |
| `web/src/lib/components/home3/diary-view.svelte` | Svelte UI component |
| `web/src/lib/components/home3/nav-rail.svelte` | Nav item (`My Workspace → Diary`) |
| `web/src/lib/components/home3/content-panel.svelte` | Route dispatch to `DiaryView` |
