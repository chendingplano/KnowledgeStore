## 1. Main Purposes

Show and edit topics (ref [1]).

## 2. Page Layout

- Add a "Semantic Web" menu. This menu has two child menu items: "Semantic Web" 
  and "Document Semantic Tree".
- Clicking "Semantic Web" opens the "Semantic Web" page (refer to "Semantic Web Design") in the right panel
- Clicking "Document Semantic Tree" opens the "Document Semantic Tree" page (refer to "Document Semantic Tree Design") in the right panel

## 3. Semantic Web
The system extracts topics from document chunks. A topic is defined by:
```text
record_id: 93,
topic_type: "topic-type"
lines: [ddd, ddd-ddd, ...]
topic_keywords: [keyword, ...]
category_paths: [(<path_keywords>, <path_confidence>, [<category_name>, <keywords>, <confidence>]), ...]
topic: "topic-content"
```
Topics are stored files (refer to the "Topic File" section in 'spec-chunking-fix-size.md') and indexed by topic's 
category paths.

### 3.1 Semantic Web

Each category of each category path maps to a directory under TOPIC_TREE_ROOT_DIR.

Each directory under TOPIC_TREE_ROOT_DIR is a 'Category'. A path from
TOPIC_TREE_ROOT_DIR to a category form a 'Category Path'. Below is the structure of the Summary Knowledge Base:
```text
TOPIC_TREE_ROOT_DIR
  |-category
    metadata.txt
    category.embed
    topics.txt
    |-category
      |-category
        metadata.txt
        category.embed
        topics.txt
      |-category
        metadata.txt
        category.embed
        topics.txt
      ...
    |-category
      metadata.txt
      category.embed
      topics.txt
    ...
  |-category
    metadata.txt
    category.embed
    topics.txt
  ...
```

### 3.2 'metadata.txt' File
The 'metadata.txt' contains the metdata about the category. Its format is:
```json
"desc":"the category description",
"confidence":ddd,
"keywords":["ddd", ...],
"create_time":"yyyymmdd-hhmmss",
```

### 3.2 'category.embed' File
This file stores the embedding vector for the category. Its format is:
```text
[0.01177215576171875, 0.0059967041015625, 0.039031982421875, ...]
```

### 3.3 'topics.txt File
This file is optional. It contains all the topics whose last category of one of its category paths
matches this directory.  These topics are semantically close to each other. The file format is:
```text
<record_id>_<topic_id>,
<record_id>_<topic_id>,
...
```
where `<record_id>` is the record ID and `<topic_id>` is the topic id (refer to 'spec-chunking-fix-size.md')

## 4. Semantic Web Design
The purpose of the "Semantic Web" page is to view/edit "topics indexed in the Semantic Web", 
- This page is a tab-window, similar to ChenWeb::/home3/knowledge, "Document Summaries => Summary Graph" page. 
  The first tab is always "Semantic Web". This tab cannot be closed.
- Other tabs show topics in a specific directory, created dynamically and can be closed manually.

### 4.1 Display of Semantic Web Chart

Note that this chart is almost identical to ChenWeb::/home3/knowledge "Document Summaries -> Summary Graph"
except:
- It shows topics instead of summaries
- The tree node is a rectangular block that shows the category important info instead of being a small circle.

### 4.2 Show Topics
Topics are shown in a separate tab in the right panel.
- Topics are defined in 'topics.txt'
- Not all categories have 'topics.txt' file. If a category does not have the file, it should grey out the button.
- Tab name is the category path, relative to SUMMARY_TREE_DIR. If the name is too long, cut off the leading
  characters with '...'. When the mouse hovers a tab, show the full category path if it is shortened.
- Tabs can be manually closed (except the first one).
- If a tab already exists, do not create a new one. Just open it.
- The page has two sub-panels: "Left Panel" and "Right Panel"
- There is a slider between the Left and Right panel to adjust their widths
- The Left panel is a list of topics from the 'topics.txt' file (refer to "Topics List" section)
- The Right panel displays the PDF for the currently selected topic (refer to "PDF Display" section)

### 4.3 Topic List
- It is a list of topics
- Each topic is displayed as a card with the following display fields:
  - The topic keywords
  - The topic

### 4.4 PDF Display
It displays the PDF for the selected topic. It is similar to the PDF display page the "Document Details" menu item.

- Clicking a summary, if the current PDF is not the one for the clicked summary,
  load the corresponding PDF
- Move the display to the right page 

## 5. Document Semantic Tree Design

The page is almost identical to ChenWeb::home3/knowledge, the "Document Summaries -> Summary Tree" page
except it displays topics instead of summaries.

## 6. References
[1] KnowledgeStore/DevDocuments/Specs/spec-chunking-fix-size.md
