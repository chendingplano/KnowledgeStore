# Quick Reference

Link: ```url https://sitandr.github.io/typst-examples-book/book/basics/tutorial/markup.html```

| Command | Explanation |
|:---------|:-------------|
| = | Create headings |
| \ | New lines or escape symbols|
| // or /* ... */ | Comments |
| - | bullet list |
| + | numbered list |
| $...$ | formula |
| Content \<ref-xxx\> | Create an in-doc reference point |
| For xxx, refer to @ref-xxx | Reference to a reference point |

## Link
```text
#let a_001 = link(
    "<the-url>"
)[#text(fill: blue)[Label]]
```

## Table
```text
#table(
  columns: 3,
  align: left,
  [Name], [Description], [Documentation],
  [Bicep], [Microsoft], [Azure-specific],
)
```

## Figure
```text
#figure(
   image("Images/image_2026030101.png", width: 100%),
   caption: [Hardware setup (#a_030105)],
)
```

## Paragraphs
```text
#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)
```

## Quote
```text
#quote(block: true, attribution:[#a_008])[
"... having to discover it on their own. Both of those concerns are actually why LLMs.txt was a valuable idea, but it was the wrong implementation."
]
```

## Reference
Intra-File reference:
```text
= Introduction <sec:intro>

This is the intro section.

...

See @sec:intro for more details.
```

The same is true for figures:
```text
#figure(
  rect(width: 2cm, height: 2cm),
  caption: [A square]
) <fig:square>

Refer to @fig:square.
```