# Spec 2026073005 — SemOS P0 Benchmark-Led Closeout

**Status:** Proposed — design approved; implementation not started  
**Date:** 2026-07-30  
**Scope:** Close the remaining SemOS P0 documentation and benchmark-evidence items in
`KnowledgeStore` and `ChenWeb`. No P1 pipeline routing, P2 ontology runtime, database migration,
production-store policy, or new repository is included.

## 1. Goal

Close P0 with an auditable documentation baseline and controlled benchmark evidence that
different store-shaped corpora need different document-processor policies.

This slice combines two previously separate tracks:

1. merge the keyword-canonicalization designs and settle the repository-placement mismatch; and
2. broaden the isolated ChenWeb gold benchmark enough to support the DR18 policy-need finding.

The benchmark is authoritative for this P0 design finding. It does not claim that differentiated
policies are deployed, nor does it substitute synthetic results for production telemetry.

## 2. Decisions already approved

### 2.1 Repository ownership

The workspace policy is the governing rule:

| Artifact | Repository | Reason |
|---|---|---|
| ADRs, specs, handoffs, operations notes, and benchmark findings | `KnowledgeStore` | Human-authored documentation belongs in the documentation repository |
| SemOS and benchmark application code | `ChenWeb` | The current implementation is ChenWeb-specific |
| Synthetic machine-consumed fixtures and benchmark metadata | `ChenWeb` | They version with their parsers, generators, scorers, and tests |
| Reusable modules/functions proven to have multiple consumers | `shared` | Shared code is introduced only when reuse is real |
| Separate `semos-ontology` repository | Not created in P0 | It conflicts with the current workspace policy and has no independently operating curator/release workflow yet |

ADR DR17 must be revised to express a logical ontology/policy package boundary, not a requirement
for a fourth physical repository. In the current phase, project-specific machine-consumed
ontology/policy data belongs in `ChenWeb`; documentation stays in `KnowledgeStore`. Moving a
proven reusable compiler or contract into `shared` remains possible later. Creating a separate
repository requires an explicit future decision and is not an implied P0 deliverable.

### 2.2 Evidence source

The isolated benchmark path is sufficient authoritative evidence for P0:

- the ChenWeb synthetic gold corpus;
- generated CDM documents;
- `gold-run` against `chenweb_test` and the production document-processing runtime;
- deterministic scorers where expected answers exist;
- explicitly labeled structural or reviewed evidence where deterministic scorers do not exist.

The deployed miner database is not required for this closeout. Its existing inventory remains a
dated operational observation, not the source of the store-policy conclusion.

### 2.3 Semantic claim being tested

P0 tests this bounded claim:

> Controlled corpora shaped for different knowledge-store purposes exhibit materially different
> processor applicability, yield, or usefulness, so store-aware pipeline policy is justified as
> a P1 design requirement.

P0 does not test or assert:

- that a production knowledge store has an active custom pipeline;
- that a processor with more rows is more useful;
- that synthetic document profiles equal deployed stores;
- that LLM review is deterministic gold;
- that the future binding precedence or persistence model is implemented.

## 3. Deliverables

### 3.1 One merged keyword-canonicalization specification

Create one KnowledgeStore specification that supersedes specs `2026072301` and `2026072703`.
The merged specification must instantiate ADR DR15's shared canonicalization-kernel contract and
DR16's selected keyword design:

- occurrence → surface → lexform → keyword-concept identity layers;
- stored surfaces, derived and versioned normalization keys;
- deterministic online resolution with `resolved`, `ambiguous`, `unresolved`, and `rejected`
  outcomes;
- Postgres `kb.` persistence and ChenWeb integration;
- mention observations, unresolved queues, reconciliation runs, and complete decision provenance;
- tombstone merges, `never_merge`, locked human decisions, and no inferred transitive merge
  closure;
- bounded asynchronous reconciliation with negative caching;
- governed `aligns_to_term` links from lexical concepts to ontology terms.

It must explicitly reject SQLite-first storage and a keyword-owned reconciliation engine. It must
mark both predecessor specs as superseded without deleting them.

### 3.2 Corrected architecture and status documents

Update the consolidated ADR and ontology handoff so that they:

- record the user's approval of the frozen competency-question answers;
- replace the standalone-repository requirement with the approved repository ownership in §2.1;
- remove the stale P0 action to create a `semos-ontology` repository and CI skeleton;
- distinguish the logical ontology/policy data package from its current physical placement;
- record the benchmark evidence and its limitations;
- mark P0 complete only after every acceptance criterion in §8 passes;
- keep P1–P7 unstarted unless separate implementation evidence exists.

ADR alternatives that currently reject placing machine-consumed data in ChenWeb or
KnowledgeStore must be reconciled with the new decision rather than left contradictory.
The checked-in fixture comments and README under
`ChenWeb/benchmark/doc-processors/gold/display-module-v1/` must also stop promising a later move
to a DR17 standalone repository. They must identify ChenWeb as the approved current home and
describe any future relocation as a separate explicit decision.

### 3.3 Store-shaped benchmark metadata

Extend the existing corpus manifest contract with validated, machine-readable metadata at the
generated-document level:

```json
{
  "document_profiles": {
    "doc:example": {
      "store_profile": "regulated-reference",
      "document_kind": "authority-standard",
      "expected_processors": {
        "extract_provisions": "required",
        "extract_metrics": "useful",
        "extract_topics": "useful",
        "summarize": "not_required"
      }
    }
  }
}
```

The exact processor names must use ChenWeb's canonical processor registry. Applicability values
are a small closed vocabulary:

- `required`: absence is a profile failure;
- `useful`: signal is expected, but absence is not automatically a failure without a scorer;
- `not_required`: the profile does not depend on the processor; nonzero output is not by itself
  an error.

Every generated document must resolve to exactly one `store_profile` and one `document_kind`.
Unknown documents, unknown processors, missing metadata, duplicate normalized identifiers, and
unknown applicability values are validation errors.

This metadata is a benchmark expectation, not a production routing policy. It must not populate
`kb.knowledge_store_bindings` or alter `required_processors`.

### 3.4 Fixture families

The corpus must contain at least three materially different profiles:

| Store profile | Representative document shape | Expected policy distinction |
|---|---|---|
| `regulated-reference` | Normative standards/guidance with clauses, limits, editions, and authority context | Provisions and metric extraction are important |
| `product-specification` | Enterprise/product specification with measurable capabilities and component context | Metrics and object/component signal are important |
| `narrative-research` | Descriptive research or explanatory prose with topics and few or no normative requirements | Topic/knowledge/summary signal is useful; provision extraction is not required |

Existing ventilator display-module documents should be reused where they satisfy a profile.
Additional documents must remain synthetic and state that their identifiers, issuers, clauses,
and values are not real standards. The smallest corpus that produces the three distinctions is
preferred.

The fixture expansion must not change the expected 36-cell verdict matrix merely to manufacture
store-policy evidence. If additional narrative or supporting documents are added to the existing
gold file, comparator resolution must continue to select the same authored subject/reference
evidence, or the additional fixtures must be isolated from that resolver.

### 3.5 Repeatable profile report

First extend `gold-run` to emit a versioned result envelope:

```json
{
  "schema_version": 2,
  "dataset": {
    "id": "doc-processors-corpus-display-module",
    "version": "1.1.0",
    "content_hash": "sha256:..."
  },
  "case_id": "display-module-v1",
  "selected_processors": ["extract_metrics", "extract_provisions"],
  "dry_run": false,
  "results": []
}
```

`content_hash` covers the canonical manifest plus every referenced fixture byte sequence used by
the selected case, including document-profile metadata. `selected_processors` records the
canonical, de-duplicated processor set actually passed to the production runtime. For a dry run
it is an empty list. The envelope is the evidence provenance contract; the reporter must reject
the older unversioned shape rather than guessing missing identity or processor selection.

Add a deterministic post-processor over this result envelope plus the validated corpus metadata.
It produces JSON and Markdown with one row per
`(store_profile, document_kind, selected_processor)`:

```text
documents
successful_documents
failed_documents
documents_with_output
output_rows
applicability
evidence_kind
assessment
```

The report must:

1. require result-envelope schema version 2;
2. recompute the selected case's content hash and require it to equal the envelope hash;
3. require dataset ID/version and case ID to equal the loaded corpus metadata;
4. validate that every result document belongs to the selected corpus case;
5. reject duplicate, missing, or unknown result documents;
6. validate every selected processor against the canonical processor registry;
7. count run failures separately from zero-output successes;
8. distinguish “no registered result table” from a valid empty result;
9. aggregate in stable lexical order;
10. include the dataset/case identity, content hash, and selected processor set;
11. label the evidence used for each assessment.

Evidence kinds are:

- `deterministic_gold`: an exact scorer or authored answer key supports the assessment;
- `structural_yield`: the report knows only whether output exists and how much;
- `reviewed`: a named human or LLM review artifact supports usefulness/correctness.

Structural yield must never be described as correctness. A `required` processor with a run
failure or no output is a failure. A `useful` processor with no output is a review warning unless
a deterministic scorer makes it a failure. `not_required` is informational and never means that
output is forbidden.

The report is read-only over the result JSON. It does not invoke processors, mutate database
rows, or call an LLM. Existing `analyze` output may be attached later as `reviewed` evidence, but
the baseline report must run offline and deterministically.

## 4. Architecture and boundaries

### 4.1 KnowledgeStore boundary

KnowledgeStore holds decisions and findings:

- this closeout design;
- the merged DR16 keyword specification;
- ADR and handoff corrections;
- operations instructions for generating the profile report;
- the final dated benchmark finding.

It does not hold Go packages, executable fixtures, or generated benchmark result files.

### 4.2 ChenWeb boundary

ChenWeb owns:

- manifest schema and validation;
- store-profile fixture metadata;
- any minimal synthetic fixture additions;
- the offline profile-report builder and CLI entry point;
- unit, fixture, and command tests.

No `shared` change is planned. If implementation exposes an already-existing shared abstraction,
the work must stop and propose that change separately rather than silently broadening this slice.

### 4.3 Data flow

```text
gold fixture + profile metadata
            |
            v
validated CorpusDataset ----> generated CDM documents
            |                          |
            |                          v
            |                   gold-run / chenweb_test
            |                          |
            +---------> result JSON <--+
                           |
                           v
                  offline profile report
                           |
                           v
               reviewed P0 finding in KnowledgeStore
```

The existing `gold-run` execution path remains the source of raw processor results. The new
reporter consumes its output; it does not create a second execution engine.

## 5. Error handling

Schema and reference errors must fail before any benchmark execution:

- missing profile metadata for a generated document;
- metadata for a document not generated by the case;
- unknown processor or applicability value;
- empty profile/document-kind identifiers;
- path traversal or unsafe fixture references.

Report errors must be explicit and non-partial:

- malformed result JSON;
- unsupported or missing result-envelope schema version;
- dry-run JSON presented as executed evidence;
- duplicate result document;
- missing result document;
- result document outside the selected case;
- incompatible dataset ID, dataset version, case ID, content hash, or selected processor set;
- unsupported result shape.

Individual processor run errors are reportable evidence, not parser errors. They appear in failure
counts and affect the assessment without preventing a report for the remaining documents.

## 6. Testing strategy

Implementation follows test-driven development.

### 6.1 Manifest tests

- valid metadata for all real fixture documents loads;
- each validation condition in §3.3 fails with a field-addressable error;
- existing path-safety and duplicate-reference protections remain intact;
- canonical processor names are accepted and aliases/unknown names are rejected.

### 6.2 Fixture tests

- all three required profiles and their expected document kinds exist;
- every generated document has exactly one profile record;
- synthetic labeling is present;
- existing CDM validation and Typst grounding tests continue to pass;
- the existing comparison fixture still scores 36/36.

### 6.3 Report tests

- aggregation is correct across profiles, kinds, processors, empty outputs, and run failures;
- missing table, empty output, and failed run remain distinct;
- output ordering and JSON/Markdown rendering are deterministic;
- evidence-kind and assessment language obey §3.5;
- unknown/duplicate documents and dry-run inputs fail;
- a golden report fixture demonstrates materially different profile vectors.

### 6.4 Verification commands

The implementation plan must name the exact focused Go tests, CLI smoke commands, and the final
`go test` scope. Tests requiring PostgreSQL, NATS, Typst, or LLM credentials must be separated
from offline tests and documented with their prerequisites. The deterministic offline suite is
always required.

P0 closeout additionally requires at least one non-dry-run `gold-run` against `chenweb_test`.
That run must cover all three store profiles and the canonical union of processors marked
`required` or `useful` by their metadata. The exact command, result-envelope content hash,
execution date, completion/failure counts, and generated profile-report hash must be recorded in
the final KnowledgeStore finding. If the environment cannot execute that run, the code and
offline tests may be complete, but P0 remains open rather than substituting a golden test fixture
for observed benchmark evidence.

## 7. Documentation protocol

At closeout, the change must answer:

1. What knowledge changed?
2. Which docs, specs, ADRs, and tests were affected?
3. Which documents were updated?
4. Which documents are now stale?
5. What was intentionally left undocumented?

The predecessor keyword specs remain as historical records with clear supersession notices.
Generated benchmark outputs are evidence artifacts and should not be committed to KnowledgeStore
unless a concise reviewed finding depends on a stable excerpt or hash.

## 8. Acceptance criteria

P0 is complete when all of the following are true:

- the merged keyword specification exists and marks both predecessors superseded;
- the consolidated ADR and handoff match the approved repository policy;
- competency-question owner review is recorded as approved by the user on 2026-07-30;
- no P0 checklist still requires a new `semos-ontology` repository;
- all generated documents have validated profile metadata;
- at least three store-shaped profiles are represented;
- the offline report is deterministic and tested;
- at least one non-dry-run `gold-run` against `chenweb_test` covers all three profiles and every
  processor marked `required` or `useful`;
- the final KnowledgeStore finding records the command, date, result-envelope content hash,
  completion/failure counts, and profile-report hash for that run;
- the report shows at least two profiles with different expected processor vectors and observed
  yield/evidence patterns;
- evidence strength and synthetic limitations are explicit;
- existing gold comparison remains 36/36;
- focused ChenWeb tests and documentation checks pass;
- KnowledgeStore and ChenWeb changes are committed separately with `jj`;
- the ADR may then mark P0 complete while P1–P7 remain unstarted.

## 9. Deferred work

The following remain outside P0:

- production knowledge-store pipeline bindings and precedence;
- `kb.knowledge_store_bindings` or other schema changes;
- ontology compiler, activation, modules, profiles, and runtime tables;
- keyword database/API implementation;
- automatic promotion of benchmark expectations into routing policy;
- deterministic semantic scorers for processors that lack answer keys;
- real standards, authoritative editions, or production regulatory claims;
- moving reusable code to `shared`;
- creating an independent ontology repository.
