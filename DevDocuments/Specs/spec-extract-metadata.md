## Summary
This is a Go program that extracts document metadata, such as document title, document number, pushers, etc. and save the results in 'kb.inputs'. 

Make sure create a separate JetStream consumers for this service.

## Retrieve Record

It retrieves the record from 'kb.inputs' by 'kb.inputs.id' = 'event.record_id'. 

Error Handling:
- If failed accessing the database, report the error and finish.
- If the record does not exist, report the error and finish.

## Inputs
- record_id: this is the value of kb.inputs.id
- input_file: this is a piece of memory that holds the content of an input file.

Input File Format:
The input file MUST conform to the canonical Line File spec:
`KnowledgeStore/DevDocuments/Specs/spec-line-file.md`.

## Workflow
- Retrieve the record by 'record_id'. 
- Read the first EXTRACT_DOCMETA_NUM_PAGES pages from the input
- Use the LLM (specified by EXTRACT_DOCMETA_LLM_NAME) to extract the metadata with the prompt (specified by EXTRACT_DOCMETA_PROMPT) to extract the document metadata from the pages. If the LLM request reading more pages, do so. The LLM outputs its extracted doc metadata as a JSON doc. Below is an example:
```json
{
  "title": "...",
  "doc_no": "...",
  "authors": [...],
  "metadata": {
    "notes": ["...", "..."],
    "source": {
      "url": "...",
      "journal": "...",
      "publisher": "...",
      "conference": "... 
    },
    "version": "...",
    "abstract": "...",
    "keywords": [],
    "language": "...",
    "subtitle": "...",
    "candidates": {
      "title": [ "...", "..." ],
      "authors": []
    },
    "confidence": ...,
    "page_count": "...",
    "identifiers": {
      "doi": "...",
      "isbn": "...",
      "issn": "...",
      "arxiv_id": "..."
    },
    "document_type": "...",
    "organizations": [
      "..."
    ]
  },
  "publish_date": "...",
  "drafting_persons": [],
  "implementation_date": "...",
  "main_drafting_persons": [...],
  ],
  "drafting_organizations": [...],
  ],
  "main_drafting_organizations": [...]
}
```

Doc Metadata
- Convert the following attributes to kb.inputs record:
  - "title" to 'kb.inputs.title'
  - "doc_no" 'kb.inputs.doc_no'
  - "publish_date" to 'kb.inputs.publish_date'

'kb.inputs.authors' Field
  - If "authors" is not empty, save it to 'kb.inputs.authors'
  - Otherwise, if "main_drafting_persons" is not empty, save it to 'kb.inputs.authors'
  - Otherwise, if "drafting_persons" is not empty, save it to 'kb.inputs.authors'

Save the JSON doc to 'kb.inputs.doc_metadata'

## Error Handling

If any error occurs, upsert the following element to kb.inputs.status:
```json
  {
    "operation": "extract_metadata",
    "proc_status": "failed",
    "error": "error-message",
    "start_time": "...",
    "ms-used": ...
  },
```

If successful, upsert the following element to kb.inputs.status:
```json
  {
    "operation": "extract_metadata",
    "proc_status": "success",
    "start_time": "...",
    "ms-used": ...
  },
```
