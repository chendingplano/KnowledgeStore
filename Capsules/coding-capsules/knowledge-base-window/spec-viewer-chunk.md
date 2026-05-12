# Goals
Create a topic-chunk viewer page, similar to ChenWeb/web/routes/home3, "Knowledge Base -> Metrics".
The menu item is "Knowledge Base -> Chunks"

## Topic Chunks

Refer to 'spec-chunking-topic.md' for information about topic-driven chunking.

Given a record_id, its topic chunks are stored in the file:
    ARTIFACT_DIR/group_id/record_id/topics.txt

'topics.txt' file format is:
```text
 <seqno> <topic_type> <lines> <keywords> <topic>
 <seqno> <topic_type> <lines> <keywords> <topic>
 ...
```

## Workflow
- User enters a record_id, it retrieves all the topic chunks from the corresponding 'topics.txt' file.
- Show the corresponding PDF 
- Chunks are displayed in the left list, one content block per chunk. 
- The content block consists of:
    - First Line: 'seqno', 'topic_type'
    - Second Line: 'topic'
    - Third Line: 'keywords'
    - Followed by the actual content of all the lines in 'lines'
- Calculate the bounding box of the chunk
- When clicking a content block, highlight the correponding areas in the PDF display