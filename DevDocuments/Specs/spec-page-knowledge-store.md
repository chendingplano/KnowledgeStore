# Knowledge Store Window

## Main Purposes

1. Show and edit Knowledge Stores.
2. Select a Knowledge Store as the Active Knowledge Store.
3. Provide a clear indication that most menu items under `/home3/knowledge` operate against the currently active knowledge store.

## Page Layout

- Show all knowledge stores as cards, one card per knowledge store.
- Provide an `Add` button. Clicking the button opens a dialog to create a new knowledge store.
- Each card has a `Modify` button. Clicking the button opens a dialog to edit the knowledge store.
- Each card has a `Delete` button. Clicking the button opens a dialog to confirm deletion.
- Clicking a card selects that knowledge store as the Active Knowledge Store.
- The selected card must have a clear visual highlight so the active state is obvious at a glance.
- The top of the page must show text indicating that a knowledge store is currently selected and that it serves as the Active Knowledge Store for the Knowledge System page.

## Design Direction

This page should behave primarily as a management dashboard, not only as a quick picker.

### Reasoning

- Users need to browse and edit knowledge stores from this page.
- Users also need to choose the knowledge store that drives the rest of the `/home3/knowledge` experience.
- Because selection depends on understanding what each store represents, the card design should emphasize content and source configuration first, while still showing operational status as secondary information.

## Card Content Priority

Each card should prioritize the following information:

1. Knowledge store identity and scope.
   - `ks_name`
   - `ks_type`
   - `ks_desc`
2. Source configuration.
   - `ks_sources`
   - enough summary information so the user can understand what content is included
3. Operational state as secondary signals.
   - `status`
   - `ks_sync_mode`
   - error or warning state when relevant

Operational status should be visible as compact badges, chips, or secondary metadata, but it should not dominate the card over the store's purpose and contents.

## Active Knowledge Store Behavior

- Users can click cards freely.
- Clicking a card immediately makes that knowledge store the Active Knowledge Store.
- No separate `Set Active` action is required.
- The active state should be persistent in the UI for the current page session.
- The page header area should explicitly state which knowledge store is active.
- Other menu items in `/home3/knowledge` should assume the currently active knowledge store unless they explicitly say otherwise.

## Open the Page

Clicking the `Knowledge Stores` menu item in the `/home3/knowledge` page opens this page.

## Database Table

Knowledge stores are stored in `kb.knowledge_store`.

Refer to `/Users/cding/Workspace/KnowledgeStore/table-schemas/table-knowledge-stores.md` for the table schema.
