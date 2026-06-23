# Overview
- Document review requests are stored in `kb.doc_review_requests`
- Document review findings are stored in `kb.doc_review_findings`
- Document review reports are stored in `kb.doc_review_reports`

Workflow on generating document review reports:
- Input: `kb.doc_review_requests.id`
- Language: if not specified, defaults to DOC_REVIEW_REPORT_LANGUAGE
- Initiated when a document review request is finished.
- Retrieve the report (JSON) from `kb.doc_review_records`
- Use the Typst template (refer to [1]) to create the report by the review report (JSON) and save it to DOC_REVIEW_REPORTS/`yyyymmdd-hhmm-` + `kb.doc_review_requests.id` + 'reports.typ'. The env var DOC_REVIEW_TEMPLATE_FILENAME defines the template file name.
- Convert the Typst file to PDF, using the same file name but with '.pdf'

# References
[1] ChenWeb/docs/doc-templates/template-document-report.typ

[2] 2026062202-adr-document-report-template.md