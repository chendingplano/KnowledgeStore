# Overview
- Document review requests are stored in `kb.doc_review_requests`
- Document review findings are stored in `kb.doc_review_findings`
- Document review reports are stored in `kb.doc_review_reports`

Workflow on generating document review reports:
- Input: `kb.doc_review_requests.id`
- Language: if not specified, defaults to DOC_REVIEW_REPORT_LANGUAGE
- Initiated when a document review request is finished.
- Retrieve the report (JSON) from `kb.doc_review_reports`
- Use the Typst template (refer to [1]) to create the report by the review report (JSON). The English and Chinese finding content is already generated and stored in `kb.doc_review_findings.metadata`, so use those localized values to create two reports, one in English and one in Chinese. Save them to DOC_REVIEW_REPORTS/`yyyymmdd-hhmm-` + `kb.doc_review_requests.id` + '-report-en.typ'/'-report-cn.typ'. The env var DOC_REVIEW_TEMPLATE_FILENAME defines the template file name.
- Convert the Typst files to PDF, using the same file names but with '.pdf'

Report finding rendering:
- Each finding card title must identify the persisted finding row, not only its ordinal position in the report. Render the title as `'Finding-' + kb.doc_review_findings.id`, for example `Finding-42`.
- Legacy report JSON without a finding row ID may continue to render an ordinal fallback such as `Finding F-03`.

Cross-document metric evidence:
- Metric consistency findings must identify the matched metric record in prose by `kb.metrics.metric_id`, for example `diaryMac.docx (refer to 415-mtc-2) specifies 48小时 ...`.
- The finding description must not rely on the filename alone when referencing a conflicting peer metric. It should include the matched metric ID, the referenced value/unit, and enough location context to let a reader find the source.
- When the metric reviewer prompt is supplied with `source_context`, append the referenced matching metric context to the analysis: include the matched metric's `source_line_spans`, the referenced line(s), and the provided +/- 10 surrounding source lines as `line_number: content`.

# References
[1] ChenWeb/docs/doc-templates/template-document-report.typ

[2] 2026062202-adr-document-report-template.md
