# Overview

The inputs to a Knowledge Store is from 'kb.inputs'. This table now supports multi-tenants
with a tenant_id.

## Workflow

| Stage | Service | JetStream Event | What It Does |
|---|---|---|---|
| Staging | `server/cmd/pdf-parser` | Emit `kb.pdf_staged` | Refer to [Handle Staged Files](#handle-staged-files) |
| Parsing | `python/pdf-parser` | Subscribe:`kb.pdf_staged`, Emit: `kb.pdf_parsed` | If a PDF file is staged, this service will receive an event with `kb.pdf_staged`. It parses the file using `kb.inputs.parser_name`. If the parser name is not specified, it uses the default PDF parser (refer to `spec-pdf-parser-python.md`) |
| Doc Processing | `server/cmd/doc-processor` | Subscribe: `kb.pdf_parsed` | Refer to `spec-doc-processor.md` |
----

## Handle Staged Files
Files are uploaded to STAGING_DIR. The service `server/cmd/pdf-parser` detects the changes. Once a new file 
is added to this directory, it moves the file to DATA_HOME_DIR/Artifacts (refer to 'pdf-parser-go-spec.md'). 
It emits `kb.pdf-staged` if it is a PDF file. Otherwisse, it emits `kb.file-staged`.

### Zip File Handling
If the file is a zip file ('.zip'):
- 
