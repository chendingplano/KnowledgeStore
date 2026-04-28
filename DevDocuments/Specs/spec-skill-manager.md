# Goals
Manage skills.

## Database Tables

Skills are stored in the table 'kb.skills' (refer to 'table-kb-skills.md' and 'table-kb-skill-categories.md').

## Frontend Pages

When clicking the "Skills" menu in 'ChenWeb::/home3' window, currently, it expands to three menu
items: 'All Skills', 'Active' and 'New Skill'.

Clicking on 'All Skills', it should expand the menu item based on the categories retrieved from the table
'kb.skill_categories', organized by category levels, shown as a menu tree, but showing only the first level 
categories only.

Clicking a category will:
- Show all the skills that the selected category matches. 
- Show all its next-level categories, if any

Note that a skill's category is an array of category names, similar to file names. When a category is selected,
it means a the full path to the selected category.

The right panel list all the matching skills. 

### Skill List
The list has a "Settings" button. Clicking the button will open a dialog to let users configure the list.
The configurable items include:
- The columns of the list: users can select/deselect columns
- 'Delete' column: true|false
- 'Edit' column: true|false

Settings must be persisted per user.

**Operation Columns**
In addition to showing fields from 'kb.skills', it has the following operation columns:
- 'Delete': delete the record.
- 'Edit': edit the record