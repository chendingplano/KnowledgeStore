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

*Change History*
#table(
  columns: 2,
  align: left,
  [Date], [Remarks],
  [2026/05/18], [file name: CodingAssistants.typ],
)

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
    "Ontology"
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
  created: "2026/05/18",
  logical_name: "Coding Assistant",
  file_id: "2026051802",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/05/18",
  keywords: ["Coding Assistant", "Harness", "SemOS"],
)

= Design Principles

It is a trend that AI systems tend to use files instead of databases. Databases provide very important and 
useful data management fucntions and features, such as ACID, indices, scalability, reliability, etc. 
These are important not only to legacy apps but to agents, too. But why many AI systems (LLMs, Agents) 
prefers file systems instead of databases?

The short answer: *agents don’t inherently prefer files over databases* — they default to files because files match how LLMs
*think, access context, and operate in simple environments*. Databases still matter a lot, but they solve a
*different layer* of the problem.

== Principle 01: A Data Store for Both Human Users and Computers
Most conventional systems, such as databases, applications, data structures (JSON, XML, etc.),
HTML (web pages), PDF, Word, Excel, etc., are designed either for human users or computers.
Enterprise Data Hub (EDH) provides a data store that is friendly for both human users and
computers.

== Principle 02: Memory and Context

Conventional systems mostly do not have the concept of context or memory (`Brain Memory`, not
computer memory). EDH treats memory and context the same as data. They are just another form
of data.

== Principle 03: Semantics

A database table is a collection of records. There is no `standard` way of specifying 
the meaning (i.e., semantics) of a table. This may not a big issue for databases because
the real users of databases are humans. That is, it is human users who understand the meaning
of a table, write statements to access the table, possibly through `standard` languages
such as SQL, JSON, MCP, etc.

EDH provides an array of mechanisms to enrich data stores with semantics, such as:
- CLAUDE.md (from Claude Code)
- SKILL.md (describe skills)
- SOUL.md (from OpenClaw)
- AGENT.md (describing agents)
- READ.md (serving as an introduction to an entity or a package)
- Sitemap (from HTML, describe the structure of a web site)
- Robots.txt (from HTML, communicating a web site with crawlers)
- And so on

EHD does not enforce any of these, but it supports most of it.

== Principle 04: `Data IP Address`

It is very close to `IP Addresses`:
- Pure Digit strings (for machines), printed in the dot-notation (for human users)
- Routable
- Standardized
- Compact and efficient
- Huge Address Space (not suffering from IPv4 problems)

This is called Docids (@ref-docid).

== Principle 05: Multi-Tenant

EHD supports multi-tenants. Refer to @sec-multi-tenant

= Architecture

== Context Machine vs Query Engine

LLMs are `context machines` not `query engines`. An LLM fundamentally works like:

```test
Give me relevant text → I reason over it → I produce output
```

That’s very different from how databases work: 
- Databases: *structured querying (SQL), optimized retrieval*
- LLMs: *unstructured context ingestion (tokens)*.

Files fit LLMs better because files are directly ingestible context, while databases require 
translation (query → result → prompt).

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

== Docids <ref-docid>

Every data item is assigned a docid. There are three types of docids: 
- Docid-8 (8-bytes unsigned integer) 
- Docid-12 (12-bytes unsigned integer)
- Docid-16 (16-bytes unsigned integer)

*Docid Format*

Docids have two parts:
- Docid Type: the highest 8 bits
- Address: the remaining bits

*Docid-8* Format
```text
  Type Bits: 8 bits, 00xxxxxx, xxxxxx not used, can be used for customization
  Cube ID: 8 bits, support up to 256 Cubes
  Shard ID: 12 bits, support up to 4096 shards per cube
  Offset: 36 bits, support up to 64 billion data entries per shard
```

Docid-8 address space is 2\*\*62 (about 4 zillions)

*Docid-12* Format

Docid-12 docids are the same as Docid-8 except that Docid-12 supports multi-tenants,
while Docid-8 is used for single-tenant.

```text
  Type Bits: 8 bits, 01xxxxxx, xxxxxx not used, can be used for customization
  TenantID: 32 bits, support up to 4 billion tenants
  Cube ID: 8 bits, support up to 256 Cubes
  Shard ID: 12 bits, support up to 4096 shards per cube
  Offset: 36 bits, support up to 64 billion data entries per shard
```

== Multi-Tenant <sec-multi-tenant>

Data for different tenants are physically isolated. Users of one tenant cannot `physically`
see files owned by users of another tenant unless data entries are explicitly marked
as `public` or `shared`.

=== Tenants

A tenant is assigned a globally unique TenantID (an integer).

=== Public Data Entries

Files whose names are ended with "\_pub" (for snake case) or "Pub" (for Pascal case)
are treated as public data entries.

(TBD).

=== Assigning Docids

Docids are assigned by the system automatically. Depending on how a data entry is created,
docids are assigned differently.

*By API*

When an API is called to add a data entry, the system will automatically assign a docid
to it.


== Retrieval is shifting from SQL → embeddings + files

A big shift:

- Old world: *index → SQL query → rows*
- Agent world: *embed → vector search → text chunks*

This stack often looks like:

```
files → chunk → embeddings → vector DB
```

Even when a “database” is used (like vector DBs), the *source of truth is still files*.

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

For many agent workflows, *Git replaces parts of a database*.

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

#figure(
   image("Images/image_2026032901.png", width: 100%),
   caption: [Schema Migration (a_26032901)],
)

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

== 2026/03/29 - Building Centralized Master Data Hub

#let a_26032901 = link(
  "https://dzone.com/articles/centralized-master-data-hub"
)[#text(fill: blue)[Article]]

#a_26032901 \
Source: dzone

It is a central data hub for master data, not real data. This is different from Matadisco,
which provides a central hub for metadata, not the data itself.

- Central ownership of master data
- Canonical, version-controlled schemas
- API-only access to master data
- Strong governance and auditability

I am not sure whether we want API-only access. API-only accesses are biased toward machines,
not human users.

Instead of API-access only, if we offer files, or file-based accesses, it is good for
both human users and machines (and AI).

There is a trend to treat file-systems as API (refer to )


= Reviews
== ZeroStack

#let a_001 = link(
  "https://crates.io/crates/zerostack/1.0.0"
)[#text(fill: blue)[OntoFlow]]

#a_001 \
Date: 2026/05/18\
Source: Hacker News

This is a small open-source project, inspired by `pi` and `opencode`, written in Rust.

*Status*

Not installed yet.

== DeepSeek Reasonix
#let a_002 = link(
  "https://github.com/esengine/DeepSeek-Reasonix"
)[#text(fill: blue)[DeepSeek Reasonix GitHub]]

#a_002 \
Date: 2026/05/19 \
Source: WeChat

This is DeepSeek-native AI coding agent (terminal). The main feature is caching. It is not a
feature that you can turn on/off. It is an invariant the loop is designed around. This is DeepSeek-only. 
Every layer is tuned to the byte-stable prefix-cache mechanic.

Support Pro and Flash auto switch.

*Status*

Installed and works as expected.

== Edit with Hashlines
(refer to [1])

*Problems*
- Coding assistant uses staled content: Read a file, the file being modified by someone,
  the coding assistant then issues an edit call with staled content. This can lead errors.
- Fail matching: in order for the coding assistant to edit, it needs to tell the tool
  exactly which lines to edit. Some models use string exact match, some may use
  other mechanisms. In general, this is not reliable. Even a tiny change, such as
  spaces, indents, can lead to incorrect tool calls.

A coding model may understand exactly what code should change, yet fail to communicate 
the change through the editing tool. Existing tools commonly require one of two 
difficult formats.

*`str_replace`*

The model must provide the exact old text:

```json
{
  "old": "  if (user == null) {\n    return;\n  }",
  "new": "  if (!user) {\n    throw new Error(...);\n  }"
}
```

This can fail because of:

- one wrong space;
- incorrect indentation;
- a missing comment;
- several identical matches;
- slightly outdated remembered content;
- quotation or escaping mistakes.

The agent has already read the code, but it must reproduce that code almost perfectly merely to 
identify what it wants changed. The article describes exact-string replacement failures as a 
major practical issue. ([Can.ac][1])

*Patch or diff formats*

With `apply_patch`, the model must produce a syntactically valid patch, including context markers 
and formatting conventions. A model can generate the correct replacement code but still fail 
because its patch is malformed or does not match the current file context. The article reports 
very high patch-failure rates for some models that were not well adapted to that particular 
patch dialect. ([Can.ac][1])

Hashlines give every observed line a compact identifier:

```text
120 4b|function calculateTotal(items) {
121 e1|  return items.reduce(...)
122 8d|}
```

The agent can say:

```text
replace 121:e1 with:
  return items.reduce(...) + tax;
```

It no longer has to:

- repeat the old line;
- preserve its whitespace;
- construct a valid unified diff;
- provide enough surrounding text to disambiguate the location.

The hash functions as a *compact, content-sensitive edit anchor*. The line number makes it easy to 
locate, while the hash confirms that the line still contains what the model saw. ([Can.ac][1])

To make this method work, the coding model needs to be 'smart'.
LLMs are generally smart enough to *understand the code despite the prefixes*, but it still 
needs to be *explicitly instructed about the hashline protocol*.

LLMs do not parse code exactly like a compiler. They process token sequences and infer structure. 
They have already encountered many similar representations:

```text
120: function calculateTotal(items) {
121:   return items.reduce(...)
122: }
```

as well as stack traces, diff markers, numbered source listings, GitHub review annotations, debugger 
output, and compiler diagnostics. Therefore, an extra prefix such as `120 4b|` usually does not 
seriously interfere with semantic understanding.

However, the harness needs to tell it something equivalent to:

```text
> File contents are displayed with line identifiers in the format `<line-number>:<hash>|<content>`.
> The identifiers are not part of the file.
> When editing, reference these identifiers using the edit tool.
> Do not include the identifiers in replacement content.
```

The edit tool schema might expose operations such as:

```json
{
  "path": "src/example.js",
  "operation": "replace",
  "start": "120:4b",
  "end": "122:8d",
  "content": "function calculateTotal(items) {\n  return items.reduce(...)\n}"
}
```

When the model edits, it references tags such as `2:f1`, ranges such as `1:a3` through `3:0e`, 
or insertion anchors such as “insert after `3:0e`.” That behavior presupposes that the tool 
definition or agent instructions explain what those tags mean. ([Can.ac][1])

Without instructions, the model might infer the convention, especially after seeing the tool 
schema, but its behavior would be unreliable. It could:

- copy hashes into the replacement code;
- use only the line number;
- call an ordinary string-replacement tool;
- reproduce the original lines instead of using identifiers;
- invent an unsupported syntax.

So the model has the cognitive ability to understand the notation, but the harness must establish 
the interface contract.

Coding agents usually receive descriptions similar to:

```text
Tool: edit_file

Source returned by read_file is prefixed with line anchors:

<line-number>:<hash>|<source text>

These anchors are display metadata and are not part of the file.

Use exact anchors from the latest read operation:
- replace one line: start_anchor
- replace a range: start_anchor and end_anchor
- insert: before_anchor or after_anchor

Replacement text must contain only actual source code.
```

And a structured schema:

```json
{
  "path": "string",
  "start_anchor": "string",
  "end_anchor": "string",
  "replacement": "string"
}
```

Performance will depend on prompt and schema quality. The harness should make four things unambiguous:

1. Hashes and line numbers are metadata, not source text.
2. The model must copy anchors exactly from the latest tool output.
3. Replacement content must not include prefixes.
4. An anchor mismatch means the file changed and should usually be reread.

== Identity Words Reconciliation
Identity Words are used in many places, such as metric name, entity name, etc.
Identity words are, however, free form. Different identity words may refer
to the same object. This section discusses the technique used to
resolve/reconcile identity words (also called keywords).

=== Trigram
PostgreSQL *trigram similarity* is a fuzzy string matching technique provided by the 
*`pg_trgm` extension*. Instead of treating text as words (like full-text search), it treats 
text as a sequence of overlapping *3-character substrings (trigrams)*. It is one of the 
most useful features for typo tolerance, approximate matching, and search-as-you-type.

Trigram similarity is often a good complement to BM25 and embeddings because it solves a 
different problem: finding strings that are *lexically similar* rather than 
*semantically similar*.

Here is how trigram works: suppose we have the word:

```
postgres
```

`pg_trgm` conceptually pads the string with spaces and generates overlapping 3-character 
windows:

```
"  p"
" po"
"pos"
"ost"
"stg"
"tgr"
"gre"
"res"
"es "
"s  "
```

(Exact padding rules are internal to PostgreSQL.) Now consider another word:

```
postgress
```

It shares almost all of the same trigrams. The similarity score is computed from the 
overlap between the trigram sets. The result is a number between

```
0.0   completely different
1.0   identical
```

For example:
```text
| String A | String B  | Similarity |
| -------- | --------- | ---------: |
| postgres | postgres  |        1.0 |
| postgres | postgress |       ~0.9 |
| postgres | postgre   |       ~0.8 |
| postgres | mysql     |       ~0.0 |
```

*Enabling pg_trgm*

```sql
CREATE EXTENSION pg_trgm;
```

*similarity()*

The basic function is

```sql
SELECT similarity('postgres', 'postgress');
```

Example output

```
 similarity
------------
0.888889
```

Another example

```sql
SELECT similarity('response time',
                  'response latency');
```

might return something around

```
0.45
```

because many character sequences overlap.

*The `%` operator*

More useful than `similarity()` is the `%` operator.

```sql
SELECT *
FROM metrics
WHERE metric_name % 'respons time';
```

This returns rows whose similarity exceeds the configured threshold.

Default threshold

```sql
SHOW pg_trgm.similarity_threshold;
```

Usually 0.3. You can change it

```sql
SET pg_trgm.similarity_threshold = 0.5;
```

*Ordering by similarity*

Very common:

```sql
SELECT
    metric_name,
    similarity(metric_name, 'respons time') AS score
FROM metrics
ORDER BY score DESC;
```

Example

```
response time      0.95
response latency   0.52
latency            0.31
```

*Fast indexing*

Without an index: `similarity(...)` must compare every row. With pg_trgm:

```sql
CREATE INDEX metric_name_trgm
ON metrics
USING GIN (metric_name gin_trgm_ops);
```

or

```sql
CREATE INDEX metric_name_trgm
ON metrics
USING GiST (metric_name gist_trgm_ops);
```

Then

```sql
WHERE metric_name % 'respons time'
```

becomes very fast even on millions of rows.

GIN is usually preferred for lookup-heavy workloads, while GiST can be advantageous 
for some nearest-neighbor style queries and update patterns.

*Distance operator*

There is also

```sql
<
->
```

(the "distance" operator)

```sql
SELECT
    metric_name,
    metric_name <-> 'respons time'
FROM metrics
ORDER BY metric_name <-> 'respons time';
```

Smaller distance means more similar.

```
0.0
```

means identical.

*KNN search*

GiST indexes support K-nearest-neighbor queries:

```sql
SELECT *
FROM metrics
ORDER BY metric_name <-> 'respons time'
LIMIT 20;
```

This efficiently returns the closest matches without scanning the whole table.

*Trigram vs. Full-Text Search (BM25-like)*

This is where many people get confused.

Suppose the query is

```
respons time
```

Trigram looks at characters.

```
respons
response
```

These are very similar. Good.

Suppose

```
response time
```

vs

```
latency
```

Character overlap is tiny. Similarity is low. Yet they may mean the same thing.
Trigram cannot tell.

*Full-text search*

Full-text search tokenizes text.

```
response
time
```

becomes

```
response
time
```

It knows nothing about character edits.

```
respons
```

becomes

```
respons
```

which is a different token.

Unless stemming or dictionaries help, it will not match.

So
```text
| Feature              | Trigram | Full Text  |
| -------------------- | ------- | ---------- |
| Typo tolerant        | ✔       | Usually no |
| Misspellings         | ✔       | Poor       |
| Character similarity | ✔       | No         |
| Word similarity      | No      | Yes        |
| Semantic similarity  | No      | No         |
| Fast indexing        | ✔       | ✔          |
```

*Trigram vs. Embeddings*

Embeddings solve a completely different problem.

Query

```
response time
```

Embedding search might retrieve

```
latency
```

because they are semantically related. Trigram similarity will not.

Conversely,

```
respons tiem
```

(an accidental misspelling)

Embedding models may produce degraded vectors, while trigram similarity still recognizes 
the intended string because most character trigrams overlap.

*Where trigram shines in SemOS*

Typical uses include:

- Resolving user typos (`latncy` → `latency`)
- Matching abbreviations or minor spelling variants before consulting a canonical alias database
- Finding near-duplicate extracted keywords during reconciliation (e.g., `response time`, `response-time`, `response times`)
- Suggesting likely metric or category names during interactive search
- Detecting duplicate entity names during ingestion

However, it should not replace semantic retrieval. A practical pipeline is often:

1. Normalize text (case, punctuation, etc.).
2. Check a canonical alias dictionary if available.
3. Use trigram similarity to catch lexical variations and typos.
4. Use BM25/full-text search for keyword relevance.
5. Use embeddings for semantic similarity.
6. Optionally expand results through graph traversal or ontology relationships.

This layered approach leverages the strengths of each technique: deterministic lexical 
matching from trigrams, relevance scoring from BM25, semantic understanding from embeddings, 
and structured relationships from your knowledge graph.

== Non-Generative NER Model - SpaCy

SpaCy is a popular open-source Python library for *natural language 
processing (NLP)*. It's designed for building production-ready applications 
that process and understand human language efficiently.

Some of the main things you can do with spaCy include:

- *Tokenization*: Split text into words, punctuation, and other meaningful units.
- *Part-of-speech tagging*: Identify whether a word is a noun, verb, adjective, etc.
- *Named entity recognition (NER)*: Find names of people, organizations, places, dates, and more.
- *Dependency parsing*: Understand the grammatical relationships between words.
- *Lemmatization*: Reduce words to their base form (e.g., "running" → "run").
- *Sentence segmentation*: Detect sentence boundaries.
- *Text classification*: Categorize text (e.g., spam detection, sentiment, topic classification).
- *Word vectors*: Represent words as numerical vectors for semantic similarity and machine learning tasks.

*Example*

```python
import spacy

# Load an English language model
nlp = spacy.load("en_core_web_sm")

text = "Apple was founded by Steve Jobs in California."

doc = nlp(text)

# Tokens
print([token.text for token in doc])

# Named entities
for ent in doc.ents:
    print(ent.text, ent.label_)
```

Output:

```
['Apple', 'was', 'founded', 'by', 'Steve', 'Jobs', 'in', 'California', '.']

Apple ORG
Steve Jobs PERSON
California GPE
```

*Characteristics of SpaCy*

- *Fast:* Optimized for speed and efficient memory usage.
- *Production-ready:* Suitable for real-world applications and large datasets.
- *Easy to use:* Clean API with sensible defaults.
- *Extensible:* Lets you train custom models for tasks like NER and text classification.
- *Integrates well:* Works alongside libraries like NumPy, pandas, scikit-learn, and PyTorch.

*spaCy vs. NLTK*

```text
| Feature                   | spaCy          | NLTK                      |
| ------------------------- | -------------- | ------------------------- |
| Primary focus             | Production NLP | Education and research    |
| Speed                     | Very fast      | Slower                    |
| Ease of use               | Modern API     | More academic and modular |
| Pretrained models         | Yes            | Limited                   |
| Deep learning integration | Strong         | Limited                   |
```

*Common Use Cases*

- Chatbots and virtual assistants
- Resume and document parsing
- Information extraction
- Search engines
- Customer support automation
- Text analytics
- Content moderation

it uses a non-generative NER model—spaCy is given as the example—to identify entity mentions. It then constructs a bipartite-style graph containing:

- *context nodes*: turns, sentences, or other trace units;
- *entity nodes*: strings recognized as named entities;
- *entity–context edges*: entity (e) occurs in context (d);
- *context–context edges*: two trace units are adjacent in the conversation. ([arXiv][1])

So a simplified graph might be:

```text
"Alice" ── occurs-in ── Turn 12
"Databricks" ─ occurs-in ─ Turn 12
Turn 12 ── adjacent-to ── Turn 13
```

The paper explicitly says the graph records *observed co-occurrence and 
trace adjacency*, rather than generating semantic triples or inferred 
relations. ([arXiv][1])

Therefore, your objection is correct for a genuine entity-relation graph, but Zero-Mem avoids that problem by building a much weaker structure. It does not know that Alice *works for* Databricks; it only knows that the two entities appeared in the same context.

A better name would arguably be:

> *entity-occurrence and trace-adjacency graph*

rather than “entity–context graph,” because the latter can easily suggest semantic relational extraction.

The cost has not disappeared entirely, either. The system still uses:

- a trained NER model;
- BGE-M3 embeddings;
- cosine similarity;
- BM25;
- Personalized PageRank.

The paper defines “zero-token” narrowly: no additional *LLM input or output tokens* are consumed during memory operations. Encoder computation is explicitly counted separately. ([arXiv][2]) Thus, “zero-token” does not mean “zero-model,” “zero-ML,” or “zero-computation.”

*“Removing conflicting evidence”* is a misleading description

The paper’s abstract says deterministic calibration “discards conflicting evidence,” but the method section describes something considerably narrower. It filters candidates using mechanically checkable constraints such as:

- provenance validity;
- session or interaction boundaries;
- subject compatibility;
- temporal compatibility;
- expected answer type;
- lexical or phrase support. ([arXiv][1])

For example, suppose the query is:

> What city did Alice say she lived in during the March session?

The retrieved evidence might contain:

```text
January: Alice lives in Boston.
March: Alice says she has moved to Seattle.
May: Bob lives in Chicago.
```

A deterministic filter can eliminate:

- the May statement because it concerns the wrong subject;
- the January statement because it lies outside the requested temporal boundary.

That is deterministic *constraint filtering*. It is not general contradiction resolution.

The system can also handle certain answer types mechanically. If the expected answer is a date, number, named entity, or list, it extracts type-compatible candidates from the evidence. It may normalize formatting, shorten an answer extractively, prune unsupported list items, or replace a scalar answer when exactly one unique compatible candidate exists. When no deterministic correction is available, the paper says it retains the LLM’s original answer. ([arXiv][1])

This means it can deterministically handle cases like:

```text
Question expects: one date
Evidence candidates: 2024-03-12
LLM answer: March 12
Result: normalize to 2024-03-12
```

But consider:

```text
Turn 10: Alice said the launch date is June 5.
Turn 20: Alice said the launch date is June 8.
```

Unless metadata establishes that Turn 20 is a later correction, a deterministic procedure cannot know whether:

- June 8 supersedes June 5;
- one statement is mistaken;
- the dates refer to different launches;
- both are estimates;
- the contradiction should be surfaced to the reader.

Semantic contradiction resolution requires a model of assertion identity, scope, temporal validity, authority, negation, and supersession. Zero-Mem’s simple graph does not contain enough structure to solve that generally.

*What the paper has really demonstrated*

The defensible claim is:

> Many memory operations can be implemented as deterministic retrieval, graph propagation, locality expansion, metadata filtering, and answer-format validation without additional generative LLM calls.

That is meaningful. However, the stronger claim—

> conflicting evidence can be deterministically removed—

is not established in the general sense. The method mostly removes 
*incompatible, out-of-scope, malformed, or unsupported evidence*, 
not arbitrary semantic contradictions.

For SemOS, I would distinguish three layers:

1. *Deterministic exclusion*
   Wrong document, product, version, jurisdiction, date range, subject, unit, or provenance.

2. *Deterministic supersession where explicit*
   “Revision 3 replaces Revision 2,” newer effective date, explicit amendment link, status changed to withdrawn.

3. *Semantic conflict analysis*
   Two provisions make incompatible claims, use different definitions, impose inconsistent thresholds, or apply under subtly different conditions.

The first two can be highly deterministic if the metadata and relations already exist. The third usually requires an LLM, a domain reasoner, formally encoded rules, or some combination of them.

So the strongest reusable idea from Zero-Mem is not that *all memory intelligence becomes deterministic*. It is that the system should reserve expensive semantic interpretation for the places where it is genuinely necessary, rather than using an LLM for routine indexing, traversal, filtering, and provenance preservation.

[1]: https://arxiv.org/html/2607.29377v1 "Zero-Mem: Zero-Token Memory Operations for LLM Agents"
[2]: https://arxiv.org/abs/2607.29377 "[2607.29377] Zero-Mem: Zero-Token Memory Operations for LLM Agents"


== Cloudflare OS
#let a_003 = link(
  "https://blog.cloudflare.com/cloudflare-os/"
)[#text(fill: blue)[CloudFlare OS Web Site]]

#a_003 \
Source: HackerNews

Cloudflare OS is an AI platform, developed for developing AI apps.

- Agent workspace: A workspace combines agent sessions, persistent state, 
  outputs and files, resource access, and an isolated runtime where the 
  agent can write and run code.
- Interface: a chat interface. User asks Cloudflare, it uses company context,
  resources made available to it, the skills created for the company,
  search, filter, etc.
- Create docs, slides, and spreadsheets: virtually anything you want to create
- Create apps
- Run deterministic workflows
- Security: 
  - agents start with no access
  - Gatekeeps goven resources and actions: a gatekeeper is a service-specific worker 
    that sits between Cloudflare OS and an external service. It understands the 
    service's API, its resources, and the operations that can be performed on them.
  - Policy follows what the agent has seen: Controlling the initial read is not enough. 
    Take, for example, the case where an agent reads a sensitive table in a data warehouse 
    and uses it to produce a live dashboard. Sharing the dashboard must not become a way 
    to share the table with people who could not access it directly.
- Every app is a Worker: when you ask your workspace to
  build an app, the agent writes two parts: Client code and Server code.
  The server is loaded on demand as a Dynamic Worker and instantiated
  as a Durable Object Facet. The facet gives the app its own SQLite
  database, separate from the Cloudflare OS runtime managing it. Dynamic
  Workers use lightweight V8 isolates, so every app can have its own 
  isolated runtime without needing a dedicated server or container
  sitting around.
- Shared the app
- Use any model: every inference call runs through Cloudflare AI Gateway,
  giving your organization one place to decide which models are available
  and which model should handle each job.
- Open source: Cloudflare OS open source.

== Zero-Mem
`Zero-Mem: Zero-Token Memory Operations for LLM Agents` addresses one of the 
major inefficiencies of today's LLM agents: almost every memory system repeatedly 
invokes an LLM to summarize conversations, extract facts, create memory records, 
or decide which memories to retrieve. Although these intermediate reasoning steps 
improve long-term memory, they incur substantial token costs, latency, and the 
risk of losing information through summarization. The paper asks a fundamental 
question: do memory operations require an LLM at all? The authors argue that they 
do not. Instead, they propose *Zero-Mem*, a framework in which every memory 
operation—except the final question answering step—is completely deterministic 
and consumes *zero LLM input/output tokens*. ([arXiv][1])

Rather than generating summaries or structured memories, Zero-Mem preserves the 
original interaction history as the authoritative record. It indexes these 
interactions using two complementary structures. The first is an *entity-context 
graph*, which connects entities, concepts, and their relationships across 
conversations, making it easy to retrieve semantically related information 
regardless of when it occurred. The second is a *temporal hierarchy*, 
which organizes conversations according to their chronological structure, preserving 
local conversational context, session state, and nearby interactions. When a user 
issues a query, the system dynamically balances these two views: graph traversal 
discovers semantically connected evidence, while temporal traversal reconstructs 
the surrounding conversational context. A deterministic calibration stage removes
conflicting evidence before the retrieved context is passed to a single LLM that 
generates the final answer. ([arXiv][1])

The most interesting contribution is philosophical as much as technical. Most 
existing agent memory systems—including frameworks such as Mem0, LightMem, LongMem, 
and many production agents—treat memory as another generative task: they ask an 
LLM to decide what to remember and later ask another LLM to decide what to 
retrieve. Zero-Mem instead treats memory as an *information retrieval and data
organization problem*, not a generation problem. The memory subsystem behaves much 
more like a search engine or database index than another language model. This 
avoids information loss caused by summarization, preserves complete provenance 
because all retrieved evidence comes directly from the original interaction traces, 
and makes the behavior substantially more deterministic and reproducible. ([arXiv][1])

Experimentally, Zero-Mem achieves competitive accuracy on long-memory and 
long-context question-answering benchmarks while eliminating all intermediate LLM 
calls. Using the same final answering model and identical context budget as 
competing methods, it reduces *memory-operation latency by 57.6%* relative to the 
fastest baseline because indexing, retrieval, graph traversal, and conflict resolution 
are entirely deterministic algorithms. Ablation studies show that both the entity 
graph and the temporal hierarchy contribute significantly, and that dynamically 
combining the two retrieval views performs better than relying on either one alone. 
The overall conclusion is that effective long-term agent memory does not 
require repeatedly asking an LLM to generate memory representations; carefully 
designed indexing structures and retrieval algorithms can perform the memory 
management, reserving the LLM solely for the final reasoning task. ([arXiv][1])

From the perspective of *SemOS* work, this paper is particularly interesting because 
its design philosophy closely matches the direction SemOS has been exploring. Instead 
of treating memory as generated summaries, Zero-Mem treats memory as *structured access 
to original artifacts*, using graph structures, hierarchical organization, 
deterministic retrieval, and evidence preservation. This is conceptually similar to 
the Virtual FS + BM25 + graph traversal + semantic retrieval architecture: the 
intelligence lies primarily in *how knowledge is organized and explored*, while the LLM 
is used only for synthesizing the final answer. The paper therefore provides empirical 
evidence supporting the idea that improving retrieval and knowledge organization may 
yield larger gains than adding additional LLM-based memory generation stages. ([arXiv][1])

= Semantic Object Store (SemOS)

*Build one context system with different memory classes, not separate knowledge base system and memory,
enhanced with explorability*.

Current memory systems are converging on a similar shape: a small always-in-context layer for durable
user/agent facts, plus a much larger on-demand archival layer for facts, documents, and other retrievable
knowledge. The system explicitly separates core memory from archival memory, where core memory is always
visible in-context and achival memory is queried on demand or `explored` by LLMs.

*Model*
```text
Unified Memory Layer
├── Core memory        (always in context)
├── Episodic memory    (conversations, sessions, tasks)
├── Semantic memory    (facts, preferences, extracted claims)
├── Artifact memory    (files, docs, tables, records, notes)
├── Procedural memory  (skills, workflows, recurring patterns)
└── Working memory     (scratchpad for current task)
```
A modern agentic system is
#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
`LLM + Skill + Iteration + Friendly Dataset + Strong Backend`. 
]

Schema-based databases, such as relational databases or any form of databases that handle structured
data, are deterministic. They are useful, but useful in the context that the applications that use
these structured data know how to use the data (such as writing the correct and precise SQL
statements). Things begin getting less deterministic when users want to the 'app' do something
on the data the 'app' was not designed for. In the future, apps will delegate more data (or knowledge)
related work to the knowledge base. The more powerful and capable the underlying knowledge store is,
the less users need to write code in apps to deal with knowledge.

This 'app' is LLM. But LLM is generic, knowing nothing about how data are stored and the datasets 
(such as NYC Taxi, Hacker News, or whatever the service may have in the future), skills are kicked
in to help LLM. 

Since skills in this context is also kind of generic. Otherwise, it needs to write a skill for
each dataset that the system offered, and more importantly, the datasets it may offer in the future.
This 'undeterministic-ness' requires the datasets be 'friendly' and the service (or backend) 
must be strong. 

This is exactly what we want to do, to develop a 'backend' that is LLM-friendly and a strong backend.
My understanding is that the most friendly type of datasets is a file-based system. For 
"My Knowledge Base Project (SemOS)", should we still use a file-based solution, but a faked one so
that it can store data on multiple machines, handle scalability, reliability, access controls,
performance, etc. (strong backend), or should I develop a CLI system, or a set of tools?

The answer: *keep the file-shaped interface*, but do not make the storage layer literally
“just files.” That is the cleanest direction for SemOS.

What we want is not “file-based vs database-based.” The real design choice is:

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
*What interface should the LLM see, and what substrate should the backend use?*
]

Build SemOS as:
#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
  *A file-like / document-like logical interface* \
  on top of \
  *a stronger multi-layer backend*
  *Use artifacts as the data model, and tools as the action model.*
  Artifacts answer: “What is in the knowledge base?”
  Tools answer: “What can the LLM do with it?”
]

So LLMs see things like:

- docs
- notes
- threads
- entities
- chunks
- citations
- attachments
- folders or collections
- versions

But underneath, we can use whatever is strongest for each job:

- object storage for blobs and original files
- relational DB for metadata, permissions, lineage, jobs, versions
- search index for retrieval
- vector index only where it actually helps
- cache for speed
- queue/workflow system for ingestion and background processing

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
> *A document/artifact-native knowledge layer*
> with
> *typed retrieval and citation tools*
> backed by
> *databases, indexes, and object storage*
]

*Fake file system outside, serious distributed system inside.*


== Design Goals

SemOS should feel like this to users and agents:

- Artifacts
- Search and Exploration
- File-based frontend
- Cite passages
- Link related things
- Create derived notes/artifacts
- Trust Provenance and Versions

The core design is:
#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
 *filesystem-like exploration outside, artifact-aware semantics underneath, strong backend inside*
]

=== Diversity

Knowledge Base should cover wide range of content, including:
- Text
- Documents
- Web Pages (HTML)
- Structured Data (JSON, XML, Markdown, Typst, LeTex, etc.)
- Videos
- Audios
- Images
- Chat history
- Social Network Content
- Blogs
- ...

=== Easy-to-Use

Users can simply drop-to-knowledge.

=== Real-Time

Content becomes `knowledge` in real-time. The moment when new content is added into the system,
it becomes `knowledge` nearly instantly.

=== Knowledge Graph

Semantic Entities (or entities for short) are connected in many dimensions:
- Similarity
- Workflow (can be useful for reasoning)
- The opposite
- and so on

This is called `Knowledge Graph` (KG).

=== Explorability

Knowledge Base must support explorability (refer to @explorability)

=== Memory 

Even with the same tools, different memory implementation has big impact on the final results.
- What gets remembered
- How it is retrieved
- When it is injected

=== Graphs

If an agent is complex enough, it can have its own sub-agents. The author suggests using graphs.
My opinion is that it should be flat (that is exactly what `pi` design: no sub-agents). 
When receiving a request, it just ask LLMs to classify the request based on all the agents (and
sub-agents, which are also agents). We may present a graph to LLMs. But LLMs always return
either a valid agent or `not found`, which falls back to the default agent.

== Design Rules

=== Ontology

The KB should not ask the LLM to guess a hidden ontology. Instead, it should expose a world
where the ontology is *legible through structure*.

That means:

- names matter
- paths matter
- hierarchy matters
- neighbors matter
- previews matter

This is why files and repos are such good environments for agents.

=== Be Logical

Paths should not expose storage details. They should expose *cognitive organization*.

Good:

```text
/projects/semos/architecture/unified-memory-layer.md
/concepts/memory/core-vs-archival.md
/user/preferences/communication.md
```

Bad:

```text
/s3/bucket123/docs/2026/04/10/chunk_4489.json
```

The filesystem is not the backend. It is the *semantic control plane* for LLM exploration. Internally, one
logical file may map to:

- many chunk rows
- embeddings
- graph nodes
- summaries
- versions
- source attachments

That is exactly the right abstraction boundary.

=== File-Shaped Interface

Files and docs are “friendly” not because they are technically superior, but because they match
how LLMs explore information.

LLMs are good at:

- reading bounded artifacts
- summarizing documents
- following references
- comparing versions
- extracting structure from semi-structured text
- navigating collections of human-created materials

LLMs are not naturally good at:

- inventing precise schemas
- knowing hidden joins
- understanding storage internals
- issuing exact structured queries without grounding

So for SemOS, the top-level abstraction should be:

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
  *knowledge artifacts*, not rows
]

That means a note, spec, PDF, markdown doc, transcript, email thread, table snapshot, code file,
image, meeting note, and maybe a synthesized “entity page” are all first-class objects.

This is why “file system” feels right.

But *do not make the backend literally a filesystem*

A literal filesystem becomes painful once you need:

- distributed storage
- deduplication
- concurrent updates
- ACLs
- queryable metadata
- indexing
- lineage
- audit trails
- partial reprocessing
- sync across machines
- efficient search
- reliability

So the right move is:

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
  *Preserve the file illusion. Fake the storage.*
]

That is not a hack. That is good architecture.

Examples of the illusion:

- every item has a stable path-like ID
- everything can be “opened”
- documents have versions
- folders/collections are navigable
- artifacts can link to artifacts
- exports/imports look like files
- the agent can “read,” “list,” “search,” “diff,” “cite,” and “compose”

But the implementation is not a POSIX tree.

== Architecture

=== LLM-Facing Interface Layer

This is what the model sees. It give the LLM *two access modes*:

*Mode 1*: virtual filesystem / path-native exploration. This provides the explorability. It exposes a stable logical tree like:

```text
/memory
  /core
    /user-profile.md
    /preferences.md
    /relationship-summary.md
  /episodes
    /2026/04/session-20260410-001.md
    /projects/semos/discussions/...
  /artifacts
    /projects/semos/specs/design.md
    /projects/semos/slides/overview.pptx
  /concepts
    /postgresql/schema-vs-db.md
    /agent-systems/memory-taxonomy.md
  /skills
    /writing/technical-explanations.md
```

This gives the model:

- browseability
- stable names
- inspectability
- low-cognitive-friction exploration

It also fits “path-native exploration model” very well.

*Mode 2*: explicit retrieval tools

Examples:

- `search("how did we define semos path-native exploration?")`
- `open("/projects/semos/specs/design.md")`
- `recall_user_profile()`
- `search_memories(entity="SemOS", type="conversation_fact")`
- `get_related("/projects/semos/specs/design.md")`

The filesystem is for *exploration*, while the retrieval API is for *precision*.

=== Canonical Memory Objects Layer

Under the hood, everything should be stored as normalized objects, not just files.

```json
SemanticObject {
  id,
  type,              // core_fact, conversation_turn, chunk, document, summary, skill, entity, relation, task
  scope,             // user, workspace, project, global
  logical_path,      // optional LLM-facing path
  title,
  content,
  source_ref,        // origin file/thread/url/session
  created_at,
  updated_at,
  valid_at,          // when fact became true
  observed_at,       // when learned
  confidence,
  salience,
  privacy,
  embedding_refs,
  keyword_index_ref,
  graph_node_ref,
  parent_id,
  chunk_ids,
  entity_ids,
  tags
}
```

This matters because “memory” and “artifact” need to coexist cleanly.

A user preference, a conversation summary, a PDF chunk, and a project design note should all be retrievable through one system, but they are *not the same type of thing*. So unify them at the storage plane, not by pretending they are identical.

=== Storage Engine Layer

Use a polyglot backend that supports:

- blob/object store
- relational metadata DB
- indexing engines
- authn/authz
- job queues
- replication/backups
- observability
- rate limits
- audit logs

=== Semantic Layer

This layer defines what LLMs and user see, making SemOS LLM-friendly. This layer does the following:

- chunking
- entity extraction
- cross-links
- summaries
- embeddings
- tags
- structured fields inferred from content
- canonical names / aliases
- relationship graph

Semantic objects examples:

- `/projects/semos/vision.md`
- `/people/alice/profile`
- `/topics/postgres/notes`
- `/sources/hn/2026-04-01-snapshot`
- `/meetings/2026-03-28/design-review`

Each semantic object has:

- content
- type
- metadata
- citations
- provenance
- version history
- permissions

=== Retrieval/query layer

How the system is actually searched.

This supports:

- lexical search
- semantic search
- faceted filtering
- graph traversal
- structured filters
- reranking
- citation generation
- hybrid retrieval


That separation gives you both friendliness and strength.

==== Object/document store

For raw artifacts and canonical objects. Examples:

- Postgres JSONB
- S3 + metadata in Postgres
- document DB if needed

Use this as source of truth.

==== Full-Text Search Index

For exact terms, identifiers, filenames, symbols, code, abbreviations. Examples:

- PostgreSQL FTS / BM25
- OpenSearch / Elasticsearch
- Tantivy / Meilisearch for self-hosted

This is essential. Pure vector search is weak for:

- names
- code symbols
- versions
- exact phrases
- file paths

==== Vector Index

For semantic recall. Examples:

- pgvector
- Qdrant
- Weaviate
- Milvus

Use this for:

- semantic similarity
- fuzzy concept recall
- cross-phrasing retrieval

==== Graph Store

For relationships and memory reasoning. Examples:

- Neo4j
- Postgres adjacency tables
- a graph overlay on top of relational tables

The value is not only entities and triples, but also fact-to-fact relationships, updates, supports, contradictions, and topic connections. ([Supermemory][2])

We will start with *Postgres + pgvector + FTS + graph tables*. Add a dedicated search engine or graph DB only after pain appears. That keeps version 1 simple.

==== Memory Processing Pipeline Layer

This is where the system becomes more than storage.

*Ingestion pipeline*

For each incoming artifact or conversation event:

1. persist raw source
2. extract structure
3. chunk
4. embed
5. keyword-index
6. entity extraction
7. fact extraction
8. relation linking
9. summary generation
10. memory classification
11. salience scoring
12. write to stores

This pipeline for both docs/files and user conversations, same system, different policies.

==== Retrieval and Assembly

At query time, the job is not “search.” The job is to assemble the *right context package* for this turn.
That package should include some mix of:

- core memory
- recent working memory
- relevant episodic memories
- relevant semantic memories
- relevant artifact chunks
- related graph facts
- citations / provenance

== Memory Classes

=== Core memory

This is for the real memory subsystem. It should hold:

- who the user is in practical terms
- stable preferences
- communication preferences
- ongoing projects
- durable constraints
- long-lived goals
- important relationships
- recurring tools/workflows

Keep it small. Think *0.5–3 KB per user/project*, not a dump.

Letta’s “memory blocks” are a useful reference point here: always-visible, persistent, small, and structured. ([Letta Docs][1])

Example:

```yaml
user_profile:
  preferred_language: English
  role: software engineer
  recurring_interests:
    - agent systems
    - knowledge systems
    - path-native exploration
  response_preferences:
    - prefers conceptual precision
    - likes system-level comparisons
    - values practical architecture advice
current_projects:
  - SemOS
durable_facts:
  - user sees memory and RAG as converging systems
```

Core memory should be:

- human-auditable
- editable
- compact
- high precision
- low churn

Do not let the system stuff noisy retrieved facts into core memory automatically.

=== Episodic Memory

This is what happened. It stores:

- session summaries
- important discussion milestones
- decisions
- task attempts
- task outcomes
- mistakes corrected
- user feedback

Example:

```text
2026-04-10: user asked to design a unified memory layer emphasizing filesystem exploration, chunking, embeddings, and real user memory.
```

This is not always in context, but searchable and summarizable.

=== Semantic Memory

This is extracted knowledge and stable facts. It stores:

- user preferences inferred from conversation
- project facts
- domain concepts learned
- definitions
- relationships

Example:

```text
Fact: In the user’s architecture, a virtual filesystem is preferred as the LLM-facing exploration interface.
Confidence: high
Scope: project/SemOS
```

This is where memory starts to overlap strongly with KB/RAG.

=== Artifact Memory

This is the “real KB” side:

- documents
- markdown files
- slides
- PDFs
- code
- notes
- tables
- records

Artifacts should preserve:

- original form
- chunks
- metadata
- logical path
- extracted entities/facts
- summaries

It stores not just memory but content or artifacts. In practice, modern memory systems already blur this line: Letta’s archival memory is explicitly for facts, knowledge, and external information at scale, not only personal memory. ([Letta Docs][3])

=== Procedural Memory

Often forgotten, but very important. It store:

- how the user likes tasks done
- reusable workflows
- templates
- skill descriptions
- tool usage patterns

Example:

```text
When explaining infrastructure systems, prefer layered architecture and contrasts with adjacent concepts.
```

This is closer to “skills” than “knowledge,” but it belongs in a unified memory layer.

== Chunking

The system does chunking. But *not one chunking strategy*. It uses *multi-resolution chunking*.

For artifacts, keep at least three levels:

- Level 0: raw document: Whole file metadata and summary
- Level 1: structural sections: Headings, chapters, slides, code modules, table sections
- Level 2: retrieval chunks: Smaller semantic chunks for vector/BM25 retrieval

This avoids a major mistake: treating the chunk as the primary object.
The chunk is an indexable slice, not the user-facing truth.

=== Chunking Policy by Content Type

- Markdown/specs: header-aware
- PDFs: layout-aware if possible
- code: function/class/module-aware
- tables: row-group or logical block-aware
- chat: turn-group or topic-shift-aware

=== Chunk Size

A practical starting point:

- 300–800 tokens per chunk
- overlap 50–120 tokens
- but prefer structural boundaries over exact token budgets

=== Chunk Metadata

Every chunk should carry:

- `doc_id`
- `section_id`
- `path`
- `heading trail`
- `position`
- `content_type`
- `timestamp`
- `entities`
- `summary`
- `scope`

This makes retrieval and reconstruction much better.

== Doc Processors
=== Summaries
(TBD)

=== Semantic Projections
(TBD)

=== Topics
(TBD)

=== Metrics
(TBD)

=== Compliance Provisions
(TBD)

=== Entities and Relations
(TBD)

=== Inventory Items
(TBD)

=== Facts
The workflow is:
- Extract facts
- Reconcile
- Review (optional)
- Establish the relations
Refer to the figure below.

#figure(
   image("../Images/image_2026070601.png", width: 100%),
   caption: [Source: #link(<memory-as-model>)[Memory as Model]],
)

The difficult part is to establish relations.

First of all, what are the relations among facts, entities, and objects?
Objects are the conomical entities. Entities are mentioned in documents.
They are normalized, reconciled to objects.

Facts should mention entities. This means that facts `<->` entities, 
thus facts `<->` objects.

Extracted relations are normalized and reconciled to Relation Nodes
(similar to Object Nodes). This means facts `<->` objects `<->` relations

== Implementation Plan

*V1*

- Postgres as canonical store
- pgvector for embeddings
- Postgres FTS or OpenSearch for BM25
- graph tables inside Postgres
- logical path tree
- basic chunking + embeddings
- memory classes:

  - core
  - episodic
  - artifact
  - semantic
- retrieval broker with hybrid ranking
- context assembler
- explicit provenance

*V2*

- better chunking by content type
- entity/relation extraction
- contradiction handling
- memory consolidation jobs
- decay/forgetting policies
- multi-hop graph retrieval
- user-visible memory editor

*V3*

- procedural memory
- self-healing summaries
- active memory suggestions
- memory quality evaluation
- per-project cognitive spaces
- richer artifact abstractions for tables/records/code

`Knowledge Base` refers to the storage in which all semantic objects are stored.

==== CLI, Tools, File-Tree

The system should support all: CLI, tools, and file-tree, with the correct order:

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
*Backend first*
 → *tool API*
 → *CLI as one client*
 → *LLM tools as another client*
]

A CLI alone is not the architecture. It is just an interface. A set of tools alone is also not
enough if there is no coherent model underneath.

*Canonical backend API*

This is the real system boundary.

Core operations:

- ingest artifact
- read artifact
- search artifacts
- retrieve chunks with citations
- resolve entity
- get linked artifacts
- update metadata
- create derived artifact
- diff versions
- list collections
- enforce permissions

*CLI*

CLI is useful for humans, scripts, and agent harnesses.

Examples:

- `semos add file.md`
- `semos search "duckdb schema evolution"`
- `semos open /projects/x/spec.md`
- `semos link /notes/a /topics/b`
- `semos diff v12 v13`
- `semos export project-x`

*LLM Tools*

These should be narrower and safer than the raw backend.

Examples:

- `search_knowledge(query, filters)`
- `open_artifact(id_or_path)`
- `read_chunk(id)`
- `get_neighbors(entity_or_artifact)`
- `create_note(parent, content)`
- `cite_passages(result_ids)`
- `propose_update(artifact, patch)`

LLMs should not directly manipulate the internal storage model.

*The Mistake to Avoid*

- *expose* raw storage primitives as the main interface.
- a pure filesystem
- a pure relational schema exposed to the LLM
- a vector DB with files glued on
- a CLI-only product
- a giant “universal query language” that the LLM must master

Bad primary interface:

- SQL tables
- raw graph nodes/edges
- opaque vector records
- low-level filesystem ops
- arbitrary shell commands

Those can exist internally, but the LLM-facing surface should be:

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
 *documented knowledge actions over meaningful artifacts*
]

That is what makes a system LLM-friendly.


Those all either become brittle or too low-level.

=== V1 Goal

A local or single-tenant system that can:

- ingest markdown/PDF/text
- normalize content
- chunk and index it
- search it
- open artifacts
- cite passages
- create draft derived notes
- keep immutable versions

That is enough to validate the model.

==== V1 Storage

- Postgres
- local filesystem or S3-compatible bucket
- pgvector
- Postgres full-text search
- one API service
- one worker

==== V1 APIs

Must-have:

- create/import artifact
- get artifact by ID/path
- get content
- search
- get chunks
- create new version
- render citations
- create draft derived note
- publish draft

==== V1 CLI

Must-have:

```bash
semos add
semos open
semos cat
semos search
semos cite
semos versions
semos diff
semos new note
semos publish
```

==== V1 LLM Tools

Must-have:

- `search_knowledge`
- `open_artifact`
- `read_passages`
- `create_note`
- `render_citations`

That is enough to support real assistant workflows.

==== V1 Relational Schema Sketch

A compact Postgres schema could start like this.

`artifacts`

- `artifact_id uuid pk`
- `logical_path text unique`
- `artifact_type text`
- `title text`
- `source_id uuid null`
- `current_version_id uuid null`
- `status text`
- `visibility text`
- `labels jsonb`
- `custom_metadata jsonb`
- timestamps

`artifact_versions`

- `version_id uuid pk`
- `artifact_id uuid fk`
- `version_number int`
- `storage_uri_original text`
- `storage_uri_normalized_text text`
- `content_hash text`
- `change_summary text`
- `parse_status text`
- `index_status text`
- `parent_version_id uuid null`
- timestamps

`(artifact_id, version_number)` can globally, uniquely identify artifacts.

`chunks`

- `chunk_id uuid pk`
- `artifact_id uuid fk`
- `version_id uuid fk`
- `chunk_index int`
- `text text`
- `token_count int`
- `char_start int`
- `char_end int`
- `page_number int null`
- `heading_path text null`
- `embedding vector(...) null`
- `fts tsvector`

`collections`

- `collection_id uuid pk`
- `logical_path text unique`
- `name text`
- `description text`
- `parent_collection_id uuid null`

`artifact_collections`

- `artifact_id uuid`
- `collection_id uuid`

`citations`

- `citation_id uuid pk`
- `artifact_id uuid`
- `version_id uuid`
- `chunk_id uuid null`
- `page_number int null`
- `char_start int`
- `char_end int`
- `locator_text text`
- `quoted_text text`

`jobs`

- `job_id uuid pk`
- `job_type text`
- `target_type text`
- `target_id uuid`
- `status text`
- `attempt_count int`
- `error_message text`
- timestamps

We can add entities/relations in V2 if V1 is doc-centric.

==== What to postpone until V2

Do not do these in V1 unless truly necessary:

- multi-machine sync
- advanced ACL inheritance
- real-time collaborative editing
- complex entity resolution
- rich graph reasoning
- OCR-heavy ingestion
- complicated workflow engine
- custom query language

V1 should prove:

- artifact model works
- citations work
- versioning works
- retrieval works
- LLM tools feel natural

==== Recommended Implementation Order

*Step 1*

Artifact + version + chunk schema

*Step 2*

Ingestion pipeline for markdown/text/PDF

*Step 3*

Search and open APIs

*Step 4*

Citation rendering

*Step 5*

CLI

*Step 6*

LLM tool layer

*Step 7*

Draft/publish workflow

*Step 8*

Derived notes with provenance

That order will get us to usefulness quickly.

==== Semantic layer

These are the derived structures for retrieval and reasoning.

Examples:

- chunks
- summaries
- tags
- extracted entities
- relationships
- embeddings
- canonical aliases

==== Retrieval layer

This layer solves how knowledge is found. It supports:

- keyword search
- semantic search
- hybrid search
- metadata filters
- graph expansion
- reranking
- passage citation

==== Control layer

This layer is responsible for making it safe and debuggable. It supports:

- auth/access control
- validation
- versioning
- drafts vs commits
- audit logs
- ingestion jobs
- retries

==== Storage layer

This is the real substrate. We will consider:

- object store: original blobs and rendered text
- relational DB: metadata, versions, ACLs, jobs, links
- search index: full text
- vector index: semantic retrieval
- queue/worker: ingestion and derivation

*Canonical Data Model*

The data model should be small and durable.

==== Semantic Objects (SemObjs)

This is the main object. Possible fields:

- `artifact_id` UUID
- `logical_path` string, like `/projects/semos/specs/vision.md`
- `artifact_type` enum
- `title`
- `mime_type`
- `current_version_id`
- `source_id`
- `collection_ids`
- `created_at`
- `updated_at`
- `created_by`
- `visibility`
- `status` (`draft`, `active`, `archived`, `deleted`)
- `labels` JSON array
- `custom_metadata` JSONB

*SemObj Types:*

- `markdown`
- `pdf`
- `docx`
- `html`
- `transcript`
- `code`
- `image`
- `table_snapshot`
- `entity_profile`
- `synthesized_note`

*Artifact Version*

Most SemObjs are immutable content snapshot. Fields include:

- `version_id`
- `artifact_id`
- `version_number`
- `storage_uri_original`
- `storage_uri_normalized_text`
- `content_hash`
- `size_bytes`
- `change_summary`
- `created_at`
- `created_by`
- `parent_version_id`
- `parse_status`
- `index_status`

This is critical. Version is the immutable state.

==== Chunk

Chunks are the retrieval unit. Chunks include the fields:

- `chunk_id`
- `artifact_id`
- `version_id`
- `chunk_index`
- `text`
- `token_count`
- `char_start`
- `char_end`
- `page_number` nullable
- `heading_path`
- `embedding_id`
- `search_document_id`

Chunks are derived, not canonical.

==== Source

It answers Where something came from. Fields include:

- `source_id`
- `source_type` (`upload`, `email`, `web_capture`, `manual`, `api_sync`)
- `source_uri`
- `external_id`
- `captured_at`
- `source_metadata` JSONB

==== Entity

Entity is the canonical named thing extracted or curated. Fields include:

- `entity_id`
- `entity_type` (`person`, `project`, `topic`, `org`, `system`, `document_concept`)
- `canonical_name`
- `aliases`
- `description`
- `profile_artifact_id` nullable
- `confidence`
- `created_at`
- `updated_at`

==== Relation

Relation is the typed edge between entities and/or artifacts. Fields include:

- `relation_id`
- `subject_type` (`artifact`, `entity`)
- `subject_id`
- `predicate`
- `object_type` (`artifact`, `entity`)
- `object_id`
- `evidence_chunk_ids`
- `confidence`
- `created_at`
- `created_by`

Example predicates:

- `mentions`
- `about`
- `derived_from`
- `contradicts`
- `supports`
- `same_as`
- `related_to`
- `owned_by`

==== Collection

Collection is the logical grouping. Fields include:

- `collection_id`
- `name`
- `logical_path`
- `description`
- `parent_collection_id`
- `visibility`

Collections give the folder/project feel without using literal folders as the only organizational model.

==== Citation

This is the reusable grounding object. Fields include:

- `citation_id`
- `artifact_id`
- `version_id`
- `chunk_id`
- `page_number`
- `char_start`
- `char_end`
- `quoted_text` optional cached excerpt
- `locator_text` like “page 4, paragraph 2”

==== Access Policy

Access Policy controls who can access which and when. Do not bolt this on later. Fields include:

- `policy_id`
- `resource_type`
- `resource_id`
- `subject_type` (`user`, `group`, `service`)
- `subject_id`
- `permission` (`read`, `write`, `admin`, `discover`)
- `effect` (`allow`, `deny`)


==== Internal Storage Choices

A strong practical split:

- *Postgres*: artifacts, versions, chunks metadata, entities, relations, jobs, ACLs
- *Object storage*: original files, normalized text, previews
- *BM25/full-text index*: OpenSearch, Typesense, Meilisearch, or Postgres FTS at small scale
- *Vector index*: pgvector first; separate service later if needed
- *Queue*: simple DB-backed jobs first; dedicated queue later
- *K-V Store*: such as ???

For V1, we can focus on the following:

- Postgres
- object store or local disk abstraction
- pgvector
- Postgres FTS
- a worker process

This will get surprisingly far while keeping things simple.

== Backend Features

=== Grounding

The system can show exactly what a result came from. Without this, LLMs becomes decorative
and untrustworthy. We want LLMs:

- passage citations
- source references
- line ranges or spans
- version IDs
- provenance chains

=== Constraint

The backend narrows ambiguity.

For example:

- artifact types
- schema for metadata
- allowed relations
- canonical entity IDs
- typed tools

This reduces hallucination.

=== Recovery

The system survives imperfect LLM behavior.

We want:

- validation
- retries
- repair loops
- safe fallbacks
- idempotent operations
- draft vs commit modes

=== Observability

When problems happen, we need to be able to debug what happened.

You want:

- tool call logs
- retrieval traces
- ranking explanations
- ingestion status
- permission-denied reasons
- version diffs

=== Evolution

We can add new data types and workflows later. This is where a file-like artifact model beats
a rigid row-first model.

== API Design

=== Ingestion APIs

*`POST /artifacts`*

This creates a new artifact.

Request:

```json
{
  "logical_path": "/projects/semos/notes/vision.md",
  "artifact_type": "markdown",
  "title": "Vision",
  "content": "# Vision\n...",
  "metadata": {
    "tags": ["semos", "architecture"]
  }
}
```

Response:

```json
{
  "artifact_id": "a1",
  "version_id": "v1",
  "status": "queued_for_indexing"
}
```

*`POST /artifacts/import`*

It imports from file/blob/external URL.

*`POST /artifacts/{id}/versions`*

It creates a new version.

=== Read APIs

*`GET /artifacts/{id}`*

It reads artifact metadata.

*`GET /artifacts/{id}/content`*

It reads normalized content for current version.

*`GET /artifacts/{id}/versions`*

It reads version history.

*`GET /artifacts/{id}/chunks`*

It reads chunk list with headings/pages.

*`GET /artifacts/by-path`*

It lookups by logical path.

Example:
```text
`GET /artifacts/by-path?path=/projects/semos/notes/vision.md`
```

=== Search APIs

*`POST /search`*

Hybrid search over artifacts/chunks.

Request:

```json
{
  "query": "artifact versioning and citations",
  "scope": {
    "collections": ["/projects/semos"],
    "artifact_types": ["markdown", "pdf"]
  },
  "mode": "hybrid",
  "limit": 10
}
```

Response:

```json
{
  "results": [
    {
      "artifact_id": "a1",
      "version_id": "v3",
      "chunk_id": "c45",
      "score": 0.92,
      "title": "Architecture Notes",
      "logical_path": "/projects/semos/architecture.md",
      "snippet": "Artifacts have immutable versions...",
      "citation": {
        "locator_text": "section Versioning",
        "char_start": 1032,
        "char_end": 1178
      }
    }
  ]
}
```

*`POST /search/related`*

Given an artifact or entity, expand neighbors.

=== Entity and relation APIs

*`GET /entities/{id}`*

*`POST /entities/resolve`*

Input a name, get canonical entity.

*`GET /artifacts/{id}/relations`*

*`POST /relations`*

=== Citation APIs

*`POST /citations/render`*

Given chunk IDs or offsets, produce stable citations.

Request:

```json
{
  "references": [
    {"chunk_id": "c45"},
    {"artifact_id": "a2", "version_id": "v7", "char_start": 500, "char_end": 620}
  ]
}
```

Response:

```json
{
  "citations": [
    {
      "citation_id": "cit1",
      "display": "Architecture Notes, Version 3, section Versioning",
      "quoted_text": "Artifacts have immutable versions..."
    }
  ]
}
```

=== Derived artifact APIs

`POST /artifacts/{id}/derive-summary`

`POST /artifacts/{id}/derive-note`

`POST /collections/{id}/synthesize`

These create new artifacts with provenance.

Every derived artifact should carry:

- source artifact IDs
- source version IDs
- citation set
- derivation job ID

=== LLM Tool Surface

The LLM should not call every API directly. Give it a smaller tool layer.

Recommended tools:

*1. `search_knowledge`*

Input:

```json
{
  "query": "How should SemOS handle versioning?",
  "filters": {
    "collections": ["/projects/semos"]
  },
  "limit": 8
}
```

Returns ranked passages with citations.

*2. `open_artifact`*

Open artifact metadata + content excerpt.

*3. `read_passages`*

Read specific chunk IDs.

*4. `find_related`*

Expand graph neighbors.

*5. `create_note`*

Create draft note under a collection/path.

*6. `update_artifact_draft`*

Patch draft content, never mutate published content directly.

*7. `render_citations`*

Turn chunk refs into stable citation text.

*8. `list_collection`*

For file/folder feel.

*9. `diff_versions`*

Very useful for reasoning over evolving knowledge.

That set is enough for many agent workflows.

== CLI design

The CLI should mirror the mental model and map to the APIs.

Use a simple style like `semos <noun> <verb>` or `semos <verb>`.
I would choose the shorter verb-first style.

*Core commands*

Add/import

```bash
semos add ./vision.md --path /projects/semos/notes/vision.md
semos import https://example.com/spec --path /sources/web/spec-001
```

Create/edit

```bash
semos new note /projects/semos/notes/ideas.md
semos edit /projects/semos/notes/ideas.md
semos publish /projects/semos/notes/ideas.md
```

Read/open

```bash
semos open /projects/semos/notes/vision.md
semos cat /projects/semos/notes/vision.md
semos show a1
semos versions /projects/semos/notes/vision.md
semos diff /projects/semos/notes/vision.md --from v2 --to v3
```

Search

```bash
semos search "artifact versioning"
semos search "citation model" --type markdown --collection /projects/semos
semos related /projects/semos/notes/vision.md
```

Cite

```bash
semos cite /projects/semos/architecture.md --section "Versioning"
semos cite chunk c45
```

Collections

```bash
semos ls /projects/semos
semos tree /projects
semos collections
```

Entities/links

```bash
semos entity resolve "Postgres"
semos links /projects/semos/architecture.md
semos link /projects/semos/architecture.md /topics/versioning --predicate about
```

Jobs/admin

```bash
semos jobs
semos reindex /projects/semos/architecture.md
semos doctor
```

== Draft/Publish Workflow

This matters a lot for LLM safety. Do not let agents silently overwrite canonical knowledge.

Recommended model is:

- all agent-authored changes go to `draft` version first
- human or policy can promote draft to `active`
- every publish creates immutable version
- every derivation records provenance

So:

- `create_note` creates draft
- `update_artifact_draft` updates draft only
- `publish` promotes to active version

This single decision will save many problems later.

=== Provenance model

This is one of the most important parts of SemOS. Every semantic object should be traceable. 
For a synthesized note, store:

- `derived_from_artifact_ids`
- `derived_from_version_ids`
- `derivation_prompt` if applicable
- `citation_ids`
- `generation_model`
- `job_id`

That lets the system to answer:

- where did this come from?
- which exact source version supported it?
- can I regenerate it?

Without provenance, an LLM knowledge base becomes untrustworthy.

For this purpose, every retrievable item should preserve:

- source
- timestamp
- extraction method
- confidence
- whether it is user-stated, inferred, or imported
- path back to original artifact/conversation

That lets the assistant say:

- “You told me this directly”
- “This came from your document”
- “This is inferred from repeated prior interactions”
- “This may be outdated”

Without provenance, memory becomes spooky and brittle.

==== The Essence of the Design

The key SemOS idea is:

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
> *documents are the native truth humans understand*
>
> *versions are the native truth systems trust*
>
> *chunks are the native truth retrieval uses*
>
> *citations are the native truth LLMs must return*
]

That combination is what makes a backend both LLM-friendly and strong.

If you want, I can turn this into a one-page RFC next, or sketch the exact Postgres tables and REST endpoints in more implementation detail.

=== Examples

These examples assume:
1. What user wants
2. What the LLM knows at the start
3. Which tools/APIs it calls
4. How it explores
5. How it forms the answer
6. What the final user answer looks like

The systems provide the following LLM-facing tools:

- `search_knowledge(query, filters?, limit?)`
- `open_artifact(id_or_path)`
- `read_passages(chunk_ids)`
- `find_related(id_or_name)`
- `list_collection(path)`
- `diff_versions(path_or_id, from_version?, to_version?)`
- `create_note(parent_path, title, content, citations?)`
- `render_citations(references)`

==== Example 1

Find the current answer in messy project docs

*User Query*

> “What is our current decision on artifact versioning in SemOS?”

This is a classic case where:

- the user does not know where the answer is
- the KB may contain old and new drafts
- the LLM must explore, compare, and ground its answer

LLMs know at the start very little about:

- the topic is “artifact versioning”
- it’s probably somewhere under the SemOS project docs
- “current decision” implies recency and perhaps a final decision doc rather than brainstorming notes

LLMs do *not* know:

- file names
- exact schema
- exact storage
- whether the answer is in one file or several

*Step 1: broad search*

```json
search_knowledge({
  "query": "artifact versioning current decision SemOS",
  "filters": {
    "collections": ["/projects/semos"]
  },
  "limit": 8
})
```

Hypothetical results:

(Hypothetically) the tool returns ranked passages like:

```text
`a17 /projects/semos/architecture.md`

  - snippet: “Artifacts have immutable versions...”
  - chunk `c301`
`a22 /projects/semos/notes/versioning-brainstorm.md`

  - snippet: “Maybe overwrite latest unless in strict mode...”
  - chunk `c455`
`a35 /projects/semos/rfcs/rfc-003-versioning.md`

  - snippet: “Decision: every publish creates a new immutable artifact version...”
  - chunk `c801`
`a41 /projects/semos/meeting-notes/2026-03-29-design-review.md`

  - snippet: “Agreed draft/publish separation is required...”
  - chunk `c920`
```

Already, the backend is doing important work:

- full-text/semantic retrieval
- passage ranking
- snippet generation
- exposing versioned artifacts and chunk IDs

*Step 2: inspect strongest candidate*

The LLM sees that `rfc-003-versioning.md` looks authoritative.

```json
open_artifact("/projects/semos/rfcs/rfc-003-versioning.md")
```

Response includes:

- title
- current version
- artifact status
- normalized content excerpt
- headings

Suppose it shows headings:

- Background
- Requirements
- Decision
- Consequences

The LLM now reads the relevant passage.

```json
read_passages({
  "chunk_ids": ["c801"]
})
```

Passage:

```text
“Decision: artifact identity is stable, while every publish creates a new immutable version. Agent-generated modifications must land in draft state first and require promotion to become active.”
```

*Step 3: verify with supporting docs*

Because the user asked for the *current* decision, the LLM should check whether later docs changed it.

```json
search_knowledge({
  "query": "versioning decision superseded changed SemOS",
  "filters": {
    "collections": ["/projects/semos"]
  },
  "limit": 6
})
```

And maybe:

```json
open_artifact("/projects/semos/meeting-notes/2026-03-29-design-review.md")
read_passages({"chunk_ids": ["c920"]})
```

Passage:
```text
> “Agreed to keep immutable versions. Drafts remain mutable until publish.”
```

This supports, not contradicts.

*Step 4: render citations*

```json
render_citations({
  "references": [
    {"chunk_id": "c801"},
    {"chunk_id": "c920"}
  ]
})
```

Returns citation display strings.

*How the LLM explores*

The exploration pattern here is:

1. Start broad
2. Identify authoritative artifact types
3. Prefer RFC/decision doc over brainstorm notes
4. Verify recency/currentness with nearby docs
5. Answer with explicit grounding

This is exactly why the artifact model matters. If the LLM only had a bag of chunks, it would lose:

- authority
- document type
- version context
- project structure

*How it forms the answer*

The LLM synthesizes:

- the decision itself
- the distinction between artifact identity and version
- the draft/publish rule
- supporting confirmation from meeting notes

It should also avoid overclaiming. For example, it should not say “this is final forever,” only “current decision based on the latest retrieved docs.”

*Final answer to the user*

A good answer might be:

```text
> The current decision is that an artifact keeps a stable identity, but every publish creates a new immutable version. Agent-written changes should go to a draft first, and only become active after promotion.
>
> The strongest source appears to be the versioning RFC, and a later design review note confirms the same model rather than changing it.
```

That answer is useful because the LLM explored rather than guessed.

==== Example 2

Answer a cross-document question the system was not explicitly designed for

*What user wants*
```text
> “Why did we choose an artifact-centric model instead of exposing SQL or raw tables to the LLM?”
```

This is more interesting because the answer may not exist as one explicit sentence anywhere.

The LLM must:

- search
- collect evidence from several docs
- infer the answer
- state that it is a synthesis

*What the LLM knows at the start*

Only the question. It does not know:

- where design rationale is documented
- whether this was discussed in notes, RFCs, or architecture docs
- whether the rationale was one reason or several

*Step 1: search for rationale*

```json
search_knowledge({
  "query": "why artifact-centric instead of SQL raw tables LLM rationale SemOS",
  "filters": {
    "collections": ["/projects/semos"]
  },
  "limit": 10
})
```

Hypothetical results:

- architecture doc: “LLMs reason better over bounded artifacts than hidden schemas”
- notes doc: “avoid requiring model to know precise relational layout”
- retrieval doc: “citations attach more naturally to passages than to rows”
- API principles doc: “tool surface should be meaningful actions over artifacts”

*Step 2: inspect multiple artifacts*

```json
open_artifact("/projects/semos/architecture.md")
read_passages({"chunk_ids": ["c110", "c114"]})
```

Passage:
```text
> “The top-level abstraction should be knowledge artifacts, not rows, because LLMs explore documents and passages more naturally than hidden joins or raw table layouts.”
```

Then:

```json
open_artifact("/projects/semos/api-principles.md")
read_passages({"chunk_ids": ["c220"]})
```

Passage:
```text
> “Do not expose raw storage primitives as the main interface. The LLM-facing surface should be knowledge actions over meaningful artifacts.”
```

Then:

```json
open_artifact("/projects/semos/retrieval.md")
read_passages({"chunk_ids": ["c340"]})
```

Passage:
```text
> “Grounding is passage-native. Citation, snippet extraction, and reranking operate over chunks linked to artifact versions.”
```

*Step 3: optionally expand related docs*

```json
find_related("/projects/semos/architecture.md")
```

This might surface:

- `/projects/semos/rfcs/rfc-001-artifact-model.md`
- `/projects/semos/notes/llm-tool-surface.md`

The LLM may inspect one more passage if needed.

*Step 4: render citations*

```json
render_citations({
  "references": [
    {"chunk_id": "c110"},
    {"chunk_id": "c220"},
    {"chunk_id": "c340"}
  ]
})
```

*How the LLM explores*

This is not simple lookup. It is a *synthesis workflow*.

The LLM is effectively building an answer from several arguments:

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
1. LLM usability:

   - artifacts are easier for LLMs than schemas/joins

2. Tool design:

   - expose meaningful actions, not low-level storage

3. Grounding:

   - passages/citations map naturally to artifacts and versions

4. System robustness:

   - artifact model separates human-facing knowledge from storage internals
]

The KB is supporting higher-level reasoning, not just exact retrieval.

*How it forms the answer*

The answer should clearly signal synthesis, such as:
```text
> Based on the design docs, the rationale seems to be...
```

That is important because the system may not have a single canonical “because” paragraph.

*Final answer to the user*
```text
> Based on the retrieved design docs, the main reason was to make the knowledge base easier for LLMs to navigate and easier to ground. The docs argue that LLMs work better with meaningful artifacts and passages than with hidden relational layouts, joins, or raw storage primitives. They also note that citation and passage retrieval are naturally artifact-based, which makes the system more trustworthy and easier to debug.
>
> So the choice was not “documents are better than databases” at the storage layer. It was that artifacts are the right *interface* for LLMs, while the backend can still use databases and indexes underneath.
```

That is a real cross-document synthesis answer.

==== Example 3

Create a new derived note after exploring the KB

*What user wants*
```text
> “Create a short draft note under `/projects/semos/notes/` summarizing the minimal V1 worth building.”
```

Now the LLM must not only answer. It must:

- find the right source material
- summarize it
- ground it
- write a new artifact draft

This is a great example of the KB as an active workspace, not just search.

*What the LLM knows at the start*

It knows the target:

- location: `/projects/semos/notes/`
- topic: minimal V1 worth building

It does not know:

- whether there is already a V1 doc
- whether “minimal V1” appears in architecture notes, roadmap, or RFCs
- whether the note should reference several sources

*Tool/API calls*

*Step 1: search*

```json
search_knowledge({
  "query": "minimal V1 worth building SemOS",
  "filters": {
    "collections": ["/projects/semos"]
  },
  "limit": 8
})
```

Hypothetical results:

- architecture note: “V1 goal”
- implementation plan: “recommended implementation order”
- roadmap doc: “what to postpone until V2”
- API design note: “must-have APIs”

*Step 2: open likely sources*

```json
open_artifact("/projects/semos/architecture.md")
read_passages({"chunk_ids": ["c510", "c520", "c530"]})
```

Suppose these passages say:

- ingest markdown/PDF/text
- normalize, chunk, index
- search, open, cite
- create draft derived notes
- keep immutable versions

Then:

```json
open_artifact("/projects/semos/roadmap.md")
read_passages({"chunk_ids": ["c610"]})
```

Passage:
```text
> “Postpone multi-machine sync, advanced ACL inheritance, rich graph reasoning, and OCR-heavy ingestion until V2.”
```

And:

```json
open_artifact("/projects/semos/api-design.md")
read_passages({"chunk_ids": ["c720"]})
```

Passage:
```text
> “Minimum LLM tool set: search_knowledge, open_artifact, read_passages, create_note, render_citations.”
```

*Step 3: render citations*

```json
render_citations({
  "references": [
    {"chunk_id": "c510"},
    {"chunk_id": "c610"},
    {"chunk_id": "c720"}
  ]
})
```

*Step 4: create the draft note*

The LLM writes a synthesized draft.

```json
create_note({
  "parent_path": "/projects/semos/notes/",
  "title": "Minimal V1 for SemOS",
  "content": "# Minimal V1 for SemOS\n\nThe minimal first version should support ingestion of markdown, text, and PDF artifacts; normalization, chunking, and indexing; search and open flows; stable passage citations; draft derived notes; and immutable published versions.\n\nThe current design suggests postponing multi-machine sync, advanced ACL inheritance, rich graph reasoning, and OCR-heavy ingestion until V2.\n\nA minimal LLM tool surface should include search, open, passage reading, note creation, and citation rendering.",
  "citations": [
    {"chunk_id": "c510"},
    {"chunk_id": "c610"},
    {"chunk_id": "c720"}
  ]
})
```

Response:

```json
{
  "artifact_id": "a99",
  "version_id": "v1",
  "logical_path": "/projects/semos/notes/minimal-v1-for-semos.md",
  "status": "draft"
}
```

*How the LLM explores*

This example shows an agentic write workflow:

1. find source material
2. gather enough evidence
3. synthesize without overreaching
4. create a draft, not silently publish
5. attach provenance

The important architectural point is that the LLM is not editing raw storage. It is operating through:

- artifact retrieval
- passage-level grounding
- draft-safe write APIs

*How it forms the answer*

The LLM should return both:

- a short user-facing summary
- the result of the note creation

For example:

- what it wrote
- where it saved it
- that it is still a draft

*Final answer to the user*

```text
> I created a draft note at `/projects/semos/notes/minimal-v1-for-semos.md`.
>
> The note summarizes V1 as:
>
> 1. ingest markdown, text, and PDF
> 2. normalize, chunk, and index content
> 3. support search, open, and citation flows
> 4. allow draft derived notes
> 5. keep immutable published versions
>
> It also notes that things like advanced ACLs, rich graph reasoning, OCR-heavy ingestion, and multi-machine sync should wait until V2.
```

That is the full loop from exploration to grounded generation to write-back.

*What these 3 examples show*

Together, they show 3 different kinds of SemOS usage.

- Example 1: retrieval + verification. The answer exists, but the LLM must find the current authoritative source.
- Example 2: retrieval + synthesis. The answer is spread across documents, and the LLM must infer it from evidence.
- Example 3: retrieval + synthesis + write-back. The LLM explores the KB, creates a grounded derived artifact, and saves it as a draft.

*The deeper pattern*

In all three cases, the LLM is not “querying a database” in the old sense.

It is doing this:

1. *Search* for likely artifacts/passages
2. *Open* promising artifacts
3. *Read* specific passages
4. *Compare / synthesize / verify*
5. *Render citations*
6. Optionally *create a derived artifact*

That is the core agent loop for an LLM-friendly knowledge base.

Traditional app over DB:
#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
> user intent → app logic → exact query → exact result
]

SemOS with LLM:
#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
> user intent → exploratory retrieval → passage grounding → synthesis → answer or draft artifact
]

So the backend must be strong in exactly the places the LLM is weak:

- finding relevant material
- preserving provenance
- exposing safe write paths
- supporting verification

=== Navigation

One issue in the above examples is that the system (SemOS) did not give LLMs a 'file-based' interface at all. 
In these examples, LLMs must 'guess' correctly that my knowledge base has a collection '/projects/semos'. 
This is a major design issue.

One SemOS design principle in my mind is: 'be natural'. Take coding for instance, when we write code, code needs
to be in a file. When people creates a file, they naturally organize files in a logical or semantic way: 
if it is a utility function, its file name may be in the directory 'utils'; if it is about products, the file name
may be named as 'product_mgr', etc. 

In coding, engineers do not organize data (code) in form of collections, which is more rooted from databases. 
As an example, I asked Codex: "Where does Qwen Code store its logs?". What Codex does is: 

- Go to ~/.qwen directory, see what files it has in the directory. Among them, there is a directory 'sessions'. 
- Codex 'guesses' this sub-directory may contain the logs, thus use to tool to retrieve files from 'sessions' directory. 
- It turned out logs are not there. 
- Codex then tries (explores) the sub-directory 'debug', ... 
- It finally found the location where logs are stored. 

Explorability is extremely important. How to improve SemOS to improve the explorability? LLMs should be able to 
*walk the space* and form hypotheses from visible structure, not only query a hidden index.

The Qwen Code example is exactly the right model. The agent did not know the answer, and it did not know the schema. 
It succeeded because the environment exposed:

- a visible hierarchy
- meaningful names
- cheap listing
- iterative narrowing
- reversible exploration

That is the kind of “naturalness” SemOS should support.

The major design deficiency of the above SemOS design is that it should not present only:

- search
- open artifact
- read passages

It should also present a *navigable, file-like world*.

So the LLM-facing surface should have two complementary modes:

==== Navigation Tools

The most commonly used tools for nagivating the knowledge base is:

- `list`
- `tree`
- `stat`
- `open`
- `find`
- `grep`
- `neighbors`

Once LLMs located the `targets`, look-up type of tools may be used, like:

- `search_knowledge`
- `read_passages`
- `find_related`
- `render_citations`

=== Explorability <explorability>

To improve SemOS explorability, make the knowledge base look less like a hidden search service
and more like a *navigable knowledge filesystem*: paths, listings, previews, relative traversal,
grep/find-like tools, and neighbor hints should become first-class.

For an LLM, explorability comes from six properties.

==== Visible structure

The agent can see what exists nearby.

Example:

- `/projects/`
- `/projects/semos/`
- `/projects/semos/rfcs/`
- `/projects/semos/notes/`

Without this, it must guess hidden namespaces.

==== 2. Meaningful Names

Paths and names carry semantics.

Examples:

- `rfc-003-versioning.md`
- `meeting-notes/2026-03-29-design-review.md`
- `architecture/retrieval.md`

These names are clues.

==== 3. Cheap Incremental Inspection

The agent can inspect without paying the cost of full retrieval.

Examples:

- list directory
- show metadata
- preview first headings
- preview first lines
- preview child counts

==== Locality

Once the agent finds one useful thing, nearby things are likely useful too.

Example:

If it finds `/projects/semos/rfcs/rfc-003-versioning.md`, then `/projects/semos/rfcs/` is probably worth listing.

==== Hypothesis-driven Traversal

The system should support “maybe it’s here” exploration.

Example:

- “logs might be in `sessions`”
- “decision might be in `rfcs`”
- “implementation details might be in `architecture`”

==== Safe Failure

Bad guesses should be cheap and informative, not catastrophic.

Example:

- “No file matched under this path”
- “Directory exists but contains no readable files”
- “Access denied to 2 items, 8 items visible”

=== The design change SemOS needs

Add a *path-native exploration API* as a first-class interface. Not just collections and IDs.
The primary world the LLM sees should look like a knowledge filesystem.

For example:

- `/projects/semos/`
- `/projects/semos/notes/`
- `/projects/semos/rfcs/`
- `/topics/postgres/`
- `/people/alice/`
- `/sources/web/modolap/`
- `/inbox/`
- `/workspace/drafts/`

These are not literal OS directories. They are logical paths. But to the LLM, they should behave similarly enough.

*`list_path(path, depth=1)`*

List children of a path.

Example return:

```json
{
  "path": "/projects/semos",
  "kind": "directory",
  "children": [
    {"name": "notes", "kind": "directory", "child_count": 12},
    {"name": "rfcs", "kind": "directory", "child_count": 5},
    {"name": "architecture.md", "kind": "artifact", "type": "markdown"},
    {"name": "roadmap.md", "kind": "artifact", "type": "markdown"}
  ]
}
```

*`stat_path(path)`*

Get metadata without opening full content.

```json
{
  "path": "/projects/semos/rfcs/rfc-003-versioning.md",
  "kind": "artifact",
  "artifact_type": "markdown",
  "title": "RFC-003 Versioning",
  "updated_at": "2026-04-01T10:33:00Z",
  "size": 12483,
  "headings": ["Background", "Decision", "Consequences"],
  "version": 3
}
```

This helps the LLM decide whether to open it.

*`preview_path(path, mode="head" | "headings" | "snippet")`*

Cheap preview.

Example:

```json
{
  "path": "/projects/semos/architecture.md",
  "preview": {
    "headings": [
      "Goals",
      "Artifact Model",
      "Versioning",
      "Retrieval"
    ]
  }
}
```

This is extremely natural for LLM exploration.

*`find_paths(query, under_path?, kind?, limit?)`*

A path-oriented search, not just semantic retrieval.

Example:

```json
find_paths({
  "query": "versioning",
  "under_path": "/projects/semos",
  "kind": "artifact",
  "limit": 10
})
```

Returns matching paths and names.

This is closer to `find` or fuzzy path search than full content search.

*`grep_content(query, under_path?, limit?)`*

Search content under a path, but preserve path context.

Example:

```json
{
  "matches": [
    {
      "path": "/projects/semos/rfcs/rfc-003-versioning.md",
      "line_or_section": "Decision",
      "snippet": "every publish creates a new immutable version"
    }
  ]
}
```

This gives the LLM the feeling of `grep -R`.

*`open_path(path, section?)`*

Open a file-like artifact by path.

This should accept paths first, IDs second.

*`tree_path(path, depth=2)`*

Show hierarchy.

Useful when orienting in an unfamiliar region.

*`suggest_neighbors(path_or_paths)`*

This is important and very LLM-friendly.

Given a useful artifact, suggest likely next places to inspect:

- sibling docs
- parent directory
- same topic folder
- linked artifacts
- more recent version or decision doc

This is a guided “what next?” explorer.

==== Exploration Loop

With those tools, the LLM can behave much more naturally.

For your earlier example:

User asks:

> “What is our current decision on versioning?”

A natural agent flow becomes:

1. `list_path("/")`
2. sees `projects`, `topics`, `inbox`, `workspace`
3. `list_path("/projects")`
4. sees `semos`, `foo`, `bar`
5. `list_path("/projects/semos")`
6. sees `rfcs`, `notes`, `architecture.md`, `roadmap.md`
7. hypothesis: decisions often live in RFCs
8. `list_path("/projects/semos/rfcs")`
9. sees `rfc-003-versioning.md`
10. `stat_path(...)`
11. `preview_path(..., "headings")`
12. `open_path(...)`
13. verify with nearby notes or newer docs

That is much closer to how a coding agent works in a repository.

==== Collections and File-Trees

Do not remove collections internally. They are still useful in the backend. But externally, 
prefer *paths* as the primary abstraction.

Internally, collections remain organizational metadata. Externally, expose them as path nodes. So `/projects/semos` may be backed by:

- a collection record
- a path index
- ACL rules
- artifact memberships

But the LLM does not need to know that.

==== Path model for SemOS

You should introduce a real logical path layer.

*Path node kinds*

- directory
- artifact
- alias
- virtual directory
- generated view

Examples

- `/projects/semos/notes/`
- `/projects/semos/rfcs/`
- `/topics/versioning/`
- `/people/alice/`
- `/sources/web/modolap/`
- `/workspace/drafts/`

Some of these are curated. Some are generated views. Unix also mixes real and virtual concepts.

Mixing curated paths and computed paths will improve explorability a lot.

*Curated paths*

Human-defined organization.

Examples:

- `/projects/semos/rfcs/`
- `/teams/platform/notes/`

*Computed paths*

System-generated views.

Examples:

- `/topics/versioning/`
- `/recent/7d/`
- `/by-type/pdf/`
- `/by-tag/postgres/`
- `/mentions/modolap/`

This is powerful because LLMs benefit from semantic neighborhoods.

So if the agent does not know where something lives, it can also explore:

- `/recent/`
- `/topics/`
- `/by-tag/`

That dramatically reduces blind guessing.

*Informative*

The directory listing itself should be informative. A plain list of names is not enough. Give the LLM just enough hints.

For each child, include:

- name
- kind
- type
- updated time
- short description if available
- child count if directory
- relevance hint if listing is the result of a suggestion

Example:

```json
{
  "name": "rfc-003-versioning.md",
  "kind": "artifact",
  "type": "markdown",
  "updated_at": "2026-04-01",
  "summary_hint": "Decision on immutable versions and draft/publish workflow"
}
```

That makes exploration much more effective.

==== Natural Affordance

Add “natural affordances” borrowed from shell/repo workflows. If we want SemOS to feel natural to
coding agents, borrow familiar operations.

*`pwd`*

Current location in the KB session.

*`cd`*

Set working path for subsequent relative operations.

*relative paths*

Let the agent operate with:

- `./rfcs`
- `../notes`
- `./architecture.md`

*globbing*

Support:

- `/projects/semos/**/*.md`
- `/projects/*/rfcs/*version*`

*find*

Search names and paths structurally.

*grep*

Search content within a region.

*ls -la equivalent*

Show richer file metadata.

These are all psychologically natural for agents trained heavily on code and shell contexts.

==== Session-Local Working Context

This is another important improvement. The system should let the LLM maintain a working directory
or working set.

Example:

- current path: `/projects/semos`
- recently opened:

  1. `architecture.md`
  2. `rfc-003-versioning.md`

- pinned artifacts:

  1. `roadmap.md`

This lets the LLM explore incrementally without repeatedly restating long paths.

So tools could support:

- `set_working_path("/projects/semos")`
- then `list_path("./rfcs")`
- then `open_path("./rfcs/rfc-003-versioning.md")`

That makes the interaction much more natural.

==== Search should become path-aware, not path-free

Your concern is exactly right: a pure semantic search interface throws away the natural structure.
So search results should always include:

- full path
- neighboring directories
- artifact type
- version
- why this result likely belongs here

Even better, let search optionally return a *path trail*:

```json
{
  "path": "/projects/semos/rfcs/rfc-003-versioning.md",
  "trail": ["/projects", "/projects/semos", "/projects/semos/rfcs"]
}
```

This helps the LLM re-anchor itself in the KB structure.

==== Improved SemOS Tool Set

*Exploration tools*

- `pwd()`
- `set_working_path(path)`
- `list_path(path=".", depth=1)`
- `tree_path(path=".", depth=2)`
- `stat_path(path)`
- `preview_path(path, mode)`
- `find_paths(query, under_path=".", kind?, limit?)`
- `grep_content(query, under_path=".", limit?)`

*Read/reason tools*

- `open_path(path, section?)`
- `read_passages(refs)`
- `diff_paths(path, from_version?, to_version?)`
- `suggest_neighbors(path_or_paths)`

*Synthesis/write tools*

- `create_note(parent_path, title, content, citations?)`
- `update_draft(path_or_id, patch)`
- `publish_draft(path_or_id)`
- `render_citations(refs)`

That is much more “natural” than starting from abstract collection filters.

==== Case Studies

Old flow:

Search with filter `/projects/semos`

New flow:

- `list_path("/")`
- `list_path("/projects")`
- `list_path("/projects/semos")`
- inspect `rfcs`
- open likely file
- verify nearby docs
- answer

The new flow is slower in the best case, but much more robust in unfamiliar territory. 
That tradeoff is worth it for exploration-heavy tasks.

==== Hybrid Strategy

*When to navigate vs when to search*

You do not want the LLM to always crawl the tree from root. That would be inefficient.
So SemOS should support this policy:

*Use navigation-first* when:

- the user asks location questions
- the agent is unfamiliar with the KB region
- path names themselves are informative
- the likely scope is small and structured
- the agent needs orientation

*Use search-first* when:

- the question is content-heavy
- the likely scope is broad
- the agent already has a good path anchor
- exact file location is not important

=== Index for Explorability

To make this work well, the backend needs a few extra indexes.

==== Path index

Fast lookup by exact path, prefix, glob, and fuzzy path name.

==== Directory materialization

Fast children listing, child counts, summaries.

==== Preview cache

Headings, first paragraphs, metadata previews.

==== Neighborhood graph

Sibling, parent, topic-linked, recent-nearby suggestions.

==== Path aliases

Multiple natural entry points.

Example:

- `/projects/semos`
- `/topics/semos`
- `/by-tag/semos`

This reduces brittle path guessing.

== Retrieval System

This is a Hybrid Retrieval System, combining file-based, vector, keyword, graph, and 
memory-aware, all under one broker.

Retrieve results should contain:

- artifact title
- logical path
- version
- snippet
- chunk ID
- score
- citation locator
- why-it-matched metadata

That last field is useful for debugging agent behavior.

Example:

```json
{
  "why_matched": {
    "keyword_terms": ["versioning", "citation"],
    "semantic_similarity": 0.81,
    "filters_applied": ["collection:/projects/semos"]
  }
}
```

=== BM25 / keyword / full-text

Full-text search is useful for:

- exact identifiers
- filenames
- acronyms
- code symbols
- rare terms
- quoted strings

=== Vector Search

Vector search (semantic search) can be useful for:

- conceptual similarity
- paraphrase matching
- fuzzy recall
- “find related discussions”

It is important that do not use semantic search alone. Use it with full-text search.

=== Graph Retrieval

Graph retrieval is useful for:
- related concepts
- user/entity/project relationships
- contradictions
- updates over time
- fact lineage

It can be useful to answer questions, such as:

- “what else is connected to this?”
- “what changed?”
- “what supports this claim?”
- “which projects relate to this preference?”

=== Memory-aware retrieval

This is the differentiator. SemOS should rank by more than relevance. It uses a scoring function like:

```text
final_score =
  semantic_similarity * w1 +
  bm25_score          * w2 +
  graph_proximity     * w3 +
  recency             * w4 +
  salience            * w5 +
  scope_match         * w6 +
  user_specificity    * w7 +
  trust/provenance    * w8
```

Where:

- *recency* matters more for conversations/tasks
- *salience* matters more for preferences/goals
- *scope_match* matters a lot
- *trust/provenance* matters for answers that cite artifacts

This is what turns retrieval into memory.

=== Context Assembly Policy

The system should build context in layers.

For each user turn, always include:

1. system instructions
2. core memory
3. recent working memory
4. current task state

Retrieve conditionally:

5. episodic memories
6. semantic memories
7. artifact chunks
8. graph neighbors
9. summaries of large retrieved clusters

Then assemble a context bundle like:

```text
<context_bundle>
  <core_memory>...</core_memory>
  <recent_context>...</recent_context>
  <relevant_memories>...</relevant_memories>
  <relevant_artifacts>...</relevant_artifacts>
  <supporting_facts>...</supporting_facts>
</context_bundle>
```

Do not dump raw retrieval results into the prompt. Normalize them into:

- concise fact cards
- summarized evidence blocks
- provenance-preserving snippets

=== Real Memory System

A real memory subsystem needs *write policies*, not just read policies.

What gets written to core memory should include only only things that are:

- durable
- user-relevant
- high confidence
- likely to matter across many future turns

Examples:

- stable preferences
- durable identity/context
- long-running projects
- standing instructions

What stays out of core memory:

- transient chat details
- random facts from one turn
- weak inferences
- most retrieved document facts

Those go to episodic or semantic memory instead.

==== Memory Write Pipeline

When a conversation ends or crosses a milestone:

1. detect candidate memories
2. classify by type
3. score confidence + durability
4. deduplicate against existing memory
5. merge / update / supersede
6. optionally ask for confirmation for sensitive long-lived facts
7. write to appropriate memory class

This is where consolidation happens. Mem0 explicitly frames memory as extraction, consolidation, retrieval, and forgetting rather than a naive transcript replay. ([Mem0][4])

==== Updating, Contradiction, and Forgetting

A real memory layer must not only remember. It must also:

- revise
- supersede
- decay
- forget

*Example*

Old memory:

```text
User prefers short answers.
```

Later evidence:

```text
User prefers detailed architecture explanations.
```

Do not silently overwrite. Keep lineage:

```text
Memory M1: user prefers short answers
status: superseded
superseded_by: M2

Memory M2: user prefers detailed architecture explanations for systems topics
status: active
```

==== Types of Forgetting

Use at least three:

1. Soft Decay: Lower retrieval weight over time
2. Archival Demotion: Keep it, but rarely retrieve it
3. Hard Delete: For explicit forget requests, privacy needs, or wrong facts

This matches the direction modern memory systems are taking: memory should evolve, consolidate, and sometimes
forget. ([Supermemory][2])

=== Retrieval Flow

*Step 1*: classify query intent

Determine whether it is primarily:

- personal memory
- recent conversation continuity
- artifact/KB retrieval
- mixed
- exploration

*Step 2*: choose retrieval blend

Examples:

Personal question: “What do I usually prefer?”

- core memory first
- semantic memory second
- episodic support third

Knowledge question: “What did the SemOS spec say about path-native exploration?”

- artifact BM25 + vector
- then related semantic facts
- then graph neighbors

Mixed question: “How does my SemOS idea compare to Supermemory?”

- core memory for your preferences
- artifact/project memory for SemOS
- external KB if needed
- graph links between concepts

*Step 3*: assemble compact evidence: Retrieve 10–30 items internally, but only inject 3–10 high-value ones into prompt context.

*Step 4*: learn from the turn: Update:

- working memory immediately
- episodic summary after turn/session
- core memory only if durable



= References

#bibliography("/references/references.bib")

== Memory blocks (core memory) \
https://docs.letta.com/guides/core-concepts/memory/memory-blocks/?utm_source=chatgpt.com

== How Graph Memory Works \
https://supermemory.ai/docs/concepts/graph-memory?utm_source=chatgpt.com

== Archival memory \
https://docs.letta.com/guides/core-concepts/memory/archival-memory/?utm_source=chatgpt.com

== AI Memory Research: 26% Accuracy Boost for LLMs \
https://mem0.ai/research?utm_source=chatgpt.com

== Memory as Model <memory-as-model>
#let r_001 = link(
  "https://www.toutiao.com/article/7652950313275605567/?app=news_article&category_new=__all__&module_name=iOS_tt_others&req_id_new=20260706060343ACF4A6D25ADEFB3E20AF&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=ba0d9deb-78bd-11f1-b4ed-00163e5a2eb2&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1783289169&tt_from=weixin&upstream_biz=iOS_wechat&use_new_style=1&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect"
)[#text(fill: blue)[Memory as Model]]

[5] #r_001

[1]: https://arxiv.org/abs/2607.29377?utm_source=chatgpt.com "Zero-Mem: Zero-Token Memory Operations for LLM Agents"


= References
[1]  I Improved 15 LLMs at Coding in One Afternoon. Only the Harness Changed
https://blog.can.ac/2026/02/12/the-harness-problem/

