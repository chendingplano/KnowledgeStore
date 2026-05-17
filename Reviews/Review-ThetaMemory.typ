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
    "Review - δ-mem: Efficient Online Memory for LLMs"
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
  FileType: "typst",
  Source: "https://arxiv.org/pdf/2605.12357",
  ArtifactType: "Academic Paper",
  PublishDate: "2026/05/13",
  DocumentDate: "2026/05/17",
  Keywords: [Memory, LLM Memory, Memory Management],
)

= Overview
This paper, *“δ-mem: Efficient Online Memory for Large Language Models”*, proposes a lightweight memory architecture for LLMs aimed at solving a common problem in agentic and long-horizon systems: how to preserve and use historical information without endlessly expanding the context window. The core idea is to keep the transformer backbone frozen while attaching a compact *online associative memory* that continuously updates as the model processes information. Instead of re-feeding all prior context, δ-mem maintains a small state matrix that acts as compressed long-term working memory, allowing the model to “remember” past interactions more efficiently. ([Hugging Face][1])

Architecturally, δ-mem modifies attention rather than replacing it. The memory is updated using a delta-rule learning mechanism (a classical associative memory update rule), and its output is injected back into attention as a *low-rank correction*. This is an important design decision: rather than building a full recurrent architecture or adding explicit retrieval infrastructure (like RAG), the model augments standard attention with a learned memory state that remains fixed in size regardless of sequence length. Conceptually, this behaves like a tiny differentiable scratchpad that accumulates useful historical signals. The attractive property is computational efficiency: memory cost does not scale linearly with token history.

Experimentally, the paper reports strong gains, especially on tasks where persistent memory matters. δ-mem improves average benchmark performance over the frozen baseline by roughly 10%, and outperforms competing memory methods by around 15%. The biggest gains appear on explicitly memory-intensive benchmarks such as MemoryAgentBench and LoCoMo, suggesting that the mechanism is genuinely helping the model retain and reuse historical information rather than merely acting as regularization. At the same time, the paper claims general capabilities are largely preserved, meaning the added memory does not significantly degrade the original model’s broad competence. ([Hugging Face][1])

From a systems perspective, δ-mem is *not external knowledge retrieval* like RAG, nor filesystem exploration 
like Codex/Claude Code. It is closer to an *internal adaptive memory layer*—a mechanism for retaining recent 
learned state during interaction. Think of the distinction this way: *RAG retrieves facts from a corpus; 
exploration agents navigate files/tools; δ-mem remembers interaction history compactly inside the model’s 
computation itself.* That makes it especially useful for conversational agents, autonomous workflows, or 
multi-step reasoning where continuity matters, but less directly applicable to SemOS architecture unless 
combined with external retrieval. A plausible future hybrid would be: *Virtual FS + retrieval + 
graph traversal + δ-mem*, where retrieval provides facts and δ-mem provides persistent working memory 
across reasoning steps.

== "Keep Transformer Backbone Frozen"

“Keep the transformer backbone frozen” means: Do not modify the original LLM’s pretrained weights; 
only train or update the newly added memory components.

A modern LLM consists of the transformer itself—the big stack of layers containing:

- token embeddings
- self-attention projections (`Wq`, `Wk`, `Wv`, `Wo`)
- MLP/feed-forward layers
- normalization layers
- output head

This is the transformer backbone (the core pretrained model). “Frozen” means those parameters 
are treated as read-only. So during training:

- gradients are not computed for those weights
- optimizer does not update them
- the original model behavior remains mostly intact

Only the new δ-mem parameters are trainable.

Training or fine-tuning a full LLM is expensive. For a 70B model:

- full fine-tuning = update 70 billion parameters
- huge GPU memory
- expensive optimizer states
- slower training
- risk of catastrophic forgetting

If δ-mem adds, say, a few million parameters, it will be much cheaper, faster, easier to deploy, 
preserves original capabilities.

This is similar in spirit to LoRA, adapters, prefix tuning, prompt tuning, etc., except δ-mem adds 
memory behavior, not just task adaptation.

To better understand this, imagine GPT as a highly trained employee. Full fine-tuning means retraining
the employee’s entire brain. Frozen backbone + δ-mem leaves the employee’s knowledge untouched, 
but give them a smart notebook that learns what matters while they work. The results:

- The employee stays the same.
- The notebook improves memory.

Instead of changing standard attention:

```text
Attention(Q,K,V)
```

they effectively do:

```text
Attention(Q,K,V) + MemoryCorrection
```

where normal transformer weights stay fixed. Only the memory module learns how to store useful information,
retrieve relevant history, and inject corrections into attention. The pretrained LLM remains unchanged, 
but gets an attachable memory extension.

Note that “Frozen” refers to parameter learning, not runtime state. Even if weights are frozen, 
runtime state can still change.

Example:

- KV cache changes every token
- recurrent hidden state changes
- δ-mem memory matrix changes online

So:

- weights = fixed
- memory state = dynamic

This distinction is critical.

Most (if not all) memory management systems, such as the one used in Codex, Claude Code, etc., do not 
change the weights. They treat memories in form of 'relevant information', similar to RAG, except that 
RAG retrieves relevant information from corpus while memory retrieves relevant information from chat history. 
In this regard, it appears there are no differences between δ-mem memory and other memory systems.

At a high level, there are two fundamentally different notions of “memory” in LLM systems:

1. Retrieval memory (external memory) → retrieve past information as text
2. Parametric/stateful memory (internal memory) → encode past information into model state

Codex / Claude Code / RAG systems are mostly in category (1). δ-mem is category (2). These systems typically do:

```text
Past interactions / files / notes
        ↓
memory retrieval
        ↓
select relevant snippets
        ↓
inject as prompt/context
        ↓
LLM reasons over text
```

If a user asks: "Continue fixing the PostgreSQL migration bug we discussed yesterday.", memory system retrieves:

```text
Yesterday:
- migration failed because search_path missing
- affected schema: kb
- failing SQL: UPDATE kb.inputs ...
```

Then feeds that back into the prompt. This is basically RAG over personal history.

δ-mem is, however, not retrieving text. δ-mem does NOT do this:

```text
search old conversations
retrieve snippets
append to prompt
```

Instead, past information is compressed into a learned matrix:

```text
M_t
```

Then future computation uses:

```text
Attention + f(M_t)
```

This means that the model does not “read” past text again. It consults encoded state. That is much closer to:

- recurrent neural nets
- differentiable memory
- associative memory

than to RAG.

*Claude/Codex memory*

If earlier you said: "My database password is abc123". Later the system might retrieve exact text:

```text
User previously said database password is abc123
```

and inject it. The model literally sees the sentence again.

In δ-mem, the sentence is processed once. The memory state changes numerically:

```text
M = M + Δ
```

Later the model does not retrieve the sentence. Instead the altered state influences 
generation.

Like:

> "some latent representation suggests database credential info was mentioned"

No explicit text retrieval. That is the fundamental difference.

== Train δ-mem?

Yes. This is the crucial part. δ-mem is NOT just a runtime cache. It contains trainable components.
The paper’s “frozen backbone” wording means: transformer weights frozen and δ-mem parameters trainable.

The model learns:

- what to store
- how strongly to update memory
- how to retrieve from memory
- how memory should influence attention

Without training, δ-mem would be just arbitrary math. In a sense, δ-mem implants a new hippocampus and train it.

== Runtime State vs Trained Parameters

There are actually TWO things in δ-mem:

*Trainable parameters*

These are learned once:

```text
W_write
W_read
W_update
projection matrices
```

These define memory behavior.

*Runtime memory state*

Changes per interaction:

```text
M_0 \rightarrow M_1 \rightarrow M_2
```

This is the actual remembered content. Equivalent to session state.

== References
[1]: https://huggingface.co/papers/2605.12357?utm_source=chatgpt.com "Paper page - δ-mem: Efficient Online Memory for Large Language Models"

