# Structured LLM JSON Contract Design

Date: 2026-05-23

## Problem

Many workspace LLM call sites require "strict JSON" but historically relied on:

- prompt instructions
- `response_format = {"type":"json_object"}`
- one-shot parsing

This is not a real contract.

It fails when the model:

- emits malformed JSON
- leaves quotes unescaped inside string fields
- returns the wrong field types
- omits required fields
- adds incompatible structure

The failure mode is especially bad for document-processing pipelines because malformed payloads appear deep inside long-running processors and are hard to recover from consistently.

## Goal

Create a shared, strict-by-default JSON contract layer in `shared/go/api/llm` so LLM JSON responses are:

- described by machine-readable schema
- parsed centrally
- schema-validated centrally
- retried when malformed or schema-invalid
- optionally repaired for narrow serialization-only damage
- failed closed when they still do not satisfy the contract

This contract must be reusable across workspace projects, with `ChenWeb` as the first adopter.

## Non-Goals

This design does not attempt to:

- guarantee semantic correctness of model reasoning
- force all providers to support native schema enforcement
- remove prompts as semantic instructions
- replace all legacy callers in one step

## Design Summary

Add a new structured-output path to the shared client:

- `ExtractStructuredJSON(ctx, input, contract)`

The caller provides:

- normal LLM request input
- a `StructuredOutputContract`

The shared client then:

1. builds the provider request
2. requests structured output when the provider supports it
3. extracts the raw textual payload
4. parses JSON
5. validates the parsed payload against the declared schema
6. optionally repairs narrow JSON formatting damage
7. retries with corrective feedback when parsing or validation fails
8. returns validated structured data or a typed failure

Legacy `ExtractJSON` remains available, but only as a compatibility bridge on top of the new engine.

## Core Types

The shared client exposes a contract/result shape conceptually like:

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

Supporting typed errors distinguish:

- invalid contract
- provider request failure
- JSON parse failure
- schema validation failure
- retries exhausted

## Validation Model

Contracts are expressed as JSON Schema.

Why JSON Schema:

- machine-readable
- reviewable in code
- portable across providers
- testable independently from model calls
- suitable for nested arrays and object validation

Validation is performed after parsing and before any business logic consumes the payload.

## Repair Model

Repair is intentionally conservative.

Allowed repair scope:

- strip Markdown JSON fences
- isolate JSON from leading or trailing prose
- recover simple malformed wrappers
- repair narrow serialization issues when structure can be recovered unambiguously

Repair must not:

- invent missing semantic fields
- infer omitted arrays or objects
- transform one semantic schema into another

If repair requires guessing, the call must fail or retry rather than silently mutate the meaning.

## Retry Model

Retries are only for malformed or schema-invalid model output.

They are not for downstream business-logic disagreement.

Retry feedback should be explicit, for example:

- previous output was not valid JSON
- previous output violated contract `<name>`
- re-output the same content as valid JSON only
- escape all inner quotes in string values

Retries are bounded and small.

## Compatibility Model

`ExtractJSON` remains public for existing callers, but its implementation routes through `ExtractStructuredJSON` with a permissive legacy object contract.

That gives the workspace:

- better parsing behavior immediately
- one centralized retry/repair path
- incremental migration of callers to explicit schemas

New call sites should use `ExtractStructuredJSON` directly.

## Adoption Pattern

Adopters define local schema contracts in code and prefer the structured path when their extractor supports it.

Pattern:

1. define a contract helper near the processor or handler layer
2. detect structured-extractor capability
3. call `ExtractStructuredJSON(...)`
4. fall back to legacy `ExtractJSON(...)` only for compatibility seams

This lets migrations happen call-site by call-site without a flag day.

## ChenWeb First-Adopter Scope

The first-adopter rollout covers the main JSON-heavy ChenWeb paths:

- topic extraction
- scene block extraction
- doc metadata extraction
- metrics extraction
- product extraction
- provision extraction
- summary generation
- doc-structure analyzer JSON fallback
- KB metric handler
- KB provision handler

Contracts are centralized in local helper files so new call sites can follow the same pattern.

## Observability

Structured-output failures should log:

- contract name
- model name
- base URL or provider
- failure class
- retry count
- whether repair was attempted

Large raw payloads should not be logged wholesale when they may contain document text.
Prefer concise excerpts and typed errors.

## Environment Compatibility

No new required environment variables are introduced by this design.

Compatibility behavior preserved or restored:

- `TOPIC_CHUNK_PROMPT` is accepted as a topic prompt override alias
- `EXTRACT_TOPIC_PROMPT` and `SEMANTIC_CHUNKING_PROMPT` still work
- `SUMMARY_TREE_DIR` is accepted as a fallback when `ARTIFACT_WEB_DIR` is not set for summary graph reads

## Failure Semantics

The design is intentionally fail-closed.

If the output cannot be repaired, parsed, and validated against the declared contract after bounded retries:

- the shared client returns a typed error
- the caller decides whether to persist failure status, retry the processor later, or continue with an explicit fallback path

## Testing Strategy

The contract layer requires tests for:

- contract validation
- schema compilation and schema validation
- parse failure classification
- retry after malformed JSON
- retry after schema mismatch
- repair success
- retries exhausted

Call-site migrations require tests for:

- use of `ExtractStructuredJSON` when supported
- zero legacy `ExtractJSON` calls on migrated paths
- expected contract names

## Result

The structured LLM JSON contract turns "please return strict JSON" from a prompt wish into an enforceable shared boundary.

It does not make LLMs infallible.
It makes their failures explicit, classified, bounded, and recoverable in one place.
