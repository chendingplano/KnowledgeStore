---
title: Document Review — User Manual
language: en
format: markdown
version: 1.0
status: current
author: Not specified
owner: Not specified
audience: Document authors, reviewers, compliance staff, and knowledge-base operators
create-time: 2026-08-16T06:18:03-05:00
last-modify-time: 2026-08-16T06:18:03-05:00
keywords: DR13, Document Review, document quality, compliance review, findings, review report, supporting documents, standards review
---

# Document Review

## 1. What it is

Document Review checks a document against the review aspects selected by the requester. It can look for writing and structure problems, content-quality issues, inconsistencies, technical or compliance concerns, and document-maintenance issues.

Use it when you want a repeatable first review of a document before publication, internal approval, external delivery, or regulated use. The result is a set of findings linked to the reviewed document, plus a report that summarizes the review.

This manual describes the current ChenWeb implementation of the DR13 Document Review Request GUI. The attached 2026-07-29 ADR uses the label “DR13” for a separate semantic-web standards decision; that decision is background context, not an additional user step in this application.

## 2. Before you start

You need access to ChenWeb and permission to use the Document Review application. The document must either already be available in the document library or be uploaded into an active knowledge store.

For a compliance-oriented review, identify the standards or other documents that should guide the review. You can add them as optional supporting documents in Step 3.

The available aspects, labels, descriptions, initial selections, and review tiers come from the deployment configuration. Therefore, another installation may show a different set of checked aspects or tier contents.

## 3. Open Document Review

1. Open the ChenWeb home dashboard.
2. In the navigation rail, open **Applications → Document Review**.
3. Start a new review, or choose **View** for an existing review run.

The page also shows existing review runs. Use **Search** in the runs list to find particular runs, then open one with **View**.

## 4. Start a review

### Step 1: Select the document

Choose one of the two input modes:

- **Search Library** — search the document library and select an existing document.
- **Upload File** — upload a new file into the active knowledge store and use it as the review document.

When uploading, select a knowledge store first, choose a parser, and then choose a file. The current file-type mapping supports PDF, Word, Excel, PowerPoint, text, JSON, XML, Markdown, Typst, and ZIP extensions. The available parser choices are `paddleocr`, `opendata`, `mineru`, and `docling`; which parser is appropriate depends on the source file.

After selection, confirm that the displayed document title is the document you intend to review, then select **Next**.

### Step 2: Choose the review aspects

Step 2 has two related choices:

1. **Review depth** — choose Depth 1, Depth 2, or Depth 3.
2. **Aspects** — choose the checks to run.

The built-in aspect groups are:

| Group | Typical checks |
|---|---|
| Language & Style | Grammar, spelling, tone, formatting, readability, localization |
| Structure & Organization | Logical flow, heading hierarchy, navigation, section balance, modularity |
| Content Quality | Completeness, correctness, clarity, conciseness, relevance, examples, diagrams, evidence |
| Consistency | Contradictions, terminology, cross-references, requirement traceability |
| Technical & Compliance | Technical accuracy, assumptions, prerequisites, standards, legal, regulatory, security, metrics, provisions, entities, inventory items |
| Meta & Process | Version history, ownership, references, confidentiality, sensitive data, retention, and intellectual property |

Turn a review level **On** to select all of its configured aspects. Expand the level to inspect individual aspects, use **Select all** or **Deselect all**, or toggle individual aspects. The selection is shared across levels: an aspect selected under one level is part of the actual submission.

The request is saved as a named built-in tier only when the selected aspects exactly match that tier. Otherwise it is saved as **Custom**. You must select at least one aspect before continuing.

Choose a depth appropriate to the document and the time available. The interface provides the three depth values, but the exact processing difference is deployment-specific; do not interpret the number as a quality guarantee.

### Step 3: Add supporting documents

Supporting documents are optional. Use the search box to find reference standards or other documents, then select **Add**. Added documents appear in the list and can be removed before submission.

Examples include:

- a governing standard or regulation;
- an internal policy;
- a prior approved version; or
- a related specification used to check terminology, requirements, or consistency.

Adding a reference does not make it authoritative by itself. It supplies additional material for the configured review process.

### Step 4: Review details and submit

Enter your name. This field is required and may be filled from your signed-in account when that information is available.

You may also enter notes, such as “focus on sterilization validation sections” or “check the revised alarm requirements.” Review the summary, which shows:

- the selected document;
- the check level or Custom selection;
- the number of aspects;
- review depth; and
- requester name.

Select **Start Review**. The system creates a review request and opens its progress view.

## 5. Follow progress

While the review is running, the page polls for updated status. Each selected aspect has its own status and progress indicator:

- **Pending** — waiting to start;
- **Running** — currently processing;
- **Success** — finished successfully; or
- **Failed** — finished with an error.

The progress panel also shows findings produced so far for each aspect. The overall request can be accepted, pending, or running while work remains. A review job leaves the active monitor after all of its aspects are finished.

Select **Stop** while the request is accepted, pending, or running if you need to cancel it. A stopped review is not the same as a completed review and may not have a complete report.

## 6. Read the results

When the review completes, the results view provides summary charts and counts, including severity distribution and findings by package or aspect. Use the available filters and views to narrow the result.

The main result choices are:

- **View Report** — opens the interactive report;
- **Findings** — opens the findings view for the review run;
- **View Full Report PDF** — opens a list of report PDFs for the document;
- **View Full Report JSON** — shows the structured report data; and
- **View Full Report Markdown** — shows the readable Markdown report.

The report includes an executive summary, assessment information, findings, and recommendations when those fields are available. A report is generated from the stored findings; it is not a substitute for a human decision.

## 7. Work with findings

A finding normally includes its review aspect, severity, title, description, evidence or location, suggestion, confidence, and review status. Expand a finding to read its details.

Use the finding actions according to your review process:

- **Accept** — keep the finding as reviewed and accepted.
- **Reject** or defer-style status actions, where shown — record that the finding should not be treated as currently actionable or needs later consideration.
- **LLM Auto Fix** — ask the configured model to propose or apply a correction to the offending line or lines. Review the result before relying on it.
- **Edit Tool** — edit the affected document lines manually through the available editor.
- **Delete** — soft-delete the finding from the report view.

Changing a finding status records a reviewer decision. It does not prove that the underlying document is compliant. Re-read important source text and apply organizational approval rules before publishing or approving the document.

## 8. Use the source-document view

The interactive report uses a two-panel layout:

- the left panel groups and displays findings; and
- the right panel shows the reviewed document’s line list and PDF view when a source document is linked.

Select a finding to move the source view to its location and highlight the relevant lines or page region. This is useful for checking whether the finding accurately describes the source text.

The report can be viewed by all findings, by package, or by severity. Selecting a group highlights its findings in the source view. If no source document is linked, the report remains readable but source navigation is unavailable.

## 9. Regenerate reports and create a change report

After findings are accepted, edited, hidden, or otherwise changed, use **Re-Generate Review Report** to rebuild the report from the current non-deleted findings. The report identifier remains stable while its contents and generated PDF are refreshed.

Use **Generate Change Report** when you need a separate summary of document corrections. This is a review-change output; it is not the same as the full review report.

Reports can be viewed or downloaded as PDF and Markdown. JSON is available for structured inspection.

## 10. Understand the outcomes

### Review failed

The request could not finish. Read the displayed error message and contact the system operator if the error persists. Do not treat a failed run as a clean review.

### Review stopped

The request was cancelled before completion. Its partial status is not a complete review result.

### No findings

No findings were returned for the selected aspects and run. This does not guarantee that the document is correct, complete, or compliant. It may reflect the selected aspects, reference material, processing configuration, or reviewer limitations.

### Findings need judgment

Document Review is an assistive review service. Findings can be incomplete, overly cautious, or incorrect. In particular, a standards or regulatory finding must be checked against the actual governing edition, jurisdiction, effective date, and source clause before it is used as a compliance conclusion.

## 11. Current implementation boundaries

- Aspect names and initial checkboxes are configuration-driven; they can change between deployments.
- Review depth has three selectable values, but the user interface does not define a universal interpretation for the difference between them.
- Supporting documents are optional and are supplied as review context; the application does not by itself establish their legal or organizational authority.
- The live monitor reports per-aspect progress, but a successful aspect does not mean every finding from that aspect is correct.
- Report regeneration updates the report from current findings. It does not automatically approve findings or publish a corrected source document.
- The attached ontology-platform ADR’s selective use of semantic-web standards is an architectural decision. It does not mean that this GUI exports every review as RDF, OWL, SKOS, or SHACL.

## 12. Troubleshooting

| Problem | What to check |
|---|---|
| No document can be selected | Search the library again, or switch to Upload File and choose an active knowledge store. |
| Upload is rejected | Check the file extension, selected parser, active knowledge store, and store tenant. |
| Next is disabled in Step 2 | Select at least one aspect. |
| Start Review is disabled | Enter your name and confirm that a document and at least one aspect are selected. |
| An aspect remains pending | Wait for the run to finish. If it remains pending or fails, inspect the request error and contact the operator. |
| The report has no PDF | Regenerate the report or use Markdown/JSON while the PDF is being produced. |
| A finding points to no source | The finding may lack a usable location or the report may not have a linked source document. |
| A result appears wrong | Inspect the source lines, review the evidence and reference documents, update the finding status, and document the human decision. |

## Change Log

| Version | Timestamp | Responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.0 | 2026-08-16T06:18:03-05:00 | Not specified | Initial manual | Documented the current DR13 Document Review GUI, request flow, progress monitoring, findings, reports, and implementation boundaries. |
