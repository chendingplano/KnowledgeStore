#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

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
    "Fact-Based Labeling"
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

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

#let frontmatter = (
  created: "2026/04/22",
  logical_name: "Fact-Based Labeling",
  file_id: "2026042201",
  file_type: "Typst",
  keywords: ["Fact-Based", "Labeling", "Knowledge Base", "Entity Extraction", "Capsule"],
  doc_time: "2026/04/22"
)

= Overview

*Stage 1: Fact Extraction (Observable Features)*

"When content is flagged, the classifier generates a structured set of observable, verifiable facts about the content. This is not a verdict or a risk score. It is a list of features — such as "contains mentions of specific pharmaceutical dosages" or "Includes a call to action for a financial transaction." Critically, these facts are generated per content vertical, ensuring the output is tailored to the specific review context."

*Stage 2: The Structured Questionnaire*

"The extracted facts are used to dynamically generate a targeted questionnaire. Instead of facing an open-ended "Review" button, the reviewer answers a sequence of specific, policy-grounded questions derived from the machine's observations."

*Stage 3: Policy Mapping and Feedback Loops*

"As reviewers respond, their answers map to specific policy identifiers. This produces an auditable decision record. More importantly, these structured decisions feed back into classifier training. The system learns from the reasoning (the facts), not just the result (approve/remove)."

*Summary by ChatGPT*

The article [“Solving the AI Accountability Gap: The Fact-Based Labeling (FBL) Framework”](https://dzone.com/articles/fact-based-labeling-framework?utm_source=chatgpt.com) argues that most AI moderation and governance systems fail not because classifiers are inaccurate, but because they are opaque. Traditional pipelines work like this: an AI model flags content, and then a human reviewer must interpret why it was flagged and how policy applies. The reviewer effectively performs an unstructured investigation between the machine output and the final decision. According to the author, this “black-box handoff” is the real accountability gap, because reviewers cannot easily verify, audit, or consistently reproduce decisions. ([DZone][1])

The proposed Fact-Based Labeling (FBL) framework changes the role of AI from “decision maker” to “fact extractor.” Instead of directly classifying content as harmful, fraudulent, or policy-violating, the system extracts observable and verifiable features from the content. Examples include statements like “contains pharmaceutical dosage information” or “includes a financial transaction request.” These extracted facts are intentionally descriptive rather than judgmental. The framework then uses those facts to guide human review. ([DZone][1])

One of the central ideas is the dynamically generated questionnaire. Rather than asking reviewers to make a vague overall judgment, the system generates targeted policy questions based on the extracted facts. For example, if the AI detects medical advice, the questionnaire may ask whether the dosage is presented as authoritative or whether it violates a specific policy section. This makes human review more structured and consistent. The questionnaire is therefore not merely a UI convenience; it becomes the mechanism that translates machine observations into auditable human reasoning. ([DZone][1])

The article also explains the architectural implications. Instead of relying purely on binary classifiers (“safe” vs. “unsafe”), the framework favors systems such as multi-label classifiers or Named Entity Recognition (NER) models that can output many policy-relevant attributes simultaneously. The included Python example demonstrates a middleware layer that takes model outputs, filters high-confidence features, maps them to a policy registry, and generates structured review tasks as JSON payloads. The policy registry acts as a “source of truth,” connecting extracted facts to policy codes and reviewer questions. ([DZone][1])

A particularly important point is the feedback loop. Traditional moderation systems typically learn only from the final decision (approve/remove). FBL instead captures the reasoning process itself: which facts were observed, which questions were answered, and how those answers mapped to policies. This creates a much richer training signal for future models and also improves auditability, regulatory compliance, and consistency across reviewers. In essence, the framework treats governance not as pure classification, but as a collaboration between machine-observed evidence and structured human judgment. ([DZone][1])

*Example*

Input content: “If you have a fever, take 1000 mg of ibuprofen every 2 hours. It works better than what doctors prescribe.”.1️⃣
Traditional approach might output:

```json
{
  "label": "unsafe_medical_advice",
  "confidence": 0.87
}
```

It did not explain Why is it unsafe? What exactly triggered it? Can a reviewer verify or challenge this? This is the accountability gap.

FBL Step 1: Extract Facts (NOT decisions). Instead of labeling, the system extracts observable facts:

```json
{
  "facts": [
    {
      "type": "medical_advice",
      "text": "take 1000 mg of ibuprofen every 2 hours",
      "confidence": 0.95
    },
    {
      "type": "dosage_information",
      "text": "1000 mg every 2 hours",
      "confidence": 0.92
    },
    {
      "type": "contradicts_professional_guidance",
      "text": "works better than what doctors prescribe",
      "confidence": 0.88
    }
  ]
}
```

These are verifiable, not judgmental.

FBL Step 2: Generate Questionnaire: Based on facts + policy registry, the system generates targeted review questions:

```json
{
  "questions": [
    {
      "id": "Q1",
      "question": "Does the content provide specific medical dosage instructions?",
      "related_fact": "dosage_information"
    },
    {
      "id": "Q2",
      "question": "Is the dosage potentially unsafe or exceeding recommended limits?",
      "related_fact": "dosage_information"
    },
    {
      "id": "Q3",
      "question": "Does the content discourage or contradict professional medical advice?",
      "related_fact": "contradicts_professional_guidance"
    }
  ]
}
```

Now the reviewer is guided, not guessing.

FBL Step 3: Human Review (Structured): Reviewer will answer:

```json
{
  "answers": [
    { "id": "Q1", "answer": "Yes" },
    { "id": "Q2", "answer": "Yes, exceeds safe limits" },
    { "id": "Q3", "answer": "Yes" }
  ]
}
```

FBL Step 4: Final Decision (Traceable): System maps answers → policy:

```json
{
  "decision": "remove",
  "policy_violations": [
    "MEDICAL_UNSAFE_DOSAGE",
    "MISLEADING_MEDICAL_ADVICE"
  ],
  "justification": [
    "Contains unsafe dosage recommendation",
    "Contradicts professional medical guidance"
  ]
}
```

== Fact-Based Labeling and SemOS

*FBL core idea:*

> Raw content → observable facts → structured questions → human/system judgment → auditable decision

*SemOS version:*

> Raw document → extracted knowledge units → schema-guided questions → derived understanding → explorable knowledge base

=== “Facts” Become SemOS Capsules 

In FBL, facts are observable statements like:

```json
{
  "fact": "The text contains a dosage instruction: 1000 mg every 2 hours",
  "confidence": 0.92,
  "evidence": "take 1000 mg of ibuprofen every 2 hours"
}
```

In SemOS, this becomes a general Evidence Unit or Knowledge Capsule ('Capsule' for short):

```json
{
  "id": "ku_001",
  "type": "provision",
  "text": "应在患者诊治及疫苗接种后3h内上报",
  "translation": "The incident should be reported within 3 hours after patient treatment and vaccination.",
  "source": {
    "document": "rabies_vaccination_standard.pdf",
    "page": 16,
    "lines": "244-246"
  },
  "attributes": {
    "modality": "mandatory",
    "deadline": "3h",
    "actor": "medical institution",
    "action": "report incident"
  },
  "confidence": 0.91
}
```

So instead of asking the LLM to directly “understand the document,” SemOS first asks it to extract
verifiable pieces of knowledge.

=== FBL questionnaire becomes SemOS schema-guided interrogation

In FBL, the questionnaire guides human reviewers.

In SemOS, questionnaires can guide extraction, validation, enrichment, and exploration.

Example for standards documents:

```json
{
  "questions": [
    "Does this text define a mandatory requirement?",
    "Who is responsible for the action?",
    "What action is required?",
    "Is there a deadline, threshold, condition, or exception?",
    "Which source lines support this interpretation?"
  ]
}
```

This is very useful because many document elements are not just “chunks.” They have hidden structure:

```text
9.3.2 发现犬只连续伤人事件，应在患者诊治及疫苗接种后 3h内上报。
```

The SemOS questionnaire extracts:

```json
{
  "is_requirement": true,
  "requirement_type": "mandatory",
  "trigger": "发现犬只连续伤人事件",
  "required_action": "上报",
  "deadline": "3h内",
  "condition": "患者诊治及疫苗接种后",
  "evidence_lines": ["9.3.2"]
}
```

=== Policy registry becomes SemOS ontology/schema registry

In FBL, a policy registry maps facts to policy rules.

In SemOS, this becomes capsule (ontology entities) registry:

```yaml
capsules:
  provision:
    fields:
      - modality
      - actor
      - action
      - condition
      - deadline
      - exception
      - evidence

  metric:
    fields:
      - metric_name
      - definition
      - unit
      - formula
      - threshold
      - measurement_method

  topic:
    fields:
      - category_path
      - keywords
      - summary
      - evidence
```

This lets SemOS avoid one giant generic extractor. Instead, it can say:

> “This block looks like a provision. Use the provision questionnaire and provision capsule.”

=== Final Decisions Become Derived Knowledge

FBL produces a moderation decision.

SemOS produces derived capsules, such as:

```json
{
  "derived_capsule": "reporting_requirement_for_consecutive_dog_injuries",
  "kind": "requirement",
  "summary": "Consecutive dog injury incidents must be reported within 3 hours after treatment and vaccination.",
  "depends_on": ["ku_001"],
  "confidence": 0.89
}
```

The derived capsule always links back to source evidence.

SemOS distinguishes:

1. Source text
2. Extracted facts
3. Derived capsules
4. Human/system validation
5. Trace links between all of them

=== FBL and DocGraph

A good SemOS graph could look like this:

```text
Document
  └── Block
        └── Knowledge Unit
              ├── Provision
              ├── Topic
              ├── Metric
              └── Entity
                    └── Derived Object
                          └── User-facing answer
```

*Example*

```text
rabies_standard.pdf
  └── section 9.3.2
        └── ku_001
              ├── topic: animal injury reporting
              ├── provision: report within 3h
              ├── condition: after treatment and vaccination
              └── derived object: consecutive dog injury reporting rule
```

FBL’s biggest value for SemOS is:

- Do not let the LLM jump directly from raw text to final knowledge.
- Force it to pass through observable, evidence-backed intermediate facts.

=== SemOS Pipeline

```text
Parse document
→ segment into blocks
→ classify block type
→ extract observable facts
→ run schema-specific questionnaires
→ create knowledge units
→ derive higher-level objects
→ store source links + confidence + validation status
→ expose everything through path-native exploration
```

A path-native SemOS view could then expose:

```text
/docs/rabies_standard/
  source.pdf
  docmap.md
  blocks/9.3.2.md
  facts/ku_001.json
  provisions/reporting_requirement_for_dog_injury.json
  graph.md
```
