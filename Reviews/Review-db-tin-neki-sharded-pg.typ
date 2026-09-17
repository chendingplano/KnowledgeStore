#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#show heading: it => {
  set text(fill: blue) if it.level == 1
  if it.numbering != none {
    counter(heading).display(it.numbering)
    h(0.5em) // Adds a little gap after the number
  }
  it.body
}

#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "Review - Tin - Fast Full-Text Search for PG"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

#let frontmatter = (
  file_type: "typst",
  logical_name: "tin-neki-sharded-pg",
  file_id: "2026091701",
  source: "https://planetscale.com/blog/introducing-tin",
  content_type: "review",
  source_date: "2026/09/16",
  document_date: "2026/09/17",
  keywords: [Tin, Neki, Sharded PostgreSQL],
)

= Overview

Tin (Text INdex) is a fast full-text search for PG. It uses various
techniques, such as something similar to docids used in JimoDB, 
bitmaps, compressions, and others.

It supports:
- Boolean expressions, phrase queries and span queries
- Fuzzy, wildcard, and regular-expression matching for terms
- Case and accent folding
- Count(\*) queries and BM25-scored top-k queries

#figure(
   image("Images/image_2026091701.png", width: 100%),
   caption: [TIN and ParadeDB Query Performance],
)

The difference is big! 

== Conclusion
Worth reading the article. Contain technical details about how to
make TIN so fast. 

It is part of Neki, which is a paid service. We may want to look at it
when we need a paid service.

Another factor to consider is: our platform is a combination of PG
and Clickhouse. For heavy loads and, especially, analytical loads, we
can use Clickhouse. 

Here is in my mind:
- Go with PG first (initially)
- Go with PG + Clickhouse when the load out grows PG
- Go with solutions such as Neki: a sharded solution

