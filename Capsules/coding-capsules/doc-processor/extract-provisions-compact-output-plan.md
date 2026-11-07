# Compact provision output implementation plan

Approved scope: information-preserving compression only (2026-11-07).
Descriptions, translations, evidence quotes, aliases, and provision granularity remain.

The LLM returns `output_format: "compact-v1"` with the existing language and
provisions fields. Only this marked format is expanded; legacy responses retain
their existing interpretation. Missing object spans and confidence inherit their
parent provision's values. For Chinese input, missing `object_name_zh` inherits
`object_name`; an explicit empty value suppresses inheritance. Other missing
optional strings and arrays expand to empty values, except category arrays:
retain explicit `[]` and leave missing categories missing to preserve legacy
storage values. Explicit values always win during expansion; the existing
downstream object normalizer still treats zero confidence as inherited.
Do not omit booleans, numbers, or nonempty information outside these rules.

The versioned prompt owns the response schema. Remove the duplicate schemas from
the chunk and block Go builders. Use v4 by default, regenerate the embedded prompt
default, and update the local service configuration to select v4. Storage and
search receive the expanded records; the provider usage archive retains the wire
response. No migrations, shared-library changes, branches, or live extraction are
needed.

- [x] Write failing tests for marked compact/legacy payload compatibility,
  inherited fields, explicit overrides, and prompt selection in chunk/block paths.
- [x] Implement expansion in the common response handling path and publish v4.
- [x] Verify focused Go tests, the doc-processing package, and processor build.
- [x] Replay run 258's ten captured responses through compact encoding and the
  real Go normalization, comparing normalized rows, search text, object records,
  and file records. Measure characters, not claimed provider token savings.
- [x] Update the existing capsule specification and implementation documentation;
  record the validation and deferred description-removal experiment.
- [x] Review the diff, commit only task files with jj in each repository, and
  confirm linear history with unrelated local edits left uncommitted.

Relevant implementation: `ChenWeb/server/api/doc-processing/extract-provisions.go`,
new compact expansion helper/tests beside it, `provisions_request_test.go`,
`ChenWeb/prompts/prompt-extract-provisions-v4.md`, and generated prompt defaults.

Validation: tests initially failed on missing expansion and duplicate schema
instructions, then passed after implementation. Replay: 119,854 → 107,699
characters (10.14% smaller), all 64 provision outputs identical after expansion.
Structured/fallback extraction, explicit overrides, language handling, legacy
markers, captured-map immutability, and embedded v4 selection are covered.
Independent implementation review found no blocking issues.

Commands from `ChenWeb/`:

```sh
go test ./server/api/doc-processing -run 'TestProvisions|TestNormalizeProvision|TestBuildProvision|TestLoadProvisions|TestDocProcessingContracts' -count=1 -v
go test ./server/api/doc-processing -count=1
go test ./server/api/doc-processing -skip '^TestKBMetricsReadersExcludeResolvedRows$' -count=1
go test ./server/cmd/doc-processor -count=1
go build -o /tmp/doc-processor-compact ./server/cmd/doc-processor
```

The full package run failed only on the pre-existing metrics-reader guard in
unchanged `server/api/kbhandler/question_generator_worker.go:133`. The run excluding
that guard passed, as did focused tests and the build. The command package has no
test files. No new LLM calls or database writes were made.
