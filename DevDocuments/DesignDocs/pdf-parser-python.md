Use superpowers to create a PDF parser.

- This is a service. 
- The service subscribes to NATS/JetStream, with the subject 'kb.pdf.staged'. The request payload is a JSON:
```json
{"record_id":123,"type":"pdf","status":"success","force":true}
```
where 'type' should ALWAYS be 'pdf'.
- When it receives a request, if the request.type is not 'pdf', it is an error. Update the status and finish.
- If request.status != 'success', update the status and finish.
- Retrieve the record from the table 'kb.inputs' (refer to 'KnowledgeStore/database-table-schemas/table-schema-kb-input.md' for information about the table). 
- If it failed retrieving the record, report an error and finish.
- If an element with "operation" == "parsing", the PDF file is being parsed now. Log the error and finish.
- If an element with "operations" == "parsed" and "proc_status = true" exists, the PDF file has already
  been parsed. If 'force' is false, log the event and finish.
- It parses the PDF using a PDF parser. Currently, there are there PDF parsers: 
  (1) paddleocr: ~/Workspace/ThirdParty/paddleocr 
  (2) opendata: ~/Workspace/ThirdParty/opendataloader-pdf. 
  (3) mineru: ~/Workspace/ThirdParty/mineru
Parser is specified by the field `parser_name`. If not specified, use the env var PDF_PARSER_NAME. If the env
var is empty or not defined, it defaults to 'loaddata'.
- When finish, set 'parser_name' to the parser_name used.

## Status Management
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

When a PDF is in the process of parsing, there should be an element in 'status':
```json
{
    "operation":"parsing",
    "progress":"percent-of-progress"
    "time":"timestamp-in-yyyymmdd hh:mm:ss-format",
    "time-used":"time-used-in-ms",
}
```
When parsing finishes, this element is replaced by:
```json
{
    "operation":"parsed",
    "proc-status":"success-or-failed",
    "time":"timestamp-in-yyyymmdd hh:mm:ss-format",
    "time-used":"time-used-in-ms",
    "error":"error-msg-if-failed"
}
```
The 'progress' is calculated by finished-pages/total-pages. The update frequency should be either finished parsing a new page or at least 3 seconds since the last update. 