## 1. Overview
Link: https://academy.dair.ai/blog/wiki-builder-claude-code-plugin

Wiki Builder is a skill. After installed, you can ask Claude to start
a new wiki, and it will scaffold a clean folder layout, drop in
a per-wiki config file, and seed the prompts for compiling pages, 
filing answers, and linnting the structure. From that point on,
the agent reads the local config first and adapts its behavior to
the wiki you are working on.

### 1.1 Config
The skill is intentionally general. Rather than hardcoding a single wiki layout,
every wiki carries its own wiki.config.md.

### 1.2 Build the Wiki
- Drop raw source material into `raw/`
- Ask the agent to compile structured pages into `wiki/`.
- Ask questions, and file the answers back into the wiki under `wiki/questions/`.
- Run a maintenance pass that looks for thin pages, missing backlinks and 
  uncompiled raw notes.

### 1.3 How It works
Wiki Builder ships three things.

**1. A Scafflding Script**
`init_wiki.sh` creates the folder layout, renders templates, and 
copies the prompt files. By default it writes to `~/dair-wikis/<slug>`,
but you can override the location with the `WIKI_ROOT` environment
variable or a `--root` flag.

**2. A Set of Prompt Templates**
It has a number of prompts. 

**3. A SKILL.md that Teaches Claude the Workflow**

