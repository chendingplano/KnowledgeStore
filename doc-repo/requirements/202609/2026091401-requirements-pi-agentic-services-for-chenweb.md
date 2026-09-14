# Requirements for Pi-Based Agentic Services in ChenWeb

- Document ID: `doc-2026091401`
- Status: Proposed
- Date: 2026-09-14
- Audience: Product owners, subject-matter experts, designers, developers, testers, and operators

## 1. Purpose

ChenWeb should offer guided, conversational services that can do more than return a list of search results. A user should be able to ask a question, describe a problem, or request help with a task. The service should decide what information it needs, consult ChenWeb's knowledge base when appropriate, and explain its answer in a useful and traceable way.

These services need an agent harness: software that manages the conversation, works with an AI model, and lets the model use approved tools. Possible harnesses include Codex, Pi, and OpenCode. This first effort will use Pi because it is comparatively small and easy to adapt. The purpose is to prove the approach and learn what ChenWeb needs before supporting more harnesses or more ambitious services.

This document describes the desired outcomes and behavior. It is a requirements document, not a detailed design or implementation specification.

## 2. Goals

The proof of concept has six goals:

1. Let a signed-in ChenWeb user hold a continuing conversation with an agentic service.
2. Let the service use ChenWeb's knowledge base to answer questions with relevant evidence.
3. Let ChenWeb offer more than one agentic service, with each service using a Pi configuration suited to its job.
4. Keep ChenWeb in control of user access, permitted actions, saved conversations, and the information shown to the user.
5. Make answers understandable and traceable to their source documents whenever the knowledge base is used.
6. Learn whether Pi is a suitable foundation and identify what a future harness-neutral ChenWeb interface would need.

Examples of early services include:

- answering questions about documents in the knowledge base;
- helping a user diagnose a product, process, or documentation problem;
- comparing facts or requirements found in several documents;
- explaining a metric, product, provision, topic, or other extracted item in context; and
- guiding a user toward the source material needed to make a decision.

The proof of concept is successful when ordinary users can complete these tasks without needing to know how Pi, AI models, document processors, or search systems work.

## 3. Guiding Principles

### 3.1 ChenWeb remains the product

Users interact with ChenWeb, not directly with Pi. ChenWeb owns the page, user identity, permissions, conversation record, service selection, and final presentation. Pi manages the model's conversation and its use of approved tools behind an agentic service.

### 3.2 Pi is replaceable

The first implementation may depend on Pi, but user-facing services should not be named or shaped around Pi-specific concepts. The boundary between ChenWeb and the harness should be clear enough that a later experiment could use Codex, OpenCode, or another harness without redesigning the user experience.

### 3.3 Evidence is more important than fluency

A polished answer is not enough. When an answer relies on the knowledge base, the user should be able to see which documents and passages support it. The service must distinguish sourced facts from its own interpretation and must say when the available evidence is incomplete or conflicting.

### 3.4 Least authority by default

An end-user service receives only the tools it needs. Knowledge-question services should begin with read-only tools. They should not automatically receive shell access, unrestricted file access, direct database access, or administrative ChenWeb abilities.

### 3.5 Start small and observable

The proof of concept should favor a small number of dependable capabilities over a large tool catalog. ChenWeb operators must be able to understand what the service did, which information it used, how long it took, and why it failed.

## 4. Main Concepts

To avoid confusion, the product should use the following distinctions:

- **Agentic service:** A user-facing capability in ChenWeb, such as “Ask the Knowledge Base” or “Diagnose a Problem.”
- **Pi profile:** The named Pi setup used by a service. It includes instructions, model choice, allowed tools, and operating limits.
- **Slug:** A short, stable key ChenWeb uses to identify a profile, such as `knowledge-guide` or `product-diagnostics`. It is not intended to be the service's user-facing name.
- **Conversation:** One continuing exchange between a user and a service. Many conversations may use the same Pi profile.
- **Pi worker:** The running Pi activity that handles a conversation. A profile does not have to mean one permanently running operating-system process.
- **Tool:** A controlled action Pi can ask ChenWeb to perform, such as searching the knowledge base or retrieving a cited passage.
- **Artifact:** A useful item created from a processed document, such as a metric, product, summary, topic, or provision. An artifact points back to the source lines from which it was produced.
- **Pi gateway:** A small internal service that receives requests from the ChenWeb backend and operates Pi. Users and browsers do not contact it directly.

One agentic service normally maps to one Pi profile. Several services may share a profile only when they truly need the same instructions, model, tools, and limits. A profile may support many users and conversations at the same time.

## 5. How the Service Works

The overall path is:

```text
User's ChenWeb page
        ↓
ChenWeb backend
        ↓
Pi profile and conversation
        ↓
Approved ChenWeb tools, including knowledge-base tools
        ↓
Pi's answer returns through ChenWeb to the page
```

The expected experience is:

1. The user opens an agentic service page in ChenWeb.
2. ChenWeb identifies the chosen service and the Pi-profile slug assigned to it.
3. The user starts a new conversation or resumes one they are allowed to access.
4. The user asks a question or describes a problem.
5. The ChenWeb backend checks the user's access, records the request, and sends the request and relevant conversation context to Pi.
6. Pi follows the selected profile's instructions. It may ask the user a clarifying question or request one or more approved tools. It may answer without searching only for conversational matters that do not depend on facts from ChenWeb's knowledge base, such as explaining what the service can do.
7. When Pi requests a tool, ChenWeb checks that the profile and the user are allowed to use it. ChenWeb performs the action and returns a limited, structured result to Pi.
8. Pi produces a response. ChenWeb shows the response progressively when possible, along with its status and supporting sources.
9. ChenWeb saves the conversation, tool activity, source references, timing, model usage, and any errors needed for later review.

The browser must not connect directly to Pi or hold model credentials. Closing or refreshing the page should not corrupt the conversation. A user should be able to stop a response that is taking too long.

## 6. The User Experience

For the proof of concept, the page should provide:

- a clear service name and a short explanation of what it can and cannot do;
- a conversation area for user questions, Pi responses, and clarifying questions;
- a visible indication when the service is thinking, searching, reading sources, finished, stopped, or unable to continue;
- a stop control for an active response;
- source references that open the relevant document and, where possible, the relevant lines or extracted item;
- a way to begin a new conversation and return to an earlier conversation;
- a clear error message with a safe retry option when recovery is possible; and
- a simple way to mark a response helpful or unhelpful and optionally explain why.

The interface may summarize tool activity in plain language, such as “Searching metrics” or “Reading lines 120–135 of Product Datasheet v3.” Internal commands, credentials, raw model messages, and private instructions must not be exposed.

The service should ask a focused follow-up question when the user's request is too broad or missing essential facts. It should not bury the user in a long questionnaire before offering help.

## 7. Multiple Pi Profiles and Services

ChenWeb must support multiple Pi profiles. Each profile is identified by a unique, stable slug. Slugs are used by ChenWeb and administrators; users normally see a friendly service name.

Each profile must be able to define:

- its purpose and user-facing description;
- its system instructions;
- its preferred AI model;
- adjustable model behavior, such as how much reasoning to use and how long an answer may be;
- the tools it may use;
- limits on tool calls, elapsed time, and model usage;
- whether conversations may be saved and resumed;
- what knowledge stores or document groups it may use;
- whether the profile is available, paused, or retired; and
- a version so past conversations can be understood even after the profile changes.

Prompts must be stored as versioned prompt files under ChenWeb's `prompts` directory, following ChenWeb's existing prompt naming rules. They must not be hidden inside application code.

Changing a profile must not silently alter an already-running conversation. A saved conversation should retain the profile version and model that produced it. If a retired or changed profile cannot safely resume an old conversation, ChenWeb should explain this and offer to start a new one.

The two initial profiles must save and resume conversations. Other profiles may disable this behavior later.

The proof of concept should include at least two profiles to demonstrate that the arrangement is real rather than theoretical:

1. **Knowledge Guide:** answers questions using knowledge-base evidence.
2. **Problem Diagnosis Guide:** helps with product, process, and documentation problems covered by ChenWeb's knowledge base. It gathers the essential symptoms and context, searches for relevant evidence, and returns a concise problem summary, supported facts, possible explanations, suggested checks in a sensible order, and unresolved questions. It stops at advice and read-only investigation; it does not change systems or records. When the knowledge base cannot support a safe conclusion, it says so and recommends the appropriate subject-matter expert or support path. Medical, legal, personal-safety, and other high-stakes diagnosis are outside this profile's purpose.

## 8. Connecting ChenWeb to Pi

The preferred proof-of-concept arrangement is a small Pi gateway running beside ChenWeb. ChenWeb sends the gateway an authenticated internal request naming the profile slug and conversation. The gateway uses Pi's supported software interface to create or resume the appropriate Pi conversation.

This arrangement is preferred because it:

- keeps the browser and public network away from Pi;
- lets ChenWeb remain responsible for access and records;
- uses Pi in its native environment without placing Pi-specific code throughout the Go backend;
- supports several profiles and concurrent conversations; and
- creates a clear seam where another harness could be tested later.

The gateway is part of the ChenWeb service environment even if its Pi-related code lives with the installed Pi package. It must have a defined start, health check, shutdown, and recovery process. ChenWeb should report that the service is temporarily unavailable when the gateway is unhealthy rather than leaving a request hanging.

Launching a new command-line Pi process for every user message is not the preferred approach. It may be useful for an early experiment, but it makes continuing conversations, cancellation, resource control, and failure recovery harder. Allowing Pi to query the ChenWeb database directly is also out of scope because it bypasses ChenWeb's access checks and makes future harness replacement more difficult.

## 9. Knowledge-Base Tools for Pi

ChenWeb's knowledge base contains several forms of the same underlying knowledge:

- parsed documents represented as numbered lines;
- chunks that group related lines into useful reading units; and
- extracted artifacts such as metrics, products, provisions, summaries, topics, entities, relationships, inventory items, and other structured findings.

Search already combines matches on the user's words with matches that appear to have a similar meaning. Pi should use this capability through a small set of ChenWeb tools. The tools should return a limited set of results with stable identifiers and source locations, allowing Pi to search broadly and then inspect only the most useful evidence.

Both initial services are knowledge-grounded. They must search ChenWeb before making a factual claim about a document, product, process, requirement, or diagnosed problem. General model knowledge may help Pi choose a question or search phrase, but it must not be presented as a ChenWeb-supported fact. If Pi includes useful background knowledge that was not found in the knowledge base, it must label that information clearly and must not use it as the sole basis for a diagnosis or recommendation.

### 9.1 Essential tools for the proof of concept

#### Search knowledge

Pi provides a natural-language query and may narrow it by document, artifact type, knowledge store, or other permitted scope. ChenWeb returns the best matching chunks and artifacts together with short excerpts, source document names, line ranges, and relevance information.

This should be the normal starting tool when Pi does not yet know where the answer is located. It should search across relevant artifact types rather than forcing Pi to guess which processor created the answer.

#### Read source passages

Pi provides a source-document identifier and one or more line ranges. ChenWeb returns the original parsed lines, including page information when available. This lets Pi verify a search result, read nearby context, and quote or paraphrase accurately.

The tool must limit the amount returned in one call. Pi may request another nearby passage when more context is genuinely needed.

#### Get artifact details

Pi provides a stable artifact identifier. ChenWeb returns the artifact's useful fields, its source spans, its source document, and its review or validation status when available. This is needed because a search result is only a summary and may omit important values or qualifications.

#### Get document context

Pi provides a document identifier. ChenWeb returns basic information such as title, filename, date, document type, available summaries, major topics, and processing status. This helps Pi understand what kind of source it is using and whether the document was processed successfully.

#### Find related knowledge

Pi provides an artifact or document identifier. ChenWeb returns directly connected or strongly related artifacts, with a short explanation of each relationship. This supports questions such as “What product does this metric describe?”, “What provision governs this requirement?”, or “What other documents discuss the same item?”

### 9.2 Useful follow-on tools

After the essential tools are proven, ChenWeb should consider:

- a comparison tool that collects the same metric, product, or provision across selected documents;
- a terminology tool that explains governed terms, labels, and known aliases;
- a document-structure tool that locates sections, tables, and headings;
- a source-opening tool that creates a safe ChenWeb link to the relevant PDF page or line view;
- a processing-status tool that explains whether missing knowledge may be caused by an incomplete or failed document-processing step; and
- service-specific diagnostic tools that read approved operational information without making changes.

These should be added because a real service needs them, not merely because the knowledge base contains the data.

### 9.3 Common behavior for every knowledge tool

Every tool must:

- apply the signed-in user's access and knowledge-store boundaries;
- accept only clearly defined, limited inputs;
- return an amount of information limited by the profile and the server;
- include stable source and artifact identifiers;
- preserve source line and page references when available;
- state when data is missing, stale, unreviewed, or derived by an AI document processor;
- treat “no result” as a normal outcome rather than inventing an answer;
- record who used the tool, through which service, and for which conversation; and
- return safe, plain error information that Pi can explain to the user.

Search-result text and document contents are untrusted evidence. They must not be allowed to change Pi's system instructions or grant new tools. A document that says “ignore previous instructions,” for example, must be treated as document content rather than as a command.

## 10. Answers and Sources

When Pi uses knowledge-base information, the final response must provide a source reference on the claim, sentence, or nearby paragraph it supports. Each distinct factual conclusion must be traceable to at least one source. A source reference should let the user identify:

- the source document;
- the relevant page or line range when available; and
- the extracted artifact when the claim comes from an artifact.

Opening a source reference must repeat the user's access check. A citation must not reveal the existence, title, excerpt, ranking, or relationship of content the user cannot access. If a source has changed since the answer was produced, ChenWeb should show the current source and warn that it may differ from the version used for the answer. Saved answers must retain enough source identity and location information for an operator to investigate such changes.

Pi should prefer the original source passage when an extracted artifact and its source disagree. It should call out meaningful conflicts between sources rather than silently choosing one. It must not present an extracted artifact as human-verified unless its recorded status supports that statement.

If the tools do not find enough evidence, the response should say so and may suggest a narrower question, another document, or a next diagnostic check. The service should distinguish among:

- facts supported by retrieved sources;
- conclusions drawn from several facts;
- suggestions that still need verification; and
- general model knowledge that did not come from ChenWeb's knowledge base.

## 11. Conversations and Continuity

Each conversation must belong to the signed-in user and the selected service. ChenWeb must prevent users from viewing or continuing conversations they are not permitted to access.

Access must also be checked when a saved conversation is opened or resumed. If the user has lost access to a source used earlier, ChenWeb must not show or resend to Pi the protected passage, artifact details, tool result, summary content, or answer content derived from that source. The page should explain that part of the conversation is unavailable because access changed. Restoring access may restore the hidden content; starting a new conversation must not carry the hidden content forward.

A saved conversation should include the user and assistant messages, source references, tool activity, service slug, Pi-profile slug and version, model used, creation and update times, and final outcome. Sensitive internal reasoning must not be stored or shown.

ChenWeb already records local harness sessions, including Pi sessions. The proof of concept should reuse useful parts of that work where appropriate, but a user-facing agentic conversation needs stronger ownership, access control, service identity, and lifecycle behavior than a read-only local session viewer.

Conversation history sent back to Pi should be limited to what is needed. Long conversations may be summarized, but the summary must not lose important user constraints or source references.

A conversation is pinned to the profile version and model with which it began. Resuming it must use that same version and model when they remain available. ChenWeb must never quietly move it to a new profile version. If the original setup is unavailable or no longer permitted, ChenWeb should keep the history readable, explain why it cannot be resumed as-is, and offer to start a new conversation using the current profile.

## 12. Safety, Privacy, and Access

The proof of concept must meet these requirements:

- Only authenticated ChenWeb users may use agentic services unless a service is deliberately approved for public use later.
- A user and a Pi profile may access only the knowledge stores and tools permitted to both of them.
- Model and service credentials remain on the server and must never appear in browser responses, prompts, logs, or error messages.
- Each tool request is checked by ChenWeb at the time of use; permission at conversation start is not enough.
- Tool results must be treated as data, not trusted instructions.
- Before the pilot begins, ChenWeb must publish the retention period and deletion behavior for model input, saved conversations, tool records, and operational logs.
- Users must be told which outside model provider receives their messages and retrieved evidence. A profile must not use a provider that is incompatible with the knowledge store's data-handling rules.
- Users must be able to delete their own saved conversations unless a disclosed legal or operational retention rule prevents deletion.
- Only authorized users and operators may view conversation or tool records. Logs should avoid full prompts and full retrieved passages unless they are explicitly required for an approved investigation mode.
- Administrators must be able to disable a service or profile promptly.
- Read-only service profiles must be unable to change source documents, extracted artifacts, settings, or processing status.
- If future tools can make changes, the user must see the proposed action and explicitly confirm consequential actions before they occur.

The page should remind users that AI assistance may be mistaken and that important decisions should be checked against the cited source.

## 13. Reliability and Resource Control

ChenWeb must place practical limits on each request and conversation, including elapsed time, number of tool calls, size of retrieved evidence, and model usage. Reaching a limit should end gracefully with an explanation rather than a broken page.

The system should handle:

- Pi or the selected model being unavailable;
- a tool timing out or returning an error;
- no useful search results;
- malformed or unexpectedly large tool requests;
- the user stopping a response;
- the browser disconnecting and reconnecting;
- several conversations using the same profile at once; and
- ChenWeb or the Pi gateway restarting during a conversation.

One failed tool should not necessarily end the response. Pi may retry once when safe, use another approved source, or explain what could not be checked. Endless retry loops must be prevented.

Each accepted user message creates one identifiable response attempt. Re-sending the same browser request after a connection problem must not accidentally create duplicate attempts. Stopping an attempt should cancel outstanding Pi and tool work as soon as practical, preserve the conversation, label any partial response as incomplete, and record the attempt as stopped rather than failed. After reconnecting, the page should show the current or final recorded state. If a restart interrupts work that cannot continue, ChenWeb should mark the attempt interrupted and offer a safe retry as a new attempt.

The system must apply fair-use limits so one conversation cannot consume all workers or model capacity. Overloaded services should queue briefly or return a clear “try again” response.

## 14. Operations and Review

Operators need a view of service health and usage that answers:

- Which services and profile versions are active?
- How many conversations are running, completed, stopped, or failed?
- Which models and tools are being used?
- How long do responses and tool calls take?
- How often do users stop requests or mark answers unhelpful?
- Which errors are recurring?
- What is the approximate model usage and cost by service?

Each request should have one traceable identifier across the ChenWeb request, Pi conversation, tool calls, and logs. Logs should contain enough information to investigate behavior while avoiding credentials and unnecessary sensitive content. Access to these records must itself be permission-controlled, and their retention must follow the published policy.

Administrators should be able to test a new profile version with selected users before making it the default, compare it with the previous version, and return to the previous version if quality declines.

## 15. Quality Evaluation

The team should maintain a small set of representative questions and diagnostic scenarios for each service. The set should include straightforward questions, ambiguous requests, missing evidence, conflicting sources, misleading instructions inside documents, and attempts to reach information the user cannot access.

Before a profile version becomes generally available, reviewers should check whether it:

- reaches the correct conclusion or gives an appropriately cautious response;
- selects suitable tools without unnecessary calls;
- cites the correct source passages;
- respects access limits;
- clearly separates facts, conclusions, and suggestions;
- asks useful clarifying questions; and
- completes within acceptable time and usage limits.

User feedback is useful but is not sufficient on its own. A confident, popular answer can still be unsupported. Source correctness and permission enforcement must be tested directly.

## 16. Proof-of-Concept Scope

The first release should include:

- one ChenWeb conversational page that can host the two initial services;
- service selection and routing by Pi-profile slug;
- new and resumable user-owned conversations;
- progressive responses and cancellation;
- the five essential read-only knowledge tools;
- visible source references;
- profile versioning and server-side prompt files;
- basic health, error, timing, model-usage, and tool-usage records;
- user feedback; and
- an evaluation set for both initial services.

The first release does not need:

- autonomous work that continues for hours without a user;
- multiple agents collaborating on one request;
- tools that modify knowledge-base content or system settings;
- arbitrary web browsing, shell commands, or unrestricted file access;
- automatic selection among Pi, Codex, OpenCode, and other harnesses;
- a visual profile builder for administrators;
- perfect recovery of an in-progress answer after every type of server failure; or
- a promise that every question can be answered from ChenWeb's current knowledge base.

## 17. Success Criteria

The proof of concept is considered successful when:

1. A signed-in user can start and resume conversations with both initial services.
2. ChenWeb consistently routes each service to the Pi profile named by its slug.
3. Two profiles can use different prompts, models, tools, or limits without affecting each other.
4. Pi can search chunks and extracted artifacts, inspect original lines, and use the retrieved evidence in an answer.
5. Knowledge-based answers include working source references, and unsupported answers clearly disclose the lack of evidence.
6. Access checks prevent a user or profile from retrieving knowledge outside its permitted scope.
7. A user can stop a response, recover from ordinary failures, and understand the current state without seeing internal implementation details.
8. Operators can trace a reported answer through its profile version, model, tool calls, sources, timing, and outcome.
9. Both services pass their agreed evaluation set: normal scenarios reach the expected outcome, unsupported scenarios disclose missing evidence, hostile-document scenarios do not change Pi's instructions, and every access-control scenario—including access revoked after a conversation was saved—is denied without leaking protected information.
10. The team can describe, using evidence from the proof of concept, which parts are ChenWeb service behavior and which parts are specific to Pi.

## 18. Questions to Resolve During the Proof of Concept

The proof of concept should produce evidence for these later decisions:

- Should the Pi gateway keep workers warm, create them on demand, or use a mixture of both?
- What conversation and evidence limits give a good balance of answer quality, response time, and cost?
- Which artifact types are most useful to each service, and which create noise?
- When should Pi search chunks directly, search extracted artifacts, or do both?
- How should ChenWeb rank original passages against AI-extracted artifacts when both match?
- Which conversations may contain sensitive material, and how long should they be retained?
- What profile-management features do administrators actually need?
- What common harness interface would allow a second implementation using Codex or OpenCode?
- Which diagnostic tasks can remain read-only, and which future tasks would require user-approved actions?

These are learning goals, not reasons to delay the initial proof of concept. The initial release should make conservative choices, record the outcomes, and use real user experience to guide the next requirements document.
