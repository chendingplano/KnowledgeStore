# Skills

Codex uses the skill list provided in AGENTS.md for the current workspace/session, then applies these trigger rules:

1. It scans your request for explicit skill names (like $skill-name or plain mention).
2. It also checks whether your task clearly matches a skill description.
3. If one or more skills match, it must use them for that turn.
4. It opens the matched skill’s SKILL.md from the listed file path, reads only what’s needed, and follows that workflow.
5. If multiple skills match, it uses the minimal set and sequences them.
6. If a named skill is missing/unreadable, it tells you briefly and falls back to a best-effort approach.

In short: lookup comes from the preloaded skill registry in your instructions, and triggering happens by explicit mention or intent matching.