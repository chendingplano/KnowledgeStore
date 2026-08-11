# Document Processing Pipeline — User Manual

**Date:** 2026-08-11
**Audience:** ChenWeb end users — anyone who uploads documents and wants to understand what the system does with them
**Scope:** Plain-language explanation of every processing stage a document goes through, what it produces, and whether it's fully working today or still being built
**Applies to:** ChenWeb's document-processing pipeline (the "Doc Processor" service)

This manual assumes the system is *fully finished*, including parts that are still under construction, so you can see the complete picture the team is building toward. Every stage carries a **Status** note telling you what's actually true today. If the code changes after this manual is written, the code wins — treat dates and status notes here as a snapshot, not a promise.

---

## 1. What happens when you upload a document

When you upload a document to ChenWeb, it doesn't just get stored — it goes through a pipeline of automated processing stages that read it, understand it, and turn it into structured, searchable, comparable knowledge. Some of this happens to *every* document automatically. Some of it only happens if your organization has switched it on. Some of it only happens when the system decides it's actually needed for that particular document. And one stage — a full document review — only happens when you ask for it.

Think of the pipeline in four rough waves:

1. **Getting ready.** The document is split into workable pieces and its basic structure and identity (title, author, date, etc.) are figured out. This always happens, for every document, and everything else depends on it.
2. **Extracting and organizing.** A set of specialized stages read the prepared document and pull out different kinds of information from it in parallel — measurable specs, rules, summaries, topics, named things and their relationships, inventory items, and so on. Which of these run depends on your organization's configuration.
3. **Behind-the-scenes cleanup and knowledge-building.** After the extraction stages finish, the system reindexes what they found so it's searchable, and — where this part of the system is switched on — turns raw extracted facts into verified, cross-document-comparable knowledge.
4. **On demand.** A full multi-aspect document review, which you explicitly request rather than something that runs automatically.

This manual walks through every stage in that rough order, in plain language, with examples.

---

## 2. Reading the status notes in this manual

Every stage below ends with a **Status** line. It means one of these:

- **Available now** — this runs today, and you can expect to see its results.
- **Available now, but its output needs human sign-off first** — the stage runs today, but what it produces is a *candidate* sitting in a review queue, not yet an official, published fact. A curator/reviewer has to approve it first.
- **Available now, but switched off by default** — the code is built and works, but your organization has to explicitly turn it on. Ask your administrator whether it's enabled.
- **Available now, but only partly** — the stage runs, but today it only understands some of the inputs it's ultimately meant to handle. The rest is described here so you know what's coming.
- **Planned — not active yet** — described here so you understand where the system is headed, but nothing runs yet.

---

## 3. Pipeline at a glance

| # | Stage (as shown in status/dashboard views) | What it's for, in one line | When it runs | Status |
|---|---|---|---|---|
| 1 | `blocking` | Splits the document into large overlapping page groups so nothing gets lost at a seam | Always | Available now |
| 2 | `structure_analyzer` | Figures out what each line is — heading, paragraph, list, table, etc. | Always | Available now |
| 3 | `chunking` | Splits the document into small, searchable, topic-tagged pieces | Always | Available now |
| 4 | `extract_metadata` | Fills in the document's "cover sheet" — title, author, date, doc number... | Always | Available now |
| 21 | `facet_tier1` | Computes free, instant facts about the document's shape (page count, language, etc.) | Always, automatically | Available now |
| 22 | `facet_tier2` | Derives a few more facts from the cover sheet | Automatically, right after #4 | Available now |
| 20 | `classify_document` | Classifies the document into standard categories, using AI | Only when the system's routing rules need it | Available now, but only lightly used so far |
| 5 | `extract_metrics` | Pulls out measurable specs, limits, and targets | If enabled | Available now |
| 6 | `extract_provisions` | Pulls out rules, requirements, and their scope | If enabled | Available now |
| 8 | `generate_summaries` | Writes summaries at multiple zoom levels | If enabled | Available now |
| 9 | `generate_topics` | Tags content with subjects and files it into a topic tree | If enabled | Available now |
| 7 | `extract_semantic_projections` | Writes a short "what this passage is about" tag for search | If enabled | Available now |
| 10 | `generate_scene_blocks` | Turns described procedures/scenarios into structured mini-stories | If enabled | Available now |
| 11 | `extract_entity_relation` | Finds named things and how they relate to each other | If enabled | Available now |
| 12 | `extract_inventory_items` | Builds a de-duplicated parts/equipment catalog | If enabled | Available now |
| 16 | `extract_product_structure` | Turns confirmed "part of" relationships into a parts hierarchy | Automatically, after #11 | Available now, output needs sign-off |
| 14 | `extract_metric_definitions` | Harvests formal definitions of metrics into a shared glossary | Automatically, when routing calls for it | Available now, output needs sign-off |
| 15 | `extract_test_methods` | Harvests testing/measurement procedures and links them to metrics | Automatically, when routing calls for it | Available now, output needs sign-off |
| 17 | `normalize_assertions` | Rewrites raw extracted facts as precise, structured candidate statements | Automatically, after extraction finishes | Available now, but switched off by default and only partly wired up |
| 18 | `associate_semantics` | Verifies, reconciles, and formally accepts those statements as trusted facts | Automatically, after #17 | Available now, but switched off by default |
| 19 | `project_semantics` | Builds ready-to-use comparisons and views from accepted facts | Automatically, after #18 | Available now, but switched off by default |
| 13 | `review_document` | A full, multi-aspect AI critique of the document | You trigger it | Available now |

The `#` column is the stage's position in the system's internal pipeline table — it's here so the order matches what you'd see in the Doc Processor Dashboard if your organization exposes one (§12), even though this manual groups stages by *purpose* rather than by that internal order.

---

## 4. Getting the document ready (always runs)

These four stages always run, for every uploaded document, before anything else. You won't interact with them directly, but everything downstream depends on them working correctly.

### 4.1 Breaking documents into overlapping sections (`blocking`)

**What it does:** Before any deep analysis happens, a document needs to be broken into workable pieces. This stage groups the document's pages into large sections — and deliberately includes a few pages of overlap between neighboring sections, so that nothing which spans a page boundary (a sentence, a table, a procedure) gets cut off and lost when a later stage looks at only one section at a time.

**Example:** A 60-page manual might be split into sections of about 20 pages, each carrying 2 extra pages borrowed from its neighbor. A paragraph that starts on page 20 and finishes on page 21 — right at the seam between two sections — shows up intact in both, so nothing downstream ever sees half a sentence.

**Why it matters to you:** This is invisible plumbing — you'll never see "sections" anywhere in the interface — but it's what lets the pipeline handle very large documents reliably, without silently losing content at the seams.

**Status:** Available now.

### 4.2 Understanding the document's structure (`structure_analyzer`)

**What it does:** This stage reads every line of your document and decides what kind of content it actually is: a heading (and at what level), a normal paragraph, a bulleted or numbered list item, a table, a formula, a table-of-contents entry, a page footer, or a cover page. It works in two passes — a fast, rule-based pass that catches obvious patterns (like a line starting with "3.1" being a sub-heading), cleans up stray watermark text and scanning artifacts, and a smarter AI pass that resolves the ambiguous cases the rules can't, like telling apart a numbered heading from a numbered list item, or picking out which page is the cover.

**Example:** A line reading "3.1 Installation" gets corrected from a generic "heading" to a "level-2 heading." A block of dotted lines like "Safety Requirements ....... 12" gets labeled a table-of-contents entry, not a paragraph. Repeated watermark text like a website URL printed on every page gets recognized and discarded rather than treated as document content.

**Why it matters to you:** This is what builds your document's outline and is what powers any "document structure" view in the interface — it's the reason headings, tables, and lists are recognized as such instead of being treated as one undifferentiated wall of text.

**Status:** Available now.

### 4.3 Splitting content into searchable chunks (`chunking`)

**What it does:** Once the document's structure is understood, this stage slices it into smaller, roughly fixed-size pieces called chunks — each a few hundred words, with a little overlapping content carried between neighbors so context isn't lost at the boundaries. It's careful never to cut a table, formula, or list in half; those stay together as one chunk even if that makes the chunk a bit bigger than usual. Each chunk also gets automatically labeled with a short topic and keywords, and those labels are organized into a browsable category tree.

**Example:** A 200-page equipment manual is divided into dozens of chunks. A torque-specification table on page 45 stays fully intact in a single chunk rather than being split awkwardly across two. A 5-step installation procedure stays together in one chunk, tagged with a topic like "installation procedure."

**Why it matters to you:** This is the step that makes search and question-answering actually work. Instead of the system having to digest your entire document every time you (or an AI assistant) ask it something, it can jump straight to the handful of relevant chunks. Chunking is what turns a big, unwieldy document into small, retrievable pieces.

**Status:** Available now.

### 4.4 Filling in the document's cover sheet (`extract_metadata`)

**What it does:** This stage reads the first several pages of your document and uses AI to identify its basic facts: title, document/standard number, edition, authors or issuing organization, publish date, language, an abstract, keywords, and identifiers like an ISBN or DOI if present. It's the pipeline filling out a cover sheet for you automatically, instead of you having to type that information in by hand. If the first AI pass can't find everything it needs, it can look at more pages or fall back to a backup model.

**Example:** You upload a PDF of a residential building health-performance standard, written in Chinese. This stage scans the opening pages and extracts the title, the standard's document number, the drafting organization, and the publish date — and normalizes the detected language down to a simple code (`zh`) regardless of whether the source said "Chinese," "中文," or "zh-CN," so the rest of the system consistently knows what language it's dealing with.

**Why it matters to you:** This is what makes your document show up in the library with the correct title, author, and date filled in automatically — and what lets you filter or search your documents by author, document number, or language later.

**Status:** Available now.

---

## 5. Profiling and classifying your document

Before the system decides which optional extraction stages are worth running on your document, it builds up a quick profile of what kind of document it even is — starting with the cheapest, fastest checks and only reaching for AI when it genuinely needs to.

### 5.1 Free, instant document facts (`facet_tier1`)

**What it does:** Immediately after your document is parsed, the system computes a batch of small, objective facts about it — no AI involved, so it's essentially free and instant. Things like: how many pages, whether multiple languages are mixed together, how table-heavy or list-heavy the content is, how densely numbers appear together with units, whether there's a table of contents, how deep the heading structure goes, and roughly how many figures/diagrams it contains.

**Example:** A 40-page technical datasheet gets tagged with facts like: 40 pages, single language (English), high numeric-density (lots of numbers paired with units — a sign it's a specs-heavy document), moderate table density, and a 3-level-deep heading structure.

**Why it matters to you:** You won't see a dedicated screen for these facts, but they're what the system uses behind the scenes to decide how to handle your document — for instance, recognizing "this is clearly a dense technical spec sheet" without having to ask an AI model.

**Status:** Available now.

### 5.2 A few more facts from the cover sheet (`facet_tier2`)

**What it does:** Right after the cover-sheet stage (§4.4) identifies your document's title, number, issuer, and date, this stage derives a few more facts from that same information — clues about the issuing authority and the specific edition — again without any extra AI calls, just by reusing what was already found.

**Example:** Once the cover-sheet stage identifies the issuer as a national standards body and the document number follows that body's numbering convention, this stage records that authority association as a fact about the document.

**Why it matters to you:** Same as §5.1 — this is background enrichment that helps the system make better automatic decisions about your document, rather than something you interact with directly.

**Status:** Available now.

### 5.3 Classifying the document (`classify_document`)

**What it does:** Uses AI to read a sample of your document's early pages and assign it labels from a standardized, controlled vocabulary: what *kind* of document it is (e.g., a standard vs. a technical manual vs. a regulation), what *domain* it belongs to (e.g., medical devices, construction, food safety), whether it's mandatory or advisory, and which jurisdiction it applies to. Unlike most other stages, it doesn't run on every document automatically — it only runs when the system's routing rules need an answer to one of those questions and the cheaper facts from §5.1–5.2 aren't enough to answer it.

**Example:** A document whose issuer and structure already make it obvious it's a mandatory national standard might never need this stage — the cheaper facts already answer the question. A document with an ambiguous title and no clear issuer might trigger this stage, which reads the opening pages and concludes: document kind = "standard," domain = "medical devices," normative status = "mandatory," jurisdiction = "China."

**Why it matters to you:** This classification is what lets the system apply the right rules to the right documents later — for example, only comparing your document against other documents in the same domain and jurisdiction, rather than everything in the library indiscriminately.

**Status:** Available now, but has not yet been exercised against a large body of real documents — expect it to become more visible as more routing rules that rely on it are configured.

---

## 6. Pulling out facts and numbers

These two stages are usually what people mean when they say "extraction" — reading a technical or regulatory document and pulling structured facts out of the surrounding prose.

### 6.1 Extracting measurable specs (`extract_metrics`)

**What it does:** Reads through a document and pulls out every number that represents a measurable fact — a limit, a target, a range, a rate, a score, a specification — and turns each one into its own structured record (what's being measured, its value and unit, what it applies to, and exactly where in the document it came from). This is what lets the system later compare the same kind of measurement across many different documents, or notice when a document is missing a metric that similar documents usually cover.

After metrics are extracted, this doc processor will  harvestMetricDefinitionCandidates at the end of every run (extract-metrics.go:664), which loops the extracted metrics and, for each one whose formula_or_definition is non-empty, builds and inserts a term/metric_definition candidate into kb.ontology_candidates. It runs regardless of whether the separate extract_metric_definitions processor also ran. This is a genuine documentation gap: neither the capsule's §7.5 nor ADR 2026072901's processor table mentions it — both still describe kb.ontology_candidates as fed only by extract_metric_definitions/extract_test_methods.

**Example:** A technical standard states: *"The maximum permissible noise level shall not exceed 85 dB during nighttime operations."* This stage extracts that as a structured record: metric = noise level, value = 85, unit = dB, comparator = "shall not exceed," subject = nighttime operations, plus the exact line it came from.

**Why it matters to you:** This directly feeds any metrics detail view in document review (showing the document's title, section, and the subject/object of each metric), and it's the foundation for cross-document comparison — surfacing metrics your document explicitly states, and eventually flagging metrics that similar documents cover but yours doesn't.

**Status:** Available now.

### 6.2 Extracting rules and requirements (`extract_provisions`)

**What it does:** Identifies the actual binding statements in a regulatory or standards document — requirements, obligations, prohibitions, permissions, recommendations — separately from the surrounding explanatory prose. For each one, it records who or what it applies to, whether it's mandatory, and a plain description, so you can see "here are the actual rules in this document" without re-reading the whole thing.

**Example:** A regulation states: *"All hospitals with more than 50 beds must submit an annual safety report to the regional health authority by March 1st."* This stage extracts it as a rule record: type = mandatory, subject = hospitals with more than 50 beds, description = must submit an annual safety report, keywords = safety report, annual, health authority.

**Why it matters to you:** This produces the list of compliance-relevant rules shown in document review, cross-linked to any metrics, named things, or other facts found in the same passage — so you can jump from "this rule" to "the number this rule refers to" and back. Low-confidence extractions are flagged for a human to double-check rather than presented as certain.

**Status:** Available now.

---

## 7. Understanding and organizing the content

These stages don't extract discrete facts so much as they make the document as a whole easier to browse, search, and skim.

### 7.1 Multi-level summaries (`generate_summaries`)

**What it does:** Writes summaries of your document at multiple zoom levels. It first summarizes each small chunk, then summarizes groups of those summaries into a higher-level summary, and repeats the "summarize the summaries" process until there's a single top-level summary for the whole document — like a table of contents that gets progressively more zoomed out.

**Example:** A 200-page maintenance manual might get 60 chunk-level summaries, which get grouped into 12 section-level summaries, which get combined into 3 chapter-area summaries, and finally one whole-document summary — each carrying its own keywords, and an English translation if the source isn't in English.

**Why it matters to you:** This is what powers the document's summary card and any drill-down summary view — a quick read of what the document says without opening the whole thing.

**Status:** Available now.

### 7.2 Topic and subject tagging (`generate_topics`)

**What it does:** Figures out what subjects each part of your document is about and files them into a hierarchy of categories, the way a library assigns books to nested subject shelves — rather than just attaching flat keywords, it builds a category *path* (broad topic → narrower sub-topic) so related content across your whole document collection ends up organized under a shared, browsable structure.

**Example:** A passage about a vaccination-record system gets extracted as a topic with keywords like "vaccination records," "recipient data," "information system," filed under the category path `public_health`, and tagged with related concepts like "health management" and "disease prevention," each with its own confidence score.

**Why it matters to you:** After upload, your document's content becomes discoverable under the same subject categories as every other document about that topic — so someone browsing "public health" material would find your document even if they never searched for it by name.

**Status:** Available now.

### 7.3 Search tags for every passage (`extract_semantic_projections`)

**What it does:** For every slice of your document, writes a short, plain-language capsule of what that slice is *about* — a descriptive name, a handful of keywords, and a suggested spot in the same subject-category tree used by §7.2. Think of it as an automatic "smart tag plus one-line summary" for each part of the document, meant to make the document findable by *meaning*, not just exact wording.

**Example:** A passage discussing self-closing fire-door hardware requirements gets a tag like: name = "Fire door self-closing mechanism requirements," keywords = fire door, self-closing device, door hardware, filed under Safety → Fire Protection → Fire Doors.

**Why it matters to you:** This improves search results — your document surfaces for relevant meaning-based searches even when the exact words don't match — and it's what places passages under the right topic-browsing categories. It links back to the exact lines it came from, so you can jump straight to the source.

> Don't confuse this with **Project Semantics** in §10.3 — that's a different, later stage with a similar-sounding name that builds cross-document views from *verified facts*, not search tags for individual passages.

**Status:** Available now.

### 7.4 Scenario and procedure extraction (`generate_scene_blocks`)

**What it does:** Looks for self-contained "situations" a document describes — a workflow, an operating procedure, a failure scenario, a decision point, a monitoring routine, a compliance check, an interaction between people or systems — and turns each one into a structured mini-story: who's involved, what triggers it, what has to be true beforehand, what happens step by step, what could go wrong, and what the outcome is. It's aimed at documents that describe processes, not just static facts.

**Example:** A procedure manual states: *"If a pressure sensor reading exceeds the safe threshold, the operator must shut down the valve within 60 seconds and log the incident."* This becomes a scene: type = operating procedure, title = "Overpressure shutdown," actors = operator, pressure sensor; trigger = reading exceeds threshold; action = operator shuts down the valve; outcome = incident logged.

**Why it matters to you:** For procedure manuals, incident reports, or operational documents, this lets the system present "what actually happens in this document" as a structured workflow you can scan at a glance, instead of reading the full narrative text.

**Status:** Available now.

---

## 8. Mapping what's in the document

These stages build a map of the concrete "things" a document talks about — named entities, catalog items, and how they fit together structurally.

### 8.1 Named things and their relationships (`extract_entity_relation`)

**What it does:** Reads the document and pulls out two things: the named "things" it discusses (products, organizations, standards, components, systems, concepts — each with a type, a short description, and any alternate names), and the stated relationships between those things (what cites what, what contains what, what's required by what). It effectively turns unstructured prose into a browsable network — click on a named thing and see everything else it's connected to.

**Example:** A passage stating that a firefighter's breathing apparatus must be inspected under a particular standard produces two entities — "breathing apparatus" (type: equipment) and the standard's number (type: standard) — and a relationship connecting them: "breathing apparatus" *requires inspection under* the standard, each tagged with a confidence score and the exact source lines.

**Why it matters to you:** This gives you a structured, searchable map of what's mentioned in your document and how it connects — powering cross-references and related-item discovery, and feeding the parts-hierarchy stage below. Findings are automatically translated to English if the source document isn't in English.

**Status:** Available now.

### 8.2 Inventory and parts catalog (`extract_inventory_items`)

**What it does:** Scans the document for concrete, catalog-style items — parts, equipment, materials, consumables, software — the kind of things that could be purchased, stocked, installed, inspected, or replaced. For each one it captures the manufacturer, model/part numbers, specs with units, and where it was mentioned — then automatically merges duplicate mentions of the same item so it doesn't get listed five times just because it was named in five places.

**Example:** One real processing run found 143 raw mentions of items across a document and consolidated them into 33 distinct items plus 110 recognized duplicates — nothing was discarded, just merged, with each duplicate kept in an audit trail pointing back to the item it was merged into.

**Why it matters to you:** You get a clean, de-duplicated parts/equipment list extracted from your document, with specs and identifiers, and flags where required details (like a manufacturer or a spec value) are missing — useful for building catalogs, checking completeness, or feeding procurement and maintenance workflows.

**Status:** Available now.

### 8.3 Formal parts hierarchy (`extract_product_structure`)

**What it does:** A quiet cleanup step that runs automatically right after §8.1 finishes, with no additional AI call. It looks only at relationships that were already explicitly and clearly stated as "is part of" or "is a component of" — with both ends of the relationship already cleanly identified — and turns just those into candidates for a formal parts hierarchy (e.g., a product's breakdown into modules and sub-parts) and for linking clickable hotspots on product images to those parts. It never guesses or invents part/component relationships beyond what the document explicitly stated.

**Example:** If the document says *"the mask assembly consists of a lens, a seal ring, and a head strap,"* and §8.1 already captured lens, seal ring, and head strap as each being a component of the mask, this stage converts just those three relationships into structural candidates: Mask → Lens, Seal Ring, Head Strap.

**Why it matters to you:** Its output feeds a curated parts-navigation tree and image-hotspot map that a human reviewer checks before it becomes visible, official product structure — so a browsable parts tree or clickable product diagram shows up once approved, not immediately after upload.

**Status:** Available now; its output is a candidate awaiting reviewer sign-off before it becomes visible structure.

---

## 9. Building a shared vocabulary

The two stages in this section don't extract facts *about your specific document* so much as they harvest raw material for a shared glossary the whole system uses — a growing dictionary of formally defined terms (what "load" means, what units it's measured in, how it's tested) that lets facts from *different* documents, written by different authors in different words, be recognized as talking about the same underlying concept.

Everything these two stages produce is a **candidate** — a proposed dictionary entry sitting in a review queue. A human curator has to review and approve it before it becomes part of the system's official, governed vocabulary. Nothing these stages find becomes "official" on its own; that's a deliberate safeguard against bad or ambiguous AI-sourced content polluting a shared reference.

### 9.1 Metric definitions (`extract_metric_definitions`)

**What it does:** Looks specifically for places where a document formally *defines* a measurable concept — its name, its aliases, and what kind of value it takes (a number, a range, a pass/fail) — as opposed to §6.1, which grabs the actual numbers a document *reports*. Where a "Definitions" section states, for example, that "load (载荷) is the force applied to a structure, measured in kN," this stage proposes a candidate dictionary entry: term = load, unit = kN, alias = 载荷.

**Example:** Two different standards might both discuss a metric called "load" — one calling it 载荷 and giving it in kN, another calling it "applied force" and giving it in N. Once both are captured as candidate definitions and a curator reconciles them, the system can recognize they're the same underlying concept, expressed in different words and different units.

**Why it matters to you:** This is what eventually lets metrics from documents that use different terminology for the same idea be compared side by side, instead of being treated as unrelated just because the words don't match.

**Status:** Available now; its output is a candidate awaiting reviewer sign-off.

### 9.2 Test methods (`extract_test_methods`)

**What it does:** Looks for the testing or measurement procedures a document describes, and — where explicitly stated — which metric that procedure is used to measure (for example, "resistance to corrosion is measured using salt-spray testing per method X"). This builds a candidate map connecting metrics to how compliance with them is actually verified.

**Example:** A standard states that "surface hardness shall be measured according to Method B of the referenced test protocol." This stage proposes a candidate link: metric = surface hardness, measured by = Method B (referenced test protocol).

**Why it matters to you:** This is what eventually lets you ask not just "what does this spec require?" but "how is compliance with this spec supposed to be checked?" — useful when comparing documents that specify the same metric but different (or no) test methods.

**Status:** Available now; its output is a candidate awaiting reviewer sign-off.

---

## 10. Turning facts into verified, comparable knowledge

This is the most ambitious part of the pipeline, and the part most under active construction. When fully built, it's a three-stage translation pipeline that takes the raw facts every earlier stage extracted — measurable specs, rules, inventory items, named-thing relationships, and procedure descriptions — and turns them into a single, verified, comparable body of knowledge that spans your whole document library, not just one document at a time.

Here's the full, intended picture, followed by exactly what's true today.

### 10.1 Normalize assertions (`normalize_assertions`)

**What it does (full design):** Takes the raw facts already found by the earlier extraction stages — metrics, rules, inventory items, entity relationships, and scenario/procedure descriptions — and rewrites each one as a candidate **assertion**: a precise, structured statement in a common shape, something like *"For [this document/subject], [this metric] must be [this comparator] [this value] [this unit], under [this condition]."* This is the step that turns loosely-extracted, document-specific facts into something the system can line up and compare.

**Example:** §6.1 found "noise level ≤ 85 dB during nighttime operation" as a raw metric record. This stage rewrites it as a qualified assertion candidate: subject = nighttime operation, metric = noise level, comparator = ≤, value = 85, unit = dB — ready for the next stage to check.

**Why it matters to you:** This is the bridge between "facts we found in this one document" and "facts we can trust and compare across every document in the library."

**Status:** Available now, but with two important limits today. First, it's switched off by default — your administrator has to explicitly enable it system-wide. Second, even when enabled, it currently only knows how to translate metrics (§6.1) and rules (§6.2) — inventory items, entity relationships, and scenario/procedure facts are extracted, but not yet fed through this translation step. Support for those is planned but not yet built.

### 10.2 Associate semantics (`associate_semantics`)

**What it does (full design):** Takes the candidate assertions from §10.1 and does the actual verification work: checks that units and values make sense (converting between units, so that "60°C" and "140°F" are recognized as the same underlying value); resolves which shared glossary term (from §9) each assertion is really talking about, so that "noise level" in one document and "sound level" in another get matched to the same concept if they mean the same thing; flags direct contradictions between documents; and — once satisfied — formally accepts the assertion as a trusted fact, keeping a record of exactly which document and which sentence it came from.

**Example:** Continuing the noise-level example: this stage confirms "dB" is a valid unit for "noise level," resolves "noise level" to the shared glossary term for sound pressure level, checks the value doesn't contradict anything else already accepted about that same document/subject, and then commits it as an official, trusted fact with its source evidence attached.

**Why it matters to you:** This is the step that actually promotes a candidate into something the rest of the system — and you — can rely on as verified, not just "an AI thought it saw this."

**Status:** Available now, but switched off by default alongside §10.1 (the two are enabled together). Today's version does this verification deterministically (rule-based), not with additional AI judgment calls — an AI-assisted version is planned as a future addition, but it will only ever be allowed to *propose* candidates, never to accept them on its own.

### 10.3 Project semantics (`project_semantics`)

**What it does (full design):** Once assertions are formally accepted (§10.2), this stage builds the derived views that make that verified knowledge actually useful day to day — for example, pre-computed cross-document comparison tables, classification shortcuts, and search-ready summaries built directly from verified facts rather than raw extracted text. If new information changes an existing assertion, this stage also knows to mark the views that depended on it as stale and rebuild them.

**Example:** Once several documents' noise-level requirements have been accepted as verified assertions, this stage could pre-build a comparison view showing every document's nighttime noise limit side by side, already converted to the same unit — ready to display instantly instead of being recomputed on the spot every time someone asks.

**Why it matters to you:** This is intended to be the payoff of the whole knowledge-building pipeline — instant, reliable, cross-document comparisons and views, instead of you having to open several documents and compare numbers by hand.

> Don't confuse this with **Extract Semantic Projections** in §7.3 — that stage tags individual passages for search, within a single document; this stage builds derived views from verified facts, across many documents.

**Status:** Available now, but switched off by default alongside §10.1–§10.2, and — since it depends on accepted assertions existing in the first place — has nothing to build from yet given today's limited (metrics- and rules-only) assertion coverage. This is the part of the pipeline furthest from being visible to an end user today.

---

## 11. On-demand document review

### 11.1 Document review (`review_document`)

**What it does:** Unlike everything above, this stage doesn't run automatically — you choose to run it. You pick which of roughly 40 review checks to run, grouped into categories covering writing quality, document structure, content depth and correctness, internal consistency, technical/regulatory compliance, and housekeeping (version history, confidentiality markings, licensing, and so on). The system then uses AI to critique your document against those checks, optionally comparing it against reference documents you specify. Its standout ability is catching *absences* — a requirement, metric, or clause your document should contain but doesn't — not just flagging errors in what's already there.

**Example:** A grammar check flags a typo with a suggested fix. A compliance check, configured against two reference standards, compares your document's content against those standards' requirements and flags — as a "missing requirement" finding — a required test that the reference standards call for but your document never addresses. Each finding comes with a severity (high/medium/low), the supporting quote, its location, and a suggested fix.

**Why it matters to you:** You get a results dashboard with a live progress view while checks run, then a findings table (filterable by severity and category) you can accept, reject, defer, or auto-fix, plus a downloadable report with an executive summary and an overall assessment.

**Status:** Available now.

---

## 12. Where you see all this in ChenWeb

If your organization exposes the **Doc Processor Dashboard**, it shows every document's progress through the pipeline as a set of connected nodes:

- The four always-on stages from §4 are shown as a straight chain — only one is active at a time.
- The optional/routed stages from §5–§11 are shown fanning out below/after that chain — several can be running at once, since they don't depend on each other.
- Each node's color or badge shows whether it hasn't started yet, is currently running, finished successfully, failed, or was stopped.
- Mandatory stages (§4) are visually distinguished from optional ones (everything else), so you can tell at a glance what always happens versus what's configuration-dependent.
- Hovering over a node shows its details.

From the same dashboard, an administrator can **manually re-run** processing for a document — either all stages or a hand-picked subset — and can **stop** a document that's still processing. A separate view lists documents where at least one stage failed, so problems don't get lost.

If you don't see a dashboard like this, ask your administrator whether one is enabled for your account — not everyone gets operational visibility into the pipeline by default.

---

## 13. Frequently asked questions

**Why don't I see results from a stage described in this manual?**
Check the Status line for that stage first. It might be switched off by default (like the whole of §10), not yet configured as one of your organization's enabled optional stages (§6–§8), or the kind of stage that only runs when the system's routing rules decide it's needed (like §5.3, §9, or §10) rather than on every document.

**Can I make the system re-run just one stage?**
If your organization gives you or your administrator access to the Doc Processor Dashboard (§12), yes — you can hand-pick which stages to re-run on a document rather than reprocessing the whole thing.

**Will the system automatically compare my document against others?**
Not yet, in general. Cross-document comparison is the end goal of §10 (Turning Facts into Verified, Comparable Knowledge), which is built but switched off by default and currently only understands metrics and rules. Until it's turned on and expanded, comparisons across documents aren't automatic — though the individual extracted facts (§6–§8) are already there to support manual comparison.

**What's the difference between a "candidate" and an official fact?**
A candidate is something an automated stage proposed but a human hasn't reviewed yet — you'll see this language around §8.3, §9, and §10. An official/accepted fact is one that's passed review (whether an automated verification pass in §10.2, or an actual human curator for glossary terms in §9). This distinction exists specifically to keep AI-sourced content from silently becoming "official" without a check.

**Why do "Extract Semantic Projections" (§7.3) and "Project Semantics" (§10.3) sound so similar?**
They're unrelated stages that happen to share the word "semantic." §7.3 tags individual passages within one document for search. §10.3 builds cross-document comparison views from verified facts. If you're trying to figure out why your document isn't showing up in a comparison table, you want §10.3, not §7.3.

---

## 14. Glossary

- **Chunk** — a small, roughly fixed-size piece of a document (a few hundred words) that most extraction stages actually read and process; see §4.3.
- **Section/block** — a larger, coarser grouping of pages used only in the very first processing step; see §4.1. Don't confuse with "chunk."
- **Candidate** — a proposed fact, definition, or relationship that an automated stage found but that hasn't been reviewed/approved yet.
- **Curator / reviewer** — a human who reviews candidates (§8.3, §9) before they become official, governed content.
- **Assertion** — a verified, structured, comparable statement of fact, accepted after passing the checks in §10.2. The end product of the "turning facts into knowledge" pipeline.
- **Governed vocabulary** — the shared, curator-approved set of terms, categories, and definitions the system uses consistently across all documents, rather than each document's own wording.
- **Artifact family** — an internal grouping name for a *kind* of extracted output (e.g., "metrics," "provisions," "inventory items"); mentioned here only because you may see the term used in status/administrative screens.

---

## 15. Related documents

- `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` — the technical specification this manual is a plain-language companion to; the source of truth if this manual and the system's actual behavior ever disagree.
- `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` — the architecture decision record behind §9–§10 (the shared-vocabulary and knowledge-verification design), including its current build status in detail.
- `KnowledgeStore/doc-repo/adrs/202606/2026061801-adr-document-review.md` — the design behind §11 (Document Review).






2. Not quite — the generalized design is different in both table and mechanism. Per ADR 2026072901 §A.1, the path that extends to provisions/inventory_items/entity_relations is normalize_assertions (a Phase C post-process stage, DR8 Phase D stage 1): it deterministically converts each artifact family's already-persisted output — metrics, provisions, "later inventory/entity/scene" — into candidate qualified assertions, written to a different table, kb.semantic_decision_candidates (candidate_kind='assertion'), not kb.ontology_candidates. It's also currently inert (SEMANTIC_ASSOCIATION_ENABLED defaults false). kb.ontology_candidates is specifically for term/definition-level proposals; nothing in the ADR plans a provisions/inventory analog of extract_metric_definitions writing there. So expect provisions/inventory/entities to eventually feed kb.semantic_decision_candidates via normalize_assertions, not to grow their own extract_metrics-style inline harvest into kb.ontology_candidates.

4. No delete. CandidateStore.CreateCandidate (candidates_store.go:141) is a pure INSERT ... ON CONFLICT (fingerprint) DO NOTHING RETURNING .... There's no DELETE anywhere in that store or in extract-metric-definitions.go. Rerunning against source_record_id=416 re-attempts an insert for every mention found this run; ones matching an existing fingerprint are silently reused (existing row returned, no update, no duplicate); genuinely new fingerprints get new rows. It's "add only what's missing," enforced by a DB uniqueness constraint rather than explicit pre-checking or purge-then-reinsert.

5. fingerprint (fingerprint.go:17) — a SHA-256 hash over the canonicalized (re-marshaled, key-order-independent) proposed_payload JSON + source_type + source_ref + proposed_module_id, NUL-joined, enforced by UNIQUE(fingerprint). source_ref here is input_record:416 (document-level, not line-specific), so line spans and confidence are not part of the identity. Two rows are the same iff the full payload (term_id from the canonical name, definition, description, observable_property, quantity_kind, permitted_units, applies_to, aliases, value_type, range_type) plus source_type/source_ref/module all match exactly. Gotcha worth knowing: if the LLM's extracted definition wording drifts even slightly between reruns of the same document, the fingerprint changes and you get a new, separate row rather than an update — reruns can accumulate near-duplicates if extraction isn't perfectly stable. Also, buildMetricDefinitionCandidate hardcodes proposed_by = "extract_metric_definitions" regardless of whether extract_metrics's inline harvest or the real extract_metric_definitions processor created the row, so you can't use that column to tell which code path produced it.

I saved these findings to memory since they resolve a real doc/code gap and clarify a design question you'll likely hit again.