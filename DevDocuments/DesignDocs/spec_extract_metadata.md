## Summary
This is a Go service that extracts document metadata, such as document title, document number, pushers, etc. and save the results in 'kb.inputs'. 

## JetStream Subscription
It subscribes to JetStream, with subject 'kb.line-file-generated'. The event payload is:
```json
{
	"record_id":"...",
	"filename":"...",
	"force":true | false
}
```
where:
- "record_id": mandatory, is the value of table field 'kb.inputs.id',
- "filename": optional. If specified, it specifies the name of its input. If the file name has no path, the file is in the same directory derived the field kb.inputs.result_filename.
- "force": optional. If not specified, it defaults to true.

IMPORTANT:
There are multiple processes that subscribe to this same subject ('kb.line-file-generated'), such as:
- Extract Document Metadata (this service)
- Chunking (a service)
- Extract Metrics (a service)
- ...

Make sure create a separate JetStream consumers for this service.

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

Input File Format:

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

## Workflow
- Retrieve Record (see above)
- Retrieve Input File (see above)
- Read the first EXTRACT_DOCMETA_NUM_PAGES pages from the input
- Use the LLM (specified by EXTRACT_DOCMETA_LLM_NAME) to extract the metadata with the prompt (specified by EXTRACT_DOCMETA_PROMPT) to extract the document metadata from the pages. If the LLM request reading more pages, do so.
- Save the extracted doc metadata to the 'kb.inputs' record.

Doc Metadata
- Save:
  - document name to 'kb.inputs.title'
  - document number to 'kb.inputs.doc_no'
  - publish date to 'kb.inputs.publish_date'
  - authors to 'kb.inputs.authors
  - save the extracted doc metadata (a JSON doc) to 'kb.inputs.doc_metadata'

