---
title: Class Contracts
language: en
format: markdown
version: 1.0
status: current
author: Not specified
owner: Not specified
audience: ChenWeb and SemOS users, ontology curators, reviewers, analysts, and system operators
create-time: 2026-09-05T06:49:42-05:00
last-modify-time: 2026-09-05T06:49:42-05:00
keywords:
  supplied: Class Contracts
  generated: metric class, class contract, class contract revision, definition_state, identity_only, partially_defined, validated, capability, can_instantiate, can_validate_value, capability validation, observed class profile, contract synthesis, conformance, not_evaluated, conforms, conformance_contract_violation, metric-contract-backfill, class resolution, ontology instance, Metric Ontology, kb.ontology_class_contract_revisions, kb.ontology_class_contract_capabilities, kb.ontology_observed_class_profiles
---

# Class Contracts

## 1. What this manual is for

The *Metric Ontology* manual explains how a document's claim — "Display luminance: 500 cd/m²" — becomes an instance of a governed **metric class**. That gives the claim an identity: it says *what kind of thing* this claim is an example of. It does not, by itself, say anything about *what values are allowed* for that class, or *whether this system can actually check* a new claim against it.

That second layer — a class's own definition of its expected shape, and what the system can and cannot yet do with it — is the **class contract**. This manual explains what a class contract is, the states it moves through, what its two current capabilities mean, how an individual claim's conformance to its class is judged, and what to expect from all of this in a real deployment today.

This manual assumes you already know what a metric class and an ontology instance are; see the *Metric Ontology* manual (§5, §9.5) if not. You do not need to write code to use it.

## 2. What a class contract is — and is not

| It holds | It does not hold |
|---|---|
| A class's expected value type and permitted units, once known | The value `500 cd/m²` a particular document stated |
| A record of whether the system can accept new instances of the class, and whether it can check a value against it | Whether one specific claim is true, accepted, or compliant |
| A history of how that definition was arrived at, and from what evidence | A prediction of what a future document will say |

A class contract is *about the class* — it is shared by every claim that is an instance of it. Whether *one particular claim* actually matches that contract is a separate, per-claim judgment, covered in §6.

## 3. The three definition states

Every metric class has exactly one current contract revision, and every contract revision carries a `definition_state`:

| State | Meaning | Reached today? |
|---|---|---|
| `identity_only` | The class exists and can be pointed at, but nothing is yet known about what values or units belong to it. | Yes — every class starts here, and it is where every class in a fresh deployment remains until enough evidence accumulates. |
| `partially_defined` | The class's evidence agrees on exactly one value type and one unit, so the contract can now state them. | Yes — see §4 for how. |
| `validated` | Reserved for a fuller, presumably curator-reviewed definition beyond what automatic agreement alone can establish. | **Not yet.** The state is defined in the database and nothing rejects it, but no current mechanism produces it. Treat any class you see at this state as something a person set deliberately, not something the system inferred. |

A contract's history is append-only: a class's definition never rewrites in place. Advancing from `identity_only` to `partially_defined` adds a new revision; the class's earlier `identity_only` revision stays exactly as it was, for anyone tracing what a claim was checked against at the time.

**A contract only ever moves forward.** Once a class has left `identity_only`, nothing reverts it — including a later document that appears to contradict it. A contradiction of that kind is recorded on the *individual claim* as a conformance violation (§6), never by rewinding the class's own contract. If you see a class at `partially_defined` and later evidence that disagrees with it, look for that disagreement on the offending claim, not on the class.

## 4. How a class earns its contract

Nothing promotes a class's contract on a single document. The rule is deliberately narrow: a class advances from `identity_only` to `partially_defined` only when its accumulated evidence — every claim recorded against it so far — agrees on **exactly one** (value type, unit) pair, and that agreement is drawn from **at least two distinct documents**.

Two things follow directly from that rule:

- **One document is never enough**, no matter how clean its data looks. A single document's choice of unit is not evidence that two independent sources would describe the class the same way, and cross-document comparability is the entire reason a contract exists.
- **Any disagreement blocks promotion outright.** If the evidence so far shows two different units, or two different value types, for the same class, the class stays `identity_only` — the system does not guess which one is "right," and it does not average or vote.

The number of documents required — two — is a starting point, not a result of any study of how much agreement is actually enough. It was chosen because it is the smallest number that means "more than one source," and it is recorded here, plainly, so it can be revisited once real usage shows whether it is too low, too high, or about right. If you see a class promoted after only two documents, that is expected behavior, not a bug.

This evidence-gathering and promotion check happens automatically, as part of the same processing step that turns an extracted metric into a stored claim (the `associate_semantics` stage described in the *Metric Ontology* manual, §9.5) — nothing separate needs to be run for a class to advance, beyond documents continuing to be processed.

## 5. Capabilities: what the system can currently do with a class

A capability is a specific, named thing the system can attempt for a class — not a general measure of how "complete" its contract is. Two capabilities exist today:

| Capability | What it means | When it can pass |
|---|---|---|
| **`can_instantiate`** | The class can accept a new, source-backed occurrence. | Always — even a class with no defined shape yet (`identity_only`) can still receive instances; that is what "identity only" means in practice. |
| **`can_validate_value`** | The class's contract is complete enough to check whether a *new* value's type and unit are actually the ones the class permits. | Only once the contract has left `identity_only` and declares both a value type and at least one permitted unit — in practice, once it reaches `partially_defined`. |

Every capability check produces one of three recorded results:

| Result | Meaning |
|---|---|
| `enabled` | The check passed; the class's contract genuinely supports this capability right now. |
| `disabled` | The check ran and failed — the contract exists but is missing something the capability needs (for example, a `can_validate_value` check against a contract that somehow lacks a permitted unit). |
| `indeterminate` | The default state before any check has run, or when a check could not reach a clear pass/fail. |

`can_instantiate` is checked as soon as a class is resolved or created, so it is normally `enabled` immediately. `can_validate_value` is only worth checking once a contract has something to validate against — checking it against an `identity_only` contract is refused outright rather than reported as `disabled`, because there is nothing yet to fail.

**What this does not yet include.** There is no capability today for comparing two different classes, or two different claims of the same class, against each other (sometimes referred to as "can this be compared"). A shared class only means the system can talk about two claims using the same vocabulary — it is not, by itself, permission to compare them. See §8.

## 6. Per-claim conformance: does *this* claim match its class?

A capability (§5) is a property of the class. **Conformance** is a property of one individual claim — whether *this specific* stored claim's value type and unit actually match its class's contract at the moment the claim was written.

| Conformance state | Meaning |
|---|---|
| `not_evaluated` | The honest default: either the class's contract is still `identity_only` (nothing to check against yet), or the claim's own value isn't present to check (for example, it was unparsed or missing). This is not a fault — it is the expected state for the overwhelming majority of claims today, since most classes have not yet left `identity_only`. |
| `conforms` | The claim's value type and unit both match what the class's contract permits. |
| `conformance_contract_violation` | The class's contract is defined enough to check, and this claim's value type or unit does not match it. |

One timing rule is worth internalizing, because it explains a state that otherwise looks wrong: **a claim's conformance is judged against its class's contract as that contract stood immediately before this claim was written — never against a promotion the claim's own arrival just caused.** If the second of two documents needed to promote a class is the very claim being written, that claim is correctly recorded as `not_evaluated` (there was no defined contract yet at the moment it was checked), even though the class contract becomes `partially_defined` moments later as a direct result of that same write. This is expected, not a bug — do not "fix" a `not_evaluated` claim sitting next to a `partially_defined` contract without first checking whether that claim is the one that caused the promotion.

Every claim also keeps a private record of exactly which contract revision it was checked against. That is what lets the system later tell, precisely, which older claims were checked against a contract that has since been superseded by a newer one — the problem §7 covers.

## 7. Keeping older claims current: the backfill command

A class's contract can advance after a claim was already written and judged against the older, less-defined contract. Left alone, that claim would sit forever recorded as `not_evaluated` even after its class becomes fully defined enough to check it.

An operator tool, `metric-contract-backfill`, finds and re-checks exactly these claims:

- Run with no flags, it only **reports** which claims are stale — checked against a contract revision that is no longer their class's current one. It makes no changes.
- Run with `--apply`, it re-evaluates each of those claims against the current contract and updates its conformance state in place. It changes nothing else about the claim.

This is safe to run repeatedly; a claim that is already up to date is simply not reported.

**A known simplification.** When the backfill tool re-checks an older claim, it can only compare the claim's *unit* against the contract — it cannot re-check the claim's original value type, because that detail is not kept on the stored claim the way it is available at the moment of a fresh write. In practice this makes the backfill's re-check slightly less precise than the check a brand-new claim receives. This is a recorded, deliberate simplification, not an oversight — treat a `conforms` result from a backfill run as "the unit matches," not as a full guarantee that nothing else about the value could have been off.

## 8. What to expect today

Observed against the live `miner` database on 2026-09-05: **zero class contract revisions exist**, and the 56 classes behind the database's existing 56 metrics and 112 semantic assertions are all still `identity_only` — every one of those assertions carries conformance state `not_evaluated`. Confirm these figures against your own deployment before relying on them; they will change as documents are processed.

This is expected, and it means something specific: the mechanism described in this manual is built, tested, and wired into the live write path, but the claims already sitting in the database were written *before* it existed and have not yet been reprocessed through it. A class only earns a `partially_defined` contract from evidence gathered as claims are written or re-evaluated — it does not retroactively inspect claims that predate the mechanism on its own. Processing new documents, or running the backfill tool (§7), is what will start moving classes past `identity_only` in this deployment.

**A note on the *Metric Ontology* manual.** That manual's §11.1 states "no class contract revisions existed at the time of observation," dated 2026-08-20. That statement is, numerically, still true today — but for a different reason than when it was written. On 2026-08-20 it was true because the mechanism in this manual did not yet exist. Today it is true because the mechanism exists and works, but no document has yet been processed (or reprocessed) through it. Do not read today's zero as evidence the mechanism is missing; check §3–§7 of this manual, and the live counts above, rather than that older manual's framing.

## 9. A worked example

Take the *Metric Ontology* manual's own example metric, **display luminance** (§6 there), and follow its class contract across three documents:

| Event | What happens to the class's contract |
|---|---|
| First document states "Display luminance: 500 cd/m², typical" | The class is resolved (or created) and given a contract for the first time, at `identity_only`. Its `can_instantiate` capability is checked and passes. The claim's conformance is `not_evaluated` — there is nothing yet to check it against. |
| Second document states "Display luminance ≥ 250 cd/m²" | Evidence now shows two documents agreeing on the same value type and the same unit (`cd/m²`). The promotion rule in §4 is met: the contract advances to `partially_defined`, declaring that value type and unit. The `can_validate_value` capability is checked and now passes. This second claim itself is still recorded `not_evaluated` — its own arrival caused the promotion, so there was no defined contract yet at the moment it was checked (§6). |
| A third document states "Display luminance: 500 nits" | The class's contract is now `partially_defined` and declares `cd/m²` as its permitted unit. This claim's unit does not match, so it is recorded `conformance_contract_violation` — a flag for review, not a silent rewrite of the class's contract (§3). |

Nothing here changes what the *Metric Ontology* manual says the class means; a class contract only ever adds a second layer — what is expected — on top of the identity that manual already describes.

## 10. What was deliberately not built yet

- **Comparing two classes, or two claims of the same class, against each other.** A shared metric class is a prerequisite for this, not the same thing as having it. This is a separate, larger effort.
- **A curator review or approval interface** for contracts that were synthesized automatically, or for classes still awaiting review generally. Today, a synthesized contract is usable immediately, the same way an auto-promoted term is usable immediately (*Metric Ontology* manual, §7.2) — usable is not the same as reviewed.
- **Any automated path to the `validated` state** (§3). Reaching it, if ever automated, is a future decision, not a currently running mechanism.

## 11. Common pitfalls

- **Do not assume a defined contract means every claim of that class conforms.** Conformance is judged per claim (§6); a contract being `partially_defined` only means the system now has something to check new claims against, not that it has rechecked every existing one.
- **Do not treat `not_evaluated` as a problem to fix.** It is the expected, honest state for a class that has not yet accumulated enough agreeing evidence, and for a claim whose own value could not be checked.
- **Do not be surprised that a class became `partially_defined` after only two documents.** That is the intended threshold (§4), not a shortcut the system took.
- **Do not expect a promotion to retroactively fix the claim that caused it.** The claim that pushes a class past `identity_only` is itself still `not_evaluated` (§6) — look at the *next* claim for `conforms` or a violation.
- **Do not read a backfill `conforms` result as a full guarantee.** It only checked the unit, not the original value type (§7).
- **Do not read a shared metric class as permission to compare two claims.** That capability does not exist yet (§5, §10).
- **Do not assume today's zero contract revisions means the mechanism is missing.** Check whether documents have actually been (re)processed since it was deployed (§8) before concluding that.

## 12. Glossary

| Term | Meaning |
|---|---|
| Class contract | A metric class's own definition of its expected value type, permitted units, and which capabilities it currently supports. |
| Class contract revision | One version of a class contract; revisions are appended, never rewritten in place. |
| Definition state | Where a contract stands: `identity_only`, `partially_defined`, or `validated` (§3). |
| Capability | A specific, named thing the system can attempt for a class, such as accepting instances or validating a value (§5). |
| Capability result | Whether a capability check passed (`enabled`), failed (`disabled`), or has not yet reached a clear answer (`indeterminate`). |
| Conformance | Whether one specific stored claim matches its class's contract (§6): `not_evaluated`, `conforms`, or `conformance_contract_violation`. |
| Contract synthesis | The automatic process that promotes a class from `identity_only` to `partially_defined` once its evidence agrees (§4). |
| Backfill | Re-checking older claims against a class's current contract after that contract has changed (§7). |

## 13. Related manuals

- *Metric Ontology* — the metric vocabulary, the metric class an ontology instance points at, and the pipeline stage (`associate_semantics`) that creates and resolves classes. Read this one first.
- *Metric and Assertion Semantic Processing* — the processing pipeline in full detail.
- *SemOS Semantic Layer User Manual* — assertions, evidence, and lossless processing generally.
- *Metric Keyword and Governed Term Resolution* — how document wording resolves to governed terms.

## Change Log

### 1.0 — 2026-09-05T06:49:42-05:00

Author: Claude

Reason: A class contract/capability mechanism was activated this session in code (openspec change `metric-class-contracts`, ChenWeb commit `be4d`), but no user manual explained what a class contract is, what its states and capabilities mean, or what to expect from it — the only prior mention was the *Metric Ontology* manual's §11.1, which described the pre-activation state and was already known to be stale.

Summary: Defined a class contract and its boundary against per-claim conformance; documented the three definition states (`identity_only`, `partially_defined`, `validated`) and that `validated` is defined but not yet reachable by any current mechanism; explained the deterministic two-document agreement rule that promotes a contract and why two is a starting threshold, not a validated number; documented the two current capabilities (`can_instantiate`, `can_validate_value`) and their `enabled`/`disabled`/`indeterminate` results; explained per-claim conformance and the rule that a claim is never evaluated retroactively against a promotion its own write caused; documented the `metric-contract-backfill` operator command and its unit-only re-check simplification; recorded live counts observed against `miner` on 2026-09-05 (zero contract revisions; 56 classes, 56 metrics, 112 assertions, all `not_evaluated`) and explained why that number is expected rather than evidence the mechanism is missing; noted cross-instance comparison and a curation review interface as explicitly not yet built; worked a three-document example through promotion and a conformance violation; added pitfalls and a glossary consistent with the *Metric Ontology* manual's existing terms.
