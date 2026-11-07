# Compact merged product extraction output

Updated: 2026-11-07. Status: implemented for merged mode (prompt v2); verified
offline. No live merged run with v2 yet.

This plan applies the compact wire-format approach in
[extract-provisions-compact-output-plan.md](extract-provisions-compact-output-plan.md)
to the **merged pass** of `extract_products`. The existing behavior is described
in [extract-products-spec.md](extract-products-spec.md) ("Merged-Pass Mode").

## Scope

Merged mode (`EXTRACT_PRODUCTS_MERGED_PASS=true`) is the mode configured locally,
with `EXTRACT_PRODUCTS_REASONING=false`. One call per chunk detects products and
assigns their relations; Deterministic Step B, Pass 3a translation, Pass 3b
name/category resolution, and storage then run unchanged.

In scope: the merged call's response format, its prompt (v2), its decoder, and the
evidence text rebuilt from the cited lines.

Out of scope:

- Pass 1 mentions and Pass 2 enrichment keep their prompts and response format.
  The decoder pieces can be reused for them later.
- Pass 3a translation: no prompt, batching, or contract change, and no translation
  run as part of this work. The merged decoder expands to the existing long-name
  rows, so translation receives the same inputs.
- Database schema, `.products` artifact field names, product IDs, category lookup,
  concurrency, reasoning settings, and pass selection.
- Row count. This is response encoding work; it must not drop rows or enrichment.

## Baseline: run 261

Run 261 (record 416, `deepseek-flash`, merged v1, reasoning off), from
`public.llm_usage_event`:

| Stage | Calls | Output tokens | Share |
|---|---:|---:|---:|
| Merged extraction | 10 | 26,904 | 70% |
| Translation | 15 | 11,447 | 30% |

With reasoning off, the merged output tokens are the JSON content. The 10 captured
responses hold 165 rows: 97,288 characters, 116,706 UTF-8 bytes. They cite 177
spans; none is missing or outside the input. 9 spans are table rows (`116#r1`), 3
are ranges (longest 7 lines). 111 of 165 summaries are English although the v1
prompt says not to translate.

Re-encoding the same rows in the v2 format below and replaying them through the
implemented decoder measured 39,333 characters (-59.6%) and 47,851 bytes
(-59.0%), with every row's meaning unchanged (see Verification).

## Decisions

| Decision | Choice | Consequence |
|---|---|---|
| Evidence text | Rebuild `evidence_quote` in Go from the cited lines; the model writes no quote (user, 2026-11-07) | Stored quotes get longer: on run 261, whole cited lines total 17,697 characters versus 4,879 for the model quotes, about half from table lines. That text reaches `kb.product_search_document`, so product search documents gain neighboring text. Citing table rows narrows it |
| Invalid row | Reject the whole response (user, 2026-11-07; same as provisions v6) | Structured retry, then the fallback model; if both fail, the chunk fails as today |
| Overlap-only rows | No new rule | Go never filtered merged rows by overlap. On run 261, 39 of 165 rows cite only overlap lines, and only 25 of them have a normal-line twin that Step B merges. Rejecting would fail most chunks; dropping would lose rows. The prompt keeps asking for normal-line evidence |
| Related products | Prompt rule only | No Go validation exists today. On run 261, 1 of 3 rows with related products used a non-inter-product relation; rejecting would fail that chunk |
| Table-row spans | Accept `N#rK`/`N#hK`, store them unchanged in `evidence_lines` | The legacy merged pass already stores them, and Step B dedup compares span strings, so stripping would change dedup |

## Wire format v2

Top level: `{"v":2,"p":[...]}`. `v` and `p` are required; `p: []` is a valid
empty extraction. No other top-level key is allowed. All generated text stays in
the source language; foreign names and identifiers already in the source are kept.

| Key | Expanded field | Requirement |
|---|---|---|
| `n` | `product_name` | Required nonempty source spelling |
| `c` | `canonical_name` | Optional; omit when identical to `n`; absent expands to `n` |
| `t` | `product_type` | Required code |
| `r` | `relation_type` | Required code |
| `d` | `product_summary` | Required nonempty summary |
| `s` | `evidence_lines` | Required nonempty spans |
| `o` | `relation_details.obligation_level` | Required code (`unk` allowed) |
| `x` | `relation_details.requirement_text` | Optional when empty |
| `cnd` | `relation_details.conditions` | Optional when empty |
| `exc` | `relation_details.exceptions` | Optional when empty |
| `p` | `relation_details.thresholds_or_parameters` | Optional when empty; entries `n` name, `v` value (string or number), optional `u` unit |
| `rp` | `relation_details.related_products` | Optional when empty; entries `n` product name, `r` relationship code |
| `a` | `relation_details.responsible_actor` | Optional when empty |
| `q` | `confidence` | Required number in [0,1], including zero |
| `cr` | `confidence_reason` | Optional when empty |

No other key is allowed: no quotes, translations, or long names. Omitted optional
strings expand to `""` and omitted arrays to `[]`. A parameter without `u`
expands to `"unit": ""`.

### Enum codes

Mappings are exhaustive and case-sensitive. Unknown codes are errors.

| Enum | Codes |
|---|---|
| Product type `t` | `sp` specific_product; `pc` product_class; `cmp` component; `mat` material; `sw` software; `sys` system; `eq` equipment; `con` consumable; `pkg` packaging; `oth` other |
| Relation type `r` | `sc` scope; `reg` regulated_object; `req` requirement_target; `perf` performance_requirement; `des` design_requirement; `mat` material_requirement; `test` testing_requirement; `cert` certification_requirement; `use` usage_condition; `inst` installation_requirement; `maint` maintenance_requirement; `stor` storage_requirement; `ban` prohibited_product; `ex` exempted_product; `part` component_of; `has` contains_product; `compat` compatible_with; `alt` replacement_or_alternative; `meas` measurement_object; `risk` risk_source; `oth` other |
| Obligation `o` | `m` mandatory; `r` recommended; `p` permitted; `b` prohibited; `c` conditional; `d` descriptive; `unk` unknown |
| Related-product relationship `rp[].r` | `part` component_of; `has` contains_product; `compat` compatible_with; `alt` replacement_or_alternative; `vs` compared_with; `oth` other |

`cr` (not `r`) holds the confidence reason, and `vs` (not `cmp`) is
`compared_with`, so no code means two different things within one row.

## Evidence spans and rebuilt evidence text

Span forms:

- a single line as an integer: `143`
- an inclusive range as a string: `"150-151"`
- one table row as a string: `"116#r3"` (data row) or `"116#h0"` (header row),
  using the row labels the input shows

Validation, against the lines the call actually sent (the chunk's non-image lines):

- every row needs at least one span
- single lines, range endpoints, and table rows must exist in that input; a range
  may pass over image lines, which are not sent
- reversed ranges, non-integral numbers, and malformed strings are errors
- a row label must exist in that table line's rendered rows

`evidence_lines` stores the spans as strings (`143` becomes `"143"`), in the
order given, row labels included.

`evidence_quote` is rebuilt from the cited text as the model saw it, in line
order, joined with newlines:

- a text line contributes its content
- a cited table row contributes that row's rendered cells without the `116#r3: `
  label
- a table line cited without a row contributes all its rendered rows without labels
- a line cited both whole and by row contributes once, whole

This is reconstructed text, longer than the old model quote; spans remain the
authoritative evidence. The prompt asks for table rows rather than whole tables.

## Failure handling

- The compact contract is a v2-only JSON schema. Schema violations trigger the
  structured client's retries. The decoder validates the same schema, so plain
  JSON clients get the same checks.
- Span errors are semantic. They fail the call, which then follows the existing
  fallback path. If the fallback also fails, the merged chunk fails as today: the
  direct path fails the run; the batch path logs and skips the chunk, and fails
  the run only when every chunk failed.
- Compact calls bypass the `isEmptyProductExtractionError` shortcut, so malformed
  output can never become an empty success.
- The captured wire response is decoded into fresh maps and never modified.

## Integration

1. `server/api/doc-processing/products_v2.go`: enum maps, schema, line lookup,
   decoder, and prompt-version check.
2. The compact contract is selected when the merged prompt is
   `prompt-extract-products-merged-v2.md` (same filename check as provisions).
   A compact call rejects a response without `v`. v1 and custom prompts keep the
   legacy contract.
3. Compact merged calls send a task suffix with no schema, only
   `Return JSON only.` and the block index, so it cannot contradict the prompt.
   The legacy suffix is unchanged.
4. `extractProductsMergedForChunk` builds the line lookup from the chunk and
   passes it to `extractProductPayloadWithFallback`. It is used on both the direct
   and the batch path. Pass 1, Pass 2, and translation pass none and are unchanged.
5. The merged default becomes v2 in `NewProductsProcessor`, in local
   `mise.local.toml`, and in regenerated `prompt_defaults_generated.go`.
6. `prompts/prompt-extract-products-merged-v2.md` carries v1's product rules plus
   the v2 format, codes, span rules, and a stronger source-language rule.
7. Update the products spec and implementation notes once implemented.

## Verification

- Replay the 10 run 261 responses (fixture
  `testdata/products-merged-run-261.json.gz`: captured responses plus the lines
  each call sent) through the real decoder, `normalizeProductList`, and Step B
  dedup. Compare against the legacy path: row count, names, types, relation
  types, obligation, requirement text, conditions, exceptions, parameters,
  related products, actor, confidence, reasons, and spans. Check the rebuilt
  evidence text separately. Report characters and bytes.
- Unit tests: all codes and optional defaults; empty extraction; zero confidence;
  rejected quote/translation/long keys; unknown codes; missing required fields;
  invalid, missing, and nonexistent spans and rows; a range across an image line;
  table-row text from a real HTML table; an unmodified captured response.
- Local HTTP server: structured retry of a legacy or invalid response; fallback
  after a span error; both models failing returns an error, not an empty result.
- Focused product/contract tests, package tests, and the doc-processor build.
- No live provider calls, re-extraction, translation jobs, or database rewrites.
  Offline size savings do not establish billing or quality changes; a fresh
  merged run on record 416 is the operator's live check.

### Results (2026-11-07)

- Run 261 replay (`TestProductsMergedV2Run261Replay`): all 165 rows decode;
  names, canonical names, types, relation types, summaries, spans, obligation,
  requirement text, conditions, exceptions, parameters, related products,
  actor, confidence, and reasons match the legacy path row for row; Step B
  yields the same row count; every rebuilt `evidence_quote` is nonempty and free
  of row labels. 97,288 → 39,333 characters, 116,706 → 47,851 bytes.
- The prompt's own example decodes under the real decoder
  (`TestProductsMergedV2PromptExampleDecodes`).
- `go test ./server/api/doc-processing`: all product tests pass. Two failures
  are unrelated and predate this change: `TestKBMetricsReadersExcludeResolvedRows`
  (`kbhandler/question_generator_worker.go:133`, noted in the provisions plan)
  and `TestProvisionsDefaultPromptUsesCompactFormat`, which expects provisions
  v7 while the committed embedded default is v8.
- `go vet` and `go build ./server/cmd/doc-processor` pass.
- Local `mise.local.toml` selects merged v2, and `prompt_defaults_generated.go`
  was regenerated (only the merged entry changed). Rebuild and restart the
  doc-processor to use it.
