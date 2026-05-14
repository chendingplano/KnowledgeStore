# PDF Parser Go Service Spec

## File

`ChenWeb/server/cmd/pdf-parser/main.go`

## Purpose

This service watches the staging directory, ingests newly arrived files into the knowledge-base repository layout under `DATA_HOME_DIR`, creates `kb.inputs` records, and emits stage events for downstream PDF processing.

## Existing Service Responsibilities

1. Load config and environment.
2. Initialize database connections and run migrations.
3. Watch `DATA_STAGING_DIR` with `fsnotify`, with polling fallback.
4. Copy each staged file to `DATA_BACKUP_DIR`.
5. Copy each staged file into the sharded repository layout:
   `DATA_HOME_DIR/Artifacts/{record_id/1000}/{record_id}/{filename}`
6. Insert or update the matching `kb.inputs` row.
7. Remove the source file from staging after successful ingestion.
8. Publish a stage event for downstream PDF parsing.

## Improvements Implemented

### 1. Store `kb.inputs.file_name` relative to `DATA_HOME_DIR`

Before:

- Example stored value:
  `/Users/cding/Apps/SemOS/Artifacts/0/86/std_33830.pdf`

After:

- Stored value:
  `Artifacts/0/86/std_33830.pdf`

The service still writes the physical file to the same place on disk. Only the persisted database value changes.

## 2. Store `kb.inputs.result_filename` relative to `DATA_HOME_DIR`

The OCR/output side now follows the same convention:

Before:

- Example stored value:
  `/Users/cding/Apps/SemOS/Artifacts/0/86/std_33830_opendata.json`

After:

- Stored value:
  `Artifacts/0/86/std_33830_opendata.json`

Readers that open files now resolve relative paths back against `DATA_HOME_DIR` before touching the filesystem.

## 3. Zip-file ingestion

If a staged file has extension `.zip`, the service now performs two levels of ingestion.

### Parent zip record

- A `kb.inputs` record is created for the zip itself.
- `kb.inputs.type = 'zip'`
- The zip file is backed up and stored in the repository layout like any other ingested file.
- No PDF parse event is published for the zip container record.

### Child records for zip entries

- Each regular file inside the zip is materialized temporarily.
- A separate `kb.inputs` record is created for each extracted file.
- The child record `type` is derived from the file extension:
  - `.pdf` -> `pdf`
  - `.txt` -> `txt`
  - `.docx` -> `docx`
  - etc.
- Each child file is copied into its own repository shard directory under `Artifacts/{group}/{record_id}/`.
- Each child file is also copied to `DATA_BACKUP_DIR`.
- PDF child records publish the same downstream stage event as normal staged PDFs.

## Path Resolution Rules

### Stored in database

- `file_name`: relative to `DATA_HOME_DIR`
- `result_filename`: relative to `DATA_HOME_DIR`
- `backup_filename`: remains as the backup-path value currently used by the service

### Used at runtime

Any consumer that needs to open a file must:

1. Check whether the stored path is already absolute.
2. If it is relative, join it with `DATA_HOME_DIR`.
3. Use the resolved absolute path for filesystem access.

## Affected Components

### Go staging service

- `server/cmd/pdf-parser/main.go`

Changes:

- relative `file_name` persistence
- zip parent/child ingestion
- per-extension `type` assignment

### Go downstream readers

- `server/api/doc-processing/event.go`
- `server/api/file-converters/service.go`
- `server/api/kbhandler/metrics_handler.go`
- `server/api/pathutil/pathutil.go`

Changes:

- resolve relative `file_name` and `result_filename` using `DATA_HOME_DIR`

### Python OCR service

- `python/pdf-parser/pdf_parser.py`
- `python/pdf-parser/shared.py`

Changes:

- resolve relative repo paths when loading inputs
- persist `result_filename` relative to `DATA_HOME_DIR`
- persist `file_name` relative to `DATA_HOME_DIR`

## Test Coverage Added

### Go

- relative `file_name` persistence
- zip parent/child ingestion
- zip `type='zip'` insert path
- relative-path resolution for doc-processing

### Python

- resolving relative repo file paths
- persisting relative output paths
- helper coverage for repo-path resolution and relativization

## Verification

Validated with:

- `env GOCACHE=/tmp/go-build go test ./cmd/pdf-parser`
- `env GOCACHE=/tmp/go-build go test ./api/doc-processing -run TestResolveInputFilePath`
- `env GOCACHE=/tmp/go-build go test ./api/file-converters ./api/kbhandler`
- `./.venv/bin/python -m pytest tests/test_pdf_parser.py tests/test_shared.py`

