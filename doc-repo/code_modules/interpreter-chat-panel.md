# Code module: `chat-panel`

**Code module ID:** `chat-panel` \
**Classes using it:** `chat-panel` \
**Implementation status:** implemented and active, 2026-10-30 \
**Design revision:** R2, 2026-10-30 — **approved** \
**Approval:** the user approved the proposal on 2026-10-30, with the R2 changes recorded in the
[composer's review record](interpreter-chat-composer.md#review-record) \
**Catalogue row:** `kb.code_modules` `chat-panel`, "Chat Panel", type `element`, `module_doc`
`interpreter-chat-panel.md`, status `active`, from migration
`ChenWeb/project_migrations/20261030000005_wpi_chat_elements.sql` \
**Companion module:** [`chat-composer`](interpreter-chat-composer.md), which sends the messages this
panel shows; its [Chat session](interpreter-chat-composer.md#chat-session) section is the contract
both share \
**Source UI:** ChenWeb Development → Chat (`/development?view=chat`): the side panel and the
conversation area of `ChenWeb/web/src/lib/components/shared-ui/chatter-01.svelte`, which is unchanged \
**Frontend:** `ChenWeb/web/src/lib/wpi/elements/ChatPanelElement.svelte`, registered in
`elements/index.ts`, using the chat in `ChenWeb/web/src/lib/wpi/chat-session.svelte.ts` and the
conversation view `ChenWeb/web/src/lib/components/shared-ui/harness-dialog.svelte` \
**Backend:** `codeModules["chat-panel"]` in `ChenWeb/server/api/wpi/validate.go`; checks in
`ChenWeb/server/api/wpi/chat_attributes.go` \
**OpenSpec:** ChenWeb change `wpi-chat-elements` \
**Part of:** reusable module `20261026-01`, [Web Page Interpreter frontend](../modules/module-web-page-interpreter-frontend.md) \
**Design:** [WPI devdoc](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md) §3.5 Elements,
§3.7 Element layouters, §5 Actions, §7 Validation; [Page Layouter](interpreter-layouter-page.md)

## Purpose and boundary

The chat panel shows the chat of its page in two tabs.

- **Chat** shows the active session's conversation, which chatter-01 shows in its middle area:
  messages, streamed replies, tool calls, permission requests and errors. Its header switches
  between sessions.
- **Dialog** shows the compact history that chatter-01's side panel shows.

Messages are written and sent in the page's [`chat-composer`](interpreter-chat-composer.md).
Both elements share the page instance's chat, so the panel follows the composer's selected
assistant and active session ([Chat session](interpreter-chat-composer.md#chat-session)).

Not part of the panel: writing and sending messages; the Settings tab of chatter-01, whose
lists only served the placeholder assistants (removed in R2); its own resize handle (the pane
is resized by the page layouter's `resizable`); the "Close panel" button of the ChenWeb shell;
data binding, WPI action triggers and appearance attributes.

## What changes from chatter-01

| Area | chatter-01 today | Panel |
| --- | --- | --- |
| Tabs | Dialog, Settings | Chat (new), Dialog; a page chooses which and in what order |
| Conversation | The middle area, beside the side panel | The Chat tab |
| Sessions | A row of session tabs and, for harness agents, a Sessions menu above the conversation | A header in the Chat tab: session select, History menu, close button |
| Settings | Lists of agents, models, attachments, skills and result options, saved to a stub | None: assistants are chosen in the composer's descriptor |
| Width | Its own drag handle, 280–560px | The pane's width; the pane may be `resizable` |
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
| `E.tabs` | Array of 1–2 distinct tokens: `chat`, `dialog` | `["chat", "dialog"]`. The tabs shown, in array order. With one tab the tab bar is not drawn; the content is a region named after the tab. An empty array, unknown (such as `settings`), repeated or non-string tokens are errors. |
| `E.initial_tab` | One of the tokens | Absent: the first of the resolved `tabs`. Must be in the resolved `tabs` (error). Shown when the element first mounts; afterwards the user's choice is kept while the page instance lives, including while it is hidden. |

### Size and layout

| Exact path | Type and allowed values | Absence and behavior |
| --- | --- | --- |
| `E.width` | `auto`, `elastic`, or a nonnegative length in `px`, `rem`, `em`, `%` | Class default `elastic` in the `chat-panel` class: fill the pane's width. |
| `E.height` | Same grammar | Class default `640px` in the `chat-panel` class. The tab bar and session header stay at the top and the conversation scrolls inside the element. With `auto` the element grows with the conversation and the pane scrolls instead, taking the tab bar with it; not recommended. |
| `E.min_width` | Same grammar | Class default `280px` in the `chat-panel` class. |
| `E.max_width` | Same grammar | Unset: no maximum. |

A WPI element cannot yet fill the height of its pane: a panel's height comes from its content,
and the flow layouter does not stretch `elastic` heights (devdoc §3.7). Hence the fixed default
height, which an instance can change to suit its page. Stretching will be addressed later as a
separate layout change (decided 2026-10-30).

<a id="chat-tab"></a>

## Tabs

### Chat

**Header.** One row with:

- a session select listing the open sessions of the selected assistant by title ("New Session"
  until the first message), with the active one selected; choosing one makes it active for the
  composer too;
- a History menu listing the sessions the harness keeps (from this page, a terminal or an
  IDE), newest first, with title or first prompt and time. Choosing one opens it with its stored
  history, or switches to it if it is already open. The menu loads each time it opens and shows
  "No sessions yet" / "暂无会话" when the list is empty or cannot be read;
- a close button for the active session. Closing a session that is streaming stops its reply;
  the session stays on the harness.

**Conversation.** The user's messages; the assistant's replies as they stream in, rendered as
Markdown with raw HTML escaped and unsafe links removed; tool calls with their input and result
or error; permission requests with Allow and Deny, whose decision is sent to the harness and
then shown as Allowed or Denied; and notices, including the composer's error notices. This is
the shared `harness-dialog.svelte`. While a reply streams, a working indicator shows at the
end. When empty: "Start chatting. Type `/` to use slash commands." / "开始聊天。输入 `/` 使用斜杠命令。".

**Scrolling.** The conversation scrolls inside the element. New content keeps it at the
bottom when the user is at the bottom; if the user has scrolled up, the position is kept.
All text can be selected and copied.

### Dialog

A read-only, compact list of the active session: each entry gives its role ("User" / "用户" or
"Assistant" / "助手"), or a tool's name, and its text cut to three lines. Permission requests and
notices are not listed. When empty: "No dialog history yet." / "还没有对话记录。".

## States

| State | Behavior |
| --- | --- |
| No session yet | The session select shows "No open session" and is disabled; the conversation shows its empty text. The composer's first message or New Session creates a session. |
| No composer on the page | The panel still lets the user open harness history, read it and answer permission requests; nothing can be sent. The app gets a warning ([Validation](#validation-and-errors)). |
| Hidden and shown again | The current tab, scroll positions and streaming replies are kept: hidden pages stay mounted. |
| Several panels on one page | Allowed. They show the same chat; each keeps its own current tab. |
| Not an admin | History shows "No sessions yet"; the composer's refused sends show their notices here. |
| Editor preview | No requests are made. Tabs can be switched; Chat and Dialog show their empty text. |

## Keyboard, touch and accessibility

- The tab bar follows the WAI-ARIA tabs pattern: `tablist`, `tab` and `tabpanel`; Left and
  Right move between tabs (wrapping), Home and End go to the first and last, selecting and
  focusing them. Tabs are labelled "Chat" / "聊天" and "Dialog" / "对话".
- The conversation is a focusable scroll region named "Conversation" / "对话内容", so it can be
  scrolled with the keyboard. Streamed text is not read aloud piece by piece; a visually hidden
  status says "Assistant is replying" / "助手正在回复" and "Reply finished" / "回复完成".
- The session select is named "Session" / "会话"; the close button "Close session" / "关闭会话".
- Every control works with the keyboard and touch; nothing depends on hover. Focus rings stay
  visible. Colours come from the theme in light and dark mode, except that the user's messages
  and the Allow button use a fixed indigo (`#4F46E5`) with white text, which reads in both
  themes, because the shared conversation view draws white text on its accent.
- Text stays selectable: the element's root sets `select-text`, since the ChenWeb shell
  disables selection.
- Module text is in Paraglide in English and Chinese under `wpi_chat_*` keys; session titles,
  assistant and model names and messages are data and are shown as given. A language change
  keeps the tab and scroll position.
- The browser does not log messages.

## Validation and errors

| Check | When | Result |
| --- | --- | --- |
| `tabs` or `initial_tab` breaks its grammar, or a value is `null` | Page save and run | Error, naming the path |
| `initial_tab` is not in the resolved `tabs` | Page save and run | Error |
| An instance sets an attribute its class fixes | Page save and run | Error |
| A class names an attribute this module does not support | Class save, app load | Warning; the attribute has no effect |
| A page has a `chat-panel` but no `chat-composer` | App load | Warning: "the page has a chat-panel but no chat-composer, so nothing can be sent" |
| A service call fails | Run time | A notice in the conversation, or "No sessions yet" in the History menu |

Both attributes are optional, so an incomplete page has nothing to finish for this element.

## Property editor

The WPI Editor's Properties panel draws this module's property editor at run time from
`ChenWeb/web/src/lib/wpi/properties/chat.ts` (OpenSpec `wpi-property-editors`); no Svelte
file is written per module. The table below is the contract that file follows: change the
two together. Groups are presentation only; the instance stays flat. Every editor starts
with a **Placement** group showing the element's pane and its position on the page
(read-only). Labels and group names are in Paraglide. Help tips are the class's `help_tip`
for each attribute; an attribute with a non-empty tip gets an info icon at the upper right
of its value editor. A value fixed by the class is shown read-only, marked fixed; *Reset*
removes the instance's own value. Hidden attributes keep their values. A class attribute
the table does not list appears under **Other** with the common-sense value editor. Value
editors are described in devdoc 2026102701 §1.3.9.

| Group | Attribute | Value editor | Data and rules |
| --- | --- | --- | --- |
| Tabs | `tabs` | ordered-multi-picker | `chat`, `dialog`; at least one stays ticked; unset means both |
| Tabs | `initial_tab` | value-picker | The ticked tabs, or *First in the list* (unset) |
| Size | `width`, `height`, `min_width`, `max_width` | length | `auto`, `elastic`, or a number in px, rem, em or %; a bare number means px |

## Examples

### Class `chat-panel`

As stored by migration `20261030000005_wpi_chat_elements.sql`.

```json
{
  "descriptor_id": "chat-panel",
  "schema_version": "0.4",
  "code_module_id": "chat-panel",
  "description": { "en": "Conversation and history of the page's chat", "zh-cn": "页面聊天的对话和历史" },
  "implement_notes": { "en": "KnowledgeStore/doc-repo/code_modules/interpreter-chat-panel.md" },
  "tabs": {
    "help_tip": { "en": "Tabs shown, in order: chat, dialog.", "zh-cn": "显示的标签页及其顺序：chat、dialog。" },
    "default_value": ["chat", "dialog"]
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

A panel with only the Chat tab, and so no tab bar, taller than the default.

```json
{
  "element": "chat-panel",
  "class": {
    "descriptor_id": "chat-panel",
    "schema_version": "0.4",
    "code_module_id": "chat-panel",
    "description": { "en": "Conversation and history of the page's chat", "zh-cn": "页面聊天的对话和历史" },
    "implement_notes": { "en": "KnowledgeStore/doc-repo/code_modules/interpreter-chat-panel.md" },
    "tabs": {
      "help_tip": { "en": "Tabs shown, in order: chat, dialog.", "zh-cn": "显示的标签页及其顺序：chat、dialog。" },
      "default_value": ["chat", "dialog"]
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
  "tabs": ["chat"],
  "height": "760px"
}
```

The page that places a panel beside a composer is in the
[composer's document](interpreter-chat-composer.md#a-chat-page).

<a id="review-record"></a>

## Review record

**R1, 2026-10-30.** First draft, written with the composer's R1.

**Feedback on R1, 2026-10-30 (user):** Q2, keep the fixed default height and address stretching
later; Q4, keep the session header. The other feedback is in the
[composer's review record](interpreter-chat-composer.md#review-record).

**R2, 2026-10-30, approved.** Approved with the composer. For the panel, R2 removes the Settings
tab (the user's choice, since assistants are now chosen in the composer's descriptor), so
`tabs` takes `chat` and `dialog` only. The other R2 changes are recorded with the composer.

## Implementation and verification

Built 2026-10-30 in ChenWeb OpenSpec change `wpi-chat-elements`; the file list and the checks
run are in the [composer's document](interpreter-chat-composer.md#implementation-and-verification).
For the panel the browser check covered: tabs Chat and Dialog with Chat first; ArrowRight and
Home on the tab bar; streamed replies and the session select titled from the first message;
the Dialog tab's entries; New Session, History and Close session; the access notice; selectable
text; Chinese labels; the one-tab form without a tab bar; dark mode and a narrow window by
screenshot. Go tests cover `tabs` and `initial_tab` values, `initial_tab` outside `tabs` and the
unpaired-panel warning.

**Not verified:** permission requests with a real harness (the browser check's stub sent none);
the Properties panel in the browser; a reply streaming while the page is hidden; two panels
on one page.

**Limits:** the panel cannot fill its pane's height (fixed 640px default); it shows only the
active session of the selected assistant.
