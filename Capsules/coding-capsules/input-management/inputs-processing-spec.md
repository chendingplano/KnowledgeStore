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

If the staged file has a `.zip` extension, the service performs two levels of ingestion.

#### Parent zip record

- `ingestInputFile` is called for the zip itself (same as any other staged file).
- A `kb.inputs` row is created with `type = 'zip'`.
- The zip is backed up to `DATA_BACKUP_DIR` and stored in the sharded repo layout under `DATA_HOME_DIR/Artifacts/{record_id/1000}/{record_id}/`.
- `file_name` is stored relative to `DATA_HOME_DIR` (e.g. `Artifacts/0/42/archive.zip`).
- No PDF stage event is published for the zip container record.

#### Child records for each zip entry

`ingestZipChildren` is called with the zip's home path after the parent record is created.

For each regular file (non-directory) inside the zip:

1. The entry is extracted to a temporary file on disk.
2. `ingestInputFile` is called for the temp file using the entry's base filename.
3. A separate `kb.inputs` row is created with `type` derived from the file extension (e.g. `pdf`, `txt`, `docx`).
4. The child file is backed up to `DATA_BACKUP_DIR` and stored in its own shard directory.
5. `file_name` is stored relative to `DATA_HOME_DIR`.
6. A PDF stage event (`kb.pdf_staged`) is published for child records whose `type = 'pdf'`.
7. The temporary file is removed after ingestion.

#### Staging cleanup

- The original zip file is removed from `DATA_STAGING_DIR` after the parent record and all child records are ingested.
