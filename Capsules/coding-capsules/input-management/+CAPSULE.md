# Overview

When users want to add files to the system, they can either:

1. Put the files in the staging directory (STAGING_DIR) — picked up automatically by the Staging Service.
2. Upload files through the web UI — the Upload File Dialog in the Injection view writes files directly to STAGING_DIR and creates a `kb.inputs` record. The dialog also supports **directory upload** (see [Web Upload Dialog](#web-upload-dialog)).

A Go service [Staging Service](#staging-service) monitors the staging directory. When a new file is added to the directory, it picks the file and processes it.

## Staging Service
## Input File Pipeline
| Seqno | Action | Processor |
|---|---|---|
| 1 | File added to STAGING_DIR | [Input File Processing](#input-file-processing) |
| 2 | Parse File | [Parse File](#parse-file) |
| 3 | Convert to Line File | [Convert to Line File](#convert-to-line-file) |
| 4 | Doc Processing | [Doc Processing](#doc-processing) |

## Pipeline Statuses
### File Staged
When: the file has been put into the ARTIFACT_DIR directory and is ready to be processed.

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation":"file_staged",
    "status":"success | failed",
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

### File Parsed
When: the file is parsed.

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "result_file_name":"xxx",
    "operation":"parsed",
    "proc_status":"success | failed",
    "num_pages":ddd,
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms-used":ddd,
}
```

### Result Converted
When: the parsing results, which is in JSON and its format is parse-dependent,
is converted to the internal Line File ([5]) format.

Status JSON:
```json
{
    "record_id":"ddd",
    "line_file_name":"xxx",
    "operation":"converted",
    "proc_status":"success | failed",
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

### Doc Processing
Refer to [1] for Doc Processing and their status.

## Web Upload Dialog

The Upload File Dialog (`ChenWeb/web/src/lib/components/home3/kb-import-view.svelte`) allows users to upload files to the active Knowledge Store directly from the browser. Files are written to STAGING_DIR by the Go upload handler (`POST /api/v1/kb/inputs/upload`) and a `kb.inputs` record is created immediately.

### Directory Upload

In addition to picking individual files, the dialog supports picking a whole directory:

- **Browse Directory** button opens a directory picker (`webkitdirectory`).
- **Recursive** checkbox (defaults **true**): when checked, all files in the directory tree are considered; when unchecked, only top-level files are included.
- Only files whose extension matches the selected **Type** (e.g. `.pdf` for type `pdf`) are kept.
- Each candidate file's **MD5** is computed in the browser. The frontend calls `POST /api/v1/kb/inputs/check-md5` to find which MD5s already exist in `kb.inputs.md5`. Files whose MD5 matches an existing record are silently skipped; the count of skipped files is shown in the dialog.

### MD5 Deduplication

`kb.inputs` has an `md5 TEXT` column (migration `20260609000001_add_kb_inputs_md5.sql`). The upload handler computes MD5 via `crypto/md5` while streaming the file to disk (`io.MultiWriter`) and stores the result. The `check-md5` endpoint (`ChenWeb/server/api/kbhandler/check_md5_handler.go`) accepts a JSON array of hex strings and returns the subset that already exist.

## Input File Processing
If the file is a PDF file, it is handled by [2]. Otherwise, it is not supported yet.

- Pick the file
- Copy it to the ARTIFACT_DIR directory and back up the file to DATA_BACKUP_DIR
- Remove the file from the staging dir
- Insert a record to 'kb.inputs' (including computed MD5)
- Generate a JetStream event with the subject 'kb.pdf.staged'

## Parse File
If the file is a PDF file, this service parses the file and generates the results in the same
directory. The location of the file is DATA_HOME_DIR + "/" + the directory of 'kb.inputs.result_filename'.
The result file name is `root of 'kb.inputs.staging_filename' + '.json'.

The service is in [3].

## Convert to Line File
This is a Go service ([4]). It converts the PDF parsing result file (.JSON) into a line file ([5]).

## Doc Processing
This is a Go service. Refer to [1].

## Status Monitoring through Redis

| Redis Key | Value | Explanations |
|---|---|---|
| active-pdf-status | an array of JSON documents | Any time when a new record is inserted to 'kb.inputs', if it is a PDF file, it adds a JSON document that reflects the current status in the input file pipeline. When the record finishes processing, its JSON is removed from this variable |

## References
[1] Capsules/coding-capsules/doc-processor

[2] ChenWeb/server/cmd/pdf-parser

[3] ChenWeb/python/pdf-parser

[4] ChenWeb/server/cmd/parser-result-converter

[5] KnowledgeStore/Capsules/coding-capsules/input-management/spec-line-file.md

[6] ChenWeb/server/api/kbhandler/upload_handler.go — web upload handler (writes file to STAGING_DIR, computes MD5, inserts kb.inputs record)

[7] ChenWeb/server/api/kbhandler/check_md5_handler.go — POST /api/v1/kb/inputs/check-md5 endpoint

[8] ChenWeb/project_migrations/20260609000001_add_kb_inputs_md5.sql — adds md5 column + index to kb.inputs

[9] ChenWeb/web/src/lib/components/home3/kb-import-view.svelte — Upload File Dialog with directory picker and MD5 dedup

[10] ChenWeb/web/src/lib/services/kbService.ts — checkKbInputMD5s() frontend service function