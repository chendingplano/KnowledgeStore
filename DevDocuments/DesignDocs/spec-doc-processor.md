## Summary
This is a service to process parsed store objects. Its main.go is in aas/server/cmd/doc-processsor.

## JetStream Subscription
It subscribes to JetStream, with subject 'kb.line-file-generated'. The event payload is:
```json
{
	"record_id":"...",
	"filename":"...",
    "operation":"...",
	"force":true | false
}
```
where:
- "record_id": mandatory, is the value of table field 'kb.inputs.id',
- "filename": optional. If specified, it specifies the name of its input. If the file name has no path, the file is in the same directory derived the field kb.inputs.result_filename.
- "operation": optional. If present, which is a list of doc processor names, it lists the doc processor(s) this service will use on the input. Refer to "Operation" section for more info. 
- "force": optional. If not specified, it defaults to true.

## Retrieve Record

It retrieves the record from 'kb.inputs' by 'kb.inputs.id' = 'event.record_id'. 

Error Handling:
- If failed accessing the database, report the error and finish.
- If the record does not exist, report the error and finish.

## Input File
- If event.filename is present and not empty, it specifies the input file.
- If the file name does not contain path, its directory is derived from kb.inputs.result_filename. 
- If the file name contains path, it must be an absolute path
- If event.filename is absent or empty, the input file name is: '<filename_root>' + '_' + kb.inputs.parser_name + '.txt', where '<filename_root>' is derived from kb.inputs.staging_filename.

Error Handling:
- If kb.inputs.parser_name is null or empty, update 'kb.inputs.status' with error 'missing parser name' and finish.
- If kb.inputs.result_filename is null or empty, update 'kb.inputs.status' with error 'missing result filename' and finish.
- If the specified input file does not exist, update 'kb.inuts.status' with error "input file not exist" and then finish.
- If the specified file is empty, update 'kb.inputs.status' with error "input file empty" and then finish.

## Input File Format
The input file is a sequence of lines of the following format:
```text
<line_number> <page_number> <line_type> <content> <coordinate>
```
where:
- '<line_number>': an integer that marks the line number, starting from 1
- '<page_number>': an integer that marks the page number
- '<line_type>': the type of the line, such as 'heading', 'paragraph', 'list-item'. This can be useful for LLMs to analyze the content.
- '<cnotent>': the actual content of the line
- '<coordinate>': the coordinate of the line, in form of [x1, y1, x2, y2]

## Doc Processors
This service is a controller. For a received event, it applies a number of doc processors to it.
Currently, it has the following doc processors:
| Seqno | Processor Name | Dependence | Explanation |
|---|---|---|---|
|1 | chunking | none | Chunking Processor. Refer to [1] for its spec |
|2 | extract_doc_metadata | after chunking | Extract Doc Metadata Processor. Refer to [2] for its spec |
|3 | extract_metrics | after chunking | Extract Metrics Processor. Refer to [3] for its spec |
---

## Operation

If present, it specifies the doc processor to apply to the input file (or chunk files). Currently,
the valid values are: 'chunking', 'extract_doc_metadata' and 'extract_metrics'.
If multiple processors are specified, they must be applied in the order in which they are listed.

## Workflow

- Receive an event
- Retrieve the record by event.record_id
- Read the input file (refer to "Input File" section)
- Apply all the doc processors in the same order as listed in "Doc Processors" section

## References

[1] Chunking Processor Spec: KnowledgeStore/DevDocuments/DesignDocs/spec-chunking.md
[2] Extract Doc Metadata Spec: KnowledgeStore/DevDocuments/DesignDocs/spec-extract-metadata.md
[3] Extract Metrics Spec: KnowledgeStore/DevDocuments/DesignDocs/spec-extract-metrics.md