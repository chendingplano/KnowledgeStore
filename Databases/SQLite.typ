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
    "Reading-202602"
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

// #table(
//  columns: 3,
//  align: left,
//  [Name], [Description], [Documentation],
//  [Bicep], [Microsoft], [Azure-specific],
//
// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

= 2026/04/07 - SQLLite New Features

#let a_001 = link(
  "https://slicker.me/sqlite/features.htm"
)[#text(fill: blue)[Article]]

#a_001 \
Source: Hacker News

== Working with JSON data

--------- \
SQLite ships with a JSON extension that lets you store and query JSON documents directly in tables. You can keep your schema flexible while still using SQL to slice and dice structured data.

Example: extracting fields from a JSON column:

```sql

CREATE TABLE events (
  id      INTEGER PRIMARY KEY,
  payload TEXT NOT NULL -- JSON
);

SELECT
  json_extract(payload, '$.user.id')   AS user_id,
  json_extract(payload, '$.action')    AS action,
  json_extract(payload, '$.metadata')  AS metadata
FROM events
WHERE json_extract(payload, '$.action') = 'login';
```

You can also create indexes on JSON expressions, making queries over semi-structured data surprisingly fast.

== Full-text search with FTS5
SQLite’s FTS5 extension turns it into a capable full-text search engine. Instead of bolting on an external search service, you can keep everything in a single database file.

Example: building a simple search index:

```sql

CREATE VIRTUAL TABLE docs USING fts5(
  title,
  body,
  tokenize = "porter"
);

INSERT INTO docs (title, body) VALUES
  ('SQLite Guide', 'Learn how to use SQLite effectively.'),
  ('Local-first Apps', 'Why local storage and sync matter.');

SELECT rowid, title
FROM docs
WHERE docs MATCH 'local NEAR/5 storage';
```

You get ranking, phrase queries, prefix searches, and more—without leaving SQLite or managing a separate service.


== Analytics with window functions and CTEs

SQLite supports common table expressions (CTEs) and window functions, which unlock a whole class of analytical queries that used to require heavier databases.

Example: computing running totals with a window function:

```sql

SELECT
  user_id,
  created_at,
  amount,
  SUM(amount) OVER (
    PARTITION BY user_id
    ORDER BY created_at
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS running_total
FROM payments
ORDER BY user_id, created_at;
```

Combine this with CTEs and you can build surprisingly rich reports and dashboards on top of a single SQLite file.

== Strict tables and better typing

SQLite is famous (or infamous) for its flexible typing model. Modern SQLite adds STRICT tables, which enforce type constraints much more like PostgreSQL or other traditional databases.

Example: defining a strict table:

```sql
CREATE TABLE users (
  id        INTEGER PRIMARY KEY,
  email     TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1
) STRICT;
```

With strict tables, invalid types are rejected at insert time, making schemas more predictable and reducing subtle bugs—especially in larger codebases.

== Generated columns for derived data

Generated columns let you store expressions as virtual or stored columns, keeping derived data close to the source without duplicating logic across your application.

Example: a normalized search field:

```sql
CREATE TABLE contacts (
  id          INTEGER PRIMARY KEY,
  first_name  TEXT NOT NULL,
  last_name   TEXT NOT NULL,
  full_name   TEXT GENERATED ALWAYS AS (
    trim(first_name || ' ' || last_name)
  ) STORED
);

CREATE INDEX idx_contacts_full_name ON contacts(full_name);
```
Now every insert or update keeps full_name in sync automatically, and you can index and query it efficiently.

== Write-ahead logging and concurrency

Write-ahead logging (WAL) is a journaling mode that improves concurrency and performance for many workloads. Readers don’t block writers, and writers don’t block readers in the common case.

Enabling WAL is a single pragma call:

```sql
PRAGMA journal_mode = WAL;
```

For desktop apps, local-first tools, and small services, WAL mode can dramatically improve perceived performance while keeping SQLite’s simplicity and reliability.
