# Overview

This document outlines the workflow of Knowledge Store.

## Workflow

| Seqno | Language | Service/Processor | Directory | Explanation |
|---|---|---|---|---|
| 1 | Go | Staging Service | ChenWeb/server/cmd/pdf-parser | Monitor the staging directory. Once new files are added to this directory, it moves the file into the repo directory and insert a record to kb.inputs |
| 2 | Python | PDF Parser service | aas/python/pdf-parser | Parse PDF documents |
| 3 | Go | Parse result converter service | ChenWeb/server/cmd/pdf-result-converter | Convert PDF parse result into a line file |
| 4 | Go | Doc Processor service | ChenWeb/server/cmd/doc-processor | Apply doc processors to a line file |
---
