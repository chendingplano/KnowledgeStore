# Overview
It breaks its input into blocks.

# Input

- record_id: the value of kb.inputs.id, identifies the record to process
- input_file: this is a piece of memory that holds the content of an input file.
- file_name: the name of the input file

Input File Format:
The input file MUST conform to the canonical Line File spec:
`KnowledgeStore/DevDocuments/Specs/spec-line-file.md`.

## Filter
- If the config item: 'doc-processing.remove_toc_in_blocks' (in 'config.toml') is true, remove all the lines whose line type = 'toc'.

## Workflow
- It breaks the input into blocks
- Each block contains 'doc-processing.prev_overlapped_pages_in_blocks' previous overlapped page + INPUT_BLOCK_SIZE continuous pages +  'doc-processing.next_overlapped_pages_in_blocks' subsequent overlapped pages. 
- For each line, remove the `<font>`, `<font-size>`, and `<coordiante>` field and add `<flag>` field in front of the line: 'o' for overlap lines (i.e., the lines from an overlap page) and 'n' for normal lines.

## Output Format
```
<flag>\t<line_number>\t<page_number>\t<line_type>\<content>
...
```

The output is saved in a buffer. Do not save it in files.
