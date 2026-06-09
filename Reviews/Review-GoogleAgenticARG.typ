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
    "Review - Google Agentic RAG"
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
  logical_name: "Google Agentic RAG",
  file_id: "2026060801",
  source: "WeChat",
  content_type: "review",
  document_date: "2026/06/08",
  keywords: [Agentic RAG],
)

= Overview
*"Sufficient Context: A New Lens on Retrieval Augmented Generation Systems"* introduces a simple 
but powerful idea: when a RAG system fails, is the failure caused by the retriever not providing 
enough information, or by the language model failing to use information that was already available? 
The authors formalize this distinction through the concept of *sufficient context*—retrieved 
context that contains enough information for a human (or ideal system) to answer the question 
correctly. They develop a method to classify whether retrieved context is sufficient and then 
use this framework to analyze RAG behavior. ([OpenReview][1])

Using this lens, the paper studies a variety of state-of-the-art models, including GPT-4o, 
Gemini 1.5 Pro, Claude 3.5, Llama 3.1, Mistral, and Gemma. The results reveal two different 
failure modes. Large frontier models are generally very good at extracting answers when sufficient 
context is present, but they often continue to answer confidently even when the retrieved 
information is insufficient, leading to hallucinations. Smaller models, in contrast, frequently 
fail or abstain even when the necessary information is already available in the retrieved 
documents. This finding suggests that retrieval quality and reasoning quality must be evaluated 
separately rather than being lumped together under a single RAG accuracy metric. ([OpenReview][1])

The authors also identify an intermediate category of retrieval results that are not fully sufficient 
but are still helpful. In these cases, the retrieved documents provide partial evidence that improves 
the model's chances of arriving at the correct answer. This is an important observation because many 
existing RAG evaluations treat retrieval as either correct or incorrect. The paper argues that context 
utility exists on a spectrum, and partial information can meaningfully improve answer quality even 
when it does not completely solve the task. ([OpenReview][1])

Building on these insights, the paper proposes a *selective generation* approach. Instead of always 
producing an answer, the model first estimates whether the retrieved context is sufficient. If the 
context appears insufficient, the system is encouraged to abstain rather than hallucinate. Experiments 
show that this guided-abstention strategy increases the proportion of correct answers among the 
responses that the system chooses to provide, yielding improvements of roughly 2–10% across several 
model families. ([OpenReview][1])

For systems such as SemOS, this paper is particularly relevant because it argues that retrieval systems 
should not be judged solely by end-to-end answer accuracy. A retrieval layer should ideally expose not 
only documents but also a signal indicating *how sufficient the retrieved evidence is for answering 
the query*. In practice, this suggests storing and retrieving evidence with stronger provenance and 
coverage information, allowing the LLM to distinguish between "I found enough evidence to answer" 
and "I found related information but not enough to be confident." The paper's central contribution 
is therefore not a new retrieval algorithm, but a new evaluation and control framework that 
separates *retrieval sufficiency*, *reasoning capability*, and *hallucination management* into 
distinct components. ([OpenReview][1])

== Sufficient Context Autorater
One area that is mostly oversighted is whether the retrieved content has sufficient information
for the given question. If not, instead of ALWAYS generating answers, the LLM may abstain
instead of halluciating answers.

Google uses an LLM to determine whether the retrieved is sufficient by the following prompt:

```text
You are an expert LLM evaluator that excels at evaluating a QUESTION and REFERENCES.
Consider the following criteria:

Sufficient Context: 1 IF the CONTEXT is sufficient to infer the answer to the question and 0
IF the CONTEXT cannot be used to infer the answer to the question

Assume the queries have timestamp <TIMESTAMP>.

First, output a list of step-by-step questions that would be used to arrive at a label for the
criteria. Make sure to include questions about assumptions implicit in the QUESTION.
Include questions about any mathematical calculations or arithmetic that would be required.
Next, answer each of the questions. Make sure to work step by step through any required
mathematical calculations or arithmetic. Finally, use these answers to evaluate the criteria.
Output the ### EXPLANATION (Text). Then, use the EXPLANATION to output the ### EVALUATION (JSON)

EXAMPLE:
### QUESTION
In which year did the publisher of Roald Dahl’s Guide to Railway Safety cease to exist?

### References
Roald Dahl’s Guide to Railway Safety was published in 1991 by the British Railways Board.
The British Railways Board had asked Roald Dahl to write the text of the booklet, and
Quentin Blake to illustrate it, to help young people enjoy using the railways safely. The
British Railways Board (BRB) was a nationalised industry in the United Kingdom that
operated from 1963 to 2001. Until 1997 it was responsible for most railway services in Great
Britain, trading under the brand name British Railways and, from 1965, British Rail. It
did not operate railways in Northern Ireland, where railways were the responsibility of the
Government of Northern Ireland.

### EXPLANATION
The context mentions that Roald Dahl’s Guide to Railway Safety was published by the
British Railways Board. It also states that the British Railways Board operated from 1963 to
2001, meaning the year it ceased to exist was 2001. Therefore, the context does provide a
precise answer to the question.

### JSON
{"Sufficient Context": 1}

Remember the instructions: You are an expert LLM evaluator that excels at evaluating a
QUESTION and REFERENCES. Consider the following criteria:
Sufficient Context: 1 IF the CONTEXT is sufficient to infer the answer to the question and 0
IF the CONTEXT cannot be used to infer the answer to the question
Assume the queries have timestamp TIMESTAMP.
First, output a list of step-by-step questions that would be used to arrive at a label for the
criteria. Make sure to include questions about assumptions implicit in the QUESTION
Include questions about any mathematical calculations or arithmetic that would be required.
Next, answer each of the questions. Make sure to work step by step through any required
mathematical calculations or arithmetic. Finally, use these answers to evaluate the criteria.
Output the ### EXPLANATION (Text). Then, use the EXPLANATION to output the ###
EVALUATION (JSON)
### QUESTION
<question>
### REFERENCES
<context>
```

*Comments:* there are generally two ways to handle question-answering, or the ways of using
LLMs to solve problems. One is driven by agents and the other by LLMs. Agentic RAG is mostly
agent-driven. Coding assistants, such as Claude Code, Codex, etc., are LLM driven.

Agent-Driven means it is the agent that drives the process. In case of question-answering,
the Agent receives a request (a question), it uses LLMs to analyze the query, decompose
the query into multiple subqueries, as needed. Recursively retrieve-analyze cycle. In Google
case, it also evaluate sufficient context. Generating answers is only a function in this 
process that is determined by the agent.

In the LLM-driven model, there is also an agent, or more precisely, a Harness. It compses
a request, including the session history, the user's environment, including the knowledge
bases, the tools, how to search information, etc. It then passes it to LLM.

The LLM analyze the query to determine whether it has enough information. If not, the LLM
decides what to do next: search the knowledge base for the missing information, explore
the knowledge base (or the files), call a tool, use MCP to retrieve, etc.

After receiving the response, the LLM evaluate what it has at hand, whether it has sufficient
sufficient information to answer the question. If not, it repeats the above until
either it can't find sufficient information or it has sufficient information. In the latter,
it generates the answer. In the former, it may ask users questions to clarify something,
to interactively ask users for the missing information, etc.


== References
[1] "Sufficient Context: A New Lens on Retrieval Augmented ..."
https://openreview.net/forum?id=Jjr2Odj8DJ&utm_source=chatgpt.com 

