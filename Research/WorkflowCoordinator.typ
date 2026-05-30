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
    "Research - Workflow Coordinator"
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

#let frontmatter = (
  file_type: "typst",
  logical_name: "PanDoc",
  file_id: "2026053001",
  content_type: "research",
  document_date: "2026/05/30",
  keywords: [Workflow, Workflow Coordinator],
)

= Overview
A workflow is a sequence of processing, normally in form of tasks. A workflow is not finished unless:
- It is explicitly aborted or stopped
- All its tasks are either finished successfully or failed

The order in which tasks are executed is important. 

*Execution Mode*
Tasks run either sequentially or in parallel. This is called Execution Mode.
In the `Sequential Mode`, all tasks must run sequentially, one after another.
In the `Parallel Mode`, all tasks may run simultaneously, normally subject to
the resources and rate controls.

*Execution Checkpoint*
For workflows where some tasks must run sequentially and some may run in parallel,
we can break a workflow into multiple `Execution Section` by `Execution Checkpoint`.
Each execution section is associated with an `execution mode`.

== Workflow
A workflow consists of tasks. Workflows are identified by Workflow IDs.
Workflow is stateful. For each of its tasks:
- Task ID
- Task Name
- Task State
- Error Message

Workflows uses a database table to manage their states.

Example:

```text
Step 1: Create customer record
Step 2: Send welcome email
Step 3: Generate invoice
```

A traditional application might do:

```go
CreateCustomer()
commit()

SendEmail()

GenerateInvoice()
commit()
```

If the process crashes after sending the email but before 
Step 3 completes, when restarted the system may not know:

- Did Step 2 finish?
- Was the email sent?
- Should Step 2 run again?
- Will the customer receive duplicate emails?

This is where durable execution comes in.

The workflow engine stores something like:

```text
workflow_id = 123

step_1 = completed
result_1 = customer_id=567

step_2 = completed
result_2 = email_message_id=ABC

step_3 = pending
```

The workflow state itself becomes data.

After every successful step:

```text
Run step
↓
Store result/checkpoint
↓
Mark step completed
↓
Move to next step
```

If the server crashes:

```text
workflow_id = 123

step_1 completed
step_2 completed
step_3 pending
```

is still in PostgreSQL.

When the system restarts, by reading the database, it can resume the
workflow by re-run 'step_3' only.

Note that in this example, 'step_2' does not have any data saved in 
the database. In order to make the operation permanent, the workflow
table becomes the enabler.

The deeper idea is to turn execution state into data.

== Review - Postgres Is All You Need for Durable Execution ([1])

The article argues that durable execution—making programs resilient to crashes, restarts, 
and failures by checkpointing execution state—does not require a dedicated workflow 
orchestration system such as Temporal, AWS Step Functions, or similar platforms. Instead, 
DBOS proposes that a single PostgreSQL database can serve as both the application's data 
store and its durable execution engine. The central claim is that if your application 
already depends on PostgreSQL, adding another orchestration layer often introduces 
unnecessary complexity and operational burden. ([dbos.dev][2])

The article contrasts two architectures. In the traditional model, applications interact 
with an external orchestrator that manages workflow state, retries, scheduling, and recovery. 
This orchestrator typically requires its own infrastructure, storage layer, monitoring, security 
controls, and operational expertise. DBOS proposes a Postgres-backed architecture where workflows 
are represented as rows in database tables. Application servers directly read and execute 
workflows from PostgreSQL, while checkpointing the results of each step back into the same 
database. In effect, PostgreSQL becomes the durable state machine for workflow execution. ([dbos.dev][2])

A major benefit highlighted is operational simplicity. By reusing PostgreSQL, organizations 
avoid introducing another critical service that must be deployed, scaled, monitored, secured, 
and backed up. The article argues that external orchestrators and their metadata stores become 
additional points of failure, whereas most applications already treat PostgreSQL as essential 
infrastructure. Therefore, using PostgreSQL for workflow durability reduces architectural complexity 
and minimizes the attack surface because workflow data never needs to pass through a separate 
orchestration service. ([dbos.dev][2])

The article also emphasizes observability. Since workflow state and step checkpoints are stored 
as ordinary database records, workflow execution can be inspected using standard SQL queries, 
dashboards, and monitoring tools. This makes workflow progress, failures, and execution history 
inherently visible without requiring specialized orchestration tooling. The same persisted state 
that provides durability also becomes a rich source of operational telemetry. ([dbos.dev][2])

From the perspective of SemOS project, the most interesting idea is not merely "using Postgres 
as a queue." The deeper architectural principle is *collapsing infrastructure layers by storing 
execution state alongside application state*. This is similar to DBOS's broader philosophy 
that many system concerns—workflows, queues, retries, observability, messaging, and recovery—can 
be represented as durable database records rather than separate services. In knowledge systems 
such as SemOS, the same pattern could potentially apply to indexing jobs, document processing 
pipelines, knowledge extraction workflows, graph construction tasks, and agent execution traces: 
instead of introducing dedicated workflow infrastructure, these processes could be modeled as 
durable state transitions stored directly in PostgreSQL. ([dbos.dev][2])

== Review - SqlLite Is All You Need for Durable Execution ([3])
2026/05/30

This article is essentially a response to the DBOS argument that 
"Postgres is all you need for durable execution.([1])" The author agrees with the core idea—durable 
execution does not require a separate workflow orchestration platform—but argues that the concept 
can be pushed even further. For many workflow systems, the truly durable asset is not the compute 
infrastructure or the application server, but the workflow state itself. Once you recognize that, 
an embedded database such as SQLite becomes sufficient for many durable workflow use cases. ([Obelisk][3])

The article explains that durable workflows work by persisting execution history. In Obelisk, workflow 
progress is stored in an execution log. Every activity invocation, sleep operation, result, and workflow 
event is recorded so that if the process crashes, the workflow can be replayed and resumed from the 
last successful step. Because the state is persisted, the compute layer becomes disposable: processes 
can crash, restart, or be replaced without losing workflow progress. The key requirement is preserving 
the execution log, not preserving the process itself. ([Obelisk][3])

A central argument is that SQLite is often a better fit than PostgreSQL for this purpose because 
workflow state is typically modest in size, append-heavy, and local to a single service. SQLite offers 
transactional durability, crash recovery, WAL (write-ahead logging), and reliable persistence without 
requiring a separate database server. By embedding the workflow store directly into the application, 
deployment becomes dramatically simpler: a single binary plus a SQLite file can provide durable execution, 
retries, recovery, and observability. ([Obelisk][3])

The article also emphasizes observability and determinism. Obelisk records workflow events into an execution 
log that can later be inspected, replayed, and debugged. Rather than reconstructing state from 
application-specific tables, the execution history itself becomes the authoritative record of what 
happened. The workflow engine can then replay the history to reconstruct state after failures. This 
is similar in spirit to event sourcing, where the log is the system of record and current state is 
derived from replaying events. ([Obelisk][1])

For reliability, the author suggests using Litestream ([4]) to back up important data to an S3-compatible
storage.

For SemOS project, the most interesting takeaway is not really "SQLite vs PostgreSQL." The deeper idea 
is that *workflow state can be represented as an append-only execution log rather than as coordinator 
memory*. Whether the backing store is SQLite or PostgreSQL becomes a deployment choice. If SemOS runs 
as a mostly single-node knowledge-processing system, SQLite could potentially persist ingestion jobs, 
OCR pipelines, topic extraction, graph-building tasks, and LLM execution traces with very little 
operational overhead. If you later need clustering, multiple workers, or large-scale concurrent processing, 
PostgreSQL may become the more natural backend. The architectural insight is that durable execution can 
be implemented by persisting workflow history itself, not by introducing a heavyweight orchestration 
service. ([Obelisk][3])


== References
[1] Postgres Is All You Need, 
https://www.dbos.dev/blog/postgres-is-all-you-need-for-durable-execution

[2] Postgres-backed Durable Workflow Execution, 
https://www.dbos.dev/blog/postgres-is-all-you-need-for-durable-execution?utm_source=chatgpt.com 

[3] SQLite is All You Need for Durable Workflows - Blog, 
https://obeli.sk/blog/sqlite-is-all-you-need-for-durable-workflows/?utm_source=chatgpt.com

[4] Litestream, https://litestream.io/
