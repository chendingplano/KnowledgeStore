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
    "Research - Future Codebase"
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
  logical_name: "Future Codebase",
  file_id: "2026061001",
  source: "ChatGPT, Claude",
  content_type: "research",
  document_date: "2026/06/10",
  keywords: [Knowledgebase, Codebase],
)

= Overview
#let a_001 = link(
  "https://openai.com/index/harness-engineering/"
)[#text(fill: blue)[OpenAI Article]]

#a_001 

When we vibe coding, we as human beings spend more time on requirements, specs, testing 
and verification, instead of coding. This means (at least to me) human programmers will 
be less 'coder' and more 'knowledge worker'. They will spend more time on documents. The 
questions: 

1. A natural way of making a code base friendly for both human programmers and agents 
  is blend documents and code files. But blending documents and code files often make 
  it less 'natural' to human programmers since we are less interested in actual code. 
  #a_001 mentions Slack, and possibly some other external sources of 
  information. How in general we bring the information all in one place and in such a 
  way that is both narual for human programmers and for coding assistants? 
2. More generally, what future codebases look like? Pure codebases + separate document 
  repo? Add an Agents.md to each directory?

== Future Codebase Characteristics 
=== Repo Becomes Operational Knowledge Base

Repos are not just source-code containers.
```text
Codebase = source code
         + executable tests
         + product specs
         + architecture rules
         + decision history
         + agent instructions
         + generated indexes
         + validation harnesses
         + observability recipes
```

=== Repo Structure
```text
repo/
  AGENTS.md                 # short navigation map, not full knowledge
  ARCHITECTURE.md           # top-level system map
  docs/
    specs/
    design/
    decisions/              # ADRs, Slack-derived decisions
    plans/
      active/
      completed/
    generated/
      db-schema.md
      api-reference.md
    references/
      llms.txt-style external docs
    quality/
    security/
    reliability/
  packages/                 # mainly code
  services/                 # mainly code
  tests/                    # mainly code
```

=== Agents.md/CLAUDE.md
Not one giant `AGENTS.md`. A short `AGENTS.md` as map plus deeper structured docs.
Important directories have their own specialized `AGENTS.md`

A root-level `AGENTS.md` (or `CLAUDE.md`, etc.) carrying global conventions — build commands, testing norms, 
style decisions, "how we do things here." Subdirectory-level files only where a module has genuinely local 
rules that differ from the global ones, e.g. `payments/AGENTS.md` saying "all money is integer cents, never 
floats, see ADR-014." These act like scoped configuration: closest file wins, and most directories need nothing.

=== Centralized External Information
External information MUST be converted into repo-local, and versioned!

=== Documents as a First-Class Engineering Artifact

The right move in future codebases and in vibe coding is to treat documentation as a first-class 
engineering artifact with the same discipline we apply to code.

=== ADRs as the Canonical Capture Mechanism.
*ADRs (Architecture Decision Records)* are invented for: a lightweight, append-only log of "we chose 
X over Y because Z".

Before, writing the ADR was a tax paid for a hypothetical future reader. Now there's an immediate, 
every-day consumer. 

*Let Agent write ADRs*. 

=== Make docs executable or testable where possible.
The deepest answer to "natural for both humans and agents" is to reduce the amount of prose that can drift. 
Schemas instead of data-format descriptions. Executable examples (doctests, example-based tests) instead of 
usage paragraphs. OpenAPI specs instead of endpoint wikis. Property-based test suites as the formal statement 
of requirements. Prose documentation rots because nothing breaks when it's wrong; executable artifacts are 
kept honest by CI, which makes them more trustworthy for humans *and* agents. The article's choice to 
reimplement `p-limit` rather than depend on it is this same instinct: prefer artifacts whose full semantics 
are inspectable and verifiable in-repo.

=== Keeping `docs/` in Sync with `src/`

Put it in `CLAUDE.md`/`AGENTS.md` as a hard rule. Something like:
```text
Definition of done for any change that alters behavior: 
(1) regression test added, 
(2) the governing spec in `specs/` updated in the same change, 
(3) if the fix contradicts a prior design assumption, append a note to the relevant ADR. Never report a 
    task complete without these.
```

=== Enforce coupling mechanically where you can.
Hooks and CI are the backstop for both human and agent forgetfulness. Concretely: a pre-commit or CI check 
that flags any PR touching `src/payments/` without touching `docs/payments/` or `specs/payments/`, requiring 
either a doc change or an explicit `no-doc-impact` label. The label matters — plenty of changes genuinely 
don't affect docs, and a gate without an escape hatch just trains people to game it. The point isn't to 
force a doc edit every time; it's to force a *conscious decision* every time, which is precisely what's missing 
today. Claude Code's hooks can do a softer version: a stop-hook that asks the model "did this session change 
behavior? if so, were docs updated?" before the session ends.

=== Run a drift auditor as a background agent.
This is the genuinely new capability that didn't exist in the stone age. A scheduled job — nightly or weekly — 
that takes the commits since its last run, reads the diffs, reads the corresponding docs, and answers: 
"does the documentation still accurately describe this code?" Where it finds drift, it opens a PR with 
proposed doc updates, which you review in two minutes over coffee. This reframes the problem completely: 
instead of needing sync to be maintained *transactionally* (every change updates docs atomically — hard), 
you only need it maintained *eventually* with a bounded staleness window (much easier). Reconciliation loops 
are how distributed systems handle exactly this kind of consistency problem, and a codebase plus its docs 
is a distributed system in the relevant sense.

=== Mine the transcripts — the knowledge already exists in writing.
Here's something underappreciated about your bug-fixing workflow: those "quite a few rounds of interactions 
with my tests and feedbacks" *are* the documentation, in raw form. The conversation contains the symptom, 
the false leads, the root cause, and the fix rationale — better material than most postmortems. It's just 
trapped in a chat log. So the ritual to build isn't "remember to write a doc," it's a one-liner at session 
end: "distill this session into a bug note: symptom, root cause, fix, and any invariant we discovered; file 
it and update affected specs." Even better, make it a hook or a slash command so it's a keystroke, not a 
sentence. The general principle: never ask a human to *author* documentation post-hoc; ask them to *approve* 
documentation the agent derives from work that already happened.

=== Shrink the surface that can drift.
Every paragraph of prose describing behavior is a sync liability. The durable artifact from a bug fix is the 
regression test — it can't drift, because CI executes it. So push as much "documentation" as possible into 
forms that are checked: the test (with a comment linking the incident), the schema, the type signature, the 
assertion. Reserve prose for the two things code can't express: *intent* ("this module exists to enforce X") 
and *rationale* ("we rejected approach Y because Z"). Intent and rationale drift much more slowly than 
behavioral descriptions — they're invalidated by re-decisions, not by refactors — so the prose that remains 
is naturally more stable. A lot of perceived doc-drift pain comes from docs that describe *what the code does*, 
which is exactly the content that should be derived or tested, not hand-maintained.

=== Accept asymmetric trust and make staleness visible. 
Even with all of the above, perfect sync is unachievable, so the last defense is epistemic honesty in the docs 
themselves. Two cheap conventions help a lot. First, freshness metadata: each spec carries a `last-verified: 
<commit-hash>` line, updated whenever someone (or the auditor agent) confirms it still matches reality — now 
staleness is *queryable* rather than invisible. Second, a reading discipline for agents, written into the context 
file: "specs describe intent; code is ground truth; when they conflict, flag the conflict rather than silently 
trusting either." This matters because the failure that actually burns you isn't a stale doc — it's a stale 
doc *trusted blindly*, by you or by the agent. A doc system that knows its own uncertainty degrades gracefully; 
one that presents everything with equal confidence degrades catastrophically.

If I had to compress all this: stop trying to make sync a matter of discipline and make it a matter of architecture. 
Transactional coupling where it's cheap (definition-of-done rules, CI gates), eventual consistency where it's not 
(auditor agents, reconciliation PRs), drift-proof artifacts wherever possible (tests over prose), and visible staleness 
for whatever prose remains. Your current workflow is actually very close — the spec-first habit and the "review 
my spec before implementing" step are the hard parts that most people don't do. What's missing is just the closing 
of the loop, and the lesson from your own experience is that the loop won't be closed by resolution. It has to be 
closed by machinery.

=== Docs as First-Class Objects
(From ChatGPT)

The way out is not “write better docs.” The way out is to treat docs as *first-class change artifacts* with the 
same lifecycle as code, tests, migrations, and API contracts.

A code change should not be considered complete unless the system has answered:

```text
What knowledge changed?
Which docs/specs/ADRs/tests are affected?
Which docs were updated?
Which docs are now stale?
What was intentionally left undocumented?
```

This should become part of the development protocol.

=== Three Kinds of Docs

Not all docs need the same sync strategy. I would separate them into three classes.

*1. Normative Docs*

These define what must be true.

Examples:

```text
product specs
API contracts
schema contracts
security rules
permission models
business rules
invariants
architecture decisions
```

These must be kept tightly in sync with code. If they drift, the system becomes dangerous.

For these, you want strict traceability:

```text
spec section -> implementation files -> tests -> behavior
```

Example:

```md
## Requirement R-023: Users cannot delete published metrics

Implementation:
- src/metrics/delete.go
- src/metrics/permissions.go

Tests:
- tests/metrics/delete_published_metric_test.go

Status:
- implemented
- verified

Last verified:
- 2026-06-10
```

The important point is that the spec is not just prose. It has anchors.

*2. Explanatory Docs*

These explain how or why the system works.

Examples:

```text
implementation notes
module overviews
developer guides
architecture walkthroughs
debugging guides
```

These are useful, but they do not need to block every commit. They should be checked when nearby code changes.

For example, if files under `src/search/` changed, the assistant should inspect:

```text
docs/implementation/search.md
src/search/AGENTS.md
docs/design-docs/search-ranking.md
```

and ask whether they still match.

*3. Historical Docs*

These record what happened.

Examples:

```text
ADRs
bug postmortems
design discussions
release notes
migration notes
```

These do not need to be constantly updated. They are append-only or mostly append-only.

A bug fix may produce:

```text
docs/bugs/2026-06-10-metric-keyword-tokenization.md
docs/decisions/2026-06-10-normalize-keywords-before-indexing.md
```

This kind of documentation is not about current truth only. It is about preserving reasoning.

=== The Mistake to Avoid

The common mistake is to ask agents:

```text
Please update the docs.
```

That is too vague.

A better instruction is:

```text
Before finishing, inspect the diff and produce a documentation impact report:
1. Which requirements/specs are affected?
2. Which docs are now stale?
3. Which docs were updated?
4. Which new ADR/implementation note/bug note should be added?
5. Which tests verify the updated behavior?
```

This turns doc maintenance from a memory task into a checklist.

=== A Practical Workflow

```text
1. Draft spec
2. Agent reviews spec
3. Agent creates implementation plan
4. Agent implements
5. Agent updates tests
6. Agent produces doc-impact report
7. Agent updates affected docs
8. Agent writes completion report
```

The key addition is step 6.

The assistant should not directly jump from implementation to “done.” It should pause at:

```text
What did I change semantically?
```

Not just:

```text
What files did I edit?
```

Because docs track semantic changes, not textual changes.

=== Add a `CHANGELOG_OF_KNOWLEDGE.md` Concept

For your SemOS-style thinking, I would introduce something like a Knowledge Delta.

Every meaningful change should produce a small structured record:

```yaml
knowledge_delta:
  change_type: bug_fix
  affected_area: metric keyword extraction
  behavioral_change: >
    Keywords are now rejected if they contain long sentence-like phrases.
  affected_specs:
    - docs/specs/topic-extraction.md
  affected_tests:
    - tests/topic_keywords_test.go
  affected_docs_updated:
    - docs/implementation/topic-extraction.md
  adr_needed: false
  bug_note_added:
    - docs/bugs/2026-06-10-sentence-keyword-extraction.md
```

This is very useful because it creates an intermediate object between code and docs.

The agent can reason from:

```text
git diff -> knowledge delta -> docs/tests/ADRs to update
```

Instead of trying to directly infer:

```text
git diff -> all necessary documentation changes
```

=== Future Repositories Need “Documentation Impact Analysis”

I think future agent-friendly repos will have a command like:

```bash
make doc-check
```

or:

```bash
agent doc-impact
```

It would inspect:

```text
git diff
changed source files
changed tests
linked specs
nearby AGENTS.md files
doc ownership metadata
```

and produce:

```text
Potential stale docs:
- docs/specs/search-ranking.md
  Reason: src/search/rank.go changed ranking formula

- docs/implementation/search.md
  Reason: new recency boost parameter added

Missing ADR:
- Change modifies architecture-level ranking behavior
```

This does not need to be perfect. Even a noisy first pass is useful because it reminds the human and agent what knowledge may have changed.

=== Use Links, not Duplication

Another way out is to reduce the amount of prose that must be synchronized.

Bad:

```md
The search system uses cosine similarity, BM25, recency, and diversity penalty.
```

Then the code has:

```go
score := 0.5*cosine + 0.3*bm25 + 0.15*recency - 0.05*diversity
```

This will drift.

Better:

```md
The ranking formula is defined in:
- src/search/ranking.go
- tests/search/ranking_formula_test.go

Conceptually, it combines semantic similarity, lexical relevance, freshness, and diversity.
```

The doc explains intent. The exact formula is either generated from code or referenced.

So the rule should be:

```text
Docs should explain intent, invariants, rationale, and examples.
Code/tests should own exact executable behavior.
Generated docs should expose exact signatures, schemas, formulas, and APIs.
```

Do not manually duplicate low-level facts unless necessary.

=== Generated Docs Should Be More Common

Some docs should not be manually maintained at all.

Generated:

```text
API references
database schema docs
CLI command references
configuration options
OpenAPI docs
protobuf docs
dependency graphs
module maps
test coverage maps
```

Human-written:

```text
why this exists
what the user problem is
what tradeoffs were made
what invariants matter
what bugs taught us
what not to change casually
```

This distinction is crucial.

Humans and agents should write *semantic docs*. Tools should generate *mechanical docs*.

=== Add Doc Ownership Metadata

Each important doc should declare what source areas it depends on.

Example:

```md
---
doc_type: implementation_note
owns:
  - src/search/**
  - tests/search/**
depends_on:
  - docs/specs/search.md
staleness_policy: review_on_change
---
```

Then when `src/search/**` changes, the agent knows this doc may need review.

For specs:

```md
---
doc_type: normative_spec
requirement_ids:
  - SEARCH-RANKING-001
  - SEARCH-RANKING-002
implemented_by:
  - src/search/ranking.go
verified_by:
  - tests/search/ranking_test.go
---
```

This makes docs machine-navigable without making them unnatural for humans.

=== Directory-level `AGENTS.md` can help, but should not carry the burden

A local `AGENTS.md` should not become the full documentation. It should say:

```md
# src/search/AGENTS.md

This directory implements search ranking and retrieval.

Before changing ranking behavior, read:
- docs/specs/search-ranking.md
- docs/design-docs/hybrid-search.md
- docs/decisions/2026-05-22-use-postgres-full-text-search.md

After changing ranking behavior, update or review:
- docs/implementation/search-ranking.md
- tests/search/ranking_test.go
```

This is extremely useful. It tells the agent where the knowledge lives and what must be synchronized.

But `AGENTS.md` should be a *routing layer*, not the knowledge base itself.

=== Bug fixes need their own documentation protocol

Bug fixes are exactly where docs drift most often.

I would require every non-trivial bug fix to produce a small bug note:

```md
# Bug: Sentence-like phrases extracted as keywords

## Symptom
The keyword extractor produced long sentence fragments as keywords.

## Root cause
The prompt constrained keywords but did not define rejection criteria strongly enough.

## Fix
Added explicit validation rules:
- reject keywords containing spaces
- reject sentence-like phrases
- reject boilerplate publication terms

## Regression test
tests/topic_keywords_test.go

## Related docs
- docs/specs/topic-extraction.md
```

Not every bug deserves an ADR. But many bugs deserve a *bug knowledge object*.

For SemOS, this is very important: bugs are not just defects; they are evidence 
that the current model of the system was incomplete.

=== Agent Should Always Finish with a “Knowledge Closure” Section

At the end of every implementation session, the agent should report something like:

```md
## Knowledge closure

Updated:
- src/search/ranking.go
- tests/search/ranking_test.go
- docs/implementation/search-ranking.md

Reviewed but unchanged:
- docs/specs/search-ranking.md
  Reason: behavior still satisfies existing spec

New knowledge captured:
- Added bug note for stale recency scoring edge case

Potential remaining drift:
- docs/product/search-overview.md may need human review because product wording may change
```

This is much better than a generic “done.”

=== A good repo may eventually have these files

```text
repo/
  AGENTS.md
  docs/
    index.md
    specs/
    design/
    decisions/
    implementation/
    bugs/
    generated/
    glossary.md
  src/
    search/
      AGENTS.md
      ranking.go
    metrics/
      AGENTS.md
  tests/
  knowledge/
    deltas/
      2026-06-10-search-ranking-change.yaml
    traceability/
      requirements.yaml
      doc-ownership.yaml
```

The `knowledge/` directory is optional, but conceptually important.

It stores machine-readable coordination artifacts:

```text
requirements -> code -> tests -> docs
source files -> owning docs
change deltas -> affected knowledge
```

This is the part that makes the repo agent-legible.

I would use five mechanisms together:

1. *Docs as contracts, not essays*
   Important docs should have requirement IDs, implementation links, test links, and status.

2. *Doc impact analysis after every code change*
   The agent must inspect what semantic knowledge changed and which docs may be stale.

3. *Knowledge Delta files*
   Every meaningful change creates a small structured summary of what changed and what docs/tests/specs it affects.

4. *Generated mechanical docs*
   Do not manually maintain API/schema/config docs when they can be generated.

5. *Local navigation files*
   Use `AGENTS.md` per major directory to point agents to relevant specs, tests, invariants, and documentation obligations.

=== The deeper point

In pre-AI development, documentation drift was annoying.

In AI-assisted development, documentation drift becomes a *control-plane failure*.

Because the human is increasingly steering through specs, plans, tests, and review 
notes rather than reading every line of code, the docs become the human’s interface 
to the codebase.

So the future codebase needs two synchronized planes:

```text
Implementation plane:
  src/
  tests/
  migrations/
  configs/

Knowledge plane:
  specs/
  design docs/
  ADRs/
  bug notes/
  implementation notes/
  generated references/
  traceability maps/
```

The solution is not to merge these planes into one messy pile. The solution is to 
create *explicit synchronization protocols* between them.

For your own workflow, I would add one standing instruction to Claude Code/Codex:

```text
Before considering the task complete, perform knowledge closure:
- summarize the semantic change
- identify affected specs/docs/ADRs/bug notes
- update required docs
- state which docs were reviewed but unchanged
- state any potential remaining drift
```

That single protocol would probably eliminate a large portion of the doc drift you are seeing.

















== From ChatGPT  
The key shift is: *the repo becomes the operational knowledge base*, not just the 
source-code container.

#a_001 says their `AGENTS.md` is not an encyclopedia; it is a short table 
of contents, while structured `docs/` is the system of record: design docs, product 
specs, execution plans, generated schemas, references, quality/security/reliability 
docs, etc. They also emphasize that Slack/Google Docs/people’s heads must be converted 
into repo-local, versioned artifacts or agents cannot use them reliably.

*Important* External information MUST be converted into repo-local, and versioned!

The repo may look like:
```text
repo/
  AGENTS.md                 # short navigation map, not full knowledge
  ARCHITECTURE.md           # top-level system map
  docs/
    product-specs/
    design-docs/
    decisions/              # ADRs, Slack-derived decisions
    exec-plans/
      active/
      completed/
    generated/
      db-schema.md
      api-reference.md
    references/
      llms.txt-style external docs
    quality/
    security/
    reliability/
  packages/
  services/
  tests/
```

Code directories contain nearby local docs only when they explain that code. 
Global/business/product knowledge should be in a separate root directory such as `docs/`.\*\*

So instead of dumping Slack logs into the repo, you extract durable knowledge from Slack:

```text
docs/decisions/2026-06-10-use-event-sourcing-for-audit-log.md
```

With structure like:

```md
# Decision: Use event sourcing for audit log

## Status
Accepted

## Context
...

## Decision
...

## Consequences
...

## Evidence
- Slack discussion: summarized from #backend, 2026-06-08
- Related PR: ...
- Related spec: ...
```

This makes the information natural for humans because they read clean docs, not chat history. 
It makes it natural for agents because the knowledge is local, versioned, searchable, linked, 
and structured.

=== Future Codebases
Future serious codebases will become *knowledge/code co-repositories*:

```text
Codebase = source code
         + executable tests
         + product specs
         + architecture rules
         + decision history
         + agent instructions
         + generated indexes
         + validation harnesses
         + observability recipes
```

Not “pure codebase + separate document repo.” Separate docs will still exist for human-facing 
material, but the agent-operational truth should live near the code.

Also, not one giant `AGENTS.md`. #a_001 explicitly says that failed because it wastes context, 
rots, and is hard to verify. Their better pattern is a short `AGENTS.md` as map plus deeper 
structured docs.

A good pattern is:

```text
AGENTS.md                  # global map and rules
services/billing/AGENTS.md # local navigation + invariants
services/search/AGENTS.md
docs/index.md              # human + agent doc map
docs/design-docs/index.md
docs/product-specs/index.md
```

Each directory-level `AGENTS.md` should be short and point to:

```md
- Main implementation files
- Tests
- Local architecture constraints
- Relevant product spec
- Relevant design decisions
- Common commands
- Known pitfalls
```

=== Conclusion
The deeper principle is: *do not make agents read more; make them navigate better.*

For SemOS, this maps very naturally to your “explore model”: the repo should expose a virtual 
knowledge filesystem where code, specs, metrics, provisions, decisions, summaries, and execution 
plans are linked objects. The future codebase is less like a folder of code and more like a 
*versioned semantic workspace*.

== Claude
The right move in future codebases and in vibe coding in general isn't "blending documents into 
code" so much as treating documentation as a first-class engineering artifact with the same discipline 
we apply to code.

The key insight from the article is "anything not in the repo doesn't exist." But that doesn't mean 
everything must literally live next to source files. A few patterns are emerging:

=== Decision records as the canonical capture mechanism.
*ADRs (Architecture Decision Records)*

The Slack-discussion problem is old — it predates agents. ADRs (Architecture Decision Records) were 
invented for exactly this: a lightweight, append-only log of "we chose X over Y because Z" living in 
`docs/adr/` or similar. What's changed is the cost-benefit. Before, writing the ADR was a tax paid 
for a hypothetical future reader. Now there's an immediate, every-day consumer: the agent. And 
critically, the agent itself can write the ADR. After a Slack thread settles an architectural debate, 
you paste the thread to your assistant and say "distill this into an ADR and open a PR." The friction 
that killed documentation culture — humans hate writing it — largely disappears when humans only have 
to review it.

=== Docs as a directory, not interleaved prose.
Most teams converging on this keep code files clean and put narrative material in a parallel structure: 
- `docs/` for domain knowledge and design rationale, 
- `specs/` for requirements and acceptance criteria, plus thin per-directory pointers. Human programmers 
  who "are less interested in actual code" (increasingly true for the spec-and-verify workflow) live 
  mostly in those directories; the agent traverses everything. The code files themselves carry only what's 
  locally relevant: doc comments, invariants, links to the governing spec.
- `tests/` for test designs
- `sanity-check/` serving as part of the acceptance tests
- `performance/`
- `reliability/`
- `security/`
- ...

=== Make docs executable or testable where possible.
The deepest answer to "natural for both humans and agents" is to reduce the amount of prose that can drift. 
Schemas instead of data-format descriptions. Executable examples (doctests, example-based tests) instead of 
usage paragraphs. OpenAPI specs instead of endpoint wikis. Property-based test suites as the formal statement 
of requirements. Prose documentation rots because nothing breaks when it's wrong; executable artifacts are 
kept honest by CI, which makes them more trustworthy for humans *and* agents. The article's choice to 
reimplement `p-limit` rather than depend on it is this same instinct: prefer artifacts whose full semantics 
are inspectable and verifiable in-repo.

=== Ingestion pipelines for external sources.
For things that genuinely live elsewhere — Slack, meeting notes, design docs — the pattern is 
summarize-and-commit, not link. A link to a Google Doc is dead weight to an agent (and often to a human 
two years later, after permissions and reorgs). Some teams are starting to automate this: a bot watches 
decision-bearing channels, drafts summaries, and a human approves the commit. The repo becomes the system 
of record; everything else is a staging area.

=== Future Codebases

I'd bet against both extremes you mention. A fully separate document repo recreates the legibility problem — 
it drifts out of sync, and agents working in the code repo can't see it without extra plumbing. Versioning 
docs *with* code is the whole point: when a PR changes behavior, the same PR updates the spec, and the diff 
makes the coupling reviewable.

An `AGENTS.md` in literally every directory is the other failure mode — it fragments context, gets stale, 
and duplicates information. The pattern that seems to be winning is hierarchical and sparse:

A root-level `AGENTS.md` (or `CLAUDE.md`, etc.) carrying global conventions — build commands, testing norms, 
style decisions, "how we do things here." Subdirectory-level files only where a module has genuinely local 
rules that differ from the global ones, e.g. `payments/AGENTS.md` saying "all money is integer cents, never 
floats, see ADR-014." These act like scoped configuration: closest file wins, and most directories need nothing.

Around that skeleton, I'd expect future repos to look roughly like: `src/` staying clean and conventional; 
`docs/` holding domain models, glossaries, and ADRs; `specs/` holding machine-checkable requirements that 
tests are derived from; and CI treating doc-drift as a failure class (e.g., a check that flags PRs changing 
public behavior without touching the corresponding spec). The interesting structural shift is that *specs 
become the primary human-authored artifact and code becomes a derived artifact* — which inverts where review 
attention goes. You review the spec diff and the test diff carefully; the implementation diff gets skimmed 
or trusted to verification.

One more prediction: the "natural for humans" problem gets partially solved by rendering rather than by 
storage. The repo stores everything as plain, versioned, agent-legible text — markdown, schemas, code — and 
humans increasingly consume it through generated views: an agent that answers "why is this module structured 
this way?" by reading the ADRs, auto-generated architecture diagrams, onboarding tours synthesized on demand. 
Humans stop needing the repo layout to be ergonomic for *browsing* because they rarely browse; they query. 
The repo's job is to be complete and truthful, not pretty.

=== Conclusion
So the short version: one repo, docs versioned alongside code but in their own structure, prose minimized 
in favor of executable/checkable artifacts, a sparse hierarchy of agent context files, automated ingestion 
of external decisions, and CI that enforces doc-code coherence. The cultural change is bigger than the 
structural one — documentation stops being a chore humans neglect and becomes the main thing humans produce, 
with agents doing both the transcription and the consumption.

== Keeping `docs/` in Sync with `src/`

One of the challenges is to keep `docs/` in sync with `src/`. As vibe coding evolves, human programmers rely 
more on 'knowledge' (or docs) than the actual code. But this is true only when `docs/` is truly in sync with 
`src/`. In reality, however, this is very difficult to achieve, though much better with coding assistants than 
the pre-AI stone age.

Based on my personal experiences, I often start a new request by drafting a spec doc and ask Claude Code/Codex 
to review the spec, add missing pieces, correct the incorrect/ambiguous, etc. Then the code assistant implement 
the spec, faithfully I hope. Even when it finishes, I often remind Claude Code/Codex to update the doc, or 
write an implementation doc.

Things get more complicated as the project moves on. Bugs are found, giving them to Claude Code/Codex, possibly 
with quite a few round of interactions with my tests and feedbacks. After bugs being fixed, I often forgot ask 
Claude Code/Codex to update the related docs, or write something about the bugs, the possible ADRs, etc.

I believe this happens not only to me. I guess it happens to nearly every non-trivial projects as well.

(From Claude)
The sync mechanism today is *human memory at the worst possible moment*. The end of a debugging session is 
exactly when you're cognitively depleted, relieved the thing finally works, and most likely to skip the 
bookkeeping. Any solution that depends on you remembering to say "now update the docs" will fail at roughly 
the rate you're experiencing. So the ways out all share one shape — remove discretion from the loop — but 
they apply at different layers.

=== Make doc updates part of the agent's standing orders, not your prompts.
The simplest fix is the one most people skip: put it in `CLAUDE.md`/`AGENTS.md` as a hard rule. Something 
like:
```text
Definition of done for any change that alters behavior: 
(1) regression test added, 
(2) the governing spec in `specs/` updated in the same change, 
(3) if the fix contradicts a prior design assumption, append a note to the relevant ADR. Never report a 
    task complete without these.
```

This moves the obligation from your working memory into the agent's context, which — unlike you at 11pm — 
reads its instructions fresh on every task. It's imperfect (agents under long sessions drift from their 
instructions too), but it converts "I forgot to ask" into "the agent occasionally forgets despite being told," 
which is a much better baseline and is catchable by the next layer.

=== Enforce coupling mechanically where you can.
Hooks and CI are the backstop for both human and agent forgetfulness. Concretely: a pre-commit or CI check 
that flags any PR touching `src/payments/` without touching `docs/payments/` or `specs/payments/`, requiring 
either a doc change or an explicit `no-doc-impact` label. The label matters — plenty of changes genuinely 
don't affect docs, and a gate without an escape hatch just trains people to game it. The point isn't to 
force a doc edit every time; it's to force a *conscious decision* every time, which is precisely what's missing 
today. Claude Code's hooks can do a softer version: a stop-hook that asks the model "did this session change 
behavior? if so, were docs updated?" before the session ends.

=== Run a drift auditor as a background agent.
This is the genuinely new capability that didn't exist in the stone age. A scheduled job — nightly or weekly — 
that takes the commits since its last run, reads the diffs, reads the corresponding docs, and answers: 
"does the documentation still accurately describe this code?" Where it finds drift, it opens a PR with 
proposed doc updates, which you review in two minutes over coffee. This reframes the problem completely: 
instead of needing sync to be maintained *transactionally* (every change updates docs atomically — hard), 
you only need it maintained *eventually* with a bounded staleness window (much easier). Reconciliation loops 
are how distributed systems handle exactly this kind of consistency problem, and a codebase plus its docs 
is a distributed system in the relevant sense.

=== Mine the transcripts — the knowledge already exists in writing.
Here's something underappreciated about your bug-fixing workflow: those "quite a few rounds of interactions 
with my tests and feedbacks" *are* the documentation, in raw form. The conversation contains the symptom, 
the false leads, the root cause, and the fix rationale — better material than most postmortems. It's just 
trapped in a chat log. So the ritual to build isn't "remember to write a doc," it's a one-liner at session 
end: "distill this session into a bug note: symptom, root cause, fix, and any invariant we discovered; file 
it and update affected specs." Even better, make it a hook or a slash command so it's a keystroke, not a 
sentence. The general principle: never ask a human to *author* documentation post-hoc; ask them to *approve* 
documentation the agent derives from work that already happened.

=== Shrink the surface that can drift.
Every paragraph of prose describing behavior is a sync liability. The durable artifact from a bug fix is the 
regression test — it can't drift, because CI executes it. So push as much "documentation" as possible into 
forms that are checked: the test (with a comment linking the incident), the schema, the type signature, the 
assertion. Reserve prose for the two things code can't express: *intent* ("this module exists to enforce X") 
and *rationale* ("we rejected approach Y because Z"). Intent and rationale drift much more slowly than 
behavioral descriptions — they're invalidated by re-decisions, not by refactors — so the prose that remains 
is naturally more stable. A lot of perceived doc-drift pain comes from docs that describe *what the code does*, 
which is exactly the content that should be derived or tested, not hand-maintained.

=== Accept asymmetric trust and make staleness visible. 
Even with all of the above, perfect sync is unachievable, so the last defense is epistemic honesty in the docs 
themselves. Two cheap conventions help a lot. First, freshness metadata: each spec carries a `last-verified: 
<commit-hash>` line, updated whenever someone (or the auditor agent) confirms it still matches reality — now 
staleness is *queryable* rather than invisible. Second, a reading discipline for agents, written into the context 
file: "specs describe intent; code is ground truth; when they conflict, flag the conflict rather than silently 
trusting either." This matters because the failure that actually burns you isn't a stale doc — it's a stale 
doc *trusted blindly*, by you or by the agent. A doc system that knows its own uncertainty degrades gracefully; 
one that presents everything with equal confidence degrades catastrophically.

If I had to compress all this: stop trying to make sync a matter of discipline and make it a matter of architecture. 
Transactional coupling where it's cheap (definition-of-done rules, CI gates), eventual consistency where it's not 
(auditor agents, reconciliation PRs), drift-proof artifacts wherever possible (tests over prose), and visible staleness 
for whatever prose remains. Your current workflow is actually very close — the spec-first habit and the "review 
my spec before implementing" step are the hard parts that most people don't do. What's missing is just the closing 
of the loop, and the lesson from your own experience is that the loop won't be closed by resolution. It has to be 
closed by machinery.

=== Docs as First-Class Objects
(From ChatGPT)

The way out is not “write better docs.” The way out is to treat docs as *first-class change artifacts* with the 
same lifecycle as code, tests, migrations, and API contracts.

A code change should not be considered complete unless the system has answered:

```text
What knowledge changed?
Which docs/specs/ADRs/tests are affected?
Which docs were updated?
Which docs are now stale?
What was intentionally left undocumented?
```

This should become part of the development protocol.

=== Three Kinds of Docs

Not all docs need the same sync strategy. I would separate them into three classes.

*1. Normative Docs*

These define what must be true.

Examples:

```text
product specs
API contracts
schema contracts
security rules
permission models
business rules
invariants
architecture decisions
```

These must be kept tightly in sync with code. If they drift, the system becomes dangerous.

For these, you want strict traceability:

```text
spec section -> implementation files -> tests -> behavior
```

Example:

```md
## Requirement R-023: Users cannot delete published metrics

Implementation:
- src/metrics/delete.go
- src/metrics/permissions.go

Tests:
- tests/metrics/delete_published_metric_test.go

Status:
- implemented
- verified

Last verified:
- 2026-06-10
```

The important point is that the spec is not just prose. It has anchors.

*2. Explanatory Docs*

These explain how or why the system works.

Examples:

```text
implementation notes
module overviews
developer guides
architecture walkthroughs
debugging guides
```

These are useful, but they do not need to block every commit. They should be checked when nearby code changes.

For example, if files under `src/search/` changed, the assistant should inspect:

```text
docs/implementation/search.md
src/search/AGENTS.md
docs/design-docs/search-ranking.md
```

and ask whether they still match.

*3. Historical Docs*

These record what happened.

Examples:

```text
ADRs
bug postmortems
design discussions
release notes
migration notes
```

These do not need to be constantly updated. They are append-only or mostly append-only.

A bug fix may produce:

```text
docs/bugs/2026-06-10-metric-keyword-tokenization.md
docs/decisions/2026-06-10-normalize-keywords-before-indexing.md
```

This kind of documentation is not about current truth only. It is about preserving reasoning.

=== The Mistake to Avoid

The common mistake is to ask agents:

```text
Please update the docs.
```

That is too vague.

A better instruction is:

```text
Before finishing, inspect the diff and produce a documentation impact report:
1. Which requirements/specs are affected?
2. Which docs are now stale?
3. Which docs were updated?
4. Which new ADR/implementation note/bug note should be added?
5. Which tests verify the updated behavior?
```

This turns doc maintenance from a memory task into a checklist.

=== A Practical Workflow

```text
1. Draft spec
2. Agent reviews spec
3. Agent creates implementation plan
4. Agent implements
5. Agent updates tests
6. Agent produces doc-impact report
7. Agent updates affected docs
8. Agent writes completion report
```

The key addition is step 6.

The assistant should not directly jump from implementation to “done.” It should pause at:

```text
What did I change semantically?
```

Not just:

```text
What files did I edit?
```

Because docs track semantic changes, not textual changes.

=== Add a `CHANGELOG_OF_KNOWLEDGE.md` Concept

For your SemOS-style thinking, I would introduce something like a Knowledge Delta.

Every meaningful change should produce a small structured record:

```yaml
knowledge_delta:
  change_type: bug_fix
  affected_area: metric keyword extraction
  behavioral_change: >
    Keywords are now rejected if they contain long sentence-like phrases.
  affected_specs:
    - docs/specs/topic-extraction.md
  affected_tests:
    - tests/topic_keywords_test.go
  affected_docs_updated:
    - docs/implementation/topic-extraction.md
  adr_needed: false
  bug_note_added:
    - docs/bugs/2026-06-10-sentence-keyword-extraction.md
```

This is very useful because it creates an intermediate object between code and docs.

The agent can reason from:

```text
git diff -> knowledge delta -> docs/tests/ADRs to update
```

Instead of trying to directly infer:

```text
git diff -> all necessary documentation changes
```

=== Future Repositories Need “Documentation Impact Analysis”

I think future agent-friendly repos will have a command like:

```bash
make doc-check
```

or:

```bash
agent doc-impact
```

It would inspect:

```text
git diff
changed source files
changed tests
linked specs
nearby AGENTS.md files
doc ownership metadata
```

and produce:

```text
Potential stale docs:
- docs/specs/search-ranking.md
  Reason: src/search/rank.go changed ranking formula

- docs/implementation/search.md
  Reason: new recency boost parameter added

Missing ADR:
- Change modifies architecture-level ranking behavior
```

This does not need to be perfect. Even a noisy first pass is useful because it reminds the human and agent what knowledge may have changed.

=== Use Links, not Duplication

Another way out is to reduce the amount of prose that must be synchronized.

Bad:

```md
The search system uses cosine similarity, BM25, recency, and diversity penalty.
```

Then the code has:

```go
score := 0.5*cosine + 0.3*bm25 + 0.15*recency - 0.05*diversity
```

This will drift.

Better:

```md
The ranking formula is defined in:
- src/search/ranking.go
- tests/search/ranking_formula_test.go

Conceptually, it combines semantic similarity, lexical relevance, freshness, and diversity.
```

The doc explains intent. The exact formula is either generated from code or referenced.

So the rule should be:

```text
Docs should explain intent, invariants, rationale, and examples.
Code/tests should own exact executable behavior.
Generated docs should expose exact signatures, schemas, formulas, and APIs.
```

Do not manually duplicate low-level facts unless necessary.

=== Generated Docs Should Be More Common

Some docs should not be manually maintained at all.

Generated:

```text
API references
database schema docs
CLI command references
configuration options
OpenAPI docs
protobuf docs
dependency graphs
module maps
test coverage maps
```

Human-written:

```text
why this exists
what the user problem is
what tradeoffs were made
what invariants matter
what bugs taught us
what not to change casually
```

This distinction is crucial.

Humans and agents should write *semantic docs*. Tools should generate *mechanical docs*.

=== Add Doc Ownership Metadata

Each important doc should declare what source areas it depends on.

Example:

```md
---
doc_type: implementation_note
owns:
  - src/search/**
  - tests/search/**
depends_on:
  - docs/specs/search.md
staleness_policy: review_on_change
---
```

Then when `src/search/**` changes, the agent knows this doc may need review.

For specs:

```md
---
doc_type: normative_spec
requirement_ids:
  - SEARCH-RANKING-001
  - SEARCH-RANKING-002
implemented_by:
  - src/search/ranking.go
verified_by:
  - tests/search/ranking_test.go
---
```

This makes docs machine-navigable without making them unnatural for humans.

=== Directory-level `AGENTS.md` can help, but should not carry the burden

A local `AGENTS.md` should not become the full documentation. It should say:

```md
# src/search/AGENTS.md

This directory implements search ranking and retrieval.

Before changing ranking behavior, read:
- docs/specs/search-ranking.md
- docs/design-docs/hybrid-search.md
- docs/decisions/2026-05-22-use-postgres-full-text-search.md

After changing ranking behavior, update or review:
- docs/implementation/search-ranking.md
- tests/search/ranking_test.go
```

This is extremely useful. It tells the agent where the knowledge lives and what must be synchronized.

But `AGENTS.md` should be a *routing layer*, not the knowledge base itself.

=== Bug fixes need their own documentation protocol

Bug fixes are exactly where docs drift most often.

I would require every non-trivial bug fix to produce a small bug note:

```md
# Bug: Sentence-like phrases extracted as keywords

## Symptom
The keyword extractor produced long sentence fragments as keywords.

## Root cause
The prompt constrained keywords but did not define rejection criteria strongly enough.

## Fix
Added explicit validation rules:
- reject keywords containing spaces
- reject sentence-like phrases
- reject boilerplate publication terms

## Regression test
tests/topic_keywords_test.go

## Related docs
- docs/specs/topic-extraction.md
```

Not every bug deserves an ADR. But many bugs deserve a *bug knowledge object*.

For SemOS, this is very important: bugs are not just defects; they are evidence 
that the current model of the system was incomplete.

=== Agent Should Always Finish with a “Knowledge Closure” Section

At the end of every implementation session, the agent should report something like:

```md
## Knowledge closure

Updated:
- src/search/ranking.go
- tests/search/ranking_test.go
- docs/implementation/search-ranking.md

Reviewed but unchanged:
- docs/specs/search-ranking.md
  Reason: behavior still satisfies existing spec

New knowledge captured:
- Added bug note for stale recency scoring edge case

Potential remaining drift:
- docs/product/search-overview.md may need human review because product wording may change
```

This is much better than a generic “done.”

=== A good repo may eventually have these files

```text
repo/
  AGENTS.md
  docs/
    index.md
    specs/
    design/
    decisions/
    implementation/
    bugs/
    generated/
    glossary.md
  src/
    search/
      AGENTS.md
      ranking.go
    metrics/
      AGENTS.md
  tests/
  knowledge/
    deltas/
      2026-06-10-search-ranking-change.yaml
    traceability/
      requirements.yaml
      doc-ownership.yaml
```

The `knowledge/` directory is optional, but conceptually important.

It stores machine-readable coordination artifacts:

```text
requirements -> code -> tests -> docs
source files -> owning docs
change deltas -> affected knowledge
```

This is the part that makes the repo agent-legible.

I would use five mechanisms together:

1. *Docs as contracts, not essays*
   Important docs should have requirement IDs, implementation links, test links, and status.

2. *Doc impact analysis after every code change*
   The agent must inspect what semantic knowledge changed and which docs may be stale.

3. *Knowledge Delta files*
   Every meaningful change creates a small structured summary of what changed and what docs/tests/specs it affects.

4. *Generated mechanical docs*
   Do not manually maintain API/schema/config docs when they can be generated.

5. *Local navigation files*
   Use `AGENTS.md` per major directory to point agents to relevant specs, tests, invariants, and documentation obligations.

=== The deeper point

In pre-AI development, documentation drift was annoying.

In AI-assisted development, documentation drift becomes a *control-plane failure*.

Because the human is increasingly steering through specs, plans, tests, and review 
notes rather than reading every line of code, the docs become the human’s interface 
to the codebase.

So the future codebase needs two synchronized planes:

```text
Implementation plane:
  src/
  tests/
  migrations/
  configs/

Knowledge plane:
  specs/
  design docs/
  ADRs/
  bug notes/
  implementation notes/
  generated references/
  traceability maps/
```

The solution is not to merge these planes into one messy pile. The solution is to 
create *explicit synchronization protocols* between them.

For your own workflow, I would add one standing instruction to Claude Code/Codex:

```text
Before considering the task complete, perform knowledge closure:
- summarize the semantic change
- identify affected specs/docs/ADRs/bug notes
- update required docs
- state which docs were reviewed but unchanged
- state any potential remaining drift
```

That single protocol would probably eliminate a large portion of the doc drift you are seeing.


== References
[1] "Harness engineering: leveraging Codex in an agent-first ..."
https://openai.com/index/harness-engineering/?utm_source=chatgpt.com 

