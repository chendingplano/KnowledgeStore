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

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

= List of Figures
#outline(
  title: [],
  target: figure.where(kind: image),
)
#pagebreak()

= Change Log
#table(align: left, columns: 2,
  [Date], [Explanation],
  [2026/03/25], [Created, AIStore],
  [2026/03/27], [Changed name from AIStore to HybridBase]
)

#show heading: it => {
  set text(fill: blue) if it.level == 1
  if it.numbering != none {
    counter(heading).display(it.numbering)
    h(0.5em) // Adds a little gap after the number
  }
  it.body
}

#show heading.where(level: 1): set text(size: 18pt)
#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "Hybrid Store"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#set page(numbering: "i")
#counter(page).update(1)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

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


= Hybrid Store

It is a trend that AI systems tend to use files instead of databases. Databases provide very important and useful data
management fucntions and features, such as ACID, indices, scalability, reliability, etc. These are important not only to
legacy apps but to agents, too. But why many AI systems (LLMs, Agents) prefers file systems instead of databases?

The short answer: *agents don’t inherently prefer files over databases* — they default to files because files match how LLMs
*think, access context, and operate in simple environments*. Databases still matter a lot, but they solve a
*different layer* of the problem.

== LLMs are `context machines,` not `query engines`

An LLM fundamentally works like:

```test
Give me relevant text → I reason over it → I produce output
```

That’s very different from how databases work: 
- Databases: *structured querying (SQL), optimized retrieval*
- LLMs: *unstructured context ingestion (tokens)*.

Files fit LLMs better because files are directly ingestible context, while databases require translation (query → result → prompt).

So agents often do:

```
read file → put into prompt → think
```

instead of:

```
query DB → serialize rows → reformat → inject into prompt
```

Files are *closer to the LLM’s native interface (text)*.


== Simplicity and Aero Infrastructure

Files win by default because they are:

- No setup (no server, no schema, no migrations)
- Easy to version (Git)
- Easy to inspect/debug
- Portable across environments

Compare:

#table(align: left, columns: 3, 
[Aspect], [Files], [Database], 
[Setup], [trivial], [non-trivial],
[Debugging], [open file], [query + tooling],
[Versioning], [Git-native], [awkward],
[Deployment], [copy files], [manage service]
)

For agents—especially local tools like coding assistants—this matters a lot.

== Agents Are *Ephemeral*, not Transactional Systems

Traditional apps:

- long-lived
- concurrent users
- need ACID guarantees

Agents:

- often *single-user, single-session*
- operate in *short-lived loops*
- can recompute or retry easily

So:

- ACID → often overkill
- strict consistency → less critical

Example:

- If an agent writes slightly inconsistent state → it can fix it next step
- If a banking system does → disaster

Agents trade *rigor for flexibility*

== Files align with how agents organize knowledge

Agents frequently use:

- Markdown (`.md`)
- JSON / YAML
- Code files
- Embeddings stored alongside text

These are:

- hierarchical
- self-describing
- LLM-readable

Databases, in contrast:

- enforce rigid schemas
- separate structure from meaning

Example:

```md
# Customer
Name: Alice
Preferences:
  - vegan
  - fast shipping
```

vs

```sql
SELECT name, preference FROM customer_preferences ...
```

Files are closer to *semantic documents*, which LLMs understand better.

== Retrieval is shifting from SQL → embeddings + files

A big shift:

- Old world: **index → SQL query → rows**
- Agent world: **embed → vector search → text chunks**

This stack often looks like:

```
files → chunk → embeddings → vector DB
```

Even when a “database” is used (like vector DBs), the **source of truth is still files**.

Files become the *canonical knowledge layer*.

== Git as a “database for agents”

This is underrated but important:

Files + Git give you:

- versioning
- history
- branching
- diff
- audit trail

That covers a surprising amount of what apps need.

For many agent workflows, **Git replaces parts of a database**.

== Where databases still dominate (and should)

Databases are still critical when you need:

*Strong guarantees*

- financial systems
- inventory
- identity/auth

*Scale & concurrency*

- multi-user systems
- high write/read throughput

*Complex querying*

- analytics
- joins across large datasets

*Structured relationships*

- relational integrity
- constraints

In fact, serious agent systems often use *both*:

```
Files → knowledge + prompts + artifacts
DB → structured state + transactions
Vector DB → semantic retrieval
```

== Why the trend *feels* like “files replacing databases”

Because most visible AI tools today are:

- developer tools (Claude Code, Codex)
- personal assistants
- research agents

These operate in:

- low-scale
- local-first
- document-heavy environments

That biases the ecosystem toward files.

== The deeper insight

This isn’t “files vs databases.”

It’s:

> *Unstructured cognition layer vs structured system layer*

- Files → optimize for *reasoning*
- Databases → optimize for *correctness + scale*

Agents start from reasoning → so they start with files.

== A better mental model

Think of a modern agent stack like this:

```
[ Files (docs, code, memory) ]   ← human + LLM friendly
            ↓
[ Embeddings / retrieval ]
            ↓
[ LLM reasoning ]
            ↓
[ Database (optional) ]          ← system-of-record
```

*Bottom line*

Agents use files not because they’re “better than databases,” but because:

1. Files match how LLMs consume information (text context)
2. They minimize infrastructure and friction
3. Most agent workloads don’t need ACID-level guarantees
4. They align with document-centric, semantic workflows

But as soon as you need *reliability, scale, or multi-user coordination*, databases come back immediately.

== Central Repository

Hybrid Store provides a central store for enterprise master data, serving as the source-of-truth.
It can scale to multiple machines, possibly in different locations.

Data are broken down into layers:
- Metadata
- DOCMAP
- Chunks
- Origin

Metadata are organized into categories, which may contain sub-categories recursively.
Metadata is small, saved in files in a Semantic Hierarchical Graph (SHG) structure. Metadata are
first organized in hierarchy by their semantics. Higher layer directories are broad categories and lower
layer directories break down higher layer categories into sub-categories, all the way to
leaves, which are a collection of chunks. Each chunk points to the file from which the chunk
resides.

In this design, all metadata must be stored in the same machine, called Master Machine.
If the average size of metadata is 100 bytes, one billion metadata requires 100GB storage.

== Semantic Hierarchical Graph (SHG)

SHG is explorable. LLMs explore SHG in the same way as exploring a codebase. A node and 
all its sub-nodes in the SHD is retrieved dynamically as needed.

DOCMAP.md files are normally served on the Master Machine only. 

== Input Data

- Office documents: Word (.doc, .docx), PowerPoint (.ppt, .pptx), Excel (.excl)
- PDF
- JSON
- XML
- Markdown
- Typst
- LeTax
- Text
- Web Pages (HTML)
- Code
- Images
- Videos
- Audios
- URLs
- Chat History
- Application Data
- Social Networks data (Facebook, X, SnapChat, etc.)
- Cloud Storage (Google Drive, OneDrive, etc.)

=== Input Data Connector

Users can develop their data connectors to read from their apps, send data to their apps or both.

== Schemas

- What exactly is a schema?
- How do we want to handle schemas?
- What are the relations between the new schemas and legacy schemas?
- Why do we need schemas?

First of all, schemas in Hybrid Store are designed for human users and agents, with more focus
on supporting agents.

Schemas are explorable, dynamic, and versioned. New schemas may be learned and created by agents.

Schemas are managed in a SHG.

=== Schema Migration

Database schema migration is very important. This is, however, out of the scope of Hybrid Store, 
which is not a replacement of conventional databases.

Hybrid Store is similar to data lake. The differences between data lakes and Hybrid Store are
that data lakes are still designed for legacy applications, but Hybrid Store is mainly designed
for human users and, more importantly, agents.

== Explorability

- What do we mean by explorability?
- How to design a system that supports better explorability?

Conventional databases are deterministic. Data are retrieved through queries. They do have some
explorability feature, such as the like operator in relational databases, or regular-expression
search (BM25) in search engines. These keyword-based searching is not the same as explorability.

Suppose we are given a codebase and a bug, we know nothing about the codebase, what do we do?
Suppose we are looking at an open-source project and want to know more about the code, what do we do?
Suppose there are no files but only CLIs to search. Can we get the job done? Possibly yes. 
Is this what we want? Probably not. Being able to see directory tree for the codebase is a minimum
requirement. This does not mean that we do not want to search. We do want to search or `grep`, `find`, etc.
Not only that, we do that a lot.

== APIs

In addition to providing files (files are new type of `APIs` to LLMs), there is still need for APIs.

== Standardization

Do we want to standardize the content? Of course, we do, if possible. But standardizing content
is extremely difficult. On the other hand, the LLMs being able to understand the natural languages,
or the contents, standardization become less important.

Instead of standardizing, we can add a layer of interpretation and abstract them into a de-facto 
'standard'.

== Duplication

Since content is mostly created in isolation. It is very possible the same content being created 
multiple times. Taking `users` as an example, almost all applications need a sense of users and 
they most likely implement their view of `users`. Logically, most `users` are the same. Different
apps take different views on the logical concept of users, with different level of details.
This is the worse part: the same attribute may be named differently.

== Entities and Relations

This is a major departure from conventional data store. Hybrid Store defines many semantic entities, such as:
- User (logical)
- First Name and Last Name: a collection of first names extracted from the store
- Phone Number
- Emails
- Topics
- Addresses

== Triggers

Any application can register triggers.

== Message Hub

This is similar to Message Queue.

== Tenant

Hybrid Store is designed from ground up to support multi-tenant. Data in one tenant store are not
visible to other tenant stores except through URLs. 

Data in one tenant store are private by default. Data can, however, be marked as public.

= Reviews
== 2026/03/28 - Matadisco

#let a_001 = link(
  "https://matadisco.org/"
)[#text(fill: blue)[Article]]

#a_001 \ 
Source: Hacker News

"...data is only as useful as it is discoverable"

Matadisco is an open, decentralized network for data discovery. There are many data service providers.
They publish metadata to a central repository (I guess) through AT Protocol.

=== How Matadisco Works

*AT Protocol*

Matadisco is built on AT Protocol, an open social protocol. Every record is cryptographically signed. 
No single entity controls the network and all components are open source and can be self-hosted.

*Producers*

Write Matadisco records to a PDS (Personal Data Server). A record is a lightweight pointer to metadata — a link, 
an optional preview, and a timestamp — so the schema works with any metadata standard: STAC, DataCite, IIIF, RSS, 
and more. A producer typically watches an existing catalogue or data source and publishes records automatically.

*Consumers*

Read records from the network via a PDS or Jetstream, filter for what's relevant, and present them as a web-based
portal for users. A satellite imagery portal, a scientific data hub, a cultural heritage archive — each built in
about 100 lines of code.

*Schema*

Below is a schema:
```text
cx.vmx.matadisco
/// A Matadisco record
record matadisco {
    /// The time the original metadata/data was published
    publishedAt!: Datetime,
    /// A URI that links to resource containing the metadata
    resource!: Uri,
    /// Preview of the data
    preview: {
        /// The media type the preview has
        mimeType!: string,
        /// The URL to the preview
        url: Uri,
    },
}
```
