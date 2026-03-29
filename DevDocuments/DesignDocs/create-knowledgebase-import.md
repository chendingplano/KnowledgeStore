Use superpowers to develop the following web page:

The menu: "Knowledge Base" in /Users/cding/Workspace/ChenWeb/web/src/routes/home3/+page.svelte currently has three sub-menu items: Documents, Search and Import. All these menu items are not implemented yet.

When clicking on "Import", it should open a web page in the center panel:
1. The page retrieves records from the table kb.inputs (refer to /Users/cding/Workspace/KnowledgeStore/DevDocuments/create-pdf-parser.md for the table definition)
2. There is a Search area, which contains:
   (a) Doc Type: a pulldown menu with ["all" (the default), "pdf", "doc", "excel", "ppt", "text", "json", "xml", "markdown", "typst"]
   (b) Pending: all records whose 'status' does not have {"operation":"parsing", ...}
   (c) Parsed Success: all records whose 'status' does have {"operation":"parsing", "status":"success", ...}
   (d) Parsed Failed: all records whose 'status' does have {"operation", "parsing", "status": not equal to "success", ...}
   (e) File Name: an input to search by filename
   (f) Start Time and End Time: time picker to search by time
3. A table with paging, page size defaults to 50