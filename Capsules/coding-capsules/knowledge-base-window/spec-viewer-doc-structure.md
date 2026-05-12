# Goals
Create a Doc Structure viewer page, similar to ChenWeb/web/routes/home3, "Knowledge Base -> Metrics". The menu item is "Knowledge Base -> Document Structure"

# File Name

Given a record_id, it reads the file: `ARTIFACT_DIR/group_id/record_id/<filename>.corrected`, 
where `<filename>` is the root of 'kb.inputs.staging_filename' + "_" + 'kb.inputs.parser_name'.

# File Format
Refer to 'spec-structure-static-analyzer.md' for information about the ".corrected" file format.

# Workflow
- User enters a record_id, it reads the corresponding '.corrected' file
- Show the corresponding PDF
- Lines are displayed in the left list, one record per line.
- When clicking a record, highlight the correponding areas in the PDF display
- Add a "Headings Only" button. When clicking it, it shows only lines whose line types are headings.