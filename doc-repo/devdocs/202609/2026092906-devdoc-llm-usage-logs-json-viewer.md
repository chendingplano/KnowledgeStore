# LLM Usage Logs JSON Viewer — Read archived request and response bodies

**Date:** 2026-09-29  
**Scope:** Explains how the LLM Usage Logs page fetches and displays archived bodies and other JSON in its dialog.  
**Code root:** `ChenWeb/web/src/lib/components/home3/llm-usage-logs-view.svelte`

## Summary

The LLM Usage Logs page lets administrators open archived input and output bodies from a usage event. JSON is shown as readable name–value rows, with nested objects and arrays displayed recursively. Some chat APIs put a second JSON document inside the message's `content` string; the viewer parses that content too, so it does not appear as one long escaped line. The dialog can be resized, and long bodies scroll inside it.

## Details

### Opening a body

The page's Input Body and Output Body buttons call `openBody(row, type)`. It fetches the selected archive through:

```text
GET /api/v1/llm/usage-events/{id}/body?type=input|output
```

The backend handler is `GetUsageEventBody` in `ChenWeb/server/api/llmreporthandler/handler.go`. It validates the type, resolves the archived body reference, reads the gzip archive, and returns its bytes. The frontend pretty-prints valid JSON before rendering it; non-JSON bodies are shown as text.

### Rendering rules

`renderJsonHtml(value, depth)` recursively turns JSON into HTML rows in the Svelte component:

| Value | Display |
| --- | --- |
| Object property | Property name at left, value at right |
| Nested object | Property name followed by its recursively rendered fields |
| Array | Indexed entries (`[0]`, `[1]`, …) |
| String | Escaped text with whitespace preserved and long content allowed to wrap |
| Number or boolean | Accent-colored scalar |
| `null` | Muted `null` label |
| Empty array or object | `[]` or `—` |

The indentation step is 8 px per nesting level. Array entries add an 8 px offset. Text is HTML-escaped before insertion through Svelte's `{@html ...}` rendering.

When an object has a string-valued `role` property, its string-valued `content` is parsed as JSON if possible. The parsed object, array, or scalar uses the same renderer. If parsing fails, `content` remains a normal string. Other string properties are never parsed as nested JSON.

If the outer body itself is malformed JSON, the dialog falls back to escaped, pre-wrapped text. The Show Selected action parses the selected text separately: valid JSON is displayed using the same renderer, malformed JSON produces an inline error, and non-JSON selections are reported as unsupported.

### Dialog sizing

The dialog uses the browser's native two-axis resize handle (`resize: both`). Its initial size is up to 900 px wide and 80 vh high (capped at 760 px), and min/max dimensions keep it within the viewport. The dialog clips its own overflow while the body pane scrolls, so resizing changes the visible reading area without removing access to the full body. Backdrop dismissal is handled on pointer-down only when the press starts on the backdrop; pointer release after an internal resize does not close the dialog.

## Known limitations

- Only chat-message `content` strings are considered for embedded JSON. JSON embedded in other fields remains a literal string.
- There are no expand/collapse controls for large objects; the full tree is rendered and navigated with scrolling.
- Native resize-handle appearance and behavior depend on browser support for CSS `resize`.
