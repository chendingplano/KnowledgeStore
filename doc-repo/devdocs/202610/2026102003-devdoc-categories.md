---
Date: 2026/10/20
Status: Drafting
---

# Summary

SemOS pulls many kinds of items out of documents: metrics, provisions, text
chunks, and so on. To find and compare them, each item should be filed under
categories, such as "Physical properties > Temperature > Maximum temperature".
Today an AI model invents these category names item by item, so the same idea
ends up under many slightly different names and paths that are hard to tidy up
afterwards.

This proposal turns that around. People prepare a category tree in advance,
one tree per kind of item, in English and Chinese, and each category in it has
one unique name and exactly one parent. When a new item arrives, an AI model
first suggests categories for it, but those suggestions are not trusted on
their own. A second, cheaper decision model walks down the tree from the top,
checking at each level which of the existing categories really fit the item.
The item is filed under every category that fits. If nothing fits at some
level, it goes into that level's "Others" bucket instead of getting a new,
made-up category.

Because items only ever land in categories that already exist, there is
nothing to clean up afterwards. The tree itself is still improved over time,
by people or by offline jobs, but never during filing. Every change to the
tree is logged, and users can mark points in that history as named revisions
(for example `v1.0.2`) and view the tree exactly as it was at any of them.
When a change makes earlier filing out of date, the affected items are flagged
and re-filed.

The tree, its change history, and the filing records are kept in their own
database tables (section 8). This replaces the earlier approach in ADR
2026071901, which will be retired gradually.

# 1. Purpose
Use shared, hierarchical category trees to organize artifacts such as chunks,
metrics, and provisions. Category leaves store artifacts, so functionally each
category is an index of the artifacts it holds. An artifact is classified
against one category tree and may belong to multiple branches of it.

This document is a proposal, not a description of implemented behavior. It is
new, and its implementation is independent of the category-consolidation
proposal (ADR 2026071901). It does not inherit that ADR's storage, hierarchy,
or migration decisions, and the ADR will be retired gradually as this proposal
is implemented. Where the two differ, this document applies:

- The ADR allows a category to have multiple parents. This document prohibits
  it to keep trees simple; multiplicity lives in artifact bindings instead, so
  one artifact may belong to multiple categories (section 3).
- The ADR stores memberships as `kb.artifact_connections` edges. This document
  stores them in their own table (section 8).

# 2. Background
SemOS (ChenWeb) has used LLMs to generate categories while extracting artifacts.
For instance, when extracting metrics, an LLM also extracts their categories.

Categories MUST be hierarchical, and an artifact may belong to multiple
categories. A hierarchical assignment identifies a complete path, not just one
category name.

SemOS already supports category paths, but generating paths independently for
each artifact creates a serious problem: it is very difficult to canonicalize
those paths. Resolving a name alone does not resolve the identity and placement
of every category along a generated path.

The proposed approach uses a pre-built category tree and a decision model. The
LLM still proposes categories for an artifact, but those proposals are
unverified. The decision model walks down the tree, verifies which existing
categories the artifact matches, and only those canonical categories are bound
to the artifact. Classification never creates or changes categories; the tree
is maintained manually or offline (section 4).

A decision model such as [Jev](https://jev-ai.pro/docs) is a candidate for these
membership decisions. The aim is to make classification cheap and fast; actual
quality, latency, and cost must be measured before choosing a model. The key
design change is reusing category identities and structure instead of repeatedly
canonicalizing newly generated paths.

# 3. Category Tree

There can be multiple category trees, each identified by a canonical name.
Each artifact type (metrics, provisions, chunks, and so on) is bound to one
category tree, and that binding is chosen by human users, not by the system.
Every artifact of a type is classified against its type's tree.

A category tree is built before classification starts. Classification never
adds, deletes, moves, or renames categories. The tree is nonetheless modified
constantly, manually or by offline jobs; every modification is logged and can
be grouped into revisions (section 4).

Every non-root category has exactly one parent; multiple parents are
prohibited to keep trees simple. Multiplicity is expressed by the artifact
bindings instead: an artifact may have direct memberships in multiple leaves and must be associated with every ancestor on
all those paths, including the root. Ancestor associations are distinct from
direct memberships; they do not turn an inner node into a leaf.

Each inner node has one reserved "others" child, always a leaf, built with the
tree. It holds artifacts that belong under that parent but match none of its
ordinary children. It is local to its parent, not a shared category elsewhere
in the tree.

## 3.1 Nodes
There are two types of nodes in a category tree:

- An inner node has category children, which may be inner nodes or leaves.
  The root is always an inner node.
- A leaf has no category children and holds direct artifact memberships.

Each node is one category; "node" and "category" name the same thing. Node
attributes, and the SKOS property each is stored as (section 3.3):

| Attribute | SKOS / Dublin Core | Rule |
|---|---|---|
| ID | concept IRI | Opaque (for example a UUID under the tree's namespace); carries no name or path, never changes, and is never reused. Memberships refer to it. |
| Canonical name | `skos:notation` | Language-neutral ASCII slug. MUST be unique within its tree. May be changed by a logged edit. Not a display label. |
| Preferred label | `skos:prefLabel` | Exactly one per language; at least `en` and `zh`. |
| Alternative labels | `skos:altLabel` | Zero or more per language: synonyms, abbreviations, former names. |
| Hidden labels | `skos:hiddenLabel` | Optional: misspellings and variants used for matching, never displayed. |
| Description (definition) | `skos:definition` | Required in `en` and `zh`; other languages added on demand. |
| Inclusion/exclusion criteria | `skos:scopeNote` | What does and does not belong, in `en` and `zh`. Recommended for every node the decision model sees. |
| Parent | `skos:broader` | Exactly one, except for the root. |
| Source | `dct:source` | The standard, document, external vocabulary, or author the node was created from. |

Multilingual names are expressed through language-tagged labels (BCP 47 tags
such as `en` and `zh`), not separate name fields.

The "others" leaf under parent P has the canonical name `<P>-others`, which
follows P's canonical name if P is renamed, the labels "Others" / "其他", and a
definition generated from P: "Belongs under P and matches none of P's other
children."

## 3.2 Membership criteria

Artifact membership asks whether the artifact's content meets a category's
definition. Give models category IDs, preferred and alternative labels in the
artifact's language, definitions, and inclusion/exclusion criteria, rather than
names alone.

Because classification descends from the root, a child's definition must be
narrower than its parent's: an artifact that meets a child's definition also
meets its parent's. Check this whenever the tree is built or edited.

## 3.3 Canonicalization with SKOS

Canonicalization happens when a tree is built or edited, so that classification
only ever selects from canonical nodes. Each tree is a SKOS vocabulary:

- The tree is a `skos:ConceptScheme`, identified by its canonical name and
  namespace, with its own labels, definition, and `dct:source`.
- Every node is a `skos:Concept` with `skos:inScheme` pointing at its tree. The
  root is the scheme's single `skos:hasTopConcept`, and its definition sets the
  tree's scope.
- Parent links are `skos:broader` (with the inverse `skos:narrower`), within
  one scheme only. `skos:related` may record topical association but never
  creates a parent link.

When adding a node, resolve it against the nodes already in the tree, comparing
labels in every language and definitions. A candidate that means the same as an
existing node is not added as a new node; its names become `skos:altLabel`s of
that node. Do the same for candidates taken from external vocabularies, and
record the external concept with `skos:exactMatch` or `skos:closeMatch`.

The same concept may appear in more than one tree. Each tree keeps its own
node, and the nodes are linked with `skos:exactMatch` (same meaning) or
`skos:closeMatch` (nearly the same). These links let artifacts be correlated
across trees without merging them.

Validate the tree after every change set (section 4.1):

- One `skos:prefLabel` per language per node, with `en` and `zh` present.
- Canonical names, and `skos:prefLabel`s within each language, are unique in
  the tree, so a name or label identifies one node.
- A label is not both a `skos:prefLabel` and a `skos:altLabel` of the same
  node, or an `altLabel` of two nodes in the tree.
- `skos:definition` is present in `en` and `zh`.
- Every non-root node has exactly one `skos:broader`, and there are no cycles.
- Every inner node has exactly one "others" child, and leaves have none.
- `skos:exactMatch` is not used between two nodes of the same tree, since that
  would mean the tree holds a duplicate.

The initial vocabulary, the namespace, and how the initial tree is authored and
loaded must be specified before implementation.

# 4. Tree changes and revisions

## 4.1 Change log

Every modification of a category tree is recorded in an append-only change log
for that tree. Changes are made manually or by offline jobs, never by
classification. A modification does not create a revision by itself.

Operations:

- **Add node:** a new node with its attributes and parent.
- **Delete node:** remove a node. Its ID is retired, not reused.
- **Move node:** change a node's parent.
- **Update node:** change its canonical name, labels, definition, scope notes,
  or source.

Related operations made in one edit session or one offline job form a change
set. A change set is applied atomically and the tree must pass the section 3.3
validation after it, so every point in the log is a valid tree. For example,
giving a leaf its first child also adds that node's "others" leaf in the same
change set.

Each entry records: change ID, change-set ID, a sequence number increasing
within the tree, timestamp, author or job, operation, affected node IDs, the
before and after values, and a reason.

Log entries are never edited or removed. A mistake is corrected by a new
change, so a past revision always replays to the same tree.

## 4.2 Revisions

A revision is a user-created name for a point in the change log, such as
`v1.0.1` or `v1.0.2`. Creating a revision records the sequence number of the
latest change; it does not change the tree. Revision names are unique within a
tree, and a revision is never moved to a different point.

Users can view the tree at any revision. The tree at a revision is the initial
tree with every change up to the revision's sequence number applied in order,
much like replaying database migrations. Snapshots of the tree at a revision
may be stored to speed this up, but the initial tree plus the log remains the
source of truth.

The current tree is the initial tree plus all changes, and may be ahead of the
latest revision. Classification runs against the current tree.

## 4.3 Effect on artifact memberships

Each binding records the sequence number of the tree it was classified
against. Changes affect existing bindings as follows:

| Change | Effect on bound artifacts |
|---|---|
| Labels or source updated | None. |
| Canonical name updated | None; memberships use the opaque ID. |
| Node moved | Ancestor associations change (section 6); no reclassification. |
| Definition or scope notes updated | Members of the node and its subtree may no longer match; reclassify them. |
| Child added to a leaf (the leaf becomes an inner node) | Its members must be reclassified among the new children and its "others" leaf. |
| Child added to an inner node | Members of the inner node's "others" leaf may now match it; reclassify them. |
| Node deleted | Members of it and its subtree must be reclassified. |

An affected artifact keeps its prior binding, marked stale with the change that
caused it, until reclassification publishes a replacement.

# 5. Resolve categories

Classify an artifact against its category tree in two stages.

**Propose.** An LLM proposes categories for the artifact, as extraction does
today. These proposals are unverified: they are evidence for the next stage,
never bound to the artifact directly. Keep them with the classification
record; proposals that end in "others" show where the tree may need new
categories.

**Verify.** A decision model walks down the tree from the root:

1. Add the root category to `pending_queue` and start an empty proposed set of
   direct memberships.
2. If the queue is empty, publish the completed assignment as described in
   section 6. Otherwise, pop the front category as `active_category`.
3. If it is a leaf, add it to the proposed direct memberships and return to step 2.
4. Otherwise, retrieve its ordinary children, excluding the reserved "others"
   child. Give the decision model the artifact, the LLM's proposed categories,
   and the children's attributes (section 3.2), and have it determine which
   children match the artifact. Multiple children may match. When there are
   more than R children, partition them into groups of at most R (R defaults to
   20), with one request per group. Each request evaluates membership in its
   supplied children; it must not infer that a batch-level non-match means no
   child of the parent matches.
5. Validate and combine results from **all** requests for this parent. Accept
   only supplied child IDs and deduplicate them. If all requests completed with
   definite decisions and no ordinary child matches, add the artifact to the
   proposed membership of this parent's "others" leaf. If one or more children
   match, enqueue each matched child. Return to step 2.
6. A failed, invalid, or uncertain response is not a confirmed non-match. Keep
   the classification pending for retry or review; do not publish a partial
   assignment or put the artifact into "others" merely because a request failed.

A match in one batch and a non-match in another must therefore produce the
matched category membership without an "others" membership under that parent.
An artifact matching none of the root's children goes to the root's "others"
leaf.

"Others" leaves are never processed automatically. A large or growing "others"
leaf indicates that the tree does not cover part of its parent's scope; report
it for review, where it may lead to a manual or offline tree change.

# 6. Artifact associations

An artifact's associations must equal its direct leaf memberships plus **all**
ancestors of those leaves. Deduplicate shared ancestors. Memberships refer to
node IDs (section 3.1). Ancestors and paths follow from the current tree's
`skos:broader` links; if they are stored for speed, they must be updated in the
same transaction as the change set that moves a node.

Publish an artifact's direct memberships and ancestor associations together, so
readers never observe a partial assignment. Failed classification leaves the
previously published assignment intact.

This is a structural consistency guarantee for accepted assignments. Semantic
classification remains fallible and requires evaluation and review. New,
unresolved artifacts remain visibly pending; they are not represented as having
a complete classification. Reclassification retains the prior valid assignment
until the replacement is ready.

# 7. Decision quality, limits, and remaining design work

Decision responses must distinguish match, no-match, and uncertain outcomes.
Validate response structure and category IDs. Retain the tree sequence number,
model and prompt versions, the LLM's proposals, and enough evidence to review
decisions, especially near the root, where a missed branch prevents discovery
of its descendants.

R limits candidates per request, not total work. Before implementation, define
per-artifact request/token budgets, bounded concurrency, and retry limits.
Exhausting a budget leaves work pending; it must not silently discard branches
or manufacture an "others" assignment. Surface unresolved work and exhausted
retries in a review queue with its reason; record review decisions and rerun
classification when needed. A reviewer may resolve the ambiguity or explicitly
close the attempt as unclassified. Closing an attempt must not publish an
incomplete assignment as a successful one.

Evaluate membership precision and recall, full-path correctness, uncertainty,
latency, and cost using a reviewed artifact sample. Include mixed English/Chinese
names and artifacts that legitimately belong to multiple branches. Verify that
changing request grouping does not materially change the intended memberships.
The sample and limits remain to be established.

Consistency checks must cover a match in only one batch, a failed batch,
"others" members, and stale bindings after a tree change. Check that every
published artifact has exactly its complete ancestor set, and that replaying
the log to any revision produces a valid tree.

Initial tree authoring, the retirement of the ADR 2026071901 category data,
and model selection remain separate implementation decisions.

# 8. Storage

Category trees, their history, and artifact bindings are stored in tables in
the `kb` schema, created through goose migrations. Table and column names below
are proposals.

## 8.1 Tables

| Table | Holds | Key points |
|---|---|---|
| `kb.category_trees` | One row per tree: opaque ID, canonical name (unique), namespace, labels, definition, source. | |
| `kb.category_tree_types` | Which tree each artifact type is bound to (section 3). | Primary key `artifact_type`; set by users. |
| `kb.category_nodes` | The current tree: one row per node with the section 3.1 attributes. | Opaque `id`; `tree_id`; `parent_id` (null only for the root); `is_others`. Labels, definitions, and scope notes are JSONB keyed by language. Deleted nodes are kept with `retired_at` set, so their IDs still resolve in history. Unique `(tree_id, canonical_name)` over non-retired nodes. |
| `kb.category_tree_changes` | The append-only change log (section 4.1). | `tree_id`, `change_set_id`, `seq` (unique per tree), operation, node ID, before/after JSONB, author or job, reason, time. |
| `kb.category_tree_revisions` | Named revisions (section 4.2). | Unique `(tree_id, name)`; the `seq` it points at. |
| `kb.category_classifications` | One row per classification attempt (section 5). | Artifact type and ID, record ID, tree ID, tree `seq`, status (pending, published, failed, in review, unclassified), the LLM's proposals, decision evidence, model and prompt versions. |
| `kb.category_bindings` | Published direct memberships (section 6). | `node_id` FK to `kb.category_nodes`; artifact type and ID; `record_id` FK to `kb.inputs` with `ON DELETE CASCADE`; the classification that produced it; tree `seq`; stale flag and the change that made it stale (section 4.3). Unique `(artifact_type, artifact_id, node_id)`; indexed by `node_id` and by artifact. |

The initial tree is recorded as the tree's first change set, so viewing any
revision is a replay from an empty tree. `kb.category_nodes` is the current
state, kept in step with the log: a change set inserts its log entries and
updates `kb.category_nodes` in one transaction, then runs the section 3.3
validation before committing, and marks affected bindings stale in the same
transaction.

Only direct leaf memberships are stored. Ancestor associations are derived
from `parent_id` with a recursive query, so moving a node never rewrites
bindings. A stored ancestor or closure table is added only if profiling
requires it, and must then be updated in the change-set transaction.

Publishing a classification replaces the artifact's bindings and marks the
classification published in one transaction. When a document is reprocessed
and its artifacts re-extracted, the bindings of its old artifacts are replaced
along with them.

## 8.2 Bindings and `kb.artifact_connections`

**Decision: do not store bindings in `kb.artifact_connections`.** Use
`kb.category_bindings` as the only membership store. Reasons, from the table's
current definition (`ChenWeb/project_migrations/20260602000002_create_kb_artifact_connections.sql`,
`20260604000003_update_kb_artifact_connections_record_columns.sql`) and its
writers (`ChenWeb/server/api/doc-processing/connections_store.go`):

- **It connects things inside documents; category nodes belong to no
  document.** Every edge must have `source_record_id` and `target_record_id`,
  both foreign keys to `kb.inputs`. The current category edges fake the target
  by reusing the source document's ID
  (`buildArtifactCategoryConnections` in `artifact_indexing.go`).
- **No referential integrity for the category.** `target_id` is free text, so
  a binding could point at a deleted or nonexistent node. A dedicated table can
  reference `kb.category_nodes` with a foreign key.
- **The lifecycle does not match.** Writers replace a document's edges
  wholesale (delete by record, method, and relation, then insert). Bindings
  need their own lifecycle: published, stale after a tree change, and kept
  until a replacement is ready (sections 4.3 and 6).
- **The binding's own data would be buried in JSONB.** The tree `seq`, stale
  flag, classification ID, and evidence would all go in `extra_info`, where
  they cannot be constrained or indexed well.
- **The key query is not indexed.** Every index on the table leads with a
  record ID, so "all artifacts in category X" scans; ADR 2026071901 records the
  same gap.

If graph traversal needs category memberships alongside other artifact
connections, expose them through a read-only view over `kb.category_bindings`
in the connection shape, rather than writing a second copy of each binding.
The existing `category_name` partition of `kb.artifact_connections` and
`kb.artifact_categories` belong to ADR 2026071901 and are retired with it; no
new bindings are written there.
