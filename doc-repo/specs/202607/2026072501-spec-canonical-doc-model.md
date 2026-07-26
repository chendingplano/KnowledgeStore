# Preface
SemOS knowledge base is built on a corpus of documents. Documents can be in many forms: Word, PDF, text, markdown,
Typst, LaTeX, JSON, XML, HTML, and so on.

We want to build a Canonical Document Model (CDM) that brings the chaos into order,
mainly by separating the semantic representation of documents from
their presentation. This model unifies and standardizes
how `Documents` are physically stored in SemOS in a standard format, while
supporting various types of rendering.

The benefits of this Canonical Document Model:
- Excellent retrieval and chunking from the semantic source,
- Beautiful PDFs from Typst, HTML with MathJax for web viewing, and plain-text projections for LLM consumption.

The key to CDM is to separate **meaning**,
**retrieval representation**, and **presentation**:

```text
                    ┌─ retrieval projection
                    ├─ plain-text projection -> line file
Canonical document  ├─ HTML renderer
semantic model      ├─ Typst renderer ─┬─ PDF (export)
                    │                  └─ SVG pages + anchor map (viewing)
                    └─ Markdown renderer
```

Typst is the primary `Rendering Language` in CDM, not the source of truth.

It carries a second responsibility beyond publication: because the Typst layout
engine knows exactly where every element lands on every page, an anchored render
tells SemOS **where** a piece of extracted knowledge lives inside a document.
That makes Typst the *location substrate* for authored documents — the role a
parsed PDF plays for uploaded ones — so navigation and highlight work the same
way regardless of where a document came from. See §5.7.

**Normative note.** This document defines CDM schema version `1.0`. Where earlier
drafts showed several candidate shapes for the same construct (equations, table
rows, identifiers), the shape given here is the single authoritative one. Every
JSON and Go example in this document conforms to it.

# 1. Canonical Document Model

Use a block-based document AST. Each block represents what the content **means**, rather than how it should look.

A practical structure for SemOS could be:

```json
{
  "document_key": "doc:jaro-winkler",
  "title": "Jaro-Winkler Similarity",
  "language": "en",
  "schema_version": "1.0",
  "content_version": 7,
  "metadata": {
    "doc_type": "technical-doc",
    "rendering_type": "user-manual",
    "authors": ["Chen Ding"],
    "version": "v1.2",
    "create_time": "2026-07-15T00:00:00Z",
    "modify_time": "2026-07-25T00:00:00Z"
  },
  "blocks": [
    {
      "id": "intro",
      "type": "paragraph",
      "content": [
        {
          "type": "text",
          "text": "Jaro-Winkler similarity is a string similarity algorithm designed for "
        },
        {
          "type": "emphasis",
          "content": [
            {
              "type": "text",
              "text": "short strings"
            }
          ]
        },
        {
          "type": "text",
          "text": ", especially names."
        }
      ]
    },
    {
      "id": "score-range",
      "type": "list",
      "ordered": false,
      "items": [
        [
          {
            "id": "score-range-1",
            "type": "paragraph",
            "content": [
              {
                "type": "strong",
                "content": [
                  {
                    "type": "text",
                    "text": "1.0"
                  }
                ]
              },
              {
                "type": "text",
                "text": " means identical strings."
              }
            ]
          }
        ],
        [
          {
            "id": "score-range-2",
            "type": "paragraph",
            "content": [
              {
                "type": "strong",
                "content": [
                  {
                    "type": "text",
                    "text": "0.0"
                  }
                ]
              },
              {
                "type": "text",
                "text": " means completely different strings."
              }
            ]
          }
        ]
      ]
    },
    {
      "id": "example-table",
      "type": "table",
      "columns": [
        {
          "key": "left",
          "title": "String 1",
          "align": "left"
        },
        {
          "key": "right",
          "title": "String 2",
          "align": "left"
        },
        {
          "key": "score",
          "title": "Similarity",
          "align": "right"
        }
      ],
      "rows": [
        {
          "cells": {
            "left": [{ "type": "text", "text": "John" }],
            "right": [{ "type": "text", "text": "Jon" }],
            "score": [{ "type": "text", "text": "0.93" }]
          }
        },
        {
          "cells": {
            "left": [{ "type": "text", "text": "Michael" }],
            "right": [{ "type": "text", "text": "Micheal" }],
            "score": [{ "type": "text", "text": "0.97" }]
          }
        }
      ]
    },
    {
      "id": "jaro-formula",
      "type": "equation",
      "math": {
        "display": true,
        "parse_status": "success",
        "original": {
          "format": "latex",
          "source": "J = \\frac{1}{3}\\left(\\frac{m}{|s_1|} + \\frac{m}{|s_2|} + \\frac{m-t}{m}\\right)"
        },
        "normalized": {
          "op": "equal",
          "args": [
            { "type": "symbol", "name": "J" },
            {
              "op": "multiply",
              "args": [
                {
                  "op": "divide",
                  "args": [
                    { "type": "number", "value": "1" },
                    { "type": "number", "value": "3" }
                  ]
                },
                {
                  "op": "add",
                  "args": [
                    {
                      "op": "divide",
                      "args": [
                        { "type": "symbol", "name": "m" },
                        {
                          "op": "length",
                          "args": [{ "type": "symbol", "name": "s_1" }]
                        }
                      ]
                    },
                    {
                      "op": "divide",
                      "args": [
                        { "type": "symbol", "name": "m" },
                        {
                          "op": "length",
                          "args": [{ "type": "symbol", "name": "s_2" }]
                        }
                      ]
                    },
                    {
                      "op": "divide",
                      "args": [
                        {
                          "op": "subtract",
                          "args": [
                            { "type": "symbol", "name": "m" },
                            { "type": "symbol", "name": "t" }
                          ]
                        },
                        { "type": "symbol", "name": "m" }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      }
    }
  ]
}
```

Here `m` is the number of matching characters and `t` is the number of
transpositions.

This is more verbose than Markdown, but it provides:

* explicit structure;
* stable block IDs;
* reliable tables;
* semantic equations;
* reusable references;
* precise chunk boundaries;
* deterministic rendering;
* easy transformation into different formats.

A canonical document can be produced by an editor (to be developed),
an LLM response, or a document-processing pipeline.

## 1.1 Identifiers

CDM uses **three** distinct identifier kinds. Confusing them is the most common
implementation error, so they are fixed here.

| Identifier | Type | Scope | Purpose |
|---|---|---|---|
| `documents.id` | `BIGSERIAL` | database | Surrogate primary key, foreign-key target. Never appears in canonical JSON. |
| `document_key` | `text` | global | Stable, human-readable document identity (`doc:jaro-winkler`). Appears in canonical JSON and in export files. |
| `Block.id` | `text` | one document | Stable, human-readable block slug (`intro`, `example-table`). Unique **within** its document. |

Block IDs are **slugs, not UUIDs**. This is deliberate: the "stable block IDs"
benefit above requires that an ID survive re-parsing and editing of the source,
and that a human reading a retrieval result can recognize what it points at.
Consequently, every column that stores a block reference is `text` (or `text[]`),
never `uuid[]`.

## 1.2 Content model invariants

A validator MUST enforce the following. These are the rules the renderers and
projections rely on.

1. `schema_version` is present and recognized.
2. Every block has a non-empty `id`, unique within the document.
3. Every block `type` is a member of §2 or §3.
4. **Content vs. children.** A block carries inline payload in `content`, or
   nested blocks in `children`, or list items in `items` — never more than one
   of the three. `paragraph`, `heading`, and `quote` use `content`; `callout`,
   `definition`, `example`, and other semantic containers use `children`; `list`
   uses `items`.
5. Every `table` row's `cells` keys are a subset of the declared `columns[].key`.
   A missing key renders as an empty cell.
6. Every `equation` has `parse_status`, and at least one of `normalized` or
   `original`.
7. Every `cross_reference` target resolves to an existing block (§7).
8. No block or inline node carries presentation properties (§12).

# 2. Block Types

For an initial implementation, support a limited set:

```text
paragraph
heading
list
table
equation
code
quote
image
callout
```

Inline content can initially support:

```text
text
strong
emphasis
code
link
math
citation
cross_reference
```

Do not try to model every possible document feature at first.

**Resolved omissions.** Three types listed in earlier drafts are deliberately
**not** in v1.0:

- `document` — the document is the root object, not a block.
- `section` — sections are **not** container blocks. Headings are flat blocks
  carrying a `level`, and `section_path` is *derived* during projection (§8) by
  tracking the heading stack. This keeps the AST shallow and makes incremental
  block edits cheap.
- `figure` — folded into `image`, which carries `caption` and `alt`. A separate
  numbered, referenceable `figure` container is deferred to a later schema
  version, together with automatic numbering.

`definition`, `example`, and `reference` are semantic blocks and are specified in
§3, not here.

# 3. Semantic Blocks
Add semantic blocks that ordinary document formats do not have:

```text
claim
definition
provision
metric
procedure
example
counterexample
assumption
evidence
reference
```

Each of these is a **container**: its body lives in `children`.

**`warning` is not a block type.** Warnings, notes, cautions, and tips are all
the same structure and differ only in severity, so they are modeled as a
`callout` block carrying a `role`:

```json
{
  "id": "limitation-1",
  "type": "callout",
  "role": "warning",
  "title": "Limitation",
  "children": [
    {
      "id": "limitation-1-body",
      "type": "paragraph",
      "content": [{ "type": "text", "text": "Scores are not comparable across locales." }]
    }
  ]
}
```

The rule that decides between a `type` and a `role`: if two constructs would
project differently for retrieval, they are different **types**; if they differ
only in how prominently they are displayed, they are one type with different
**roles**. `role` is therefore restricted to the callout severity vocabulary
(`note`, `tip`, `important`, `warning`, `caution`).

A `definition` looks like this:

```json
{
  "id": "definition-jw",
  "type": "definition",
  "term": "Jaro-Winkler similarity",
  "children": [
    {
      "id": "definition-jw-body",
      "type": "paragraph",
      "content": [
        {
          "type": "text",
          "text": "A character-based similarity measure for short strings."
        }
      ]
    }
  ]
}
```

A Typst renderer might display this as a styled definition box. A retrieval projection might emit:

```text
Definition: Jaro-Winkler similarity
A character-based similarity measure for short strings.
```

The semantic block remains the same.

# 4. Separate Semantic Structure from Style

Avoid storing Typst-specific properties such as:

```json
{
  "font_size": "14pt",
  "fill": "#e8f0ff",
  "stroke": "1pt"
}
```

Instead, store semantic roles:

```json
{
  "type": "callout",
  "role": "warning",
  "title": "Limitation"
}
```

The Typst theme decides how a warning looks:

```typst
#let callout(role, title, body) = block(
  inset: 12pt,
  radius: 4pt,
  stroke: if role == "warning" { 0.8pt + red } else { 0.8pt },
  [
    *#title*

    #body
  ],
)
```

## 4.1 Document Metadata

Document-level metadata lives under `metadata` in the canonical JSON:

```json
{
  "doc_type": "technical-doc",
  "rendering_type": "user-manual",
  "authors": ["name1", "name2"],
  "version": "v1.2",
  "create_time": "2026-07-15T00:00:00Z",
  "modify_time": "2026-07-25T00:00:00Z"
}
```

Two fields drive behavior and must be spelled consistently everywhere —
including §5.4 and the storage model:

- `doc_type` — what kind of document this is, used by retrieval and policy.
- `rendering_type` — which Typst template family to render with (§5.4).
  This field is named `rendering_type`, never `render_type`.

Timestamps are RFC 3339 / ISO 8601 UTC. `authors` is an array of strings.

This keeps content independent from presentation.

# 5. Rendering

CDM supports four renderers, matching the projection targets in §9 and the
pipeline in §10:

| Renderer | Output | Purpose |
|---|---|---|
| Typst | `.typ` → PDF | Primary publication format |
| Typst → SVG | paginated `.svg` pages | **Viewing substrate** — the anchored render used for navigation and highlight (§5.7) |
| HTML | HTML fragment | Browser viewing of fragments, MathML/MathJax |
| Markdown | `.md` | LLM context, interchange |
| Plain text | `.txt` | Retrieval projections (§8), line file (§10.1) |

All renderers are **deterministic**: the same canonical document and renderer
version always produce byte-identical output, which is what makes the cached
artifacts in §11 safe.

## 5.1 HTML Renderer
An HTML renderer may generate:

```html
<aside class="callout callout--warning">
  ...
</aside>
```

## 5.2 Typst Renderer
Typst is the main renderer for documents.

A renderer walks through the canonical blocks and emits Typst source.

For example:

```text
semantic paragraph          → Typst paragraph
semantic table              → #table(...)
semantic equation           → $ ... $
semantic image              → #image(...)
semantic callout[warning]   → #callout("warning", ...)
```

A simplified Go interface could be:

```go
type Renderer interface {
	RenderDocument(doc *Document) ([]byte, error)
}

type TypstRenderer struct {
	Theme string
}

type HTMLRenderer struct {
	Theme string
}

type MarkdownRenderer struct{}

type PlainTextRenderer struct{}
```

The canonical types:

```go
type Document struct {
	Key            string   `json:"document_key"`
	Title          string   `json:"title"`
	Language       string   `json:"language"`
	SchemaVersion  string   `json:"schema_version"`
	ContentVersion int64    `json:"content_version"`
	Metadata       Metadata `json:"metadata"`
	Blocks         []Block  `json:"blocks"`
}

type Metadata struct {
	DocType       string    `json:"doc_type,omitempty"`
	RenderingType string    `json:"rendering_type,omitempty"`
	Authors       []string  `json:"authors,omitempty"`
	Version       string    `json:"version,omitempty"`
	CreateTime    time.Time `json:"create_time,omitempty"`
	ModifyTime    time.Time `json:"modify_time,omitempty"`
}

// Block is the single struct for every block type. Which fields are
// populated is determined by Type; see the invariants in §1.2.
type Block struct {
	ID   string `json:"id"`
	Type string `json:"type"`

	// callout severity only; see §3.
	Role string `json:"role,omitempty"`

	// heading
	Level int `json:"level,omitempty"`

	// callout / definition
	Title string `json:"title,omitempty"`
	Term  string `json:"term,omitempty"`

	// code (Text holds the verbatim source; Lang is the highlight language)
	Text string `json:"text,omitempty"`
	Lang string `json:"lang,omitempty"`

	// list
	Ordered bool      `json:"ordered,omitempty"`
	Items   [][]Block `json:"items,omitempty"`

	// inline payload (paragraph, heading, quote)
	Content []Inline `json:"content,omitempty"`

	// nested blocks (callout, definition, and other semantic containers)
	Children []Block `json:"children,omitempty"`

	// table
	Columns []TableColumn `json:"columns,omitempty"`
	Rows    []TableRow    `json:"rows,omitempty"`

	// equation
	Math *Equation `json:"math,omitempty"`

	// image
	Src     string   `json:"src,omitempty"`
	Alt     string   `json:"alt,omitempty"`
	Caption []Inline `json:"caption,omitempty"`
}

type Inline struct {
	Type    string   `json:"type"`
	Text    string   `json:"text,omitempty"`
	Content []Inline `json:"content,omitempty"`

	// link
	URL string `json:"url,omitempty"`

	// math
	Math *Equation `json:"math,omitempty"`

	// cross_reference
	Target *RefTarget `json:"target,omitempty"`

	// citation
	CitationKey string `json:"citation_key,omitempty"`
	Locator     string `json:"locator,omitempty"`
}

type TableColumn struct {
	Key   string `json:"key"`
	Title string `json:"title"`
	Align string `json:"align,omitempty"` // left | center | right; default left
}

// TableRow keys cells by TableColumn.Key. A missing key is an empty cell.
type TableRow struct {
	Cells map[string][]Inline `json:"cells"`
}

type Equation struct {
	Display     bool        `json:"display"`
	Original    *MathSource `json:"original,omitempty"`
	Normalized  *MathExpr   `json:"normalized,omitempty"`
	ParseStatus string      `json:"parse_status"` // success | failed | skipped
}

type MathSource struct {
	Format string `json:"format"` // latex | typst | asciimath
	Source string `json:"source"`
}

// MathExpr is either an operator node (Op + Args) or a leaf (Type + Name/Value).
type MathExpr struct {
	Op   string     `json:"op,omitempty"`
	Args []MathExpr `json:"args,omitempty"`

	Type  string `json:"type,omitempty"`  // symbol | number
	Name  string `json:"name,omitempty"`  // symbol
	Value string `json:"value,omitempty"` // number, as an exact decimal string
}

// RefTarget addresses a block. An empty DocumentKey means "this document".
type RefTarget struct {
	DocumentKey string `json:"document_key,omitempty"`
	BlockID     string `json:"block_id"`
}
```

Numeric literals are carried as **strings** (`"value": "3"`) so that exact
decimal text round-trips without binary floating-point loss. Rational constants
such as one third are represented as a `divide` node, not as a `"1/3"` literal.

A minimal Typst renderer:

```go
package rendering

import (
	"fmt"
	"strings"
)

func (r *TypstRenderer) RenderDocument(doc *Document) ([]byte, error) {
	var out strings.Builder

	out.WriteString("#import \"theme.typ\": *\n\n")
	out.WriteString(fmt.Sprintf("= %s\n\n", escapeTypst(doc.Title)))

	body, err := r.renderBlocks(doc.Blocks)
	if err != nil {
		return nil, err
	}

	out.WriteString(body)
	out.WriteString("\n")

	return []byte(out.String()), nil
}

func (r *TypstRenderer) renderBlocks(blocks []Block) (string, error) {
	var out strings.Builder

	for _, block := range blocks {
		rendered, err := r.renderBlock(block)
		if err != nil {
			return "", fmt.Errorf(
				"render block %q: %w",
				block.ID,
				err,
			)
		}

		out.WriteString(rendered)
		out.WriteString("\n\n")
	}

	return strings.TrimRight(out.String(), "\n"), nil
}

func (r *TypstRenderer) renderBlock(block Block) (string, error) {
	switch block.Type {
	case "heading":
		return strings.Repeat("=", block.Level) +
			" " +
			renderInlines(block.Content), nil

	case "paragraph":
		return renderInlines(block.Content), nil

	case "quote":
		return "#quote(block: true)[" +
			renderInlines(block.Content) +
			"]", nil

	case "code":
		return fmt.Sprintf(
			"#raw(block: true, lang: %q, %q)",
			block.Lang,
			block.Text,
		), nil

	case "equation":
		if block.Math == nil {
			return "", fmt.Errorf("equation has no math")
		}

		expr, err := r.renderMath(block.Math)
		if err != nil {
			return "", err
		}

		if block.Math.Display {
			return "$ " + expr + " $", nil
		}

		return "$" + expr + "$", nil

	case "list":
		return r.renderList(block)

	case "table":
		return r.renderTable(block)

	case "image":
		return fmt.Sprintf(
			"#figure(image(%q), caption: [%s])",
			block.Src,
			renderInlines(block.Caption),
		), nil

	case "callout":
		body, err := r.renderBlocks(block.Children)
		if err != nil {
			return "", err
		}

		role := block.Role
		if role == "" {
			role = "note"
		}

		return fmt.Sprintf(
			"#callout(%q, [%s], [%s])",
			role,
			escapeTypst(block.Title),
			body,
		), nil

	case "definition":
		body, err := r.renderBlocks(block.Children)
		if err != nil {
			return "", err
		}

		return fmt.Sprintf(
			"#definition(%q, [%s])",
			block.Term,
			body,
		), nil

	default:
		return "", fmt.Errorf(
			"unsupported block type %q",
			block.Type,
		)
	}
}

// renderMath implements the §6.4 fallback rule: prefer the normalized AST,
// fall back to the original source.
func (r *TypstRenderer) renderMath(eq *Equation) (string, error) {
	if eq.Normalized != nil {
		return renderTypstMath(eq.Normalized)
	}

	if eq.Original == nil {
		return "", fmt.Errorf("equation has neither normalized AST nor original source")
	}

	switch eq.Original.Format {
	case "typst":
		return eq.Original.Source, nil

	case "latex":
		return convertLatexToTypst(eq.Original.Source)

	default:
		return "", fmt.Errorf(
			"unsupported math source format %q",
			eq.Original.Format,
		)
	}
}
```

List and table rendering:

```go
func (r *TypstRenderer) renderList(block Block) (string, error) {
	marker := "-"
	if block.Ordered {
		marker = "+"
	}

	var out strings.Builder

	for _, item := range block.Items {
		body, err := r.renderBlocks(item)
		if err != nil {
			return "", err
		}

		out.WriteString(marker + " " + indentContinuation(body) + "\n")
	}

	return strings.TrimRight(out.String(), "\n"), nil
}

func (r *TypstRenderer) renderTable(block Block) (string, error) {
	var out strings.Builder

	aligns := make([]string, 0, len(block.Columns))
	for _, col := range block.Columns {
		align := col.Align
		if align == "" {
			align = "left"
		}

		aligns = append(aligns, align)
	}

	out.WriteString("#table(\n")
	out.WriteString(fmt.Sprintf("  columns: %d,\n", len(block.Columns)))
	out.WriteString(fmt.Sprintf("  align: (%s),\n", strings.Join(aligns, ", ")))
	out.WriteString("  table.header(\n")

	for _, col := range block.Columns {
		out.WriteString(
			fmt.Sprintf("    [*%s*],\n", escapeTypst(col.Title)),
		)
	}

	out.WriteString("  ),\n")

	for _, row := range block.Rows {
		for _, col := range block.Columns {
			out.WriteString(
				fmt.Sprintf("  [%s],\n", renderInlines(row.Cells[col.Key])),
			)
		}
	}

	out.WriteString(")")

	return out.String(), nil
}
```

Inline rendering:

```go
func renderInline(node Inline) string {
	switch node.Type {
	case "text":
		return escapeTypst(node.Text)

	case "strong":
		return "*" + renderInlines(node.Content) + "*"

	case "emphasis":
		return "_" + renderInlines(node.Content) + "_"

	case "code":
		return fmt.Sprintf("#raw(%q)", node.Text)

	case "link":
		return fmt.Sprintf(
			"#link(%q)[%s]",
			node.URL,
			renderInlines(node.Content),
		)

	case "math":
		if node.Math == nil {
			return ""
		}

		expr, err := renderTypstMath(node.Math.Normalized)
		if err != nil {
			return ""
		}

		return "$" + expr + "$"

	case "cross_reference":
		if node.Target == nil {
			return ""
		}

		return fmt.Sprintf("#ref(label(%q))", node.Target.BlockID)

	case "citation":
		return fmt.Sprintf("#cite(label(%q))", node.CitationKey)

	default:
		// Unknown inline types are rejected by validation (§1.2) and
		// dropped here rather than corrupting the output.
		return ""
	}
}

func renderInlines(nodes []Inline) string {
	var out strings.Builder

	for _, node := range nodes {
		out.WriteString(renderInline(node))
	}

	return out.String()
}
```

Helpers used above, declared elsewhere in the package:

```go
// indentContinuation indents every line after the first by two spaces, so that
// multi-block list items stay inside their list item in Typst.
func indentContinuation(s string) string

// renderTypstMath walks a normalized math AST and emits Typst math syntax.
func renderTypstMath(expr *MathExpr) (string, error)

// convertLatexToTypst is the best-effort fallback used when no normalized AST
// is available. See §6.4.
func convertLatexToTypst(src string) (string, error)

var typstEscaper = strings.NewReplacer(
	`\`, `\\`,
	"#", `\#`,
	"$", `\$`,
	"*", `\*`,
	"_", `\_`,
	"`", "\\`",
	"@", `\@`,
	"<", `\<`,
	">", `\>`,
	"[", `\[`,
	"]", `\]`,
)

func escapeTypst(s string) string {
	return typstEscaper.Replace(s)
}
```

This generates Typst such as:

```typst
#import "theme.typ": *

= Jaro-Winkler Similarity

Jaro-Winkler similarity is designed for _short strings_.

#table(
  columns: 3,
  align: (left, left, right),
  table.header(
    [*String 1*],
    [*String 2*],
    [*Similarity*],
  ),
  [John],
  [Jon],
  [0.93],
  [Michael],
  [Micheal],
  [0.97],
)
```

## 5.3 Typst Templates
Different business needs or customers may require documents to be rendered
differently. When creating a document, users may specify the Typst
template to use. If no Typst template is specified, a fallback Typst
template is used. The fallback Typst template can be specified at
the following levels:
- System wide
- Tenant wide
- User wide

The **most specific** level wins: a user-level fallback overrides a tenant-level
fallback, which overrides the system-level fallback. An explicit
per-document template overrides all three.

## 5.4 Typst Template Association with `rendering_type`
Users can create associations between the `rendering_type` (§4.1) and Typst
templates. Resolution order for a given document:

1. Explicit template named on the document.
2. Template associated with the document's `rendering_type`, at the most
   specific level available (user → tenant → system).
3. The fallback template, at the most specific level available.

## 5.5 Templates Carry Formatting Requirements

Templates are not a convenience feature. They are how CDM answers a hard
real-world requirement: **mandatory document formatting standards.**

Many organizations require documents to be formatted in a prescribed way, and
some are regulated at extreme granularity — China's mandatory standard governing
how a national standard must be formatted specifies fonts, sizes, spacing,
numbering, and section structure in exacting detail.

The obvious way to meet such a requirement is to build an online rich-text
editor that enforces the formatting directly, as a Word or Google Docs
equivalent. That approach has been tried and its failure mode is known: the
formatting rules become entangled with the editor itself, the tool grows
extremely difficult to maintain, and — most damagingly — it is welded to *one*
standard. Adapting it to another customer's rules is impractical, because the
rules were never a separable artifact.

CDM's split is the direct answer. The document stores what it *means*; the Typst
template carries what it must *look like*. A second formatting standard is a
second template, not a second editor. The rules become data — versioned,
reviewable, and swappable per customer, tenant, or document type through the
resolution order in §5.4.

This is the load-bearing reason §12 forbids presentation properties in the
canonical schema. Font, size, color, alignment, and spacing belong to the
template, so an editing surface should expose *semantic* actions — heading,
emphasis, list, table, callout, definition — and let the template decide how each
one looks. Every presentation property admitted into a document is one the
template can no longer control, and it is exactly that leakage that made the
earlier tool unmaintainable.

Full support for a specific mandatory standard is deferred until the CDM and
CDM Editor designs are mature (§16). The requirement is recorded here because it
constrains the architecture now: it is why formatting must stay in templates.

## 5.6 Markdown and Plain-Text Renderers
The Markdown renderer emits CommonMark plus fenced code and LaTeX math; it is
the basis for the LLM context projection (§9.3). The plain-text renderer emits
no markup at all and is the basis for the retrieval projections (§8, §9.1,
§9.2). Both walk the same block tree with the same `renderBlock` dispatch shape.

## 5.7 Anchored Rendering: Typst as the Location Substrate

Typst is not only how a CDM document is published. It is how SemOS knows
**where** a piece of extracted knowledge lives inside a document.

Applications built on the knowledge base must jump to the place an artifact was
extracted from and highlight it. For uploaded documents that works because the
PDF parser emits a bounding box per element alongside the line file, and the
viewer paints highlight overlays at those boxes. The viewer's contract is
narrow:

> **`line span → {page, x, y, w, h}`, plus paginated pages to draw on.**

A CDM document satisfies that contract without ever producing a PDF. Rendering
emits two artifacts together:

1. **Paginated SVG pages** — `typst compile --format svg`, one file per page,
   each carrying its page box.
2. **An anchor map** — for every line-file unit (§10.1), its exact location as
   `{page, x, y, w, h}` in points.

The anchor map is obtained by wrapping each unit in a marker that records
`here().position()` into a `state`, terminating the document with a queryable
`metadata` label, and reading it back with
`typst query <label> --field value`. The SVG `viewBox` is the page box in the
same coordinate space as those positions, so a highlight rectangle placed at an
anchor's coordinates lands exactly on its content.

**Why this is stronger than the PDF path.** The coordinates come from the layout
engine as ground truth rather than being reverse-engineered from a rendered
page; and because the line file and the anchor map are generated from the same
AST in the same pass, the line-span↔location mapping is exact *by construction*
rather than inferred and later repaired.

**Two constraints that follow.**

*Do not use Typst HTML export as the viewing target.* It is documented as
incomplete and not production-ready, and — decisively — it discards pagination
(`page set rule was ignored during HTML export`). Without pages there are no
page coordinates and the contract above collapses. Its cost is that SVG emits
text as glyph references rather than selectable text, so text selection and
in-document search must be served from the line file and anchor map, as they
already are for uploaded documents.

*Anchor units with paired start and end marks, not a position plus a measured
height.* `measure()` reports a unit's height in isolation, which is wrong
whenever the unit breaks across a page — a unit can measure taller than the page
body it flows through, so a single record would run a highlight off one page and
paint nothing on the next. Paired marks report the true start and end pages, from
which one highlight fragment per occupied page is derived.

Because the anchor map depends on layout, it is only valid for the
`content_version` and `renderer_version` that produced it. A Typst upgrade or a
theme change invalidates it, so both are recorded alongside it (§11).

# 6. Formula Representation

Formulas are the hardest part because Markdown/LaTeX math and Typst math are not identical.

There are three possible approaches.

## 6.1 Option A: Store Separate Source Variants

```json
{
  "type": "equation",
  "representations": {
    "latex": "JW = J + lp(1-J)",
    "typst": "JW = J + l p (1 - J)"
  }
}
```

This is easy, but duplicates content: the variants drift, and nothing says which
one is authoritative when they disagree.

## 6.2 Option B: Use LaTeX as the Canonical Source

```json
{
  "type": "equation",
  "format": "latex",
  "source": "JW = J + lp(1-J)"
}
```

Then convert LaTeX into Typst.

This is practical if formulas originate in academic documents, but conversion will occasionally be imperfect.

## 6.3 Option C: Use a Semantic Math AST

```json
{
  "op": "equal",
  "args": [
    { "type": "symbol", "name": "JW" },
    {
      "op": "add",
      "args": [
        { "type": "symbol", "name": "J" },
        {
          "op": "multiply",
          "args": [
            { "type": "symbol", "name": "l" },
            { "type": "symbol", "name": "p" },
            {
              "op": "subtract",
              "args": [
                { "type": "number", "value": "1" },
                { "type": "symbol", "name": "J" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

The Typst renderer emits:

```typst
$ JW = J + l p (1 - J) $
```

The LaTeX renderer emits:

```latex
\[
JW = J + lp(1-J)
\]
```

The HTML renderer emits MathML or MathJax-compatible LaTeX.

## 6.4 Decision: Option C with Option B as Fallback

CDM v1.0 adopts the following, and it is the **only** equation shape in this
specification:

* Store the original formula source in `original`.
* Store a normalized semantic math AST in `normalized` when parsing succeeds.
* Record the outcome in `parse_status` (`success`, `failed`, or `skipped`).
* Render from `normalized` when it is present.
* Fall back to converting `original` otherwise.

```json
{
  "id": "jw-formula",
  "type": "equation",
  "math": {
    "display": true,
    "parse_status": "success",
    "original": {
      "format": "latex",
      "source": "JW = J + lp(1-J)"
    },
    "normalized": {
      "op": "equal",
      "args": []
    }
  }
}
```

`normalized` holds the expression tree **directly** — there is no wrapping
`{ "format": ..., "expression": ... }` envelope, because the format is always
the CDM semantic math AST.

Supported operator vocabulary for v1.0:

```text
equal  add  subtract  multiply  divide  power  root
abs  length  sum  product  min  max  function
```

`length` (not `abs`) denotes the length or cardinality of a string, sequence, or
set — `|s|` in conventional notation. `abs` is reserved for numeric absolute
value. Conflating the two produces incorrect verbalization in retrieval
projections.

# 7. References, Citations, and Cross-References

The "reusable references" benefit in §1 requires an explicit reference model.
CDM has three distinct constructs.

**`cross_reference`** (inline) points at another block, in this or another
document:

```json
{
  "type": "cross_reference",
  "target": { "document_key": "doc:jaro-winkler", "block_id": "jaro-formula" },
  "content": [{ "type": "text", "text": "the Jaro formula" }]
}
```

An empty or absent `document_key` means the current document. `content` is
optional display text; when absent, renderers generate a label (Typst `#ref`,
HTML anchor text, or the target's `term`/`title`).

**`citation`** (inline) points at a bibliography entry by key:

```json
{
  "type": "citation",
  "citation_key": "winkler1990",
  "locator": "p. 354"
}
```

**`reference`** (block, §3) is a bibliography entry. Its `id` is the citation
key that `citation.citation_key` resolves against:

```json
{
  "id": "winkler1990",
  "type": "reference",
  "children": [
    {
      "id": "winkler1990-text",
      "type": "paragraph",
      "content": [
        {
          "type": "text",
          "text": "Winkler, W. E. (1990). String Comparator Metrics and Enhanced Decision Rules."
        }
      ]
    }
  ]
}
```

The pipeline's **reference resolution** step (§10) verifies that every
`cross_reference` target and every `citation_key` resolves, and records
unresolved references as validation errors rather than silently dropping them.
Cross-document references are resolved against `document_key`, which is why that
key must be stable (§1.1).

# 8. Retrieval Projection

The retrieval representation should not simply be the Typst source.

Typst contains presentation noise:

```typst
#table(
  columns: 3,
  align: ...
)
```

That is not useful to semantic retrieval.

Instead, generate a projection like:

```text
Title: Jaro-Winkler Similarity

Jaro-Winkler similarity is designed for short strings, especially names.

Score range:
- 1.0 means identical strings.
- 0.0 means completely different strings.

Examples:
- John compared with Jon has similarity approximately 0.93.
- Michael compared with Micheal has similarity approximately 0.97.

Jaro formula:
J equals one-third times the sum of:
- matching characters divided by the length of the first string;
- matching characters divided by the length of the second string;
- matching characters minus transpositions, divided by matching characters.
```

Notice that the table has become sentence-like text. This is better for:

* embedding;
* BM25;
* LLM context;
* chunk summaries;
* question answering.

`section_path` is computed here, not stored on blocks: the projector walks the
block list maintaining a stack of open `heading` blocks by `level`, and each
emitted chunk records the heading titles above it.

The projection interface might be:

```go
type Projection interface {
	ProjectDocument(doc *Document) ([]ProjectedChunk, error)
}

type ProjectedChunk struct {
	ChunkID      string
	DocumentKey  string
	SectionPath  []string
	Text         string
	BlockIDs     []string
	SemanticType string
	Metadata     map[string]any
}
```

Example output:

```json
{
  "chunk_id": "doc:jaro-winkler:examples",
  "document_key": "doc:jaro-winkler",
  "section_path": [
    "Jaro-Winkler Similarity",
    "Examples"
  ],
  "block_ids": [
    "example-table"
  ],
  "semantic_type": "example",
  "text": "John and Jon have Jaro-Winkler similarity approximately 0.93. Michael and Micheal have similarity approximately 0.97."
}
```

This gives you traceability from retrieval results back to the source blocks.

# 9. Keep Multiple Projections

One canonical document can produce several projections:

```text
canonical.json
├── retrieval-dense.txt
├── retrieval-bm25.txt
├── llm-context.md
├── display.typ
├── display.html
└── export.pdf
```

The projections can serve different purposes.

## 9.1 BM25 Projection

Preserve exact terminology and aliases:

```text
Jaro-Winkler
Jaro Winkler
string similarity
record linkage
entity resolution
name matching
transposition
common prefix
```

## 9.2 Embedding Projection

Use natural, explanatory text:

```text
Jaro-Winkler is a character-based similarity measure for comparing short
strings and names while tolerating typographical errors and transpositions.
```

## 9.3 LLM Context Projection

Preserve structure, equations, examples, and provenance:

```markdown
## Jaro formula

Formula:

`J = 1/3 * (m/|s_1| + m/|s_2| + (m-t)/m)`

Variables:

- `m`: matching characters
- `t`: transpositions
- `s_1`, `s_2`: the two strings being compared
```

Variable names in projections must match the symbols in the equation AST
(§1); a projection that renames `t` to `tau` breaks the link between the
formula and its explanation.

## 9.4 Display Projection

Render to Typst or HTML.

# 10. Recommended SemOS Pipeline

SemOS has **two document origins** and **one processing pipeline**. A document
either arrives from outside as a file, or is authored inside SemOS with the CDM
Editor. The two paths differ only in how they reach a line file; from there they
are identical.

```text
  UPLOADED                                AUTHORED (CDM)
  file (PDF/Word/…)                       CDM Editor
      │                                       │
      ▼                                       ▼
  PDF parser                          Canonical semantic document
      │                                       │
      │                                 ├── validation
      │                                 ├── normalization
      │                                 ├── enrichment
      │                                 ├── reference resolution
      │                                 └── semantic annotations
      │                                       │
      │                                       ▼
      │                              Typst anchored rendering (§5.7)
      │                                       │
      ▼                                       ▼
  line file + bboxes                  line file + anchor map
      │                                       │
      └───────────────────┬───────────────────┘
                          ▼
              DOC-PROCESS PIPELINE  (identical for both)
                          │
          ├── extraction (metrics, provisions, entities, …)
          ├── artifacts + source_line_spans provenance
          ├── chunking + embedding
          └── search, review, knowledge applications
```

The canonical document additionally derives its own projections and renderings:

```text
Canonical semantic document
    ├── BM25 projection
    ├── embedding projection
    ├── LLM context projection
    ├── Typst rendering  → PDF (export) / SVG pages (viewing)
    ├── HTML rendering
    └── Markdown rendering
```

## 10.1 Document Lifecycle and Line-File Generation

An authored document moves through:

```text
editing → published → rendered → line_file_generated → doc-process pipeline
```

- **editing** — a draft. Its `kb.inputs` row exists from creation (so that
  author-triggered processing, §10.5, has somewhere to attach artifacts), but
  the row is written so that **both** derived states are terminal:
  `parse_state = 'parsed_success'` and `pipeline_state = 'success'`. A draft is
  therefore invisible to both worklists, and anything that runs against it runs
  because the author explicitly asked, never because a poller picked it up.
- **published** — the document's `doc_processing` status entry is cleared, so
  `pipeline_state` derives back to `'pending'` and the standard doc-processing
  worklist enqueues it for the authoritative full run. Publishing is thus a
  *status transition on an existing row*, not a row creation.
- **rendered** — anchored rendering (§5.7) produces the SVG pages and the anchor
  map.
- **line_file_generated** — the line file is emitted from the same AST in the
  same pass as the anchor map, one line per **anchorable unit**: a paragraph, a
  list item, a table row, a heading, an equation, or a code block. Choosing the
  line granularity to match the anchor granularity makes `line span → location`
  a 1:1 lookup rather than a range computation.
- **doc-process pipeline** — the document is handed to the standard pipeline and
  is processed on the same terms as an uploaded one. Extractors consume the line
  file and emit `source_line_spans`; they need no CDM-specific handling.

A CDM document is therefore **born parsed**: the CDM AST *is* the parse result,
so there is no file to parse, but everything downstream of parsing still applies.
PDF generation remains available for export and download, and is not on the
critical path for viewing, navigation, or highlight.

Because a draft may already have been processed on demand (§10.5), the run
triggered at publish can encounter artifacts from earlier draft runs. Artifacts
are therefore keyed to the `content_version` they were derived from, and a run
supersedes artifacts from an older version of the same document rather than
appending to them.

The canonical document should be versioned:

```json
{
  "schema_version": "1.0",
  "content_version": 7,
  "renderer_version": {
    "typst": "3.2",
    "retrieval": "2.1"
  }
}
```

`schema_version` describes the shape of the AST, `content_version` increments
when the document's content changes, and `renderer_version` records which
renderer produced a cached artifact. This lets projections be regenerated when a
renderer improves without modifying the source document.

## 10.2 Chunking: Semantic Declaration, Physical Resolution

Chunking is an **artifact**, produced after the line file exists. Its physical
form is a list of line ranges with overlaps:

```text
overlap: []
lines: [1-23]

overlap: [21-23]
lines: [24-42]

overlap: [39-42]
lines: [43-66]
```

Because the line file is logically the same for both document origins (§10.1),
this artifact and everything that consumes it are unchanged for CDM documents.

What CDM adds is the ability for an **author** to declare chunk boundaries at
the *semantic* level, which are then resolved to the *physical* level once the
line file is generated:

```text
author declares chunk groups on blocks   (semantic, stored in the AST)
                │
                ▼
        line file generated               (§10.1)
                │
                ▼
   chunk groups resolve to line ranges    (physical, the .chunks artifact)
```

Blocks may carry an optional chunk-group identifier; a maximal run of
consecutive blocks sharing an identifier forms one semantic chunk. Overlap
remains the chunker's concern, not the author's — the author declares *where
meaning divides*, and the pipeline decides how much context to carry across the
seam.

If a document declares no chunk groups, the pipeline chunks it automatically, as
it does for uploaded documents. Author-declared chunking is therefore an
optional refinement, never a prerequisite.

This two-level split mirrors anchored rendering (§5.7): the AST carries intent,
and the physical coordinates are derived once the concrete artifact exists.

## 10.3 Author Annotations Are Artifacts

The CDM Editor lets an author select a span of text and mark it as a semantic
object — a `terminology`, `concept`, `definition`, `entity`, `relation`, or
`canonical object`. These are **artifacts in exactly the same sense** as the ones
a doc processor extracts, stored in the same tables, consumed by the same search
and review tooling. They differ only in how they were produced: far cheaper, and
far more accurate, because a human asserted them.

Since an author annotates a span of text, and spans resolve to line ranges via
the line file, an author-created artifact carries the same `source_line_spans`
provenance as an extracted one — and therefore the same navigate-and-highlight
behavior (§5.7) with no special handling.

**Every artifact records its origin.** Artifact tables carry an origin
discriminator defaulting to `extracted`, with `human-created` for author
assertions. This follows the existing convention on `kb.images.origin`. The flag
matters well beyond bookkeeping: it tells downstream consumers which assertions
carry human authority, lets review tooling skip re-verifying what a human
asserted, and lets extraction avoid overwriting it.

Artifact types that do not exist yet — `terminology`, `concept`, `definition` —
are planned as ordinary doc processors with ordinary tables. CDM adds no new
artifact types of its own.

## 10.4 Document Versions Are Documents

A new version of a document is a **new document**, not a revision record inside
an existing one. It gets its own canonical document and its own `kb.inputs` row,
and it is processed independently.

Versions are linked by a typed relation recorded on the input row (in a
dedicated column or within `kb.inputs.doc_metadata`), naming the document this
version was created from and how it relates to it:

```text
addendum   — adds to the prior version without altering it
amendment  — modifies part of the prior version
replace    — supersedes the prior version entirely
```

This keeps every version independently addressable, independently processed, and
independently citable — which matters because artifacts, `source_line_spans`,
anchors, and renderings are all bound to a specific document. A revision model
that mutated one document in place would invalidate all of them on every edit.

Note the two distinct counters this leaves:

- `content_version` (§1, §11) is the **within-document** edit counter. It
  increments as an author saves changes to *one* document, and keys that
  document's derived renderings, anchors, and projections.
- The **version lineage** above is *between* documents, and is the notion a
  reader means by "version 2 of the standard".

## 10.5 Author-Triggered Extraction and Generated Appendices

An author writing a document may want an appendix of the metrics it contains.
The action is explicit: the author invokes *Generate Appendix of Metrics*, and
the system does, in order:

```text
generate line file  →  chunk  →  run the extract_metrics doc processor
        →  reconcile with the author's own marked metrics
        →  render the appendix
```

This is the same line file, the same chunking, and the same doc processor used
after publication (§10.1). Nothing about extraction is special-cased for the
editor; only the *trigger* differs — an author asked, rather than a worklist
poller.

**Why this does not create a cycle.** The apparent circularity is document →
pipeline → artifacts → document content. It is broken by three properties:

1. The trigger is **manual and bounded**. A run happens because an author asked
   for one; it does not cascade.
2. A draft sits off both worklists (§10.1), so a run cannot enqueue further runs.
3. The appendix is a **render-time projection**, not a stored block.

The third point is the important one. The appendix is *rendered from* the current
artifacts at render time; it is not written back into the AST. So it never
becomes stale content that disagrees with the artifacts, editing the document
never invalidates a stored appendix, and — decisively — nothing the appendix
contains can ever be re-extracted as if it were authored prose. The
*Generate Appendix* action therefore means "run extraction now, so the appendix
has current artifacts to show", not "insert an appendix into my document".

### 10.5.1 Reconciling Human and LLM Assertions

An author who has marked metrics by hand (§10.3) will often *still* want the
extractor to run — precisely because they may have missed some. The two sources
have complementary strengths:

- **Human marking** is high **precision**: what the author marked is right.
- **LLM extraction** is high **recall**: it finds what the author overlooked.

So the two sets are reconciled rather than concatenated. Where both assert the
same metric, they are merged into one, and **the human assertion wins** — its
values, wording, and boundaries are authoritative, and the `origin` stays
`human-created`. Where only the extractor found something, it is added with
`origin = 'extracted'`.

This is the same class of problem the object reconciliation machinery already
solves for entities and inventory items (`kb.reconcile_runs`,
`kb.entity_merge_candidates`, `kb.entity_merges`, `kb.inventory_item_merges`;
ADR 2026070701 for ambiguous ties). Note that no equivalent exists for metrics
yet, so human/LLM reconciliation of metrics needs building, with the entity
machinery as its model.

### 10.5.2 Provenance Is Displayed, Never Erased

While drafting, the author needs to see which assertions are theirs and which
came from the LLM, so the appendix can show provenance per entry. When the
document is published, that annotation should usually disappear — a reader of a
standard does not need to see which metrics an LLM proposed.

**This is a display setting, not a data operation.** The `origin` value on the
artifact (§10.3) is permanent and is never cleared, at publish or at any other
time. Publishing hides provenance in the *rendered appendix*; it does not remove
provenance from the *record*.

The distinction matters because `origin` is what tells downstream consumers
which assertions carry human authority — it lets review tooling skip
re-verifying what a human asserted, and lets a later extraction run avoid
overwriting it. Erasing it at publish would destroy exactly the value the flag
exists to provide, and it is unrecoverable: nothing else in the system records
that a human, rather than a model, made that claim.

So: one permanent `origin` column, and a per-render `show_provenance` option
that defaults on while editing and off once published.

# 11. Storage Model

The PostgreSQL structure below follows the existing `kb` schema conventions:
`BIGSERIAL` surrogate keys, `create_time` / `update_time` timestamps, and
`ON DELETE CASCADE` from child tables. Per workspace policy, these are applied
through `goose` migrations, not ad-hoc DDL.

Tables use the **`kb.cdm_*`** namespace. This is deliberate and load-bearing:
`kb.semantic_projections` already exists in SemOS and means something entirely
different — a search-oriented enrichment of an input (keywords, category paths,
search vectors) produced by the doc-processor. A CDM projection is not a summary
at all; it is a de-formatted textual rendition of the document. A bare
`kb.documents` would likewise sit beside `kb.doc_process_runs`,
`kb.doc_proc_logs`, and the `kb.doc_review_*` family. The subsystem prefix
follows the convention already used by `kb.artifact_*`, `kb.benchmark_*`, and
`kb.inventory_*`, and keeps "projection" usable as the concept word in prose.

```sql
CREATE TABLE IF NOT EXISTS kb.cdm_documents (
    id                BIGSERIAL PRIMARY KEY,
    document_key      VARCHAR(255) NOT NULL UNIQUE,
    title             TEXT NOT NULL,
    language          VARCHAR(32),
    schema_version    VARCHAR(32) NOT NULL,
    content_version   BIGINT NOT NULL DEFAULT 1,
    doc_type          VARCHAR(64),
    rendering_type    VARCHAR(64),
    authors           TEXT[] NOT NULL DEFAULT '{}',
    doc_version       VARCHAR(32),
    semantic_document JSONB NOT NULL,
    create_time       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    update_time       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

`semantic_document` is the authoritative canonical JSON. `doc_type`,
`rendering_type`, and `authors` are promoted out of it into columns because they
are queried and filtered on; they must be kept consistent with the JSON on write.

Blocks can optionally be extracted into a separate table for block-level
queries and provenance:

```sql
CREATE TABLE IF NOT EXISTS kb.cdm_blocks (
    id                BIGSERIAL PRIMARY KEY,
    document_id       BIGINT NOT NULL
                          REFERENCES kb.cdm_documents(id) ON DELETE CASCADE,
    block_id          VARCHAR(255) NOT NULL,
    parent_block_id   VARCHAR(255),
    block_type        VARCHAR(64) NOT NULL,
    block_role        VARCHAR(64),
    ordinal           INTEGER NOT NULL,
    section_path      TEXT[],
    semantic_content  JSONB NOT NULL,
    source_provenance JSONB,
    content_hash      VARCHAR(64) NOT NULL,
    create_time       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    update_time       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_kb_cdm_blocks_block_id
        UNIQUE (document_id, block_id),
    CONSTRAINT uq_kb_cdm_blocks_ordinal
        UNIQUE NULLS NOT DISTINCT (document_id, parent_block_id, ordinal)
);

CREATE INDEX IF NOT EXISTS idx_kb_cdm_blocks_document_id
    ON kb.cdm_blocks(document_id);
```

`block_id` and `parent_block_id` are the **text slugs** from §1.1, not UUIDs.
`UNIQUE NULLS NOT DISTINCT` requires PostgreSQL 15+; it makes the ordinal unique
among top-level blocks (where `parent_block_id` is `NULL`) as well as among
siblings.

Rendered artifacts:

```sql
CREATE TABLE IF NOT EXISTS kb.cdm_renderings (
    id                BIGSERIAL PRIMARY KEY,
    document_id       BIGINT NOT NULL
                          REFERENCES kb.cdm_documents(id) ON DELETE CASCADE,
    content_version   BIGINT NOT NULL,
    renderer          VARCHAR(32) NOT NULL,
    renderer_version  VARCHAR(32) NOT NULL,
    media_type        VARCHAR(128) NOT NULL,
    page              INTEGER NOT NULL DEFAULT 0,
    rendered_content  BYTEA NOT NULL,
    create_time       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_kb_cdm_renderings
        UNIQUE (document_id, content_version, renderer, renderer_version, page)
);
```

`page` was added during Phase 1 implementation: the original key had no room for
a paginated renderer, since anchored rendering (§5.7) produces one SVG file
*per page* under the same `renderer`/`renderer_version`. `page` is `0` for
non-paginated renderers (the Typst source itself, a single PDF export, the
generated line file) and the page number (1-indexed) for each SVG page.

Retrieval projections:

```sql
CREATE TABLE IF NOT EXISTS kb.cdm_projections (
    id                 BIGSERIAL PRIMARY KEY,
    document_id        BIGINT NOT NULL
                           REFERENCES kb.cdm_documents(id) ON DELETE CASCADE,
    content_version    BIGINT NOT NULL,
    chunk_id           VARCHAR(255) NOT NULL,
    block_ids          TEXT[] NOT NULL,
    projection_type    VARCHAR(32) NOT NULL,
    projection_version VARCHAR(32) NOT NULL,
    section_path       TEXT[],
    semantic_type      VARCHAR(64),
    projected_text     TEXT NOT NULL,
    metadata           JSONB,
    embedding          vector(1536),
    create_time        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_kb_cdm_projections
        UNIQUE (document_id, content_version, projection_type,
                projection_version, chunk_id)
);

CREATE INDEX IF NOT EXISTS idx_kb_cdm_projections_document_id
    ON kb.cdm_projections(document_id);
```

`block_ids` is `TEXT[]` because block IDs are slugs (§1.1). The `vector(1536)`
dimension matches the embedding model already used elsewhere in the `kb` schema
and must be changed together with it.

The anchor map (§5.7), one row per highlight fragment:

```sql
CREATE TABLE IF NOT EXISTS kb.cdm_anchors (
    id                BIGSERIAL PRIMARY KEY,
    document_id       BIGINT NOT NULL
                          REFERENCES kb.cdm_documents(id) ON DELETE CASCADE,
    content_version   BIGINT NOT NULL,
    renderer_version  VARCHAR(32) NOT NULL,
    line_number       INTEGER NOT NULL,
    block_id          VARCHAR(255) NOT NULL,
    fragment_ordinal  INTEGER NOT NULL DEFAULT 0,
    page              INTEGER NOT NULL,
    x                 REAL NOT NULL,
    y                 REAL NOT NULL,
    w                 REAL NOT NULL,
    h                 REAL NOT NULL,
    create_time       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_kb_cdm_anchors
        UNIQUE (document_id, content_version, renderer_version,
                line_number, fragment_ordinal)
);

CREATE INDEX IF NOT EXISTS idx_kb_cdm_anchors_lookup
    ON kb.cdm_anchors(document_id, content_version, line_number);
```

`line_number` is the line in the generated line file (§10.1), which is what
artifact `source_line_spans` refer to — so resolving an artifact to a highlight
is an index lookup on this table. `fragment_ordinal` distinguishes the
per-page fragments of a unit that breaks across pages (§5.7); a unit contained
on one page has a single row with ordinal `0`. Coordinates are in points, in the
page coordinate space shared with the rendered SVG.

The anchor map is only valid for the `content_version` and `renderer_version`
that produced it, both of which are part of the key — a stale map is therefore
detectable rather than silently wrong.

# 12. Avoid Making the Canonical Schema Presentation-Oriented

A common mistake is building a universal document format that becomes an imitation of HTML or Typst.

Avoid nodes such as:

```text
horizontal_stack
vertical_stack
font
margin
border
page_break
absolute_position
```

Those belong in renderers and templates.

Your semantic representation should answer questions such as:

* Is this a definition?
* Is this a formula?
* Is this an example?
* Is this a warning?
* What concept does this block describe?
* Which source passage supports it?
* Which other artifact does it reference?

It should not normally answer:

* What color should the box be?
* How wide should the table be?
* Which font should be used?
* Where on the page should it appear?

# 13. A Practical MVP

Implementation can be broken into four phases.

## 13.1 Phase 1: Block AST and Typst Renderer

Support:

```text
heading
paragraph
list
table
code
equation
image
quote
```

For equations, store `original` with `parse_status: "skipped"` and no
`normalized` AST; the renderer takes the §6.4 fallback path. Do **not** store
parallel LaTeX and Typst variants — that is Option A, which §6.4 rejects.

Phase 1 also delivers the publish lifecycle and anchored rendering (§5.7,
§10.1): paginated SVG pages, the anchor map, and line-file generation. These
belong in Phase 1 rather than later because they are what lets an authored
document enter the existing doc-process pipeline at all — without a line file
there is nothing for the extractors to consume, and without the anchor map the
knowledge applications cannot point back at the source.

## 13.2 Phase 2: Retrieval Projection

Generate chunked text from the same blocks.

Tables should be verbalized. Equations should include variable descriptions. Images should use captions and descriptions.

## 13.3 Phase 3: Semantic SemOS Blocks

Add:

```text
definition
claim
metric
provision
procedure
example
evidence
callout (with role)
reference
```

## 13.4 Phase 4: Normalized Formula and Diagram Models

Add semantic math ASTs (`parse_status: "success"`) and structured diagram
definitions only when the value justifies the complexity.

# 14. CDM Editor
This is a browser-based editor. Users use the CDM Editor to create and edit
documents. It is specified separately in
`2026072502-spec-cdm-editor`, whose Design Decisions section records how its
requirements were reconciled with this model — formatting via templates (§5.5),
author annotations as artifacts (§10.3), versions as documents (§10.4), and
author-declared chunking (§10.2). ADR `2026072602` records the same decisions
with their alternatives.

# 15. Summary

The architecture:

```text
JSON semantic AST as canonical representation
        +
block-level provenance and stable IDs
        +
projection-specific text generation
        +
deterministic Typst/HTML renderers
```

The most important design rule is:

> Store what the content means once; derive how it is searched, read, and published.

# 16. Open Questions

Deliberately deferred beyond CDM v1.0:

1. **Numbered, referenceable figures and tables** — requires a numbering
   authority and a `figure` container (§2). **Now known to be required** by the
   CDM Editor's auto-generated content (list of figures, list of tables, list of
   formulas, index), so this is a scheduled need rather than a hypothetical one.
   The artifact appendices in that feature should be render-time projections
   rather than stored blocks, to avoid a document → pipeline → document cycle.
2. **Structured diagram model** — Phase 4 (§13.4); no schema proposed yet.
3. **Multi-language documents** — `language` is per document; a per-block
   language override is not yet modeled.
4. **Block-level access control** — whether redaction happens in CDM or in the
   projection layer.
5. **Line-file dialect** — the generated line file (§10.1) must match the shape
   the existing extractors already consume from the PDF parser. The exact
   contract must be read off the current implementation before the generator is
   written.
6. **Text selection in the viewer** — SVG output is not selectable text (§5.7).
   If users must select text in CDM documents, the likely answer is an invisible
   text layer positioned over the SVG from the anchor map, which is the technique
   PDF viewers use.
7. **SVG page delivery** — whether pages are pre-rendered and cached at publish
   or rendered on demand is a performance question to settle once realistic page
   counts are known.

Deferred and recorded during the CDM Editor review (ADR 2026072602):

8. **User-defined document lifecycles** — an editorial lifecycle is a
   user-defined finite state machine with optional entry conditions, automatic
   triggers, and manual transitions. It is a **separate axis** from the
   processing lifecycle in §10.1; both use the word `published` and they are not
   the same thing. Keeping them separate is what lets this be added later as
   document metadata plus definition tables, without touching the AST.
9. **Ontology association** — must connect to the existing object model
   (ADR 2026070101) rather than introduce a parallel one.
10. **Mandatory formatting standards** — full support for a prescribed standard
    (§5.5) awaits maturity of CDM and the editor. The architecture already
    accommodates it: a standard is a template.
11. **Chunk-group field on `Block`** — the concrete representation of
    author-declared semantic chunking (§10.2) is deferred to the Phase 2
    chunking work.
12. **Retention plans** — documents may carry a retention plan, archived on
    expiry and eventually hard-removed. Not yet modeled.

**Resolved since the first draft:** tenant scoping of `document_key` — CDM
documents inherit `tenant_id` and `ks_store_id` from their `kb.inputs` row
(§10.1), so no tenant prefix on the key is needed.
