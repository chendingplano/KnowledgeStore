#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#show heading: it => {
  set text(fill: blue) if it.level == 1
  if it.numbering != none {
    counter(heading).display(it.numbering)
    h(0.5em) // Adds a little gap after the number
  }
  it.body
}

#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "Reading-202602"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

= Lessons from Building Claude code

#let a_001 = link(
  "https://x.com/trq212/status/2027463795355095314"
)[#text(fill: blue)[article]]

Link: #a_001

Source: TouTiao

- One of the hardest parts of building an agent harness is constructing its action space
- Claude Code does it through tool calling
- There are a number of ways to construct tools (bash, skills, code execution, etc.)
- Do you need just one or only very few (such as bash or code execution)?
- Or you want to have 50+ or even more tools

== AskUserQuestion Tool

It tried to let Claude ask user questions (as needed) in the ExitPlanTool (a tool). 
It is not flexible and sometimes not working.

It then tried to let Claude generate output that contains the questions to ask users.
This works most of the time. But Claude often add more contents, sometimes does not follow the format.

It finally decided to write a AskUserQuestion tool. The idea (I guess) is that when you
want LLMs to do something, reliably, let LLMs use a tool can be the most effective way.

Claude Code has plan mode and work mode. AskUserQuestion is used in the plan mode only.
Pi does not have plan mode.

My question is: why we want to limit AskUserQuestion to the plan mode only. During implementation,
if LLMs find more details and need users to determine the choices, we can use AskUserQuestion.

However, one of the pi principles is not to ask users because it wants to do the jobs without
interruption, or autonomousely. To do things autonomousely is a design principle. We should 
stick with it as much as possible, but only when doing so makes sense. If LLMs already know
it would be better to let users make decision rather than let LLMs pick one, there is no point
to continue the current workflow. Getting humans involved in a workflow IS important, though
it should be kept minimal.

== Updating with Capabilities

As models getting better, something that must be done before may turn out to be more constraining.
We should keep tracking the performance of the system to make sure the assistant (Claude Code)
advances along with the advances of LLMs.

== Designing a Search Interface

- When Claude code first came out, it used an RAG vector database to find context for Claude.
  While RAG was powerful and fast it requires indexing and setup and could be fragile across
  a host of different environments. More importantly, Claude was given this context
  instead of finding the context itself.
- If Claude can search the web, why not search the codebase? By giving Claude the grep tool,
  it lets Claude search for files and build context itself.
- As LLMs get smarter, it becomes increasingly good at building its context if it is
  given the right tools.

== Incremental Discovery

- Agent Skills: formalize the idea of progressive disclosure, which allows agents to
  incrementally discover relevant context through exploration.
- A common use of skills is to add more search capabilities to LLMs like giving it
  instructions on how to use an API or query a database.
- Over the course of a year Claude went from not really being able to build its own context,
  to being able to do nested search across several layers of files to find the exact
  context it needed.

== Progressive Disclosure - The Claude Code Guide Agent

- Claude Code currently has about 20 tools. 
- Add new tools with care (higher bar)
- Claude (the LLM) does not know Claude Code (surprising, right?!)
- One solution is to add information in the context. But this information is normally not used
  at all unless one wants to ask questions about Claude Code
- Claude Code uses a sub-agent (why not an agent?). Claude is prompt to call when it is asked
  about Claude Code.

The question is:
- Add a Tool
- Add an Agent
- Add a Skill

I am not sure whether Claude Code distingushes agents and skills.

= Agents and Skills

Source: Qwen

== Core Definitions
Aspect
Agent
Skill
Primary Role
Orchestrates workflows, makes decisions, manages state
Packages reusable expertise or procedural knowledge
Scope
Vertical: specialized for a specific domain/task
Horizontal: broadly applicable across contexts
Execution
Can invoke tools, manage multi-step reasoning, maintain memory
Provides context/instructions; doesn't execute code directly
Analogy
An employee in a department (e.g., "debugging specialist")
A tool/app employees use (e.g., "fact-check macro")

== Key Distinctions
*🤖 Agents*
- Autonomous decision-makers: Agents have reasoning loops, can plan multi-step tasks, and manage
  state across interactions (`thenewstack.io`)
- Workflow orchestrators: They decide which capabilities to use and when (`thenewstack.io`)
- Scope-bound: Typically designed for a specific purpose (e.g., "code migration agent," "customer
  support agent")
- Can use skills: Agents dynamically load and apply relevant skills during execution (
  `www.christopherspenn.com`)

*🧰 Skills*
Modular expertise packages: Skills are declarative bundles containing instructions, templates, scripts, or domain knowledge 
DEV社区
www.arcade.dev
Progressive loading: Agents see only skill metadata initially; full content loads on-demand to protect context windows 
thenewstack.io
Reusable across agents: A "fact-check" skill could be used by writing agents, research agents, or QA agents 
www.christopherspenn.com
Maintained independently: Domain experts can update skills without modifying agent logic 
thenewstack.io
Practical Example
A writing agent (agent) might invoke a brand-standards skill to format output, then a fact-check skill to verify claims, then a SEO-optimization skill before publishing. The agent orchestrates; the skills provide specialized knowledge 
www.christopherspenn.com
.
When to Use Which
Build an Agent when you need:
Multi-step workflow orchestration with decision trees
State management across complex operations
Quality control through systematic evaluations
Clear scope boundaries to prevent misuse 
thenewstack.io
Build a Skill when you need:
Reusable procedural knowledge applicable across multiple agents
Domain expertise contributions from non-developers
Context-window efficiency via selective/progressive loading
Capabilities that evolve independently of core agent logic 
thenewstack.io
Architecture Insight
"From the model's perspective, it's all just tools" — but for you, the distinction matters: skills shape how agents think; tools let agents act 
www.eesel.ai
. The most robust systems use agents equipped with skills, not one or the other 
thenewstack.io
.
Production Considerations
Token efficiency: Skills reduce context bloat vs. loading all tool definitions upfront 
www.eesel.ai
Security: Tools require auth/authorization infrastructure; skills are prompt-based but still need execution safeguards 
www.eesel.ai
Maintainability: Skills enable domain experts to contribute without touching agent orchestration code 
thenewstack.io
In short: Agents decide what to do; skills provide the knowledge for how to do it. Modern agentic systems increasingly adopt a hybrid architecture where general-purpose agents dynamically load specialized skills as needed 
www.christopherspenn.com
thenewstack.io
.
If you're working within a specific framework (Anthropic's Agent Skills, LangChain toolkits, MCP, etc.), the implementation details may vary—let me know your stack if you'd like more targeted guidance.

= Jimmy's Neovim setup reference

+ `<space>n` to open NeoTree (the file explorer for neovim),
+ The NeoTree buffer is a normal vim buffer, so you can use
  the normal keybinds (like `hjkl` and `/`) to navigate and search.
+ To format the document, use `<space>f`.
+ Neovim has a concept of a "Working Directory", which is the directory that you instruct neovim to view.
  For example, if you called `vi ./src/` in a project, its working directory would be `./src/`.
  And if you called `vi ./src/main.rs`, its working directory will still be `./src/`.
+ You can go back a directory within NeoTree by pressing `<backspace>`.
+ Within NeoTree, you can use `a` to create a file/directory (depending on whether the name ends with `/`),
  you can also add multiple directories by specifying a path (`src/package/main.rs`).
  You can use `r` to rename a file/directory, use `x` to cut, `y` to copy, and `p` to paste.
+ To grep all file contents, use `<space>sg`. To grep all file names, use `<space>sf`. This will
  only search within the working directory that vi is in.
+ There are multiple LSP actions that you can take within neovim. In order to go to definition, use `gd`.
  That is the most common one that I use. The other important ones are `gri` (go to implementation),
  `grD` (go to declaration), `gra` (call LSP code action, like rename or add linting comments), and
  `grr` (go to references).
+ You can press `K` over anything to get LSP definitions of the item you're hovering.
+ Every time neovim navigates, it adds an entry onto the navigation stack. In order to pop out of the stack,
  use `<ctrl>o`. In order to navigate into the stack, use `<ctrl>i`. For example, if I went to a definition,
  I would use `<ctrl>o` to go back to where I was. If I want to recall what I was reading, I would use `<ctrl>i`
  to redo the navigation.
+ Neovim keeps history of which file you last visited, and `<backspace>` in normal mode allows you to switch between
  the last two buffers.
+ Actually neovim keeps history of all files you viewed, so by using `<space>b` you can open a tree of all buffers
  you have visited. This is the same UI as `<space>n`, but it could be preferred since there are a lot less to
  navigate between.
+ You can use `<ctrl><space>` (it might not work right now because of language switching using the same keybind) to
  manually request a completion from the LSP server. You can use `<ctrl>n` to go down in the list of selections,
  `<ctrl>p` to go up, and `<ctrl>y` to accept. You can also use `<ctrl>e` to remove the completion box, I normally
  press `<ctrl>e` and then `<ctrl>y` to accept a Github Copilot suggestion.
+ You can use `[d` and `]d` to navigate to the next and previous diagnostic. You can use `<space>e` to view the
  diagnostic message.
