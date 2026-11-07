# Compact provision output: analysis, decisions, and implementation

Updated: 2026-11-07. Status: implemented in prompt v6 / wire format v2.

This document records the size analysis, the options considered, what was
implemented, and the source-span regression that shaped the final design.
The current behavioral contract is [extract-provisions-spec.md](extract-provisions-spec.md),
with implementation details in [extract-provisions-impl.md](extract-provisions-impl.md).

## Current result

The final implementation uses source-language text, short attribute names, short
enum codes, explicit evidence spans, omission of empty optional fields, integer
single-line spans, and packed boolean flags. Descriptions, context, keywords,
aliases, acronyms, and provision granularity remain when meaningful/nonempty.
Generated translations and object evidence quotations are intentionally removed.

Replay of record **416**, run **258**, retains all **64 provisions and 152 object
mentions**, with the expected source-language storage, artifact, object, search,
flag, enum, and evidence-span values:

| Measure | Original captured output | Implemented v2 encoding | Reduction |
|---|---:|---:|---:|
| Characters | 119,854 | 29,539 | **75.35%** |
| UTF-8 bytes | 151,818 | 53,742 | **64.60%** |

These are offline reserialization/replay measurements, not provider-token or
billing reductions. The user subsequently reran extraction and confirmed that
output was much smaller; no quantified live reduction is claimed here.

## Analysis and baseline

Run 258 used `deepseek-flash` with `prompt-extract-provisions-v3.md`:

| Measurement | Value |
|---|---:|
| Extraction calls | 10 |
| Input tokens | 20,369 |
| Output tokens | 34,148 |
| Additional object-resolution output tokens | 952 |
| Extracted provisions | 64 |
| Object mentions | 152 |

The captured JSON was already minified and contained no captured reasoning text.
Whitespace removal or disabling reasoning would therefore not reduce this run's
response content.

The main sources of size were:

- Object records occupied **40.2%** of complete serialized output, including keys.
- The output repeated source content as English translations, descriptions,
  context, keywords, and object metadata.
- All 152 objects repeated their source-language name as `object_name_zh`;
  133 repeated the parent provision's spans and 78 its confidence.
- Long attribute names were repeated for every provision and object.
- Object evidence quotes copied content already addressable by source spans.

The original benchmark report scored run 258 at 54/100 and identified merged
requirements. Reducing provision count or combining requirements was therefore
excluded as a size-reduction method.

### The user's three requested improvements

The following cumulative analysis used the same captured run 258 content:

| Cumulative transformation | Characters | Reduction from original |
|---|---:|---:|
| Original | 119,854 | — |
| Remove translations and redundant language-specific object names | 62,069 | 48.2% |
| Also shorten attribute names | 40,740 | 66.0% |
| Also replace object evidence quotes with existing spans | 36,267 | 69.7% |

Those three changes reduced UTF-8 size to 60,470 bytes, **60.2%** below the
original. They retained explicit spans on every provision and object. The
object's existing span field serves as the evidence location; no second evidence
span attribute is added.

A cross-check on run 259's eight responses with valid provision spans (58
provisions, 140 objects) showed **63.1% fewer characters and 53.9% fewer bytes**
for the same three changes. For a comparable explicit-span baseline, omitted
object spans were first expanded using that run's existing v4 inheritance rules.
The two responses without provision evidence were excluded from this comparison.

### Additional options evaluated

Each percentage below is an **isolated further character reduction from the
36,267-character result above**, not a cumulative or additive percentage.
The analysis used trial code mappings; final implementation measurements are
reported separately at the top of this document.

| Option | Further reduction | Decision and reason |
|---|---:|---|
| Short enum codes | 9.5% | **Implemented**; deterministic expansion restores values |
| Omit empty optional fields | 4.6% | **Implemented** with a precise allowlist; required fields remain explicit |
| Integer single-line spans | 1.4% | **Implemented**; inclusive ranges remain strings |
| Pack the two boolean flags into an integer | 2.3% | **Implemented**; all four combinations are tested |
| Remove provision/object descriptions | 18.6% | Not implemented; retains separately written enrichment |
| Remove keywords | 6.9% | Not implemented; protects existing search inputs |
| Remove context | 3.7% | Not implemented; surrounding context may carry useful meaning |
| Positional arrays instead of named fields | 23.1% | Not implemented; increases field-position and decoding risks |
| Replace provision text with source references | About 10.9% | Not implemented; whole lines may contain multiple clauses, and precise reconstruction may need offsets |
| Exact object dictionary per response | **2.7% larger** | Rejected; only eight of 152 mentions shared identical descriptive metadata within their chunks |

The user approved the original three improvements plus the **first four** options
in this table. No nonempty descriptions, keywords, context, or aliases were
removed as an extra optimization.

## Implemented choices

| Approved improvement | Final behavior |
|---|---|
| No translations | Emit one source-language value. No generated English/Chinese counterparts; preserve foreign names and identifiers already present in the source |
| Short attribute names | Top level `v`, `l`, `p`; provision fields include `n`, `t`, `x`, `s`, `lt`, `q`, `f`, `d`, `c`, `u`, `k`, `o`, `g`; object fields include `n`, `t`, `r`, `s`, `q`, `d`, `a`, `y` |
| Evidence spans instead of object quotes | Every object's `s` identifies its evidence lines. Quotes and duplicate evidence attributes are rejected |
| Short enum codes | For example `m` → mandatory, `mat` → material, `reg` → regulated_object; decode before storage/search |
| Omit empty optional values | Only named optional strings/lists may be omitted. Required values, including zero confidence/flags, are retained. Category arrays preserve missing versus explicit `[]` |
| Numeric single-line spans | Emit `[143]`; emit ranges as `["150-151"]`. Both levels require explicit nonempty spans |
| Packed boolean flags | `f` bit 0 (value 1) = `is_explicit`; bit 1 (value 2) = `need_verify` |

Flag decoding is explicit: `0` = neither, `1` = explicit only, `2` = verification
only, `3` = both. Missing flags or values outside 0–3 are rejected rather than
silently defaulted.

### Compatibility and evidence safeguards

- V6 requires the short v2 shape: `{"v":2,"l":"zh","p":[...]}`. Structured
  extraction uses a v2-only contract, so verbose/translated output is not silently
  accepted. Ordinary JSON clients validate against the same schema.
- Explicitly selected old/custom prompts retain legacy/v1 support. Unknown v2
  keys, translation/quote attributes, unknown enum codes, invalid confidence,
  missing flags, and malformed evidence are errors.
- Every emitted provision **and object** requires explicit nonempty spans. V2
  never inherits evidence. Every supplied span must be usable; mixed invalid
  values and reversed ranges fail. Validation does not check membership in the
  actual input unit's line-number set.
- Schema violations trigger structured-client retries. Semantic reversed-range
  errors are caught during decoding and follow the existing fallback path. If
  both models produce invalid evidence, the unit fails instead of saving or
  silently dropping the affected provisions.
- The decoder preserves captured wire responses and expands values before the
  existing normalization/storage/search paths. Database and artifact-file keys
  retain their long names; no migration is required.
- Native English text is copied server-side into existing English storage fields
  to avoid losing it under the existing English deduplication rule. Native Chinese
  object names populate their Chinese field similarly. Neither operation creates
  a translation or duplicates LLM output.
- Shared object reconciliation remains a separate step; its canonical metadata
  enrichment contract was not changed by this extraction-response optimization.
- Decoder code `li` preserves captured legacy `list-item` values; the v6 prompt
  requests `b` for bullet/list-item locations.

## Earlier designs and the source-span regression

The initial approved scope preserved translations and evidence quotes. V4 used
`output_format: "compact-v1"`, omitted empty values and repeated object metadata,
and expanded them server-side. Duplicate schemas embedded in Go instructions
were removed so the versioned prompt owned the response fields.

Offline replay initially suggested about 12% compression. Preserving absent
versus empty category arrays and adding the format marker yielded the measured
**10.14%** reduction: 119,854 → 107,699 characters, with identical expanded run
258 outputs. That scope was superseded by the later source-only approval.

The first live v4 extraction, **run 259**, exposed a serious gap: two provider
responses omitted provision-level source spans on **16 of 74 provisions**.
`llm-1f52fd3c` omitted them on seven provisions and `llm-7274abaf` on nine,
despite receiving line-numbered input. The response handler accepted them and
storage received null spans, causing downstream indexing warnings.

The original replay only simulated allowed omissions from valid responses; it
did not establish that the model would follow the omission rules. V5 tightened
the prompt, stopped requesting span inheritance, and added required nonempty
provision evidence to both structured validation and the common response handler.
V6 carries those safeguards forward and adds strict explicit object evidence in
its schema and decoder. Compression must never relax evidence requirements.

## Implementation and verification

- [x] Reproduce the initial expansion/schema issues with failing tests.
- [x] Preserve the run 259 failures in a captured-response regression fixture.
- [x] Implement v2 schema/decoder, all seven approved changes, prompt v6, and
  regenerated embedded defaults; select v6 in local configuration.
- [x] Verify all packed-flag combinations, source-only English storage, empty
  extractions, strict enums/attributes, response immutability, and invalid spans
  at both levels.
- [x] Verify real local-HTTP structured retries of incompatible legacy output,
  missing object evidence, and invalid flags.
- [x] Replay run 258 through the real decoder/normalizer and compare expected
  source-only storage, file artifacts, objects, and search text.
- [x] Run focused provision tests, broader package checks, build, and independent
  review; document the unrelated existing guard failure.
- [x] Update capsule specification/implementation documentation and commit task
  files through jj, leaving unrelated edits uncommitted.

Relevant code is under `ChenWeb/server/api/doc-processing/`:
`provisions_v2.go`, `provisions_v2_test.go`, `provisions_compact.go`,
`provisions_compact_test.go`, `provisions_source_spans_test.go`,
`extract-provisions.go`, `llm_contracts.go`, and `provisions_request_test.go`.
The active prompt is `ChenWeb/prompts/prompt-extract-provisions-v6.md`.
Fixtures are `testdata/provisions-run-258.json.gz` and
`testdata/provisions-run-259.json.gz` beneath the doc-processing package.

Verification commands from `ChenWeb/`:

```sh
go test ./server/api/doc-processing -run 'TestProvisions|TestExtractProvision|TestNormalizeProvision|TestBuildProvision|TestLoadProvisions|TestDocProcessingContracts' -count=1 -v
go test ./server/api/doc-processing -skip '^TestKBMetricsReadersExcludeResolvedRows$' -count=1
go build -buildvcs=false -o ./.cache/doc-processor.exe ./server/cmd/doc-processor
```

Focused tests and the package run excluding that guard passed. The excluded
`TestKBMetricsReadersExcludeResolvedRows` fails on the unrelated unchanged
`server/api/kbhandler/question_generator_worker.go:133`, which lacks the required
`ref_mention_id` predicate. The processor build and independent code review passed.
Implementation verification used captured responses and a local HTTP test server,
without agent-initiated provider calls or database rewrites.

Commits recording the stages:

| Repository | Commit | Change |
|---|---|---|
| ChenWeb | `46dd64df` | Initial v4 metadata compression |
| ChenWeb | `69a9` | Reject extractions without usable source evidence; v5 |
| ChenWeb | `5ca0` | Source-only short v2 response; prompt v6 |
| KnowledgeStore | `84ef45d` | Initial compact contract and replay |
| KnowledgeStore | `386d` | Source-span regression and validation |
| KnowledgeStore | `9f9d` | Source-only format and size measurements |

Rebuild/restart a running processor to activate code/prompt changes. This work
changed extraction behavior, not existing document rows; previous invalid output
requires a successful fresh extraction to replace it and rebuild indexes.
