# MinerU → Line File Conversion

## 1. Overview

This document describes the implementation that converts a MinerU parser result JSON file into the canonical Line File format (see `KnowledgeStore/Capsules/coding-capsules/input-management/spec-line-file.md`).

**Location:** `ChenWeb/server/api/file-converters/mineru.go`

The MinerU JSON has a flat page-item structure — each page contains a typed item list with no nested tree. The converter iterates each page's items, maps each to zero or more Line File records, applies repeat-content removal, and writes the `.txt` and `.origin` output files following the same conventions as the opendata converter.

---

## 2. Input JSON Structure

### Top-level fields

The converter parses only the `pages` field. All other top-level fields (`input_id`, `source_pdf`, `engine`, etc.) are present in the JSON but ignored.

| Field | Description |
|---|---|
| `pages` | Array of page objects (the only field used) |

### Page object (`mineruPage`)

| Field | Type | Description |
|---|---|---|
| `page_number` | int | 1-indexed page number used for Line File output |
| `items` | array | Content items for this page |

### Content item (`mineruItem`)

Only fields relevant to conversion are parsed. `sub_type`, `text_format`, `img_path`, and `page_idx` exist in the raw JSON but are not included in the struct and are ignored.

| Field | Type | Description |
|---|---|---|
| `type` | string | Item type (see type mapping below) |
| `text` | string | Text content; used by `text` and `equation` items |
| `text_level` | `*int` | Optional heading level; pointer distinguishes absent from zero |
| `list_items` | `[]string` | Plain string array; used by `list` items |
| `table_caption` | `[]string` | Caption strings; used by `table` items |
| `table_footnote` | `[]string` | Footnote strings; used by `table` items |
| `table_body` | string | HTML table string; used by `table` items |
| `bbox` | `json.RawMessage` | Bounding box; stored as raw JSON to preserve original format |

**`bbox` handling:** Stored as `json.RawMessage` and passed directly to the output as-is. This preserves the original integer or float encoding from MinerU without any re-marshaling. Falls back to `"[]"` when absent or `null`.

---

## 3. Type Mapping

| MinerU item type | Condition | Line file `line_type` | Emits |
|---|---|---|---|
| `text` | `text_level` non-nil and > 0 | `heading(N)` where N = `*text_level` | 1 line |
| `text` | `text_level` nil or 0 | `paragraph` | 1 line |
| `header` | — | — | **skip** |
| `footer` | — | — | **skip** |
| `page_number` | — | — | **skip** |
| `list` | — | `list-item` (one line per non-empty string in `list_items`) | N lines |
| `equation` | — | `equation` | 1 line |
| `table` | caption non-empty | `table-caption` (one per caption string) | M lines |
| `table` | `table_body` parseable | `table-row` (one per `<tr>`) | R lines |
| `table` | footnote non-empty | `table-footnote` (one per footnote string) | K lines |
| any other type | — | — | **silently skipped** |

---

## 4. Implementation

### 4.1 Main flow (`ConvertMineruFile`)

```
ConvertMineruFile(inputPath):
  1. Read and unmarshal JSON into mineruDocument (only pages decoded)
  2. items = extractMineruLineItems(doc.Pages)
  3. items = filterRepeatedContentLines(items, totalPages=len(doc.Pages))
  4. lines = formatOpenDataLines(items)          // reuses opendata.go function
  5. outputPath = mineruOutputPath(inputPath)
  6. Write outputPath: join(lines, "\n") + trailing "\n" if non-empty
  7. Write originPath (.origin) as read-only copy (0o444) via writeReadOnlyFile
  return outputPath
```

`formatOpenDataLines` and `filterRepeatedContentLines` are shared with the opendata converter and not duplicated.

### 4.2 Item extraction (`extractMineruLineItems`)

```
extractMineruLineItems(pages):
  items = []

  for each page in pages:
    pageStr = str(page.page_number)

    for each item in page.items:
      switch lowercase(trim(item.type)):

        case "header", "footer", "page_number":
          skip

        case "text":
          content = trim(item.text)
          if content == "": skip
          if item.text_level != nil and *item.text_level > 0:
            lineType = "heading", headingLevel = str(*item.text_level)
          else:
            lineType = "paragraph", headingLevel = ""
          append {page: pageStr, type: lineType, headingLevel: headingLevel,
                  bbox: mineruBBoxStr(item.bbox), content: content}

        case "list":
          bbox = mineruBBoxStr(item.bbox)
          for each s in item.list_items:
            if trim(s) != "":
              append {page: pageStr, type: "list-item", bbox: bbox, content: trim(s)}
          // All list-item lines share the parent list's bbox (no per-item bbox)

        case "equation":
          if trim(item.text) != "":
            append {page: pageStr, type: "equation",
                    bbox: mineruBBoxStr(item.bbox), content: trim(item.text)}

        case "table":
          bbox = mineruBBoxStr(item.bbox)
          for each caption in item.table_caption:
            if trim(caption) != "":
              append {page: pageStr, type: "table-caption", bbox: bbox, content: trim(caption)}
          for each row in parseMineruHTMLTableRows(item.table_body):
            append {page: pageStr, type: "table-row", bbox: bbox, content: markdownRow(row)}
          for each fn in item.table_footnote:
            if trim(fn) != "":
              append {page: pageStr, type: "table-footnote", bbox: bbox, content: trim(fn)}

        // no default case — unknown types are silently skipped

  return items
```

### 4.3 HTML table parsing (`parseMineruHTMLTableRows`)

Uses `golang.org/x/net/html` tokenizer. Handles both `<td>` and `<th>` cells, and decodes HTML entities automatically (`&lt;` → `<`, `&amp;` → `&`, etc.).

```
parseMineruHTMLTableRows(htmlBody):
  if trim(htmlBody) == "": return nil

  tokenize with html.NewTokenizer:
    StartTag "tr":      currentRow = []
    StartTag "td"/"th": inCell = true; reset cellBuf
    EndTag   "td"/"th": currentRow.append(trim(cellBuf)); inCell = false
    EndTag   "tr":      if currentRow != nil: rows.append(currentRow); currentRow = nil
    Text token:         if inCell: cellBuf.write(text)
    ErrorToken:         break

  return rows
```

If the HTML is empty, malformed, or yields no rows, the function returns `nil` and no `table-row` lines are emitted. No warning is logged; caption and footnote lines are still emitted regardless.

Each row is rendered as a Markdown table row via `markdownRow` (shared with opendata converter): `|cell1|cell2|` with `|` inside cells escaped as `\|`.

### 4.4 Post-processing

`filterRepeatedContentLines` (shared with opendata converter) is applied after extraction:

- Content appearing on ≥ `LINE_FILE_REMOVE_REPEAT_PERCENT`% of pages (default: 85%) is removed.
- Controlled by `LINE_FILE_REMOVE_REPEAT_LINES` env var (default: enabled).

No `filterPageNumberLines` heuristic is needed — `type: "page_number"` items are skipped during extraction.

### 4.5 Line formatting

`formatOpenDataLines` (shared with opendata converter) renders each `extractedOpenDataLine` into a 7-field TAB-separated record:

| Field | Value |
|---|---|
| `line_number` | Incrementing integer from 1 |
| `page_number` | From item |
| `line_type` | Type string; `heading` becomes `heading(N)` when `headingLevel` non-empty |
| `font` | Always `unknown-font` (MinerU provides no font metadata) |
| `font_size` | Always `12` (MinerU provides no font-size metadata) |
| `coordinate` | `mineruBBoxStr` result — original JSON array or `[]` |
| `content` | Text with CRLF/LF/CR → `\n` and TAB → `\t` |

---

## 5. Output File Naming

| | Path |
|---|---|
| Input | `<root>_mineru.json` (or any `.json`) |
| Writable output | `<root>_mineru.txt` |
| Read-only backup | `<root>_mineru.origin` |

```go
func mineruOutputPath(inputPath string) string {
    root := strings.TrimSuffix(inputPath, filepath.Ext(inputPath))
    if strings.HasSuffix(strings.ToLower(root), "_mineru") {
        return root + ".txt"
    }
    return root + "_mineru.txt"
}
```

Mirrors `openDataOutputPath` exactly.

---

## 6. Integration in `service.go`

`ChenWeb/server/api/file-converters/service.go` — `convertOneParserFile` and `findParserJSONs`:

The converter is "smart": when invoked for a record, it scans the record directory for all files matching `<stem>_<parser>.json` and converts each one independently. The parser name is derived from the filename suffix.

```go
func findParserJSONs(dir, stem string) []parserJSONFile {
    // scans dir for files matching <stem>_<parser>.json
    // returns list of {path, parser} pairs
}

func convertOneParserFile(inputPath, parserName string) (string, error) {
    switch parserName {
    case "opendata":
        return ConvertOpenDataFile(inputPath)
    case "mineru":
        return ConvertMineruFile(inputPath)
    // ...
    }
}
```

A single `HandleRequest` call may produce multiple line files (one per discovered parser JSON). One `LineFileGeneratedEvent` is published per successfully converted file. The record directory and stem are derived from `rec.FileName`; `rec.ParserName` is not used for dispatch.

---

## 7. Key Differences from the OpenData Converter

| Aspect | OpenData | MinerU |
|---|---|---|
| JSON tree shape | Nested with recursive `kids` | Flat `pages → items` list |
| Font / size metadata | Available per node | Not available → always `unknown-font` / `12` |
| Heading detection | `type = "heading"` + `heading level` field | `type = "text"` + `*text_level` pointer field |
| List items | Structured child nodes (maps) | Plain strings in `list_items` array |
| List item bbox | Individual node bbox | Shared parent-list bbox |
| Table structure | Structured rows/cells with row/col numbers | HTML string parsed by `x/net/html` tokenizer |
| Table caption | Not present | Emitted as `table-caption` lines before rows |
| Table footnote | Not present | Emitted as `table-footnote` lines after rows |
| Split-table merge | Yes (by ID link or matching header) | Not implemented (no ID links in MinerU) |
| Page-number removal | `filterPageNumberLines` heuristic | Direct skip (`type = "page_number"`) |
| Repeat-line removal | `filterRepeatedContentLines` | Same — shared function |
| Unknown item types | N/A (recursive `walk` handles all known types) | Silently skipped |
| bbox storage | Parsed into `[4]float64`, re-marshaled | `json.RawMessage` passed through as-is |

---

## 8. Edge Cases

1. **Empty `text` or empty list-item strings:** Skipped — no line emitted.
2. **Missing or null `bbox`:** `mineruBBoxStr` returns `"[]"`.
3. **Malformed or empty `table_body`:** `parseMineruHTMLTableRows` returns `nil`; no `table-row` lines emitted. Caption and footnote are unaffected.
4. **`text_level` absent:** Go's JSON decoder sets the `*int` pointer to `nil`; item is treated as `paragraph`.
5. **HTML entities in `table_body`:** Decoded automatically by the `x/net/html` tokenizer.
6. **`<th>` cells:** Treated identically to `<td>` by the HTML tokenizer.
7. **Unknown item types:** Silently skipped. The `switch` has no `default:` case.
8. **Split-table merging:** Not implemented. MinerU lacks `previous_table_id`/`next_table_id` links. Can be added later using the header-matching heuristic from the opendata converter.
9. **`sub_type` on list items:** Ignored. All `list_items` strings are emitted as `list-item` lines regardless of `sub_type`.
10. **`page_idx` field:** Ignored. The parent page's `page_number` (1-indexed) is used exclusively.
