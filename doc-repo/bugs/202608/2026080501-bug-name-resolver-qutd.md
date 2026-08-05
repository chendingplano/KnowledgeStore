
# Bug Report: Name Resolver and QUDT

Date: 2026/08/05

## 1. Findings

The generic boundary is currently crossed in several places in [associate_semantics.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/assertions/associate_semantics.go:176):

- `metricCandidatePayload` knows the `extract_metrics` payload.
- `processMetric` implements metric-specific behavior.
- `processProvision` implements provision-specific behavior.
- `init()` registers `"metric"` and `"provision"` consumers inside the ontology package.
- `governedMetricAssertionKinds` hardcodes measurement-domain policy.
- `mea:measured_by` and `mea:<assertion_kind>` are hardcoded.
- `canonicalUnitForm` and `unitQuantityKindMap` hardcode pilot metric behavior.

Therefore, `AssociateSemantics.Run` and the registry mechanism are generic, but the package as a whole is not. Adding `resolveMetricDefinitionTerm` to `processMetric` would deepen the problem.

The keyword API is also not yet a good general consumer API:

- `ResolveSurface` mixes lookup with writes to mentions, decision logs, surfaces, and unresolved backlog.
- Its parameters expose storage-oriented concepts such as `artifactRef`.
- The caller-supplied scope is currently ignored during matching because `Kernel.Resolve` recomputes scope through `KeywordFamily.Scope`, which always returns `"_"`.
- It returns a keyword concept but cannot follow an accepted alignment to an ontology term.
- The proposed `aligns_to_term` mechanism does not exist.
- `kb.semantic_assertions` cannot currently represent a keyword concept as a subject because `subject_ref_kind` does not include `keyword_concept`.

So processors technically could call `KeywordFamily.ResolveSurface`, but they would be coupling themselves to an incomplete, side-effect-heavy implementation rather than a stable ontology capability.

## 2. Recommended architecture

Introduce a consumer-agnostic name-resolution service under the ontology API, for example:

```text
server/api/ontology/names/
    resolver.go
    alignment_store.go
    occurrence_store.go
```

The dependency flow should be:

```text
extract_metrics ───────────┐
extract_provisions ────────┤
extract_test_methods ──────┤
extract_inventory_items ───┼──▶ names.Resolver.ResolveName(...)
extract_entity_relation ───┤               │
other consumers ───────────┘               ├── keyword concepts
                                            ├── governed term labels
                                            └── accepted concept↔term alignments
```

The ontology name resolver knows nothing about metrics, provisions, processors, or consumer table schemas. Consumers decide:

- which fields are names;
- the expected ontology kind or module;
- what provenance/context to record;
- where to persist the returned identifiers;
- whether an unresolved result is acceptable.

### 2.1 Suggested Go contract

Use an injected resolver rather than a global function:

```go
type NameResolver interface {
    ResolveName(
        ctx context.Context,
        req ResolveNameRequest,
    ) (NameResolution, error)

    ResolveNames(
        ctx context.Context,
        reqs []ResolveNameRequest,
    ) ([]NameResolution, error)
}

type ResolveNameRequest struct {
    Name              string
    Scope             string
    ExpectedTermKinds []string
    ExpectedModules   []string
    Language          string
}

type NameResolution struct {
    RawName       string
    NormalizedKey string
    Status        ResolutionStatus

    ConceptID       string
    ConceptPrefName string

    TermID       string
    TermPrefName string
    TermKind     string
    ModuleID     string

    Candidates []NameCandidate
    Method     string
    Confidence float64
}
```

Important points:

- No `MetricID`, `ProvisionID`, processor name, or consumer table appears in the contract.
- `Scope` must be explicit and honored.
- Expected term kinds are semantic constraints, not consumer coupling. For example, a metric passes `metric_definition`; a test method passes `procedure`.
- The result should return stable IDs and labels. Consumers must not treat a canonical display string as identity.
- `ambiguous`, `unresolved`, and `lexical_only` should be normal results, not errors.
- Add `ResolveNames` early because chunk processors will otherwise produce large numbers of small database calls.

## 3. Keep resolution and observation separate

I recommend making `ResolveName` read-only. The current `ResolveSurface` performs too many writes for a general lookup operation.

Use a separate operation such as:

```go
ObserveName(ctx, NameOccurrence) error
```

or:

```go
ResolveAndObserve(ctx, request, occurrence)
```

as an explicit convenience method.

This prevents a UI lookup, API request, test, or reprocessing run from unexpectedly:

- creating mention rows;
- extending the lexicon;
- incrementing unresolved counts;
- creating alternative surfaces.

A name lookup and a corpus observation are related, but they are not the same command.

The current `kb.keyword_mentions` schema is inadequate for direct processor use because it does not store the raw name, resolved concept, field identity, or a link to the decision record. It should at least capture:

```text
artifact_type
artifact_id
field_path
raw_name
scope / ks_id
context
chunk_ref
concept_id nullable
term_id nullable
resolution_status
decision_log_id
```

This can remain generic: `field_path = "metric_name"` is supplied by the consumer as provenance, not understood by the ontology service.

## 4. Resolution semantics

`ResolveName` should preserve the distinction between lexical and governed identities:

```text
raw name
   │
   ├── exact released ontology label ───────────────▶ governed term
   │
   └── keyword surface ─▶ keyword concept
                              │
                              └── accepted alignment ─▶ governed term
```

Recommended outcomes:

- `term_resolved`: exactly one released term is established.
- `lexical_resolved`: a keyword concept was found, but no governed alignment exists.
- `ambiguous`: multiple equally valid concepts or terms remain.
- `unresolved`: no match.
- `disabled`: resolver intentionally disabled.

A lexical auto-match must not automatically become a governed ontology identity. Only either of these should produce `TermID`:

1. An exact match against a released term’s governed pref/alt label.
2. An accepted, reviewed concept-to-term alignment.

That preserves the governance boundary while giving every consumer one natural API.

## 5. Where consumers should call it

Calling from consumers is preferable to waiting for `AssociateSemantics.processMetric`.

For `extract_metrics`, the appropriate point is after the LLM result has been parsed and validated, but before the metric row is persisted:

```go
resolution := resolver.ResolveName(ctx, ResolveNameRequest{
    Name:              metric.Name,
    Scope:             knowledgeStoreID,
    ExpectedTermKinds: []string{"metric_definition"},
})
```

Persist:

- the original `metric_name`;
- `keyword_concept_id`, when lexically resolved;
- `metric_definition_term_id`, when governed resolution succeeds;
- optionally resolution method/version.

Apply the same pattern independently to:

- `extract_metric_definitions`: canonical name and aliases;
- `extract_test_methods`: procedure name and referenced metric names;
- `extract_provisions`: only fields explicitly defined as semantic names;
- entities, products, and inventory items where lexical concept resolution is useful.

Not every string called “name” belongs to the same identity family. Product instances, organization names, metric definitions, procedure terms, and category labels need different expected kinds or providers. A single unscoped string-to-string canonicalizer would over-merge them.

## 6. What should remain in `AssociateSemantics`

`AssociateSemantics` can remain a generic engine for processing semantic decision candidates, but concrete metric/provision behavior should move out.

Recommended split:

```text
ontology/assertions
    AssociateSemantics.Run
    resolver registry
    assertion/evidence stores
    generic lifecycle and validation

consumer integration
    metric assertion adapter
    provision assertion adapter
    consumer payload decoding
    consumer-specific predicates and policies
```

The generic ontology package should not register `"metric"` and `"provision"` in its own `init()`. Registration should happen during application composition, or the relevant consumer package should explicitly provide its adapter.

Direct `ResolveName` calls do not necessarily eliminate Phase D. They eliminate the need for Phase D to discover what an extracted name means. Phase D may still build and adjudicate qualified semantic assertions from already-resolved artifact data.

## 7. QUDT implication

The same recommendation applies to `resolveUnitTerms`.

QUDT already lives in the ontology store, so unit resolution should eventually be:

```go
ResolveName(Name: "ms", ExpectedTermKinds: ["unit"])
```

against released pref/alt labels or lexical alignments.

The present hardcoded five-unit map should be removed after:

1. QUDT labels and symbols are correctly backfilled into `kb.ontology_term_labels`.
2. Unit-to-quantity-kind relationships are imported as governed ontology data.
3. Exact governed-label resolution is implemented.

Currently the importer skips existing term IDs before backfilling labels, and it does not import QUDT unit-to-quantity-kind relationships. Those two gaps created the need for the hardcoded runtime maps.

## 8. Recommended sequence

1. Correct the specification: replace the proposed `processMetric` integration with a generic `ResolveName` service called by consumers.
2. Define the layered result contract and explicit scope semantics.
3. Separate read-only resolution from observation/reconciliation writes.
4. Fix the keyword scope, normalization, surface-key, and mention-schema defects.
5. Implement governed concept-to-term alignment storage and lookup.
6. Backfill QUDT labels and import unit relationships.
7. Integrate `extract_metric_definitions` and `extract_metrics` as the pilot consumers.
8. Add other consumers field by field.
9. Move metric/provision assertion adapters out of the generic ontology package.
10. Remove `canonicalUnitForm`, `unitQuantityKindMap`, and the proposed metric-specific name logic from `AssociateSemantics`.

The central rule should be:

> Ontology provides generic identity and meaning-resolution capabilities. Consumers identify names, call those capabilities, preserve raw evidence, and decide how resolved identities participate in their own artifacts.
