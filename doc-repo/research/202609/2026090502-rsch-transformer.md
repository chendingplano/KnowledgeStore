## 1. Overview - Transformer

### 1.1 What Is a Transformer?
At the core of a Transformer is **self-attention**.

Suppose the input is:

> `The bank approved the loan`

After tokenization, imagine:

```text
The | bank | approved | the | loan
```

A Transformer creates a contextual representation (a vector) for every token. Self-attention lets one token use information from other tokens when constructing that representation.

For `bank`, for example:

```text
              ┌──── The
              │
              ├──── approved
bank ─────────┤
              ├──── the
              │
              └──── loan
```

Seeing `approved` and `loan` helps the model represent `bank` as a **financial institution**, rather than a river bank.

That's one of the central ideas behind Transformers: **tokens dynamically exchange information through attention**.

In other word, transformer converts input to vectors (transforms) that contain the 'semantics' of
the inputs, not just converting strings from one form to another form.  

### 1.2 Where directionality enters

Consider:

> `The bank approved the loan`

When the Transformer computes the representation of `bank`, which tokens is it allowed to look at?

There are two major possibilities.

### Causal/unidirectional attention

A GPT/Llama/Qwen-style generative model uses **causal attention**:

```text
The     bank     approved     the     loan
 │       │          │          │       │
 ▼       ▼          ▼          ▼       ▼

The
The ← bank
The ← bank ← approved
The ← bank ← approved ← the
The ← bank ← approved ← the ← loan
```

More precisely:

```text
"The"       can see: The
"bank"      can see: The, bank
"approved"  can see: The, bank, approved
"the"       can see: The, bank, approved, the
"loan"      can see: The, bank, approved, the, loan
```

`bank` **cannot see `approved the loan`**, because those tokens are to its right.

This restriction is deliberate.

Why? Because the model is trained to predict the next token:

```text
The bank approved the _____
                        ↓
                       loan
```

If `approved` were allowed to see `loan` while the model was being trained to predict `loan`, that would leak the answer.

This is why it's called **causal** attention.

---

### 1.3 Bidirectional attention
> **“Bidirectional” does not mean that the Transformer reads the input once left→right and once right→left.**

It refers to **which tokens each token is allowed to attend to**.

There are directional attention and causal attention.

A BERT-style encoder—and broadly the architecture underlying models such as GLiNER—doesn't need this causal restriction when encoding the supplied text.

Every token can attend to tokens on **both sides**:

```text
        ← ← ← attention → → →

The     bank     approved     the     loan
         ↑
         │
         ├── sees "The"
         ├── sees "approved"
         ├── sees "the"
         └── sees "loan"
```

So the representation for `bank` can immediately incorporate:

```text
left context:
    "The"

right context:
    "approved the loan"
```

That's what **bidirectional** means here.

It does *not* mean:

```text
pass 1: The → bank → approved → the → loan
pass 2: loan → the → approved → bank → The
```

Instead, conceptually it means:

```text
             all tokens
                 ↕
The ↔ bank ↔ approved ↔ the ↔ loan
                 ↕
             all tokens
```

In actual Transformer attention, these computations are heavily parallelized.

### 1.4 Why is bidirectional attention useful?

Because for **understanding an existing piece of text**, information after a word can be just as important as information before it.

Consider:

> `Washington signed the agreement.`

versus:

> `Washington imposed new sanctions.`

versus:

> `Washington is located in the Pacific Northwest.`

To classify `Washington`, the words **after it** may be critical.

For NER, suppose GLiNER needs to decide whether:

```text
Washington
```

is:

```text
person
location
organization/government
```

Bidirectional attention gives its representation of `Washington` access to the complete surrounding sentence.

That's excellent for:

* NER
* relation extraction
* classification
* semantic similarity
* embeddings
* extractive question answering
* other text-understanding tasks

These tasks generally have the **complete input available before inference begins**.

### 1.5 Why don't generative LLMs just use bidirectional attention?

Because generation creates a fundamental asymmetry.

Suppose an LLM has generated:

```text
The capital of France is
```

It needs to predict:

```text
Paris
```

There **is no future text yet**.

It can't look to the right because the right side is precisely what it's trying to generate.

Generation therefore naturally becomes:

```text
The
 ↓
The capital
      ↓
The capital of
          ↓
The capital of France
                 ↓
The capital of France is
                    ↓
The capital of France is Paris
```

Mathematically:

$$
P(x_1,x_2,\ldots,x_n)
=
\prod_{i=1}^{n}P(x_i\mid x_1,\ldots,x_{i-1})
$$

Each next token depends on previous tokens.

That's the fundamental reason decoder-only LLMs use causal attention.

### 1.6 More on Transformers

> GLiNER, GLiREL and LLMs are all transformers, but they are used for different purposes.

As a **high-level mental model**, that's useful. I'd refine it to:

```text
                         Transformer
                              │
               ┌──────────────┴──────────────┐
               │                             │
         Encoder-style                 Decoder-style
       / bidirectional                   / causal
               │                             │
        understand/classify             generate tokens
               │                             │
      BERT-like models              GPT / Llama / Qwen
               │
       specialized models
      such as GLiNER-style
        extraction models
```

The distinction isn't simply **“can generate vs cannot generate.”** Their **training objective, attention mask, architecture, and output head** are designed for different jobs.

GLiNER essentially wants to answer:

> Given the *whole text*, which spans correspond to these entity types?

A generative LLM wants to answer:

> Given everything I've seen so far, what token should come next?

## 1.7 A concrete example shows why GLiNER benefits

Suppose your SemOS document says:

> `The maximum response time shall not exceed 200 ms.`

GLiNER might be asked to identify:

```text
["metric", "unit", "product", "organization"]
```

When representing `response time`, bidirectional attention can directly use:

```text
             LEFT                       RIGHT
               ↓                          ↓
The maximum [response time] shall not exceed 200 ms
                     ↑
              representation
```

The right-hand context `shall not exceed 200 ms` is extremely useful evidence that `response time` is a **metric**.

A causal LLM processing the token `response` internally cannot use `200 ms` to construct that token's representation at that layer, because `200 ms` lies in its future.

Of course, a modern LLM can still solve the extraction task very well: once it has consumed the **whole prompt/document**, its later token representations contain information about everything earlier, and it can then generate an answer. But that's a less direct computational setup for extraction.

That's one reason encoder models remain attractive for specialized extraction: **when the whole input is already known and the desired output is classification/extraction rather than new prose, there's no intrinsic reason to impose the causal restriction required by generation.**

So the shortest definition I'd keep in mind is:

> **Bidirectional Transformer:** when encoding a token, attention can use context from both before and after that token.
>
> **Causal Transformer:** when encoding a token, attention can use only that token and earlier tokens.

That distinction is about **attention visibility**, not the physical direction in which text is fed into the model.
