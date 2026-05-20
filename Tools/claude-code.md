# Claude Code Cheat Sheet

https://cc.storyfox.cz/

## Hooks
### Session Lifecycle (4)
| Hook	| When it fires	| Can block? |
|-------|---------------|------------|
| Setup	| During --init-only, --init, or --maintenance modes	| No |
| SessionStart	| Session starts or resumes (startup/resume/clear/compact)	| No |
| SessionEnd	| Session terminates (clear/resume/logout/other)	| No |
| Stop	| Claude finishes a response	| Yes |
-----------

### Per-Turn (3)
| Hook	| When it fires	| Can block? |
|-------|---------------|------------|
| UserPromptSubmit	| After you submit a prompt, before Claude processes it	| Yes |
| UserPromptExpansion	| When a user-typed command expands into a prompt	| Yes |
| StopFailure	| When a turn ends due to an API error	| No |
-----------

### Tool Calls (6)
| Hook	| When it fires	| Can block? |
|-------|---------------|------------|
| PreToolUse	| Before a tool executes	| Yes |
| PostToolUse	| After a tool succeeds	| No (observe only) |
| PostToolUseFailure	| After a tool fails	| No |
| PostToolBatch	| After a batch of parallel tool calls resolves	| Yes |
| PermissionRequest	| When a permission dialog appears	| Yes |
| PermissionDenied	| When auto-mode denies a tool call	| No |
-----------

### Context & Instructions (3)
| Hook	| When it fires	| Can block? |
|-------|---------------|------------|
| InstructionsLoaded	| When CLAUDE.md or rules are loaded	| No |
| PreCompact	| Before context compression	| Yes |
| PostCompact	| After context compression completes	| No |
-----------

### SubAgents & Tasks (4)
| Hook	| When it fires	| Can block? |
|-------|---------------|------------|
| SubagentStart	| When a subagent is created	| No |
| SubagentStop	| When a subagent finishes	| Yes |
| TaskCreated	| When a task is created via TaskCreate	| Yes |
| TaskCompleted	| When a task is marked complete	| Yes |
-----------

### Teams (1)
| Hook	| When it fires	| Can block? |
|-------|---------------|------------|
| TeammateIdle	| When a team agent is about to go idle	| Yes |
-----------

### MCP (2)
| Hook	| When it fires	| Can block? |
|-------|---------------|------------|
| Elicitation	| When an MCP server requests user input mid-tool-call	| Yes |
| ElicitationResult	| After user responds to an MCP request, before sending back to server	| Yes |
-----------

### Files, Config & Environment (4)
| Hook	| When it fires	| Can block? |
|-------|---------------|------------|
| ConfigChange	| When settings change mid-session	| Yes |
| CwdChanged	| When the working directory changes (cd)	| No |
| FileChanged	| When a watched file changes on disk	| No |
| Notification	| When Claude Code sends a notification	| No
-----------

### Worktree (2)
| Hook	| When it fires	| Can block? |
|-------|---------------|------------|
| WorktreeCreate	| When a worktree is created	| Yes
| WorktreeRemove	| When a worktree is removed	| No
-----------

Hooks support 5 handler types: command, http, mcp_tool, prompt, and agent. Configuration goes in any of 6 locations (from lowest to highest priority): user settings → policy settings → plugin hooks → project settings → project local settings → skill/agent frontmatter.