# Description
This table is used to manage inputs to a Knowledge Base (KB). A KB is a collection of files stored in a specific directory. Files are organized in a form of File-Tree.

Inputs to KB can be virtually anything: markdown files, text files, images, documents, etc. A record is created for each
input. 

## Table Schema

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

## Status Management
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

As an example, for PDF parsing, the status JSON doc should be:
```json
For parsing-in-progress:
{
    "operation":"parsing",
    "progress":"percent-of-progress"
    "time":"timestamp-in-yyyymmdd hh:mm:ss-format",
    "time-used":"time-used-in-ms",
}

Once the parsing finishes, the above entry is replaced with:
{
    "operation":"parsed",
    "proc-status":"success-or-failed",
    "time":"timestamp-in-yyyymmdd hh:mm:ss-format",
    "time-used":"time-used-in-ms",
    "error":"error-msg-if-failed"
}
```

The 'progress' is calculated by finished-pages/total-pages. The update frequency should be either finished parsing a new page or at least 3 seconds since the last update. 

The idea applies to other types of inputs.