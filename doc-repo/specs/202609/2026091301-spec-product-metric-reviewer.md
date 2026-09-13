---
title: Product Metric Reviewer — Capability Specification
language: en
format: markdown
version: 1.0
status: current
author: Not specified
owner: Not specified
audience: Engineers and non-engineers who need to understand what Product Metric Reviewer is, why it exists, how it decides what belongs to a product, and what its current limits are — without reading code
create-time: 2026-09-13T07:19:17-05:00
last-modify-time: 2026-09-13T07:19:17-05:00
keywords: Product Metric Reviewer, PMR, product metrics, metric coverage, scope profile, scope tree, part hierarchy, lifecycle aspects, coverage gaps, coverage report, document-first retrieval, direct-match retrieval, hybrid search, retrieval precision, capability specification, openspec, product-scope-profile, product-artifact-retrieval, product-metric-review-runs, product-metric-reviewer-page
---

# Product Metric Reviewer — Capability Specification

## 1. What this document is

This is a plain-language description of **Product Metric Reviewer**: what it is, why it was
built, how it decides what counts as "belonging to" a product, and — honestly — what it does
and does not do well today. It is written so that someone without a coding background can
understand the capability on its own terms, without reading source code.

This is a companion to, not a replacement for, two other documents:

- If you want to **operate the page** (start a review, read results, curate a product's
  breakdown), see the user manual — `doc-repo/user-manuals/product-metric-reviewer-v1.1-en.md`.
- If you want the **engineering-level requirements** this capability was built and tested
  against, see the openspec change referenced in [Section 7](#7-references).

## 2. What it is, in one sentence

Product Metric Reviewer answers one question — *which measurable requirements apply to this
product?* — by building a structured picture of the product first, and then finding every
metric attached to any piece of that picture, wherever in the knowledge base it lives.

"Metric" here means a measurable requirement: a threshold, a limit, a target value, a test
result — the kind of thing a specification or a standard states as a number with a unit or a
pass/fail condition attached.

## 3. The problem it solves

Searching a knowledge base for a product's name — "ventilator," say — sounds like it should
find every requirement that applies to a ventilator. It doesn't, for two reasons.

**Most requirements are attached to a part, not to the product.** A display's luminance limit,
a battery's endurance requirement, a power supply's leakage-current limit — none of those
mention the word "ventilator" anywhere near them. They are requirements on the display, the
battery, the power supply. A product is really a nested structure — product, made of modules,
made of parts, sometimes made of smaller parts still — and a name search only ever finds the
top of that structure, never the parts hanging off it.

**Many requirements describe a condition the product must satisfy, not a part of it.** A
storage-temperature limit, a drop-test requirement, a packaging specification — these are about
the product, but their subject is a condition (how it's stored, how it's transported, how it's
disposed of), not a named component. A name search misses these for the same reason: the
product's name doesn't have to appear anywhere near the requirement text.

Everything needed to answer the real question — what does this product's structure look like,
and what requirements attach to each piece of it — already exists scattered across a knowledge
base: records of which documents are *about* which products and under what relationship,
identities for each requirement's real-world subject, a reconciled graph of how parts relate to
the products and to each other, and a search system that can look things up both by wording and
by meaning. Product Metric Reviewer's job is to assemble those pieces into one answer, instead
of leaving a person to hunt for them one at a time.

## 4. How it decides what belongs to a product

### 4.1 It builds a picture of the product first

Before Product Metric Reviewer looks for a single metric, it builds and saves a **scope
profile** — a reusable, structured description of the product:

- the **product** itself, at the root;
- its **parts and modules**, nested as deep as the real breakdown goes (a part can itself have
  parts);
- a fixed set of **lifecycle aspects** attached to the product as a whole — storage, transport,
  maintenance, the environment it operates in, safety, packaging, disposal, and similar
  conditions a product must satisfy across its life, independent of any single part.

This profile is built in three passes, none of which need a person to trigger them:

1. **Propose.** A single pass of an AI model reads the product's name and description and
   proposes a first-draft breakdown — its likely modules and parts.
2. **Ground.** Every proposed part is checked against identities the knowledge base already
   tracks, so that later matching can work by *identity* — this specific, already-reconciled
   thing — rather than by spelling out the same words differently in different documents. A
   part that doesn't match anything known stays in the tree and is matched by its text alone
   from then on.
3. **Expand.** The tree is then extended using part-of-a-whole relationships the knowledge base
   already records elsewhere — which can add real parts the first pass never named, because
   they were never described in the product's own name or description.

A person can review this proposed breakdown afterward — accept it, reject a part that doesn't
belong, correct a label, or add something the automatic passes missed — but nothing in the
process requires that review to happen before results can be produced.

### 4.2 It looks for requirements two independent ways

Once the picture exists, Product Metric Reviewer looks for matching requirements along two
independent paths, then combines what each one finds:

- **By document.** Every document that appears to be *about* the product — because it names the
  product itself, because it names one of the product's parts, or because it covers one of the
  product's lifecycle conditions — contributes every requirement found inside it. Documents that
  look like governing standards or specifications are ranked to the front of this list, but a
  document is never excluded just because it isn't one.
- **By subject.** Independently of which document it's in, every requirement whose own subject
  matches a part of the product — by identity where one exists, by close wording or close
  meaning otherwise — is found directly. This is what catches a figure like a display's
  luminance limit sitting in a component supplier's own datasheet that never mentions the parent
  product's name at all.

A requirement found by only one path, or by both, appears exactly once in the final answer, and
keeps a record of every way it was found.

### 4.3 Every result is labeled with what it actually matched

Each requirement that comes back is labeled with exactly one of four tiers, describing what it
matched:

| Label | What it means |
|---|---|
| Direct | The requirement's subject is the product itself. |
| Part | The requirement's subject is one of the product's parts or modules. |
| Aspect | The requirement's subject or context is one of the lifecycle conditions (storage, safety, and so on). |
| Document only | The requirement matched no specific part of the product, but it was found in a document that is about the product as a whole. |

A requirement whose subject is a specific part keeps that label even when the only reason it
surfaced was that its document happened to be in scope — the label always reflects the
strongest thing it actually matched, not just the path that found it.

### 4.4 It reports what it found — and what it didn't

Each time Product Metric Reviewer is run, it produces one **run**: the full list of results plus
a **coverage report**. The report includes a table of how many requirements and documents
matched each part of the product's structure, and — often the more useful half of the answer —
a **gap list**: every accepted part of the product that matched zero requirements. A gap can
mean a genuine hole in the available documents, or it can mean the part was never tied to a
recognized identity; the report shows which is more likely for each gap.

Runs are kept, not overwritten. A product's breakdown can be edited and re-run at any time, and
the report for a later run shows what's new, what's gone, and what moved to a different label
compared to the run before it — while every earlier run still shows exactly what it showed when
it ran.

## 5. Current status

As of 2026-09-13, this capability is fully built and its full task list (38 items, spanning the
data model, the profile-building passes, the two-path retrieval, run and report persistence, and
the page itself) is complete, including end-to-end verification against a real, populated
knowledge base — not just simulated test data.

That end-to-end verification found and fixed two real defects along the way, both now confirmed
fixed:

- A database query used while scoring documents was written in a way that made **every review
  run fail outright**, regardless of what data existed — a run would fail in under a second, no
  matter the product. This has been fixed.
- The self-service "start a review" flow — the page's normal, no-setup way to begin — built a
  product's breakdown correctly but skipped the step that lets any of its parts actually
  participate in matching, so a review started this way could **never** return a part-level
  result, only whole-product or lifecycle-condition results. This has been fixed; a review
  started through the self-service flow now can return part-level results.

Both fixes were verified against a real product profile (a blood-pressure monitor, matching an
actual set of documents already in the knowledge base): the run produced part-level results,
a lifecycle-condition result, and a correctly populated gap list.

## 6. A known, honest limitation

The same verification also surfaced a genuine limitation that is **not** fixed, and is unlikely
to be fixed by a small adjustment.

For a part with a very short, generic name — a two-character label meaning something like "main
unit," for example — the "by subject" matching path can occasionally attribute a requirement
from a **completely different kind of product** to that part. This was confirmed with real
measurements, not just observed anecdotally: for one such generic label, the requirements that
were genuinely about the right product and the requirements that were about an unrelated product
turned out to be mathematically intermixed, with no line that could be drawn between them
without also losing real matches. A partial safeguard was added that measurably reduces the
weakest, most tenuous matches, but it does not resolve this for a label generic enough to have
this problem in the first place.

In practice, this means: **a result being returned is not, by itself, proof that it is correct.**
Every result carries the document it came from, the exact place in that document, and a
plain-language reason it was included — and a person should look at that evidence before relying
on a result, the same way they would for any assistive retrieval tool. This limitation, and the
measurements behind it, are recorded in full in the bug report referenced in
[Section 7](#7-references), including the specific direction a real fix would need to take.

## 7. References

This document summarizes, in plain language, the following source documents. Each is more
detailed and more technical than this one:

- **The engineering proposal** — why this capability was built and the architecture it's built
  on: `ChenWeb/openspec/changes/archive/2026-09-13-product-metric-reviewer/proposal.md` (or, if
  not yet archived at the time of reading, `ChenWeb/openspec/changes/product-metric-reviewer/
  proposal.md`).
- **The requirements it was built and tested against** — four detailed specifications, one each
  for the product breakdown and its curation, the two-path matching and labeling rules, the
  run/report/re-run behavior, and the page itself: `.../product-metric-reviewer/specs/
  product-scope-profile/spec.md`, `.../product-artifact-retrieval/spec.md`,
  `.../product-metric-review-runs/spec.md`, `.../product-metric-reviewer-page/spec.md`.
  (Same archive-path note as above.)
- **The full task list and its completion record**: `.../product-metric-reviewer/tasks.md`.
- **The implementation notes**, including what the app assumes about the data it reads and what
  was intentionally left undocumented: `.../product-metric-reviewer/notes.md`.
- **The known-limitation bug report**, with the full measured evidence behind
  [Section 6](#6-a-known-honest-limitation):
  `KnowledgeStore/doc-repo/bugs/202609/2026091301-bug-product-metric-reviewer-e2e-crash-curation-gap-and-retrieval-precision.md`.
- **The operating manual**, for step-by-step instructions on using the page:
  `KnowledgeStore/doc-repo/user-manuals/product-metric-reviewer-v1.1-en.md`.

## Change Log

| Version | Timestamp | Responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.0 | 2026-09-13T07:19:17-05:00 | Not specified | Initial capability specification, written after the openspec change's task list reached 38/38 complete | Documented, in plain language and without code references, what Product Metric Reviewer is, the problem it solves, how it builds a product's scope profile, how its two-path matching and tiering decide what counts, its report and gap list, its current fully-implemented and end-to-end-verified status (including two defects found and fixed during verification), and one honest, still-open limitation around generic part-name matching precision, with full references back to the openspec proposal/specs/tasks/notes and the underlying bug report. |
