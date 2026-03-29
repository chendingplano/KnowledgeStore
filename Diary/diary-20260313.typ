#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

= List of Figures
#outline(
  title: [],
  target: figure.where(kind: image),
)
#pagebreak()

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

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

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

So the entire *evaluation system* boils down to:

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

== Note Attributes

- Brief Description
- Detailed Description
- Keywords
- Embedding (for semantic search)
- List of nodes that have this attribute

== Relation Attributes

- Brief Description
- Detailed Description
- Keywords
- Embedding (for semantic search)
- List of relations that have this attribute

= 2026/03/21 - RAG Guardrails

#let a_015 = link(
  "https://dzone.com/articles/rag-guardrails-for-enterprise-llm-deployments"
)[#text(fill: blue)[Article]]

#a_015 \
Source: dzone

== Force LLMs to Show the Work
```python
SYSTEM_PROMPT = """Answer using ONLY the provided context documents.

Rules:
1. Every factual claim MUST cite its source as [Doc X].
2. If the context doesn't contain the answer, say so. Don't guess.
3. If documents contradict each other, state both with their citations.
4. Do not add information beyond what's in the documents.

Context Documents:
{context}

Question: {query}
"""
```

It is important to validate the citations.
```python
import re

def validate_citations(response, num_docs):
    citations = re.findall(r'\[Doc\s+(\d+)\]', response)

    bad_refs = [c for c in citations if int(c) < 1 or int(c) > num_docs]

    # find sentences that make factual claims but cite nothing
    sentences = [s.strip() for s in re.split(r'[.!?]', response) if s.strip()]
    uncited = []
    for sent in sentences:
        skip_phrases = ["i don't have", "based on the", "according to", "the context"]
        if any(p in sent.lower() for p in skip_phrases):
            continue
        if not re.search(r'\[Doc\s+\d+\]', sent) and len(sent.split()) > 5:
            uncited.append(sent)

    return {
        "valid": len(bad_refs) == 0 and len(uncited) == 0,
        "bad_refs": bad_refs,
        "uncited_claims": uncited
    }
```

== Cross-LLM Check

Sometimes, it may still make mistakes: the meaning of the cited content is different from the cited chunks. We can ask a smaller model: Does the source actually support this claim?

```python
def verify_consistency(claims, sources, threshold=0.5):
    from transformers import pipeline
    nli = pipeline("text-classification", model="cross-encoder/nli-deberta-v3-base")

    problems = []
    for claim, source in zip(claims, sources):
        result = nli(f"{source} [SEP] {claim}")
        if result[0]["label"] == "CONTRADICTION" and result[0]["score"] > threshold:
            problems.append({
                "claim": claim,
                "source": source,
                "confidence": result[0]["score"]
            })

    return problems
```

"This is the most expensive guardrail. DeBERTa inference adds 300-500ms per response, depending on how many claim-source pairs you’re checking. For our latency-sensitive paths, I run it async. The user gets the response immediately, and if the NLI check flags a contradiction, a correction fires within a few seconds. For compliance-critical paths (anything touching payroll calculations, tax rates, regulatory guidance), it runs synchronously. The extra half-second is worth it."

== Stale Documents Are the Killers

Some documents are constantly updated. When a document is updated, all the chunks need to
be updated instantly.

I don't quite understand what the author said. Any time when a document is updated, we need
to update the chunks immediately. 

== Teach the System to Say "I'm nNot Sure"

```python
def score_confidence(relevance_scores, citation_check, nli_flags, stale_chunks, total_chunks):
    avg_relevance = sum(relevance_scores) / len(relevance_scores) if relevance_scores else 0
    cite_score = 1.0 if citation_check["valid"] else max(0, 1 - len(citation_check["uncited_claims"]) * 0.2)
    consistency = max(0, 1.0 - len(nli_flags) * 0.3)
    freshness = 1.0 - (len(stale_chunks) / total_chunks) if total_chunks else 0

    score = 0.30 * avg_relevance + 0.25 * cite_score + 0.25 * consistency + 0.20 * freshness

    if score >= 0.85:
        return {"confidence": score, "action": "serve"}
    elif score >= 0.60:
        return {"confidence": score, "action": "serve_with_disclaimer"}
    else:
        return {"confidence": score, "action": "abstain"}
```
It uses multiple scores to calculate the final scores:
- relevance score
- citation score
- consistency score
- freshness score

= 2026/03/21 - Run Qwen 3.5 on Local Machines

#let a_016 = link(
  "https://www.sharpai.org/benchmark/"
)[#text(fill: blue)[Article]]

#a_016 \
Source: Hacker News

Machine: MacPro with 64GB unified memory, M5 chip.

#figure(
   image("Images/image_2026032101.png", width: 100%),
   caption: [Benchmark 01 (#a_016)],
)

#figure(
   image("Images/image_2026032102.png", width: 100%),
   caption: [Benchmark 02 (#a_016)],
)

= 2026/03/21 - HydraDB

#let a_017 = link(
  "https://docs.hydradb.com/"
)[#text(fill: blue)[Article]]

#a_017 \
Source: Tou Tiao

*Problems*
#quote(block: true, attribution:[#a_017])[
"Pure vector search has repeatedly failed to provide reliable enterprise-grade context on
its own. Research from Google DeepMind and Stanford shows that embedding-only retrival systems
often surface irrelevant, outdated, or misleading information, especially in complex 
knowledge workflwos.
]

== Memory

"In HydraDB, memories are structured units of contextual information that help your AI system"
- Remember user preferences and past interactions
- Provide personalized, context-aware responses
- Adapt behavior over time
- Improve relevance and accuracy across worksflows

Memories are continuously updated, enriched, re-ranked and reused.
All memories are dynamic, adaptive, and selv-evolving.

== Types of Memories

=== User Memories

It is personal, user-specific context.
- Preferences ("prefers concise answers")
- Behavior ("often asks technical questions")
- History ("previously worked on Project xyz")

=== Knowledge Memories

The is the major part of the database:
- Slack threads
- Emails
- Diary
- Notion pages

=== Documents
- Word, PDF, Excep, PPT, ...
- ...

=== Organization Memories

Tenant-level memory shared across all agents. Organization memories are adaptive, self-evolving
and dynamic. Users can add anything to organization memories.

- Team roles
- Internal workflows
- Policies and playbooks
- Security rules
- ...

=== Derived Memories

Most of the derived memories are generated by LLMs.

=== Reports

They are normally generated by LLMs. Users may manually contribute, too.
Reports are normally generated periodically, such as daily, weekly, monthly, etc.

- Reports on personal activities
- Reports on knowledgebase
- Reports on ETL
- Reports on customer activities
- Reports on customer services
- ...

=== Bugs

It is a database of bugs. Bugs may be manually created or automatically derived by LLMs.

=== Questions

This is a database of the questions users, which can be individual users or users in
a team, in an organization unit, in an organization, or in the public.

=== Standards

The standards that are used in an environment.

=== Formulas

This is a repository of formulas used in an environment.

== Not Just VectorDB

HydraDB is more a memory system than a vector database:
- Content Graphs instead of chunks
- Understand the intent of queries
- Consider user, tenant, and agent context (how?)
- Traverse the graph to understand the relationships, linkages, and historical outcomes
- Weighs recency, relevance, frequency, and semantic similarity
- Rank memories based on how useful they are for the current task

One thing HydraDB and I in common: traditional vector databases are flat.
HydraDB treats memory like living context graph. But in my mind, memory and knowledge
are two different things.

Knowledge should not be flat. First of all, they should be hierarchical: higher levels
are abstract and lower levels reveal details.

It is, however, not pure hierarchical. Any node can connect to other nodes. They are
essentially graphs. But don't forget that they are hierarchical first. We can call
this type of graph *Hierarchical Graphs*.

== File-Based Semantic Hierarchical Graph (SHG)

One of the problems with vector databases is that we put all vectors into the same collection.
This can easily mix unrelated but semantically close chunks together.

One solution is to create an SHG. Leaves in an SHG are collections.
If we have a chunk that discusses how penicillin was invented:
- Level 1: Medicine
- Level 2: History
- Level 3: Antibiotics
- Level 4: Penicillin (leaf)

If Level 4 does not exist, it can find entries in Level 3: Antibiotics. It may not find penicillin
but may find similar antibiotics.

== Metadata: Structuring Memory for Deterministric Retrieval

This is similar to the vision of File-Based Hiearchical Graph.

== Retrieval

Retrieval is the most important part of a knowledge system.
- by metadata
- by keywords (BM25)
- by vector (semantics)

In addition, these are what I want to have:
- by SHG
- by freshness
- by intent
- by topics
- ???

"retrieval shouldn't be vector search first. Recall should be intelligent,
personalized, and context-aware, not just semantic search over embeddings."

*Comments* 'retrieval shouldn't be vector search first.' I agree with this.
Not only that, vectors should be organized. There should be multiple small, topic-based
collections instead of one huge collection.

The challenges are 'intelligent, personalized, and context-aware'

This is how HydraDB retrieves:
```text
   1. Understands the intent of the query
   2. Considers the user, tenant, and agent context
   3. Traverses the memory graph to understand relationships and outcomes
   4. Weighs recency, relevance, frequency, and semantic similarity
   5. Ranks memories based on how useful they are for the current task
```

=== Customize Your Retrievals

- recency_bias: prefer newer memories
- search_alpha: balance semantic vs lexical
- custom scoring functions
- metadata constraints
- BM25 (mine)
- BM25 + Vector reranking weights
- Model-based reranking: configure the model name

*Thought* When design retrievals, it is very important not be too 'smart'. 
The smartness (or intelligence) should not be in the database (at least should not be too much).
LLMs are much better at being smart. A retrieval system should focus on providing tools, 
and, more importantly, present the data (or information) for LLMs, and then for human users.

For instance, the goals of HydraDB are 'intelligent, personalized, and context-aware'.
These can be easily achieved by LLMs, not HydraDB or any databases in general.
Given a query and the context, which includes what data we have and how they can be explored,
LLMs will be much better than any databases in finding the niddle in the hey.

What we need is a tool: SHG + search(...). The SHG is stored in files.
Initially, it loads the first N levels (limited by size, such as 1000 bytes)
of the tree. LLMs will use the tool `search(...)`, just like `ls`, to retrieve lower-level
nodes until the leaves are hit. LLMs can then use `search(...)` to retrieve all the chunks.

=== Collections

*Multiplicity* One vector may be in multiple collections. Duplicate storage does use
more space. But it can improve retrievals.


=== Adaptive and Personalized retrieval

Over time, the system leans which memories are actually helpful for a given user or workflow.
This enables:
- *Personalized Ranking*: two users asking the same question may get different context.
  I am not sure whether this is important or how important it is.
- *Implicit feedback loops*: memories that are frequently used, referenced, or lead to
  successful outcomes are prioritized. This is important. The system should automatically 
  detect it. Users may or may not tell us about whether a reference is useful. 
  Implicit feedback requires the system is smart enough.

= 2026/03/22 - Grafeo

#let a_018 = link(
  "https://github.com/GrafeoDB/grafeo"
)[#text(fill: blue)[Article]]

#a_018 \
Source: Hacker News

This is a new open-source graph database in Rust. It is kind of too new now. 
It does have Go binding. We may want to use it in the future.

= 2026/03/22 - TIGERFS

#let a_019 = link(
  "https://tigerfs.io/"
)[#text(fill: blue)[Article]]

#a_019 \
Source: Hacker News

Tigerfs is a file system backed by PostgreSQL and a file system interface to PostgreSQL.
It mounts a database as a directory. Every file is a real row. Writes are transactions.
Multiple agents and humans can read and write concurrently with full ACID guarantees,
locally or across machines. Any tool that works with files works out of the box.

#table(
  columns: 2,
  align: left,
  [System], [Explanation],
  [Local Files], [ACID transactions and version history, instead of bare files with no coordination guarantees.],
  [GIT], [Changes are visible immediately, with automatic version history. You don't need to pull, push, or merge.],
  [S3], [Structured rows and ACID transactions, not blobs. You can query the data, not just retrieve it.],
  [Database], [ Your agents already know how to work with files. You don't need client libraries or schemas to pass around.]
)

A good thing about Tigerfs is that you can mount an existing PostgreSQL database.

#figure(
   image("Images/image_2026032201.png", width: 100%),
   caption: [Benchmark 02 (#a_019)],
)

== Shared Agent Workspace

Multiple agents operate on the same knowledge base at the same time. 
Every edit is versioned, so if one agent overrites another's work,
you can recover it from .history/

```text
# agent A writes research findings
cat > /mnt/db/kb/auth-analysis.md << 'EOF'
---
author: agent-a
---
OAuth 2.0 is the recommended approach...
EOF

# agent B reads immediately. no sync. no pull.
cat /mnt/db/kb/auth-analysis.md
```

== Multi-Agent Task Queue

todo/, doing/, and done/ are your three directories, and mv is your only API. 
Moves are atomic database operations, so two agents can't claim the same task.

```text
# agent claims a task atomically
mv /mnt/db/tasks/todo/fix-auth-bug.md \
   /mnt/db/tasks/doing/fix-auth-bug.md

# see what everyone is working on
ls /mnt/db/tasks/doing/
grep "author:" /mnt/db/tasks/doing/*.md
```

== Collaborative Docs

A human drafts, an agent edits, another summarizes, all in the same directory,
all visible immediately. History hows who changed what and when.

```text
# browse the full edit trail
ls /mnt/db/docs/.history/proposal.md/

# see what changed in the last edit
diff /mnt/db/docs/.history/proposal.md/2026-02-25T100000Z \
     /mnt/db/docs/proposal.md
```

== Quick Data Fixes

Update a customer's email, toggle a feature flag, delete a test record.
One shell command instead of opening a SQL client, remembering the schema,
and writing a WHERE clause.

```text
# update a single column
echo 'new@example.com' > /mnt/db/users/123/email.txt

# update a full row via JSON
echo '{"email":"a@b.com","name":"A"}' > /mnt/db/users/123.json

# delete a record
rm -r /mnt/db/users/456/

# bulk-load from CSV
cat data.csv > /mnt/db/orders/.import/.append/csv
```

== Data Analytics

Stnadard Unix tools work on every table. For larger queries,
chain filters and pagination into a single path to push the work into the database.

```text
# find shipped orders
grep "shipped" /mnt/db/orders/*/status.txt

# select specific columns via pipeline
cat /mnt/db/orders/.filter/status/shipped\
    /.columns/id,total,created_at/.export/csv

# sum shipped order totals
cat /mnt/db/orders/.filter/status/shipped\
    /.columns/total/.export/csv | awk '{s+=$1} END {print s}'
```

= 2026/03/22 - Ralph and Cook

#let a_020 = link(
  "https://github.com/snarktank/ralph"
)[#text(fill: blue)[Cook]]

#let a_021 = link(
  "https://github.com/rjcorwin/cook"
)[#text(fill: blue)[Cook]]

#a_020 \
#a_021 \
Source: Tou Tiao

Ralph is an autonomous AI agent loo that runs AI coding tools (such as Claude Code)
repeatly until all PRD items are complete. Each iteration is a fresh instance with
clearn context. Memory persists via git history.

Cook is a simple CLI for orchestrating Claude Code, Codex, and OpenCode. 
It runs agents (licke Claude Code, Codex) in an automated "work → review → gate" loop
until the task is done. It is basically an agent orchestrator for coding tasks.
Instead of you prompt an AI once → get an answer → iterate manually, Cook does:
- run the agent
- review its output
- decide whether to continue
- repeat automatically

= 2026/03/22 - Flash-KMeans

#let a_022 = link(
  "https://github.com/svg-project/flash-kmeans"
)[#text(fill: blue)[GitHub]]

#a_022 \
Source: Hacker News

KMeans is an important algorithm in AI. Flash KMeans can do it much faster.

We can come back to this project when we want a faster KMeans.

= 2026/03/22 - Jarvis

#let a_023 = link(
  "https://scalingintelligence.stanford.edu/blogs/openjarvis/"
)[#text(fill: blue)[Article]]

#let a_024 = link(
  "https://github.com/open-jarvis/OpenJarvis"
)[#text(fill: blue)[GitHub]]

#a_023 \
#a_024 \
Source: Google

This is a Personal AI project. It runs LLMs locally. Keep data locally. Runs AI locally.

= 2026/03/22 - GStack

#let a_025 = link(
  "https://github.com/garrytan/gstack?ref=producthunt"
)[#text(fill: blue)[GitHub]]

#a_025 \
Source: Google

GStack is an open-source "Skill Pack" for Claude Code that turns one AI assistant into
a team of specialized roles (CEO, Engineer, QA, etc.) to auto mate software development workflows.

The core idea is "structure AI like a real engineering organization":
- A CEO
- An Engineering Manager
- A QA Engineer
- A Release Engineer

All implemented as predefined "skills" (slash commands). It is basically:
- A set of custom commands (skills) for Claude Code
- Each command = a role + workflow pattern
- Installed into your local dev environment or repo

== Workflows

A typical workflow:
1. /plan-ceo-review → rethink problem
2. /plan-eng-review → design solution
3. (Claude builds feature)
4. /review → find issues
5. /browse → test UI
6. /ship → deploy

= 2026/03/22 - Harness Engineering

#let a_026 = link(
  "https://openai.com/index/harness-engineering/"
)[#text(fill: blue)[OpenAI]]

#let a_027 = link(
  "https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html"
)[#text(fill: blue)[Birgitta Bockeler]]

#a_026 \
Source: Hacker News

This is an article from OpenAI. *Harness Engineering* is a new concept.

= 2026/03/23 - TUI Studio

#let a_027 = link(
  "https://tui.studio/"
)[#text(fill: blue)[WebSite]]

#a_027 \
Source: Hacker News

One can build a TUI by its TUI Studio and then generate code to 6 frameworks.

Reference only. Study it more when need it.

= 2026/03/23 - Optimizing Content for Agents

#let a_028 = link(
  "https://cra.mr/optimizing-content-for-agents/"
)[#text(fill: blue)[Article]]

Keywords: Agent, Content \
#a_028 \
Source: Hacker News

== Core Ideas

"You should be optimizing content for agents, just as you optimize things for people.
How you do that is an ever-evolving subject, but there are some common things we see:
- Order of content
- Content size
- Depth of nodes"

LLMs behave very differently when they are told information exists somewhere vs.
having to discover it on their own.

= 2026/03/23 - LLMs.txt

Source: ChatGPT

LLMs.txt is a proposed standard file (usually at /llms.txt) that gives LLMs a clean,
structured summary of a website. It is typically a markdown file, placed at the root
of a site (e.g., https://example.com/llms.txt). It contains a short description of the site,
key links (docs, APIs, guides, etc.) and optional structure/usage hints.

LLMs.txt is similar to robots.txt (tells crawlers what NOT to access), sitemap.xml
(lists of all pages).

*Example*
```text
# My Product Docs

> Official documentation for developers

## Guides
- Getting Started: https://example.com/docs/start
- Installation: https://example.com/docs/install

## API
- Reference: https://example.com/docs/api
```

== Docs

The primary optimizations:

1. Serve true markdown content - massive tokenization savings as well as improved accuracy
2. Strip out things that only make sense in the context of the browser, especially navigation and JavaScript bits
3. Optimize various pages to focus more on link hierarchy - our index, for example, is mostly a sitemap, completely different than non-markdown

== Facts about Typst

(from ChatGPT) Typst is relatively new (about 2023). It is still niche compared to markdown,
HTML, LaTex, etc. LLMs have no problems in understanding Typst syntax but it is less robust,
more likely to hallucinate.

== Do LLMs Have Format Preferences

Yes - very strong ones, in a statistical + structural efficiency sense.

*Tier 1 - Best for LLMs*

- Markdown
- Plain text (well-structured)

*Tier 2 - Very strong (structured)*
- JSON
- YAML

*Tier 3 - Good but Noisy*

- HTML
- XML

*Tier 4 - Specialized*

- LaTex
- Typst

*Tier 5 - Bad for LLMs*

- PDF
- Word
- PPT

= 2026/03/23 - PageIndex

#let a_029 = link(
  "https://github.com/VectifyAI/PageIndex"
)[#text(fill: blue)[GitHub]]

#let a_030 = link(
  "https://pageindex.ai/blog/pageindex-intro"
)[#text(fill: blue)[Article]]

#a_029 \
#a_030 \
Source: WeChat

== Core Ideas

It builds a `Tabel-of-Contents` tree structured index of documents. Retrieval
is done by reasoning, or traverse through the tree.

#figure(
   image("Images/image_2026032301.png", width: 100%),
   caption: [PageIndex (#a_029)],
)

== Overcoming the Limitations

=== Query - Knowledge Space Mismatch

LLMs uses reasoning to infer which section is likely to contain the answer.
It can think about document structure.

=== Semantic Similarity ≠ True Relevance

Reasoning-based retrieval emphsizes contextual relevance, not just similarity.
LLMs read Table of Contents (or Semantic Hierarchical Graph), interprets the query's intent,
and navigates to sections that actually contain the answer, even if their
language is different.

=== Semantic Mismatch ≠ Not Relevant

This is even more important than "Semantic Similarity ≠ True Relevance". 
For instance, for the content:

```text
Table 5.3 summarizes the income, expenses, and distributions of the Reserve Banks for 2023 and 2022. Appendix G of this report, ‘Statistical Tables,’ provides more detailed information…
```

the chance to be retrieved by the query "Total value of deferred asserts" is low because
the semantic similarity will be very low.

The reasoning-based retriever can traverse the semantic tree, find the correct table,
and returns the total deferred asset value
=== Hard Chunking Breaks Semantic Integrity

There is still chunking, but more by document structures. 
Reasoning-based RAG retrieves semantically coherent sections (e.g., full pages, sections,
or chapters). If the model detects that a section is incomplete, it iteratively fetches
neighboring sections until context is sufficient.

=== Inability to Integrate Chat History

Retrieval is context-aware: LLms use prior conversation history to refine its understanding
of the current question (this is very important). For instance, if the user previously
asked about "financial assets", and now asks, "What about liabilities?", LLMs know
the question is about the reliabilities of financial asserts. Not only that,
it should look for reliabilities from the same document. It is up to LLMs to determine
whether to retrieve other relevant information. This is called *Context-Aware Retrieval*.

=== Poor Handling of In-Document References

It is much easier to read the cross-references in the same document. Reasoning-based
retrieval can follow references like a human reader. When it encounters a phrase
like "see Appendix G", LLMs navigates the index tree to that section and retrieves
the relevant data.

= 2026/03/26 - Google Memory Compression Algorithm PolarQant

#let a_031 = link(
  "https://research.google/blog/turboquant-redefining-ai-efficiency-with-extreme-compression/"
)[#text(fill: blue)[PolarQuant]]

#a_031 \
Source: TechCrunch

It is just announced. We need to wait until it settles down. But it looks promising.

= 2026/03/26 - Tokens and Transactions with AI

#let a_032 = link(
  "https://dzone.com/articles/tokens-and-transactions-with-ai"
)[#text(fill: blue)[Article]]

#a_032 \
Source: dzone

#quote(block: true, attribution:[#a_032])[
For a database audience, the keynote underscores a fundamental shift: Data is no longer just stored and queried — it is continuously activated to power agentic systems. The talk highlights that the center of gravity is moving from traditional transactional and analytical databases toward AI-driven data platforms that unify structured, unstructured, and real-time data streams into a single operational fabric. Massive growth in AI infrastructure — driven by data center expansion and trillion-dollar-scale compute demand — signals that data systems must scale not just for queries, but for continuous inference and agent workflows. 

A key theme is the rise of “agentic architectures,” where data is embedded, indexed, and retrieved dynamically to support reasoning systems, making vector search, hybrid retrieval, and multimodal indexing first-class primitives. The keynote also implicitly reframes databases as part of an end-to-end AI stack — tightly coupled with compute, models, and orchestration layers — rather than standalone systems. This creates pressure on databases to evolve toward low-latency, context-aware, and semantically rich data access patterns.
]

The most *important* take away from it:
#quote(block: true, attribution:[#a_032])[
  Finally, the emerging paradigm suggests that competitive advantage will hinge on how effectively platforms can turn raw data into actionable intelligence for autonomous agents, blending transactions, analytics, and AI into a unified system of execution.
]

From database evolvution point of view, databases "have to go beyond their roots and handle unstructured data - pure text,
PDFs, images, and more. Time for databases to be reinvented. Again!"

== Single Operational Fabric

What is the `single operational fabric`? Is it still a database, or a legacy database (such as relational databases,
graph databases, document-based databases, etc.)? A database that stores data in a propriatory format that no LLMs 
can understand without additional helping mechanisms?

In the era of AI, things should be designed not just for humans but for AI (or Agents). For databases, most legacy 
databases require special way to access and manipulate, such as SQL for relational databases, JSON (ElasticSearch,
MongoDB, etc.), Cypher (Neo4j), etc. They are not for agents.

To turn them into a format that agents can understand and, more importantly, explore, an easy and straightforward way
is to use plain text files. Legacy databases may still be needed and critical, but this file-based `single operational fabric`
is equally important.

I would imagine that there will be two `parallel` data stores: levacy database systems and file-based plain data store.
The former is for the legacy apps and systems and the latter for agents and future agantic apps/systems.

== Structured, Unstructured, Real-Time Data

The file-based plain data store can easily combine structured, unstructured and real-time data into a uniform
store. Note that in agents, there are no structured or unstructured. The only that that matters for agents is
`understandability`. Agents (i.e., LLMs) are good at understanding natural languages (unstructured). Structured
data need to be enriched with semantics. For instance, row-based relational databases can only be operated 
through SQL but column-based relational databases can be stored in plain files.

== Databases or Files

The most critical question is: Shall we keep on using databases or we should consider files, too?
Databases provide very important and useful data management functions and features, such as ACID,
indices, scalability, reliability, etc. These are important not only to legacy apps but to agents, too.

If this is the case, why we want to use files?

== Token vs Transaction Computing

"Enterprise computing has long been built around transactions - Boolean algegra over ACID. In other words,
deterministic units of work are executed over structure data. Recent advances in AI, however,
introducte a complementary unit of computation: tokens. *Tokens represent language, context, and reasoning*,
enabling systems to interpret unstructured data and perform multi-step inference."

== System of Records vs System of Cognition

Enterprise systems have historically been defined by transactions and analytics (via data warehouses).
A transaction encapsulates a unit of business logic. Analytical databases are optimized for analyzing large
volumes of data to discover business insights.

*Tokens* are the atomic units of language models. They represent fragments of meaning.

Three critical components of token computing:
- Information
- Context
- Reasoning

SQL never considers 'context'. This is not a problem because this is exactly what it is designed for.
There is no 'semantics' in SQL, nor needed. SQL is syntactical, deterministic, and structural. 
It should be used when LLMs know exactly what they need and how a database is defined and constructed.
When LLMs are not sure exactly how to retrieve/find relevant information (or LLMs need to explore instead
of querying), especially when LLMs are not sure exactly whether and how the information they are looking
for is stored in databases, a less strict data store that is intentially designed to `explore` instead of
`query` can be critical.

File-based stores are better suited for exploration, while databases are optimized for precise querying.
Files are not "designed" for exploration - they are unconstrained enough to allow it.

SQL, on the other hand, is syntactical, deterministic and structural. It has no semantics. SQL is best
suited when you (or LLms) know what exists, where it is stored and how it is structured.

When these assumptions are broken, or when LLMs do not know what tables to look for, what columns
may contain the information it is looking for, how data are encoded, especially how data are
broken up (due to database normalization) and how to join them, it is difficult (or brittle) for LLMs to 
use SQL to get what they need. They may get wrong joins, missed data, hallucinated schema assumptions.
This is where `exporation` shines.

File-based stores enable exploration because they defer structure and semantics to interpretation time (by humans or LLMs), whereas databases require structure and semantics to be defined upfront for precise querying.

*Files* have properties that support exploration.

=== Self-contained meaning

A file often carries structure and semantics together

Example:

```markdown
# Order Processing

We retry failed payments up to 3 times...

No schema lookup needed.
```

=== Redundancy and Narrative

Files are often:

- verbose
- repetitive
- explanatory

That’s bad for databases, but great for LLMs.

=== Fuzzy Access Is Allowed

You can:

- keyword search
- semantic search (embeddings)
- skim multiple files

Instead of:
```sql
SELECT ...
```

you do:
```text
“Find anything related to payment retries”
```

=== No Strict Contract

Databases enforce:

- schema
- types
- constraints

Files allow:

- partial info
- inconsistent structure
- evolving formats

That flexibility enables exploration.

*IMPORTANT* Files are not designed for exploration. They are schema-light, loosely structured artifacts that LLMs can
reinterpret dynamically

The real “exploration system” is:
```text
LLM + retrieval (search / embeddings / ranking)
```

=== A more precise model

Instead of:
```text
Files = exploration
DB = query
```

A better model is:

Two axes:
#table(align: left, columns: 3,
[Dimension], [Files], [Databases],
[Structure], 	[loose], [strict],
[Access mode], 	[retrieval/search], [query],
[Semantics], 	[embedded in text], [externalized in schema],
[Determinism], 	[low], [high]
)

=== Real Distinction

The deeper truth is:

Databases → schema-first systems
- meaning defined upfront
- access via formal language (SQL)

File + LLM → interpretation-first systems
- meaning inferred at runtime
- access via natural language + retrieval


=== The Emerging Hybrid Pattern: Exploration Engine
File-based stores lead to a powerful pattern:

*Phase 1: Exploration (files)*
- discover concepts
- understand domain
- locate relevant signals

*Phase 2: Formalization (DB)*
- define schema
- enforce constraints
- run precise operations

Modern systems increasingly look like:

```text
[ Raw knowledge: files ]
        ↓ (embedding/search)
[ Exploration: LLM reasoning ]
        ↓ (structuring)
[ Database: system of record ]
```

This pattern encourages: *Exploration → then Query*

- SQL world: “Truth is structured, find it precisely.”
- LLM world: “Truth is messy, approximate it through context.”

Both are valid — for different stages of knowing.

= JSONata

#let a_033 = link(
  "https://github.com/jsonata-js/jsonata"
)[#text(fill: blue)[GitHub]]

#let a_034 = link(
  "https://www.reco.ai/blog/we-rewrote-jsonata-with-ai"
)[#text(fill: blue)[Article]]

#let a_035 = link(
  "https://blog.cloudflare.com/vinext/"
)[#text(fill: blue)[CloudFlare]]

#a_033 \
#a_034 \
#a_035 \
Source: Hacker News

This is an open-source project that implements a query langlage. It can be used to query
big JSON docs.

JSONata was originally implemented in TypeScript. In the author of #a_034 system, it
costed about \$300K/year to use it because for each call, it needs to serialize it
(they are using Go in the backend), sends it through the network, then retrieves
the results from the network and unserializes it.

It uses AI to re-write JSONata in Go. About 7 hours later, 13,000 lines of Go with
1,778 passing test cases. Total token cost: \$400.

The ROI? Previously, the system spends about \$25K per month. Now, it costs \$0.

Another important improvement they observed: the initial implementation, it spins 
up tens of thousands of goroutines to maximize concurrency (with all the added
resources) in what would otherwise be a straightforward pipeline of micro-batches.
That resulted in execssive memory and high CPU contention. 

They optimized this portion (possibly through just-in-time batching). The results
are: another \$18K/month off the bill.

*Try It*
```go
go get github.com/recolabs/gnata

expr, _ := gnata.Compile(`user.role = "admin" and user.loginCount > 100`)

json := []byte(`{
  "user": {
    "email": "admin@example.com",
    "role": "admin",
    "loginCount": 247
  }
}`)

result, _ := expr.EvalBytes(ctx, json)
fmt.Println(result) // true
```
Actions: A candidate to add to DeepDoc.

= 2026/03/28 - Matadisco

#let a_035 = link(
  "https://matadisco.org/"
)[#text(fill: blue)[Article]]

#a_035 \
Source: Hacker News

This is an open-source project using AT Protocol to publish data and retrieve data.
For more information, refer to the HyperStore.typ.

= 2026/03/28 - jai

#let a_036 = link(
  "https://jai.scs.stanford.edu/"
)[#text(fill: blue)[Article]]

#a_036 \
Source: Hacker News

Refer to /Users/cding/Workspace/KnowledgeStore/AI/JAI-LightWeightSandbox.md

= 2026/03/28 - HyperAgents

#let a_037 = link(
  "https://github.com/facebookresearch/hyperagents"
)[#text(fill: blue)[Article]]

#a_037 \
Source: Hacker News

This is a Self-referential self-improving agents that can optimize for any computable task.


