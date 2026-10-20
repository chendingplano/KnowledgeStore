---
Date: 2026/10/20
Status: Drafting
---

# 1. Purpose
Use a shared, hierarchical category index to organize artifacts such as chunks,
metrics, and provisions. An artifact may belong to multiple category branches.

This document is a proposal, not a description of implemented behavior. It is
independent of the category-consolidation proposal: the methods are different,
and this proposal does not inherit that proposal's storage or migration decisions.

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

The proposed approach maintains a shared category tree and uses a decision
model to select existing categories as an artifact moves down the tree. Its
paths then follow from those selections. Category generation happens during
tree maintenance rather than independently for every artifact.

A decision model such as [Jev](https://jev-ai.pro/docs) is a candidate for these
membership decisions. The aim is to make classification cheap and fast; actual
quality, latency, and cost must be measured before choosing a model. The key
design change is reusing category identities and structure instead of repeatedly
canonicalizing newly generated paths.

# 3. Category Tree

Each category index has a root and a tree of named category nodes. A category
has a stable ID, a canonical name, and a definition. Names and paths may change;
the ID remains the same. Canonical names, aliases, and English/Chinese labels
are vocabulary metadata. The SKOS mapping, initial vocabulary, and its namespace
must be specified before implementation.

There are two types of nodes:

- An inner node has category children, which may be inner nodes or leaves.
- A leaf has no category children and holds direct artifact memberships.

Every non-root category has exactly one parent. An artifact may have direct
memberships in multiple leaves and must be associated with every ancestor on
all those paths, including the root. Ancestor associations are distinct from
direct memberships; they do not turn an inner node into a leaf.

Each inner node may have one reserved "others" child, always a leaf. It holds
artifacts that belong under that parent but match none of its ordinary children.
It is local to its parent, not a shared category elsewhere in the tree.

If a proposed category is narrower than multiple candidate parents, choose the
top-ranked valid parent only. Use the decision model's ranking, with a stable-ID
tie-break, and flag the category for review. Retain all candidate parents, their
ranking, the selected parent, and the reason in the tree operation log. Never
create multiple parent edges or an edge that introduces a cycle.

## 3.1 Membership and category relationships

Artifact membership asks whether the artifact's content meets a category's
definition. Category placement asks whether the proposed category is genuinely
narrower than an existing category. These are different decisions and must use
separate criteria and model instructions.

For a proposed category, distinguish:

- **Equivalent:** the same concept under another name. Reuse the existing
  category and record the alternate name as an alias. Transfer any provisional
  memberships and reconcile children rather than creating a duplicate node.
- **Narrower:** a subtype of an existing category. Place it under that category,
  subject to the single-parent rule.
- **Related:** associated in topic but neither equivalent nor narrower. This
  alone does not justify a parent-child edge.

Give models category IDs, definitions, and inclusion/exclusion criteria, rather
than names alone. Validate equivalence and placement before changing the tree.

# 4. Resolve categories

Resolve an artifact against one published tree version. The root defines the
index's scope; an out-of-scope artifact must not be forced into that index.

1. Add the root category to `pending_queue` and start an empty proposed set of
   direct memberships.
2. If the queue is empty, publish the completed assignment as described in
   section 8. Otherwise, pop the front category as `active_category`.
3. If it is a leaf, add it to the proposed direct memberships and return to step 2.
4. Otherwise, retrieve its ordinary children, excluding the reserved "others"
   child. Use a decision model to determine which children match the artifact.
   Multiple children may match. When there are more than R children, partition
   them into groups of at most R (R defaults to 20), with one request per group.
   Each request evaluates membership in its supplied children; it must not infer
   that a batch-level non-match means no child of the parent matches.
5. Validate and combine results from **all** requests for this parent. Accept
   only supplied child IDs and deduplicate them. If all requests completed with
   definite decisions and no ordinary child matches, add the artifact to the
   proposed membership of this parent's "others" leaf, creating it if needed.
   If one or more children match, enqueue each matched child. Return to step 2.
6. A failed, invalid, or uncertain response is not a confirmed non-match. Keep
   the classification pending for retry or review; do not publish a partial
   assignment or put the artifact into "others" merely because a request failed.

A match in one batch and a non-match in another must therefore produce the
matched category membership without an "others" membership under that parent.

# 5. Process 'others' category

When an "others" leaf contains more than S artifacts (S defaults to 1,000), use
an LLM to propose categories from its artifacts. This is one category-discovery
operation over the collection, not a repeated extraction for each candidate.
Large collections require bounded batches and reconciliation of their proposals.

For each proposed category, compare it with existing categories under the
"others" node's parent using section 3.1:

- If equivalent to an existing category, reuse that category and reconcile any
  provisional children or memberships.
- If narrower than an existing category, add it beneath the top-ranked valid
  parent; flag multiple-parent candidates as described in section 3.
- If neither equivalent nor narrower, add it as an ordinary child of the
  "others" node's parent, provided its definition is within that parent's scope.

An existing leaf receiving a category child becomes an inner node. Its current
artifacts must be reassigned among the resulting children, with unmatched
artifacts moved into its own "others" leaf. It cannot retain direct memberships
while becoming an inner node. Complete all affected reclassifications, including
those outside the original "others" collection, before publishing this change.

Reclassify every artifact from the original "others" node against the resulting
children. Also re-evaluate artifacts already under the affected parent where
new or changed categories could add memberships: artifacts may belong to more
than one branch. Update all affected ancestor associations under section 8.

Keep unmatched artifacts in the original parent's residual "others" leaf.
Remove that leaf only when it has no remaining direct memberships and the
redistribution has been published successfully. If classification is incomplete
or maintenance fails, retain the previously published tree and assignments.

# 6. Process inner nodes

When there are too many ordinary children (> T, T defaults to 100), use an LLM
to propose broader categories that group those children. Exclude the reserved
"others" leaf from grouping and keep it attached to its original parent, where
its residual meaning remains valid. Validate and
resolve those categories using section 3.1 and the single-parent rule. Grouping
must represent a broader/narrower relationship, not merely topical similarity.

Preserve the IDs and direct memberships of existing leaves when only their
ancestors change. Recompute the ancestor associations for every affected
artifact. Re-evaluate the parent's residual "others" artifacts against the
resulting categories. If definitions or direct destinations change, or new
grouping categories could add memberships in other branches, reclassify the
affected artifacts before publishing. Log the regrouping, including every move and any
ambiguous placement. Publish the tree and association changes together.

# 7. Process leaf nodes

No automatic post-processing or splitting of ordinary leaves for now. A valid
leaf may contain thousands of artifacts. Artifact count alone does not justify
splitting it. The split policy and W threshold are deferred; section 5's
maintenance of the reserved "others" leaf is a separate operation.

# 8. Artifact associations and tree changes

For every published tree version, an artifact's associations must equal its
direct leaf memberships plus **all** ancestors of those leaves. Deduplicate
shared ancestors. This invariant must hold at all times in the published view,
including during regrouping, splitting, merging, moving, or deleting nodes.

Memberships refer to stable category IDs. Paths follow the current parent
links; any stored path is a derived value that must be updated with the tree.
Removing one leaf membership must not remove an ancestor association still
supported by another membership.

Prepare a tree change and all affected membership, ancestor, and path updates
before publishing them together. Use an atomic transaction or a versioned
publication with an atomic switch; the storage mechanism remains to be chosen.
Readers must never observe a new tree with old associations. Concurrent
classification must publish against the same tree version it evaluated or retry
against the newer version. Failed operations leave the published state intact.

This is a structural consistency guarantee for accepted assignments. Semantic
classification remains fallible and requires evaluation and review. New,
unresolved artifacts remain visibly pending; they are not represented as having
a complete classification. Reclassification retains the prior valid assignment
until the replacement is ready.

# 9. Tree operation log

Maintain a durable operation log for each category tree. Record node additions,
deletions, splits, merges, moves, regrouping, renames/definition changes, and
errors. Record attempts and outcomes so failed operations are also inspectable.

Each operation records:

- Operation ID, tree ID, timestamp, actor or job, operation type, and reason.
- Tree versions before and after publication, affected category IDs, and the
  relevant before/after names, definitions, and parent links.
- Affected artifact counts and a reference to the membership changes.
- Model/prompt versions and decision evidence when a model is involved.
- Candidate-parent rankings, the selected parent, and a review flag when more
  than one parent qualifies.
- Status (started, succeeded, failed, or pending review), error details, and
  retry linkage where applicable.

Keep operation history after a category is removed. Publish a successful change
and its success record together; preserve failure records even when the attempted
tree mutation is rolled back. Log failures must not allow unlogged mutations.

# 10. Decision quality, limits, and remaining design work

Decision responses must distinguish match, no-match, and uncertain outcomes.
Validate response structure and category IDs. Retain tree, model, and prompt
versions and enough evidence to review decisions, especially near the root,
where a missed branch prevents discovery of its descendants.

R limits candidates per request, not total work. Before implementation, define
per-artifact request/token budgets, bounded concurrency, retry limits, and
context-size limits for maintenance. Exhausting a budget leaves work pending;
it must not silently discard branches or manufacture an "others" assignment.
Surface unresolved work and exhausted retries in a review queue with its reason;
record review decisions and rerun classification when needed. A reviewer may
resolve the ambiguity or explicitly close the attempt as unclassified. Closing
an attempt must not publish an incomplete assignment as a successful one.

Evaluate membership precision and recall, full-path correctness, uncertainty,
latency, and cost using a reviewed artifact sample. Include mixed English/Chinese
names and artifacts that legitimately belong to multiple branches. Verify that
changing request grouping does not materially change the intended memberships.
The sample and limits remain to be established.

Consistency checks must cover a match in only one batch, a failed batch, residual
"others" members, multiple-parent candidates, and tree maintenance concurrent
with ingestion. Check that every published artifact has exactly its complete
ancestor set and that failed maintenance changes neither the tree nor assignments.

Storage, initial vocabulary/bootstrap, integration with existing indexes,
migration, and model selection remain separate implementation decisions. Any
integration must explicitly reconcile this proposal with the relevant existing
contracts; independence from the category-consolidation proposal does not imply
that a second conflicting membership store should be introduced.
