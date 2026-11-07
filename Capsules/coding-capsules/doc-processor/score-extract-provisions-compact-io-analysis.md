# Compact provision scoring input and output

Analysis date: 2026-11-07. Status: measured proposal; scoring code, skill and prompt are unchanged.

## Finding

The matching model receives much more than it needs to decide statement identity,
false-positive causes and subject equivalence. Keep the complete evidence snapshot
for reproducibility, but derive a separate, small LLM view. Return compact decisions
and expand them into the existing scorer contract before validation and arithmetic.

This is independent of the extraction response format. Scoring does not need to
produce translations, descriptions, field grades or a narrative report: Python
already computes the grades and writes the report.

## Captured evidence

`public.llm_usage_event.id = 'llm-6adc0b65'`:

- Document 416; provision score run 2; model `deepseek-flash`.
- Prompt `prompt-score-extract-provisions-v1.md`.
- 35,725 input tokens, 3,323 output tokens; 768 input cache-hit tokens.
- 84 gold rows, 70 predictions, 35 excluded/duplicate ledger candidates.
- Captured decisions: 52 pairs, 32 misses, 18 false positives, no overrides.
- Existing scorer produces 57/100. This analysis does not reassess those decisions.

Request and response were read from the archived gzip bodies under
`/Users/cding/Apps/llm-logs/2026/2026-11/2026-11-07/account-bbdc2874-2dcf-4d7a-b6af-80ac74cdcb14/bodies/llm-6adc0b65-{input,output}.json.gz`.
The saved scoring evidence is `/Users/cding/Apps/SemOS/provision-score-runs/2/evidence/`.
No provider call or database write was made for this analysis.

### Actual input composition

Lengths below count Unicode characters, not bytes or provider tokens.

| Component | Characters |
|---|---:|
| System prompt | 3,949 |
| SCORING_INPUT snapshot | 83,986 |
| SOURCE_LINES | 10,477 |
| Labels and language selector | 48 |
| Total message content | 98,460 |

The snapshot contains approximately 43,470 characters of gold rows, 22,003 of
predictions, 9,967 of suggestions, and 6,806 of ledger candidates. The remainder
is metadata and JSON structure. Suggestions alone occupy almost as much space
as the entire source document sent to the matcher.

Important: the live runner already minifies this snapshot when source text is
available. Changing the export's indentation alone will not reduce this request.
It also already removes `source_text` from the LLM snapshot before appending
SOURCE_LINES. There is no second complete source copy in this captured request.
The saved audit snapshot does contain the source, as intended.

## Code and prompt analysis

1. `.agents/skills/score-extract-provisions/SKILL.md` instructs the agent to read
   the entire export, including suggestions and the ledger. It uses full IDs,
   verbose objects and notes for every decision. Update it alongside any new
   matcher view so terminal and UI scoring use the same contract.
2. `scripts/score_io.py`, `GOLD_FIELDS`, `PRED_FIELDS`, `compact_gold` and
   `compact_pred`: "compact" currently means field selection, not a minimal
   matching representation. It retains names, English counterparts, confidence,
   evidence, section and other metadata. Those belong in the audit snapshot.
3. `suggestions()` emits up to five prediction IDs with text similarity and
   weighted credit per gold row. Matching does not require numeric credit;
   showing it can encourage choosing a higher-scoring pair rather than the same
   statement. Remove suggestions from the matcher view. If hints prove useful,
   retain only candidate indices, without grades, and measure their value.
4. `ChenWeb/server/api/kbhandler/metric_score_runner.go`, `executeScore` and
   `buildMetricScoreInput`: shared infrastructure exports the provision snapshot,
   adds provenance, sends all fields and full source lines, then validates with
   the frozen Python scorer. Insert a provision-specific projection here or
   consume a projection produced by the frozen skill. Do not silently change
   metric/reference scoring, which also uses this runner.
5. `ChenWeb/prompts/prompt-score-extract-provisions-v1.md` explicitly requires
   reading the complete snapshot and returning exhaustive verbose decisions.
   A versioned v2 prompt should describe the smaller matching view and output
   contract. Preserve matching rules, one-to-one accounting, merge/split rules,
   source-change behavior, subject overrides and evidence-as-data instructions.
6. A validation failure triggers one full retry: original input plus all previous
   matches and the validation error. Compact input and decisions reduce both
   attempts. Keep the complete evidence and bounded retry; never silently accept
   missing rows to avoid a repair call.

## Input proposal

Keep `input.json` as the full immutable scoring snapshot. Add a separately
versioned matching view with just:

- `lines_comparable` and actionable source-availability/change warnings.
- For each gold/prediction: statement text, original subject and source spans.
- For each ledger candidate: text, source spans, exclusion/duplicate rule and
  rationale. Keep all ledger candidates initially, including their reasons.
- Full SOURCE_LINES initially, plus output language.

Remove model/run metadata, filesystem paths, hashes, extraction times, provenance,
confidence, names, translations, deterministic scoring fields, and suggestions
from the LLM view. Preserve all of them in the audit snapshot and reports.
Gold kind remains available locally for per-kind recall; it is not needed for
matching. Subject must remain in the LLM view because semantic subject overrides
are the one field judgment delegated to the model.

Two measured serialization choices, using the captured rows:

| Row representation | Snapshot chars | With unchanged full SOURCE_LINES | Reduction vs original snapshot + source |
|---|---:|---:|---:|
| Original | 83,986 | 94,463 | — |
| Minimal named fields, full IDs | 27,516 | 37,993 | 59.8% |
| Indexed positional arrays | 13,528 | 24,005 | 74.6% |

These are payload measurements excluding the prompt and framing; a new prompt's
length and the provider's token count have not been measured. The named-field
variant is a lower-complexity first step. For the smallest contract, use arrays
with fixed schemas: `g`/`p` rows `[spans,text,subject]`, candidate rows
`[spans,text,rule,reason]`. A row's one-based position is its local ID. Persist
the exact ordering/ID mapping; never assume the suffix of a database ID is the
array index. Preserve original spans; do not renumber source lines.

### Source filtering is secondary

Of 169 source lines, 74 are referenced by any gold row, prediction or ledger
candidate. Their serialized lines occupy 6,744 characters; adding physical
line-number neighbours within ±1 occupies 8,472 characters. Neither selection
is a validated context policy. Section headings, list introductions, complete
tables and antecedents may be farther away. Start with the full 10,477-character
source: pruning row metadata provides much larger savings.

Do not reconstruct provision text from whole lines: several gold provisions can
share one line. Do not remove ledger candidates solely because they have no
line overlap when source versions differ. If later batching is necessary, use
complete overlap components when lines are comparable, with a global duplicate
pass and explicit handling of prediction-only components. There are 52 gold/
prediction overlap components here, largest 24 rows; this does not establish
semantic independence or justify 52 separate model requests.

## Output proposal

Use exhaustive compact decisions with no prose for routine outcomes:

```json
{"v":2,"p":[[2,10]],"m":[[1,0,"Reason"],[4,11]],"f":[[1,"x",6]],"o":[]}
```

Illustrative schema, with one-based local indices:

- `p`: `[gold,prediction]` pairs.
- `m`: `[gold,0,reason]` for a genuine miss, or `[gold,prediction]` when merged
  into a prediction paired elsewhere. Generate the paired-gold reference locally.
- `f`: `[prediction,cause,target]`, with an optional final explanation when
  needed. Causes: `x` ledger exclusion/duplicate, `s` split, `d` prediction
  duplicate, `n` not in gold, `i` invalid. Targets respectively identify a ledger
  row, paired gold row, other prediction, or null. Require a reason for `n`/`i`;
  `n` must explain whether gold appears to have missed a real provision.
- `o`: `[paired_gold,correct,reason]` for subject-only overrides. Preserve the
  current boolean semantics and require a specific equivalence explanation.

Expand ledger candidate/rule IDs, full provision IDs and routine localized
explanations locally. Preserve an explanation for unusual cases such as a
prediction that duplicates another statement but appends a separate sentence.
Require every gold and prediction exactly once; do not interpret an omitted row
as an intentional miss or false positive. Reject unknown versions, invalid
indices, duplicate accounting, incorrect target types and unknown causes.

| Transformation of captured response | Characters | Reduction |
|---|---:|---:|
| Original response content | 9,852 | — |
| Remove only empty notes | 9,532 | 3.2% |
| Remove all notes, retain verbose IDs/objects | 4,415 | 55.2% |
| Indexed decisions, structured merge links, exceptional reasons retained | 1,071 | 89.1% |

The final row is a retrospective encoding of this one captured response, not
a fresh model response. It retains all decisions, the genuine-miss explanation,
31 merge links and the exceptional duplicate explanation. Routine pair merge
notes are recoverable from those links; exclusion reasons come from the ledger.
Wording of generated notes changes. A compact decoder must preserve exceptional
notes and must not infer semantic classifications from text similarity alone.

An offline indexed encode/decode replay passed the existing `check_matches` and
`score` functions. Score (57), overall metrics, per-type metrics, per-kind recall,
field accuracy and weights were identical to the original. This establishes
arithmetic preservation for captured decisions, not future matching accuracy.

## Implementation and acceptance plan

1. Freeze this event as a regression fixture. Add the projection and a versioned
   compact decoder in the skill, usable by both CLI and UI. Keep one authority
   for mapping and validation; expand to the old scorer structure.
2. Add prompt v2 and update the skill instructions and provision prompt selector.
   Keep the existing score formula, weights, database shape, report shape and
   full audit evidence. Persist the exact matcher projection and its version so
   runs remain reconstructable. Include new helper files in frozen skill hashes.
3. Test invalid indices/versions/causes, exhaustive accounting, source-change and
   unreadable-source paths, subject overrides, splits, duplicate chains, merge
   references, exceptional reasons and repair responses. Verify compact replay
   produces identical scoring measures for the saved decisions.
4. Evaluate fresh compact matching against adjudicated cases, including shared
   source lines, mixed subjects/types, tables, changed source, duplicates and
   split/merge ambiguity. Compare match decisions and error patterns, not merely
   final scores. An arithmetic round-trip cannot demonstrate matching quality.
5. Measure provider tokens and aggregate retry tokens before claiming token
   savings. The request's `max_tokens` is currently 100,000; use a realistic,
   row-count-based output budget only after contract validation. Lowering that
   ceiling alone does not reduce actual output, and truncation creates retries.

No existing docs/specs become stale from this analysis because behavior has not
changed. Implementation would require updating the scoring skill, its tests,
versioned prompt, runner integration and applicable capsule contract docs.
