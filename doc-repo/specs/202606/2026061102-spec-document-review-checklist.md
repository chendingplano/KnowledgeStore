# 1. Document Review Checklist

- DocID: `doc-2026061102`
- **Status:** Active
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** Document Review

# 2. Change Logs
- Created by Chen Ding on 2026/06/11

# 3 Complete List of Review Aspects

The following aspects are organized by category for reviewing a technical document.

## 3.1 Content Quality

| Aspect | Priority | Pass | Description |
|--------|----------|------|-------------|
| Completeness | High | P3 | Are all required topics, sections, and edge cases covered? Is anything missing? |
| Correctness / Accuracy | High | P3 | Are technical facts, claims, formulas, and code examples accurate and verifiable? |
| Consistency (internal) | High | P4 | Are there internal contradictions? Is the document consistent with related documents, architecture decisions, and codebase? (more in [Internal Consistency](internal-consistency)|
| Consistency (external) | High | P4 | Does it agree with related docs, specs, ADRs, and the actual codebase/system? |
| Clarity | High | P3 | Is the writing clear and unambiguous? Can a qualified reader understand it on first reading? |
| Conciseness | Medium | P3 | Is there redundancy, duplication, or unnecessary verbosity? |
| Relevance | Low | P3 | Is all content relevant to the document's stated purpose and scope? |
| Currency / Freshness | Low | P3 | Is the information up-to-date? Are referenced versions, dates, and URLs still valid? |
---

### 3.1.1 Internal Consistency
* defined terms;
* quantities and units;
* responsibilities;
* process states;
* cross-references;
* abbreviations;
* enumerated requirements.

Example:

```text
Section 4: Samples must be processed within 2 hours.
Section 7: Samples may be stored for up to 4 hours before processing.
```

The system should determine whether these are:

* a true contradiction;
* separate conditions;
* a general rule and exception;
* two different sample categories;
* ambiguous due to missing context.

## 3.2 Structure & Organization

| Aspect | Priority | Pass | Description |
|--------|----------|------|-------------|
| Logical Flow | High | P2 | Is information presented in a sensible order (e.g., overview → details → references)? |
| Heading Hierarchy | High | P2 | Are heading levels used correctly and consistently? Does the nesting make sense? |
| Table of Contents | High | P2 | Is the ToC accurate, complete, and at the right level of detail? |
| Navigability | High | P2 | Can a reader quickly find a specific piece of information? Are cross-references correct? |
| Safety and Risk | High | P2 | Some documents need document dedicated risk-oriented content ([Safety and Risk](safety-and-risk)|
| Completeness | High | P2 | Check whether the document contains expected components for its type (more on [Structural Completeness](structural-completeness)) |
| Section Balance | Medium | P2 | Are sections proportionally sized relative to their importance? |
| Modularity | Medium | P2 | Are large topics split sensibly? Or should something be split into a separate document? |

### 3.2.1 Structural Completeness
* purpose;
* scope;
* responsibilities;
* definitions;
* materials;
* procedure;
* safety precautions;
* acceptance and rejection criteria;
* quality control;
* records;
* references;
* revision history.

This should be driven by document-type profiles, not by generic LLM intuition.

### 3.2.2 Safety and Risk

Some documents, especially for medical documents, need a dedicated risk-oriented pass:

* Could following the document cause patient harm?
* Are high-risk actions missing verification?
* Are warnings separated from the action they constrain?
* Are escalation conditions defined?
* Are abnormal results handled?
* Is there a fail-safe response?
* Are roles authorized to perform the stated action?
* Could ambiguity lead to materially different behavior?

The safety and risk check is document type dependent.

Safety findings should receive stricter evidence and verification requirements.


## 3.3 Technical Quality

| Aspect | Priority | Pass | Description |
|--------|----------|------|-------------|
| Technical Accuracy | High | P5 | Do code snippets compile/run? Are API signatures, config keys, and CLI commands correct? |
| Terminology | High | P4 | Is domain-specific terminology used correctly and consistently throughout? ([Terminology and Definition Alignment](terminology-and-definition-alignment)|
| Assumptions | High | P5 | Are implicit assumptions explicitly called out (e.g., "assumes PostgreSQL 15+")? |
| Prerequisites & Dependencies | High | P5 | Are all required dependencies, versions, and setup steps listed? |
| Limitations & Known Issues | High | P5 | Are known gaps, limitations, and edge cases documented? |
| Error Handling | High | P5 | Are error scenarios, failure modes, and recovery steps addressed? |
| Performance Considerations | Medium | P5 | Are performance implications, scaling limits, and bottlenecks discussed where relevant? |
| Security Considerations | Medium | P5 | Are security implications, threat models, and mitigations addressed? |

### 3.3.1 Terminology and Definition Alignment

Most standards frequently define terms precisely. Check whether:
* the document uses a term differently;
* a broader term is incorrectly substituted for a narrower one;
* two terms are treated as synonyms when standards distinguish them;
* an acronym is overloaded;
* a deprecated term is used.

## 3.4 Compliance & Standards

| Aspect | Priority | Pass | Description |
|--------|----------|------|-------------|
| Legal/Standard Compliance Provisions | High | P5 | Does the document/solution comply with applicable laws (GDPR, CCPA, HIPAA, SOX, etc.) or applicable standards? (more in [Compliance Provisions](compliance-provisions)|
| Regulatory Compliance | High | P5 | Does it meet industry-specific regulations (financial, healthcare, telecom, etc.)? |
| Standards Compliance | High | P5 | Does it adhere to relevant standards (ISO, IEEE, W3C, IETF RFCs, NIST, etc.)? |
| Internal Policy Compliance | High | P5 | Does it follow organizational policies, coding standards, and architectural guidelines? |
| Accessibility | Low | P6 | If user-facing, does it meet WCAG / Section 508 / EN 301 549 requirements? |
| License / IP Compliance | Medium | P6 | Are third-party dependencies, licenses, and attributions properly handled? |

### 3.4.1 Compliance Provisions
For each applicable provision:

1. retrieve candidate document passages;
2. classify the relationship;
3. generate a finding only when supported.

Useful relationship labels include:

```text
satisfied
partially_satisfied
not_satisfied
contradicted
not_addressed
not_applicable
unclear
insufficient_evidence
```

Notice that **not addressed** is not automatically the same as **noncompliant**. The provision might not need to appear in this particular document.

**Document-to-standard conflict detection**

Start from statements in the reviewed document and retrieve standard provisions that may disagree.

This is the reverse of compliance checking:

```text
Document statement → retrieve potentially conflicting provisions
```

For example, the document specifies a storage temperature of 8°C. SemOS searches for provisions concerning that item, process, and temperature, rather than merely checking a predetermined list.

## 3.5 Audience & Usability

| Aspect | Priority | Pass | Description |
|--------|----------|------|-------------|
| References | High | P6 | Are all citations, links, and external references correct and accessible? |
| Target Audience Fit | Low | P6 | Is the content pitched at the right level for the intended readers (junior devs, architects, stakeholders)? |
| Examples & Illustrations | Medium | P3 | Are there enough practical examples, code snippets, and use cases? |
| Glossary | Medium | P4 | Are all acronyms and domain-specific terms defined on first use or in a glossary? |
| Searchability | Medium | P2 | Is the document structured so its content can be found via search? |
| Diagrams & Visuals | Low | P3 | Are diagrams accurate, clear, and consistent with the text? Do they use standard notation? |

## 3.6 Process & Lifecycle

| Aspect | Priority | Pass | Description |
|--------|----------|------|-------------|
| Related Documents | High | P6 | Are predecessor, successor, and sibling documents cross-referenced? |
| Version / Revision History | Low | P6 | Is the document versioned? Is there a changelog or revision history? |
| Review & Approval Status | Low | P6 | Is the review state clear (draft, in-review, approved, deprecated)? |
| Ownership & Authorship | Low | P6 | Are author(s), reviewer(s), and owner identified? |
| Maintenance Plan | Low | P6 | Is there a plan or cadence for keeping the document current? |
| Expiration / Sunset | Low | P6 | Does the document have an expiration date or review-by date? |

## 3.7 Writing & Style

| Aspect | Priority | Pass | Description |
|--------|----------|------|-------------|
| Grammar & Spelling | High | P1 | Are there any grammatical, spelling, or punctuation errors? |
| Localization / i18n | High | P1 | If the audience is international, are idioms, date formats, and measurement units accessible? |
| Tone & Voice | High | P1 | Is the tone appropriate (formal vs. informal, prescriptive vs. descriptive)? Is it consistent? |
| Formatting Consistency | High | P1 | Are fonts, code blocks, callouts, tables, and lists styled consistently? |
| Readability | Low | P1 | Is the reading level appropriate? Are sentences and paragraphs structured well? |

## 3.8 Data & Confidentiality

| Aspect | Priority | Pass | Description |
|--------|----------|------|-------------|
| Confidentiality Markings | High | P6 | Are proper classification labels applied (Internal, Confidential, Public, etc.)? |
| Sensitive Data Exposure | Medim | P6 | Does the document inadvertently contain passwords, API keys, tokens, or secrets? |
| PII / Personal Data | Medim | P6 | Does it contain personally identifiable information that should be redacted? |
| Data Retention | Low | P6 | Does the document address how long data is kept and when it should be purged? |

## 3.9 Verifiability & Traceability

| Aspect | Priority | Pass | Description |
|--------|----------|------|-------------|
| Testable Claims | High | P3 | Are claims stated in a way that can be verified or tested? |
| Requirements Traceability | High | P4 | Can each requirement be traced to a source (spec, user story, regulation)? |
| Evidence & Rationale | High | P3 | Is evidence provided for design decisions (benchmarks, experiments, references)? |
| Reproducibility | Low | P6 | If the document describes a process or experiment, can the reader reproduce the results? |

## 3.10 Prioritization Matrix

Not all aspects carry equal weight for every document:

| Tier | When to Apply |
|------|---------------|
| Must Review (every doc) | Correctness, Completeness, Clarity, Grammar & Spelling, Terminology, Version/Revision |
| Should Review (most docs) | Consistency, Logical Flow, Assumptions, Prerequisites, References, Confidentiality |
| Review for External/Public docs | Legal Compliance, Accessibility, Localization, License/IP, Sensitive Data |
| Review for Regulated domains | Regulatory Compliance, Standards Compliance, Data Retention, PHI/PII |
| Review for Architectural docs | Technical Accuracy, Error Handling, Performance, Security, Traceability |

## References
[1] KnowledgeStore/doc-repo/202604/2026042101-line-file-spec.md