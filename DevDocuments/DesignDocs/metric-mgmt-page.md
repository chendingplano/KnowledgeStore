Use frontend-design skill to implement a metric management page. Add the page to ChenWeb/web/src/routes/home3, menu: "Knowledge Base -> Metrics". 

Requirements:
The page has Left Panel and Right Panel.

## Left Panel
Left Panel has the following elements:
- "Record ID" input field, used for entering the record id.
- "Search Records" button adjacent to the "Record ID" field. Clicking this button will
  open a dialog to let users search/query records from 'kb.inputs', which will display all
  the matching records in a list. Double clicking on a record in the list or clicking a record and press the "Select" button will close the dialog and populate the 'id' field of the selected record.
- "Retrieve" button: when clicked, it uses the record ID in "Record ID" to retrieve all the records from kb.metrics where 'input_record_id' = the record ID and display the result in the "Metrics" list.
- "Metrics" is a list of cards, one for each record retrieved. Clicking a card in the list will signal the Right Panel to show the content identified by the values of "source_line_spans"

## Right Panel

This panel displays the original file. The file type is from the 'type' field of the 'kb.inputs' table.
- When the "Retrieve" button on Left panel is clicked, if retrieves the document by the 'file_name' field of the 'kb.inputs' table and shows the original document (such as PDF, Word, etc.) in this panel.
- When clicking on a card in Left Panel, it moves the document display to the corresponding page and highlights the corresponding content. Left Panel provides an array of page_number:line_number retrieved from the field 'source_line_spans' of the table 'shared.nats_metrics'. It then retrieve the coordinates of each line from the file "<filename_root>.txt", called 'raw_line' file, in the same directory of the file in 'result_filename' of the table 'kb.inputs'.
- The format of lines in the 'raw_line' file is:
```text
<line_number> <page_number> <line_type> <content> <coordinate>
```
where '<line_number>' and '<page_number>' are integers, '<line_type>' is a single word, '<coordinate>' is: '[111.22, 333.44, 555.66, 777.88]'. Below is an example:

105 10 list-item 4.1.6 卫生间、浴室的地面应设置防水层，墙面、顶棚应设置防潮层。 [90,424.476,453,440.472]
where:
line_number: 105
page_number: 10
line_type: 'list-item'
content: 4.1.6 卫生间、浴室的地面应设置防水层，墙面、顶棚应设置防潮层。 
coordinates: [90,424.476,453,440.472] 
