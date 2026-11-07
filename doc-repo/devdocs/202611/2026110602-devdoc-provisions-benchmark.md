# Provisions Benchmark — an answer key and a quality score for extract_provisions

**Date:** 2026-11-06 \
**Scope:** What the provisions benchmark is, how its answer key is made and scored, and where
its two ChenWeb pages are. Open this before you build gold provisions for a document, score
`extract_provisions`, or change the provisions benchmark rules.
**Code root:** `.agents/skills/extract-provisions-benchmark`, `.agents/skills/score-extract-provisions`,
`ChenWeb/server/api/kbhandler/gold_provisions.go`, `ChenWeb/server/api/kbhandler/provision_score_handler.go`,
`ChenWeb/web/src/lib/components/home3/provision-score-view.svelte`

**Traceability — openspec** (the change is not archived yet; after archiving, these paths move
under `openspec/changes/archive/`, and the specs move to `openspec/specs/`):
- `ChenWeb/openspec/changes/extract-provisions-benchmark/proposal.md`: why this exists.
- `ChenWeb/openspec/changes/extract-provisions-benchmark/design.md`: decisions D1–D6,
  alternatives considered, risks and trade-offs.
- `ChenWeb/openspec/changes/extract-provisions-benchmark/tasks.md`: the implementation log.
- `ChenWeb/openspec/changes/extract-provisions-benchmark/specs/provision-gold-benchmark/spec.md`
  and `.../specs/provision-benchmark-scoring/spec.md`: the requirements. **If behavior
  changes, update these spec files, not just this doc.** This doc explains the feature for
  people; the spec is the contract.

## Summary

Standards, regulations and similar documents are full of **provisions**: sentences that say what
must, should, may or must not be done. The document processor `extract_provisions` uses an AI
model to find these sentences and stores them in the table `kb.provisions`. Until now nobody could
say how good that output was, because there was nothing to compare it with.

The provisions benchmark adds that comparison, in the same way the Metrics, References and
Summaries benchmarks already work.

1. **An answer key (the "gold" provisions).** A coding assistant reads one document line by line
   and lists every provision it really contains. It runs the skill
   `extract-provisions-benchmark`, following a fixed, numbered rule book (the rules file). For each
   provision it records:
   - the exact text and the source lines;
   - its strength: mandatory, recommended or optional;
   - its kind: requirement, prohibition, instruction, recommendation or permission;
   - who or what it binds;
   - where it sits (a sentence, a list item, a table cell …);
   - whether it is stated outright (应 / shall / 宜 / 可 …) or only implied by the section it is in.

   The assistant also records every statement it decided is *not* a provision, and why: scope
   statements, definitions, pointers such as "see Table 1", and so on. The result is saved as a
   separate, unchangeable "run" in the test area of the database, never in the production table.
2. **A score.** The skill `score-extract-provisions` lines up the production output with the
   answer key: which extracted row is the same statement as which gold row, what was missed, and
   what was extracted wrongly. It then computes a score from 1 to 100. A script does the
   arithmetic, so the score can be reproduced from the saved files.

Three choices in the first rule book (version 1.0.0) were made by the user:
- A step of a test method ("称取试样 3 个…") counts as a mandatory provision.
- One provision is one normative statement: normally one sentence. A sentence is split only when
  its strength changes (must → may) or it starts to bind a different party or object.
- The first answer key is for record 416 (DB33/T 2030—2018, 农村生活垃圾分类处理规范).

That first answer key exists. Run `20261106_143017` (rules 1.0.0, made by `claude-opus-5-5`) has:
- 84 gold provisions: 80 mandatory, 3 optional, 1 recommended; 15 of them only implied;
- 35 statements recorded as not provisions.

Its working files are in `Artifacts/0/416/benchmark-provisions/1.0.0/claude-opus-5-5/20261106_143017/`
under the data home directory.

**Changing the rules.** The rule book is versioned and frozen. To change what counts as a
provision, release a new rules version (for example 1.1.0 or 2.0.0). Never edit the released
file, because scores are only comparable against the same answer key.

## Where things live

**In ChenWeb** (development page only, admin and root users): System Admin › Benchmark ›
**Provisions** has two pages.
- **Gold Provisions** shows the answer keys. Pick a document and a run on the left. The list then
  shows its gold provisions, or, with the list switch, the statements that were left out. Clicking
  one highlights its lines in the PDF. The page is read-only: the extract, edit and line-editing
  tools of the ordinary Provisions page are hidden.
- **Benchmark** scores a document. Pick a document, a scoring model and (optionally) a gold run,
  then press Run. The scoring runs in the background and lands in the history table. Opening it
  shows:
  - the score;
  - precision and recall;
  - a breakdown by strength and by kind;
  - how often each checked field was right;
  - the matched, missed and wrongly extracted statements, each of which highlights its lines in
    the PDF;
  - the full report.

**In the workspace:**
- Gold skill: `.agents/skills/extract-provisions-benchmark/`. The procedure is in `SKILL.md`, the
  rule books in `rules/` (listed with their checksums in `rules/versions.json`), field contracts in
  `references/benchmark-contract.md`, and the plain-language guide in `USER_MANUAL.md`.
- Scoring skill: `.agents/skills/score-extract-provisions/`. The procedure is in `SKILL.md`, the
  default weights in `weights.json`.
- Database:
  - answer keys in `testbed.provision_benchmark_runs`, `testbed.provisions` and
    `testbed.provisions_dropped` (migration `20261106000101`);
  - score history in `testbed.provision_score_runs` (created by migration `20261106000102` and moved by `20261107000001`).
- Server:
  - `GET /api/v1/kb/provisions?source=testbed&…` and `GET /api/v1/kb/provisions/gold-options`
    for the Gold page;
  - `/api/v1/kb/provision-scores` for the Benchmark page;
  - matching prompt `ChenWeb/prompts/prompt-score-extract-provisions-v1.md`.
- Browser smoke test: `ChenWeb/web/scripts/test-provision-benchmark-pages.py` (mocked data,
  English and Chinese).

## Known limitations

- **Record 416 cannot be scored yet.** Its `kb.provisions` rows were deleted at some point, so
  `extract_provisions` has to run on it once. Until then, scoring 416 reports "no predictions".
- **Only some fields are graded.** The score checks strength, text, lines, subject, location and
  explicitness. Production rows store no "kind", so kind is reported only as recall (how many gold
  requirements, instructions … were found). Names, descriptions, keywords, categories and
  extracted objects are free text and are not graded.
- **The sentence rule is strict.** An extractor that returns one row per numbered clause gets a
  match for one sentence, and the other sentences count as missed. The report shows this as
  "merged into …" notes, so it can be told apart from real misses.
- **One annotator per run.** An answer key is one model's careful reading, checked twice by that
  model. A second opinion means a second run, preferably by a different model, and the scoring page
  warns when the gold run and the scorer use the same model.
- **The text check rewards copying the source.** This is intended, because production's
  `provision` field is meant to hold the original wording.
