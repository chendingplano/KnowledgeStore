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
    "Review - Prompt Optimizer"
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
  logical_name: "Prompt Optimizer",
  file_id: "2026060501",
  source: "Template",
  content_type: "review",
  document_date: "2026/06/05",
  keywords: [Prompt Optimization],
)

= Overview
The article “Engineering Patterns for 10x Resource Efficiency” argues that most organizations focus on model quality 
and capabilities while largely ignoring a major operational cost driver: token inefficiency. As AI systems move 
from experimentation into production, unnecessary token consumption becomes a hidden tax on both budgets and 
infrastructure. The author estimates that every million tokens saved can translate into meaningful cost 
reductions and lower environmental impact, making token efficiency an engineering concern rather than 
merely a financial one. ([DZone][1])

A central theme is that many AI applications waste tokens through poor prompt design, excessive context injection, 
and repeatedly sending information that the model does not actually need. Developers often include entire documents, 
conversation histories, logs, or metadata "just to be safe." While this may improve accuracy marginally, it frequently 
causes token usage to grow much faster than the business value generated. The article advocates conducting a baseline 
audit to identify where tokens are being consumed and whether each token contributes meaningful value to 
the outcome. ([DZone][1])

The article then presents a set of engineering patterns for improving efficiency. These include minimizing prompt 
verbosity, reducing redundant context, caching reusable information, summarizing long histories before reusing them, 
and selecting the smallest model capable of performing a task adequately. The idea is similar to traditional software 
performance optimization: rather than immediately purchasing more compute resources, engineers should first eliminate 
waste from the system. ([DZone][1])

Another important insight is that token costs are often nonlinear. As AI applications become more agentic, multi-step 
workflows can repeatedly reprocess growing conversation histories and intermediate outputs, causing token consumption 
to balloon unexpectedly. This aligns with a broader industry observation that the total cost of AI systems is driven 
not only by model pricing but also by workflow design, context management, and orchestration architecture. ([DZone][1])

The article's conclusion is optimistic: unlike model pricing, token waste is largely under the developer's control. 
By systematically auditing token usage and applying efficiency patterns, organizations can often achieve substantial 
reductions in operating costs without sacrificing output quality. The message is that AI cost optimization should be 
treated as a core engineering discipline, much like database optimization, caching, or network performance 
tuning. ([DZone][1])

For SemOS project, the article's lesson extends beyond prompt engineering. The emphasis on semantic projections, 
scene blocks, normalized knowledge objects, summaries, and retrieval structures can be viewed as a token-efficiency 
strategy. Instead of repeatedly feeding raw documents into an LLM, SemOS precomputes and organizes semantic 
representations so the model receives only the information needed for a task. In effect, you are trading storage 
and preprocessing for lower inference-time token consumption—a pattern very similar to the article's 
recommended engineering approach.

== Pattern 1: Make Prompts More Concise
#table(
  columns:3,
  align: left,
  [Aitn-Pattern], [Fix], [Token Savings],
  ["You are highly skilled ..." preambles], [Remove entirely - adds zero value], [30-50 tokens/request],
  ["Please carefully extract ..." polite requests], [Imperative: "Extract ..."], [about 40% of instruction tokens],
  [Unspecified output format], [Specify JSON explicitly], [Eliminates retry loops],
  [Multiple redundant examples], [One example or none (test which)], [Varies by templates]
)

== Pattern 2: Streaming with Early Termination

Streaming is not only for UX. It lets you inspect the partial answer while tokens are still being generated, 
then stop once the answer is “good enough” instead of paying for the full completion.

Conceptually:

```python
def stream_with_early_stop(prompt, query_type):
    buffer = ""
    tokens_generated = 0

    for chunk in client.stream(prompt):
        buffer += chunk
        tokens_generated += count_tokens(chunk)

        if tokens_generated >= 50:
            score = satisfaction_score(buffer, query_type)
            if score > 0.85:
                return buffer, tokens_generated

    return buffer, tokens_generated
```

What it does:

- Starts a streamed LLM response.
- Accumulates streamed chunks into `buffer`.
- Counts generated output tokens.
- Waits for a small grace period, here 50 tokens, so it does not judge too early.
- Calls `satisfaction_score(buffer, query_type)` on the partial answer.
- If the partial answer is probably sufficient, it returns immediately.
- If not, it keeps streaming until the model finishes.

In production, “return early” should also cancel/close the provider stream so generation 
actually stops server-side. Otherwise you may stop reading but still pay for continued 
generation depending on provider/client behavior.

This works best for factual/procedural questions, which the article also recommends starting with. 
It is risky for tasks where the end matters: code generation, legal analysis, long reasoning, 
summaries with conclusions, safety disclaimers, or anything that may be wrong if truncated.

Implementing `satisfaction_score(...)`

Implement it in layers, starting cheap and deterministic:

```python
def satisfaction_score(buffer: str, query_type: str) -> float:
    text = buffer.strip()
    if not text:
        return 0.0

    score = 0.0

    # 1. Enough substance
    word_count = len(text.split())
    if word_count >= 35:
        score += 0.20
    if word_count >= 60:
        score += 0.10

    # 2. Ends cleanly, not mid-thought
    if text.endswith((".", "!", "?", "。", "！", "？")):
        score += 0.20
    if text.lower().endswith(("and", "or", "because", "such as", "for example", ":")):
        score -= 0.25

    # 3. Query-type expectations
    if query_type == "procedural":
        if any(marker in text.lower() for marker in ["step", "first", "then", "finally", "1.", "2."]):
            score += 0.20
    elif query_type == "factual":
        if word_count >= 25 and text.endswith((".", "!", "?")):
            score += 0.25
    elif query_type == "definition":
        if any(phrase in text.lower() for phrase in ["is ", "refers to", "means"]):
            score += 0.20

    # 4. Penalize uncertainty / incompleteness
    uncertainty = [
        "i need more information",
        "cannot determine",
        "it depends",
        "not enough context",
        "as mentioned below",
        "the following",
    ]
    if any(p in text.lower() for p in uncertainty):
        score -= 0.20

    return max(0.0, min(1.0, score))
```

That is a decent first version, but for real use we need to make it more robust:

```python
def satisfaction_score(buffer, query_type, user_question=None):
    features = {
        "token_count": count_tokens(buffer),
        "sentence_count": count_sentences(buffer),
        "ends_cleanly": ends_at_sentence_boundary(buffer),
        "has_unfinished_list": has_unfinished_list(buffer),
        "has_uncertainty": has_uncertainty_phrases(buffer),
        "query_coverage": semantic_similarity(user_question, buffer) if user_question else 0,
        "type_completeness": query_type_completeness(buffer, query_type),
    }

    return weighted_score(features)
```

Practical scoring signals:

- *Completeness:* Does it contain a direct answer, steps, or final recommendation?
- *Clean ending:* Does it end at a sentence/list boundary?
- *Query coverage:* Does the partial answer semantically cover the user question?
- *No dangling structure:* Not ending after “First,” “For example,” “The key points are:”.
- *Low uncertainty:* Avoid stopping on “it depends” before the actual answer arrives.
- *Query-type rules:* A password-reset answer may be complete in 2 sentences; code generation almost never is.

Best production path:

1. Log full streamed answers and many partial prefixes: 50, 75, 100, 150 tokens.
2. Label each prefix: sufficient / insufficient / unsafe-to-stop.
3. Train a small classifier or calibrated logistic regression.
4. Use conservative thresholds first, e.g. `0.90`, as the article suggests for rollout.
5. Track false early stops, retries, user thumbs-down, and cost savings.

In other words: start with heuristics, collect labels, then replace `satisfaction_score` 
with a calibrated “would the user accept this partial answer?” classifier.

== Pattern 3: Context Pruning with Relevance Ranking
Formula:
```
  score = (0.6 x cosine) + (0.25 x BM25) + (0.1 x recency) - (0.05 x diversity_panelty)
```

The idea behind a *diversity penalty* is to avoid returning multiple results that are 
essentially the same thing.

Without it, a hybrid search system often returns results like:

```text
| Rank | Content                                                         |
| ---- | --------------------------------------------------------------- |
| 1    | Section 3.1 - Temperature Monitoring                            |
| 2    | Section 3.1 - Temperature Monitoring (slightly different chunk) |
| 3    | Section 3.1 - Temperature Monitoring (summary)                  |
| 4    | Section 3.1 - Temperature Monitoring (duplicate PDF)            |
| 5    | Section 4.2 - Alarm Requirements                                |
```

Although the top four results have high cosine similarity and BM25 scores, they provide very little additional information.

The diversity penalty reduces the score of documents that are too similar to already-selected documents.

Instead of ranking solely by query relevance:

```text
score(doc) = relevance(query, doc)
```

rank by:

```text
score(doc) =
    relevance(query, doc)
    - λ × similarity(doc, selected_docs)
```

where:

```text
similarity(doc, selected_docs)
=
max(
    cosine(doc, doc1),
    cosine(doc, doc2),
    ...
)
```

If a document is nearly identical to one already chosen:

```text
similarity = 0.95
```

then:

```text
diversity_penalty = 0.95
```

and the score is reduced.

Note that this algorithm needs to calculate the similarity of the
chunk-to-select and all the selected chunks. Calculating similarity is cheap than calling LLMs.
This algorithm is, thus, normally not a problem.


Example: assume:

```text
Query:
"temperature alarm requirements"
```

Candidate results:

```text
| Doc | Query Relevance |
| --- | --------------- |
| A   | 0.95            |
| B   | 0.92            |
| C   | 0.89            |
```

Document similarities:

```text
sim(A,B)=0.96
sim(A,C)=0.35
```

Without diversity:

```text
A = 0.95
B = 0.92
C = 0.89
```

Ranking:

```text
A
B
C
```

But B is almost the same as A.

With diversity:

```text
A = 0.95

B = 0.92 - 0.05×0.96
  = 0.872

C = 0.89 - 0.05×0.35
  = 0.8725
```

Now C slightly outranks B.

The system returns:

```text
A
C
B
```

giving broader coverage.

*MMR (Maximum Marginal Relevance)*

This is actually a simplified version of a well-known retrieval technique called:
*Maximum Marginal Relevance*

MMR computes:

```text
MMR =
λ × relevance(query, doc)
-
(1-λ) × similarity(doc, selected_docs)
```

For example:

```text
MMR =
0.7 × relevance
-
0.3 × redundancy
```

This is widely used in:

- RAG systems
- Search engines
- Recommendation systems
- Vector databases

For SemOS, we will not use a simple chunk-level diversity penalty.
SemOS have richer structures:

- Raw chunks
- Summaries
- Semantic projections
- Scene blocks
- Knowledge objects
- Documents
- Categories

We can penalize at multiple levels.

*1. Document Diversity*

If two chunks come from the same document:

```text
penalty += 0.2
```

to avoid retrieving 20 chunks from one standard.

*2. Topic Diversity*

If two topics come from the same document, penalize the second one:

```text
penalty += 0.2
```

*3. Scene Diversity*

If two results belong to the same Scene Block:

```text
Cold Chain Monitoring
```

penalize the second one.

This is often more useful than chunk diversity.

*4. Semantic Projection Diversity*

Suppose the query is:

```text
vaccine cold chain alarms
```

and retrieval finds:

```text
Alarm threshold
Alarm threshold summary
Alarm threshold metric
Alarm threshold provision
```

These are different objects but represent the same concept.

SemOS could detect that all four point to:

```text
Concept:
temperature excursion alarm
```

and apply a diversity penalty at the concept level.


Being a stronger approach, SemOS will replace `diversity_penalty` with `coverage_bonus`.
Instead of punishing duplicates, reward new information.

For example:

```text
final_score = relevance + coverage_bonus
```

where coverage is based on:

- new topic
- new scene
- new document
- new provision type
- new metric
- new entity

For a knowledge system like SemOS, maximizing semantic coverage is usually more 
valuable than maximizing raw similarity.

== Honest Failures

*1. Aggressive Response Caching*
"We thought caching responses for similar queries would save enormous tokens. In 
practice, cache hit rate was 4%. User queries are too diverse and too contextual. 
The overhead of maintaining the cache exceeded the savings. We killed it after two weeks."

*Comment*: Karpathy's LLM Wiki suggests: do not do it from scratch! If a request
was processed before, use it.

The 4% issue is real. Depending on the systems at hand, this number may vary significantly.

The 'caching', especially in the fashion of LLM Wiki, may be 'knowledge' itself.
This means that the more we use our knowledge base, the more knowledge we get.
This LLM generated knowledge is not purely extracted from the existing knowledge
base, but also the knowledge from LLMs.

We may not call it `caching`.

*2. Routing Everything to Smaller Models*
"We tried sending all requests to GPT-3.5 instead of GPT-4. Token costs dropped 90%. 
Retry rate increased 340% — because users weren't satisfied with initial responses. 
Paying for quality upfront is cheaper than paying for retries. Every time."

*Comment*: I 100% agree with it. We should normally detect query intent and
query complexity. A naive approach is to ask LLM to break a query into multiple
tasks. A better solution, the Harness solution, is to let LLMs drive.

*3. Blanket Token Limits Without Classification*
"Before per-request-type budgets, we tried a flat 500-token limit on everything. 
Users revolted. Code generation got cut off mid-function. Contract analysis was 
unusable. Intelligent limits beat arbitrary ones. Always classify first."

*Comment*: I won't do it at all.

== References
[1]: https://dzone.com/articles/hidden-cost-of-ai-tokens?utm_source=chatgpt.com "Engineering Patterns for 10x Resource Efficiency"

