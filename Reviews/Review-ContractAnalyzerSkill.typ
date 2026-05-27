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
    "Review - Contract Reviewer"
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
  logical_name: "Contract Reviewer",
  file_id: "2026052601",
  source: "https://github.com/hexiongjiu/contract-reviewer",
  content_type: "review",
  document_date: "2026/05/26",
  keywords: [Contract Review, Contract Review Skill, Skill],
)

= Overview
[contract-reviewer GitHub repository](https://github.com/hexiongjiu/contract-reviewer?utm_source=chatgpt.com) is an 
open-source AI-assisted contract analysis application focused on reviewing legal agreements for risks, obligations, 
and problematic clauses. Architecturally, it is a relatively lightweight web application rather than a full 
legal-tech platform. The project appears to center on taking uploaded contract text (or documents), 
processing that content through LLM-backed analysis, and presenting structured review findings to 
the user. The goal is practical contract triage: quickly identifying clauses that may deserve legal 
attention rather than replacing a lawyer’s full legal review. ([PyPI][1])

From a systems perspective, the project follows a familiar modern AI app pattern: frontend UI for document 
interaction, backend orchestration for parsing and prompt management, and LLM-driven semantic analysis. 
The core value is not novel ML infrastructure, but workflow integration—turning raw contract text into 
actionable issue spotting. Typical outputs include identification of unusual terms, potential liability 
exposure, missing protections, renewal traps, payment obligations, confidentiality concerns, and 
termination-related risks. In essence, this is a domain-specific document intelligence tool specialized 
for legal contracts rather than a generic RAG platform.

A notable design characteristic is that this project is application-oriented rather than infrastructure-oriented. 
It is built as an end-user product, not as a reusable contract analysis framework, extraction engine, or 
composable legal knowledge platform. If your lens is SemOS / structured knowledge systems, this matters: 
the project likely emphasizes immediate inference (“analyze this contract now”) rather than persistent 
normalized knowledge objects, causal/legal reasoning graphs, or reusable legal ontology construction. 
It behaves more like an AI assistant workflow than a knowledge engineering substrate.

Practically, this makes the repository useful as a reference implementation, LLM prompt orchestration, 
contract-focused UX, and legal-review workflow design. It is less useful if your goal is building a 
generalized explorable legal knowledge base or sophisticated structured extraction pipeline. 
This is closer to an *AI vertical application* than a *knowledge operating system component*.

== Architecture

This is a pure single-shot LLM call — no skills, no multi-step decomposition, no agents. The entire 
review happens in one fetch() call to the DeepSeek API (index.html:966-974):

```text
Upload DOCX → Mammoth.js extracts HTML → One API call → Parse annotated HTML response → Render + generate DOCX
```

The only "structure" is that the single call combines two parts:

- A fixed system prompt (hardcoded, user never sees it) — controls output format
- User-editable review instructions (shown in a textarea) — controls review focus areas

These are concatenated into combinedPrompt right before the call.

There is a second separate single-shot call for the Q&A feature (ask questions about the contract), 
which injects the contract text into the system prompt.

All prompts are embedded directly in index.html, around lines 572–600 and 961–974:

SYSTEM_PROMPT (index.html:585) — fixed, controls output format:

```text
你是一个专业的合同审核专家。请分析合同内容，输出HTML格式的标注结果。
【规则】: 用 <span class="problem-highlight"> 包裹问题原文，
后面紧跟 <div class="issue-annotation"> 放问题说明和建议...
DEFAULT_INSTRUCTIONS (index.html:574) — user-editable, controls review scope:


请重点审核以下方面：
1. 条款合理性...
2. 风险点识别...
3. 合规性审查...
4. 缺失条款...
5. 表述准确性...
```

At review time, they're combined (index.html:961):

```text
const combinedPrompt = `${SYSTEM_PROMPT}\n\n审核重点和要求：\n${userInstructions}`;
// user message: `请审核以下合同：\n\n${originalHtmlContent}`
```

In short, this is the simplest possible approach — one system prompt that instructs the LLM to 
output HTML with specific CSS classes, plus a user-customizable checklist appended to it. 
No routing, no decomposition, no retries. The "intelligence" is entirely delegated to the 
LLM in a single shot.

== References
[1]: https://pypi.org/project/contract-reviewer/?utm_source=chatgpt.com "contract-reviewer · PyPI"

