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

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

// #table(
//  columns: 3,
//  align: left,
//  [Name], [Description], [Documentation],
//  [Bicep], [Microsoft], [Azure-specific],
//
// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

= Overview

Given a hardware product, such as 'Electrical Motor', 'Microwave Oven', etc., this 
app builds a model for it. The model has:
- Component and Part List
- Metric List
- Standards
- Laws and Regulations
- Requirement List
- Packaging Requirements
- Storage Requirements
- Environmental Requirements
- Cost Model
- Supplier Chains

== Web Sites

- @snap_magic 

=== Blueprint

#let a_003 = link(
  "https://www.blueprint.am/"
)[#text(fill: blue)[BluePrint]]

#a_003 

It uses (I guess) LLMs to create a BOM for a given hardware module.
This is very close to what we want to do.

=== SnapMagic <snap_magic>

#let a_001 = link(
  "https://www.snapeda.com/"
)[#text(fill: blue)[SnapMagic]]

#a_001 

SnapEDA is an online platform used by electronics engineers to find and download
ready-to-use design data for electronic components—especially when designing
circuit boards (PCBs). It is "Google for electronic components (with read-to-use
CAD files)"

This website offers:

1. Search for electronic components
   - By part number (e.g., STM32, USB-C)
   - By specs or keywords

2. Download design files instantly
   - Symbols
   - PCB footprints
   - 3D models

3. Information:
   - Datasheets
   - Specs
   - Pricing and availability

*Related*:
- KiCad
- Altium
- Eagle
- Cadence

=== Ultra Librarian
<ultra-librarian>

- Very similar to SnapEDA
- Strong partnerships with component manufacturers
- Direct integration with tools like Altium, OrCAD
- Large library of:
  - Symbols
  - Footprints
  - 3D models

Often considered the #strong[closest competitor]

#line(start: (0pt, 0pt), end: (100%, 0pt), stroke: 0.8pt + gray,)

=== SamacSys (now part of Supplyframe)
<samacsys-now-part-of-supplyframe>

#let a_002 = link(
  "https://www.ultralibrarian.com/"
)[#text(fill: blue)[Ultra Librarian]]

#a_002

- Offers a #strong[Library Loader] tool

- Provides:

  - Symbols
  - Footprints
  - 3D models

- Strong integration with major EDA tools

👉 Very widely used in professional workflows

=== Digi-Key
<digi-key>

- Huge component catalog

- Some parts include:

  - CAD models
  - Datasheets

- Excellent filtering/search

👉 More “buy + spec” than “design library”

=== Mouser Electronics
<mouser-electronics>

- Similar to Digi-Key
- Strong manufacturer partnerships
- Sometimes links to SnapEDA / Ultra Librarian assets

=== GrabCAD
<grabcad>

- Massive community-driven 3D model library

- Includes:

  - Connectors
  - Enclosures
  - Mechanical parts

👉 Less reliable for PCB footprints, great for #strong[mechanical
integration]

=== TraceParts
<traceparts>

- Industrial-grade CAD library

- Strong in:

  - Mechanical + electromechanical parts

- Provides multiple CAD formats

=== KiCad Library
<kicad-library>

- Open-source
- Official libraries for KiCad
- Open-source and version-controlled
- High quality but:

  - Smaller than SnapEDA
  - Requires more manual work

=== EasyEDA Library
<easyeda-library>

- Open-Source
- Built into EasyEDA
- Large community-contributed parts
- Easy to use but quality varies

=== Octopart
<octopart>

- Search engine for electronic parts
- Often links to SnapEDA / Ultra Librarian
- Aggregates:

  - Pricing
  - Availability
  - Datasheets


Think: #strong[Google for components]

*Quick Comparison*
<quick-comparison>
#figure(
  align(center)[#table(
    columns: 3,
    align: (auto,auto,auto,),
    table.header([Platform], [Focus], [Best For],),
    table.hline(),
    [SnapEDA], [CAD library], [Fast PCB design],
    [Ultra Librarian], [CAD library], [Professional workflows],
    [SamacSys], [CAD + integration], [Tool integration],
    [Digi-Key / Mouser], [Distribution], [Specs + purchasing],
    [GrabCAD / TraceParts], [3D models], [Mechanical fit],
    [KiCad / EasyEDA libs], [Open-source], [DIY workflows],
    [Octopart], [Search engine], [Discovery],
  )]
  , kind: table
  )

