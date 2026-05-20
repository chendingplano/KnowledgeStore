# Overview
Document metadata is stored in 'kb.inputs.doc_metadata' in JSON documents.

## Document Metadata Attributes
Document metadata attributes are grouped as follows:
- Basic Info
  "title": from 'title' or 'metadata.candidates.title'
  "subtitle"
  "doc_no": "T/GCM 004—2019",
  "language": from 'metadata.language',
  "publisher": from 'metadata.publisher',
  "page_count": retrieve from its line file
- Document Type
  "ICS"
  "CCS"
  "document_type": from 'metadata.document_type'
- Dates
  "publish_date": "2019-12-05",
  "implementation_date": "2019-12-05",
- Versions
  "version": from 'metadata.version',
- Identifiers
  "doi": from 'metadata.identifiers.doi'
  "isbn": from 'metadata.identifiers.isbn'
  "issn": from 'metadata.identifiers.issn'
  "arxiv_id" from 'metadata.identifiers.arxiv_id'
  "std_no": from ???
- Context
  "abstract"
  "summary": from the document top level summary 
  "first_level_headings"
  "Keyords": from 'metadata.keywords'
- Authors
  "authors": from 'authors' or 'metadata.candidates.authors',
  "drafting_persons": [...]
  "main_drafting_persons": [],
  "drafting_organizations": [...]
  "organizations": [...]
  "main_drafting_organizations": []
- Source
  "url": from 'metadata.source.url',
  "journal": from 'metadata.source.journal',
  "conference": from 'metadata.source.conference',