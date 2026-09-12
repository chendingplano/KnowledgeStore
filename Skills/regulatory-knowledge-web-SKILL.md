---
name: regulatory-knowledge-web
description: Knowledge web expansion skill specialized for standards, laws, regulations, and similar technical/legal documents (e.g. ISO standards, GDPR, FDA regulations, building codes, industry specifications, compliance frameworks). Use this skill whenever a user asks about a regulation, law, standard, directive, code, or compliance requirement — including requests to "explain", "break down", "map out", "compare", "trace", or "deep dive" into any such document or provision. Also trigger for related terms: regulatory landscape, compliance mapping, legal traceability, normative reference, cross-reference, jurisdiction comparison, amendment history, enforcement mechanism. Builds a structured knowledge web covering the document's context, hierarchy, cross-references, obligations, enforcement, and evolution.
---

# Regulatory Knowledge Web

## Core Model

Each regulatory knowledge point is expanded across **6 dimensions** tailored to the nature of legal and technical documents:

| Dimension | Direction | Method |
|-----------|-----------|--------|
| **Horizontal Expansion** | Peer-level mapping | Equivalent standards in other jurisdictions, parallel regulations, competing frameworks, sibling provisions |
| **Vertical Drill-Down** | Hierarchical decomposition | Parent legislation → regulation → implementing rule → guidance note → technical annex |
| **Normative Context** | Origin and rationale | Legislative history, drafting intent, problem the rule was designed to solve, predecessor documents |
| **Cross-References & Dependencies** | Linkage web | Cited standards, incorporated documents, conflicting provisions, superseded versions |
| **Obligations & Enforcement** | Practical impact | Who must comply, duties imposed, prohibited acts, competent authority, penalties, audit triggers |
| **Evolution & Amendment** | Timeline of change | Version history, major amendments, planned revisions, sunset clauses, transitional provisions |

---

## Extended Capabilities

### Capability 1: Jurisdiction Comparison

When a regulation or standard has equivalents in other jurisdictions, build a comparison table:

```
## 🌐 Jurisdiction Comparison

| Jurisdiction | Instrument | Key Difference | Stricter / Lighter |
|--------------|------------|----------------|--------------------|
| EU           | [name]     | [delta]        | [assessment]       |
| US           | [name]     | [delta]        | [assessment]       |
| CN/JP/UK/... | [name]     | [delta]        | [assessment]       |
```

### Capability 2: Normative Reference Chain

When a standard or regulation cites other documents, trace the full reference chain:

```
## 🔗 Normative Reference Chain

[Root Document]
 └─ References → [Doc A] (mandatory)
      └─ References → [Doc A1] (informative)
 └─ References → [Doc B] (mandatory)
      └─ References → [Doc B1] (mandatory)
 └─ References → [Doc C] (superseded by [Doc C2])
```

Mark each reference as: `mandatory` | `informative` | `superseded` | `withdrawn`

### Capability 3: Obligation & Compliance Matrix

For any provision imposing duties, extract the structured obligations:

```
## ✅ Obligation & Compliance Matrix

| Obligation | Duty-Bearer | Trigger Condition | Deadline | Competent Authority | Penalty |
|------------|-------------|-------------------|----------|---------------------|---------|
| [Art. X]   | [who]       | [when/if]         | [by when]| [body]              | [sanction] |
```

### Capability 4: Amendment Timeline

For documents with a revision history:

```
## 📅 Amendment Timeline

| Version / Year | Key Change | Reason / Trigger | Impact |
|----------------|------------|-----------------|--------|
| [v1 / YYYY]    | [change]   | [event/pressure]| [effect] |
| [v2 / YYYY]    | [change]   | [...]           | [...]  |
| [Planned]      | [expected change] | [...]    | [...]  |
```

---

## Workflow

```
Input document/provision → 6-dimension expansion → sub-nodes expanded on request → structured output
```

### Step 1: Identify the Input

Determine the user's core subject:
- A specific article or clause (e.g., "GDPR Article 17")
- A whole instrument (e.g., "ISO 9001:2015")
- A concept within a regulatory context (e.g., "legitimate interest under GDPR")
- A compliance question (e.g., "FDA 21 CFR Part 11")

### Step 2: Disambiguate if Needed

If the input is ambiguous (common name, acronym shared by multiple instruments, or jurisdiction-specific term), **list all matches before proceeding** — see the "Multiple Instruments" rule below.

### Step 3: 6-Dimension Expansion

Produce output for each dimension that is relevant to the input. Not all dimensions apply equally to every input — use judgment:
- Legislative acts → all 6 dimensions
- Technical standards (ISO/IEC/ASTM) → prioritize normative references, compliance matrix, jurisdiction comparison
- Court decisions or guidance notes → prioritize normative context and evolution

### Step 4: Offer Recursive Drill-Down

At the end, ask the user whether to drill into any specific sub-node (a cited standard, a specific article, an enforcement mechanism, etc.).

---

## Output Format

### Multiple Instruments Rule (Important)

When the input name or acronym matches multiple instruments (e.g., "REACH" could be EU REACH Regulation or a US state analogue; "Part 11" could be FDA or another body), **list all matches and expand each separately**:

```
# [Input] — Multiple Instruments Found

> Found N matching instruments. Expanding each:

---

## ① [Full Name] — [Jurisdiction / Issuing Body / Year]

[Knowledge web content]

---

## ② [Full Name] — [Jurisdiction / Issuing Body / Year]

[Knowledge web content]

---
```

### Single Instrument Knowledge Web Format

```
# [Document Name / Provision] — Regulatory Knowledge Web

## 📋 Core Identification
- **Full Title**: [...]
- **Issuing Body**: [...]
- **Jurisdiction**: [...]
- **Current Version / In Force Since**: [...]
- **Status**: In force / Superseded / Under revision / Withdrawn
- **One-Line Summary**: [What it does and who it affects]

---

## 🔄 Horizontal Expansion
### Peer Instruments (same subject, other jurisdictions or bodies)
| Instrument | Issuing Body | Jurisdiction | Key Alignment | Key Divergence |
|------------|-------------|--------------|---------------|----------------|
| [A]        | [body]      | [place]      | [...]         | [...]          |
| [B]        | [body]      | [place]      | [...]         | [...]          |

### Competing / Alternative Frameworks
- [Framework A]: [brief description + when preferred over subject document]
- [Framework B]: [...]

---

## ⬇️ Vertical Drill-Down
### Document Hierarchy (top → bottom)
- [Enabling treaty / Primary legislation]
  - [Regulation / Standard]
    - [Implementing rule / Technical annex]
      - [Guidance document / Interpretive note]

### Key Internal Structure
| Part / Chapter / Annex | Scope | Normative? |
|------------------------|-------|------------|
| [Part I]               | [...]  | Yes / No   |
| [Annex A]              | [...]  | Yes / No   |

---

## 📜 Normative Context
- **Legislative History**: [When initiated, why, key events in drafting]
- **Problem Being Solved**: [The regulatory gap or risk the instrument addresses]
- **Predecessor Documents**: [What it replaced or amended]
- **Drafting Body / Committee**: [Working group, rapporteur, public consultation process]

---

## 🔗 Cross-References & Dependencies
### Normative References (documents this instrument relies on)
| Referenced Document | Type | Status |
|--------------------|------|--------|
| [Doc A]            | Mandatory | In force |
| [Doc B]            | Informative | Superseded |

### Documents That Reference This Instrument
- [Downstream Doc A]: [how it cites/incorporates subject document]

### Conflicting or Overlapping Instruments
- [Instrument X]: [nature of overlap / conflict resolution rule]

---

## ✅ Obligations & Enforcement
### Who Must Comply
- [Entity type A]: [specific obligations]
- [Entity type B]: [specific obligations]

### Key Obligations Summary
| Obligation | Article / Clause | Trigger | Deadline | Penalty / Consequence |
|------------|-----------------|---------|----------|-----------------------|
| [duty]     | [ref]           | [when]  | [by]     | [sanction]            |

### Competent Authority / Enforcement Body
- [Body]: [powers, jurisdiction, enforcement tools]

### Audit / Inspection Triggers
- [Trigger condition → enforcement action]

---

## 📅 Evolution & Amendment History
| Version | Date | Key Change | Driver |
|---------|------|------------|--------|
| [v1]    | [YYYY] | [change] | [event/pressure] |
| [v2]    | [YYYY] | [change] | [...]  |
| **Planned** | [ETA] | [expected revision] | [...] |

### Transitional Provisions
- [Grace periods, phased-in dates, grandfather clauses]

---

## 🌐 Global Context (for instruments with international significance)
When the document was issued during or in response to a significant period, add the broader context:

| Domain | Event / Development | Relevance to This Instrument |
|--------|--------------------|-----------------------------|
| Regulatory | [contemporaneous regulatory event] | [connection] |
| Technology | [tech development that drove/shaped the rule] | [connection] |
| Political / Trade | [geopolitical event] | [connection] |
| Industry | [sector development] | [connection] |

---

## ⚠️ Known Compliance Pitfalls & Grey Areas
| Issue | Provision | Common Misinterpretation | Authoritative Guidance |
|-------|-----------|--------------------------|------------------------|
| [issue] | [ref]   | [what people get wrong]  | [official position, if any] |
```

---

## Expansion Principles

1. **Provision-level resolution**: A regulation is only as useful as its specific articles — always offer to drill into individual provisions after the top-level web.
2. **Jurisdiction awareness**: The same concept (e.g., "data controller") may carry different definitions across legal systems — note divergences explicitly.
3. **Normative vs. informative**: Always distinguish between mandatory requirements and advisory guidance; mark annexes and referenced documents accordingly.
4. **Version discipline**: Regulatory work is version-sensitive; always note which version or edition is being discussed and flag if a newer one exists.
5. **Enforcement realism**: Rules without enforcement are aspirational — always map the competent authority, penalty regime, and known enforcement track record.
6. **Follow the reference chain**: Standards cite other standards; regulations incorporate other regulations by reference — trace at least two levels deep.
7. **Conflict awareness**: Overlapping instruments from different bodies (e.g., ISO vs. national body, EU vs. US) create compliance complexity — surface conflicts explicitly.
8. **Temporal precision**: Transitional periods, phase-in dates, and sunset clauses are operationally critical — include them.

---

## Quality Requirements

- **Disambiguation first**: If input matches multiple instruments, list all before expanding any.
- Use tables for horizontal comparison (at least 3 peer instruments where they exist).
- Vertical drill-down covers at least 3 hierarchy levels (primary legislation → regulation → implementation detail).
- Normative context includes the regulatory problem being solved and the predecessor document.
- Cross-references distinguish mandatory from informative, and flag superseded documents.
- Obligations matrix specifies duty-bearer, trigger, and penalty for every key obligation.
- Evolution table covers all significant versions; note planned revisions if publicly known.
- **Always state the version/edition** at the top of the web.
- **End every web** by asking whether the user wants to drill down into a specific provision, reference, or jurisdiction.
- **Compliance pitfalls**: For any instrument with complex or contested provisions, include at least one known grey area or common misinterpretation.

---

## Usage Examples

**Input**: "GDPR Article 17"
→ Horizontal: CCPA Right to Delete, LGPD Art. 18, UK GDPR equivalent
→ Vertical: Charter of Fundamental Rights → GDPR → EDPB Guidelines → national DPA guidance
→ Normative context: 1995 Directive gap, Court of Justice case law on Right to be Forgotten
→ Cross-references: Articles 6, 9, 17(3) exceptions, Recital 65-66
→ Obligations: Controller, processor, third parties notified under Art. 19
→ Evolution: 1995 Directive → GDPR 2016/679 → post-Schrems II adjustments

**Input**: "ISO 9001:2015"
→ Horizontal: AS9100 (aerospace), IATF 16949 (automotive), ISO 13485 (medical devices)
→ Vertical: ISO 9000 vocabulary → ISO 9001 requirements → ISO 9004 guidance → sector-specific add-ons
→ Normative context: 1987 origin, shift from prescriptive to risk-based in 2015 revision
→ Cross-references: ISO 9000:2015 (terms), ISO 31000 (risk), ISO 19011 (auditing)
→ Obligations: Context of organization, leadership, planning, support, operation, performance evaluation, improvement
→ Evolution: 1987 → 1994 → 2000 → 2008 → 2015; next revision expected ~2026

**Input**: "21 CFR Part 11"
→ Horizontal: EU Annex 11, GAMP 5, ICH Q10
→ Vertical: FD&C Act → 21 CFR → Part 11 → FDA guidance on Part 11 scope and application
→ Obligations: Electronic records authenticity, audit trails, access controls, electronic signatures
→ Pitfalls: Scope confusion (predicate rule vs. Part 11 itself), legacy system validation gaps

**Input**: "REACH"
→ Multiple instruments: EU REACH (EC 1907/2006) vs. UK REACH (post-Brexit) — expand both separately
```
