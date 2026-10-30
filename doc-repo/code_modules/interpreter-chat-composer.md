# Code module: `chat-composer`

**Code module ID:** `chat-composer` \
**Classes using it:** `chat-composer`; specialised classes, such as a composer for one assistant,
may reuse it \
**Implementation status:** implemented and active, 2026-10-30 \
**Design revision:** R2, 2026-10-30 — **approved** \
**Approval:** the user approved the proposal on 2026-10-30 together with the R2 changes listed in
the [review record](#review-record) \
**Catalogue row:** `kb.code_modules` `chat-composer`, "Chat Composer", type `element`,
`module_doc` `interpreter-chat-composer.md`, status `active`, from migration
`ChenWeb/project_migrations/20261030000005_wpi_chat_elements.sql` \
**Companion module:** [`chat-panel`](interpreter-chat-panel.md), which shows the conversation this
composer sends to \
**Source UI:** ChenWeb Development → Chat (`/development?view=chat`): the message box and tool bar
at the bottom of `ChenWeb/web/src/lib/components/shared-ui/chatter-01.svelte`, which is unchanged \
**Frontend:** `ChenWeb/web/src/lib/wpi/elements/ChatComposerElement.svelte`, registered in
`elements/index.ts`; the chat shared with `chat-panel` in `ChenWeb/web/src/lib/wpi/chat-session.svelte.ts`;
assistant and model selection in `ChenWeb/web/src/lib/wpi/chat-agents.ts` \
**Backend:** `codeModules["chat-composer"]` in `ChenWeb/server/api/wpi/validate.go`; checks in
`ChenWeb/server/api/wpi/chat_attributes.go` \
**OpenSpec:** ChenWeb change `wpi-chat-elements` \
**Part of:** reusable module `20261026-01`, [Web Page Interpreter frontend](../modules/module-web-page-interpreter-frontend.md) \
**Design:** [WPI devdoc](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md) §3.5 Elements,
§3.7 Element layouters, §3.8 Input doc, §5 Actions, §7 Validation; [input reference](interpreter-input.md)

## Purpose and boundary

The composer is where a user writes a message to an AI assistant and sends it. It draws a
multi-line message box and, under it, a tool bar: the assistant (agent) and model, a prompt
picker, a larger text editor, New Session, and Send, which becomes Stop while a reply streams
in. Replies are not shown here. They appear in the Chat tab of a
[`chat-panel`](interpreter-chat-panel.md) on the same page ([Chat session](#chat-session)).

A typical page reproduces ChenWeb's Chat page: the composer in a bottom pane and the panel in
a right pane. Another page can use a composer restricted to one assistant, with only the
controls that page needs, without new code.

Only the four real assistants are offered: `Claude Code`, `Codex`, `DeepSeek Harness` and
`pi`, each backed by a harness gateway on the server. A page chooses among them in its
descriptor.

Not part of the composer:

- the conversation and the session list, which belong to `chat-panel`;
- the skill picker ("Create Skill") at the top of chatter-01, whose choice is never sent;
- Attach and Dictate, which chatter-01 draws but which do nothing (left out, Q1);
- the output format select, which only the placeholder assistants used (removed in R2);
- the "Close panel" button of the ChenWeb shell;
- data binding to the input doc, WPI action triggers and appearance attributes.

## What changes from chatter-01

| Area | chatter-01 today | Composer |
| --- | --- | --- |
| Scope | One component draws the tool row, session tabs, conversation, composer and side panel | Message box and tool bar only; the conversation and sessions are in `chat-panel` |
| Assistants | The chat settings list (placeholder assistants included) with the harness assistants appended | The four harness-backed assistants, chosen in the descriptor |
| Controls | A fixed row, including Attach, Dictate and Output format | `toolbar` chooses and orders the working controls |
| Failed send | A made-up reply "Stub response from …" for placeholder assistants | An error notice in the conversation; the sent message stays visible |
| Colours | A hard-coded palette per light/dark mode | ChenWeb theme colours, light and dark |
| Prompt and text editor dialogs | Overlays inside the chat component | App modal dialogs: focus kept inside, Escape closes |
| Sending from the keyboard | Only by tabbing to Send | Also Ctrl+Enter / ⌘+Enter |

<a id="chat-session"></a>

## Chat session

This section is the contract that `chat-composer` and `chat-panel` share.

**Scope.** All chat elements of one page instance share one chat. No attribute pairs them:
the `chat-composer` and every `chat-panel` of a page instance work on the same chat. A page
opened in a pane of another page is a different page instance with its own chat. A page has at
most one composer ([Validation](#validation-and-errors)). Two independent chats on one page
are not supported; a pairing attribute such as `channel` could be added later without
changing pages that leave it out.

**Contents.** The chat holds the configured and offered assistants, the selected assistant and
model, each harness's model list, the open sessions and which one is active, each session's
conversation, whether a reply is streaming in a session, the harness's session history, and the
prompts and slash commands. This is runtime state, not data: it is not in the input doc, `save`
and `save-page` never send it, it never makes the page dirty, and the unsaved-changes prompt
does not look at it.

**Lifetime.** The chat is created when the first chat element of the page instance mounts.
It then loads, once, the list of configured harnesses, the prompts and the slash commands.
It is kept while the page is hidden in the Panel Cache: hidden pages stay mounted, so a
streaming reply keeps arriving. When the last chat element of the page instance is
destroyed, which happens when the page instance closes, the chat is discarded and every
streaming reply is aborted. Aborting closes the stream, which interrupts the harness's turn.
The session stays on the harness, where the panel's History menu can open it again. An
unsent draft is lost when the page closes.

**Services.** The module calls existing ChenWeb services itself; it does not run WPI actions:

| Purpose | Service | Behavior today |
| --- | --- | --- |
| Configured assistants | `GET /api/v1/harness-frontend` | The harnesses whose gateway the server has (`CLAUDE_CODE_`, `CODEX_`, `DEEPSEEK_HARNESS_`, `PI_HARNESS_` + `GATEWAY_URL` and `GATEWAY_SECRET`). **Admin-only.** |
| Models, sessions, streamed turns, interrupt, permission decisions | `/api/v1/harness-frontend/<harness>/…` | Real assistants. **Admin-only.** |
| Prompts, slash commands | `GET /api/v1/chatter/prompts`, `/slash-commands` | Fixed lists from a stub handler; the module has built-in fallbacks. |

Agent names map to harnesses in code (`HARNESS_BY_AGENT` in `harnessFrontendService.ts`).
Descriptor attributes only choose among these four names and among model names. They never
name URLs, endpoints, tables or credentials, and they grant no access: a user who is not an
admin gets the server's refusal as an error notice in the conversation.

## Descriptor rules and precedence

A class has its own `descriptor_id`, `schema_version` `"0.4"` and `code_module_id`
`"chat-composer"`. An instance lives at `$.panels.<pane_id>.elem_list[i]`, names its class in
`element` and holds the complete class row in `class`; `element` equals
`class.descriptor_id`. In the tables, `E.<name>` is the instance's flat attribute; its
definition is `E.class.<name>`, or `$.<name>` in the class row. Properties groups are
presentation only and add no nested objects.

Each definition has an author-facing `help_tip` in English and Chinese, an optional
`default_value` and an optional `instance_modifiable`. Every attribute has a module fallback,
so a class normally leaves `default_value` out or gives a concrete value. A specialised class
may still use `default_value: null` to make every instance choose, for example
`default_agent`. `instance_modifiable: false` needs a non-null default and forbids any
instance value, even an equal one. An instance value of `null` is invalid for every attribute.

For a valid instance each attribute resolves to the fixed class value, else the instance
value, else the class copy's non-null default, else the module fallback in the tables below.
The composer has no action-valued attributes. Later edits to a class reach only instances
placed afterwards; an attribute added to this module later must have a fallback that keeps
today's behavior for copies that do not name it.

`label`, `data_binding` and `binding_mode` are not supported: a class that names them gets a
warning, and they have no effect. A page-level `binding_mode` does not apply to the composer;
a `read-only` page can still send messages.

## Attribute contract

### Message box

| Exact path | Type and allowed values | Absence, validation and behavior |
| --- | --- | --- |
| `E.placeholder` | Localized text: a nonempty string, or a language map with a nonempty `en` | Absent: the module text "Ask anything... Use '/' for commands." / "随便问… 输入“/”使用命令。". Shown only while the box is empty; never the accessible name. Language maps fall back to `en`. An empty string is invalid, as for every WPI text attribute. |
| `E.rows` | Integer 1–20 | `3`. Visible lines of the box. Longer text scrolls inside the box; the box does not grow. `0`, fractions and numeric strings are invalid. |
| `E.slash_commands` | Boolean | `true`: while the draft starts with `/`, list the matching slash commands under the box; choosing one replaces the draft with the command and a space. `false`: no list, and `/…` is sent as typed. |

### Tool bar

| Exact path | Type and allowed values | Absence, validation and behavior |
| --- | --- | --- |
| `E.toolbar` | Array of 0–5 distinct tokens: `agent`, `model`, `prompt`, `text_editor`, `new_session` | `["agent", "model", "prompt", "text_editor", "new_session"]`. The controls shown, left to right, in array order. `[]` shows only Send. Send (or Stop) is always present, last and right-aligned. Unknown, repeated and non-string tokens are errors; `attach`, `dictate` and `output_format` are unknown. |

| Token | Control and behavior |
| --- | --- |
| `agent` | A menu of the offered assistants, labelled with the selected one. Choosing an assistant shows its sessions ([chat-panel](interpreter-chat-panel.md#chat-tab)) and loads its models. Without this control the assistant stays as `default_agent` resolves. |
| `model` | A select of the selected harness's own models, loaded the first time the assistant is chosen, with the states *Loading models…* and *Models unavailable*. A model is sent only when it is in that harness's list. |
| `prompt` | Opens the prompt picker: saved prompts, newest first, with a search box over titles and texts. Choosing one replaces the draft. If prompts fail to load, the module's two built-in prompts are offered. |
| `text_editor` | Opens a large editor holding the draft. Apply replaces the draft; Cancel and Escape leave it unchanged. |
| `new_session` | Starts a new, empty session for the selected assistant and makes it active; the harness creates the session with its first message. |

### Assistant and model

| Exact path | Type and allowed values | Absence, validation and behavior |
| --- | --- | --- |
| `E.agents` | Array of 1–4 distinct tokens: `Claude Code`, `Codex`, `DeepSeek Harness`, `pi` | Absent: all four, in that order. Present: these, in this order. At run time the composer offers only those whose gateway the server has configured; if that list cannot be read (for example, the user is not an admin), it offers them all and a send reports the refusal. Other names are errors. |
| `E.default_agent` | One of the four tokens | Absent: the first offered assistant. It must be one of the resolved `agents` (error). If its gateway is not configured at run time, the first offered assistant is selected. The user's later choice wins while the page instance lives. |
| `E.default_model` | String, 1–128 characters | Absent: when the assistant changes or its models finish loading, keep the current model if it is offered, else take the first. Present: in those moments, if the current model is not offered, take this one when it is offered, else the first. Not checked against model lists, which come from the harness at run time. |

With `agents` set to one assistant and `agent` left out of `toolbar`, a page has a composer for
one assistant.

### Size and layout

| Exact path | Type and allowed values | Absence and behavior |
| --- | --- | --- |
| `E.width` | `auto`, `elastic`, or a nonnegative length in `px`, `rem`, `em`, `%` | Class default `elastic` in the `chat-composer` class: share the row's free width. |
| `E.height` | Same grammar | Unset or `auto` (recommended): the box's rows plus the tool bar's rows. |
| `E.min_width` | Same grammar | Class default `320px` in the `chat-composer` class. |
| `E.max_width` | Same grammar | Unset: no maximum. |

The layouter applies these sizes to the whole element (devdoc §3.7). When the tool bar does
not fit on one line it wraps; Send stays last on the final line. The box always takes the full
width of the element.

## Behavior

### States

| State | Behavior |
| --- | --- |
| Loading | Until the configured harnesses, prompts and slash commands have loaded, the controls and Send are disabled. |
| Empty draft | Send is disabled; a draft of only spaces counts as empty. |
| Ready | Send sends the draft with its outer spaces removed, then clears the box. |
| Streaming | In the active session, Send becomes Stop. The box stays editable, so the next message can be prepared. Other sessions and assistants can be used meanwhile; the stream continues in its own session. |
| Stopping | Stop asks the harness to interrupt the turn; a failure becomes an error notice. |
| No assistant offered | The agent menu shows "Select AI Assistant" and lists "No assistant is available"; Send is disabled. |
| Send failure | An error notice "Could not reach <assistant>: <reason>" goes into the session's conversation; the sent message stays there. A 401 or 403 shows "You do not have access to this assistant." / "你无权使用此助手。". Nothing is made up. |
| Editor preview | No requests are made. The controls are drawn and disabled. |

### Keyboard, touch and accessibility

- Tab order: the box, the tool bar controls in their order, then Send or Stop. Every control
  works with the keyboard and touch; nothing depends on hover.
- In the box, Enter inserts a new line and Ctrl+Enter or ⌘+Enter sends when Send is enabled,
  but not while an input method is composing. Send's tooltip names the shortcut.
- The slash command list is a list of buttons right after the box in the tab order; Escape
  hides it until the draft is edited again.
- The box has a visually hidden label "Message" / "消息". The tool bar is a group named "Chat
  controls" / "聊天控件". The model select is named "Model" / "模型". The agent menu button is
  named "AI assistant: <name>" / "AI 助手：<name>".
- The prompt picker and text editor are modal dialogs. They keep focus inside, close with
  Escape and return focus to the control that opened them.
- Text stays selectable: the element's root sets `select-text`, since the ChenWeb shell disables
  selection. Focus rings stay visible, and colours come from the theme in light and dark mode.
- All module text is in Paraglide, in English and Chinese, under `wpi_chat_*` keys. Assistant,
  model and prompt names are data and are shown as given. A language change updates the text
  without losing the draft or focus.
- The browser does not log messages. The harness front-end handlers already log requests on
  the server.

## Validation and errors

| Check | When | Result |
| --- | --- | --- |
| An attribute value breaks its grammar in the tables above, or is `null` | Page save and run | Error, naming the path |
| `default_agent` is not in the resolved `agents` | Page save and run | Error |
| An instance sets an attribute its class fixes | Page save and run | Error |
| A class names an attribute this module does not support | Class save, app load | Warning; the attribute has no effect |
| A page has more than one `chat-composer` | Page save and run | Error at the second one: the chat has one selected assistant and one draft per page |
| A page has a `chat-composer` but no `chat-panel` | App load | Warning: "the page has a chat-composer but no chat-panel, so replies are not shown" |
| A service call fails | Run time | Error notice in the conversation |

All attributes are optional, so an incomplete page has nothing to finish for this element.

## Properties panel

Groups are presentation only; the instance stays flat. The editor groups a class by its code
module, so specialised classes get the same groups. Labels are in Paraglide. Fixed values are
shown read-only as "Fixed by class". Reset removes the instance value.

| Order and group | Attributes, labels EN / 中文 | Controls |
| --- | --- | --- |
| 1. Message box / 消息框 | `placeholder` Placeholder / 占位文字; `rows` Rows / 行数; `slash_commands` Slash commands / 斜杠命令 | Text (JSON for a language map), number 1–20, checkbox |
| 2. Tool bar / 工具栏 | `toolbar` Controls / 控件 | A checklist of the five controls; checked ones are stored in order, with move up and down buttons |
| 3. Assistant / 助手 | `agents` Assistants / 助手; `default_agent` Default assistant / 默认助手; `default_model` Default model / 默认模型 | A checklist of the four assistants (at least one stays checked), a choice among the checked ones or "First in the list", text |
| 4. Size / 尺寸 | `width`, `height`, `min_width`, `max_width` | Size fields |

## Examples

### Class `chat-composer`

As stored by migration `20261030000005_wpi_chat_elements.sql`.

```json
{
  "descriptor_id": "chat-composer",
  "schema_version": "0.4",
  "code_module_id": "chat-composer",
  "description": { "en": "Message box and controls for chatting with an AI assistant", "zh-cn": "与 AI 助手聊天的消息框和控件" },
  "implement_notes": { "en": "KnowledgeStore/doc-repo/code_modules/interpreter-chat-composer.md" },
  "placeholder": {
    "help_tip": { "en": "Text shown in the empty message box.", "zh-cn": "消息框为空时显示的文字。" }
  },
  "rows": {
    "help_tip": { "en": "Visible lines of the message box, 1 to 20.", "zh-cn": "消息框可见行数，1 到 20。" },
    "default_value": 3
  },
  "slash_commands": {
    "help_tip": { "en": "Suggest slash commands when a message starts with /.", "zh-cn": "消息以 / 开头时提示斜杠命令。" },
    "default_value": true
  },
  "toolbar": {
    "help_tip": { "en": "Controls shown under the message box, in order: agent, model, prompt, text_editor, new_session.", "zh-cn": "消息框下方显示的控件及其顺序：agent、model、prompt、text_editor、new_session。" },
    "default_value": ["agent", "model", "prompt", "text_editor", "new_session"]
  },
  "agents": {
    "help_tip": { "en": "Assistants offered, in order, from Claude Code, Codex, DeepSeek Harness and pi; leave out for all four.", "zh-cn": "提供的助手及其顺序，可选 Claude Code、Codex、DeepSeek Harness 和 pi；留空则提供全部四个。" }
  },
  "default_agent": {
    "help_tip": { "en": "Assistant selected when the page opens; leave out for the first.", "zh-cn": "页面打开时选中的助手；留空则选第一个。" }
  },
  "default_model": {
    "help_tip": { "en": "Model selected when the assistant offers it.", "zh-cn": "助手提供该模型时选中它。" }
  },
  "width": {
    "help_tip": { "en": "Width of the whole composer.", "zh-cn": "整个输入区的宽度。" },
    "default_value": "elastic"
  },
  "min_width": {
    "help_tip": { "en": "Narrowest width of the composer.", "zh-cn": "输入区的最小宽度。" },
    "default_value": "320px"
  }
}
```

### Class `claude-code-composer`, fixed to one assistant

A specialised class drawn by the same module. It is not stored; an admin can create it with the
editor's *Create Element*. It fixes the assistant and the controls, so every instance is a
Claude Code composer without an agent menu.

```json
{
  "descriptor_id": "claude-code-composer",
  "schema_version": "0.4",
  "code_module_id": "chat-composer",
  "description": { "en": "Message box for Claude Code", "zh-cn": "Claude Code 消息框" },
  "agents": {
    "help_tip": { "en": "Fixed to Claude Code.", "zh-cn": "固定为 Claude Code。" },
    "default_value": ["Claude Code"],
    "instance_modifiable": false
  },
  "toolbar": {
    "help_tip": { "en": "Fixed controls for Claude Code.", "zh-cn": "Claude Code 的固定控件。" },
    "default_value": ["model", "prompt", "text_editor", "new_session"],
    "instance_modifiable": false
  },
  "rows": {
    "help_tip": { "en": "Visible lines of the message box, 1 to 20.", "zh-cn": "消息框可见行数，1 到 20。" },
    "default_value": 4
  },
  "width": {
    "help_tip": { "en": "Width of the whole composer.", "zh-cn": "整个输入区的宽度。" },
    "default_value": "elastic"
  }
}
```

### An instance in a panel, with its class copy

The entry of `elem_list` that places a `claude-code-composer`. It sets only the placeholder;
setting `agents` or `toolbar` here would be an error, since the class fixes them.

```json
{
  "element": "claude-code-composer",
  "class": {
    "descriptor_id": "claude-code-composer",
    "schema_version": "0.4",
    "code_module_id": "chat-composer",
    "description": { "en": "Message box for Claude Code", "zh-cn": "Claude Code 消息框" },
    "agents": {
      "help_tip": { "en": "Fixed to Claude Code.", "zh-cn": "固定为 Claude Code。" },
      "default_value": ["Claude Code"],
      "instance_modifiable": false
    },
    "toolbar": {
      "help_tip": { "en": "Fixed controls for Claude Code.", "zh-cn": "Claude Code 的固定控件。" },
      "default_value": ["model", "prompt", "text_editor", "new_session"],
      "instance_modifiable": false
    },
    "rows": {
      "help_tip": { "en": "Visible lines of the message box, 1 to 20.", "zh-cn": "消息框可见行数，1 到 20。" },
      "default_value": 4
    },
    "width": {
      "help_tip": { "en": "Width of the whole composer.", "zh-cn": "整个输入区的宽度。" },
      "default_value": "elastic"
    }
  },
  "placeholder": { "en": "Ask Claude Code about this repository", "zh-cn": "向 Claude Code 询问此代码库" }
}
```

### A chat page

The Chat page of the screenshot as a WPI page: a work area with a composer under it, and the
chat panel on the right. Element and layouter instances leave out their `class` copies; the
page write fills them in from the active classes. The browser check stored and ran this layout,
without `default_agent` ([Implementation and verification](#implementation-and-verification)).

```json
{
  "descriptor_id": "assistant-chat",
  "schema_version": "0.5",
  "page_name": { "en": "Chat", "zh-cn": "聊天" },
  "input": {},
  "page_layouter": {
    "layouter": "single-pane",
    "root": {
      "pane_id": "page",
      "split": "columns",
      "children": [
        {
          "pane_id": "work",
          "split": "rows",
          "children": [
            { "pane_id": "content" },
            { "pane_id": "composer", "height": "auto", "left_margin": "16px", "right_margin": "16px", "bottom_margin": "12px" }
          ]
        },
        { "pane_id": "assistant", "width": "420px", "min_width": "280px", "max_width": "640px", "resizable": true }
      ]
    }
  },
  "panels": {
    "content": {
      "elem_layouter": { "layouter": "flow-layouter" },
      "elem_list": [
        { "element": "text", "text": "Ask the assistant on the right. 请向右侧的助手提问。" }
      ]
    },
    "composer": {
      "elem_layouter": { "layouter": "flow-layouter" },
      "elem_list": [
        { "element": "chat-composer", "default_agent": "Claude Code" }
      ]
    },
    "assistant": {
      "elem_layouter": { "layouter": "flow-layouter" },
      "elem_list": [
        { "element": "chat-panel" }
      ]
    }
  }
}
```

<a id="review-record"></a>

## Review record

**R1, 2026-10-30.** First draft, from the screenshot of ChenWeb's Chat page and
`chatter-01.svelte`, after the user decided that the highlighted area becomes two elements, one
for the bottom and one for the right, and that the conversation moves into a new Chat tab of
the right panel.

**Feedback on R1, 2026-10-30 (user):**

- **Q1 Attach and Dictate:** leave them out for now.
- **Q2 Panel height:** keep the fixed default height; stretching is addressed later.
- **Q3 Placeholder assistants:** the user asked which four assistants are real (the
  harness-backed ones), then decided: "Make real assistants configurable through its
  descriptor."
- **Q4 Session header:** keep it.
- Asked what to do with the output format control and the Settings tab, which only the
  placeholder assistants used, the user chose to remove both.

**R2, 2026-10-30, approved.** The user approved the proposal on 2026-10-30 ("The proposal is
approved. Go ahead to implement it.") together with the Q3 decision, and chose the removal of
output format and Settings. R2 is R1 with:

1. `agents` limited to the four harness-backed assistants, defaulting to all four; the user's
   chat settings no longer supply assistants; the offered list is filtered to the gateways
   the server has configured.
2. The `output_format` control and the chatter send, session and settings calls removed.
3. Implementation-level corrections made while building, which do not change what a page
   can configure: an empty `placeholder` is invalid, as for every WPI text attribute; closing
   a streaming session or page interrupts the harness's turn, because aborting the stream
   does; the unpaired-element warnings are given at app load, where the existing page
   warnings are given; the disabled-control explanations of R1 were not built (see Limits).

Assumptions kept from R1: one chat per page and at most one composer; existing services rather
than WPI actions; Ctrl+Enter / ⌘+Enter sends; the chat is not page data; choosing a prompt
replaces the draft; theme colours; errors instead of made-up replies.

A material change returns to review.

## Implementation and verification

**Built 2026-10-30** (ChenWeb OpenSpec change `wpi-chat-elements`):

| File | Role |
| --- | --- |
| `web/src/lib/wpi/chat-session.svelte.ts` | `ChatSession`, the chat of a page instance; `acquireChat` / `releaseChat` keep one per runtime and page instance, reference-counted |
| `web/src/lib/wpi/chat-agents.ts` | `CHAT_AGENTS`, `offeredAgents`, `pick`: the assistant and model selection |
| `web/src/lib/wpi/elements/ChatComposerElement.svelte` | The composer |
| `web/src/lib/wpi/elements/index.ts`, `types.ts` | Registration; descriptor fields |
| `web/src/lib/services/harnessFrontendService.ts` | `listHarnesses`; `HarnessRequestError` carries the HTTP status |
| `web/src/lib/components/shared-ui/canvas/PropertiesPanel.svelte` | Groups by code module; checklist and choice controls |
| `web/src/lib/wpi/api.ts`, `server/api/wpi/store.go` | The element class list reports `code_module_id` |
| `server/api/wpi/chat_attributes.go`, `validate.go`, `bundle.go` | Attribute checks, one composer per page, pairing warnings |
| `project_migrations/20261030000005_wpi_chat_elements.sql` | `kb.code_modules` rows and the active `chat-composer` and `chat-panel` classes (version 1) |
| `web/messages/en.json`, `zh-cn.json` | `wpi_chat_*` messages |

**Checks run on 2026-10-30:**

- `go test ./api/wpi/`: passes, including `chat_attributes_test.go` (attribute grammar, fixed
  `agents`, `default_agent` outside `agents`, two composers, pairing warnings, the migration's
  class bodies valid with no warnings) and the seed test extended to the new migration.
- `bun test src/lib/wpi/chat-agents.test.ts`: passes. `bun run check`: 0 errors, i18n ok; the
  remaining warnings are in files this change did not touch, or are unused CSS rules it did
  not touch.
- The migration was dry-run in a rolled-back transaction, then applied with
  `doc-service --migrate-only`; both classes read back as active.
- Browser, Playwright against the vite dev server and the real WPI handlers (a stand-in admin
  user), with the harness gateway stubbed: the agent menu offers only configured gateways;
  default tool bar; harness models; Send disabled while empty; slash list and Escape;
  Ctrl+Enter sends to `claude-code` with the model, the reply streams into the Chat tab and the
  second message continues the harness session; New Session, History and Close session; prompt
  picker and text editor; a 403 shows the access notice; text selectable; switching to `pi`;
  Chinese labels; a configured page (`agents: ["pi"]`, `toolbar: ["model"]`, `rows: 2`); dark
  mode and a 760px-wide window by screenshot. The test apps were deleted afterwards.

**Not verified:** a real harness gateway (stubbed in the browser check); the Properties panel in
the browser (the WPI editor needs a signed-in admin; it was type-checked only); input-method
composition with Ctrl+Enter; touch devices; a reply streaming while its page is hidden.

**Limits:**

- Disabled controls do not say why they are disabled.
- The harness gateways are admin-only, so for other users the composer can only report the
  refusal.
- Prompts and slash commands come from the stub `/api/v1/chatter` handler.
- One chat per page.

**Old class copies:** none exist yet. A later attribute must keep this behavior when absent.

**Docs:** the WPI devdoc, the frontend reusable-module document and the ChenWeb OpenSpec change
`wpi-chat-elements` (not yet archived; until it is, `openspec/specs/wpi-page-rendering` and
`wpi-classes` still list only the first six element classes) describe this module.
