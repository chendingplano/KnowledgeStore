# Code module: `chat-panel`

**Code module ID:** `chat-panel` \
**Classes using it:** `chat-panel` (proposed) \
**Implementation status:** proposed; no code, class or catalogue row exists yet \
**Design revision:** R1, 2026-10-30 — **Awaiting human design review** \
**Approval:** none recorded \
**Proposed catalogue row:** `kb.code_modules` `chat-panel`, `module_name` "Chat Panel",
`module_type` `element`, `module_doc` `interpreter-chat-panel.md`, added by a goose migration with
its code \
**Companion module:** [`chat-composer`](interpreter-chat-composer.md), which sends the messages this
panel shows; its [Chat session](interpreter-chat-composer.md#chat-session) section is the contract
both share \
**Source UI:** ChenWeb Development → Chat (`/development?view=chat`): the Dialog/Settings side panel
and the conversation area of `ChenWeb/web/src/lib/components/shared-ui/chatter-01.svelte` \
**Proposed frontend:** `ChenWeb/web/src/lib/wpi/elements/ChatPanelElement.svelte`, registered in
`elements/index.ts`, using the store `ChenWeb/web/src/lib/wpi/chat-session.svelte.ts` \
**Proposed backend:** `codeModules["chat-panel"]`, a `chat-panel` case in `element()` and a page
check in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, [Web Page Interpreter frontend](../modules/module-web-page-interpreter-frontend.md) \
**Design:** [WPI devdoc](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md) §3.5 Elements,
§3.7 Element layouters, §5 Actions, §7 Validation; [Page Layouter](interpreter-layouter-page.md)

## Purpose and boundary

The chat panel shows the chat of its page: the conversation, a compact history and the chat
settings, in three tabs.

- **Chat** (new) shows the active session's conversation, which chatter-01 shows in its middle
  area: messages, streamed replies, tool calls, permission requests and errors. Its header
  switches between sessions.
- **Dialog** shows the compact history that chatter-01's side panel shows today.
- **Settings** edits the chat's lists of assistants, models and output formats.

Messages are written and sent in the page's [`chat-composer`](interpreter-chat-composer.md).
Both elements share the page instance's chat session store, so the panel follows the
composer's selected assistant and active session ([Chat session](interpreter-chat-composer.md#chat-session)).

Not part of the panel: writing and sending messages; its own resize handle (the pane is
resized by the page layouter's `resizable`); the "Close panel" button of the ChenWeb shell;
data binding, WPI action triggers and appearance attributes.

## What changes from chatter-01

| Area | chatter-01 today | R1 panel |
| --- | --- | --- |
| Tabs | Dialog, Settings | Chat (new), Dialog, Settings; a page chooses which and in what order |
| Conversation | The middle area, beside the side panel | The Chat tab |
| Sessions | A row of session tabs and, for harness agents, a Sessions menu above the conversation | A header in the Chat tab: session select, History menu, close button ([Q4](#review-record)) |
| Width | Its own drag handle, 280–560px | The pane's width; the pane may be `resizable` |
| Settings lists | Agents, models, attachments, skills, result options | Agents, models, output formats; attachments and skills are not used by the composer and are kept unchanged when saving |
| Colours | A hard-coded palette per light/dark mode | ChenWeb theme colours, light and dark |

## Descriptor rules and precedence

The rules of the composer apply ([Descriptor rules](interpreter-chat-composer.md#descriptor-rules-and-precedence)):
`schema_version` `"0.4"`, `code_module_id` `"chat-panel"`, the complete class copy in `class`,
fixed value before instance value before class default before module fallback, `null` instance
values invalid, later class edits reaching only new instances. `label`, `data_binding` and
`binding_mode` are not supported, and a page-level `binding_mode` does not apply. The panel has
no action-valued attributes.

## Attribute contract

### Tabs

| Exact path | Type and allowed values | Absence, validation and behavior |
| --- | --- | --- |
| `E.tabs` | Array of 1–3 unique tokens: `chat`, `dialog`, `settings` | `["chat", "dialog", "settings"]`. The tabs shown, in array order. With one tab the tab bar is not drawn; the content takes the tab's name as its accessible name. An empty array, unknown, duplicate or non-string tokens are errors. |
| `E.initial_tab` | One of the tokens | Absent: the first of the resolved `tabs`. Must be in the resolved `tabs` (error). Shown when the element first mounts; afterwards the user's choice is kept while the page instance lives, including while it is hidden. |

### Size and layout

| Exact path | Type and allowed values | Absence and behavior |
| --- | --- | --- |
| `E.width` | `auto`, `elastic`, or a nonnegative length in `px`, `rem`, `em`, `%` | Class default `elastic` in the proposed class: fill the pane's width. |
| `E.height` | Same grammar | Class default `640px` in the proposed class. The tab bar stays at the top and the tab's content scrolls inside the element. With `auto` the element grows with the conversation and the pane scrolls instead, taking the tab bar with it; not recommended ([Q2](#review-record)). |
| `E.min_width` | Same grammar | Class default `280px` in the proposed class. |
| `E.max_width` | Same grammar | Unset: no maximum. |

A WPI element cannot yet fill the height of its pane: a panel's height comes from its content,
and the flow layouter does not stretch `elastic` heights (devdoc §3.7). Hence the fixed default
height, which an instance can change to suit its page ([Q2](#review-record)).

<a id="chat-tab"></a>

## Tabs

### Chat

**Header.** One row with:

- a session select listing the open sessions of the selected assistant by title, with the
  active one selected; choosing one makes it active for the composer too;
- for a harness assistant, a History menu listing the sessions the harness keeps (from this
  page, a terminal or an IDE), newest first, with title or first prompt and time. Choosing one
  opens it with its stored history, or switches to it if it is already open. The menu loads
  each time it opens and shows "No sessions yet" / "暂无会话" when the list is empty or fails;
- a close button for the active session. A harness session can always be closed and stays on
  the harness. For other assistants the last open session cannot be closed, as in chatter-01.

**Conversation.** For a harness session: the user's messages; the assistant's replies as they
stream in, rendered as Markdown with raw HTML escaped and unsafe links removed; tool calls
with their input and result or error; permission requests with Allow and Deny, whose decision
is sent to the harness and then shown as Allowed or Denied; and notices, including the
composer's error notices. For other assistants: user and assistant messages as bubbles. This
reuses `harness-dialog.svelte` and chatter-01's bubbles. While a reply streams, a running
indicator shows at the end. When empty: "Start chatting. Type `/` to use slash commands." /
"开始聊天。输入 `/` 使用斜杠命令。".

**Scrolling.** The conversation scrolls inside the element. New content keeps it at the
bottom when the user is at the bottom; if the user has scrolled up, the position is kept.
All text can be selected and copied.

### Dialog

A read-only, compact list of the active session, as chatter-01's side panel shows it: each
entry gives its role, or a tool's name, and its text; harness entries are cut to three lines.
Permission requests and notices are not listed. When empty: "No dialog history yet." /
"还没有对话记录。".

### Settings

Three list editors, one entry per line: **Assistants** / 助手, **Models** / 模型 and **Output
formats** / 输出格式, then **Save Settings** / 保存设置.

- An edited list takes effect in the store, and so in the composer's menus, when its editor
  loses focus. Lines are trimmed, empty lines dropped and repeated entries removed, keeping
  the first. A list left empty is not applied and shows "Enter at least one entry." /
  "请至少填写一项。".
- When the page's composer sets `agents`, the Assistants editor is read-only and says "Set by
  this page" / "由本页设定".
- Save sends every list, including the attachment, skill and slash-command lists as they were
  loaded, to `PUT /api/v1/chatter/settings`. Save is disabled while it runs. Success shows
  "Settings saved" / "设置已保存"; a failure shows the reason and keeps the edits.
- **Today the server does not keep them.** The settings endpoint is a stub that answers
  success without saving, so edits last only while the page instance is open
  ([Q3](interpreter-chat-composer.md#review-record)).

## States

| State | Behavior |
| --- | --- |
| Loading | While settings load, Chat and Dialog show their empty text and the Settings editors are disabled. |
| No composer on the page | The panel still shows sessions and lets the user open harness history and answer permission requests; nothing can be sent. The page gets a warning ([Validation](#validation-and-errors)). |
| Hidden and shown again | The current tab, scroll positions and streaming replies are kept: hidden pages stay mounted. |
| Several panels on one page | Allowed. They show the same store; each keeps its own current tab. |
| Not an admin, harness assistant | The History menu shows "No sessions yet"; the composer's failed sends show their notices here. |
| Editor preview | No requests are made. Tabs can be switched; Chat and Dialog show their empty text; the Settings editors and Save are disabled. |

## Keyboard, touch and accessibility

- The tab bar follows the WAI-ARIA tabs pattern: `tablist`, `tab` and `tabpanel`; Left and
  Right move between tabs and Home and End go to the first and last, activating them. Tabs
  are labelled "Chat" / "聊天", "Dialog" / "对话" and "Settings" / "设置".
- The conversation is a focusable scroll region named "Conversation" / "对话内容", so it can
  be scrolled with the keyboard. Streamed text is not read aloud piece by piece; a visually
  hidden polite status says "Assistant is replying" / "助手正在回复" and "Reply finished" /
  "回复完成".
- Allow and Deny are named with the tool, for example "Allow Bash" / "允许 Bash".
- Every control works with the keyboard and touch; nothing depends on hover. Focus rings stay
  visible, and colours come from the theme in light and dark mode.
- Text stays selectable: the element's root sets `select-text`, since the ChenWeb shell
  disables selection.
- Module text is in Paraglide in English and Chinese under `wpi_chat_*` keys; session titles,
  assistant and model names and messages are data and are shown as given. A language change
  keeps the tab, scroll position and unsaved edits.
- The browser does not log messages or settings.

## Validation and errors

| Check | When | Result |
| --- | --- | --- |
| `tabs` or `initial_tab` breaks its grammar, or a value is `null` | Page save and run | Error, naming the path |
| `initial_tab` is not in the resolved `tabs` | Page save and run | Error |
| An instance sets an attribute its class fixes | Page save and run | Error |
| A class names an attribute this module does not support | Class save, app load | Warning; the attribute has no effect |
| A page has a `chat-panel` but no `chat-composer` | Page save and app load | Warning: "Nothing can be sent from this page." |
| A service call fails | Run time | A notice in the conversation, or a message in the Settings tab or History menu |

Both R1 attributes are optional, so an incomplete page has nothing to finish for this element.

## Properties panel

Groups are presentation only; the instance stays flat. Labels and help are in Paraglide.
Fixed values are shown read-only as "Fixed by class" / "类固定值"; reset restores the class
default or module fallback.

| Order and group | Attributes, labels EN / 中文 | Controls and help EN / 中文 |
| --- | --- | --- |
| 1. Tabs / 标签页 | `tabs` Tabs / 标签页; `initial_tab` First tab shown / 初始标签页 | A checklist of the three tabs with Move up / Move down, then a choice among the selected tabs. "One tab hides the tab bar." / "只选一个标签页时不显示标签栏。" Until the checklist exists, the generic JSON control. |
| 2. Size / 尺寸 | `width`, `height`, `min_width`, `max_width` | Size fields. "Give the panel a height so the conversation scrolls inside it." / "请为面板设置高度，使对话在面板内滚动。" |

## Examples

The JSON below is complete but **not runnable until R1 is implemented and its class is
registered**. The page that places this panel beside a composer is in the
[composer's document](interpreter-chat-composer.md#a-chat-page).

### Class `chat-panel`

```json
{
  "descriptor_id": "chat-panel",
  "schema_version": "0.4",
  "code_module_id": "chat-panel",
  "description": { "en": "Conversation, history and settings of the page's chat", "zh-cn": "页面聊天的对话、历史和设置" },
  "implement_notes": { "en": "KnowledgeStore/doc-repo/code_modules/interpreter-chat-panel.md" },
  "tabs": {
    "help_tip": { "en": "Tabs shown, in order: chat, dialog, settings.", "zh-cn": "显示的标签页及其顺序：chat、dialog、settings。" },
    "default_value": ["chat", "dialog", "settings"]
  },
  "initial_tab": {
    "help_tip": { "en": "Tab shown first; leave out for the first tab.", "zh-cn": "首先显示的标签页；留空则为第一个。" }
  },
  "width": {
    "help_tip": { "en": "Width of the panel.", "zh-cn": "面板宽度。" },
    "default_value": "elastic"
  },
  "height": {
    "help_tip": { "en": "Height of the panel; the conversation scrolls inside it.", "zh-cn": "面板高度；对话在其中滚动。" },
    "default_value": "640px"
  },
  "min_width": {
    "help_tip": { "en": "Narrowest width of the panel.", "zh-cn": "面板的最小宽度。" },
    "default_value": "280px"
  }
}
```

### An instance in a panel, with its class copy

A panel without the Dialog tab, opening on Chat, taller than the default.

```json
{
  "element": "chat-panel",
  "class": {
    "descriptor_id": "chat-panel",
    "schema_version": "0.4",
    "code_module_id": "chat-panel",
    "description": { "en": "Conversation, history and settings of the page's chat", "zh-cn": "页面聊天的对话、历史和设置" },
    "implement_notes": { "en": "KnowledgeStore/doc-repo/code_modules/interpreter-chat-panel.md" },
    "tabs": {
      "help_tip": { "en": "Tabs shown, in order: chat, dialog, settings.", "zh-cn": "显示的标签页及其顺序：chat、dialog、settings。" },
      "default_value": ["chat", "dialog", "settings"]
    },
    "initial_tab": {
      "help_tip": { "en": "Tab shown first; leave out for the first tab.", "zh-cn": "首先显示的标签页；留空则为第一个。" }
    },
    "width": {
      "help_tip": { "en": "Width of the panel.", "zh-cn": "面板宽度。" },
      "default_value": "elastic"
    },
    "height": {
      "help_tip": { "en": "Height of the panel; the conversation scrolls inside it.", "zh-cn": "面板高度；对话在其中滚动。" },
      "default_value": "640px"
    },
    "min_width": {
      "help_tip": { "en": "Narrowest width of the panel.", "zh-cn": "面板的最小宽度。" },
      "default_value": "280px"
    }
  },
  "tabs": ["chat", "settings"],
  "initial_tab": "chat",
  "height": "760px"
}
```

<a id="review-record"></a>

## Review record

**R1, 2026-10-30.** First draft, written with the composer's R1. No human feedback or approval
has been recorded. The user's decision of 2026-10-30 (two elements; the conversation in a new
Chat tab) and assumptions A1–A3, A5 and A7 of the
[composer's review record](interpreter-chat-composer.md#review-record) apply here too.

Open questions:

- **Q2 Height.** The panel cannot fill its pane's height today, so R1 gives it a fixed
  default height of 640px. Accept that, or first extend the layout so an element can fill its
  pane's height (a flow-layouter change, with its own review)?
- **Q4 Session header.** The screenshot leaves out chatter-01's session tabs and Sessions
  menu, but without them earlier sessions cannot be reached. R1 puts a session select,
  History menu and close button in the Chat tab's header. Keep that, move them elsewhere, or
  drop session switching?
- Q1 and Q3 concern the composer; see its [review record](interpreter-chat-composer.md#review-record).

Approval must name R1 or a later revision. A material change returns to review. Automated
checks do not replace human approval.

## Implementation and verification

Nothing is implemented; the read-only findings are in the
[composer's document](interpreter-chat-composer.md#implementation-and-verification). Document
checks: the JSON blocks parse; the instance's class copy equals its class; relative links resolve.

After approval, in the same ChenWeb OpenSpec change as the composer: build
`ChatPanelElement.svelte` on the shared store, reusing `harness-dialog.svelte`; register it;
add its `types.ts` fields, `wpi_chat_*` messages, `codeModules` entry, value checks and the
page check; add the Properties groups; add the `kb.code_modules` row and `chat-panel` class by
goose migration. Verify in a browser: tab order and `initial_tab`, the one-tab form,
streaming and permission decisions, session select and History, settings edits with and
without `agents` on the composer, hidden and shown pages, two panels on one page, keyboard
use of the tabs, both languages, both themes and narrow panes.
