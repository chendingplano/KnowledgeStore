# Structured LLM JSON Contract Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a strict-by-default structured-output contract in `shared/go/api/llm` so all workspace LLM JSON calls are validated, retried, and failed closed unless they satisfy an explicit machine-readable contract.

**Architecture:** Add a new structured-output engine in `shared/go/api/llm` that accepts a prompt plus a schema contract, requests provider-enforced structured output when supported, parses and validates the reply, performs bounded repair/retry when the reply is malformed, and returns typed failure classes when the contract is not met. Keep `ExtractJSON` as a compatibility bridge on top of the new engine, then migrate ChenWeb doc-processing and handler call sites to explicit strict contracts as the first adopter.

**Tech Stack:** Go, `net/http`, `encoding/json`, JSON Schema validation, shared LLM provider adapters, workspace `go.work`, ChenWeb doc-processing.

---

## File Structure

Shared contract layer:

- Modify: `shared/go/api/llm/openai_client.go`
- Modify: `shared/go/api/llm/openai_client_test.go`
- Modify: `shared/go/api/llm/types.go`
- Modify: `shared/go/go.mod`
- Modify: `shared/go/go.sum`
- Create: `shared/go/api/llm/structured_output.go`
- Create: `shared/go/api/llm/structured_output_test.go`
- Create: `shared/go/api/llm/structured_output_schema.go`
- Create: `shared/go/api/llm/structured_output_schema_test.go`
- Create: `shared/go/api/llm/structured_output_retry.go`
- Create: `shared/go/api/llm/structured_output_retry_test.go`
- Create: `shared/go/api/llm/structured_output_errors.go`
- Create: `shared/go/api/llm/structured_output_errors_test.go`
- Create: `shared/go/api/llm/json_repair.go`
- Create: `shared/go/api/llm/json_repair_test.go`

ChenWeb first-adopter migration:

- Modify: `ChenWeb/server/api/doc-processing/extract-doc-metadata.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-metrics.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-products.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-provisions.go`
- Modify: `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
- Modify: `ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go`
- Modify: `ChenWeb/server/api/doc-processing/topic_chunking_shared.go`
- Modify: `ChenWeb/server/api/kbhandler/extract-metric-handler.go`
- Modify: `ChenWeb/server/api/kbhandler/extract-provision-handler.go`
- Modify: `ChenWeb/server/api/doc-processing/doc-structure-analyzer.go`

ChenWeb schema-contract definitions and migration tests:

- Create: `ChenWeb/server/api/doc-processing/llm_contracts.go`
- Create: `ChenWeb/server/api/doc-processing/llm_contracts_test.go`

Docs:

- Create: `docs/superpowers/specs/2026-05-23-structured-llm-json-contract-design.md`
- Create: `KnowledgeStore/Capsules/coding-capsules/doc-processor/structured-llm-json-contract.md`

## Cross-Cutting Decisions

### Strict-By-Default Rule

All new structured JSON calls must use the new contract API. Prompt text may still describe semantics, but schema shape, required fields, allowed fields, and type validation must come from code.

### Compatibility Rule

`ExtractJSON` remains temporarily available, but its implementation should route through the new engine with a permissive fallback contract so existing callers keep working while explicit-schema migrations happen incrementally.

### Retry Rule

Retries are for malformed or schema-invalid model output only. They are not for semantic disagreement in downstream business logic. Retry count must be small and bounded.

### Repair Rule

Repair may fix obvious serialization breakage such as code fences, leading prose, truncated wrappers, or unescaped embedded quotes when the string boundaries are otherwise recoverable. Repair must never invent missing semantic fields.

### Observability Rule

Every structured-output failure must log:

- schema name
- model name
- base URL / provider
- failure class
- retry attempt
- whether repair was attempted

Do not log full raw payloads indiscriminately if they may contain large or sensitive document text. Prefer trimmed excerpts.

## Chunk 1: Shared Structured Output Foundation

### Task 1: Define the new contract types and error model

**Files:**
- Modify: `shared/go/api/llm/types.go`
- Create: `shared/go/api/llm/structured_output_errors.go`
- Create: `shared/go/api/llm/structured_output_errors_test.go`

- [ ] **Step 1: Write the failing tests**

Cover:

- contract requires a non-empty schema name
- contract requires a non-empty machine-readable schema
- failure classes distinguish parse failure, schema validation failure, provider failure, and exhausted retries

- [ ] **Step 2: Add contract types**

Define focused types such as:

```go
type StructuredOutputContract struct {
	Name              string
	Schema            json.RawMessage
	AllowRepair       bool
	MaxRetries        int
	DisallowExtraKeys bool
}

type StructuredOutputResult struct {
	Parsed map[string]any
	Raw    string
}
```

- [ ] **Step 3: Add typed errors**

Create errors or sentinel wrappers that callers can test with `errors.Is` / `errors.As` for:

- invalid contract
- provider request failure
- parse failure
- schema validation failure
- retries exhausted

- [ ] **Step 4: Run tests**

Run: `cd /Users/cding/Workspace/shared/go && go test ./api/llm -run 'StructuredOutputErrors|StructuredOutputContract'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/cding/Workspace/shared add api/llm/types.go api/llm/structured_output_errors.go api/llm/structured_output_errors_test.go
git -C /Users/cding/Workspace/shared commit -m "feat: add structured output contract types"
```

### Task 2: Add schema compilation and validation

**Files:**
- Create: `shared/go/api/llm/structured_output_schema.go`
- Create: `shared/go/api/llm/structured_output_schema_test.go`
- Modify: `shared/go/go.mod`
- Modify: `shared/go/go.sum`

- [ ] **Step 1: Write the failing validation tests**

Cover:

- required field missing
- wrong field type
- unexpected extra field when disallowed
- nested array/object validation

- [ ] **Step 2: Add a JSON Schema validator**

Use a library that supports in-process validation of JSON Schema documents and cache compiled schemas by contract name to avoid recompiling on every request.

- [ ] **Step 3: Expose focused helpers**

Create helpers resembling:

```go
func compileStructuredSchema(contract StructuredOutputContract) (*compiledSchema, error)
func validateStructuredJSON(contract StructuredOutputContract, payload map[string]any) error
```

- [ ] **Step 4: Sync workspace dependencies**

Run from workspace root: `go work sync`

- [ ] **Step 5: Run tests**

Run: `cd /Users/cding/Workspace/shared/go && go test ./api/llm -run 'StructuredOutputSchema|ValidateStructuredJSON'`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git -C /Users/cding/Workspace/shared add go.mod go.sum api/llm/structured_output_schema.go api/llm/structured_output_schema_test.go
git -C /Users/cding/Workspace/shared commit -m "feat: add structured output schema validation"
```

## Chunk 2: Parsing, Repair, And Retry Pipeline

### Task 3: Add conservative JSON repair helpers

**Files:**
- Create: `shared/go/api/llm/json_repair.go`
- Create: `shared/go/api/llm/json_repair_test.go`
- Modify: `shared/go/api/llm/openai_client_test.go`

- [ ] **Step 1: Write the failing repair tests**

Cover:

- markdown JSON fences
- leading explanatory prose followed by JSON
- invalid embedded quotes in a string field
- truncated wrapper with intact inner object
- malformed payload that should remain unrepaired

- [ ] **Step 2: Implement conservative repair**

Add helpers that normalize known wrapper noise and attempt tightly-scoped quote repair only when the parser can recover unambiguously.

- [ ] **Step 3: Keep the failure boundary strict**

If repair would require guessing field values or structure, return failure rather than silently mutating semantics.

- [ ] **Step 4: Run tests**

Run: `cd /Users/cding/Workspace/shared/go && go test ./api/llm -run 'JSONRepair|ExtractJSON'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/cding/Workspace/shared add api/llm/json_repair.go api/llm/json_repair_test.go api/llm/openai_client_test.go
git -C /Users/cding/Workspace/shared commit -m "feat: add conservative json repair helpers"
```

### Task 4: Build the shared structured-output execution path

**Files:**
- Create: `shared/go/api/llm/structured_output.go`
- Create: `shared/go/api/llm/structured_output_retry.go`
- Create: `shared/go/api/llm/structured_output_test.go`
- Create: `shared/go/api/llm/structured_output_retry_test.go`
- Modify: `shared/go/api/llm/openai_client.go`

- [ ] **Step 1: Write the failing end-to-end tests**

Cover:

- success on valid JSON matching schema
- retry after parse failure then success
- retry after schema validation failure then success
- failure after retries exhausted
- repair succeeds before retry

- [ ] **Step 2: Implement a new public API**

Add a method resembling:

```go
func (c *OpenAIJSONClient) ExtractStructuredJSON(ctx context.Context, in JSONExtractionInput, contract StructuredOutputContract) (*StructuredOutputResult, error)
```

- [ ] **Step 3: Add retry prompt feedback**

On retry, prepend machine-readable feedback like:

- invalid JSON syntax
- missing required fields
- wrong field types
- extra fields not allowed

The retry instruction must ask for the same data, JSON only, with no prose.

- [ ] **Step 4: Prefer provider-enforced structured output when possible**

For providers/endpoints that support schema-constrained responses, send the contract schema in the request. For providers that do not, fall back to prompt + validation + retry.

- [ ] **Step 5: Keep raw transport separate from validation**

Refactor `openai_client.go` so HTTP request/response handling remains small and reusable while structured-output orchestration lives in the new files.

- [ ] **Step 6: Run tests**

Run: `cd /Users/cding/Workspace/shared/go && go test ./api/llm -run 'StructuredOutput|ExtractStructuredJSON'`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git -C /Users/cding/Workspace/shared add api/llm/openai_client.go api/llm/structured_output.go api/llm/structured_output_retry.go api/llm/structured_output_test.go api/llm/structured_output_retry_test.go
git -C /Users/cding/Workspace/shared commit -m "feat: add strict structured output execution path"
```

## Chunk 3: Compatibility Bridge And Shared Adoption Safety

### Task 5: Re-implement `ExtractJSON` on top of the new engine

**Files:**
- Modify: `shared/go/api/llm/openai_client.go`
- Modify: `shared/go/api/llm/openai_client_test.go`

- [ ] **Step 1: Write the failing compatibility tests**

Cover:

- existing callers still receive `map[string]any`
- markdown-fenced JSON still parses
- invalid JSON errors now include failure class context
- permissive legacy contract allows unknown keys at top level

- [ ] **Step 2: Route through a legacy contract**

Keep `ExtractJSON` public, but make it call `ExtractStructuredJSON` with a compatibility contract like:

- top-level object required
- additional properties allowed
- minimal retries enabled
- repair enabled

- [ ] **Step 3: Preserve useful error text**

Carry forward the current raw-response excerpt behavior while adding structured failure metadata.

- [ ] **Step 4: Run tests**

Run: `cd /Users/cding/Workspace/shared/go && go test ./api/llm`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/cding/Workspace/shared add api/llm/openai_client.go api/llm/openai_client_test.go
git -C /Users/cding/Workspace/shared commit -m "refactor: route legacy ExtractJSON through strict engine"
```

### Task 6: Add logging and rollout documentation

**Files:**
- Modify: `shared/go/api/llm/openai_client.go`
- Create: `KnowledgeStore/Capsules/coding-capsules/doc-processor/structured-llm-json-contract.md`
- Create: `docs/superpowers/specs/2026-05-23-structured-llm-json-contract-design.md`

- [ ] **Step 1: Add structured logs**

Ensure success/failure logs include:

- contract name
- model
- provider/base URL
- attempts used
- repair attempted
- final failure class

- [ ] **Step 2: Document the contract**

Write a short internal design/reference doc describing:

- why prompt-only JSON is insufficient
- how to declare contracts
- when to enable repair
- when to use retries

- [ ] **Step 3: Run targeted tests**

Run: `cd /Users/cding/Workspace/shared/go && go test ./api/llm -run 'ExtractStructuredJSON|ExtractJSON'`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git -C /Users/cding/Workspace/shared add api/llm/openai_client.go /Users/cding/Workspace/docs/superpowers/specs/2026-05-23-structured-llm-json-contract-design.md /Users/cding/Workspace/KnowledgeStore/Capsules/coding-capsules/doc-processor/structured-llm-json-contract.md
git -C /Users/cding/Workspace/shared commit -m "docs: add structured output rollout guidance"
```

## Chunk 4: ChenWeb First-Adopter Migration

### Task 7: Define shared ChenWeb contracts for current strict JSON flows

**Files:**
- Create: `ChenWeb/server/api/doc-processing/llm_contracts.go`
- Create: `ChenWeb/server/api/doc-processing/llm_contracts_test.go`

- [ ] **Step 1: Write the failing schema tests**

Add tests ensuring contracts exist for at least:

- doc metadata extraction
- metric candidate extraction / enrichment
- product extraction
- provision extraction
- topic extraction
- scene block generation

- [ ] **Step 2: Move schema shape out of prompts and into code**

For each contract, define a machine-readable schema with:

- required fields
- optional fields
- nested array/object shapes
- additional-properties policy

- [ ] **Step 3: Keep prompts semantic**

Do not try to encode the entire schema in the prompt anymore. Leave prompts responsible for task semantics, not final shape enforcement.

- [ ] **Step 4: Run tests**

Run: `cd /Users/cding/Workspace/ChenWeb && go test ./server/api/doc-processing -run 'LLMContracts'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/cding/Workspace/ChenWeb add server/api/doc-processing/llm_contracts.go server/api/doc-processing/llm_contracts_test.go
git -C /Users/cding/Workspace/ChenWeb commit -m "feat: add ChenWeb structured output contracts"
```

### Task 8: Migrate the highest-risk doc-processing paths first

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/topic_chunking_shared.go`
- Modify: `ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-provisions.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-products.go`

- [ ] **Step 1: Write failing migration tests**

Cover:

- invalid quote in `topic_desc_en` retries and succeeds
- missing required scene block fields retries and succeeds
- unexpected provision payload shape fails with validation error class
- product extraction still falls back cleanly between models when configured

- [ ] **Step 2: Update call sites to use explicit contracts**

Replace direct `ExtractJSON` calls with `ExtractStructuredJSON` plus the relevant schema contract.

- [ ] **Step 3: Normalize error handling**

Return errors that preserve the business context (`block_no`, `record_id`, operation name) while exposing structured-output failure class in the wrapped error.

- [ ] **Step 4: Run targeted tests**

Run: `cd /Users/cding/Workspace/ChenWeb && go test ./server/api/doc-processing -run 'Topic|Scene|Provision|Product'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/cding/Workspace/ChenWeb add server/api/doc-processing/topic_chunking_shared.go server/api/doc-processing/generate-scene-blocks-processor.go server/api/doc-processing/extract-provisions.go server/api/doc-processing/extract-products.go
git -C /Users/cding/Workspace/ChenWeb commit -m "refactor: migrate high-risk doc processors to structured output contracts"
```

### Task 9: Migrate remaining ChenWeb JSON call sites

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/extract-doc-metadata.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-metrics.go`
- Modify: `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
- Modify: `ChenWeb/server/api/kbhandler/extract-metric-handler.go`
- Modify: `ChenWeb/server/api/kbhandler/extract-provision-handler.go`
- Modify: `ChenWeb/server/api/doc-processing/doc-structure-analyzer.go`

- [ ] **Step 1: Write failing coverage tests**

Cover:

- doc metadata extraction uses explicit schema
- metric extraction path still supports multi-pass retries
- fixed-size chunking uses contract validation for generated topics
- handler endpoints surface clear validation failures to logs without leaking oversized raw payloads

- [ ] **Step 2: Migrate each call site**

Prefer one small caller conversion at a time, keeping diffs narrow and testable.

- [ ] **Step 3: Run package tests**

Run:

- `cd /Users/cding/Workspace/ChenWeb && go test ./server/api/doc-processing`
- `cd /Users/cding/Workspace/ChenWeb && go test ./server/api/kbhandler`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git -C /Users/cding/Workspace/ChenWeb add server/api/doc-processing/extract-doc-metadata.go server/api/doc-processing/extract-metrics.go server/api/doc-processing/fix-size-chunking.go server/api/kbhandler/extract-metric-handler.go server/api/kbhandler/extract-provision-handler.go server/api/doc-processing/doc-structure-analyzer.go
git -C /Users/cding/Workspace/ChenWeb commit -m "refactor: migrate remaining ChenWeb JSON callers to structured output"
```

## Chunk 5: Verification And Enforcement

### Task 10: Run workspace verification for shared-go plus ChenWeb

**Files:**
- No code changes required

- [ ] **Step 1: Run shared LLM package tests**

Run: `cd /Users/cding/Workspace/shared/go && go test ./api/llm`

Expected: PASS

- [ ] **Step 2: Sync workspace**

Run from workspace root: `go work sync`

Expected: success with no module resolution errors

- [ ] **Step 3: Run ChenWeb backend tests**

Run:

- `cd /Users/cding/Workspace/ChenWeb && go test ./server/api/doc-processing`
- `cd /Users/cding/Workspace/ChenWeb && go test ./server/api/kbhandler`

Expected: PASS

- [ ] **Step 4: Run broad workspace smoke tests**

Run from workspace root:

- `go test ./...`

If the full workspace suite is too slow or flaky, document the exact failing unrelated packages and rerun the targeted packages above.

- [ ] **Step 5: Commit verification notes if needed**

If a doc/test note was added during verification, commit it with a focused message. Otherwise skip this step.

### Task 11: Add enforcement guidance for future callers

**Files:**
- Modify: `shared/go/api/llm/openai_client.go`
- Modify: `ChenWeb/server/api/doc-processing/llm_contracts.go`
- Modify: `docs/superpowers/specs/2026-05-23-structured-llm-json-contract-design.md`

- [ ] **Step 1: Add deprecation comments**

Mark prompt-only `ExtractJSON` usage as legacy in comments and direct new callers to `ExtractStructuredJSON`.

- [ ] **Step 2: Add helper constructors**

If repetition is emerging, add small contract-builder helpers for common array/object patterns rather than duplicating large schema literals everywhere.

- [ ] **Step 3: Run final targeted tests**

Run:

- `cd /Users/cding/Workspace/shared/go && go test ./api/llm`
- `cd /Users/cding/Workspace/ChenWeb && go test ./server/api/doc-processing ./server/api/kbhandler`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git -C /Users/cding/Workspace/shared commit -am "chore: document structured output as the default JSON path"
git -C /Users/cding/Workspace/ChenWeb commit -am "chore: document ChenWeb structured output contract usage"
```

## Notes For The Implementer

- Keep the first shared API map-based. Typed generic decoding can come later once the contract layer is stable.
- Do not start by rewriting every prompt. Move the shape contract into code first, then simplify prompts opportunistically.
- Keep retries bounded and deterministic. Start with `MaxRetries = 2` unless a caller has a strong reason to differ.
- Preserve existing business-context error wrapping. The new engine should improve causality, not flatten it.
- After any new dependency in `shared/go`, remember the workspace rule: run `go work sync`.

Plan complete and saved to `docs/superpowers/plans/2026-05-23-structured-llm-json-contract.md`. Ready to execute?
