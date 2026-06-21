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
    "Research - Database"
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
  logical_name: "research-database",
  file_id: "2026061901",
  content_type: "research",
  document_date: "2026/06/19",
  keywords: [Database],
)

= Overview

== Arrow

Apache Arrow ([1]) defines a language-independent columnar memory format for flat 
and nested data, organized for efficient analytic operations on modern hardware 
like CPUs and GPUs. The Arrow memory format also supports zero-copy reads for 
lightning-fast data access without serialization overhead.

== DuckDB
DuckDB ([2]) has gone from a research project at CWI Amsterdam in 2019 to one of the 
most widely adopted databases of the past decade. The list of places it shows 
up is long: notebooks, ETL pipelines, dashboards, CI test runners, embedded 
analytics inside SaaS products, even an iPhone running TPC-H at scale factor 100.

*In-Process* \
There is no daemon for DuckDB. It is a C++ library: libduckdb. It runs in
the app process. 

*Analytical Database*\
DuckDB is an analytical database (columnar). Its speed comes from:
- In-process execution
- Columnar, compressed storage with zonemaps
- Vectorized execution
- Morsel-driven parallelism
- Snapshot isolation with optimistic MVCC

== Clickhouse

Clickhouse open-sourced in 2015 ([3]) with more than 2000 contributors now.
The first commit in ClichHouse was made on May 29, 2009. It is a personal
experiment project (Alexey Milovidov). 

== References
[1] Arrow, "https://arrow.apache.org/?ref=greybeam-blog.ghost.io"

[2] DuckDB Internals: Why is DuckDB Fast? (Part 1), 
https://www.greybeam.ai/blog/duckdb-internals-part-1

[3] Ten years of Clickhouse in open source,
https://clickhouse.com/blog/open-source-10
