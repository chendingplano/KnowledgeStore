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
- Use the primary LLM (specified by `EXTRACT_DOCMETA_MODEL_NAME`) together with the models file (`EXTRACT_DOCMETA_MODELS_FILE` or `MODELS_FILE`) and the prompt (specified by `EXTRACT_DOCMETA_PROMPT`) to extract the document metadata from the pages.
- If the primary extraction request fails and `EXTRACT_DOCMETA_MODEL_FALLBACK` is configured, retry the same extraction with the fallback model.
- If the LLM requests reading more pages, do so.
- The LLM outputs its extracted doc metadata as a JSON doc. Below is an example:
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
  "drafting_organizations": [...],
  "main_drafting_organizations": [...]
}
```

Doc Metadata
- Convert the following attributes to kb.inputs record:
  - "title" to 'kb.inputs.title'
  - "doc_no" 'kb.inputs.doc_no'
  - "publish_date" to 'kb.inputs.publish_date'

Language Normalization
- Before saving the JSON doc, normalize `metadata.language` by calling `ApiUtils.NormalizeLang(metadata.language)`.
  This maps full language names and locale variants (e.g. "Chinese", "中文", "zh-CN", "English", "en-US", "日本語") to canonical lowercase BCP-47 base codes (e.g. "zh", "en", "ja").
  Store the normalized value back into `metadata.language` before writing to `kb.inputs.doc_metadata`.

'kb.inputs.authors' Field
  - If "authors" is not empty, save it to 'kb.inputs.authors'
  - Otherwise, if "main_drafting_persons" is not empty, save it to 'kb.inputs.authors'
  - Otherwise, if "drafting_persons" is not empty, save it to 'kb.inputs.authors'

Save the JSON doc to 'kb.inputs.doc_metadata'

## Error Handling

If any error occurs, upsert the following element to kb.inputs.status:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation":"extract_metadata",
    "proc_status":"failed",
    "error":"error-msg",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

If successful, upsert the following element to kb.inputs.status:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation":"extract_metadata",
    "proc_status":"success",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```
