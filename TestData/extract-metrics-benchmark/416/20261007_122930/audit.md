# Document 416 gold metrics audit

Saved and read back **32 metrics** in `testbed.metrics`, using `extract-metrics-benchmark` rules **4.0.0**.

- Document: 农村生活垃圾分类处理规范, DB33/T 2030—2018.
- Requested model profile: `deepseek-flash-processor`; configured and returned API identity: `deepseek-flash`.
- Annotation author: DeepSeek; independent source review, corrections and persistence: Codex.
- Full run key: (`extract-metrics-benchmark`, `4.0.0`, `deepseek-flash`, `20261007_122930`).
- Source: `/Users/cding/Apps/SemOS/Artifacts/0/416/std_1503937_mineru.txt`.
- Source SHA-256: `5acb3df6b320fdd4d3e293cc8170e4b68511ee274b2ee3f930268b1a4a590fcd`.
- Rules SHA-256: `82e5b8a2aa032e0650b9738c0f60d7bc2f234c7646d9dff0e7be2d179773ee34`.
- Coverage: all **169** canonical records, no numbering gaps; 17 non-overlapping section-specific coverage regions.
- Candidate ledger: **130** decisions, **32 accepted**, **95 excluded**, **3 duplicate pointers**.
- Stored kinds: 12 requirements with numeric criteria, 2 declared equipment values left open, 15 test parameters, 3 metric definitions/interpretation cut-offs.

## Review findings

The independent review recovered the two equipment-declaration metrics (specific energy consumption and fermentation duration), the sample and blank-control counts, and the separate GI <100% and >100% interpretations. It corrected candidate links, ranges and formula representation. Table 2 applies only to machine-composting fertilizer; Table 3 applies to both machine and solar-assisted composting. Measurement basis stays in the property description rather than condition.

Physical inspection features and referenced-standard requirements remain excluded candidates (X15/X16). The solar-greenhouse volume sizing duty is X17; agreed kitchen-waste activity time/frequency is X2. The 500 ml bottle and filter-paper sheet are apparatus/procedure instructions (X12). Test conditions, bounds, translations, table rows and exact evidence were checked against the source. The project's `ParseTableGrid` implementation supplied the recorded row IDs and hashes.

The final model response reached its output cap only during an optional extra envelope note; every required field, metric and review was already complete. Recovery and model call metadata are documented in `model-provenance.json`; all later independent corrections appear in `review-corrections.json`. `model-annotation.json` preserves the recovered author draft, and `benchmark.json` is the validated, stored result.

## Verification and scope

Save completed in one transaction. A read-back selected document 416 and the complete run key and matched every substantive field, source hash, excerpt, table-row reference and audit/provenance field against the validated JSON. Only the helper-generated review timestamp was excluded from comparison. `readback-verification.json` records the result and hashes. The source copy in `canonical-source.txt` preserves the reviewed input.

Coverage is complete within the supplied canonical line file. The original PDF and page images were not independently audited; this run makes no claim about original-PDF coverage. No unresolved ambiguity remains within the canonical source. Production extraction predictions were neither read nor called during annotation.

Knowledge changed: a new independently reviewed 4.0.0 gold snapshot exists for document 416. These audit artifacts are the updated documentation; application specs, ADRs and tests are unaffected, and no implementation documentation became stale. Original-PDF coverage and production-comparison scoring were intentionally outside this invocation.
