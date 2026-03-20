# 1. Overview

For standards/regulatory corpora, the system should not answer from “top chunks.”
It should answer from an **evidence path**:

```text
DOCMAP route
→ definition
→ scope
→ requirement
→ exception
→ amendment
→ grounded answer
```

That is the most reliable end-to-end flow for clause-heavy, cross-referenced repositories.

I can also turn this into a **swimlane diagram** or a **JSON workflow spec** next.

## 1.1 Workflow

```text
User Question
   │
   ▼
[1] Query Intake
   - classify intent
   - detect domain terms
   - detect target corpus/doc family
   - detect whether user wants: obligation, definition, applicability,
     exception, comparison, or change-over-time
   │
   ▼
[2] DOCMAP Routing
   - consult DOCMAP.md
   - identify authoritative document set
   - narrow to likely volumes / parts / subparts / annexes
   - apply authority + version policy
   │
   ▼
[3] Query Planning
   - decompose into subquestions
   - identify needed evidence types:
     definitions, scope, requirements, exceptions, amendments
   - produce retrieval plan
   │
   ▼
[4] First-pass Retrieval
   - BM25 / keyword retrieval
   - vector retrieval
   - heading/title retrieval
   - citation-target retrieval
   │
   ▼
[5] DocGraph Expansion
   - traverse from retrieved nodes to:
     parent sections
     referenced clauses
     defined terms
     exceptions
     amendments / superseding text
     related tables / annexes
   │
   ▼
[6] Evidence Normalization
   - extract clause text
   - preserve section hierarchy
   - attach metadata:
     doc id, version, authority, modality, effective date
   - deduplicate near-identical chunks
   │
   ▼
[7] Reasoning Graph Construction
   - build working graph for this query
   - connect claims to evidence
   - mark support / conflict / uncertainty
   - track evidence paths
   │
   ▼
[8] Answer Synthesis
   - produce direct answer
   - cite clause-level evidence
   - explain exceptions and scope limits
   - surface ambiguity where present
   │
   ▼
[9] Verification / Guardrails
   - check against authority order
   - ensure newer amendment not missed
   - ensure informative annex not mistaken for normative text
   - ensure definitions are applied consistently
   │
   ▼
[10] Final Output
   - answer
   - cited evidence path
   - confidence / uncertainty note
   - optional “documents consulted” summary
```

### 1.1.1 Query intake

Input example:

> “Does the current electrical safety standard require redundant shutdown signaling for offshore remote-control systems?”

The system first identifies:

* **intent**: requirement lookup
* **entities**: electrical safety, shutdown signaling, offshore, remote-control systems
* **question type**: obligation + applicability
* **time sensitivity**: “current” means latest effective version

Output of this stage might be:

```json
{
  "intent": "requirement_applicability",
  "topics": ["electrical safety", "shutdown signaling"],
  "entities": ["offshore remote-control systems"],
  "time_mode": "current",
  "needs": ["definitions", "scope", "requirements", "exceptions", "amendments"]
}
```

---

### 1.1.2 DOCMAP routing

The system consults `DOCMAP.md` to decide:

* which standards/regulations are authoritative,
* which families contain relevant clauses,
* which documents are normative vs explanatory,
* how to prioritize versions.

Example routing result:

```yaml
route:
  authoritative_docs:
    - IEC-XXXXX:2025
    - Offshore Safety Regulation Part 8
  supporting_docs:
    - Amendment A1
    - Definitions Annex
  likely_sections:
    - "scope"
    - "definitions"
    - "shutdown/control requirements"
    - "exceptions"
```

This prevents searching the whole corpus blindly.

---

### 1.1.3 Query planning

The planner turns the question into subquestions:

```text
SQ1: What does “remote-control system” mean in this corpus?
SQ2: Are offshore systems in scope?
SQ3: Is there a clause imposing redundancy for shutdown signaling?
SQ4: Are there exceptions, annex notes, or amendments modifying that rule?
```

This stage decides the retrieval sequence:

1. definitions,
2. scope,
3. requirement clauses,
4. exceptions/amendments.

---

### 1.1.4 First-pass retrieval

Use several retrieval modes in parallel:

* **BM25/lexical** for exact phrases like “shutdown signaling”
* **vector retrieval** for semantically similar language like “redundant trip path”
* **heading retrieval** for sections titled “Remote Shutdown” or “Safety Functions”
* **citation retrieval** for explicit section references like “see clause 8.4.3”

Typical output:

```text
Top candidates:
- Doc A §3.12 "Remote-control system"
- Doc A §1.2 "Scope"
- Doc A §8.4.3 "Shutdown signaling"
- Doc A Annex C "Exceptions for legacy installations"
- Amendment A1 §2 "Revision to clause 8.4.3"
```

---

### 1.1.5 DocGraph expansion

Now the graph earns its keep.

Starting from the initial hits, the system traverses edges such as:

* `DEFINES`
* `CONTAINS`
* `REFERENCES`
* `EXCEPTION_TO`
* `AMENDS`
* `APPLIES_TO`

Example expansion:

```text
§8.4.3 "Shutdown signaling"
   ├─ REFERENCES → §3.12 "Remote-control system"
   ├─ APPLIES_TO → Offshore installations
   ├─ EXCEPTION_TO ← Annex C §C.2
   └─ AMENDED_BY ← Amendment A1 §2
```

This is where a DocGraph beats flat chunk retrieval, because it can pull in:

* the exact definition needed to interpret the clause,
* the applicable scope language,
* the amendment that changes the clause,
* the exception that narrows the answer.

---

### 1.1.6 Evidence normalization

The retrieved material is normalized into evidence units.

Each unit should carry:

* exact text,
* document id,
* section/clause id,
* hierarchy path,
* version/effective date,
* modality label,
* authority score.

Example:

```json
{
  "evidence_id": "E17",
  "doc": "IEC-XXXXX:2025",
  "clause": "8.4.3",
  "path": ["Part 8", "Control Functions", "Shutdown Signaling"],
  "modality": "SHALL",
  "effective_date": "2025-07-01",
  "text": "... shutdown signaling shall be redundant ...",
  "authority": "normative"
}
```

For regulatory corpora, modality detection is important:

* **SHALL / MUST** = obligation
* **SHOULD** = recommendation
* **MAY** = permission
* **EXCEPT / UNLESS** = carve-out

---

### 1.1.7 Reasoning graph construction

The system builds a temporary **reasoning graph** for the live question.

Example:

```text
Claim C1: Offshore remote-control systems are in scope
  supported by:
    E2 = Scope clause
    E5 = Definition of offshore installation

Claim C2: Redundant shutdown signaling is required
  supported by:
    E17 = Clause 8.4.3 (SHALL)
    E21 = Amendment A1 confirms revised wording

Claim C3: Legacy systems may be exempt in a narrow case
  supported by:
    E30 = Annex C.2 exception
  constrained by:
    E31 = Annex applicability note
```

This graph lets the system distinguish:

* direct support,
* indirect support,
* conflicting language,
* unresolved ambiguity.

---

### 1.1.8 Answer synthesis

Now the LLM generates the answer using the reasoning graph, not raw chunks alone.

A good synthesis should include:

1. the direct answer,
2. scope conditions,
3. exceptions,
4. version context,
5. citations.

Example output style:

```text
Yes — in the current authoritative text, redundant shutdown signaling is required
for offshore remote-control systems, provided the installation falls within the
scope defined in §1.2 and the term “remote-control system” is interpreted as
defined in §3.12. The obligation appears in §8.4.3 using SHALL-language.
However, Annex C.2 introduces a limited exception for certain legacy installations,
and Amendment A1 modifies the clause wording for post-2025 implementations.
```

---

### 1.1.9 Verification and guardrails

Before returning the result, run checks like:

* Did we use the **latest effective version**?
* Did we confuse **informative annex** text with **normative** requirements?
* Did we include the governing **definition**?
* Did we miss an **exception** or **superseding amendment**?
* Are there conflicting authorities across documents?

For standards/regulatory work, this step is essential.

---

### 1.1.10 Final output shape

A robust final response can be structured like this:

```yaml
answer:
  conclusion: "Yes, with a limited legacy exception."
  confidence: "high"

basis:
  - "IEC-XXXXX:2025 §8.4.3 imposes a SHALL requirement"
  - "§1.2 confirms offshore systems are in scope"
  - "§3.12 defines remote-control system"
  - "Annex C.2 provides a narrow exception"
  - "Amendment A1 modifies the current wording"

evidence_path:
  - "DOCMAP -> IEC-XXXXX:2025"
  - "Scope -> Definition -> Requirement -> Exception -> Amendment"

uncertainty:
  - "Applicability depends on whether the installation qualifies as legacy under Annex C.2"
```

### 1.1.11 Minimal pseudocode

```python
def answer_query(query, docmap, vector_index, bm25_index, docgraph):
    intent = classify_query(query)
    route = route_with_docmap(query, intent, docmap)

    subquestions = plan_query(query, intent, route)

    candidates = []
    for sq in subquestions:
        candidates += bm25_index.search(sq, route)
        candidates += vector_index.search(sq, route)
        candidates += retrieve_by_headings_and_refs(sq, route)

    expanded = graph_expand(
        seeds=candidates,
        graph=docgraph,
        edge_types=[
            "DEFINES", "REFERENCES", "EXCEPTION_TO",
            "AMENDS", "APPLIES_TO", "CONTAINS"
        ],
        depth=2
    )

    evidence = normalize_evidence(expanded)
    evidence = rerank_and_dedupe(query, evidence)

    reasoning_graph = build_reasoning_graph(query, evidence)
    draft_answer = synthesize_answer(query, reasoning_graph)

    verified = verify_answer(
        draft_answer,
        evidence,
        checks=[
            "latest_version",
            "authority_order",
            "normative_vs_informative",
            "exceptions_checked",
            "definitions_applied"
        ]
    )

    return format_output(verified, reasoning_graph, evidence)
```

### 1.1.12 Best practice for standards/regulatory corpora

The retrieval order should usually be:

```text
definitions
→ scope
→ primary obligation
→ exceptions
→ amendments / superseding text
→ related annexes / tables
```

That order matters because legal/technical meaning often depends on:

* what a term means,
* whether the subject is in scope,
* whether the obligation is modified elsewhere.

## One concrete example flow

```text
Question:
"Is encryption mandatory for remote telemetry under the current rail signaling standard?"

1. DOCMAP routes to:
   - Rail Signaling Standard 2026
   - Cybersecurity Annex
   - Amendment 2

2. Planner creates subquestions:
   - What is remote telemetry?
   - Is it in scope?
   - Is encryption mandatory?
   - Are there exceptions?

3. Retrieval finds:
   - Definitions §2.4
   - Scope §1.1
   - Security controls §9.7
   - Exception note Annex D
   - Amendment 2 revising §9.7

4. DocGraph expands:
   - §9.7 REFERENCES §2.4
   - Amendment 2 AMENDS §9.7
   - Annex D EXCEPTION_TO §9.7

5. Reasoning graph concludes:
   - telemetry is in scope
   - §9.7 says SHALL encrypt
   - Annex D exempts isolated maintenance channels only

6. Final answer:
   - Yes, mandatory in general
   - No, not for a narrow exempt category
   - cite §1.1, §2.4, §9.7, Annex D, Amendment 2
```

## 2. Evaluation

The critical part is the evaluation. We will use a pattern (such as pi-autoresearch) to do the following: 

Given a technical document, LLMs analyze the document to determine whether it clearly specifies: 
- The standards to flow 
- Which standard, the specific requirements (such as "the max pressure should not exceed xyz"), the corresponding section and page number of the requirement. 
- Check whether the doc misses any standard that is relevant to the doc. 
- Check whether the references are correct (assume my system has a rich set of full-searchable standards). 
- Pay special attentions to the metrics, such as the max/min working temperatures, pressures, speeds, size, etc. 

To evaluate, I am assuming that I should work out a few docs, identify all the related standards, the corresponding requirements/metrics, and where they should be referenced in the docs. Then run the loop.

Here’s an **end-to-end query flow** for a **DocGraph-based standards/regulatory corpus**.