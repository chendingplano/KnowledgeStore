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
    "Diary-20260313"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

= Claude Can Draw Charts Now

#let a_001 = link(
  "https://claude.com/blog/claude-builds-visuals"
)[#text(fill: blue)[Hacker News]]

#a_001

It is not only generate charts, but interactive charts. You can click it. For instance, 
you can ask Claude to draw a period table. You can click on an element in the table.
The chart will show the details.

It can also create tabs, pulldowns, etc.

== Thoughts

This feature is not available in Claude Code (I believe). But we can create a skill for
chat-to-web-page. Instead of generating textual contents, we can ask an LLM to generate
web pages and add it to my ChatApp.

= Autoresearch

#let a_002 = link(
  "https://github.com/karpathy/autoresearch"
)[#text(fill: blue)[Karpathy]]

#let a_003 = link(
  "https://github.com/miolini/autoresearch-macos"
)[#text(fill: blue)[GitHub-MacOs]]

#a_002 \
#a_003 \
Source: Hacker News

== Core Idea

Give an AI agent a small but real LLM training setup and let it experiment autonomously overnight.
It modifies the code, trains for 5 minutes, checks if the result improved, keeps or discards, and repeats.

Here is what Autoresearch does (instead of a human doing):

- Modify training code
- Train the model
- Evaluate results
- Adjust hyperparameters
- Repeat
- …

the AI agent performs this loop automatically.

The loop:
```markdown
1. Read the training code
2. Propose a change (architecture, optimizer, hyperparameter)
3. Modify train.py
4. Train the model for a short time (e.g., 5 minutes)
5. Evaluate validation loss
6. If better → keep change
   else → revert change
7. Repeat indefinitely
```

The system can run about 1000 experiments overnight on one GPU.

It trains an LLM, a tiny one:
- GPT-style transformer
- About 10M parameters (toy model)
- Trained on tiny datasets like:
  - TinyStories
  - TinyShakespeare

These datasets are included in the repo or automatically downloaded.

== The Value

The key innovation is not the model. It is research automation pattern. Instead of humans
doing experiments, it becomes:
- Human: write research strategy (program.md)
- Agent: run experiments forever

This changes the researcher's role to:
*design experiment search space rather than manually tuning models.*

== Evaluation

(From ChatGPT)

Evaluation the *most critical component*.
In *AutoResearch*, the *evaluation metric* determines whether a code change is *accepted or rejected*. 
Without a reliable evaluation signal, the whole autonomous loop would fail.

The mechanism is actually *very simple and deterministic*.

=== Core idea: validation loss as the judge

After every training run, AutoResearch evaluates the model using a *validation dataset* and computes *validation loss*.

Typical metric:

```
cross-entropy loss on validation set
```

Interpretation:

#table(
  columns: 2,
  align: left,
  [Validation Loss], [Meaning],
  [Lower], [Model improved],
  [Higher], [Model worse]
)

The system then compares:

```
new_loss vs best_loss
```

Decision logic:

```
if new_loss < best_loss:
    accept change
else:
    revert change
```

So the entire evaluation system boils down to:

> *minimize validation loss*

=== How the evaluation is implemented

The evaluation code is intentionally placed in a file the agent *cannot modify*.

Typically:

```
prepare.py
```

contains:

```
train_dataset
validation_dataset
evaluation logic
```

Example simplified flow:

```
train.py
   |
   v
train model for N steps
   |
   v
run validation
   |
   v
compute cross_entropy_loss
   |
   v
print result
```

The result is then parsed by the orchestration script.

=== Why the evaluation code is locked

The AI agent is allowed to modify:

```
train.py
```

But *not*:

```
prepare.py
```

This prevents the agent from *cheating* the benchmark.

Otherwise it might do things like:

```
return loss = 0
```

or

```
skip validation
```

So the evaluation function acts like a *fixed benchmark*.

=== What exactly is being evaluated

The evaluation is typically:

```
per-token cross entropy
```

For a GPT-style model:

```
Loss = -log P(next_token | previous_tokens)
```

Example:

```
Input:  "The cat sat on the"
Target: "mat"

Model predicts probability distribution over vocabulary.

Loss computed using cross entropy.
```

Average loss over the validation set becomes the *score*.

=== Example evaluation loop

Conceptually the system runs something like:

```
best_loss = 2.15

agent modifies train.py

run training
loss = evaluate()

if loss < best_loss:
    keep change
    best_loss = loss
else:
    revert change
```

So the repository gradually accumulates *improving commits*.

=== Why training runs are very short

Training is usually limited to something like:

```
few thousand steps
```

or

```
5 minutes
```

Reason:

The agent needs *fast feedback*.

Instead of:

```
1 experiment = 3 days
```

they want:

```
1 experiment = 3 minutes
```

Then overnight:

```
~100 experiments
```

=== Weakness of this evaluation approach

Although simple, it has limitations.

* 1️⃣ noisy signal*

Short training runs produce *high variance* results.

The agent might think something improved when it didn't.


* 2️⃣ overfitting ris *

If the validation set is small:

```
agent may optimize for that specific dataset
```


* 3️⃣ local optima*

Simple greedy acceptance:

```
accept only improvements
```

means the system may get stuck in a *local minimum*.


=== More advanced evaluation strategies (not in the repo)

More advanced autonomous research systems may use:

* multiple metrics*

```
score =
    0.6 * validation_loss
  + 0.3 * perplexity
  + 0.1 * inference_speed
```


* statistical tests*

Instead of:

```
loss_new < loss_old
```

Use:

```
statistically significant improvement
```


* multiple runs*

```
run experiment 3 times
average result
```


=== Simple mental model

AutoResearch is basically doing *automated hyperparameter search*:

```
propose change
train
measure validation loss
accept or reject
repeat
```

So evaluation is just:

> *validation loss on a fixed dataset*


💡 *Interesting insight*

AutoResearch demonstrates something important:

You *do not need complex evaluation* for autonomous ML research.

As long as you have:

```
fast training
+
stable metric
```

an AI agent can *search the model design space automatically*.


If you'd like, I can also explain *the three biggest tricks AutoResearch uses to prevent the AI agent from breaking the training code* (this part is actually very clever).

== Agent in the Loop

Agent (Claude Code, Codex, etc.) orchestrates the whole loop, while AutoResearch mainly provides
the training + evaluation framework.

The loop is:
```yaml
Agent: read repository and instructions (program.md)

LOOP
    Agent: propose change to train.py
    Agent: edit train.py
    Agent: run training (python train.py)

    AutoResearch code:
        train model
        evaluate validation loss
        output metrics

    Agent: read results
    Agent: decide:
        keep change (commit)
        OR revert change

    Agent: decide whether to continue
END
```

*The agent performs most of the orchestration*.


=== What AutoResearch actually provides

AutoResearch mainly provides *three things*:

*Training pipeline*

```
train.py
```

Contains:

- model architecture
- optimizer
- training loop

*Evaluation logic*

Usually inside:

```
prepare.py
```

This computes:

```
validation_loss
perplexity
```

* 3️⃣ Stable dataset + metric*

This ensures the agent cannot cheat.

=== What the agent actually does

The agent is responsible for *research decisions*.

Example tasks:

* modify model architecture*

```
increase transformer layers
change attention heads
add dropout
```

* modify training parameters*

```
learning rate
batch size
optimizer
weight decay
```

* modify implementation*

```
activation function
initialization
normalization
```

* analyze results*

Example reasoning:

```
Loss improved from 2.35 → 2.28.
This suggests the deeper model helped.
Next I will try increasing embedding size.
```

=== Where git fits in

Git is used to track experiments.

Typical flow:

```
edit train.py
run experiment

if improvement:
    git commit
else:
    git checkout previous version
```

So the repository history becomes a *log of successful experiments*.

=== Important nuance: AutoResearch does not decide “keep or revert”

In many implementations:

```
Agent decides
```

because it reads the loss from logs.

Example output:

```
validation loss: 2.17
```

The agent compares this with the previous best result and decides.

=== Mental Model of the Loop

Your version:

```
Agent: edit train.py
Agent: run train.py

AutoResearch code:
    train model
    compute validation loss
    print result

Agent:
    read result
    decide keep or revert
    git commit or rollback
    decide next experiment
    continue or stop
```

So *the agent drives the research*.

=== Why this design is important

This design makes the system *very flexible*.

Different agents can be used:

- Claude Code
- Codex
- Gemini CLI
- OpenClaw
- Cursor agents

Because the repo just exposes:

```
edit code
run training
read metrics
```


=== Mental model

Think of AutoResearch as a *gym environment for ML experiments*.

```
Environment:
    training code
    dataset
    evaluation metric

Agent:
    proposes experiments
```

So conceptually:

```
AutoResearch = ML environment
Agent = researcher
```
 
= pi-autoresearch - Autonomous Research for pi

#let a_004 = link(
  "https://github.com/davebcn87/pi-autoresearch?tab=readme-ov-file"
)[#text(fill: blue)[GitHub]]

#a_004 \
Source: Hacker News

This project is inspired by Karpathy's #a_003

We will come back to this open-source when we work on pi!

= Conversational UI

== Value Proposition

I have an app that has a GUI, which consists of many web pages and a menu tree with possibly hundreds of menu items. 
Users use the app by picking and clicking menu items to open the desired pages, and so on. Menu tree can get pretty
complicated. To make the app user friendly, I would like to add a "Chat Interface": the app has a chat panel. 
Users can express what they want, the Chat decides whether the thing can be done, and if yes, open the correponding
page, etc.

Can PageAgent be used to achieve this goal?

=== Short Answer
Yes — *PageAgent can help*, but *not exactly the way you described*, and it might *not be the best architecture* for your case. Your use case is actually a very common pattern now called a *“conversational UI for enterprise apps”*.


=== Your goal (architecture)

Your application roughly looks like this:

```
Web App
 ├── Menu system
 │    ├── Sales
 │    │    ├── Orders
 │    │    ├── Customers
 │    │    └── Reports
 │    ├── Inventory
 │    └── Settings
 └── Many pages
```

Users currently navigate by:

```
click menu → open page → perform action
```

You want:

```
User: "Show me last month's sales report"

Chat Agent:
    understand intent
    navigate to correct page
    open report
```

This is a *very reasonable feature*.

=== Can PageAgent implement this?

*Short answer*

✅ *Yes, technically possible*

But:

⚠️ *It is not the intended use case and may be inefficient.*

=== How PageAgent would work in your case

If you embed PageAgent in your app, the flow would be:

```
User prompt
     ↓
LLM analyzes DOM
     ↓
Find menu item
     ↓
Click menu
     ↓
Open page
```

Example:

User:

```
Open inventory settings
```

Agent internally does something like:

```
document.querySelector("menu:contains('Inventory')")
click()

document.querySelector("menu:contains('Settings')")
click()
```

So navigation happens *by clicking the UI like a human*.

=== Why this approach is not ideal

For your application, the AI *already knows the structure*.

Instead of:

```
AI → inspect DOM → click buttons
```

You could do:

```
AI → call navigation API
```

Example:

```
openPage("inventory/settings")
```

This is *far more reliable*.

=== Better architecture for your case

A cleaner architecture would be:

```
User
 ↓
Chat panel
 ↓
LLM
 ↓
Structured command
 ↓
App navigation API
 ↓
Open page
```

Example flow:

User:

```
Open inventory settings
```

LLM returns:

```json
{
  "action": "navigate",
  "page": "inventory/settings"
}
```

Your app executes:

```
router.navigate("/inventory/settings")
```

No DOM clicking needed.

=== Why this is better than PageAgent

Advantages:

*deterministic*

No guessing from DOM.

*cheaper*

No large DOM prompt sent to LLM.

*faster*

Single API call instead of multiple steps.

*safer*

You control exactly what actions are allowed.

=== Where PageAgent is useful

PageAgent is better for *generic websites* where you *cannot modify the backend*.

Example:

```
AI controlling Gmail
AI controlling Amazon
AI controlling random SaaS dashboards
```

In those cases the AI must:

```
inspect page
click elements
fill forms
```

=== Your use case is different

Your situation:

```
You own the application
```

So you can expose internal APIs like:

```
openPage()
openReport()
createOrder()
```

Then the AI simply calls those.

This pattern is often called:

```
LLM tool calling
```

or

```
AI command interface
```

=== Real systems that use this approach

Large enterprise tools already do this.

Examples:

- Salesforce Einstein Copilot
- Notion AI navigation
- Microsoft Copilot for Dynamics
- SAP Joule

They *do not click the UI*.

They call *internal app APIs*.

=== Best architecture for your case

Recommended structure:

```
App
 ├── menu system
 ├── router
 └── chat agent

Chat agent
 ├── LLM
 └── tools
        ├── navigate_page
        ├── open_report
        ├── search_customer
        └── create_order
```

Example tool:

```json
{
  "name": "navigate_page",
  "parameters": {
    "page_id": "string"
  }
}
```

=== Bonus idea (very useful)

Since your menu tree is large (hundreds of items), you can give the LLM a *menu index*.

Example:

```
Inventory
   - inventory/products
   - inventory/stock
Sales
   - sales/orders
   - sales/reports
```

Then the model chooses the correct page.

=== When PageAgent might still help

You could combine both approaches:

```
LLM → navigation API
LLM → PageAgent (for complex UI actions)
```

Example:

```
open page via API
fill form via PageAgent
```

But many apps simply implement *form APIs instead*.

=== Final recommendation

For *your app*, the best design is:

```
Chat interface
    +
LLM tool calling
    +
internal navigation APIs
```

Not PageAgent.

✅ *Summary*

#table(
  columns: 2,
  align: left,
  [Question], [Answer],
[ Can PageAgent do it?      ], [Yes ],
[ Is it ideal for your app? ], [No    ],
[ Better approach?          ], [LLM + navigation API           ],
[ Why?                      ], [Faster, deterministic, cheaper ]

)

== A Common Pattern

(By ChatGPT)

Large SaaS systems (CRM, ERP, analytics tools, etc.) often implement a *“semantic navigation layer”* between the chat interface and the application router.
Instead of letting the LLM guess UI elements, they give the model a *structured index of the entire application* and let it choose the correct destination.

This pattern scales to *hundreds or thousands of pages*.

Below is the architecture used in many modern SaaS copilots.

=== High-level architecture

```
User
  ↓
Chat interface
  ↓
LLM intent analysis
  ↓
Menu / page semantic index
  ↓
Best page match
  ↓
Router API
  ↓
Open page
```

Key idea:

The LLM *does not inspect the DOM*. It searches a *semantic catalog of pages*. This means when
we build applications, we need to build a semantic catalog of pages (see below).

=== Step 1 — Build a “Page Catalog”

First create a *structured catalog of all pages in the app*.

Example:

```json
[
  {
    "id": "sales_orders",
    "title": "Sales Orders",
    "path": "/sales/orders",
    "description": "View, create, and manage customer orders",
    "keywords": ["orders", "sales order", "purchase order"]
  },
  {
    "id": "sales_reports",
    "title": "Sales Reports",
    "path": "/sales/reports",
    "description": "Analytics and reports for sales performance",
    "keywords": ["sales report", "revenue report", "monthly sales"]
  },
  {
    "id": "inventory_stock",
    "title": "Inventory Stock",
    "path": "/inventory/stock",
    "description": "Current stock levels and warehouse inventory"
  }
]
```

=== App Knowledge Base

Yes, an app should have a knowledge base. *Page Catalog* is part of its knowledge base.
This knowledge base MUST be a *navigation knowledge base*, which is a very important aspect of
AI-enabled Artifact.

=== Step 2 — Create embeddings for pages

Convert each page entry into a *vector embedding*.

Example pipeline:

```
Page description
        ↓
Embedding model
        ↓
Vector database
```

Example embedding input:

```
Sales Reports
Analytics and reports for sales performance, revenue, and monthly sales trends
```

Store vectors in something like:

- PostgreSQL + pgvector
- Pinecone
- Weaviate
- Elasticsearch
- Redis vector

=== Step 3 — User query → semantic search

User asks:

```
Show me last month's sales numbers
```

System performs:

```
embedding(user_query)
       ↓
vector similarity search
       ↓
top K pages
```

Example results:

```
1. Sales Reports
2. Sales Dashboard
3. Orders
```

=== Step 4 — LLM selects the correct page

The LLM receives:

```
User query
+
Top candidate pages
```

Example prompt:

```
User request:
"Show me last month's sales numbers"

Candidate pages:
1. Sales Reports — analytics and revenue reports
2. Sales Dashboard — overview metrics
3. Orders — manage customer orders

Which page should open?
```

LLM returns:

```json
{
  "action": "navigate",
  "page": "sales_reports"
}
```

=== Step 5 — Application opens the page

Your app simply calls the router:

```
router.navigate("/sales/reports")
```

The UI updates instantly.

=== Why this works extremely well

This pattern works because it combines:

*semantic search*

handles natural language

*structured routing*

guarantees deterministic navigation

=== Performance with large menu trees

Even with *1000+ pages*, performance stays fast.

Typical numbers:

```
embedding search: ~5–20 ms
LLM reasoning: ~200–800 ms
page navigation: instant
```

So the user sees:

```
chat → page opens in ~1 second
```

=== Additional improvements used in real SaaS systems

*(1) Menu hierarchy awareness*

Store parent menus:

```json
{
  "id": "sales_reports",
  "menu_path": ["Sales", "Reports"],
  "path": "/sales/reports"
}
```

This lets the AI explain navigation:

```
Opening: Sales → Reports
```

*(2) Usage telemetry*

Track frequently used pages.

```
boost score if page frequently used
```

*(3) Permission filtering*

Only return pages the user is allowed to access.

*(4) Action suggestions*

Instead of only navigation:

```
create invoice
add customer
generate report
```

These become *tools* the LLM can call.

=== Example user experience

User types:

```
Where do I update product prices?
```

System:

```
search page index
```

Candidates:

```
Product Catalog
Pricing Rules
Inventory Settings
```

LLM selects:

```
Product Catalog
```

Response:

```
Opening Product Catalog page.
```

Page opens automatically.

=== Why this pattern is better than DOM agents

DOM-based approach (PageAgent):

```
LLM reads page
LLM clicks menu
LLM clicks submenu
```

Problems:

- fragile
- slow
- token heavy

Semantic navigation:

```
LLM selects page
router opens page
```

Much simpler and robust.

=== Simple implementation stack

A typical stack looks like:

```
Frontend
  └─ Chat panel

Backend
  ├─ page catalog
  ├─ embedding service
  ├─ vector search
  └─ LLM tool calling

App
  └─ router.navigate()
```

=== Example minimal API

Navigation tool:

```json
{
  "name": "open_page",
  "parameters": {
    "page_id": "string"
  }
}
```

LLM returns:

```json
{
  "tool": "open_page",
  "arguments": {
    "page_id": "sales_reports"
  }
}
```

=== Why large SaaS apps like this pattern

This design:

- scales to *thousands of pages*
- supports *natural language*
- is *deterministic*
- integrates with *existing routers*

✅ *Key takeaway*

The powerful pattern is:

```
Semantic page index
      +
vector search
      +
LLM tool calling
      +
app router
```

This is currently the *most reliable architecture for AI navigation in large web apps*.


== Task-Level Navigation

*Task-level navigation* is the next step beyond simple “open page” navigation.
Instead of mapping *one user request → one page*, the system maps:

```
user request → multi-step workflow
```

This is how many advanced SaaS copilots work.

=== Concept

Basic navigation system:

```
User: "Open sales reports"

AI → open page
```

Task-level navigation:

```
User: "Create a customer and send the first invoice"

AI executes multiple steps across pages.
```

Example workflow:

```
1. Open customer page
2. Create customer
3. Open invoice page
4. Create invoice
5. Link invoice to customer
```

The user never touches the menus.

=== Architecture

```
User
 ↓
Chat interface
 ↓
LLM intent analysis
 ↓
Task planner
 ↓
Sequence of actions
 ↓
Application APIs / router
 ↓
Execute steps
```

The key new component is the *task planner*.

=== Step 1 — Define application actions

Instead of exposing only pages, expose *structured tools*.

Example tools:

```json
[
  {
    "name": "open_page",
    "parameters": {
      "page_id": "string"
    }
  },
  {
    "name": "create_customer",
    "parameters": {
      "name": "string",
      "email": "string"
    }
  },
  {
    "name": "create_invoice",
    "parameters": {
      "customer_id": "string",
      "amount": "number"
    }
  }
]
```

These tools map to your internal APIs.

=== Step 2 — LLM produces a plan

User:

```
Create a new customer called Acme Corp and generate an invoice for $500
```

LLM generates a *task plan*:

```json
{
  "plan": [
    {
      "action": "create_customer",
      "args": {
        "name": "Acme Corp"
      }
    },
    {
      "action": "create_invoice",
      "args": {
        "customer_name": "Acme Corp",
        "amount": 500
      }
    }
  ]
}
```

=== Step 3 — Execution engine runs the plan

Execution engine:

```
for step in plan:
    call tool
    store result
```

Example:

```
create_customer → returns customer_id=123
create_invoice(customer_id=123)
```

=== Step 4 — UI navigation (optional)

You can optionally open pages during the process.

Example:

```
Step 1 → open /customers
Step 2 → create customer
Step 3 → open /invoices
Step 4 → create invoice
```

But the UI navigation becomes *visual feedback*, not the core logic.

=== Example real workflow

User request:

```
Register a new product and add 50 units to inventory
```

AI plan:

```
1 create_product
2 open inventory page
3 add_stock
```

Execution:

```
create_product("Laptop")
add_stock(product_id, quantity=50)
```

=== How planning works internally

Two common approaches:

*Approach A — single LLM plan*

LLM generates the full plan.

```
prompt → plan → execute
```

Simple and fast.

*Approach B — agent loop*

More advanced systems use an *agent loop*.

```
LLM → choose next tool
tool executes
LLM sees result
repeat
```

Example:

```
Thought: Need to create customer
Action: create_customer
Observation: id=123

Thought: Need to create invoice
Action: create_invoice
```

=== Example UI experience

User types:

```
Add a new vendor called TechSupply and place an order for 200 units
```

Chat shows:

```
✓ Creating vendor
✓ Opening purchase orders
✓ Creating order
✓ Adding items
```

The UI navigates automatically.

=== Why this is powerful

This enables *natural language workflows*.

Users don't need to know:

- menu locations
- page names
- workflow steps

The AI performs the workflow.

=== Example enterprise scenarios

Common examples:

*CRM*

```
Add new customer and schedule onboarding meeting
```

*ERP*

```
Create purchase order for 100 units of product X
```

*Analytics*

```
Generate a revenue report for Q3 and export it
```

=== Key implementation components

Typical stack:

```
Chat UI
   ↓
LLM
   ↓
Task planner
   ↓
Tool registry
   ↓
Execution engine
   ↓
App APIs
```

=== Simple implementation example

Pseudo code:

```python
plan = llm.plan(user_prompt)

context = {}

for step in plan:
    result = run_tool(step.action, step.args)
    context.update(result)
```

=== Combining navigation + tasks

Best systems combine both:

```
semantic page navigation
+
task automation
```

Example:

```
User: "Show last month's sales and export to CSV"
```

Plan:

```
1 open_page sales_reports
2 generate_report
3 export_csv
```

=== Why this pattern is becoming standard

Modern SaaS apps are moving toward:

```
menu-driven UI
        +
AI workflow layer
```

So the UI becomes *optional*.

Users can operate the system via:

```
chat commands
```

✅ *Summary*

Task-level navigation means:

```
User request
     ↓
AI generates workflow
     ↓
System executes multiple actions
     ↓
Pages open automatically
```

This lets users operate complex apps *without knowing the menu structure*.

If you'd like, I can also show you a *very practical blueprint for implementing this in an existing web app (React/Vue/etc.) with about ~300 lines of backend code*. It’s surprisingly simple and many teams underestimate how easy it is.

= FreePik

#let a_005 = link(
  "https://www.freepik.com/pikaso/spaces/a14a694e-a841-49b5-b3f8-a369ebd8031d"
)[#text(fill: blue)[URL]]

#a_005

This is a drag-and-drop editor that lets users create workflows.

= Page Agent

#let a_006 = link(
  "https://github.com/alibaba/page-agent"
)[#text(fill: blue)[GitHub]]

#a_006

Alibaba open-sourced this project.

= UI Skill

#let a_006 = link(
  "https://github.com/zkoss-demo/agent-skill/blob/main/skills/zul-writer/SKILL.md"
)[#text(fill: blue)[Zul-Writer Skill]]

#let a_007 = link(
  "https://www.zkoss.org/"
)[#text(fill: blue)[ZK]]

#a_006 \
#a_007 \
Source: dzone

This skill is specially for #a_007 (a Java GUI framework). We can't use it directly. But we can use its SKILL.md.

ZK has 200+ reusable components so developers can focus on business logic, the same thinking behind DeepDoc.

= Optimize Content for Agents

#let a_008 = link(
  "https://cra.mr/optimizing-content-for-agents/"
)[#text(fill: blue)[Optimize Content for Agents]]

Date: 2026/03/14 \
#a_008 \
Source: Hacker News

#quote(block: true, attribution:[#a_008])[
"Frontier models and the agents built on top of them all behave similarly, with similar constraints and optimizations. For example, one thing they’re known to do, to avoid context bloat, is to only read parts of files. The first N lines, or bytes, or characters. They’re also known to behave very differently when they’re told information exists somewhere vs. having to discover it on their own. Both of those concerns are actually why LLMs.txt was a valuable idea, but it was the wrong implementation."
]

= Thoughts - DocMap

Date: 2026/03/14

This is triggered by web page Site Map. A DocMap is a guide for agents about a doc (which can be articles, books,
web pages, videos, audios, code, etc.). 

It follows the 'Incremental Exposure' principle. Agents reads:
- A brief summary 
- DocMap
- Selected Content
- Entire Doc

DocMap, normally named DOCMAP.md, normally contains the following information. Refer
to ChenWeb/Documents/DOCMAP.md for a reference template.

== Predictable Sections

Agents can easily parse:

- Metadata
- Scope
- Structure
- Index
- Concepts
- Tasks

== Explicit Paths

Avoids ambiguous references.

Good:

```text
docs/api/api-reference.md
```

Bad:

```text
API documentation
```

== Concept Layer

This greatly improves semantic search and reasoning.

Example:

```text
Standard -> contains -> Requirement
```


This helps agents understand relationships.

== Task Navigation

Agents can follow workflow instructions instead of scanning everything.


= The Enterprise Context Layer

#let a_009 = link(
  "https://andychen32.substack.com/p/the-enterprise-context-layer"
)[#text(fill: blue)[Article]]

#a_009 \
Date: 2026/03/15

*Enterprise Context Layer*: the central intelligentce that encompasses all knowledge for your company,
is able to answer any questions, and *self-updates*.

== Search

Below is the prompt the author uses:
```text
You are an Enterprise Context Layer (ECL) Agent that builds and maintains internal mental models, the reasoning frameworks our experts use, not just raw facts.

It serves to document everything related to our product/people/process/etc.

Some (non exhaustive by any means) dimensions of understading:

- How our product works

- How to communicate things to customers

- Organization behavior/politics

- etc

This enterprise context layer needs to be a truthful reflection of how our product/people/process works. It should contain the good, bad, and ugly.

the ECL is not built for readability. It’s built for traceability and verifiability

Every claim, every statement, soft or hard, has to have an inline citation for the source(s) that it directly draws from.
```

== Storage

It stores files in GitHub (or Git). Any environment can either checkout the Git or
access files directly from GitHub.

The author used the above prompt, plus some instructions about how to use tools and
a simple file-based task system inspired by Anthropic C Compiler.

== What ECL Stores

#quote(block: true, attribution: [#a_009])[
  The entire customer journey: from first sales contact through deployment, onboarding, renewal, and churn, mapped end-to-end with handoff points between teams, common failure modes at each stage, and the exact playbooks for each scenario. Cross-referenced against real support cases and Gong calls.
]

#quote(block: true, attribution: [#a_009])[
  A detection model lifecycle document that maps all distinct causes of detection behavior change to customer-visible impact, with triage frameworks, source code references, Databricks dashboard links, and real incident case studies. It bridges engineering, support, and customer success into one coherent mental model that previously only lived in a few engineers’ heads.
]

== Self-Evolving

#quote(block: true, attribution: [#a_009])[
  "As you run these agents more and more the context layer will only get richer and richer, with more backlinks, cross-references, and inter-departmental mental models."
]

== TODO

Need to continue reading. This is very important.

= Anthropic C Compiler

#let a_010 = link(
  "https://www.anthropic.com/engineering/building-c-compiler"
)[#text(fill: blue)[Article]]

#a_010 \
Date: 2026/03/15

Anthropic uses 16 agents with writing a Rust-Based C compiler, from scratch, using Agent Teams.
With agent teams, multiple Claude instances work in parallel on a shared codebase without 
active human intervention. Over nearly 2,000 Claude Code sessions and \$20,000 in API costs,
the agent team produced a 100,000 line compiler.

== Enable Long-Running Claudes

There is no human intervention. In the agent prompt, it tells Claude what problem to solve and ask it
to approach the problem by breaking it into small pieces, tracking what it is working on,
figuring out what to work on next, and to effectively keep going until it's perfect.

== Running Claude in Parallel

A new bare git repo is created, and for each agent, a Docker container is spun up with the repo
mounted to /upstream. Each agent clones a local copy to /workspace, and then it is done,
pushes from its own local container to upstream.

#quote(block: true, attribution: [#a_010])[
To prevent two agents from trying to solve the same problem at the same time, the harness uses a simple synchronization algorithm:

1. Claude takes a "lock" on a task by writing a text file to current_tasks/ (e.g., one agent might lock current_tasks/parse_if_statement.txt, while another locks current_tasks/codegen_function_definition.txt). If two agents try to claim the same task, git's synchronization forces the second agent to pick a different one.
2. Claude works on the task, then pulls from upstream, merges changes from other agents, pushes its changes, and removes the lock. Merge conflicts are frequent, but Claude is smart enough to figure that out.
3. The infinite agent-generation-loop spawns a new Claude Code session in a fresh container, and the cycle repeats.
]

Comments: As we can see, GitHub becomes more and more important. The main reason: Everything Text.
This is the reason why LLMs turn their attention to files, instead of databases, because files are
universal and LLMs are particularly trained well on files. Databases are powerful but vendor dependent,
or not universal. More importantly, LLM training datasets contain very little database data because
they are not 'text', they are format sensitive, vendor dependent, hard to 'understand'.

When multiple agents are involved, when you want to keep track of the changes, versions, etc., when
there are multiple instances that need to share the same set of data (that is, data needs to be
centrally managed), people naturally turn to GitHub. We can use either GitHub.com or self hosted
GitHub.

It is very difficult to replicate and sync data between databases, but it is much easier to 
centrally store, manage and synchronize data through Git.

== The Grand Loop

#quote(block: true, attribution:[#a_010])[
  The scaffolding runs Claude in a loop, but that loop is only useful if Claude can tell how to make progress. Most of my effort went into designing the environment around Claude—the tests, the environment, the feedback—so that it could orient itself without me. These are the approaches I’ve found most helpful when orchestrating multiple Claude instances.
]

== Write Extremely High-Quality Tests

#quote(block: true, attribution: [#a_010])[
  Claude will work autonomously to solve whatever problem I give it. So it’s important that the task verifier is nearly perfect, otherwise Claude will solve the wrong problem. Improving the testing harness required finding high-quality compiler test suites, writing verifiers and build scripts for open-source software packages, and watching for mistakes Claude was making, then designing new tests as I identified those failure modes.
]

= Postgres for Agents

#let a_011 = link(
  "https://db9.ai/"
)[#text(fill: blue)[Article]]

#a_011 \
Date: 2026/03/14

The idea is make Posgres for agents. The database is serverless. Agents access the database through CLI.

== My Thoughts

I am not sure whether it is a good idea to introduce a database to agents (i.e., LLMs). 
If LLMs use databases, they must know how to query, mostly through SQL. Different databases
use different dialects of SQL. LLMs may be good enough at PostgreSQL syntax. But things can
change.

Files, on the other hand, are very mature, extremely mature, have been with us for decades.
It is safe to say that files will remain the same 'files' in the next 10 years (very stable).

The syntax of files or CLI commands is also quite simple, comparing with SQL.

My understanding, or my approach is:
- Use files
- Stay away from databases
- Use file tree to organize files
- Each directory has an AGENT.md that explains what the directory contains.
- Use semantic search with care. A well structured file tree + AGENT.md require much less semantic search.
- Keep a directory small enough (around 100 files/sub-directories). When a directory becomes too big, use LLMs to break it and add AGENT.md for each newly created sub-directory and update the original one.
- Keep the files in a GitHub repo
- Commit often
- Sync often
- Use a background cron job to monitor the file tree

= 2026/03/20 - Flash-Means

#let a_012 = link(
  "https://arxiv.org/pdf/2603.09229"
)[#text(fill: blue)[Article]]

#let a_013 = link(
  "https://github.com/svg-project/flash-kmeans"
)[#text(fill: blue)[GitHub]]

#a_012 \
#a_013 \
Source: Hacker News

k-means has historically been positioned primarily as an offline processing primitive, 
typically used for dataset organization or embedding preprocessing rather than as a 
first-class component in online systems. In this work, we revisit this classical algorithm 
under the lens of modern AI system design and enable k-means as an online primitive. 
We point out that existing GPU implementations of k-means remain fundamentally bottlenecked 
by low-level system constraints rather than theoretical algorithmic complexity. 
Specifically, the assignment stage suffers from a severe IO bottleneck due
to the massive explicit materialization of the N × K distance matrix in High Bandwidth Memory
(HBM). Simultaneously, the centroid update stage is heavily penalized by hardware-level atomic write
contention caused by irregular, scatter-style token aggregations. To bridge this performance gap, we
propose flash-kmeans, an IO-aware and contention-free k-means implementation for modern GPU
workloads. Flash-kmeans introduces two core kernel-level innovations: (1) FlashAssign, which fuses
distance computation with an online argmin to completely bypass intermediate memory materialization;
(2) sort-inverse update, which explicitly constructs an inverse mapping to transform high-contention
atomic scatters into high-bandwidth, segment-level localized reductions. Furthermore, we integrate
algorithm-system co-designs, including chunked stream overlap and cache-aware compile heuristic,
to ensure practical deployability. Extensive evaluations on NVIDIA H200 GPUs demonstrate that
flash-kmeans achieves up to 17.9× end-to-end speedup over best baselines, while outperforming
industry-standard libraries like cuML and FAISS by 33× and over 200×, respectively. At the kernel
level, FlashAssign and Sort-Inverse Update deliver up to 21.2× and 6.3× speedups. Beyond raw
compute, our pipelined co-design enables seamless out-of-core execution on up to one billion points
with a 10.5× speedup, and our heuristics slash configuration tuning overhead by 175× with near-zero
performance degradation. By systematically restructuring execution around underlying hardware
constraints, flash-kmeans delivers mathematically exact, scalable, and highly deployable acceleration
across diverse AI workloads.

= 2026/03/20 - Categories (CatDat)

#let a_013 = link(
  "https://catdat.app/"
)[#text(fill: blue)[WebSite]]

#let a_014 = link(
  "https://en.wikipedia.org/wiki/Category_theory"
)[#text(fill: blue)[Category Theory]]

#a_013 \
#a_014 \
Source: Hacker News

This is a database (open-source) of categories based on the #a_014

We can do a similar thing.

== Entities

An entity is similar to a category in #a_013. 
- Brief Description
- Detailed Description
- Keywords
- Embedding (for semantic search)
- Attributes
- Relations to other entities
- File References: a list of file names where the original context is stored
- Docids: a list of docids for the records where the original context is stored

= Note Attributes

- Brief Description
- Detailed Description
- Keywords
- Embedding (for semantic search)
- List of nodes that have this attribute

= Relation Attributes

- Brief Description
- Detailed Description
- Keywords
- Embedding (for semantic search)
- List of relations that have this attribute

