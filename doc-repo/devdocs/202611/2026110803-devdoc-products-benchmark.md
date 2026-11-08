# Products Benchmark — an answer key and a quality score for extract_products

**Date:** 2026-11-08 \
**Scope:** What the products benchmark is, how its answer key is made and scored, and where its two
ChenWeb pages are. Open this before you build gold products for a document, score
`extract_products`, A/B a products prompt or model, or change the products benchmark rules.
**Code root:** `.agents/skills/extract-products-benchmark`, `.agents/skills/score-extract-products`,
`ChenWeb/server/api/kbhandler/gold_products.go`, `ChenWeb/server/api/kbhandler/product_score_handler.go`,
`ChenWeb/web/src/lib/components/home3/product-score-view.svelte`

**Traceability — openspec** (the change is not archived yet; after archiving, these paths move
under `openspec/changes/archive/`, and the specs move to `openspec/specs/`):
- `ChenWeb/openspec/changes/extract-products-benchmark/proposal.md`: why this exists.
- `ChenWeb/openspec/changes/extract-products-benchmark/design.md`: decisions D1–D7, alternatives
  considered, risks and trade-offs.
- `ChenWeb/openspec/changes/extract-products-benchmark/tasks.md`: the implementation log, including
  what was not verified live.
- `ChenWeb/openspec/changes/extract-products-benchmark/specs/product-gold-benchmark/spec.md` and
  `.../specs/product-benchmark-scoring/spec.md`: the requirements. **If behavior changes, update
  these spec files, not just this doc.** This doc explains the feature for people; the spec is the
  contract.

## Summary

The document processor `extract_products` uses an AI model to find the products a document names
(bins, vehicles, appliances, materials, waste categories …) and to record how the document relates
to each one: the product is in scope, must be designed a certain way, must be stored or transported
a certain way, must meet limits, and so on. It stores one row per product and relation in the table
`kb.products`. Until now, prompt and model changes to this processor could only be judged by spot
checks and by counting how many products came out. The products spec itself asks for every prompt
change to be compared properly, and for merged-pass mode to be re-measured for each new model.

The products benchmark makes that possible. It works like the Metrics, References and Provisions
benchmarks.

1. **An answer key (the "gold" products).** A coding assistant reads one document line by line,
   following the skill `extract-products-benchmark` and its fixed, numbered rule book. It decides:
   - which things are products and which are not (a facility, a place, an organization, a measured
     property, or something named only in a cited document's title is not a product);
   - each relation the document has with each product, one row per relation;
   - for each row, the obligation (mandatory, permitted …), the requirement text copied from the
     source, conditions, numeric parameters, the responsible party, and the second product for
     part/whole or replacement relations.

   It also records every candidate it rejected, and why. The result is saved as a separate,
   unchangeable "run" in the database's test area, never in the production table.
2. **A score.** The skill `score-extract-products` lines up the production rows with the answer
   key: which extracted row is the same relation of the same product as which gold row, what was
   missed, and what was extracted wrongly. A script then computes:
   - a score from 1 to 100 over the rows, where each matched row earns partial credit for the
     fields it gets right (a row with the right product and fact but the wrong relation type still
     earns most of its credit);
   - **product detection**: how many of the document's products were found at all, whatever their
     relations. This is the number the spec's prompt comparisons track.

Four choices in the first rule book (version 1.0.0) were made by the user:
- One gold row is one product and one relation, as in `kb.products`; the rows of one product share
  a product key.
- Waste categories and waste streams (可回收物, 易腐垃圾, 有害垃圾, 废玻璃, 渗滤液 …) are products.
- Obligation, requirement text, conditions, parameters, related products and responsible party are
  all graded. Requirement text is graded by similarity to the source wording, so paraphrases score
  lower.
- The first answer key is for record 416 (DB33/T 2030—2018, 农村生活垃圾分类处理规范).

That first answer key exists. Run `20261108_110147` (rules 1.0.0, made by `claude-opus-5-5`) has 188
gold rows for 160 products, and 134 rejected candidates (facilities, organizations, measured
properties, citation-only names). Its working files are in
`Artifacts/0/416/benchmark-products/1.0.0/claude-opus-5-5/20261108_110147/` under the data home
directory.

**First score.** Record 416's existing extraction (deepseek-flash, 2026-11-07, 138 rows) scores
**66**. Product detection: 94.6% precision, 76.9% recall. What it misses most: the umbrella waste
classes of the recyclables list (废弃纸制品, 废塑料制品, 废玻璃 …), the six things the definition
excludes (工业垃圾, 建筑垃圾 …), and waste streams such as 渗滤液, 飞灰 and 炉渣. It also labels the
hazardous-waste examples as "regulated" rather than "in scope", and finds only 2 of the 12
storage/transport duties. The scoring files are in
`Artifacts/0/416/extract-products-scores/1.0.0/claude-opus-5-5/20261108_110147/20261108_score1/`.

**Changing the rules.** The rule book is versioned and frozen. To change what counts as a product
or how a relation is chosen, release a new rules version (for example 1.1.0 or 2.0.0). Never edit
the released file, because scores are only comparable against the same answer key.

## Where things live

**In ChenWeb** (development page only, admin and root users): System Admin › Benchmark ›
**Products** has two pages.
- **Gold Products** shows the answer keys. Pick a document and a run on the left; the switch below
  the run filters chooses between the gold rows and the rejected candidates. Clicking a row opens it
  next to the PDF with its lines highlighted. The page is read-only. It is the ordinary
  Products view with a test-area source.
- **Benchmark** scores a document. Pick a document, a scoring model and (optionally) a gold run,
  then press Run. The scoring runs in the background and lands in the history table. Opening it
  shows the score, product detection, a breakdown by relation type and by product type, how often
  each checked field was right, the matched, missed and wrongly extracted rows (each highlights its
  lines in the PDF), and the full report.

**In the workspace:**
- Gold skill: `.agents/skills/extract-products-benchmark/`. The procedure is in `SKILL.md`, the
  rule books in `rules/` (with checksums in `rules/versions.json`), field contracts in
  `references/benchmark-contract.md`, and the plain-language guide in `USER_MANUAL.md`. Its helper
  reads table rows with a copy of ChenWeb's table parser, so evidence such as `121#r3` means the same
  row the extractor saw. If ChenWeb changes how it numbers table rows, the copy must follow.
- Scoring skill: `.agents/skills/score-extract-products/`. The procedure is in `SKILL.md`, the
  default weights in `weights.json`. It uses the same compact request format as the provisions
  scorer.
- Database:
  - answer keys in `testbed.product_benchmark_runs`, `testbed.products` and
    `testbed.products_dropped` (migration `20261108000101`);
  - score history in `testbed.product_score_runs` (migration `20261108000102`).
- Server:
  - `GET /api/v1/kb/products?source=testbed&…` and `GET /api/v1/kb/products/gold-options` for the
    Gold page;
  - `/api/v1/kb/product-scores` for the Benchmark page;
  - matching prompt `ChenWeb/prompts/prompt-score-extract-products-v1.md`.
- Browser smoke test: `ChenWeb/web/scripts/test-product-benchmark-pages.py` (mocked data, English
  and Chinese).

## Known limitations

- **No live page scoring yet.** The Benchmark page was checked with mocked data, and the first
  score (66) was matched by the assistant through the scoring skill, not through the page. The
  first real run from the page is still to be done.
- **Gold and scorer are the same model so far.** Both the 416 answer key and its first score were
  made by `claude-opus-5-5`. The page warns about this; a scoring model other than the gold model
  gives an independent check. The assistant had also seen a 25-row sample of 416's production rows
  before annotating; the run says so.
- **Relation types overlap.** "In scope", "regulated" and "requirement target" are close. The rule
  book fixes an order for choosing between them, and a wrong relation type costs only that field
  (20 of 100 points of the row), not the whole row.
- **One row per relation means long rows.** When a document states several things of the same
  kind about one product (for example two transport duties), they form one gold row with all their
  lines and text. Production that keeps them as two rows gets one match and one duplicate.
- **Only one record has gold.** Record 416 is a waste-sorting standard; product standards and test
  methods (for example record 753) behave differently and need their own answer keys before the
  score generalizes.
- **Names must match closely.** A different surface for the same product (废血压计 vs 血压计) fails
  the name check unless the matcher overrides it with a reason; such overrides are listed in the
  report.
