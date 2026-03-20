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

= ChatGPT Visualizes Concepts

#let a_001 = link(
  "https://techcrunch.com/2026/03/10/chatgpt-can-now-create-interactive-visuals-to-help-you-understand-math-and-science-concepts/"
)[#text(fill: blue)[ChatGPT Can Now Create Interactive Visuals]]

Link: #a_001 \
Source: TechCrunch

The function is limited, mainly for formulas.

= Gemini Embedding 2 - Multimodel Embedding

#let a_002 = link(
  "https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-embedding-2/"
)[#text(fill: blue)[Google Multimodel Embedding]]

Link: #a_002 \
Source: Hacker News

This is a true multimodel embedding model, embeds text, images, videos, audios and documents
into a single, unified embedding space, and captures semantic intent across over 100 languages.
For Documents, it can embed PDFs directly up to 6 pages long.

It also understands interleaved input so you can pass multiple modalities of input
(e.g., image + text) in a single request.

```python
from google import genai
from google.genai import types

# For Vertex AI:
# PROJECT_ID='<add_here>'
# client = genai.Client(vertexai=True, project=PROJECT_ID, location='us-central1')

client = genai.Client()

with open("example.png", "rb") as f:
    image_bytes = f.read()

with open("sample.mp3", "rb") as f:
    audio_bytes = f.read()

# Embed text, image, and audio 
result = client.models.embed_content(
    model="gemini-embedding-2-preview",
    contents=[
        "What is the meaning of life?",
        types.Part.from_bytes(
            data=image_bytes,
            mime_type="image/png",
        ),
        types.Part.from_bytes(
            data=audio_bytes,
            mime_type="audio/mpeg",
        ),
    ],
)

print(result.embeddings)
```
