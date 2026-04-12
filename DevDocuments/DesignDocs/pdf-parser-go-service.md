Use superpowers to create a PDF parser and save it in shared/go/api/parsers/pdf-parser:

- PDF Parser is a service, written in Go.
- The service uses a PDF parser to parse PDF docs. Currently, there are two PDF parsers: (1) ~/Workspace/ThirdParty/paddleocr and (2) ~/Workspace/ThirdParty/opendataloader-pdf. Note that we may add more PDF parsers in the future.
- There is a database table: 'kb.inputs' that manages all the inputs. Each record in the table is an input, which can be a document (such as PDF, Word, Excel, PPT, text, markdown, etc.). Refer to "kb.input Table Definition" for the table schema.
- The 'type' field identifies the type of the input. The value 'pdf' means the input is a PDF file.
- Status Management: refer to "Field status and Status Management" section.
- The service monitors the database table 'kb.inputs'. For this service, it handles only the records with `type` = 'pdf'. If its status does not have an entry whose `operation` is "parse", it will pick up the record and start parsing the doc.

## kb.input Table Definition

<a id="kb-input-table-def"></a>
| Field Name | Required | Explanation |
|:-----------|:---------|:------------|
| id | mandatory | Auto-incremented ID (integer) that identifies the record |
| type | mandatory | The input type, such as 'word', 'pdf', ... |
| title | optional | The title if the input is a document |
| doc_no | optional | The document number, which is normally a string, if any |
| source | optional | Where the input came from |
| parser_name | optional | The name of the parser to use |
| staging_filename | optional | The file name in the staging directory|
| file_name | optional | The file name (url) at which the file is stored, applicable to files only |
| backup_filename | optional | The backup file name |
| publish_date | optional | The doc's publish date |
| authors | optional | The doc's authors |
| owner | optional | The ID of the user Who owns the input |
| status | mandatory | A JSON doc that keeps track of the operations on the input (refer below to its definition) |
| create_time | mandatory | The creation time (read-only) |
| modify_time | mandatory | The last modification time |
| public_info | optional | A JSON document that stores additional public info |
| private_info | optional | A JSON document that stores additional private info |
| notes | optional | Stores notes |
| error_msg | optional | Stores error messages, such as processing error messages |

## Field `status` and Status Management
An input may be processed by a pipeline, such as for Field `type` = 'pdf', it will be processed by:
 - Extracting (or parsing) text and document structures from the PDF document
 - Use an LLM to extract topics from the extracted text and generate chunks based on the topics
 - Generate a one-line summary; 

Field 'status' keeps track of the process status. It is an array. Each element in the array is a JSON doc with the following format:
```json
[
    {"operation":"the-opr", "time":"timestamp-in-yyyymmdd hh:mm:ss", "status":"success or fail", "error":"error-msg"},
    {"operation":"the-opr", "time":"timestamp-in-yyyymmdd hh:mm:ss", "status":"success or fail", "error":"error-msg"},
    ...
]
```
where:
- 'operation' specifies the operation performed on the file, such as 'parsing', 'analyzing', 'adding to knowledge', etc.
- 'time': the time when the operation was performed, 
- 'status': success or failed, and "error": the error message.

For PDF parsing, the status JSON doc should be:
```json
{
    "operation":"parse",
    "proc-status":"success-or-failed",
    "time":"timestamp-in-yyyymmdd hh:mm:ss-format",
    "time-used":"time-used-in-ms",
    "error":"error-msg-if-failed"
}
```

## Workflow

Below is the workflow for this service:
- Step 1: Detect changes in the Staging directory. Once one or more new files are added to the directory, go to the next step.
- Step 2: Handle Input File: refer to the 'Handle Input File' section.
- Step 3: Parse PDF File: refer to the 'Parse PDF File' section.

## Handle Input File

Three directories used for PDF files:
- Staging Directory: Input files are originally saved in the staging directory, specified by the env variable STAGING_DIR
- Result Directory: PDF parser will generate some result files, such as one JSON file and one image for each page. Store the result files in 'PDF_REPO_DIR/pdf_parser/record_id/', where 'PDF_REPO_DIR' is an environment variable and 'record_id' is the record's id. 
- Backup Directory: After processing, the original file is copied to the result directory and the backup directory: DATA_BACKUP_DIR/pdf_files, where 'DATA_BACKUP_DIR' is an environment variable.

Below is the workflow for handling the input file:
- If the staging directory has the file specified by `staging_filename` field, copy the file to the result directory and the backup directory. Remove it from the staging directory. Then go to the next step. 
- Otherwise, if `result_filename` field is empty, this is an error. Record the error and abort the operation. 
- Otherwise, make sure the result directory does have the named file. If not, it is an error. Record the error and abort the operation.
- Otherwise, this is re-processing the file. Go to the next step.

## Parse PDF File
Currently it supports two PDF parsers:
- PaddleOCR, installed in ~/Workspace/ThirdParty/paddleocr
- opendataloader-pdf: installed in ~/Workspace/ThirdParty/opendataloader-pdf

It is specified by the environment variable PDF_PARSER_NAME:
- 'paddleocr': use PaddleOCR
- 'opendata': use opendataloader-pdf

If not specified, it defaults to opendataloader-pdf.

Note that the actual PDF file parsing is not done by this service. What this service does is to upsert the record in 'kb.input'.