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
    "Review - Neki - Sharded Postgres"
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
  logical_name: "neki-sharded-pg",
  file_id: "2026091101",
  source: "https://planetscale.com/blog/introducing-neki",
  content_type: "review",
  document_date: "2026/09/11",
  keywords: [Neki, Sharded PostgreSQL],
)

= Overview
Neki is sharded Postgres from PlanetScale. It lets you scale a Postgres database
across many machines while keeping real Postgres on every shard.

- Your application connects to a Neki router over the standard Postgres
  wire protocol
- Each shard is a full Postgres cluster with one primary and at least 
  two replicas across 3 availability zones. 
- You choose the shard key and control how tables are grouped and 
  distributed through a JSON data topology.
- Schema changes, version upgrades, failovers, imports and resharding all run 
  as built-in fully online workflows.
- You also get the PlanetScale features, including Insights, schema 
  recommendations, branching and MCP.
- You don't have to shard on day one. Run Neki as a single primary with replicas,
  and when you outgrow one machine, resharding is a workflow you run against
  the cluster you already have.

== How It Works

=== Neki Routers
Your apps connect to Neki Router. A router has a full Postgres query parser,
a distributed query planner, query buffering and more.

=== Sharding and Shard Groups
Every shard in Neki is real Postgres with 1 primary and at least 2 replicas.
Shards are organized into shard groups, so different tables or workloads
can live on different sets of shards. Each shard uses a configuration profile
that defines its instance size, replica count, storage, Postgres parameters,
extensions, so you can size each group for its own traffic.

=== Connection Pooling
Sidecars run alongside every Postgres instance.

=== Control Plane
The control plane tracks the health of every node.

=== Data Topology
Tying it together is the data topology, a JSON configuration that
maps your logical tables into physical shards.

