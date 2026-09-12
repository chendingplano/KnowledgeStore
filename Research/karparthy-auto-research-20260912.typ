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
    "Research - Auto-Research"
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
  logical_name: "karparthy-auto-research",
  file_id: "2026091201",
  content_type: "research",
  document_date: "2026/09/12",
  keywords: [auto-research, testbot, self-improvement],
)

= Overview
The central idea of autoresearch is to let LLM randomly (controlled) modify
'programs', conduct an experiments, evaluate the changes, accept if it improves,
discards if not. Repeat either infinite, with maximum number of experiments,
a goal, or any meaningful termination condition.

Karparthy's original autoresearch is for machine learning:
- Prepare
- Modify `train.py` based on `program.md`
- Run the machine learning for a given time (5 minutes)
- Evaluate the results
- Accept (commit) or discard
- Repeat until finish

#figure(
   image("Images/image_2026091201.png", width: 100%),
   caption: [Kumar Autoresearch [2]],
)

== Recursive Self Improvement (RSI)
Recursive Self Improvement (RSI) is a hot topic today. I do believe the true
AI revolution should come from RSI. Karparthy's autoresearch is an RSI: it 
improves the target autonomously.

== Testbot
Testbot is another form of RSI:
- model.md describes the underlying model, the hyperparameters,
  how hyperparameters are changed, how to simulate real-world
- programs to run. Programs can be in any language: Python, Go, Java, etc.
  After settling the values of hyperparameters, it modifies the programs,
  generate inputs, generate expected results, etc.
- evaluate: this is a program to determine whether the test is successful
  or fail. If failed, it uses LLM to categorize failures. It generates a bug 
  report for each failure category (maximum N bug reports).
- Kick off a sub-agent for the next bug to fix the program. After that, 
  run the same inputs. If the bug is fixed, commit the code. Otherwise, repeat
  the fix until the bug is fixed or a maximum tries is reached. If it is the 
  latter, it fails the testbot. Human users may be involved or try a better model.
- Repeat the above until finish

== RSI, AGI and Beyhond
How to let LLMs drive the research or solve undeterministic problems? This is
a very important aspect of AI, or AGI.

Many people relate RSI to AGI. I am not sure whether AGI is a measureable
scientific term at all and there is no need to formly define what exactly 
is AGI. 

I think there will be no single turning point for AGI: once across that point,
we enter the AGI age. This is true for human intelligence, too. There are 
various experts in the real world. But we never bother to even mention the
concept of 'superman', or a person that is super good at everything. Such
a 'person' does not exist at all.

AGI, if we still want to use the term in its vague and fuzzy sense,
is a process, an evolution from less powerful to more powerful. 

This turns our attention to 'How to improve the machine intelligence'.

Facts about AGI:
- Must be able to continuously learning
- Must be very efficient to learn
- Must have a clear separation between 'knowledge' and 'thinking/reasoning'
- Knowledge MUST be accumulative
- Must have a built-in 'associative memory system'
- Must be able to learn from failure
- Must know how to accumulate experiences
- Must be able to 'the more to use, the smarter it becomes'

== References
[1] Karparthy Autoresearch, 
https://github.com/karpathy/autoresearch/tree/master

[2] Kumar Authresearch
https://ykumar.me/blog/eclip-autoresearch/
