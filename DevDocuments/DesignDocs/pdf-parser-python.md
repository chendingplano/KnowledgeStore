Use superpowers to create a PDF parser.

- This is a service. 
- The service subscribes to NATS/JetStream, with the subject 'kb.pdf.staged'. The request payload is a JSON:
```json
{"record_id":123,"type":"pdf","proc_status":"success","force":true}
```
where 'type' should ALWAYS be 'pdf'.
- Retrieve the record from the table 'kb.inputs' (refer to 'KnowledgeStore/database-table-schemas/table-schema-kb-input.md' for information about the table). If it failed retrieving the record, report an error and finish.
- If there is an element with "operation" == "parsing" in 'status', the PDF file is being parsed now. Update "proc_status" with the error message "file is parsing" and finish ([Status Management](#status-management))
- If there is an element with "operation" == "parsed" and "proc_status" == true exists, the PDF file has already been parsed. If request.'force' is false, log the event and finish.
- It parses the PDF using a PDF parser. Currently, there are there PDF parsers: 
  (1) paddleocr: ~/Workspace/ThirdParty/paddleocr 
  (2) opendata: ~/Workspace/ThirdParty/opendataloader-pdf. 
  (3) mineru: ~/Workspace/ThirdParty/mineru
Parser is specified by the field `parser_name`. If not specified, use the env var PDF_PARSER_NAME. If the env var is empty or not defined, it defaults to 'loaddata'.
- Output file name: the output file name is: \<filename-root\> + "_" + \<parser_name\> + ".json"
- When finish, set 'parser_name' to the parser_name used.

## [Status Management](status-management)
An input may be processed by a pipeline. For Field `type` = 'pdf', it will be processed by:
 - PDF Parser: Extracting text and document structures from the PDF document
 - Use an LLM to extract topics from the extracted text and generate chunks based on the topics
 - Generate a one-line summary; 

Field 'status' keeps track of the process status. It is an array. Each element in the array is a JSON doc with the following format:
```json
[
    {"operation":"the-opr", "time":"timestamp-in-yyyymmdd hh:mm:ss", "proc-status":"success or fail", "error":"error-msg"},
    {"operation":"the-opr", "time":"timestamp-in-yyyymmdd hh:mm:ss", "proc-status":"success or fail", "error":"error-msg"},
    ...
]
```
where:
- 'operation' specifies the operation performed on the file, such as 'parsing', 'analyzing', 'adding-to-knowledge', etc.
- 'time': the time when the operation was performed, 
- 'proc-status': success or failed, and "error": the error message.
```

For this service, its format is one of the following:

When it is in the process of parsing:
```json
  {
    "operation": "parsing",
    "ms-used": 1893447,
    "num_pages": 25,
    "start_time": "20260413 23:21:39",
    "percent": the-percent
  }
```

When it finishes, replace the above entry with:
```json
  {
    "operation": "parsed",
    "ms-used": 1893447,
    "num_pages": 25,
    "start_time": "20260413 23:21:39",
    "proc-status": "success-or-failed"
    "error": "error-message-only-when-it-failed",
  }
```

The 'progress' is calculated by finished-pages/total-pages. The update frequency should be either finished parsing a new page or at least 3 seconds since the last update. 