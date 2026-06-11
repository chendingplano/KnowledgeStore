# Document Review — Complete List of Aspects

A reference checklist for reviewing technical documents. Aspects are grouped
by category. Not every aspect applies to every document — see the
**Prioritization** section at the end to decide what matters for a given doc.

- **Status:** Active
- **Date:** 2026-06-11
- **Maintainer:** ChenWeb

---

## 1. Content Quality

| Aspect | What to Check |
|--------|---------------|
| **Completeness** | Are all required topics, sections, and edge cases covered? Is anything missing relative to the stated scope? |
| **Correctness / Accuracy** | Are facts, claims, formulas, figures, and code examples accurate and verifiable? |
| **Consistency (internal)** | Are there contradictions within the document (terms, values, conclusions)? |
| **Consistency (external)** | Does it agree with related docs, specs, ADRs, and the actual codebase/system? |
| **Clarity** | Can a qualified reader understand it on first reading, without ambiguity? |
| **Conciseness** | Is there redundancy, duplication, or unnecessary verbosity? |
| **Relevance / Scope** | Is all content within the document's stated purpose and scope? No scope creep? |
| **Currency / Freshness** | Is the information current? Are versions, dates, URLs, and screenshots still valid? |

## 2. Structure & Organization

| Aspect | What to Check |
|--------|---------------|
| **Logical Flow** | Is information ordered sensibly (context → overview → detail → reference)? |
| **Heading Hierarchy** | Are heading levels correct, consistent, and sensibly nested? |
| **Table of Contents** | Is the ToC present, accurate, complete, and at the right depth? |
| **Section Balance** | Are sections sized in proportion to their importance? |
| **Navigability** | Can a reader quickly locate a specific item? Are anchors/cross-refs correct? |
| **Modularity** | Are oversized topics split well? Should anything be its own document? |
| **Summary / TL;DR** | Is there an abstract or executive summary for quick orientation? |

## 3. Technical Quality

| Aspect | What to Check |
|--------|---------------|
| **Technical Accuracy** | Do code snippets compile/run? Are API signatures, config keys, CLI commands correct? |
| **Terminology** | Is domain terminology used correctly and consistently throughout? |
| **Assumptions** | Are implicit assumptions made explicit (e.g., "assumes PostgreSQL 15+")? |
| **Prerequisites & Dependencies** | Are required dependencies, versions, and setup steps listed? |
| **Limitations & Known Issues** | Are gaps, limitations, and edge cases documented? |
| **Error Handling** | Are error scenarios, failure modes, and recovery steps addressed? |
| **Performance** | Are performance implications, scaling limits, and bottlenecks discussed where relevant? |
| **Security** | Are threat models, attack surfaces, and mitigations addressed? |
| **Backward Compatibility** | Are breaking changes, migrations, and deprecation paths called out? |

## 4. Compliance & Standards

| Aspect | What to Check |
|--------|---------------|
| **Legal Compliance** | Does it comply with applicable law (GDPR, CCPA, HIPAA, SOX, etc.)? |
| **Regulatory Compliance** | Does it meet industry regulations (financial, healthcare, telecom, etc.)? |
| **Standards Compliance** | Does it adhere to relevant standards (ISO, IEEE, W3C, IETF RFCs, NIST, ANSI, etc.)? |
| **Internal Policy Compliance** | Does it follow org policies, coding standards, and architectural guidelines? |
| **Accessibility** | If user-facing, does it meet WCAG / Section 508 / EN 301 549? |
| **License / IP Compliance** | Are third-party licenses, attributions, and IP handled correctly? |
| **Export / Trade Controls** | Does content fall under export-control or trade restrictions (where applicable)? |

## 5. Audience & Usability

| Aspect | What to Check |
|--------|---------------|
| **Target Audience Fit** | Is the level right for the intended readers (junior devs, architects, stakeholders)? |
| **Examples & Illustrations** | Are there enough practical examples, snippets, and use cases? |
| **Diagrams & Visuals** | Are diagrams accurate, clear, consistent with the text, and using standard notation? |
| **Glossary & Acronyms** | Are acronyms and domain terms defined on first use or in a glossary? |
| **References / Links** | Are citations and external links correct, accessible, and stable? |
| **Actionability** | Can a reader actually do what the doc describes (clear next steps)? |
| **Searchability** | Is content phrased and structured so it can be found via search? |

## 6. Writing & Style

| Aspect | What to Check |
|--------|---------------|
| **Grammar & Spelling** | Any grammatical, spelling, or punctuation errors? |
| **Tone & Voice** | Is the tone appropriate and consistent (formal/informal, prescriptive/descriptive)? |
| **Readability** | Is the reading level appropriate? Are sentences and paragraphs well structured? |
| **Formatting Consistency** | Are code blocks, callouts, tables, lists, and fonts styled consistently? |
| **Localization / i18n** | For international audiences: are idioms, date formats, and units accessible? |
| **Inclusive Language** | Is wording free of biased, exclusionary, or deprecated terminology? |

## 7. Process & Lifecycle

| Aspect | What to Check |
|--------|---------------|
| **Version / Revision History** | Is the doc versioned? Is there a changelog or revision history? |
| **Review & Approval Status** | Is the state clear (draft, in-review, approved, deprecated)? |
| **Ownership & Authorship** | Are author(s), reviewer(s), and owner identified? |
| **Maintenance Plan** | Is there a cadence or owner for keeping it current? |
| **Expiration / Review-by Date** | Does it have a sunset or next-review date? |
| **Related Documents** | Are predecessor, successor, and sibling docs cross-referenced? |

## 8. Data & Confidentiality

| Aspect | What to Check |
|--------|---------------|
| **Secret Exposure** | Does the doc contain passwords, API keys, tokens, or credentials? |
| **PII / Personal Data** | Does it contain personal data that should be redacted? |
| **Confidentiality Markings** | Are classification labels applied (Public, Internal, Confidential, Restricted)? |
| **Data Retention** | Does it address how long data is kept and when it is purged? |
| **Data Provenance** | Are data sources and their licensing/usage rights identified? |

## 9. Verifiability & Traceability

| Aspect | What to Check |
|--------|---------------|
| **Testable Claims** | Are claims stated so they can be verified or tested? |
| **Requirements Traceability** | Can each requirement be traced to a source (spec, user story, regulation)? |
| **Evidence & Rationale** | Is there evidence for decisions (benchmarks, experiments, references)? |
| **Reproducibility** | If a process/experiment is described, can a reader reproduce the results? |
| **Decision Record** | Are key decisions and the alternatives considered captured? |

---

## 10. Prioritization

Not all aspects carry equal weight for every document. Use these tiers to scope
a review:

| Tier | Apply When | Focus Aspects |
|------|-----------|---------------|
| **Must review (every doc)** | Always | Correctness, Completeness, Clarity, Grammar & Spelling, Terminology, Version/Revision |
| **Should review (most docs)** | Most | Consistency, Logical Flow, Assumptions, Prerequisites, References, Confidentiality |
| **External / public docs** | Doc leaves the org | Legal Compliance, Accessibility, Localization, License/IP, Secret Exposure |
| **Regulated domains** | Finance, health, gov, etc. | Regulatory Compliance, Standards Compliance, Data Retention, PII/PHI |
| **Architecture / design docs** | System design | Technical Accuracy, Error Handling, Performance, Security, Traceability, Decision Record |

---

## 11. Suggested Output of a Review

For each finding, a reviewer should record:

- **Aspect** — which category/aspect from above
- **Location** — section, page, or line reference
- **Severity** — Blocker / Major / Minor / Nit
- **Finding** — what is wrong or missing
- **Recommendation** — concrete fix or follow-up
