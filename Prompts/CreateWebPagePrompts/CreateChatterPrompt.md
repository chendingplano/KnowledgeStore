Use superpowers to create an AI chat page similar to ChatGPT chat using Svelte, save it in ChenWeb/web/src/lib/components/shared-ui/chatter-01.svelte and add a menu Chat to ChenWeb/web/src/routes/home3.

# Design Guidelines

## Chat Page Layout:
- The Chat Page is loaded into the middle panel when the 'Chat' menu item is selected
- The page has two panels: Chat Panel and Info Panel
- The page style should be consistent to ChenWeb/web/src/routes/home3, especially it supports light and dark modes
- Users can create multiple Chat in the way similar to multiple tags in a browser
- There is a slider between Chat Panel and Info Panel. Their widths can be adjusted by sliding

### Chat Panel
- An Agent Selector button with the following options:
    - OpenClaw (the default)
    - Claude Code
    - Codex
    - Qwen Code
    - OpenCode
    - pi
    (The list is configured in 'Settings'. The above is the default)
- A Model Selector that lets users select a model: "ChatGPT 5.4, ...", the list is defined from the 'Settings' (refer below)
- An Attatchment button ("+") with the following options:
    - Photos and Files
    - Recent Files
    - A separator 
    - Create an image
    - Deep Research
    (The list is configured in 'Settings'. The above is the default)
- Plugin/Skill Selector:
    - Create Skill
    - superpowers
    - docx
    - pptx
    - pdf
    (The list is configured in 'Settings'. The above is the default)
- Result button with the options:
    - Text
    - Markdown
    - JSON
    - Web Page
    (The list is configured in 'Settings'. The above is the default)
- Prompt button: clicking the button will pop up a Prompt Selection dialog:
    - A Search area
    - List of prompts, with most recent on the top
    (Prompts are read from the backend)
- A dictate button
- A 'Text' button. Clicking the button will pop a Text editor to enter/edit the inputs
- A "New Session" button to start a new session
- The '/' commands: enter '/' will show a listt of slash-commands. The commands are configured in 'Settins'

### Info Panel
- The Info Panel is a Tabbed Panel with the following tabs:
    - Dialog Sub-Panel
    - Setting Sub-Panel

#### Dialog Sub-Panel
- Dialog Sub--Panel shows the converation history
- A vertical scroll bar shows automatically when the history hight out grows the sub-panel hight

#### Setting Sub-Panel
The Setting Sub-Panel configures the Chat Page:
- Agent Selector List
- Model Selector List
- Attachment Selector List
- Plugin/Skill Selector List
- Result Options List

## Development Requirements
- Frontend is Svelte (ChenWeb/web). 
- Backend is Go (ChenWeb/server).

# REST API and Backend
- Create all the needed REST API endpoints
- Create all the handlers with stubs only

# Activities

## Implementation Summary (2026-03-14)

Tool: Codex

Completed an end-to-end chat page implementation for `home3` using Svelte + Go stubs, following the requested ChatGPT-like layout and controls.

### Frontend (Svelte)
- Created new chat UI component:
  - `ChenWeb/web/src/lib/components/shared-ui/chatter-01.svelte`
- Implemented two-panel chat page:
  - **Chat Panel** (left):
    - Agent selector (default options: OpenClaw, Claude Code, Codex, Qwen Code, OpenCode, pi)
    - Model selector (default includes `ChatGPT 5.4`)
    - Attachment menu (`+`) with configured options and separator
    - Plugin/Skill selector (Create Skill, superpowers, docx, pptx, pdf)
    - Result selector (Text, Markdown, JSON, Web Page)
    - Prompt button with prompt selection dialog:
      - search input
      - prompt list sorted most-recent first
    - Dictate button
    - Text button with popup text editor
    - New Session button
    - Slash command popup when input starts with `/`
    - Multi-session chat tabs (browser-tab style)
  - **Info Panel** (right):
    - Tabbed panel with:
      - Dialog history sub-panel (scrollable)
      - Settings sub-panel for configuring selector lists
- Added adjustable splitter between Chat Panel and Info Panel (drag to resize).
- Styled to match `home3` visual tokens and support light/dark mode.

### Frontend Integration in home3
- Added **Chat** menu item to the navigation rail:
  - `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`
- Wired chat page rendering in the middle content panel when Chat is selected:
  - `ChenWeb/web/src/lib/components/home3/content-panel.svelte`

### Frontend API Service
- Added chat API service wrapper:
  - `ChenWeb/web/src/lib/services/chatterService.ts`
- Provides typed methods for settings, prompts, slash commands, sessions, dialogs, and message send.

### Backend (Go) REST Stubs
- Created new handler package with stub-only handlers:
  - `ChenWeb/server/api/chatterhandler/handler.go`
- Registered new routes in:
  - `ChenWeb/server/api/routes.go`

Implemented stub endpoints:
- `GET /api/v1/chatter/settings`
- `PUT /api/v1/chatter/settings`
- `GET /api/v1/chatter/prompts`
- `GET /api/v1/chatter/slash-commands`
- `GET /api/v1/chatter/sessions`
- `POST /api/v1/chatter/sessions`
- `GET /api/v1/chatter/sessions/:id/dialogs`
- `POST /api/v1/chatter/sessions/:id/messages`

### Verification
- Ran Go formatting and API tests successfully (with local `GOCACHE` override in sandbox):
  - `cd ChenWeb && GOCACHE=/tmp/go-build go test ./server/api/...`
- Ran frontend type/svelte checks:
  - Existing unrelated repository errors remain in other files (`DspyStudio.svelte`, `routes/home2/+page.svelte`),
  - No new blocking errors introduced by the new chat component itself.

### Notes
- Backend handlers are intentionally stubbed as requested.
- Settings/prompt/session data currently uses stub responses/fallbacks; ready to connect to database-backed persistence next.
