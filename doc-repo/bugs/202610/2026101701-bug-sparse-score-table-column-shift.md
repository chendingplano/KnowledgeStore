# Record 364: sparse score columns shifted and distinct bands collapsed

2026-10-17. Affected document: WS/T 810—2022, 基层医疗卫生机构急重患者判断及转诊技术标准.

## Evidence and causes

Canonical line 118 and its original table image show heart-rate bands ≤40, 41~50,
51~100, 101~110, 111~129 and ≥130 under scores 2, 1, 0, 1, 2 and 3. The score-3
column before ≤40 is empty. The canonical HTML and TableGrid column labels are correct.

Pass 1 log 140715 candidate 4_14 already assigned the wrong first two scores (3, 2).
Pass 2 log 140736 shifted the first five populated cells to scores 3, 2, 1, 0, 1;
the final ≥130 score remained 3. English context repeated the erroneous mapping.
The model input retained blanks but required positional alignment across two header
rows with repeated numeric labels. The prompts did not explicitly cover sparse scoring
tables. This was an extraction error, not a source-parser error.

Pass 2 emitted all 23 table cells, but left every condition empty. Final deduplication
compares name, subject, unit, score, source lines and condition. Thus equal scores for
different bands on the same source line collided, leaving only 18 rows. The deduper
works as designed when the band condition is populated.

## Repair and prevention

- Corrected 364_mtc_122–125 from 3, 2, 1, 0 to 2, 1, 0, 1.
- Preserved all 18 existing IDs and added source-grounded bilingual conditions to them.
  Rebuilt their English contexts directly from the source mapping.
- Restored the five lost bands as 364_mtc_140–144: heart rate 111~129 (2 points),
  heart rate ≥130 (3), systolic pressure ≥200 (2), respiratory rate 21~29 (2), and
  temperature ≥38.5 (2). The table now has all 23 nonempty cells, and the document
  has 144 metrics. Refreshed the `.metrics` cache and search text via the database trigger.
- Multi-level table data rows now give explicit full-header/value pairs, with complete
  cell text. Single-header serialization, source row IDs and hashes are unchanged.
- New candidates v26 and enrich v25 prompts require one row per scoring cell, the
  source score, a band/state condition, and consistent translations. Defaults and the
  ignored local mise prompt overrides select the new versions. A running backend must
  reload/restart to use the code and newly selected prompts.

The repair backup, source hash, SQL, verification results and replay-guarded Python
script are in `/Users/cding/Apps/SemOS/Artifacts/0/364/score-table-repair-20261017/`.
Database log activity `repair_sparse_score_table` records the affected IDs and backup.
The script checks every mapping against canonical line 118 before applying, and
verifies all 23 persisted rows afterward. Original extraction logs and gold benchmarks
are intentionally unchanged; they remain historical evidence.

## Validation and knowledge impact

The sparse-score regression failed on the old positional rendering, then passed with
the paired rendering. A second regression keeps six bands with repeated scores while
deduplicating a truly repeated band. The full `server/api/doc-processing` package passed.
One full-suite run encountered an intermittent concurrent-map panic in extraction
logging; the preceding and subsequent runs passed. No unrelated concurrency changes
were made.

Updated the extraction specification's conditions section and this incident report.
Older prompt versions remain available for reproducibility, rather than being edited
in place. No schema or public API changes; no frontend changes. No full stochastic
LLM extraction rerun was used to overwrite the document's other metrics. No claim is
made that other documents' historical scoring rows have been audited or repaired.
