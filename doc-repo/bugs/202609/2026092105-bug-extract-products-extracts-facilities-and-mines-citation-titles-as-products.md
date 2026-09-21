# extract_products extracts facilities/works as products, and mines product names out of normative-reference titles

Date: 2026-09-21

Status: root-caused and fixed in the working tree (prompt-layer fix, A/B-verified against the
real document); `go build ./...` and `go test ./server/api/doc-processing/` clean; not
committed. User will re-run the processors on record 416; existing `kb.products` and
`kb.product_names` rows intentionally left untouched.

Scope: `ChenWeb/prompts/prompt-extract-product-mentions-v2.md` (new),
`ChenWeb/prompts/prompt-enrich-product-mention-v4.md` (new),
`ChenWeb/server/api/doc-processing/extract-products.go` (default prompt refs),
`ChenWeb/mise.local.toml` (prompt pins), and this capsule's spec,
`KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-products-spec.md`
(Pass 1, Pass 2, and a new "Configuration Override Caution" section).

Reported by: user, via five `kb.products` rows on record 416 that "do not look like products":
`416_prd_24` (有害垃圾独立贮存点), `416_prd_23` (垃圾分类投放点), `416_prd_84`
(农村沼气集中供气工程), `416_prd_87` (垃圾转运站), `416_prd_116` (环境卫生设施, flagged by the
user as uncertain).

---

## 1. Summary

Two distinct defects produce the reported rows. Both are precision failures in Pass 1, which is
the pipeline's only producthood gate.

1. **Places, facilities and construction works are extracted as products.** Pass 1's definition
   of a product affirmatively admits them and excludes nothing place-shaped. Reported rows
   `416_prd_23`, `416_prd_24`, `416_prd_87`.
2. **Product names are mined out of normative-reference (citation) titles.** A noun phrase
   occurring only inside a cited standard's title is treated as a product the document discusses.
   Reported rows `416_prd_84`, `416_prd_116`.

Pass 2 could not correct either, because its prompt explicitly forbade it from re-deciding
producthood — so every Pass 1 false positive was guaranteed into `kb.products`, and amplified
into one row per relation type plus a `status='proposed'` row in `kb.product_names`.

## 2. Root cause

### 2a. No facility/works exclusion in the producthood gate

`prompt-extract-product-mentions-v1.md` defines a product as anything that "can be designed,
manufactured, sold, purchased, installed, used, tested, maintained, regulated, certified,
inspected, recalled, or disposed of", lists "systems" and "equipment" among the includes, and
excludes only: organizations, people, locations, abstract concepts, activities by themselves,
legal acts, document sections.

A 垃圾转运站 satisfies the positive test cleanly (it is designed, installed, used, maintained,
regulated and inspected) and matches no exclusion — "locations" reads as a place name, not as a
built facility. The model therefore has an affirmative reason to extract it and no rule to stop
it.

`product_type_hint` has no `facility` value, so facility-shaped mentions are forced into the
nearest bucket, `system`. All five reported rows carry `product_type = 'system'`, and that
bucket is a near-perfect proxy for this failure mode:

| `product_type` | rows (record 416) |
|---|---|
| product_class | 374 |
| specific_product | 276 |
| material | 175 |
| **system** | **128** |
| equipment | 118 |
| packaging | 67 |
| other | 36 |
| consumable | 24 |
| component | 21 |

The 41 distinct `system` names are almost entirely facilities, sites and works — 垃圾转运站,
垃圾处理站, 生活垃圾焚烧厂, 生活垃圾卫生填埋场, 宣传教育基地, 垃圾分类投放点,
村分类垃圾投放点, 有害垃圾独立贮存点, 沼气工程, 农村沼气集中供气工程, 堆肥设施（阳光房）,
臭气处理设施, 污水收集和处理设施, 环境卫生设施 — plus 物联网, an abstract technology already
excluded in principle by the existing "abstract concepts" rule.

### 2b. Citation titles treated as product evidence

Record 416's lines 17–30 are the standard's 规范性引用文件 list. Pass 1 mined product names out
of those titles. 28 of the record's 1219 rows are grounded in evidence matching a
standard-number prefix:

| `product_rel_id` | `product_name` | sole `evidence_quote` |
|---|---|---|
| `416_prd_84` | 农村沼气集中供气工程 | `NY/T 2371 农村沼气集中供气工程技术规范` |
| `416_prd_116` | 环境卫生设施 | `CJJ 27 环境卫生设施设置标准` |
| `416_prd_120` | 农村户用沼气 | `NY/T 90 农村户用沼气发酵工艺规程` |
| `416_prd_82` | 生物有机肥 | `NY 884 生物有机肥` |
| `416_prd_83` | 微生物肥料 | `NY 1109 微生物肥料生物安全通用技术准则` |

Verified against the source artifact: 生物有机肥 and 微生物肥料 occur **only** on lines 28 and
29 — the citation lines — and nowhere in body text. They were never products this document
discusses.

Worse, Pass 2 then invents a requirement to justify the row. `416_prd_116` carries
`requirement_text = "环境卫生设施应符合 CJJ 27 环境卫生设施设置标准。"` — a normative statement
the document does not make. Its only source line is the bare citation.

### 2c. Pass 2 was forbidden from correcting either

`prompt-enrich-product-mention-v3.md` (Definition of Product):

> Use this only to refine `product_type` from the candidate's `product_type_hint` — the
> candidate has already established that this is a product; you are not re-deciding whether it
> qualifies.

This makes a Pass 1 false positive structurally unrecoverable. It is also the amplification
point: Pass 2 emits one row per supported relation type, so ~41 bad candidates became 128 rows.

### 2d. Contributing: stale prompt pins override the Go defaults

`ChenWeb/mise.local.toml` pins `EXTRACT_PRODUCT_MENTIONS_PROMPT` and
`ENRICH_PRODUCT_MENTION_PROMPT` by filename, and env wins over the defaults in
`NewProductsProcessor`. The 2026-09-20 run recorded
`prompt_name = prompt-enrich-product-mention-v2.md` while the code default was already v3 —
i.e. the v3 behavior documented in the spec was never actually running. Any prompt version bump
must touch both places or it is a no-op locally.

## 3. Blast radius

Not specific to record 416. Every document whose subject matter includes infrastructure —
environmental, municipal, construction, utilities, waste management — will carry facility rows,
and every standards document with a 规范性引用文件 section is exposed to the citation-mining
defect. Downstream effects:

- `kb.products` rows that are not products.
- `kb.product_names` accumulates `status='proposed'` rows that can never match the NMPA
  classification catalog, polluting the curation queue. At time of writing, 34 of the 638
  `source='extract_products'` proposed rows are facility-shaped.
- Fabricated `requirement_text` on citation-grounded rows (2b) is a correctness problem, not
  just a precision one — it asserts normative content the source document does not contain.
- Cost: bad candidates are amplified into multiple Pass 2 rows each, compounding the output-token
  problem recorded in `2026092103`.

Historical blast radius across other records was not queried this session. `product_type='system'`
plus an `evidence_quote ~ '^[A-Z]{2,6}[ /][A-Z0-9]'` predicate give a usable first-pass audit.

## 4. Fix implemented (uncommitted)

**`prompt-extract-product-mentions-v2.md` (new, replaces v1 as the Pass 1 prompt):**

- Adds the operative test — a product is a **movable, procurable article**; a facility is
  constructed at a site — with an explicit exclusion list (facilities, plants, stations, depots,
  collection/storage points, centres, bases, buildings, rooms, civil-engineering works and
  projects, installations assembled in place).
- Chinese naming cues: suffixes `站`/`厂`/`场`/`基地`/`中心`/`园`/`区`/`房`/`池`/`工程`/`设施`,
  and locational `点` (`投放点`, `贮存点`).
- A keep-vs-drop example table built from the record's real false positives
  (`垃圾焚烧炉` vs `生活垃圾焚烧厂`, `垃圾转运车辆` vs `垃圾转运站`, `沼气` vs `沼气工程`).
- `系统` judged by the same test: a licensed software system is a product; a physical system
  assembled on site is not.
- A **referenced-document-title rule**, scoped as an *evidence* rule rather than a product rule:
  a citation line may never be used as `evidence_quote`, but a product that also appears in body
  text is extracted normally from that body line. Only a citation-**only** mention is skipped.
- `product_type_hint` field rule now reserves `system` for software/information systems and
  states that a physical installation must be omitted rather than typed `system`.

**`prompt-enrich-product-mention-v4.md` (new, replaces v3 as the Pass 2 prompt):** replaces the
"you are not re-deciding whether it qualifies" instruction with a deliberately **narrow veto** —
Pass 2 returns an empty `products` array when a candidate is clearly a place/facility/works, an
organization, person, abstract concept, activity, legal act, document section, or is supported
only by a citation line. Explicitly not a general confidence filter (thin evidence remains
Rule 3's and the confidence floor's job), so it cannot quietly become a second uncalibrated
recall gate.

**`extract-products.go`:** default prompt refs bumped to v2/v4.
**`mise.local.toml`:** both pins updated to match (see 2d).
**Spec:** Pass 1 section documents the gate and both exclusions; Pass 2 section documents the v4
veto; new "Configuration Override Caution" section records the env-override trap.

### Prompt-balance regression, caught and corrected

The first draft of the v2 exclusions **over-corrected**. Framing Pass 1 as "the only producthood
gate" and asserting that "omitting a non-product is correct, not a recall failure" shifted the
model's posture toward rejection globally rather than toward rejecting facilities specifically.
Measured against v1 on record 416, that draft dropped 57 distinct mentions where only ~18 were
facilities, losing core recyclables the standard is actually about — `瓶`, `罐`, `箱`, `袋`,
`易拉罐`, `图书`, `报纸`, `废弃家具`, `旧纺织衣物`, `电器电子产品`.

The shipped v2 keeps the exclusions but restores balance with an explicit "be thorough about
ordinary articles" keep-list and a symmetric Rule 7 — "dropping a real product is as much an
error as extracting a facility". This is the main lesson of the bug: **a precision fix to an
extraction prompt must be measured on aggregate recall, not spot-checked on the false positives
it was written to fix.**

## 5. Verification

A/B harness: both Pass 1 prompts run over all 10 chunks of record 416, reconstructed from
`std_1503937_mineru.txt` + `.chunks` with the same overlap flags the processor builds, same model
(`deepseek-v4-flash`), temperature 0.

| metric | v1 | shipped v2 |
|---|---|---|
| facility-shaped distinct mentions | 13 | **0** |
| total distinct mentions | 140 | **154** |

All 13 facility mentions eliminated, with recall up rather than down. The 17 facility/works names
dropped are exactly the intended targets (垃圾转运站, 生活垃圾焚烧厂, 生活垃圾卫生填埋场,
环境卫生设施, 农村沼气集中供气工程, 臭气处理设施, 污水收集和处理设施, …). 生物有机肥 and
微生物肥料 are also dropped and this is **correct** — verified above, they occur only in citation
lines.

**Caveat on measurement:** this pass is not deterministic even at temperature 0 — two identical
v1 runs returned 151 and 140 distinct mentions. Single-item deltas are noise; only aggregate
movements should be read as signal. The facility count (13 → 0) was stable across both runs.

`go build ./...` clean; `go test ./server/api/doc-processing/` passes (4 consecutive runs). One
transient failure was observed — a goroutine panic at `control.go:276` — which reproduced on
neither of the four subsequent runs and originates in pre-existing uncommitted work in
`control.go`, not in this change.

## 6. Tasks

- [x] Reproduce and characterize the reported rows against real `kb.products` data
- [x] Identify the missing facility/works exclusion in the Pass 1 producthood gate
- [x] Identify citation-title mining as a second, distinct defect behind two of the five rows
- [x] Identify Pass 2's "not re-deciding" instruction as the reason neither is recoverable
- [x] Write `prompt-extract-product-mentions-v2.md` with both exclusions
- [x] Detect and correct the recall over-correction in the first v2 draft via full-document A/B
- [x] Write `prompt-enrich-product-mention-v4.md` with the narrow veto
- [x] Bump Go defaults **and** `mise.local.toml` pins
- [x] A/B verify on record 416: facility mentions 13 → 0, distinct mentions 140 → 154
- [x] Update the capsule spec (Pass 1, Pass 2, Configuration Override Caution)
- [ ] Re-run the processors on record 416 — user is doing this
- [ ] After the re-run, confirm `kb.products.prompt_name` reads `prompt-enrich-product-mention-v4.md`
      (guards against the 2d pin trap) and that `product_type='system'` no longer contains
      facilities
- [ ] Commit the `ChenWeb` prompt/code changes and the `KnowledgeStore` spec update (two repos,
      via `jj`) — note the `ChenWeb` working tree carries unrelated uncommitted work in
      `control.go`/`event.go`/`jetstreamhandler/` that must not be swept into this commit
- [ ] Decide whether to clean up the 34 facility-shaped `status='proposed'` rows already in
      `kb.product_names` — deferred by user
- [ ] Size the historical blast radius across other records (`product_type='system'` and
      citation-shaped `evidence_quote`) — not done this session

## 7. Open questions / future related activities

- **Should `facility` become a real `product_type` value?** This session's fix excludes
  facilities outright, on the user's decision. The document genuinely imposes requirements on
  them (乡镇应科学配置垃圾转运站…), and those requirements are now simply not captured anywhere.
  If that content matters, the right shape is a separate facilities extractor or a `facility`
  type with its own table — not readmitting them to `kb.products`.
- **Borderline: built-in-place units that are arguably articles.** `农村户用沼气池` (a household
  biogas digester) is excluded by the `池` cue, but is closer to a purchasable unit than a
  facility. Likewise `宣传栏`. If curation shows these are wanted, the cue list needs a
  carve-out rather than a loosened rule.
- **`product_type='other'` and `material` buckets were not audited.** They contain items like
  烟蒂, 蛋壳, 腐肉, 笋壳, 谷壳, 庭园饲养动物粪便 — defensible for a waste-classification standard
  (they are the regulated objects) but worth a look if precision complaints continue.
- **The `system` bucket loses its audit value once this fix lands.** Future facility leakage will
  not be detectable by `product_type='system'` alone, since legitimate software systems share it.
- Relationship to sibling bugs: `2026092103` (Pass 2 wasted output tokens / prompt drift) and
  `2026092104` (Step B dedup missed paraphrased duplicates) are the other two defects found in
  this processor on the same record. All three compound: bad candidates (this bug) × multiple
  relation rows each (`2026092103`) × failed dedup (`2026092104`) is what produced 1219 rows from
  a 12-page document.
