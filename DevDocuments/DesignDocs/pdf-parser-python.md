Use superpowers to create a PDF parser.

- This is a service. The service monitors the database table 'kb.inputs' (refer to 'KnowledgeStore/database-table-schemas/table-schema-kb-input.md' for information about the table). It handles only the records with `type` = 'pdf'. If its status does not have an entry whose `operation` is "parse" or "parsing", it will pick up the record and start parsing the doc (i.e., extracting its text and document structure and save the results in the corresponding directory (see below). For more information about status management, refer to "Status Management" section.
- Currently, there are two PDF parsers: 
  (1) paddleocr: ~/Workspace/ThirdParty/paddleocr 
  (2) opendata: ~/Workspace/ThirdParty/opendataloader-pdf. 
  Note that we may add more PDF parsers in the future. Parser is specified by the field `parser_name`. If not specified, it defaults to 'opendata'.

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

For PDF parsing, the status JSON doc should be:
```json
For parsing-in-progress:
{
    "operation":"parsing",
    "progress":"percent-of-progress"
    "time":"timestamp-in-yyyymmdd hh:mm:ss-format",
    "time-used":"time-used-in-ms",
}

For parsed:
{
    "operation":"parsed",
    "proc-status":"success-or-failed",
    "time":"timestamp-in-yyyymmdd hh:mm:ss-format",
    "time-used":"time-used-in-ms",
    "error":"error-msg-if-failed"
}
```

The 'progress' is calculated by finished-pages/total-pages. The update frequency should be either finished parsing a new page or at least 3 seconds since the last update. 

Once finished, the "parsing" entry is replaced with the "parsed" entry.