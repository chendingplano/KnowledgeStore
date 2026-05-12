# Overview

When users want to add files to the system, they put the files in the staging directory (STAGING_DIR).

A Go service [Staging Service](#staging-service) monitors the staging directory. When a new file is added to the directory, it picks the file and processes it [Staging Service](#staging-service) 

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

## Input File Processing
If the file is a PDF file, it is handled by [2]. Otherwise, it is not supported yet.

- Pick the file
- Copy it to the ARTIFACT_DIR directory and back up the file to DATA_BACKUP_DIR
- Remove the file from the staging dir
- Insert a record to 'kb.inputs'
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

[5] KnowledgeStore/Specs/spec-line-file.md