# Overview

The inputs to a Knowledge Store is from 'kb.inputs'. This table now supports multi-tenants
with a tenant_id.

## Workflow

| Stage | Service | JetStream Event | What It Does |
|---|---|---|---|
| Staging | `server/cmd/doc-service` (binary/task name as of 2026-09; this doc previously said `pdf-parser`, which is not a real binary in this repo — the closest-named one, `server/cmd/service-pdf-parser`, exists but is dead code not wired into any `mise` task) | Emit `kb.pdf_staged` | Refer to [Handle Staged Files](#handle-staged-files) |
| Parsing | `python/pdf-parser` | Subscribe:`kb.pdf_staged`, Emit: `kb.pdf_parsed` | If a PDF file is staged, this service will receive an event with `kb.pdf_staged`. It parses the file using `kb.inputs.parser_name`. If the parser name is not specified, it uses the default PDF parser (refer to `spec-pdf-parser-python.md`) |
| Doc Processing | `server/cmd/doc-processor` | Subscribe: `kb.pdf_parsed` | Refer to `spec-doc-processor.md` |
----

## Upload Processing Modes

The upload UI provides an **Auto Process** mode for each upload. The default is
`Auto`.

| Mode | Behavior |
|---|---|
| `Auto` | Upload the files, parse PDFs, and publish the parsed event so the document-processing pipeline runs. |
| `Upload Files Only` | Upload the files and create the `kb.inputs` record, but do not parse the file or start downstream processing. |
| `PDF Parsing` | Upload and parse PDFs, but do not publish the parsed event; downstream document processing is not started. |

The selected mode is stored with the input record so processing remains
consistent if the service restarts or the upload contains multiple files.
For ZIP uploads, the selected mode is inherited by every extracted child
record. `Upload Files Only` therefore does not publish PDF stage events for
the extracted PDFs.

## Handle Staged Files
Files land in the staging directory (env var `UPLOAD_FILE_STAGING_DIR` as of
2026-09; this directory was previously configured via two separate env vars,
`STAGING_DIR` and `DATA_STAGING_DIR`, that were meant to name the same path —
consolidated into one name to remove that footgun) one of two ways:

- **Through the upload API** (`kbhandler.UploadInputs`, `POST /kb/inputs/upload`):
  the file is written to the staging directory and a `kb.inputs` row is
  inserted in the same transaction, with `tenant_id`/`ks_store_id` from the
  authenticated request and `file_name` set to the staged path,
  `backup_filename` left empty.
- **Directly** (an internal developer/admin copies a file onto the box, or —
  see [Pending Files](#pending-files) below — claims a `.pending` file
  through the admin UI, which performs the same kind of insert before
  renaming the file into place).

Independently, `server/cmd/doc-service` watches the staging directory via
`fsnotify` (with a debounce, plus a periodic fallback rescan in case events
are missed or the watch can't be established). For each file found there, it
copies it to `DATA_BACKUP_DIR` and a record-sharded path under
`DATA_HOME_DIR/Artifacts/{record_id/1000}/{record_id}/`, removes it from
staging, and either **updates** the existing `kb.inputs` row matching
`file_name = <staged path> AND backup_filename = ''` (the row the upload API
or a pending-file claim already inserted) or, if no such row exists,
**inserts a new unattributed row** and raises the `missing_user_id` alarm
(see
`KnowledgeStore/doc-repo/devdocs/202609/2026092403-devdoc-doc-processing-user-id-attribution.md`).
It publishes a `kb.pdf.staged`-shaped JetStream event for PDFs (unless the
record's processing mode is `upload_only`); non-PDF/non-docx types are not
otherwise pushed downstream from here.

### Zip File Handling

A staged `.zip` file gets a `kb.inputs` parent row (`type = 'zip'`), backed
up and copied to home like any other file. `doc-service` then opens the zip
and calls `ingestInputFile` for every entry inside it (`ingestZipChildren`):
each entry becomes its own `kb.inputs` row (`type` derived from the entry's
extension), inheriting the parent zip record's `tenant_id`/`ks_store_id`/
`ks_desc` and processing mode. Zip entries with non-UTF8 names (common for
archives built on Chinese Windows) are decoded from GBK/GB18030. A PDF child
gets its own stage event published, same as a top-level PDF upload.

### Pending Files

Internal developers/admins can also get a file into the pipeline by copying
it directly into `UPLOAD_FILE_STAGING_DIR` with a `.pending` suffix appended
to the real filename (e.g. `report.pdf.pending`). The staging poller ignores
any `.pending`-suffixed file outright, so it never becomes an unattributed
`kb.inputs` row on its own.

An admin-only **Pending Files** button on `ChenWeb/home3/knowledge` → File
Management (`GET /kb/pending-files` to list, `POST /kb/pending-files/claim`
to claim — both admin-role-gated server-side) lets an admin select one or
more `.pending` files and claim them. Claiming, per file, inserts a
`kb.inputs` row the same way the upload API would (using the admin's active
knowledge store for `tenant_id`) and then renames `<name>.pending` to
`<name>` within the same DB transaction — so the file only becomes visible
under its real name once a matching row already exists for the staging
poller to find. If the rename fails (another admin already claimed it, or
the file is gone), the transaction rolls back and that file reports a clean
per-file error without affecting the rest of the batch.

#### Staging cleanup

- A normally staged file (including a `.zip`) is removed from
  `UPLOAD_FILE_STAGING_DIR` once the poller has copied it to backup/home.
- A claimed `.pending` file is renamed (not copied) to its real name as part
  of the claim, then follows the same poller-driven cleanup as any other
  staged file.
