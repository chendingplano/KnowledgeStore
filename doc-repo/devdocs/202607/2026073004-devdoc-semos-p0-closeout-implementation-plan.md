# SemOS P0 Benchmark-Led Closeout Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close SemOS P0 by merging the keyword design, correcting repository ownership, and
producing provenance-bound `chenweb_test` evidence that three store-shaped corpus profiles need
different processor policies.

**Architecture:** Keep all executable fixtures and Go code in ChenWeb and all prose decisions and
findings in KnowledgeStore. Extend the existing corpus manifest with per-document profiles,
derive a case content hash from canonical metadata plus exact fixture bytes, emit a versioned
`gold-run` envelope, and feed it to a deterministic offline profile reporter. Reuse the current
nine-document display-module corpus; do not implement production routing or ontology runtime
behavior.

**Tech Stack:** Go 1.25, PostgreSQL (`chenweb_test` only), JSON, TOML, Markdown, Typst,
`mise`, Jujutsu (`jj`)

**Approved design:** `doc-repo/specs/202607/2026073005-spec-semos-p0-benchmark-led-closeout.md`

---

## File map

### ChenWeb

| File | Responsibility |
|---|---|
| `server/api/doc-processing/processor_registry.go` | One canonical ordered registry for optional production processors |
| `server/api/doc-processing/processor_registry_test.go` | Registry copy-safety, ordering, alias, and validation tests |
| `server/api/doc-processing/runtime.go` | Consume the canonical registry instead of duplicating names |
| `server/api/doc-benchmark/corpus_dataset.go` | Profile schema, validation, case content hash, loaded profile access |
| `server/api/doc-benchmark/corpus_dataset_test.go` | Manifest/profile/hash failure and real-fixture regression tests |
| `benchmark/doc-processors/gold/display-module-v1/manifest.json` | Nine document-to-profile mappings and processor expectations |
| `benchmark/doc-processors/gold/display-module-v1/README.md` | Profile definitions, commands, and approved fixture ownership |
| `benchmark/doc-processors/gold/display-module-v1/gold.toml` | Correct stale standalone-repository comments only |
| `server/api/doc-benchmark/profile_report.go` | Result-envelope contract, validation, aggregation, and rendering |
| `server/api/doc-benchmark/profile_report_test.go` | Envelope/report rules and deterministic golden tests |
| `server/api/doc-benchmark/testdata/profile-report.golden.json` | Canonical JSON regression output |
| `server/api/doc-benchmark/testdata/profile-report.golden.md` | Canonical Markdown regression output |
| `server/cmd/doc-benchmark/gold_run.go` | Emit schema-v2 provenance and structured processor result states |
| `server/cmd/doc-benchmark/gold_run_test.go` | Processor selection, result shape, and envelope tests |
| `server/cmd/doc-benchmark/gold_profile_report.go` | Offline `profile-report` CLI |
| `server/cmd/doc-benchmark/main.go` | Register the new command |
| `server/cmd/doc-benchmark/main_test.go` | Command validation and smoke coverage |
| `mise.toml` | Repeatable profile-report and P0 evidence tasks |

### KnowledgeStore

| File | Responsibility |
|---|---|
| `doc-repo/specs/202607/2026073006-spec-semos-keyword-canonicalization.md` | Merged DR16 keyword specification |
| `doc-repo/specs/202607/2026072301-spec-keyword-canonicalization-reconciliation.md` | Historical status and supersession pointer |
| `doc-repo/specs/202607/2026072703-spec-keyword-canonicalization-reconciliation-2.md` | Historical status and supersession pointer |
| `doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` | Approved repository policy, CQ approval, P0 evidence, and status |
| `doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md` | Accurate closeout and P1/P2 handoff |
| `doc-repo/devdocs/202607/2026073002-devdoc-gold-benchmark-operations.md` | Profile metadata/report execution instructions |
| `doc-repo/devdocs/202607/2026073005-devdoc-semos-p0-benchmark-evidence.md` | Dated command, hashes, completion/failure counts, and bounded finding |
| `doc-repo/specs/202607/2026073005-spec-semos-p0-benchmark-led-closeout.md` | Final implementation status |

No file under `shared` and no new repository is part of this plan.

## Chunk 1: Validated store-profile corpus

### Task 1: Centralize the optional production-processor registry

**Files:**

- Create: `ChenWeb/server/api/doc-processing/processor_registry.go`
- Create: `ChenWeb/server/api/doc-processing/processor_registry_test.go`
- Modify: `ChenWeb/server/api/doc-processing/runtime.go`
- Modify later: `ChenWeb/server/cmd/doc-benchmark/gold_run.go`

- [ ] **Step 1: Confirm the ChenWeb working copy is clean**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
jj status
```

Expected: `The working copy has no changes.` Stop and report unexpected changes before editing.

- [ ] **Step 2: Write failing registry tests**

Add tests that require a stable ordered list, copy isolation, alias normalization, and rejection of
unknown names:

```go
func TestOptionalProductionProcessorNames(t *testing.T) {
    want := []string{
        "generate_summaries", "generate_topics", "extract_doc_metadata",
        "extract_semantic_projections", "extract_structured_knowledge",
        "extract_entity", "extract_relation", "extract_inventory_items",
        "extract_metrics", "extract_provisions", "generate_scene_blocks",
    }
    got := OptionalProductionProcessorNames()
    if !reflect.DeepEqual(got, want) {
        t.Fatalf("got %v, want %v", got, want)
    }
    got[0] = "mutated"
    if OptionalProductionProcessorNames()[0] != "generate_summaries" {
        t.Fatal("registry returned shared mutable storage")
    }
}

func TestCanonicalOptionalProductionProcessor(t *testing.T) {
    got, ok := CanonicalOptionalProductionProcessor(" extract-metadata ")
    if !ok || got != "extract_doc_metadata" {
        t.Fatalf("got %q, %v", got, ok)
    }
    if _, ok := CanonicalOptionalProductionProcessor("static_analyzer"); ok {
        t.Fatal("mandatory processor must not be selectable")
    }
    if _, ok := CanonicalOptionalProductionProcessor("not_a_processor"); ok {
        t.Fatal("unknown processor accepted")
    }
}
```

- [ ] **Step 3: Run the tests and confirm the API is missing**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-processing -run 'Test(OptionalProductionProcessorNames|CanonicalOptionalProductionProcessor)$' -count=1
```

Expected: build failure because the two exported functions do not exist.

- [ ] **Step 4: Add the registry**

Create one immutable package-level list and return copies:

```go
package docprocessing

var optionalProductionProcessorOrder = []string{
    "generate_summaries", "generate_topics", "extract_doc_metadata",
    "extract_semantic_projections", "extract_structured_knowledge",
    "extract_entity", "extract_relation", "extract_inventory_items",
    "extract_metrics", "extract_provisions", "generate_scene_blocks",
}

func OptionalProductionProcessorNames() []string {
    return append([]string(nil), optionalProductionProcessorOrder...)
}

func CanonicalOptionalProductionProcessor(raw string) (string, bool) {
    name := normalizeRuntimeName(raw)
    for _, candidate := range optionalProductionProcessorOrder {
        if name == candidate {
            return candidate, true
        }
    }
    return "", false
}
```

Change `resolveRequiredProcessors` to append `optionalProductionProcessorOrder` after
`static_analyzer` and `chunking`, and change `validateRequiredProcessors` to use
`CanonicalOptionalProductionProcessor` plus the two mandatory names. Preserve existing aliases
and production order.

- [ ] **Step 5: Run focused and runtime-selection tests**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-processing \
  -run 'Test(OptionalProductionProcessorNames|CanonicalOptionalProductionProcessor|ProductionRuntimeSelectedProcessorDependencyClosure|NewProductionRuntimeOptionsRejectUnknownExplicitProcessorBeforeInitialization|NewProductionRuntimeSuccessfulExplicitAndDefaultSelection)$' \
  -count=1
```

Expected: PASS.

- [ ] **Step 6: Commit the ChenWeb registry change**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
jj status
jj describe -m "refactor: centralize document processor registry"
jj new
```

Expected: the described commit contains only the registry, runtime, and registry tests; the new
working copy is clean.

### Task 2: Add document profiles and case content hashing

**Files:**

- Modify: `ChenWeb/server/api/doc-benchmark/corpus_dataset.go`
- Modify: `ChenWeb/server/api/doc-benchmark/corpus_dataset_test.go`

- [ ] **Step 1: Extend the minimal test manifest with complete profiles**

Add test helpers using the two minimal documents and two processors:

```go
func validDocumentProfilesJSON() string {
    return `"document_profiles": {
      "doc:ent-q-syn-001-2026": {
        "store_profile": "product-specification",
        "document_kind": "enterprise-standard",
        "expected_processors": {
          "extract_metrics": "required",
          "extract_provisions": "useful"
        }
      },
      "doc:cn": {
        "store_profile": "regulated-reference",
        "document_kind": "authority-standard",
        "expected_processors": {
          "extract_metrics": "useful",
          "extract_provisions": "required"
        }
      }
    }`
}
```

Update `validCorpusManifest()` to include that object inside the case.

- [ ] **Step 2: Write table-driven failing validation tests**

Cover these exact errors:

```go
tests := []struct {
    name, mutate, want string
}{
    {"missing generated document", deleteProfile("doc:cn"), "document_profiles[doc:cn]: required"},
    {"unknown document", addProfile("doc:ghost"), "document_profiles[doc:ghost]: document is not generated"},
    {"empty store profile", setProfileField("doc:cn", "store_profile", ""), "store_profile: required"},
    {"whitespace store profile", setProfileField("doc:cn", "store_profile", "  "), "store_profile: must be canonical nonblank text"},
    {"empty document kind", setProfileField("doc:cn", "document_kind", ""), "document_kind: required"},
    {"whitespace document kind", setProfileField("doc:cn", "document_kind", "  "), "document_kind: must be canonical nonblank text"},
    {"missing expectations", deleteExpectedProcessors("doc:cn"), "expected_processors: required"},
    {"empty expectations", emptyExpectedProcessors("doc:cn"), "expected_processors: must not be empty"},
    {"unknown processor", setExpectation("doc:cn", "unknown", "useful"), "unknown processor"},
    {"processor alias rejected", setExpectation("doc:cn", "extract-metrics", "useful"), "processor name must be canonical"},
    {"unknown applicability", setExpectation("doc:cn", "extract_metrics", "sometimes"), "unknown applicability"},
    {"missing selected expectation", deleteExpectation("doc:cn", "extract_provisions"), "expected_processors[extract_provisions]: required"},
    {"normalized duplicate document", addProfile(" doc:cn "), "duplicate normalized document id"},
    {"normalized duplicate processor", addExpectation("doc:cn", " extract_metrics ", "useful"), "duplicate normalized processor id"},
}
```

Add raw-manifest cases with exact duplicate JSON keys:

```go
func TestLoadCorpusDatasetRejectsDuplicateDocumentProfileJSONKey(t *testing.T)
func TestLoadCorpusDatasetRejectsDuplicateExpectedProcessorJSONKey(t *testing.T)
```

These tests must construct raw JSON containing the repeated keys literally; a Go map cannot
represent the invalid input.

Also add:

```go
func TestCorpusCaseContentHashChangesWithProfileOrGold(t *testing.T)
func TestCorpusCaseContentHashIgnoresMapInsertionOrder(t *testing.T)
func TestCorpusCaseContentHashUsesSHA256Prefix(t *testing.T)
```

The insertion-order test must load semantically identical manifests whose map keys appear in
different orders and expect equal hashes. The mutation tests change one profile value or one gold
byte and expect different hashes.

- [ ] **Step 3: Run the focused tests and confirm failure**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-benchmark \
  -run 'TestLoadCorpusDataset|TestCorpusCaseContentHash' -count=1
```

Expected: failures because the schema, validation, and hash do not exist.

- [ ] **Step 4: Implement focused profile types and validation**

Add:

```go
type ProcessorApplicability string

const (
    ProcessorRequired    ProcessorApplicability = "required"
    ProcessorUseful      ProcessorApplicability = "useful"
    ProcessorNotRequired ProcessorApplicability = "not_required"
)

type DocumentProfile struct {
    StoreProfile       string                                    `json:"store_profile"`
    DocumentKind       string                                    `json:"document_kind"`
    ExpectedProcessors map[string]ProcessorApplicability         `json:"expected_processors"`
}

type CorpusManifestCase struct {
    CaseID           string                     `json:"case_id"`
    Gold             string                     `json:"gold"`
    Tags             []string                   `json:"tags,omitempty"`
    DocumentProfiles map[string]DocumentProfile `json:"document_profiles"`
}
```

Before `decodeStrict`, run a duplicate-aware JSON-key preflight over `manifestBytes`. Implement it
with `json.Decoder.Token`: maintain one key set per object scope, recurse through arrays/objects,
and return a field-addressable error when the same literal key occurs twice. Do not round-trip
through `map[string]any`, because that has already discarded the duplicate. This preflight covers
duplicate keys anywhere in the manifest; the two tests above lock the profile-specific cases.

Import `server/api/doc-processing` and validate processor keys with
`CanonicalOptionalProductionProcessor`. For each case:

1. build the exact generated-document key set from `gold.BuildDocuments`;
2. require one and only one metadata record per generated document;
3. reject metadata for unknown documents;
4. require nonblank `store_profile` and `document_kind`;
5. trim document/profile/processor identifiers for comparison, reject noncanonical whitespace,
   aliases, and two keys that normalize to the same identifier;
6. require `expected_processors` to be present and nonempty;
7. compute the union of expected processors across the case;
8. require every document profile to declare one applicability for every union member.

Store the validated map and hash on the loaded case:

```go
type CorpusCase struct {
    CaseID          string
    Tags            []string
    Gold            gold.File
    Resolved        *gold.Resolved
    DocumentProfiles map[string]DocumentProfile
    ContentHash     string
}
```

Derive `ContentHash` as `sha256:` plus SHA-256 over framed bytes containing:

- a domain prefix such as `chenweb-corpus-case-v1\n`;
- canonical JSON of the complete manifest, including `schema_version`, dataset ID/version, all
  cases, tags, and all document-profile metadata;
- the exact referenced `gold.toml` bytes.

Use length-prefixed frames, sort no semantic data outside canonical JSON, and do not reuse the
single-line `sha256Hex` helper without the framing/domain prefix.

- [ ] **Step 5: Run all corpus-loader tests**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-benchmark -run 'TestLoadCorpusDataset|TestCorpusCaseContentHash' -count=1
```

Expected: unit fixtures pass. The real-fixture test still fails until Task 3 adds metadata.

### Task 3: Classify the existing nine documents into three store profiles

**Files:**

- Modify: `ChenWeb/benchmark/doc-processors/gold/display-module-v1/manifest.json`
- Modify: `ChenWeb/benchmark/doc-processors/gold/display-module-v1/README.md`
- Modify: `ChenWeb/benchmark/doc-processors/gold/display-module-v1/gold.toml`
- Modify: `ChenWeb/server/api/doc-benchmark/corpus_dataset_test.go`

- [ ] **Step 1: Add the nine-document profile matrix to the real fixture test**

Assert:

```go
wantProfileCounts := map[string]int{
    "regulated-reference":   5,
    "product-specification": 3,
    "narrative-research":    1,
}

wantDocuments := map[string]struct{ profile, kind string }{
    "doc:cn-gb-syn-9706-1-2020":         {"regulated-reference", "authority-standard"},
    "doc:intl-iso-syn-62366-1-2015":     {"regulated-reference", "authority-standard"},
    "doc:intl-iec-syn-60601-1-8-2020":   {"regulated-reference", "authority-standard"},
    "doc:eu-harm-syn-2021":               {"regulated-reference", "authority-standard"},
    "doc:us-syn-guidance-2019":           {"regulated-reference", "authority-standard"},
    "doc:ent-q-syn-001-2026":             {"product-specification", "enterprise-standard"},
    "doc:ent-q-syn-001-2019":             {"product-specification", "enterprise-standard"},
    "doc:ent-q-syn-002-2024":             {"product-specification", "enterprise-standard"},
    "doc:ent-mkt-syn-2025":               {"narrative-research", "marketing-narrative"},
}
```

Also assert that every profile exposes a different expected-processor vector and that the verdict
fixture still has 36 expected and 36 matched cells. Compare every document ID with `wantDocuments`
so a profile/kind swap cannot pass through aggregate counts.

- [ ] **Step 2: Run the real-fixture test and confirm failure**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-benchmark -run TestLoadCorpusDatasetAgainstRealFixture -count=1
```

Expected: FAIL because the real manifest lacks `document_profiles`.

- [ ] **Step 3: Add profile metadata without changing corpus prose**

Set `dataset_version` to `1.1.0`. Map:

- the five `cn`/`international`/`eu`/`us` documents to
  `regulated-reference` / `authority-standard`;
- `doc:ent-q-syn-001-2026`, `doc:ent-q-syn-001-2019`, and
  `doc:ent-q-syn-002-2024` to `product-specification` /
  `enterprise-standard`;
- `doc:ent-mkt-syn-2025` to `narrative-research` / `marketing-narrative`.

Every document must declare this same eight-processor key set:

```text
generate_summaries
generate_topics
extract_structured_knowledge
extract_entity
extract_relation
extract_inventory_items
extract_metrics
extract_provisions
```

Use these profile vectors:

| Processor | Regulated reference | Product specification | Narrative research |
|---|---|---|---|
| `generate_summaries` | `not_required` | `not_required` | `required` |
| `generate_topics` | `useful` | `useful` | `required` |
| `extract_structured_knowledge` | `useful` | `useful` | `useful` |
| `extract_entity` | `not_required` | `useful` | `useful` |
| `extract_relation` | `not_required` | `useful` | `not_required` |
| `extract_inventory_items` | `not_required` | `required` | `not_required` |
| `extract_metrics` | `useful` | `required` | `not_required` |
| `extract_provisions` | `required` | `useful` | `not_required` |

These are authored benchmark expectations, not claims about production policies.

- [ ] **Step 4: Correct stale fixture ownership prose**

In the README and `gold.toml` header:

- replace “once the ontology data repository exists” with ChenWeb as the approved home for
  machine-consumed project fixtures;
- state that a future relocation requires a separate decision;
- document the three profiles and warn that profile expectations do not equal deployed routing;
- keep the synthetic-data warning prominent.

- [ ] **Step 5: Run corpus, grounding, and verdict regression tests**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-benchmark -run 'TestLoadCorpusDataset|TestCorpusCaseContentHash|TestScoreVerdictMatrix' -count=1
go test ./server/api/ontology/comparison -run TestGoldFixture -count=1
go test ./benchmark/doc-processors/gold/display-module-v1 -count=1
```

Expected: PASS, including the unchanged 36/36 comparison result.

- [ ] **Step 6: Commit the ChenWeb corpus contract**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
jj status
jj describe -m "feat: classify gold corpus by store profile"
jj new
```

Expected: the commit includes Tasks 2–3 only; the new working copy is clean.

## Chunk 2: Provenance-bound execution and offline reporting

### Task 4: Emit a schema-v2 `gold-run` result envelope

**Files:**

- Create: `ChenWeb/server/api/doc-benchmark/profile_report.go`
- Modify: `ChenWeb/server/cmd/doc-benchmark/gold_run.go`
- Create: `ChenWeb/server/cmd/doc-benchmark/gold_run_test.go`

- [ ] **Step 1: Confirm the ChenWeb working copy is clean**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
jj status
```

Expected: `The working copy has no changes.` Stop and report unexpected changes before editing.

- [ ] **Step 2: Write failing envelope, state, fetch, and processor-selection tests**

Define expected output using public benchmark types:

```go
func TestGoldRunEnvelopeIncludesProvenance(t *testing.T) {
    got := newGoldRunEnvelope(ds, corpusCase, []string{"extract_metrics"}, false, nil)
    if got.SchemaVersion != 2 ||
        got.Dataset.ID != ds.Manifest.DatasetID ||
        got.Dataset.Version != ds.Manifest.DatasetVersion ||
        got.Dataset.ContentHash != corpusCase.ContentHash ||
        got.CaseID != corpusCase.CaseID ||
        !reflect.DeepEqual(got.SelectedProcessors, []string{"extract_metrics"}) {
        t.Fatalf("bad envelope: %#v", got)
    }
}

func TestResolveProcessorSelectionUsesCanonicalRegistry(t *testing.T)
func TestResolveProcessorSelectionDeduplicatesInRegistryOrder(t *testing.T)
func TestDryRunEnvelopeHasNoSelectedProcessors(t *testing.T)
func TestGoldRunProcessorResultEmitsNonemptyRows(t *testing.T)
func TestGoldRunProcessorResultEmitsRegisteredEmptyRows(t *testing.T)
func TestGoldRunProcessorResultEmitsNotRegisteredWithoutRows(t *testing.T)
func TestGoldRunDocumentRunErrorHasNoProcessorResults(t *testing.T)
func TestProcessorResultTablesIncludeSummariesAndTopics(t *testing.T)
func TestFetchProcessorResultsReturnsNonemptyRows(t *testing.T)
func TestFetchProcessorResultsReturnsRegisteredEmptySlice(t *testing.T)
```

Use `sqlmock` for the fetch tests. Assert the exact mappings
`generate_summaries → kb.summaries/input_record_id` and
`generate_topics → kb.topics/input_record_id`. The registered-empty test must distinguish a
nonnil empty slice from the `nil` returned for an unregistered processor.

- [ ] **Step 3: Run tests and confirm missing types/helpers**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/cmd/doc-benchmark \
  -run 'Test(GoldRunEnvelope|GoldRunProcessorResult|GoldRunDocumentRunError|ResolveProcessorSelection|DryRunEnvelope|ProcessorResultTables|FetchProcessorResults)' \
  -count=1
```

Expected: build/test failure.

- [ ] **Step 4: Add the public result-envelope contract**

In `profile_report.go`, add:

```go
type GoldRunDatasetIdentity struct {
    ID          string `json:"id"`
    Version     string `json:"version"`
    ContentHash string `json:"content_hash"`
}

type GoldRunProcessorResult struct {
    State string            `json:"state"` // "rows" or "not_registered"
    Rows  *[]map[string]any `json:"rows,omitempty"`
}

type GoldRunDocumentResult struct {
    Document string                            `json:"document"`
    RecordID int64                             `json:"record_id"`
    RunError string                            `json:"run_error,omitempty"`
    Results  map[string]GoldRunProcessorResult `json:"results,omitempty"`
}

type GoldRunEnvelope struct {
    SchemaVersion      int                     `json:"schema_version"`
    Dataset            GoldRunDatasetIdentity  `json:"dataset"`
    CaseID             string                  `json:"case_id"`
    SelectedProcessors []string                `json:"selected_processors"`
    DryRun             bool                    `json:"dry_run"`
    Results            []GoldRunDocumentResult `json:"results"`
}
```

Use named constants for schema version and processor-result states. The pointer is a presence
contract:

- `state="rows"` requires a nonnil pointer and emits `"rows":[]` or a nonempty array;
- `state="not_registered"` requires `Rows == nil` and omits the field;
- a document with `run_error` requires no processor results.

- [ ] **Step 5: Make `gold-run` emit only the schema-v2 envelope**

Remove `allGoldProcessors`; resolve processor names through
`docprocessing.OptionalProductionProcessorNames` and
`CanonicalOptionalProductionProcessor`, then return them in registry order.

Replace the string sentinel for missing result tables with:

```go
GoldRunProcessorResult{State: GoldRunResultNotRegistered}
```

Represent a registered table that returned no rows as:

```go
rows := []map[string]any{}
GoldRunProcessorResult{State: GoldRunResultRows, Rows: &rows}
```

Add summaries and topics to `processorResultTables`:

```go
"generate_summaries": {"kb.summaries", "input_record_id"},
"generate_topics":    {"kb.topics", "input_record_id"},
```

Build the final envelope from loaded dataset/case identity. Dry runs have an empty selected
processor list and remain invalid as profile evidence. Producer helpers must make illegal
state/field combinations unrepresentable in normal execution.

- [ ] **Step 6: Run command tests**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/cmd/doc-benchmark \
  -run 'Test(GoldRunEnvelope|GoldRunProcessorResult|GoldRunDocumentRunError|ResolveProcessorSelection|DryRunEnvelope|ProcessorResultTables|FetchProcessorResults)' \
  -count=1
```

Expected: PASS.

### Task 5: Build and render the deterministic profile report

**Files:**

- Modify: `ChenWeb/server/api/doc-benchmark/profile_report.go`
- Create: `ChenWeb/server/api/doc-benchmark/profile_report_test.go`
- Create: `ChenWeb/server/api/doc-benchmark/testdata/profile-report.golden.json`
- Create: `ChenWeb/server/api/doc-benchmark/testdata/profile-report.golden.md`

- [ ] **Step 1: Write a representative report test fixture**

Construct a loaded case with the three profiles and an envelope containing:

- one document with rows;
- one valid empty row set;
- one document-level `run_error`;
- one `not_registered` processor result.

Require report rows with:

```go
type ProfileReportRow struct {
    StoreProfile        string `json:"store_profile"`
    DocumentKind        string `json:"document_kind"`
    Processor           string `json:"processor"`
    Documents           int    `json:"documents"`
    SuccessfulDocuments int    `json:"successful_documents"`
    FailedDocuments     int    `json:"failed_documents"`
    DocumentsWithOutput int    `json:"documents_with_output"`
    OutputRows          int    `json:"output_rows"`
    NotRegistered       int    `json:"not_registered"`
    Applicability       string `json:"applicability"`
    EvidenceKind        string `json:"evidence_kind"`
    Assessment          string `json:"assessment"`
}
```

Baseline evidence kind is always `structural_yield`. Use assessments:

- `required_failure` when any required document failed, was not registered, or had zero rows;
- `required_output_observed` otherwise;
- `useful_review_warning` when useful output is absent or a run failed;
- `useful_output_observed` otherwise;
- `informational_not_required` for `not_required`, regardless of row count.

None of these strings may contain “correct”, “accurate”, or “quality”.

- [ ] **Step 2: Write failing strict-validation tests**

Table-test:

```text
unsupported/missing schema version
dry_run=true
dataset ID mismatch
dataset version mismatch
case ID mismatch
content hash mismatch
unknown selected processor
duplicate selected processor
selected processors out of canonical order
duplicate result document
missing result document
unknown result document
result for unselected processor
missing result for selected processor
unknown processor-result state
rows state with missing rows field
not_registered state with rows field
run_error combined with processor results
inconsistent applicability inside one aggregate key
```

- [ ] **Step 3: Run report tests and confirm failure**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-benchmark -run 'Test(BuildProfileReport|ProfileReport)' -count=1
```

Expected: build/test failure.

- [ ] **Step 4: Implement validation and aggregation**

Add:

```go
func BuildProfileReport(
    ds *CorpusDataset,
    caseID string,
    run GoldRunEnvelope,
) (ProfileReport, error)
```

Validation order must be stable: envelope identity, selected processors, document membership,
per-processor result states, then aggregation. Reuse the corpus case's validated profiles; do not
trust profile metadata copied into the run.

Sort rows lexically by the full `(store_profile, document_kind, processor)` tuple, matching the
approved contract. Populate:

```go
type ProfileReport struct {
    SchemaVersion      int                    `json:"schema_version"`
    Dataset            GoldRunDatasetIdentity `json:"dataset"`
    CaseID             string                 `json:"case_id"`
    SelectedProcessors []string               `json:"selected_processors"`
    Rows               []ProfileReportRow     `json:"rows"`
}
```

Add:

```go
func RenderProfileReportJSON(ProfileReport) ([]byte, error)
func RenderProfileReportMarkdown(ProfileReport) string
```

JSON ends in one newline. Markdown includes a provenance section, the selected processors, a
table of rows, and an explicit note: structural yield is not semantic correctness.

- [ ] **Step 5: Add golden rendering assertions**

Render the representative fixture twice and byte-compare both outputs. Compare each output with
its checked-in golden file. The Markdown table must use stable escaping and ordering.

- [ ] **Step 6: Run report and corpus tests**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-benchmark \
  -run 'Test(BuildProfileReport|ProfileReport|LoadCorpusDataset|CorpusCaseContentHash)' \
  -count=1
```

Expected: PASS.

### Task 6: Add the offline CLI and repeatable mise tasks

**Files:**

- Create: `ChenWeb/server/cmd/doc-benchmark/gold_profile_report.go`
- Modify: `ChenWeb/server/cmd/doc-benchmark/main.go`
- Modify: `ChenWeb/server/cmd/doc-benchmark/main_test.go`
- Modify: `ChenWeb/mise.toml`

- [ ] **Step 1: Write failing CLI tests**

Add:

```go
func TestProfileReportCommandRejectsMissingFlags(t *testing.T)
func TestProfileReportCommandRejectsDryRunEnvelope(t *testing.T)
func TestProfileReportCommandRendersJSON(t *testing.T)
func TestProfileReportCommandRendersMarkdownToFile(t *testing.T)
func TestParseGoldRunEnvelopeRejectsMalformedJSON(t *testing.T)
func TestParseGoldRunEnvelopeRejectsUnknownTopLevelField(t *testing.T)
func TestParseGoldRunEnvelopeRejectsUnknownNestedField(t *testing.T)
func TestParseGoldRunEnvelopeRejectsMultipleJSONValues(t *testing.T)
func TestParseGoldRunEnvelopeRejectsUnversionedShape(t *testing.T)
func TestParseGoldRunEnvelopeRejectsInvalidStateCombinations(t *testing.T)
func TestProfileReportCommandRejectsUnsupportedFormatAsValidationError(t *testing.T)
```

The success tests use a temporary valid corpus and result envelope; they require no DB, NATS,
Typst, or LLM. Parser tests must include `rows` without a `rows` field, `not_registered` with a
`rows` field, and `run_error` with results. Command input errors must wrap `errUsage` so
`execute` emits the existing `validation_error` envelope with exit code 2.

- [ ] **Step 2: Run tests and confirm the command is unknown**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/cmd/doc-benchmark \
  -run 'Test(ProfileReportCommand|ParseGoldRunEnvelope)' -count=1
```

Expected: FAIL with unknown command or missing implementation.

- [ ] **Step 3: Implement `profile-report`**

Flags:

```text
--dataset  required corpus root
--case     required case ID
--results  required schema-v2 gold-run JSON
--format   json (default) or markdown
--output   optional file; stdout when omitted
```

Read the envelope with a strict exported parser:

```go
func ParseGoldRunEnvelope(raw []byte) (GoldRunEnvelope, error)
```

The parser must reject unknown fields at every struct level, multiple JSON values, old/unversioned
input, and invalid state/field combinations. Load the corpus, call `BuildProfileReport`, render
the requested format, and use the existing safe output behavior from the other commands.

- [ ] **Step 4: Add mise tasks**

Add `gold-benchmark-profile-report`:

```toml
[tasks.gold-benchmark-profile-report]
description = "Render a deterministic store-profile report from schema-v2 gold-run JSON."
run = '''
set -euo pipefail
: "${RESULTS:?set RESULTS to an absolute schema-v2 gold-run JSON path}"
DATASET_ROOT="${DATASET_ROOT:-benchmark/doc-processors/gold/display-module-v1}"
CASE_ID="${CASE_ID:-display-module-v1}"
FORMAT="${FORMAT:-json}"
args=(profile-report --dataset "$DATASET_ROOT" --case "$CASE_ID" --results "$RESULTS" --format "$FORMAT")
if [ -n "${OUTPUT:-}" ]; then
  args+=(--output "$OUTPUT")
fi
go run ./server/cmd/doc-benchmark "${args[@]}" "$@"
'''
```

Add `semos-p0-benchmark-evidence` that hard-codes `chenweb_test`, the current dataset/case, and
the eight-processor union from Task 3:

```toml
[tasks.semos-p0-benchmark-evidence]
description = "Run the isolated SemOS P0 store-profile evidence workflow."
run = '''
set -euo pipefail
: "${RESULTS:?set RESULTS to an absolute output JSON path}"
: "${REPORT:?set REPORT to an absolute report JSON path}"
export PG_DB_NAME=chenweb_test
export ARTIFACT_DIR=/Users/cding/Workspace/ThirdParty-2/Data/Artifacts
export ARTIFACT_WEB_DIR=/Users/cding/Workspace/ThirdParty-2/Data/ArtifactWeb
DATASET_ROOT=benchmark/doc-processors/gold/display-module-v1
CASE_ID=display-module-v1
PROCESSORS=generate_summaries,generate_topics,extract_structured_knowledge,extract_entity,extract_relation,extract_inventory_items,extract_metrics,extract_provisions
go run ./server/cmd/doc-benchmark gold-run \
  --dataset "$DATASET_ROOT" \
  --case "$CASE_ID" \
  --artifact-root "$ARTIFACT_DIR" \
  --artifact-web-root "$ARTIFACT_WEB_DIR" \
  --processors "$PROCESSORS" > "$RESULTS"
RESULTS="$RESULTS" OUTPUT="$REPORT" FORMAT=json \
  mise run gold-benchmark-profile-report
'''
```

Both output variables are mandatory. `PG_DB_NAME` and artifact roots are unconditional literals,
not fallback expansions, so ambient production values cannot win.

- [ ] **Step 5: Verify task definitions without executing a database command**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
rg -n -A35 \
  '^\[tasks\.(gold-benchmark-profile-report|semos-p0-benchmark-evidence)\]' \
  mise.toml
sed -n '/^\[tasks\.semos-p0-benchmark-evidence\]/,/^\[tasks\./p' mise.toml |
  rg 'export PG_DB_NAME=chenweb_test'
if sed -n '/^\[tasks\.semos-p0-benchmark-evidence\]/,/^\[tasks\./p' mise.toml |
  rg 'PG_DB_NAME=\$|PG_DB_NAME=.*:-|PG_DB_NAME=.*PG_DB_NAME'; then
  exit 1
fi
```

Expected: task text contains literal `export PG_DB_NAME=chenweb_test`, isolated artifact roots,
the processor union, required output checks, and output redirection. This is static verification
only and cannot contact a database.

- [ ] **Step 6: Run CLI and package tests**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/cmd/doc-benchmark -count=1
go test ./server/api/doc-benchmark -count=1
```

Expected: PASS without external services.

- [ ] **Step 7: Commit the ChenWeb execution/reporting change**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
jj status
jj describe -m "feat: report gold benchmark yield by store profile"
jj new
```

Expected: only Tasks 4–6 are in the commit; the new working copy is clean.

## Chunk 3: DR16 consolidation and architecture correction

### Task 7: Write the merged keyword-canonicalization specification

**Files:**

- Create: `KnowledgeStore/doc-repo/specs/202607/2026073006-spec-semos-keyword-canonicalization.md`
- Modify: `KnowledgeStore/doc-repo/specs/202607/2026072301-spec-keyword-canonicalization-reconciliation.md`
- Modify: `KnowledgeStore/doc-repo/specs/202607/2026072703-spec-keyword-canonicalization-reconciliation-2.md`
- Reference: `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (DR15–DR16)

- [ ] **Step 1: Confirm the KnowledgeStore working copy is clean**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
jj status
```

Expected: `The working copy has no changes.` Stop and report unexpected changes before editing.

- [ ] **Step 2: Add supersession banners to both historical specs**

Immediately below each title, add:

```markdown
> **Superseded on 2026-07-30 by
> `2026073006-spec-semos-keyword-canonicalization.md`.**
> Retained as historical design input; do not implement independently.
```

Do not delete or rewrite their historical bodies.

- [ ] **Step 3: Create the merged specification**

Use this required section structure:

```text
1. Status, lineage, and scope
2. Goals and non-goals
3. Terminology and four identity layers
4. Shared DR15 kernel contract
5. Postgres data model
6. Deterministic working-mode resolution
7. Asynchronous reconciliation
8. Merge, split, never-merge, and ambiguity state machines
9. Provenance, audit, and rollback
10. API contracts
11. Seed and normalization-version lifecycle
12. Metrics and operational limits
13. Security and failure handling
14. Migration/compatibility boundaries
15. Acceptance tests
16. Deferred work
```

The content must include every bullet in approved design §3.1. Use DR16's exact table names:

```text
kb.keyword_concepts
kb.keyword_surfaces
kb.keyword_surface_keys
kb.keyword_mentions
kb.keyword_unresolved
kb.keyword_rewrite_rules
kb.semid_decision_log
kb.semid_never_merge
kb.semid_snapshots
```

State explicitly:

- `lexform` is a derived/versioned lookup identity, not an independently governed meaning;
- keyword concepts are lexical identities; ontology terms are governed meanings;
- `aligns_to_term` is reviewed and does not imply `owl:sameAs`;
- online resolution makes no LLM call;
- reconciliation never scans the full concept table in an LLM prompt;
- ambiguity is stored, not forced;
- A→B and B→C decisions do not create a new inferred A→C decision;
- SQLite-first storage and a keyword-owned reconciliation engine are rejected;
- implementation is P3 and remains unstarted by this documentation task.

- [ ] **Step 4: Check lineage and required contracts**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
merged_spec=doc-repo/specs/202607/2026073006-spec-semos-keyword-canonicalization.md
required_patterns=(
  'occurrence'
  'surface'
  'lexform'
  'keyword concept'
  'aligns_to_term'
  'never_merge'
  'no transitive'
  'Postgres'
  'SQLite'
  'ambiguous'
  'unresolved'
  'semid'
  'online.*no LLM|no LLM.*online|deterministic.*online'
  'bounded.*reconciliation|candidate-bounded'
  'negative cach'
  'tombstone'
  'locked.*human|human.*locked'
  'kb\.keyword_concepts'
  'kb\.keyword_surfaces'
  'kb\.keyword_surface_keys'
  'kb\.keyword_mentions'
  'kb\.keyword_unresolved'
  'kb\.keyword_rewrite_rules'
  'kb\.semid_decision_log'
  'kb\.semid_never_merge'
  'kb\.semid_snapshots'
  '\bresolved\b'
  '\brejected\b'
  'aligns_to_term.*review|review.*aligns_to_term'
  'owl:sameAs'
  'derived.*versioned.*normal|versioned.*derived.*normal'
  'never.*full.*table.*LLM|full.*table.*never.*LLM'
  'keyword-owned.*reconciliation.*reject|reconciliation engine.*rejected'
  'P3.*unstarted|P3.*not started|implementation.*P3.*unstarted'
)
for pattern in "${required_patterns[@]}"; do
  rg -qi "$pattern" "$merged_spec" || exit 1
done
rg -n 'Superseded on 2026-07-30 by' \
  doc-repo/specs/202607/2026072301-spec-keyword-canonicalization-reconciliation.md
rg -n '2026073006-spec-semos-keyword-canonicalization' \
  doc-repo/specs/202607/2026072301-spec-keyword-canonicalization-reconciliation.md
rg -n 'Superseded on 2026-07-30 by' \
  doc-repo/specs/202607/2026072703-spec-keyword-canonicalization-reconciliation-2.md
rg -n '2026073006-spec-semos-keyword-canonicalization' \
  doc-repo/specs/202607/2026072703-spec-keyword-canonicalization-reconciliation-2.md
git diff --check
```

Expected: each required contract and both supersession pointers are present; no whitespace errors.

- [ ] **Step 5: Commit the KnowledgeStore keyword consolidation**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
jj status
jj describe -m "docs: merge SemOS keyword canonicalization specs"
jj new
```

Expected: only the new merged spec and two historical status banners are committed.

### Task 8: Align the ADR, handoff, and operations guide

**Files:**

- Modify: `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`
- Modify: `KnowledgeStore/doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md`
- Modify: `KnowledgeStore/doc-repo/devdocs/202607/2026073002-devdoc-gold-benchmark-operations.md`

- [ ] **Step 1: Reconfirm the KnowledgeStore working copy is clean**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
jj status
```

Expected: clean working copy after Task 7's commit.

- [ ] **Step 2: Update the ADR decision record**

Make these bounded edits:

1. Add a 2026-07-30 revision-log entry for the P0 closeout.
2. Replace DR17's physical standalone-repository requirement with a logical
   ontology/policy-data package:
   - human documentation in KnowledgeStore;
   - ChenWeb-specific machine data and code in ChenWeb;
   - proven multi-consumer modules may later move to `shared`;
   - a fourth repository requires a new explicit decision.
3. Preserve source commit/content checksum release provenance as a future P2 contract, but do not
   claim a repository or release compiler exists.
4. Reconcile AD8 so it no longer rejects the approved placement.
5. Resolve OD7/repository hosting under the workspace policy.
6. Update all 20 CQ owner-review cells to `Approved by user — 2026-07-30`.
7. Link the merged spec from DR16 and record both predecessors as superseded.
8. Keep P0 open until the evidence run in Task 9 succeeds; do not pre-announce its result.
9. Move authoritative real standards, authoritative editions, and a real-data worked example from
   P0 exit blockers to future validation. The approved synthetic benchmark is sufficient for P0.
10. Treat the existing three store-shaped profiles as satisfying P0 fixture-family breadth; do
    not retain “broaden beyond one fixture family” as a closeout blocker.
11. Replace the stale explanation that `Pending ... owner` cells still require approval.

Search the entire ADR—not only DR17—for physical-repository assumptions. Reconcile:

- the architecture/source tree (`<ontology-repo>`);
- policy-authoring and compiler input descriptions;
- `ONTOLOGY_REPO_REF`, module-root, checkout, pinning, and release language;
- phase descriptions and P0 actions;
- consequences and operational/release sections;
- open decisions and documentation-impact sections;
- alternatives that call ChenWeb placement categorically invalid.

Use logical `ontology/policy package` or `source package` terminology. Preserve future immutable
source revision plus content-checksum provenance, but do not imply a fourth repository, a current
checkout, or a compiler that does not exist.

- [ ] **Step 3: Update the handoff without overstating implementation**

Remove:

- “separate repo does not exist” as a blocker;
- “stand up `semos-ontology` repository and CI” as a next step;
- pending CQ approval;
- claims that P0 has no code at all.
- authoritative editions, a real-data example, and broader fixture families as P0 blockers.

Replace them with:

- logical package placement is resolved;
- benchmark tooling is P0 validation code, not ontology runtime;
- P1–P7 remain unstarted;
- live evidence run and merged keyword spec status reflect actual completion at this step.
- the Task 9 isolated evidence run is the remaining P0 closeout gate after the documentation
  changes in this chunk.

- [ ] **Step 4: Extend benchmark operations**

Document:

- the three profile definitions and the eight-processor union;
- schema-v2 envelope provenance fields;
- `gold-benchmark-profile-report`;
- `semos-p0-benchmark-evidence`;
- the difference among rows, empty rows, unregistered tables, and run failures;
- the evidence-kind limitation: structural yield is not correctness;
- exact `chenweb_test` and artifact prerequisites;
- generated output files must live outside the repositories.

- [ ] **Step 5: Run enforcing contradiction checks**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
if rg -n \
  '<ontology-repo>|ONTOLOGY_REPO_REF|ONTOLOGY_MODULE_ROOT|ontology data repository|data repository|dedicated repository|separate repository|separate git-authored|second repository|stand up.*semos-ontology|owner approval.*pending|once the ontology data repository exists' \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md \
  doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md \
  doc-repo/devdocs/202607/2026073002-devdoc-gold-benchmark-operations.md \
  ../ChenWeb/benchmark/doc-processors/gold/display-module-v1/README.md \
  ../ChenWeb/benchmark/doc-processors/gold/display-module-v1/gold.toml; then
  exit 1
fi
if rg -n \
  'real-data.*P0 blocker|authoritative edition.*P0 blocker|broaden.*fixture.*P0 blocker|Pending .* owner.*means' \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md \
  doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md; then
  exit 1
fi
if rg -n \
  'Structurally frozen.*owner approval still pending|Still open before P0 exit:.*(authoritative|real-data|broader)' \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md; then
  exit 1
fi
handoff_open="$(
  sed -n '/^\*\*Not done, still open within P0:\*\*/,/^\*\*P1.P7:/p' \
    doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md
)"
test -n "$handoff_open" || exit 1
if printf '%s\n' "$handoff_open" |
  rg 'authoritative standard editions|real-data worked example|Broaden the fixture corpus|broaden.*fixture'; then
  exit 1
fi
approved_count="$(
  rg -c '^\| CQ-[A-Z][0-9][0-9] .* Approved by user — 2026-07-30 \|$' \
    doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md
)"
test "$approved_count" -eq 20 || exit 1
if rg -n 'Pending (domain|ontology|application) owner' \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md; then
  exit 1
fi
rg -n \
  'logical.*package|source.*checksum|future validation|Task 9|evidence run|Approved by user' \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md \
  doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md
git diff --check
```

Expected: no normative standalone-repository or stale P0-blocker phrase remains. Historical input
documents outside this check may retain the old proposal when clearly marked superseded.

- [ ] **Step 6: Commit the KnowledgeStore architecture correction**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
jj status
jj describe -m "docs: align SemOS architecture with workspace ownership"
jj new
```

Expected: ADR, handoff, and operations guide are committed; working copy is clean.

## Chunk 4: Execute evidence and close P0

### Task 9: Run the isolated benchmark and record the finding

**Files:**

- Create outside repositories: `/tmp/semos-p0-<timestamp>/gold-run.json`
- Create outside repositories: `/tmp/semos-p0-<timestamp>/profile-report.json`
- Create outside repositories: `/tmp/semos-p0-<timestamp>/profile-report.md`
- Create: `KnowledgeStore/doc-repo/devdocs/202607/2026073005-devdoc-semos-p0-benchmark-evidence.md`

- [ ] **Step 1: Confirm committed, clean repositories and prerequisites**

Run:

```bash
set -euo pipefail
cd /Users/cding/Workspace/ChenWeb
jj status
test -z "$(jj diff --summary)" || exit 1
command -v typst
go test ./server/api/doc-benchmark ./server/cmd/doc-benchmark -count=1

cd /Users/cding/Workspace/KnowledgeStore
jj status
test -z "$(jj diff --summary)" || exit 1
```

Expected: both working copies are clean, Typst resolves, and focused tests pass. Stop rather than
recording closeout evidence from a dirty tree.

- [ ] **Step 2: Create, execute, validate, and hash the evidence in one shell session**

Run:

```bash
set -euo pipefail
cd /Users/cding/Workspace/ChenWeb
SEMOS_EVIDENCE_DIR="$(mktemp -d /tmp/semos-p0-XXXXXXXX)"
printf '%s\n' "$SEMOS_EVIDENCE_DIR"
RESULTS="$SEMOS_EVIDENCE_DIR/gold-run.json" \
REPORT="$SEMOS_EVIDENCE_DIR/profile-report.json" \
mise run semos-p0-benchmark-evidence
RESULTS="$SEMOS_EVIDENCE_DIR/gold-run.json" \
OUTPUT="$SEMOS_EVIDENCE_DIR/profile-report.md" \
FORMAT=markdown \
mise run gold-benchmark-profile-report

expected_processors='[
  "generate_summaries",
  "generate_topics",
  "extract_structured_knowledge",
  "extract_entity",
  "extract_relation",
  "extract_inventory_items",
  "extract_metrics",
  "extract_provisions"
]'
jq -e --argjson expected "$expected_processors" '
  .schema_version == 2 and
  .dry_run == false and
  .dataset.id == "doc-processors-corpus-display-module" and
  .dataset.version == "1.1.0" and
  (.dataset.content_hash | startswith("sha256:")) and
  .case_id == "display-module-v1" and
  .selected_processors == $expected and
  (.results | length) == 9 and
  ([.results[].document] | unique | length) == 9
' "$SEMOS_EVIDENCE_DIR/gold-run.json"

jq -e '
  .schema_version == 1 and
  .dataset.id == "doc-processors-corpus-display-module" and
  .dataset.version == "1.1.0" and
  .case_id == "display-module-v1" and
  ([.rows[].store_profile] | unique) ==
    ["narrative-research", "product-specification", "regulated-reference"] and
  ([.rows | group_by(.store_profile)[] |
      map(.processor + ":" + .applicability) | sort | join(",")] |
    unique | length) == 3 and
  ([.rows | group_by(.store_profile)[] |
      map(.processor + ":" + (.documents_with_output|tostring) + ":" +
          (.output_rows|tostring) + ":" + (.failed_documents|tostring)) |
      sort | join(",")] |
    unique | length) >= 2
' "$SEMOS_EVIDENCE_DIR/profile-report.json"

run_content_hash="$(jq -r '.dataset.content_hash' "$SEMOS_EVIDENCE_DIR/gold-run.json")"
report_content_hash="$(jq -r '.dataset.content_hash' "$SEMOS_EVIDENCE_DIR/profile-report.json")"
test "$run_content_hash" = "$report_content_hash" || exit 1

jj log -r @- --no-graph -T 'commit_id ++ "\n"'
shasum -a 256 \
  "$SEMOS_EVIDENCE_DIR/gold-run.json" \
  "$SEMOS_EVIDENCE_DIR/profile-report.json" \
  "$SEMOS_EVIDENCE_DIR/profile-report.md"
jq '{
  schema_version,
  dataset,
  case_id,
  selected_processors,
  dry_run,
  documents: (.results | length),
  completed_documents: ([.results[] | select((.run_error // "") == "")] | length),
  failed_documents: ([.results[] | select((.run_error // "") != "")] | length)
}' "$SEMOS_EVIDENCE_DIR/gold-run.json"
jq '{
  rows: (.rows | length),
  profiles: ([.rows[].store_profile] | unique),
  aggregate_failed_processor_documents: ([.rows[].failed_documents] | add),
  aggregate_documents_with_output: ([.rows[].documents_with_output] | add)
}' "$SEMOS_EVIDENCE_DIR/profile-report.json"
printf '%s\n' "$SEMOS_EVIDENCE_DIR" > /tmp/semos-p0-evidence-dir
```

The mise task must unconditionally set `PG_DB_NAME=chenweb_test`, the isolated artifact roots,
the display-module dataset/case, and the eight processors shown above.

Expected: one absolute `/tmp/semos-p0-*` directory; both commands exit 0; schema version 2,
`dry_run=false`, nine unique documents, the exact canonical processor list, three exact profiles,
three different expected vectors, and at least two different observed yield/failure vectors.
The output includes explicit completed- and failed-document counts plus stable hashes. Any failed
assertion leaves P0 open. A document-level processor failure may be retained as evidence; an
infrastructure or validation failure does not satisfy P0.

- [ ] **Step 3: Write the bounded evidence document**

Restore and validate the recorded path before reading evidence:

```bash
SEMOS_EVIDENCE_DIR="$(< /tmp/semos-p0-evidence-dir)"
test -d "$SEMOS_EVIDENCE_DIR" || exit 1
printf '%s\n' "$SEMOS_EVIDENCE_DIR"
```

Record:

- execution date/time and timezone;
- ChenWeb commit ID;
- exact command and environment overrides;
- dataset ID/version/case content hash;
- selected processors;
- gold-run file SHA-256 and profile-report JSON/Markdown SHA-256;
- document count, completion count, failure count;
- the report table or a concise per-profile summary;
- which assessments are `structural_yield`;
- any deterministic gold result, including the separate unchanged 36/36 verdict check;
- the bounded conclusion that profile differences justify store-aware policy as a P1 requirement;
- explicit non-claims: no production routing, no semantic correctness from row counts, no real
  regulatory authority, no P2 ontology runtime.

Do not copy raw LLM output or sensitive configuration into KnowledgeStore.

- [ ] **Step 4: Commit the evidence document**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
git diff --check
jj status
jj describe -m "docs: record SemOS P0 store-profile benchmark evidence"
jj new
```

Expected: the commit contains only the evidence document; generated JSON/Markdown remain in
`/tmp`.

### Task 10: Mark P0 complete and verify both repositories

**Files:**

- Modify: `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`
- Modify: `KnowledgeStore/doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md`
- Modify: `KnowledgeStore/doc-repo/specs/202607/2026073005-spec-semos-p0-benchmark-led-closeout.md`

- [ ] **Step 1: Run final ChenWeb verification before changing P0 status**

Run:

```bash
set -euo pipefail
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/doc-processing -count=1
go test ./server/api/doc-benchmark -count=1
go test ./server/cmd/doc-benchmark -count=1
go test ./server/api/ontology/comparison -count=1
go test ./benchmark/doc-processors/gold/display-module-v1 -count=1
go vet ./server/api/doc-processing ./server/api/doc-benchmark ./server/cmd/doc-benchmark
jj status
test -z "$(jj diff --summary)" || exit 1
```

Expected: all tests and vet pass; ChenWeb is clean because its changes were already committed.

- [ ] **Step 2: Update status only after evidence assertions and final verification pass**

After Task 9 and Step 1 succeed:

- mark all §8 acceptance criteria in spec `2026073005` implemented;
- mark P0 complete in the ADR and handoff;
- link merged keyword spec `2026073006` and evidence devdoc `2026073005`;
- state exactly that `P1–P7 remain unstarted`;
- list remaining real-data/authoritative-edition work as future validation, not a P0 blocker;
- preserve any observed run failures in the evidence summary.

- [ ] **Step 3: Add the development documentation protocol answers to the handoff**

Before committing, ensure the final handoff explicitly answers:

```text
What knowledge changed?
Which docs/specs/ADRs/tests are affected?
Which docs were updated?
Which docs are now stale?
What was intentionally left undocumented?
```

Required answers:

- knowledge changed: approved repository ownership plus observed, labeled benchmark evidence now
  justify store-aware policy as a P1 requirement;
- affected artifacts: ChenWeb corpus/registry/envelope/reporter code and tests plus the
  KnowledgeStore documents below;
- documents updated: ADR `2026072901`, handoff `2026073002`, operations devdoc `2026073002`,
  closeout spec `2026073005`, merged keyword spec `2026073006`, predecessor specs `2026072301`
  and `2026072703`, evidence devdoc `2026073005`, and the ChenWeb display-module README and
  `gold.toml` comments;
- stale documents: the two keyword predecessor specs remain historical but are explicitly
  superseded;
- intentionally undocumented: raw model responses, secrets, generated artifact contents, and
  claims unsupported by deterministic or labeled structural evidence.

- [ ] **Step 4: Run stale-language and protocol checks**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
adr=doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md
handoff=doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md
closeout_spec=doc-repo/specs/202607/2026073005-spec-semos-p0-benchmark-led-closeout.md

rg -qi 'P0.*complete|complete.*P0' "$adr" || exit 1
rg -qi 'P0.*complete|complete.*P0' "$handoff" || exit 1
rg -q 'Status:.*Implemented' "$closeout_spec" || exit 1
for file in "$adr" "$handoff" "$closeout_spec"; do
  rg -q 'P1–P7 remain unstarted' "$file" || exit 1
  rg -q '2026073006-spec-semos-keyword-canonicalization' "$file" || exit 1
  rg -q '2026073005-devdoc-semos-p0-benchmark-evidence' "$file" || exit 1
done
approved_count="$(rg -c 'Approved by user — 2026-07-30' "$adr")"
test "$approved_count" -eq 20 || exit 1
for heading in \
  'What knowledge changed?' \
  'Which docs/specs/ADRs/tests are affected?' \
  'Which documents were updated?' \
  'Which documents are now stale?' \
  'What was intentionally left undocumented?'; do
  rg -Fq "$heading" "$handoff" || exit 1
done

if rg -n \
  'stand up.*semos-ontology|owner approval.*pending|P0.*still open|P1 (is|has|implementation has) started|P2 (is|has|implementation has) started' \
  "$adr" "$handoff" "$closeout_spec"; then
  exit 1
fi

unstarted_count="$(
  rg -l 'P1–P7 remain unstarted' \
    "$adr" "$handoff" "$closeout_spec" |
  wc -l | tr -d ' '
)"
test "$unstarted_count" -eq 3 || exit 1
git diff --check
```

Expected: positive references and protocol headings are present, stale closeout claims are absent,
and all three status documents say exactly that P1–P7 remain unstarted.

- [ ] **Step 5: Commit final KnowledgeStore closeout**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
jj status
jj describe -m "docs: close SemOS ontology P0"
jj new
jj status
```

Expected: final status documents are committed and the new working copy is clean.
