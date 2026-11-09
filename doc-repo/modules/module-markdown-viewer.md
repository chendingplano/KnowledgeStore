# Module: Markdown Viewer

**Module ID:** `20261109-01`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — new; not yet adopted by existing views (harness dialog, metric review and the user manual still call `marked` themselves)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/markdown-viewer`
**Created:** 2026-11-09
**Devdocs:** None

## 1. What it is

A read-only viewer for Markdown text. Give it a string and it shows headings, lists, code,
quotes and tables. The text may come from an LLM or a document, so it is treated as
untrusted: raw HTML is shown as plain text, links keep only `http(s):`, `mailto:` and `#`
targets, and images are off unless asked for. It is not an editor, and it does not highlight code.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/markdown-viewer/markdown.ts` | `renderMarkdown(source, opts)`: pure, safe Markdown → HTML string |
| `ChenWeb/web/src/lib/components/shared-ui/markdown-viewer/markdown-viewer.svelte` | The component; styles the output, selectable text |
| `ChenWeb/web/src/lib/components/shared-ui/markdown-viewer/markdown.test.ts` | Tests for rendering and the safety rules |

## 3. Interface

```ts
renderMarkdown(source: string, opts?: { gfm?: boolean; breaks?: boolean; allowImages?: boolean }): string
```

Component props: `source: string`, `gfm?`, `breaks?`, `allowImages?`, `emptyText?: string`,
`ariaLabel?: string`.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `gfm` | `true` | Tables, task lists, strikethrough |
| `breaks` | `false` | A single newline becomes a line break |
| `allowImages` | `false` | Render `http(s)` images; otherwise the alt text is shown |
| `emptyText` | none | Dimmed text shown when `source` is blank |

## 5. Usage

```svelte
<script lang="ts">
  import MarkdownViewer from '$lib/components/shared-ui/markdown-viewer/markdown-viewer.svelte';
  let { answer }: { answer: string } = $props();
</script>

<MarkdownViewer source={answer} breaks emptyText="No answer yet." />
```

Outside a component (for example an export), call `renderMarkdown(text)` directly.

## 6. Behaviour and conventions

- Output is safe for `{@html}`; do not add another sanitiser on top.
- Text is selectable (`select-text`).
- Colours follow the current text colour, so it works in light and dark themes.
- Renderers are cached per option set.

## 7. Scope and limits

No syntax highlighting, math, or heading anchors. Callers with special raw HTML (metric
review's pre-sanitised grounding tables) keep their own renderer. The first adopters to
migrate are `harness-conversation.ts` and `metric-review-client.ts`; if another project
needs it, move it to `shared/svelte`.
