# Overview
Research Topics manages a collection of articles, blogs, thoughts, or any form of artifacts. They are
collectively called Research Topic Bean (RTB).

## Research Topic Bean
The ontology of RTB has the following attributes.
| Name | Required | Description |
|------|----------|-------------|
| Name | Required | Description |
| bean_name | required | The name of the research topic research topic bean |
| bean_desc | optional | Its description |
| bean_keywords | optional | Its keywords |
| bean_type | required | The type of the research topic (Refer to [Bean Type](#bean-type)) |
| related_topics | optional | The related ontology beans |
| research_title | required | The title |
| research_subtitle | required | The subtitle |
| file_type | required | The type of its file (Refer to [File Types](#file-types)) |
| bean_category | required | It is a category path, mapping to file path |
| authors | optional | The artifact's author |
| content | optional | The content of the bean |
--------

## Bean Type
- Thoughts
- Design
- Spec
- Implementation
- Reading

## File Types
Currently, it supports:
- Markdown (.md)
- Typst (.typ)
- Text (.text)
- HTML (.mtml)