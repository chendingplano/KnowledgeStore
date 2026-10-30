# Code module: `chat-composer`

**Code module ID:** `chat-composer` \
**Classes using it:** `chat-composer` (proposed); specialised classes, such as a composer for one
assistant, may reuse it \
**Implementation status:** proposed; no code, class or catalogue row exists yet \
**Design revision:** R1, 2026-10-30 — **Awaiting human design review** \
**Approval:** none recorded \
**Proposed catalogue row:** `kb.code_modules` `chat-composer`, `module_name` "Chat Composer",
`module_type` `element`, `module_doc` `interpreter-chat-composer.md`, added by a goose migration
with its code \
**Companion module:** [`chat-panel`](interpreter-chat-panel.md), which shows the conversation this
composer sends to \
**Source UI:** ChenWeb Development → Chat (`/development?view=chat`): the message box and tool bar
at the bottom of `ChenWeb/web/src/lib/components/shared-ui/chatter-01.svelte` \
**Proposed frontend:** `ChenWeb/web/src/lib/wpi/elements/ChatComposerElement.svelte`, registered in
`elements/index.ts`, and the chat session store shared with `chat-panel`,
`ChenWeb/web/src/lib/wpi/chat-session.svelte.ts` \
**Proposed backend:** `codeModules["chat-composer"]`, a `chat-composer` case in `element()` and a
page check in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, [Web Page Interpreter frontend](../modules/module-web-page-interpreter-frontend.md) \
**Design:** [WPI devdoc](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md) §3.5 Elements,
§3.7 Element layouters, §3.8 Input doc, §5 Actions, §7 Validation; [input reference](interpreter-input.md)

## Purpose and boundary

The composer is where a user writes a message to an AI assistant and sends it. It draws a
multi-line message box and, under it, a tool bar: the assistant (agent) and model, the output
format, a prompt picker, a larger text editor, New Session, and Send, which becomes Stop while
a reply streams in. Replies are not shown here. They appear in the Chat tab of a
[`chat-panel`](interpreter-chat-panel.md) on the same page ([Chat session](#chat-session)).

A typical page reproduces ChenWeb's Chat page: the composer in a bottom pane and the panel in
a right pane. Another page can use a composer restricted to one assistant, with only the
controls that page needs, without new code.

Not part of the composer:

- the conversation, the session list and the Dialog and Settings tabs, which belong to `chat-panel`;
- the skill picker ("Create Skill") at the top of chatter-01, whose choice is never sent with
  a message today;
- Attach and Dictate, which chatter-01 draws but which do nothing ([Q1](#review-record));
- the "Close panel" button at the top right of the screenshot, which belongs to the ChenWeb
  shell and toggles its context shelf;
- data binding to the input doc, WPI action triggers and appearance attributes.

## What changes from chatter-01

| Area | chatter-01 today | R1 composer |
| --- | --- | --- |
| Scope | One component draws the tool row, session tabs, conversation, composer and side panel | Message box and tool bar only; the rest moves to `chat-panel` |
| Controls | A fixed row, including Attach and Dictate, which have no behavior | `toolbar` chooses and orders the working controls |
| Assistants | The chat settings list, with the harness assistants appended | The same by default; a page may restrict it with `agents` |
| Failed send (non-harness) | A made-up reply "Stub response from …" is added | An error notice is added to the conversation; the sent message stays visible |
| Colours | A hard-coded palette per light/dark mode | ChenWeb theme colours, light and dark |
| Prompt and text editor dialogs | Overlays inside the chat component | App modal dialogs: focus kept inside, Escape closes |
| Sending from the keyboard | Only by tabbing to Send | Also Ctrl+Enter / ⌘+Enter ([A4](#review-record)) |

<a id="chat-session"></a>

## Chat session

This section is the contract that `chat-composer` and `chat-panel` share.

**Scope.** All chat elements of one page instance share one chat session store. R1 has no
attribute that pairs elements: the `chat-composer` and every `chat-panel` of a page instance
work on the same store. A page opened in a pane of another page is a different page instance
with its own store. A page has at most one composer ([Validation](#validation-and-errors)).
Two independent chats on one page are not supported; a pairing attribute such as `channel`
could be added later without changing pages that leave it out.

**Contents.** The store holds the chat settings lists (agents, models and output formats, and,
only so that saving keeps them, the attachment, skill and slash-command lists); the selected
agent, model and output format; the open sessions and which one is active; each session's
conversation; and whether a reply is streaming in a session. This is runtime state, not data:
it is not in the input doc, `save` and `save-page` never send it, it never makes the page
dirty, and the unsaved-changes prompt does not look at it.

**Lifetime.** The store is created when the first chat element of the page instance mounts,
which loads the settings, prompts and slash commands once. It is kept while the page is hidden
in the Panel Cache: hidden pages stay mounted, so a streaming reply keeps arriving. It is
discarded when the page instance closes. The browser then stops reading any streaming reply;
a harness keeps the session on the server, where the panel's History menu can open it again.
An unsent draft is lost when the page closes ([A5](#review-record)).

**Services.** The module calls existing ChenWeb services itself; it does not run WPI actions
([A3](#review-record)):

| Agent | Service | Behavior today |
| --- | --- | --- |
| `Claude Code`, `Codex`, `DeepSeek Harness`, `pi` | `/api/v1/harness-frontend/<harness>/…`: models, sessions, streamed turns, interrupt, permission decisions | Real assistants. **Admin-only** on the server. |
| any other name, e.g. `OpenClaw` | `/api/v1/chatter/…` | **A stub**: fixed settings, prompts and sessions; every reply is canned; saved settings are not kept ([Q3](#review-record)). |

The mapping from agent names to harnesses is fixed in code (`HARNESS_BY_AGENT` in
`harnessFrontendService.ts`). Descriptor attributes only choose among agent and model
names. They never name URLs, endpoints, tables or credentials, and they grant no access: a
user who is not an admin and sends to a harness agent gets the server's refusal as an error
notice in the conversation.

## Descriptor rules and precedence

A class has its own `descriptor_id`, `schema_version` `"0.4"` and `code_module_id`
`"chat-composer"`. An instance lives at `$.panels.<pane_id>.elem_list[i]`, names its class in
`element` and holds the complete class row in `class`; `element` equals
`class.descriptor_id`. In the tables, `E.<name>` is the instance's flat attribute; its
definition is `E.class.<name>`, or `$.<name>` in the class row. Properties groups are
presentation only and add no nested objects.

Each definition has an author-facing `help_tip` in English and Chinese, an optional
`default_value` and an optional `instance_modifiable`. Every R1 attribute has a module
fallback, so a class normally leaves `default_value` out or gives a concrete value.
A specialised class may still use `default_value: null` to make every instance choose,
for example `default_agent`. `instance_modifiable: false` needs a non-null default and
forbids any instance value, even an equal one. An instance value of `null` is invalid for
every attribute.

For a valid instance each attribute resolves to the fixed class value, else the instance
value, else the class copy's non-null default, else the module fallback in the tables below.
The composer has no action-valued attributes. Later edits to a class reach only instances
placed afterwards; an attribute added to this module later must have a fallback that keeps
R1 behavior for copies that do not name it.

`label`, `data_binding` and `binding_mode` are not supported: a class that names them gets a
warning, and they have no effect. A page-level `binding_mode` does not apply to the composer;
a `read-only` page can still send messages.

## Attribute contract

### Message box

| Exact path | Type and allowed values | Absence, validation and behavior |
| --- | --- | --- |
| `E.placeholder` | Localized text: a string, or a language map with a nonempty `en` | Absent or empty: the module text "Ask anything... Use '/' for commands." / "随便问… 输入“/”使用命令。". Shown only while the box is empty; never the accessible name. Language maps fall back to `en`. |
| `E.rows` | Integer 1–20 | `3`. Visible lines of the box. Longer text scrolls inside the box; the box does not grow. `0`, fractions and numeric strings are invalid. |
| `E.slash_commands` | Boolean | `true`: while the draft starts with `/`, list the matching slash commands above the box; choosing one replaces the draft with the command and a space. `false`: no list, and `/…` is sent as typed. |

### Tool bar

| Exact path | Type and allowed values | Absence, validation and behavior |
| --- | --- | --- |
| `E.toolbar` | Array of 0–6 unique tokens: `agent`, `model`, `output_format`, `prompt`, `text_editor`, `new_session` | `["agent", "model", "output_format", "prompt", "text_editor", "new_session"]`. The controls shown, left to right, in array order. `[]` shows only Send. Send (or Stop) is always present, last and right-aligned. Unknown, duplicate and non-string tokens are errors; `attach` and `dictate` are unknown in R1. |

| Token | Control and behavior |
| --- | --- |
| `agent` | A menu of the offered agents, labelled with the selected one. Choosing an agent shows that agent's sessions ([chat-panel](interpreter-chat-panel.md#chat-tab)) and loads its models. Without this control the agent stays as `default_agent` resolves. |
| `model` | A select. A harness agent offers the harness's own models, loaded the first time the agent is chosen, with the states *Loading models…* and *Models unavailable*. Other agents offer the settings model list. A model is sent to a harness only when it is in that harness's list. |
| `output_format` | A select of the settings output formats, sent with each message to a non-harness agent. Disabled while a harness agent is selected, with the tooltip "Not used by this assistant" / "此助手不使用该选项", since harnesses ignore it. |
| `prompt` | Opens the prompt picker: saved prompts, newest first, with a search box over titles and texts. Choosing one replaces the draft ([A6](#review-record)). If prompts fail to load, the module's two built-in prompts are offered, as in chatter-01. |
| `text_editor` | Opens a large editor holding the draft. Apply replaces the draft; Cancel and Escape leave it unchanged. |
| `new_session` | Starts a new session for the selected agent and makes it active. For a harness agent the session is created by its first message; for another agent, by `POST /api/v1/chatter/sessions`, and when that fails, as a local session. |

### Assistant and model

| Exact path | Type and allowed values | Absence, validation and behavior |
| --- | --- | --- |
| `E.agents` | Array of 1–20 unique strings, each 1–64 characters without leading or trailing spaces | Absent: the settings agent list (from the server, or the module's defaults if loading fails), with any missing harness agents appended, as in chatter-01. Present: exactly these agents in this order; the panel's Settings tab then shows the agent list read-only. A name that is not a harness agent uses the chatter service. |
| `E.default_agent` | String, same grammar as an agent name | Absent: the first offered agent. When `agents` resolves, `default_agent` must be one of them (error). Without `agents`, a name missing from the user's list at run time falls back to the first agent; this is not an error, since the list is runtime data. Applied once, when the store is created. |
| `E.default_model` | String, 1–128 characters | Absent: when the agent changes, or its models finish loading, keep the current model if it is offered, else take the first. Present: in those moments, if the current model is not offered, take this one when it is offered, else the first. Not checked against model lists, which are runtime data. |

With `agents` set to one name and `agent` left out of `toolbar`, a page has a composer for one
assistant.

### Size and layout

| Exact path | Type and allowed values | Absence and behavior |
| --- | --- | --- |
| `E.width` | `auto`, `elastic`, or a nonnegative length in `px`, `rem`, `em`, `%` | Class default `elastic` in the proposed class: share the row's free width. |
| `E.height` | Same grammar | Unset or `auto` (recommended): the box's rows plus the tool bar's rows. A larger fixed height leaves space below; a smaller one scrolls inside the element. Nothing is clipped. |
| `E.min_width` | Same grammar | Class default `320px` in the proposed class. |
| `E.max_width` | Same grammar | Unset: no maximum. |

The layouter applies these sizes to the whole element (devdoc §3.7). When the tool bar does
not fit on one line it wraps; Send stays last on the final line. The box always takes the full
width of the element.

## Behavior

### States

| State | Behavior |
| --- | --- |
| Loading | While settings load, the agent menu shows "Select AI Assistant" and Send is disabled. |
| Empty draft | Send is disabled; the draft counts as empty when it is only spaces. |
| Ready | Send sends the draft with its outer spaces removed, then clears the box. |
| Sending (non-harness) | Send is disabled until the reply or failure arrives, so a second click cannot send twice. |
| Streaming (harness) | In the active session, Send becomes Stop. The box stays editable, so the next message can be prepared. Other sessions and agents can be used meanwhile; the stream continues in its own session. |
| Stopping | Stop asks the harness to interrupt the turn; a failure becomes an error notice. |
| No agents | The agent menu shows "Select AI Assistant" and Send is disabled. |
| Send failure | An error notice with the reason goes into the session's conversation; the sent message stays there, visible and copyable. A 401 or 403 shows "You do not have access to this assistant." / "你无权使用此助手。". Nothing is made up. |
| Editor preview | No requests are made. The controls are drawn and disabled; the agent label is `default_agent`, else the first of `agents`, else "Select AI Assistant". |

### Keyboard, touch and accessibility

- Tab order: the box, the tool bar controls in their order, then Send or Stop. Every control
  works with the keyboard and touch; nothing depends on hover.
- In the box, Enter inserts a new line and Ctrl+Enter or ⌘+Enter sends when Send is enabled,
  but not while an input method is composing.
- The slash command list is a list of buttons right after the box in the tab order; Escape closes it.
- The box has a visually hidden label "Message" / "消息". The tool bar is a group named "Chat
  controls" / "聊天控件". The selects are named "Model" / "模型" and "Output format" /
  "输出格式". The agent menu button is named "AI assistant: <name>" / "AI 助手：<name>".
- Disabled controls give their reason in a tooltip that also appears on keyboard focus.
- The prompt picker and text editor are modal dialogs. They keep focus inside, close with
  Escape and return focus to the control that opened them.
- Text stays selectable: the element's root sets `select-text`, since the ChenWeb shell disables
  selection. Focus rings stay visible, and colours come from the theme in light and dark mode.
- All module text is in Paraglide, in English and Chinese, under `wpi_chat_*` keys. Agent,
  model and prompt names are data and are shown as given. A language change updates the text
  without losing the draft or focus.
- The browser does not log messages. The chat and harness handlers already log requests on
  the server.

## Validation and errors

| Check | When | Result |
| --- | --- | --- |
| An attribute value breaks its grammar in the tables above, or is `null` | Page save and run | Error, naming the path |
| `default_agent` is not in a resolved `agents` | Page save and run | Error |
| An instance sets an attribute its class fixes | Page save and run | Error |
| A class names an attribute this module does not support | Class save, app load | Warning; the attribute has no effect |
| A page has more than one `chat-composer` | Page save and run | Error: the store has one selected agent and one draft per page |
| A page has a `chat-composer` but no `chat-panel` | Page save and app load | Warning: "Replies are not shown on this page." |
| A service call fails | Run time | Error notice in the conversation |

All R1 attributes are optional, so an incomplete page has nothing to finish for this element.
The page checks need the validator to look at the element instances of the whole page, as it
already does for the `save` consistency warning.

## Properties panel

Groups are presentation only; the instance stays flat. Labels and help are in Paraglide.
Fixed values are shown read-only as "Fixed by class" / "类固定值". Reset removes the instance
value and shows the class default or module fallback, with its source.

| Order and group | Attributes, labels EN / 中文 | Controls and help EN / 中文 |
| --- | --- | --- |
| 1. Message box / 消息框 | `placeholder` Placeholder / 占位文字; `rows` Rows / 行数; `slash_commands` Slash commands / 斜杠命令 | Localized text, integer 1–20, switch. "Placeholder text never replaces the label." / "占位文字不能代替标签。" |
| 2. Tool bar / 工具栏 | `toolbar` Controls / 控件 | A checklist of the six controls with Move up / Move down. "Send is always shown last." / "发送按钮始终显示在最后。" Until this control exists, the generic JSON control. |
| 3. Assistant / 助手 | `agents` Assistants / 助手; `default_agent` Default assistant / 默认助手; `default_model` Default model / 默认模型 | List editor (one name per line), a choice among `agents` or free text, free text. "Leave Assistants empty to use each user's chat settings." / "助手留空则使用用户自己的聊天设置。" |
| 4. Size / 尺寸 | `width`, `height`, `min_width`, `max_width` | Size fields. "Prefer auto height." / "建议使用自动高度。" |

## Examples

The JSON below is complete but **not runnable until R1 is implemented and its classes are
registered**.

### Class `chat-composer`

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
    "help_tip": { "en": "Controls shown under the message box, in order.", "zh-cn": "消息框下方显示的控件及其顺序。" },
    "default_value": ["agent", "model", "output_format", "prompt", "text_editor", "new_session"]
  },
  "agents": {
    "help_tip": { "en": "Assistants offered on this page; leave out to use the user's chat settings.", "zh-cn": "本页提供的助手；留空则使用用户的聊天设置。" }
  },
  "default_agent": {
    "help_tip": { "en": "Assistant selected when the page opens.", "zh-cn": "页面打开时选中的助手。" }
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

A specialised class drawn by the same module. It fixes the assistant and the controls, so
every instance is a Claude Code composer without an agent menu or output format.

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
chat panel on the right. As in the devdoc's examples, element and layouter instances leave
out their `class` copies; this form is accepted by the page write, which fills the copies in
from the active classes. The `chat-panel` instance is described in its
[own document](interpreter-chat-panel.md).

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

The `text` element uses a plain string, the only form today's `text` module accepts; the
[`text` R1 proposal](interpreter-text.md) adds language maps.

<a id="review-record"></a>

## Review record

**R1, 2026-10-30.** First draft, from the screenshot of ChenWeb's Chat page and
`chatter-01.svelte`. No human feedback or approval has been recorded.

Decided by the user on 2026-10-30, before the draft: the highlighted area becomes two
elements, one for the bottom (this composer) and one for the right
([`chat-panel`](interpreter-chat-panel.md)), and the conversation moves into a new Chat tab of
the right panel.

Assumptions for review:

1. **A1 Two modules.** `chat-composer` and `chat-panel` are separate code modules with separate
   classes and documents, sharing one store in code.
2. **A2 One chat per page.** One store per page instance, no pairing attribute, at most one
   composer per page.
3. **A3 Existing services, not WPI actions.** The module calls the chat and harness services
   directly. Streaming, interrupting and permission decisions fit no existing action class,
   and new action classes would be a larger change. Authorization stays on the server.
4. **A4 Ctrl+Enter / ⌘+Enter sends**; Enter inserts a new line.
5. **A5 The chat is not page data.** It never makes the page dirty; an unsent draft is lost
   when the page closes, as in chatter-01.
6. **A6 Choosing a prompt replaces the draft**, as in chatter-01.
7. **A7 Theme colours** replace chatter-01's palette; appearance attributes wait for Page Styles.
8. **A8 A failed send shows an error**, not a made-up reply.

Open questions:

- **Q1 Attach and Dictate** draw in chatter-01 but do nothing. R1 leaves them out. Should they
  be designed now (what does Attach send, and where does dictation run?), or added once they work?
- **Q3 Stub assistants.** Agents other than the four harnesses get canned replies, and
  settings are not saved, because `/api/v1/chatter` is a stub. Keep offering them by default,
  as chatter-01 does, or make the default agent list the four harness agents?
- Q2 and Q4 concern the panel; see its [review record](interpreter-chat-panel.md#review-record).

Approval must name R1 or a later revision. A material change returns to review. Automated
checks do not replace human approval.

## Implementation and verification

Nothing is implemented. Read-only inspection on 2026-10-30 found: `chatter-01.svelte` and
its services (`chatterService.ts`, `harnessFrontendService.ts`, `harness-conversation.ts`,
`harness-dialog.svelte`); the stub `server/api/chatterhandler/handler.go`; admin-only harness
routes in `server/api/harnessfrontend/handler.go`; the element registry `elements/index.ts`
and `codeModules` in `validate.go`; no existing `chat-composer` or `chat-panel` module, class,
document or migration.

Document checks: the JSON blocks parse; the instance's class copy equals its class; relative
links resolve. No application code, migration or catalogue was changed.

After approval, through a ChenWeb OpenSpec change:

- Build `chat-session.svelte.ts` from the logic in chatter-01, reusing its services,
  `harness-conversation.ts` and `harness-dialog.svelte`. Leave chatter-01 unchanged, so the
  current Chat page keeps working.
- Build `ChatComposerElement.svelte` and register it; add the `ElementInstance` fields in
  `types.ts`; add `wpi_chat_*` Paraglide keys in both message files.
- Add `chat-composer` to `codeModules` and value checks in `validate.go`, and the page checks
  (one composer; composer without panel). Add Go and TypeScript tests.
- Add the Properties groups above.
- A goose migration adds the `kb.code_modules` row and the `chat-composer` class, active once
  the code exists. Record the module under reusable module `20261026-01`.
- Verify in a browser, as an admin and as a non-admin: defaults, `toolbar` order, restricted
  and fixed agents, harness streaming and Stop, a stub agent, failures, hidden and shown
  pages, keyboard sending and IME, both languages, both themes and narrow panes. Report
  checks blocked by login or services rather than claiming them.

Knowledge changed: the contract for converting the chat composer into a WPI element. Affected
after implementation: the WPI devdoc's list of element classes, the parent reusable-module
document, the `wpi-*` OpenSpec specs and the module catalogue. Deliberately undocumented: the
internal design of the store, until it is built.
