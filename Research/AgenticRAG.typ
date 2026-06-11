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
    "Research - Agentic RAG"
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
  logical_name: "Agentic RAG",
  file_id: "2026061101",
  content_type: "research",
  document_date: "2026/06/11",
  keywords: [RAG, Agentic RAG, Graph RAG, Knowledge System],
)

= Overview
[[ref:[1]]] is an article about graph RAG. 
Many people struggle (at least I) about flat-RAG and graph-RAG. The author of this article lists:
- What concepts relate to this issue?
- Which prerequisite skill may be lacking?
- Which resource previously addressed this gap?
- What assessment verifies improvement?
- Which rule restricts recommendations?

I am not sure whether these should be treated as a search requests or question-answering 
requests. To me, it is more the latter than the former. Search requires very little 'smartness', 
tend to be more 'mechanical', while question-answering requires much more 'smartness'. 

If it is the latter, when a user asks "What concepts relate to \<this issue\>?", the request is 
routed to an LLM. I am not sure whether (most likely not) the LLM will just throw the original 
questions back to an RAG, asking for supporting materials, and answer the questions. Instead, 
the LLM analyze the question, and formulates search queries, if needed, and then send the 
search queries to an RAG.

== Agentic RAG
What is 'Agentic RAG'? 

Looking at Claude Code, Codex, or any coding assistant, they are essentially an infinte loop:

- Receive a request
- Let LLM 'think', with proper prompt, list of tools and possibly something more
- LLM understand what it needs to do
- Formulate search requests, often the time through tool-calling, such as 'grep ...', as needed
- The coding assistant checks whether it has right to run the tool
- Run the tool if it can
- Get results, feed back with session history (memory) to the LLM
- (...) essentially going back to the beginning of the loop

My understanding is an agentic RAG is an RAG that has a 'brain'. It uses the brain to think, 
reason, and uses 'search' as a tool, as needed, to find the relevant information, and so on.

If this is what an agentic RAG is, it is not just an RAG, it is an agentic solution, an 
agentic app, just like Claude Code, Codex, etc. This is the reason why we never categorize 
Claude Code as an RAG, agentic or not, but as a kind of 'super app'.

If this is the case, where is the agentic RAG, or what exactly is an agentic RAG?

*(from Fable 5)* \
At the fully agentic end, "agentic RAG" is architecturally indistinguishable from "an agent 
with retrieval tools." The term survives for reasons of lineage and emphasis, not because it 
names a distinct architecture.

*The lineage explanation.* RAG (the 2020 Lewis et al. paper) named a fixed pipeline: 
```text
embed query → retrieve → stuff context → generate. 
```

Crucially, the LLM sits at the *end* of the pipeline as a passive consumer. Control flow 
belongs to the pipeline, not the model. Over 2023–2025, people kept patching this pipeline's 
failures by adding LLM-powered decision points:

- *Query rewriting/decomposition*: an LLM reformulates the user's question before retrieval
- *Routing*: an LLM decides *which* index/retriever to query (vector store vs. graph vs. SQL vs. web)
- *Grading/reflection*: an LLM judges whether retrieved chunks are actually relevant, and re-retrieves if not (Self-RAG, Corrective RAG)
- *Iteration*: multi-hop retrieval where the result of one retrieval informs the next query

Each patch hands a bit more control flow to the model. "Agentic RAG" is the umbrella term 
for any point along this gradient. Push the gradient to its limit — LLM owns the loop entirely, 
retrieval is just a tool it calls when it wants — and yes, you've reproduced exactly the 
Claude Code loop you sketched, with `vector_search` where `grep` would be. Your observation 
that the categories merge at the limit is correct.

*But here's the nuance: most things sold as "agentic RAG" are not at the limit.* 

They're usually a *directed graph with LLM-powered decision nodes* — think LangGraph-style: a router 
node, a rewrite node, a retrieve node, a grade node, a conditional edge back to rewrite, then 
generate. The topology is fixed by the developer; the LLM only picks branches within it. That's 
meaningfully less than Claude Code, where the model decides at every turn what to do next in 
an open-ended loop with no predetermined topology. So one defensible definition is:

- *Classic RAG*: fixed pipeline, zero LLM decisions about control flow
- *Agentic RAG*: developer-fixed topology, LLM-controlled branching within it
- *Agent*: LLM-controlled topology — the loop you described

*The teleological explanation.* 

The other reason Claude Code isn't called RAG while a 
"support copilot" doing nearly identical loops is: the terms describe *purpose*, not mechanism. 
RAG, agentic or not, names systems whose end product is an answer grounded in a corpus — retrieval 
is the point, and the system is read-only with respect to the world. Claude Code's retrieval (grep, 
file reads) is incidental; its point is to *act* — edit files, run tests, commit. We categorize by 
what the system is for and what it can touch, not by its loop structure. By this lens, Anthropic's 
and OpenAI's "deep research" features are the clearest real-world examples of agentic RAG at the 
fully-agentic end: an open-ended agent loop whose only tools are search and fetch, whose only output 
is a grounded answer. Nobody markets them as RAG, which rather proves your point — once the agency 
is obvious, the RAG label gets dropped.

*And the cynical explanation, which deserves mention.* 

"Agentic RAG" is also a marketing term coined by the ecosystem that grew up around RAG — vector 
databases, orchestration frameworks, chunking tools — at the moment plain RAG started looking 
commoditized and agents became the hot category. Calling your product "agentic RAG" lets you 
keep your existing positioning while claiming the new trend. That's not the whole story, but 
it explains why the term is used far more by vendors and framework docs than by research papers, 
which prefer specific names like Self-RAG, ReAct, or multi-hop retrieval.

So to answer "where is the agentic RAG?": it lives in the middle of a spectrum. At one end, a 
static pipeline nobody would call agentic; at the other, a full agent nobody bothers to call RAG. 
"Agentic RAG" names the transitional region — retrieval-centric systems where the LLM has been 
given partial control of the retrieval process but the system's identity is still "answers questions 
over a corpus" rather than "does things in the world." You're right that it's not a third kind 
of thing; it's a waypoint between two kinds, named from the perspective of people who started at 
the RAG end.

== References
[1] "Engineering Closed-Loop Graph-RAG Systems", 
https://dzone.com/articles/graph-rag-closed-loop-retrieval-reasoning

