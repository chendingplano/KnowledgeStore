#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

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
    "Fuse"
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

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

#let frontmatter = (
  created: "2026/06/15",
  logical_name: "Fuse",
  file_id: "2026061501",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/06/15",
  keywords: ["FUSE", "Userland Filesystem", "Filesystem"],
)

= Overview
FUSE—*Filesystem in Userspace*—lets you implement a filesystem as a normal 
user-space process rather than as kernel code.

Applications still use ordinary filesystem operations such as `open`, `read`, 
`write`, `stat`, `readdir`, and `rename`. The kernel forwards those operations 
to the FUSE process, which decides how to satisfy them.

Conceptually:

```text
Application
   ↓ open/read/write
Kernel VFS
   ↓ FUSE protocol
User-space filesystem process
   ↓
Database, object store, remote API, generated content, encrypted storage, etc.
```

Main usage is to create a filesystem for a specific dataset, such as databases,
knowledge bases, etc. You want people to access the dataset using the standard
filesystem interface and toolset.

== Main benefits

=== Normal filesystem interface over non-filesystem data

FUSE can expose almost anything as files and directories:

- S3 or another object store
- a database
- an HTTP API
- an archive
- encrypted content
- generated or computed data
- a knowledge graph
- a version-control repository
- a remote machine

Existing tools can then access that data without special integration:

```bash
cat /mnt/knowledge/topics/postgresql.md
grep -R "BM25" /mnt/knowledge
find /mnt/knowledge -name '*.md'
```

This is often FUSE's most important advantage: *it converts a custom storage 
system into a widely understood interface*.

=== Much safer and easier development than kernel filesystems

Kernel filesystem development is difficult and dangerous. A bug can crash or corrupt the entire machine.

A FUSE filesystem is an ordinary process:

- it can be written in Go, Rust, Python, C++, and other languages;
- it can use normal debuggers and logging;
- a crash usually only unmounts or breaks that filesystem;
- deployment does not normally require a custom kernel module.

That makes FUSE practical for experimental or application-specific filesystems.

=== Compatibility with existing software

Many programs understand files but do not understand your database schema, graph API, or object-store API.

FUSE provides compatibility with:

- editors
- command-line tools
- compilers
- backup tools
- IDEs
- coding agents
- desktop file browsers
- language runtimes
- legacy software

=== Lazy and dynamic content generation

A FUSE filesystem does not have to materialize every file in advance.

For example:

```text
/mnt/semos/searches/postgresql-bm25/results.md
```

could be generated when it is opened.

Likewise:

```text
/mnt/semos/concepts/response-time/related.md
```

could query a graph dynamically.

This is useful when files are:

- expensive to generate;
- derived from current data;
- personalized;
- query-dependent;
- too numerous to precompute.

=== Centralized policy enforcement

Because all filesystem operations pass through the FUSE service, it can enforce:

- access control;
- read-only views;
- audit logging;
- content filtering;
- encryption and decryption;
- tenant isolation;
- file-name normalization;
- version selection;
- provenance tracking.

=== Building an encrypted filesystem

The FUSE layer can decrypt data during reads and encrypt it during writes, 
while presenting normal plaintext files to authorized applications.

== When FUSE is not a good choice

=== Very high-performance local storage

FUSE introduces extra overhead.

=== Extremely high metadata-operation rates

Workloads involving enormous numbers of:

- `stat`
- `open`
- `close`
- `readdir`
- tiny reads

may suffer significantly.

=== When strong transactional semantics are required

Normal filesystem operations do not naturally expose database-grade multi-record transactions.

If users need:

```sql
BEGIN;
UPDATE ...
INSERT ...
COMMIT;
```

a filesystem interface is usually insufficient as the primary interface.

== SemOS
For SemOS, FUSE could be useful as an *LLM-oriented exploration layer*.

For example:

```text
/mnt/semos/
├── documents/
│   └── iso-1234/
│       ├── source.pdf
│       ├── summary.md
│       ├── provisions/
│       ├── metrics/
│       └── references/
├── concepts/
│   └── response-time/
│       ├── description.md
│       ├── related/
│       └── evidence/
├── categories/
├── searches/
└── recent/
```

The underlying information could remain in PostgreSQL and object storage. FUSE would 
generate the directory structure and files dynamically.

This would allow Codex, Claude Code, shell tools, or an editor to explore SemOS 
using ordinary operations:

```bash
find /mnt/semos/concepts/response-time
cat /mnt/semos/concepts/response-time/description.md
grep -R "time to first byte" /mnt/semos/metrics
```

However, I would not use FUSE as SemOS's canonical data model. The canonical layer 
should still use stable object IDs, structured metadata, graph relationships, and 
database transactions. Paths should be *projections or views* of those objects.

A sensible SemOS architecture would be:

```text
PostgreSQL + object store + graph/indexes
                  ↓
         SemOS domain service
          ↙       ↓        ↘
        API      CLI      FUSE
```

That gives agents filesystem exploration while preserving proper structured access.

== Practical decision rule

Use FUSE when all three are substantially true:

1. The consumers already understand files and directories.
2. The underlying data is not naturally available as a normal filesystem.
3. The convenience and compatibility outweigh the added performance and semantic complexity.

For SemOS specifically, FUSE is most compelling as a *read-heavy virtual knowledge filesystem 
for exploration*, not as the primary write or transactional interface.

