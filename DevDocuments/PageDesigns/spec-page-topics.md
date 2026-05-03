## 1. Main Purposes

Show and edit topics (ref [1]).

## 2. Page Layout

- Add a "Semantic Web" menu. This menu has two child menu items: "Global Semantic Web" 
  and "Document Semantic Tree".
- Clicking "Global Semantic Web" opens the "Global Semantic Web" page (refer to "Global Semantic Web Design") in the right panel
- Clicking "Document Semantic Tree" opens the "Document Semantic Tree" page (refer to "Document Semantic Tree Design") in the right panel

## 3. Topic Knowledge Base
The system extracts topics from document chunks. These topics are stored as files under the directory TOPIC_TREE_ROOT_DIR.  

Each directory under TOPIC_TREE_ROOT_DIR is a 'Summary Category' (or 'category' for short). A path from
SUMMARY_TREE_DIR to a category form a 'Category Path'. Below is the structure of the Summary Knowledge Base:
```text
SUMMARY_TREE_DIR
  |-category
    metadata.txt
    summaries.txt
    |-category
      metadata.txt
      summaries.txt
      |-category
        metadata.txt
        summaries.txt
      |-category
        metadata.txt
        summaries.txt
      ...
    |-category
        metadata.txt
        summaries.txt
    ...
  |-category
    metadata.txt
    summaries.txt
  ...
```

### 3.1 'metadata.txt' File
The 'metadata.txt' contains the metdata about the category. Its format is:
```json
"desc":"the category description",
"category_type":"the category type",
"confidence":ddd,
"keywords":["ddd", ...],
"create_time":"yyyymmdd-hhmmss",
```

### 3.2 'summary.txt File
This file is optional. It contains all the summaries that belong to this node. 
These summaries are semantically close to each other. The file format is:
```text
93_0_0003
...
```
Each line is a Summary ID (refer to [1])

## 4. Summary Graph Design
The purpose of the "Summary Graph" page is to view/edit "Summary Knowledge Store", 
- This page is a tab-window. The first tab is always "Summary Graph". This tab cannot be closed.
- Other tabs are 'Category Summary' tabs, created dynamically and can be closed manually.

### 4.1 Display of Summary Graph Chart
Initially, it shows the first level categories as a horizontal tree chart.
Users can do the following on the chart:
- Show summaries (refer to "Show Summaries" Section)
- Expand/shrink a node
- Edit the node name
- Edit the node's 'metadata.txt'
- Delete a node
- Add a node
- Merge two nodes
- Split a node

### 4.2 Show Summaries
Summaries are shown in a separate tab in the right panel.
- Tab name is the category path, relative to SUMMARY_TREE_DIR. If the name is too long, cut off the leading
  characters with '...'. When the mouse moves over a table, show the full category path if it is shortened.
- Tabs can be manually closed.
- If a tab already exists, do not create a new one.
- The page has two sub-panels: "Left Panel" and "Right Panel"
- There is a slider between the Left and Right panel to adjust their widths
- The Left panel is a list of summaries from the 'summaries.txt' file (refer to "Summary List" section)
- The Right panel displays the PDF for the currently selected summary (refer to "PDF Display" section)

### 4.3 Summary List
- It is a list of summaries
- Each summary is displayed as a card with the following display fields:
  - PDF File Name (no path, just file name)
  - The summary keywords
  - The summary

### 4.4 PDF Display
It displays the PDF for the selected summary. It is similar to the PDF display page the "Document Details" menu item.

- Clicking a summary, if the current PDF is not the one for the clicked summary,
  load the corresponding PDF
- Move the display to the right page 

## 5. Document Summary Graph Design

The page is similar to `ChenWeb::home3/knowledge, the "Document Structure" menu item:
- It has two panels: "Left Panel" and "Right Panel", which is a tabbed panel
- The List Panel has a Search area and a list that lists all the records in 'kb.inputs' (default) or all the 
  searched records in 'kb.inputs'.
- The list displays records in one of two forms: one-line-per-record list or a list of blocks (similar to the one in 
  "Document Details")
- There is a slider between the 

## 6. References
[1] KnowledgeStore/DevDocuments/Specs/spec-chunking-fix-size.md
