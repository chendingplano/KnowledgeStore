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

#show heading.where(level: 2): set text(size: 16pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

= Five Ways to Add Custom Attributes in RDBMSs

#let a_030100 = link(
  "https://dzone.com/articles/custom-attributes-in-relational-databases"
)[#text(fill: blue)[article]]

Link: #a_030100

Source: dzone

This article explores five ways to bring flexibility to RDBMS for custom
attributes.

== Dynamic Metadata Tables

It creates a separate table with entityID, attrID, value and a foreign key:
```sql
CREATE TABLE EntityAttrValue (
  entityId INT,
  attrId INT,
  value TEXT,
  FOREIGN KEY (attrId) REFERENCES AttributeMeta(id)
);
```

It is flexible and can be used for any table. The cons is that it requires joins. 

== Entity-Attribute-Value Model

I am not sure how it works.

== JSON

This is a typical way of providing custom attributes to tables. PostgreSQL, MySQL 8+, SQL Server
and Oracle support JSON columns, combining relational and NoSQL flexibility.

One of the cons is the lack of schema support. Users can add artitrary attributes.
Use this method with cautions. One should not add too many different attributes
or the same attributes but named slightly differently.

Because JSON is sensitive to attribute names, we should consider:
- Convert to lower-case, ALWAYS
- Document this to users
- Ideally, we can flag users from using symbols, or clearly document what can go into attribute names
- Use a dictionary for attribute names. If a user wants to use a new name,
  he/she should check the dictionary. If it is not there, add it first.
  This ensures that attribute names are uniform and less ambiguious.

One way to tackle this problem is to periodically review all the custom attributes.
If needed, extract the commonly used custom attributes to the table. By this, we 
evolve tables based on how the table is used.

This can be even done automatically.

== Hybrid Approach (Core + Extended Attributes)

Never mind about this approach. It is already covered with my comments above.

== Dynamic Column Addition

It automatically evolve tables by dynamically adding columns and indexes using metadata
and procedures. 

I am not sure whether we want to use this one or not. The problem with this method is
uncontrollability. A new column may be added accidentally, added for a specific record
and is not used by millions of other records, etc.

Changing schemas is a big, BIG issue. One should NEVER do it lightly.

Note that it is different from the comments I maded for JSON. We may automatically
add new columns, but we add them with strong support: the attribute(s) is used
with most (if not all) records.

= Code Mode

#let a_030101 = link(
  "https://blog.cloudflare.com/code-mode-mcp/"
)[#text(fill: blue)[article]]

#let a_030102 = link(
  "https://mksg.lu/blog/context-mode"
)[#text(fill: blue)[article]]

Link: #a_030101

Link: #a_030102

Source: Hacker News and ChatGPT

Instead of listing tons of functions and tools, Code Mode provides only two MCP tools:
- search() - let the agent search the API spec
- execute() - let the agent run generated JavaScript code against the API

The difference is that the agent (i.e., LLMs) writes JavaScript that discovers
what it needs from the API spec (for CloudFlare) and then calls the API

*Search*
- The search() tool accepts a snippet of JavaScript that examines a typed 
  representation of the API spec and returns exactly the endpoints the agent cares about.
- The full OpenAI spec never goes into the model's context - only the results of the
  code execution does.

Example
```js
async () => {
  const results = [];
  for (const [path, methods] of Object.entries(spec.paths)) {
    if (path.includes('/zones/') &&
        (path.includes('firewall/waf') || path.includes('rulesets'))) {
      results.push({ method: method.toUpperCase(), path, summary: op.summary });
    }
  }
  return results;
}
```
This code snippet filters possibly thousands of endpoints down to just the ones
relevant for rulesets or WAF.

*Execute*

Once the agent knows what endpoints it needs:
- It writes JavaScript that makes those API calls
- That code returns a secure sandbox (a Dynamic Worker isolate) with restricted access
  (no file system or uncontrolled network, for example).

This avoids round-trip calls for every single API action and avoids loading large
responses into the model's context.

Example
```js
async () => {
  const response = await cloudflare.request({
    method: "GET",
    path: `/zones/${zoneId}/rulesets`
  });
  return response.result;
}
```

== How It Works
1. Your real agent tells LLM: 'I have two tools: search() and execute()'
2. LLM receives a user query.
3. LLM decides whether to call a tool.
4. If yes → calls search()
5. Your agent runs the JS snippet in sandbox.
6. Returns results.
7. LLM decides whether it found the right endpoints.
8. If yes → calls execute() with generated code.
9. Your agent runs it and returns results.

That is exactly how Code Mode works conceptually.

It is just:
```text
LLM (planner)
    ↓
search()
    ↓
filtered schema returned
    ↓
execute()
    ↓
actual API results
```


This is a normal tool-calling loop — the difference is what the tool does.

== About 'Agent'

The article mentions 'agent'. Loosely speaking, it is the LLM. More precisely,
- The LLM is the reasoning engine
- The MCP server exposes tools
- The 'agent' is the LLM + tool-calling loop

In other word, when MCP is involved, there should be an MCP server between an LLM
and your application or your agents.

== Core Ideas

Code Mode is not about Cloudflre APIs. It is about letting LLM write programs instead
of calling atomic tools.

The general pattern is:
```text
Instead of expoising many rigit tools,
expose a programmable execution surface.
```

Letting LLMs write arbitrary JavaScript code is dangerous!
To avoid it, we can do the following.

The deeper architectural insight of Code Mode is:
- Instead of letting LLM select from a fixed menu of tools
- LLM dynamically explores capability space by writing code

=== Level 1 - Traditional Tool Mode

The search results are a list of related tools. It is safer, still compact, and easier 
to validate. The cons: it may be less flexible (normally does not matter much).

=== Level 2 - Parameterized Meta-Tools

Use parameterized meta-tools:
```js
search(spec_query: string)
execute(endpoint: string, method: string, body: json)
```

Note the concept: 'Meta-Tools', or a tool about tools!

=== Level 3: Full Code Mode (Cloudflare Style)

Unless you have very strong reason, do not do this!

== About MCP

MCP is a 'standardized way for an LLM client to discover and call
tools from external servers'.

It standardizes:
- How tools are described
- How tools are discovered
- How tool calls are invoked
- How results are returned

=== When MCP Actually Matters

MCP becomes useful when:

==== Case A — Third-party tools

You want to use tools from:

- A cloud provider
- A database vendor
- A SaaS system
- Someone else's tool server

And you do not want to:

- Manually integrate each API

- Hardcode each tool definition

MCP allows dynamic discovery.

==== Case B — Multi-client ecosystem

If:

- Multiple LLM clients exist
- Different models need the same tools
- You want plug-and-play compatibility

Then MCP is valuable.

==== Case C — Agent marketplace

If tools are like “apps”:

```text 
LLM ↔ Tool Ecosystem
```

Then MCP becomes like USB for AI tools.

= Alibaba Qwen 3.5 Medium models offer Sonnet 4.5 performance on local computers

#let a_030104 = link(
  "https://venturebeat.com/technology/alibabas-new-open-source-qwen3-5-medium-models-offer-sonnet-4-5-performance"
)[#text(fill: blue)[article]]

Link: #a_030104

Source Hacker News 

Will install and run it on my local machine.

= Deterministics in LLMs

#let a_030103 = link(
  "https://www.mcherm.com/deterministic-programming-with-llms.html"
)[#text(fill: blue)[article]]

Link: #a_030103

Source: Hacker News

Given exactly the same request, LLMs rarely generate identical results. Thi sis fundamental to the way
that LLMs operate: based on the 'weights' derived from their training data, they calculatge
the likelihood of possible next words to output, then
randomly select one (in proportion to its likelihood). This produces results that
are based on the sum total of the training data. This is the reason why LLMs almost never
get the same results, even when given exactly the same inputs.

Humans, like LLMs, aren't deterministrics, either. The software industry has invented 
various techniques to solve human undeterministrics, such as code review, pair programming,
et. The same techniques can be applied to LLMs.

== Lint

Lint becomes more important in vibe programming. This is a 'superviser' that checks the code
LLMs write. 

The lint here is not just from the programming language point of view. It should reflect
the best practice in your team.

== Testbot (Torturer)

Testing becomes even more important. A systematic approach to testing is critical. It is not
just another testing technique. 

== Formal Specification Language

Make sure requirements are spelled clearly. The skill allium is such an example. 
Spec-Driven Development (SDD) is another example.

== Pair Programming

Use multiple LLMs to do the same thing. This is especially important at requirement
and design stages.

= Run 1T Parameter LLM Locally

#let a_030105 = link(
  "https://www.amd.com/en/developer/resources/technical-articles/2026/how-to-run-a-one-trillion-parameter-llm-locally-an-amd.html"
)[#text(fill: blue)[article]]

#let a_030107 = link(
  "https://store.minisforum.com/products/minisforum-ms-s1-max-mini-pc?variant=47071388139765&country=US&currency=USD&utm_medium=product_sync&utm_source=google&utm_content=sag_organic&utm_campaign=sag_organic&gad_source=1&gad_campaignid=23282032443&gbraid=0AAAAAppTKYxLpViL06xt2CsucEoDZnrqp&gclid=Cj0KCQiA5I_NBhDVARIsAOrqIsb7BFxstGa2AFUcfwzfHzKEjjM0aYUQyZgBeJw-cZOzisKsfuw3rdUaAo8tEALw_wcB"
)[#text(fill: blue)[machine-info]]

Link: #a_030105

Machine Info: #a_030107

Source: Hacker News

#figure(
  image("Images/image_2026030101.png", width: 100%),
  caption: [Hardware setup (#a_030105)],
)

#figure(
  image("Images/image_2026030102.png", width: 100%),
  caption: [Hardware setup (#a_030107)],
)

Hardware: 4x Framework Desktop - AMD Ryzen™ AI Max+ 395 - 128GB 

AI Framework: AMD ROCm™ 

Inference Engine: Llama.cpp RPC 

OS: Ubuntu 24.04.3 LTS 

Model: Kimi-K2.5 (UD_Q2_K_XL) (375GB)

Network Interconnect: 5Gbps over Ethernet

== Conclusion

By leveraging the unified memory architecture of AMD's Ryzen AI Max+ platform and the flexibility
of llama.cpp RPC, it is able to inference a one trillion parameter start-of-the-art model
across a small cluster of AI PCs as a single coordinated inference system.

