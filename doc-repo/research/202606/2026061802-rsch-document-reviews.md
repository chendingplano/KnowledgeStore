# How to Review a Document

## 1. Treat the standards as a retrievable, clause-level index

Standards corpus is too large to stuff into context, and most of any document is 
irrelevant to most clauses. So:

- Chunk standards at the *requirement/clause* level, not by arbitrary token windows. Medical standards are already structured (sections → clauses → individual "shall/should" requirements). Preserve that structure as metadata: standard ID, version, section, clause ID, requirement type (mandatory vs. recommended).
- Index with **hybrid retrieval** — embeddings *plus* keyword/BM25. Pure semantic search misses exact identifiers that matter enormously in medicine: ICD/SNOMED codes, drug names, dosage units, standard numbers (e.g. ISO 13485, IEC 62304). Keyword search catches those; embeddings catch paraphrased concepts.

## 2. Decompose "review" into distinct check types

Each of the aspects is a *different* operation with a different prompt and often different retrieval:

- **Internal consistency** — contradictions *within* the document. No standards retrieval needed; you extract claims/values from the document and check them pairwise (e.g. dosage stated as 5mg in one section, 50mg in another).
- **Conflict with standards** — the document asserts something a standard forbids or contradicts.
- **Compliance / coverage** — a standard *requires* X; does the document address it, and adequately?

## 3. Make each check a classification, not open generation

This is the single biggest reliability lever. Instead of "what's wrong here," iterate over requirements and ask a constrained question:

> For requirement [clause text], does the document **satisfy / partially satisfy / contradict / not address** it? Cite the exact document span and explain.

Classification is far more reliable than free-form critique, easier to evaluate, and produces a clean compliance matrix. For conflict detection specifically, conflicts are pairwise — frame it as "does this document span contradict this clause?" rather than asking the model to hunt for conflicts in the open.

## 4. The review loop

Roughly:

1. Segment the document (by section, or better, by extracted claim).
2. For each segment, retrieve the top-k relevant standard clauses (hybrid search).
3. Run the relevant typed checks against those clauses.
4. Emit **structured findings** via JSON mode / function calling, with a fixed schema:

```json
{
  "finding_type": "conflict | compliance_gap | inconsistency",
  "severity": "critical | major | minor",
  "document_location": "section 3.2, para 1",
  "document_text": "<exact span>",
  "standard_ref": "ISO 13485:2016 §7.5.6",
  "standard_text": "<exact clause>",
  "explanation": "...",
  "confidence": 0.0
}
```

## 5. Ground everything and verify (non-negotiable for medical)

- **Every finding must cite its source** — the exact clause ID and the exact document span. A finding with no verifiable citation gets dropped automatically.
- **Add a verification pass**: a second LLM call (or a cheaper deterministic check) takes each finding and confirms the cited document text and cited clause actually say what the finding claims. This kills a large fraction of hallucinated "conflicts."
- **Keep a human in the loop.** The system *proposes* findings ranked by severity and confidence; a domain expert dispositions them. In a regulated domain you almost certainly need this for liability anyway.

## 6. The deliverable: a traceability matrix

The standard output in regulated/medical work is a **requirements traceability matrix** — every applicable requirement mapped to met / partial / unmet / not-applicable, with evidence pointing at the document location. That's far more useful and auditable than a prose review, and it falls out naturally from the classification approach above.

## 7. Measure it

Build a small labeled set — documents with known seeded issues (planted conflicts, omitted requirements) — and track precision and recall per check type. Without this you can't tell whether prompt changes help, and you can't trust the system. Watch recall on *missing* requirements especially; "didn't flag a real gap" is the most dangerous failure mode here.

---

A few practical notes: standards have *versions*, so pin which version a document is being reviewed against and store it in metadata. Not every standard applies to every document — add an applicability filter step before you waste calls checking irrelevant requirements. And reserve your strongest reasoning model for the classification/verification steps while using cheap models for embedding and retrieval.












## Traceability
Every finding is traceable to:

1. a specific passage in the reviewed document;
2. one or more applicable standard provisions;
3. an explicit reasoning chain or comparison;
4. a confidence and severity assessment.

## Check Items

* Compliance
* Missing mandatory requirements
* Conflicts with standards
* Incorrect terminology
* Incorrect thresholds or units
* Missing safety controls
* Missing documentation requirements
* Missing verification or validation procedures
* Outdated references
* Deviations from recommended practice

### Cross-standard review

* Two standards impose different thresholds
* A local regulation overrides an international standard
* A newer version supersedes an older version
* A general standard is constrained by a domain-specific one
* A mandatory rule conflicts with an informative recommendation
* Multiple provisions apply under different conditions

## Important extracted elements

For each provision, extract:

* actor or responsible party;
* required, prohibited, or recommended action;
* controlled object;
* applicability conditions;
* exceptions;
* numeric limits;
* units;
* deadlines or frequencies;
* evidence required;
* verification method;
* normative strength;
* dependencies on other provisions;
* source location;
* version and effective date.

# 3. Determine applicability before checking compliance

The most important step is often not compliance reasoning. It is determining **which standards and provisions apply**.

Before reviewing, construct a document context profile:

```json
{
  "document_type": "clinical laboratory procedure",
  "document_purpose": "blood sample handling",
  "organization_type": "hospital laboratory",
  "jurisdiction": ["United States", "Texas"],
  "medical_domain": ["laboratory medicine", "hematology"],
  "products": [],
  "processes": [
    "sample collection",
    "sample labeling",
    "sample transportation",
    "sample rejection"
  ],
  "intended_users": [
    "laboratory technicians",
    "nurses"
  ],
  "patient_population": ["adult", "pediatric"],
  "risk_level": "high",
  "effective_date": "2026-06-01"
}
```

Then retrieve candidate standards using this profile.

Applicability should be represented explicitly:

```json
{
  "standard_id": "STANDARD-A",
  "applicability": "applicable",
  "reason": "The document controls collection and transport of clinical specimens.",
  "confidence": 0.94
}
```

Possible values should include:

* `applicable`
* `partially_applicable`
* `possibly_applicable`
* `not_applicable`
* `insufficient_context`

Without this step, the LLM may accuse a document of violating provisions that were never applicable.

---

# 4. Convert the reviewed document into reviewable units

The input document should also be structurally parsed. Do not compare arbitrary 1,000-token chunks.

Extract elements such as:

* normative statements;
* procedures and steps;
* definitions;
* responsibilities;
* thresholds;
* warnings;
* exceptions;
* forms and required records;
* acceptance or rejection criteria;
* verification steps;
* references;
* claims about compliance.

A document requirement might be represented as:

```json
{
  "statement_id": "DOC-S4.2-P3-R1",
  "section": "4.2",
  "statement_type": "procedure_step",

  "actor": "laboratory technician",
  "action": "reject",
  "object": "unlabeled specimen",

  "conditions": [
    "specimen has no patient identifier"
  ],

  "source_text": "Unlabeled specimens must be rejected.",
  "source_location": {
    "page": 6,
    "paragraph": 3
  }
}
```


# 6. Use bidirectional retrieval

A good review requires two complementary retrieval directions.

## Standard-driven review

For every applicable provision:

```text
standard provision
    → retrieve document evidence
    → determine satisfaction
```

This detects omissions.

## Document-driven review

For every material statement in the document:

```text
document statement
    → retrieve relevant standard provisions
    → detect conflicts or constraints
```

This detects incorrect assertions that a checklist-based review might miss.

Both are needed. Standard-driven review has better coverage of requirements; document-driven review has better coverage of problematic content.

---

# 7. Retrieval should use more than vector similarity

A provision can be relevant even when it uses different wording. However, embeddings alone will also retrieve many provisions that are semantically related but not legally or technically applicable.

Use hybrid retrieval:

```text
candidate_score =
    semantic_similarity
  + terminology_match
  + entity_match
  + process_match
  + document_type_match
  + jurisdiction_match
  + applicability_match
  + graph_proximity
  + normative_priority
```

Apply hard filters where appropriate:

* effective version;
* jurisdiction;
* product category;
* medical specialty;
* document type;
* population;
* process;
* mandatory versus informative section.

Your existing category, artifact, scene, and relationship representations in SemOS can be useful here. A document passage and a standard provision may be connected through a process, medical product, measurement, role, or risk even when they share few words.

---

# 8. Make each finding a structured artifact

A review finding should not merely be prose.

```json
{
  "finding_id": "F-0027",
  "review_type": "compliance",

  "title": "Missing independent verification before result release",

  "status": "not_satisfied",
  "severity": "major",
  "confidence": 0.91,

  "document_evidence": [
    {
      "statement_id": "DOC-S8-P4",
      "quote": "The technician releases the result after completing the analysis.",
      "location": {
        "page": 14,
        "section": "8.4"
      }
    }
  ],

  "standard_evidence": [
    {
      "provision_id": "STD-A-7.3.2-R1",
      "quote": "...",
      "location": {
        "standard": "STD-A:2025",
        "section": "7.3.2",
        "page": 42
      }
    }
  ],

  "analysis": {
    "expected": "A verification step before release.",
    "observed": "The procedure moves directly from analysis to release.",
    "gap": "No verification actor, method, or record is specified."
  },

  "applicability_reason": "The procedure governs release of clinical results.",

  "recommended_action": "Add a documented verification step and identify the authorized verifier.",

  "verification_needed": true,

  "alternative_interpretations": [
    "Verification may be described in a separate referenced procedure that was not provided."
  ]
}
```

The field `alternative_interpretations` is important. It reduces false certainty and tells a human reviewer what additional evidence could resolve the finding.

---

# 9. Separate evidence from judgment

For each candidate issue, the LLM should execute three logically distinct stages.

## Stage 1: Evidence collection

Identify relevant passages without making a final judgment.

## Stage 2: Comparison

Construct a normalized comparison:

```json
{
  "expected": "...",
  "observed": "...",
  "difference": "...",
  "conditions_considered": [],
  "exceptions_considered": []
}
```

## Stage 3: Judgment

Classify the result, severity, confidence, and need for human review.

This separation makes the pipeline auditable and allows different models or deterministic validators to check each stage.

---

# 10. Add a verification pass

Every significant finding should be reviewed by a second pass that tries to disprove it.

The verifier should ask:

* Is the cited provision actually applicable?
* Is the quoted provision normative or informative?
* Was an exception overlooked?
* Is the document evidence incomplete?
* Is the requirement satisfied elsewhere?
* Are the two passages discussing different entities or conditions?
* Is the cited standard version current for the document date?
* Does the conclusion overstate the standard?
* Is the recommended correction itself supported?

The verifier should be given the candidate finding, surrounding document context, and complete provision context—not merely the selected sentences.

A useful outcome is:

```json
{
  "verification": "confirmed",
  "confidence": 0.88,
  "objections_considered": [
    "The requirement might be implemented in an external procedure."
  ],
  "remaining_uncertainty": "The referenced quality manual was unavailable."
}
```

Possible verifier results:

* `confirmed`
* `revised`
* `rejected`
* `requires_more_evidence`
* `requires_domain_expert`

---

# 11. Avoid unrestricted multi-agent reviewing

You could create agents called “compliance agent,” “consistency agent,” and “safety agent,” but the agent labels are not what makes the system reliable.

The important properties are:

* scoped task;
* bounded evidence;
* explicit output schema;
* deterministic retrieval;
* source citations;
* verification;
* coverage accounting.

A workflow of specialized, schema-constrained LLM calls is usually easier to test than autonomous agents talking to one another.

---

# 12. Measure coverage, not just the number of findings

A review that returns five good findings may still have examined only 10% of the applicable requirements.

Track:

```json
{
  "applicable_provisions": 186,
  "provisions_reviewed": 181,
  "satisfied": 126,
  "partially_satisfied": 17,
  "not_satisfied": 9,
  "not_addressed": 14,
  "unclear": 15,
  "review_coverage": 0.973
}
```

Also track document-side coverage:

* percentage of normative statements checked;
* percentage of numeric constraints checked;
* percentage of references resolved;
* percentage of sections included;
* unresolved external references;
* provisions skipped due to insufficient context.

This is much more meaningful than saying, “The LLM reviewed the document.”

---

# 13. Use a review plan before executing the review

The first LLM call should produce a review plan.

Example:

```json
{
  "document_classification": {
    "type": "clinical laboratory procedure",
    "domain": ["specimen handling"],
    "risk": "high"
  },

  "applicable_standard_sets": [
    {
      "standard_id": "STD-A",
      "applicability": "applicable",
      "relevant_sections": ["5", "7", "9"]
    }
  ],

  "review_dimensions": [
    "internal_consistency",
    "mandatory_requirements",
    "sample_identification",
    "transport_conditions",
    "rejection_criteria",
    "recordkeeping",
    "safety"
  ],

  "high_risk_topics": [
    "patient identification",
    "sample integrity",
    "result validity"
  ],

  "missing_context": [
    "organization jurisdiction",
    "referenced quality manual"
  ]
}
```

The plan controls subsequent retrieval and review calls.

---

# 14. Suggested SemOS pipeline

A practical end-to-end workflow would be:

```text
1. Ingest and structurally parse the document
2. Classify document type, domain, jurisdiction, processes, and risk
3. Generate an applicability profile
4. Select candidate standards and versions
5. Generate a review plan
6. Extract reviewable statements from the document
7. Run internal-consistency checks
8. Run standard-driven provision coverage
9. Run document-driven conflict searches
10. Run terminology and numeric checks
11. Run medical safety review
12. Consolidate duplicate findings
13. Verify each major or critical finding
14. Generate coverage statistics
15. Produce human-readable and machine-readable reports
```

Steps 7–11 can execute independently, but they should consume the same document model and applicability context.

---

# 15. Human-readable report structure

The final report could contain:

## Executive assessment

* document type and scope;
* standards reviewed;
* overall coverage;
* critical limitations;
* count of findings by severity.

## Critical and major findings

Each finding includes:

* issue;
* document evidence;
* standard evidence;
* reasoning;
* impact;
* suggested correction;
* confidence;
* human-review status.

## Minor findings

Terminology, clarity, references, formatting, and low-risk incompleteness.

## Requirement coverage matrix

| Provision | Applicability | Document evidence | Status              | Confidence |
| --------- | ------------- | ----------------- | ------------------- | ---------- |
| 7.3.2     | Applicable    | Section 8.4       | Partially satisfied | 0.88       |
| 7.3.3     | Applicable    | None found        | Not addressed       | 0.79       |

## Unresolved questions

* referenced documents unavailable;
* jurisdiction unknown;
* unclear product classification;
* conflicting standards requiring expert interpretation.

---

# 16. Medical-domain safeguards

Because these reviews may affect clinical or regulatory decisions, SemOS should enforce several rules:

* Never treat an LLM conclusion as a legal or regulatory determination.
* Distinguish standards, laws, regulations, guidance, and organizational policies.
* Preserve standard version, effective date, amendments, and jurisdiction.
* Distinguish normative sections from annexes and examples.
* Never infer compliance solely from absence of contradictory text.
* Route high-severity findings to qualified human reviewers.
* Record model version, prompt version, retrieval results, and timestamps.
* Treat missing referenced documents as unresolved evidence.
* Require direct source citations for every compliance finding.
* Prevent the model from inventing provision text or section numbers.

---

# 17. A concrete example

Suppose a procedure says:

> Blood specimens may remain at room temperature for up to six hours before processing.

SemOS should not directly ask, “Is this compliant?”

It should construct:

```json
{
  "entity": "blood specimen",
  "property": "maximum pre-processing time",
  "value": 6,
  "unit": "hour",
  "condition": "room temperature"
}
```

Retrieval might find:

```text
Provision A: Specimens for Test X shall be processed within two hours.
Provision B: Specimens may be stored for six hours when maintained at 2–8°C.
Provision C: The two-hour limit does not apply when Stabilizer Y is used.
```

The reasoning process then checks:

* Does the procedure apply to Test X?
* Is the sample at room temperature or refrigerated?
* Is Stabilizer Y used?
* Is the provision current and applicable?
* Does another section impose a shorter limit?

The finding might become:

```text
Potential conflict—major severity.

The document permits six hours at room temperature. Provision A requires
processing within two hours for Test X. The six-hour allowance in Provision B
applies only at 2–8°C. No use of Stabilizer Y was found.

Uncertainty: The procedure may cover specimen types other than Test X.
```

That is far more defensible than an unconstrained LLM answer.

---

## Recommended architectural principle

The central SemOS artifact should be a **review case**, not merely a generated report:

```text
Review Case
├── reviewed document version
├── applicability profile
├── standards and versions
├── review plan
├── extracted document statements
├── candidate provision mappings
├── findings
├── verification records
├── coverage metrics
└── human dispositions
```

This lets SemOS re-run only affected portions when:

* the document changes;
* a standard is updated;
* applicability information changes;
* a finding is corrected;
* the review methodology improves.

That incremental capability is especially important for your standards collection. SemOS should know not only which standards relate to a document, but also **which provisions support each finding and which findings must be reconsidered when a provision changes**.
