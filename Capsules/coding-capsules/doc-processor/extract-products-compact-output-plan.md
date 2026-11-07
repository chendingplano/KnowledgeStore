# Compact product extraction output

Updated: 2026-11-07. Status: proposed; independent design review passed,
implementation pending user review.

This plan applies the compact wire-format approach in
[extract-provisions-compact-output-plan.md](extract-provisions-compact-output-plan.md)
to the extraction stages of `extract_products`. The existing behavior is described
in [extract-products-spec.md](extract-products-spec.md).

## Scope and recommendation

Use a versioned response with short named fields, short enum codes, numeric
single-line spans, and omission of empty optional fields. Replace model-generated
evidence quotations with explicit evidence spans and reconstruct evidence text
from the supplied source lines in Go where existing consumers need it.

Apply this to Pass 1 mention extraction, Pass 2 relation enrichment, and the
optional merged extraction mode. Preserve producthood rules, the narrow Pass 2
veto, recall, relation granularity, meaningful summaries, confidence reasons,
conditions, exceptions, parameters, and related-product metadata.

**Do not generate translations in extraction, change the translation prompt or
batching contract, or run translation as part of this work.** Pass 3a remains the
separate translation step. Compact responses expand to existing long-name maps
before downstream processing, so the translation step still receives its existing
inputs when an operator subsequently runs the full pipeline. The extraction
prompts already omit translations; there is no new translation-removal saving
to claim here.

The database schema, `.products` artifact field names, product IDs, category
lookup, concurrency settings, reasoning settings, and pass selection stay as
specified today. This is response encoding work, not a reduction in row count.

## Alternatives

| Approach | Decision |
|---|---|
| Short named fields, enum codes, optional omission, span references | Recommended: retains semantics and readable validation failures |
| Positional arrays | Defer: field-order mistakes are harder to detect and review |
| Remove summaries/reasons, cap relations, or disable reasoning | Exclude: changes enrichment or recall rather than just encoding |

Product responses have only one explicitness boolean, unlike provisions' two
flags. Keep it as a required boolean; do not introduce a bitmask for one bit.
Do not add a product dictionary or candidate identity inheritance in the first
implementation. Both introduce additional reconstruction rules and require
measured evidence that they are worth the complexity.

## Wire format v2

Pass 1 returns `{"v":2,"m":[...]}`. Pass 2 and merged extraction return
`{"v":2,"p":[...]}`. Empty arrays are valid successful extractions. The `v`
marker and the correct stage-specific array are required, including when empty.
There is no response-level language field: all generated text stays in the
source language, preserving foreign names or identifiers already in the source.

### Mention fields

| Key | Expanded field | Requirement |
|---|---|---|
| `n` | `mention_text` | Required nonempty source spelling |
| `c` | `canonical_hint` | Optional; omit when empty or identical to `n`; expand to `n` when absent |
| `t` | `product_type_hint` | Required enum; `unk` allowed |
| `s` | `evidence_lines` | Required nonempty explicit spans |
| `e` | `is_explicit` | Required boolean, including `false` |
| `q` | `confidence` | Required number in [0,1], including zero |
| `r` | `confidence_reason` | Optional when empty; retain meaningful reasons |

Example: `{"v":2,"m":[{"n":"垃圾桶","t":"eq","s":[143],"e":true,"q":0.98}]}`.

### Product-relation fields

| Key | Expanded field | Requirement |
|---|---|---|
| `n` | `product_name` | Required nonempty source spelling |
| `c` | `canonical_name` | Optional only when identical to `n`; expand to `n` when absent |
| `t` | `product_type` | Required enum; no `unknown` value |
| `r` | `relation_type` | Required enum |
| `d` | `product_summary` | Required nonempty concise source-language summary |
| `s` | `evidence_lines` | Required nonempty explicit spans |
| `o` | `relation_details.obligation_level` | Required enum; `unk` allowed |
| `x` | `relation_details.requirement_text` | Optional when empty |
| `cnd` | `relation_details.conditions` | Optional when empty |
| `exc` | `relation_details.exceptions` | Optional when empty |
| `p` | `relation_details.thresholds_or_parameters` | Optional when empty; entries use `n`/`v`/optional `u` for name/value/unit |
| `rp` | `relation_details.related_products` | Optional when empty; entries use required `n`/`r` for product_name/relationship |
| `a` | `relation_details.responsible_actor` | Optional when empty |
| `q` | `confidence` | Required number in [0,1] |
| `cr` | `confidence_reason` | Optional when empty; retain meaningful reasons |

Flattening relation details saves a repeated wrapper. Expand them back into the
existing `relation_details` object before `normalizeProductList` runs. Omitted
optional strings become empty strings; omitted arrays become empty arrays.
Do not omit zero confidence, false explicitness, required enums, or evidence.

Example:

```json
{"v":2,"p":[{"n":"垃圾桶","t":"eq","r":"use","d":"垃圾桶应保持清洁。","s":[143],"o":"m","x":"垃圾桶应保持清洁。","q":0.98}]}
```

### Enum codes

Mappings are exhaustive and case-sensitive. Unknown codes are errors, never
silently mapped to `other` or `unknown`.

| Enum | Codes → existing values |
|---|---|
| Product type | `sp` → specific_product; `pc` → product_class; `cmp` → component; `mat` → material; `sw` → software; `sys` → system; `eq` → equipment; `con` → consumable; `pkg` → packaging; `oth` → other; `unk` → unknown (mentions only) |
| Relation type | `sc` → scope; `reg` → regulated_object; `req` → requirement_target; `perf` → performance_requirement; `des` → design_requirement; `mat` → material_requirement; `test` → testing_requirement; `cert` → certification_requirement; `use` → usage_condition; `inst` → installation_requirement; `maint` → maintenance_requirement; `stor` → storage_requirement; `ban` → prohibited_product; `ex` → exempted_product; `part` → component_of; `has` → contains_product; `compat` → compatible_with; `alt` → replacement_or_alternative; `meas` → measurement_object; `risk` → risk_source; `oth` → other |
| Obligation | `m` → mandatory; `r` → recommended; `p` → permitted; `b` → prohibited; `c` → conditional; `d` → descriptive; `unk` → unknown |
| Related-product relationship | `part` → component_of; `has` → contains_product; `compat` → compatible_with; `alt` → replacement_or_alternative; `cmp` → compared_with; `oth` → other |

The existing rule that related products belong only to the four inter-product
relation types remains in the prompt and validation.

## Evidence and failure handling

Emit single lines as integers (`[143]`) and inclusive ranges as strings
(`['150-151']`, with JSON double quotes on the wire). Every mention and every
relation has its own explicit spans; no inheritance from candidates or siblings.
Reject missing/empty spans, nonintegral numbers, malformed or reversed ranges,
and references outside the actual source lines supplied for that call. Require
normal-line support according to the existing overlap rule. Validate by walking
available source lines rather than allocating unbounded ranges from model input.

Resolve spans against the actual chunk document or multi-block fallback input.
For downstream `evidence_quote`, join the referenced source contents in source
order with newlines, without line-number prefixes. This is reconstructed evidence
text, potentially longer than the old selected quotation; do not claim byte-for-byte
equivalence of evidence quotes. Keep the span references authoritative. Full-line
text can include adjacent clauses, so it must not create extra product relations
or substitute for a missing requirement summary.

Pass 1's current `mentionHasNormalEvidence` treats empty spans plus an empty
quote as normal evidence whenever any normal line exists. Compact decoding must
reject missing evidence before reaching that permissive legacy behavior.
Do not reconstruct text from the mention name or unrelated candidate lines.

Use stage-specific structured contracts so a mentions response cannot satisfy
Pass 2 or merged extraction. Schema validation failures use structured retries;
semantic span failures reach the existing model fallback path. Exhausted failures
must retain existing unit/run failure reporting rather than turning into a valid
empty extraction. Keep the captured wire response unchanged for diagnostics.
Compact validation errors must not match `isEmptyProductExtractionError`, whose
legacy shortcut can otherwise convert malformed output into a successful empty.

## Integration and compatibility

1. Add a focused compact schema/decoder module beside `extract-products.go`.
   Decode fresh maps before existing mention/relation normalization and dedup.
2. Select compact contracts by the explicitly selected compact prompt version:
   mentions v3, enrichment v5, and merged v2. Old/custom prompts keep legacy
   support. A compact-selected call must not silently accept verbose responses.
3. Remove the duplicate verbose output examples in
   `buildProductMentionsTaskPrompt` and `buildMergedProductsTaskPrompt` for compact
   calls; their suffix must identify stage/block without contradicting the prompt.
   Preserve compatibility for explicitly selected legacy prompts.
4. Pass the actual source-line lookup to extraction decoding at each call site,
   covering direct and orchestrator batch execution and multi-block enrichment.
5. **Separate translation dispatch before selecting compact contracts.**
   `extractProductPayload` currently handles translation too. Translation retains
   its existing `products`/`idx`/`_en` schema, parsing, and matching. Do not feed
   translation results into the extraction decoder or invoke translation in
   offline replay tests.
6. Update constructor defaults and embedded prompt defaults using the existing
   generator. Check tracked/local prompt selectors for explicit old versions;
   document any selector that deliberately remains legacy.
7. Update the products spec and implementation notes to describe the implemented
   wire contract once it exists. Keep this plan marked proposed until verified.

## Verification and measurement

- Capture representative existing Pass 1, Pass 2, and merged responses. Report
  characters and UTF-8 bytes separately, per stage and combined. Reserialize the
  same semantic content into v2; do not manufacture savings by dropping rows,
  nonempty enrichment, or counting already-removed translations.
- Replay through the real decoder, normalizer, merge/dedup, and output builders.
  Compare product identity, types, relation counts, Unicode grouping, conditions,
  exceptions, parameters, actors, confidence, and spans. Separately assert the
  documented reconstructed evidence text and canonical-name defaults.
- Test all enum mappings and optional defaults; empty successful extractions;
  zero confidence and false explicitness; unknown/translation/quote attributes;
  wrong stage/version; missing fields; mixed invalid spans; nonexistent lines;
  overlap-only evidence; and unchanged captured response maps.
- Exercise structured retries and fallback with a local HTTP server. Cover
  direct, batch, merged, and Pass-1-only paths. Test translation dispatch isolation
  using mocks only, without generating translations or changing its behavior.
- Run focused product/contract tests, the package checks, and the processor
  build. Record unrelated pre-existing failures separately.
- No live provider calls, document re-extraction, translation jobs, or database
  rewrites are needed to implement or verify the encoding change.

No product compression percentage is claimed before captured-output measurement.
Offline byte savings do not establish provider-token, reasoning-token, billing,
or live extraction-quality improvements. Preserve reasoning settings and use a
separate operator-run A/B evaluation if live quality measurement is later wanted.
