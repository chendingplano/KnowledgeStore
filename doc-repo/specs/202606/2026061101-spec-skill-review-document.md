# 1. 'Review Document' — Skill Role (Superseded for Production Design)

- DocID: `doc-2026061101`
- **Status:** Superseded — production design moved to ADR 2026061801
- **Date:** 2026-06-11
- **Deciders:** ChenWeb
- **Tags:** Skill

> **NOTE (2026-06-21):** This document originally proposed implementing document
> review as a Claude Code *coordinator skill*. That decision was reconsidered in
> [4] **ADR 2026061801**, which decided to build the production review service as
> a **Go module** (a Phase-C doc processor with an in-process, LLM-as-investigator
> tool-use loop) rather than an external skill. ADR 2026061801 is now the source
> of truth for the review pipeline; the framework and the first reviewer
> (`grammar_spelling`) are already implemented in
> `ChenWeb/server/api/doc-processing/review-document.go`.
>
> This document is retained to record the **narrowed role** the skill still plays.
> See §3.1 below.

# 2. Change Logs
- Created by Chen Ding on 2026/06/11
- 2026/06/21 — Superseded by ADR 2026061801 for the production design. Scope
  narrowed to the skill's supporting role (prototyping + human pre-review).

# 3. Context
The system has a knowledgebase that is built on the corpus of standards, technical documents, etc.
Documents are parsed into text form as needed form and then converted to line files (refer to [1]).

Refer to [2] for for more information about the knowledgebase.

Given a technical document, review it in in the aspects specified in [3]
to identify the discrepancies based on the ground truth in the system knowledgebase.

The review aspects are prioritized into 'High', 'Medium' and 'Low'. Users can choose
which aspects (or priority tiers) to run.

## 3.1 Why a Go module, not a coordinator skill

The original plan made this skill a *coordinator* that would drive per-aspect
review skills. ADR 2026061801 rejected that approach for the production service
because the review is fundamentally a database-bound, concurrent operation over
SemOS artifacts (`kb.entities`, `kb.relations`, `kb.metrics`, `kb.provisions`,
`kb.search_artifacts`):

- **DB integration** — review compares the document-under-review against extracted
  artifacts; this is native Go (connection pools, prepared statements) rather than
  MCP/shell access from a skill.
- **Concurrency** — ~40 reviewers run as goroutines with per-chunk fan-out; a skill
  is sequential.
- **Pipeline integration** — review is registered as the `review_document` Phase-C
  processor, plugging into the existing event/operation lifecycle, status locking,
  `CheckAndHandleStop`, and per-reviewer model routing.
- **Dashboard + persistence** — findings land in `kb.doc_review_findings` and drive
  a GUI for accept/reject; this must live inside the pipeline's status protocol.

The "LLM as investigator" capability that motivated a skill is preserved **inside**
the Go module via the managed tool-use loop (ADR 2026061801, DR10).

## 3.2 Remaining role of the skill

A Claude Code skill is still useful for, and is the intended vehicle for:

1. **Human pre-review** of parsed content and extracted artifacts — the quality
   gates before review runs (ADR 2026061801, DR9 steps 3 and 5).
2. **Prototyping** new reviewer prompts and tool definitions before they are baked
   into Go reviewers.
3. **Ad-hoc one-off reviews** where pipeline concurrency, dashboard, and persistence
   are not needed.

These uses do not require a coordinator skill; they are interactive, developer- or
assistant-driven activities.

## References
[1] 2026042101-spec-line-file.md

[2] 2026061105-spec-knowledgestore-explore-search.typ

[3] 2026061102-spec-document-review-checklist.md

[4] 2026061801-adr-document-review.md — **production design (source of truth)**
