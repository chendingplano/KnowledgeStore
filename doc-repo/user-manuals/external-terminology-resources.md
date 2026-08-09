# External Terminology Resources — User Manual

**Date:** 2026-08-09  
**Audience:** ChenWeb engineers and operators  
**Scope:** Download, review, and approve external terminology resources (QUDT, UCUM, SIRP, Wikidata, IEC 60050-845) on System Admin → Resources; what Approve actually writes to the database, with QUDT's governed-ontology write path covered in detail  
**Applies to:** ChenWeb `terminologyresourcehandler` (System Admin → Resources → External Terminology Resources / Review External Resources pages)

---

## 1. Purpose

This manual explains what happens, step by step, when an operator downloads, reviews, and approves an external terminology resource through the ChenWeb admin UI — and specifically what changed for the `qudt` resource as of 2026-08-09: approving it now writes governed ontology terms into `kb.ontology_terms` (the `quantity` 4a module), not just the keyword lexicon's staging tables.

This matters because Approve is not a single, uniform action across resources: what it writes, whether it's idempotent, and what you'll actually see in the UI differs by resource and by whether the exact content was approved before. This manual is meant to answer "if I click this button, what happens?" concretely, not just describe the code.

---

## 2. Reference documents

- `ChenWeb/openspec/changes/external-resource-approve-ontology-terms/` — proposal, design, spec, and tasks for the QUDT governed-term write (the change this manual mostly documents)
- `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` — §15.2 (P2 gaps), Appendix B.1/B.2 (ontology content model, 4a modules), 2026/08/09 changelog entry
- `ChenWeb/docs/superpowers/specs/2026-08-07-external-terminology-resource-portfolio-design.md` — the keyword-lexicon staging design (§9.2, §12.3, §13.2) that the Approve flow was originally built around
- `ChenWeb/server/api/terminologyresourcehandler/handler.go`, `qudt_ontology.go` — the actual code
- `ChenWeb/server/cmd/qudt-import/main.go` — the original, never-run-in-production CLI this feature gives an operator-triggered equivalent for

If this manual and code behavior disagree, the code is the source of truth.

---

## 3. The two pages and the three actions

- **External Terminology Resources** — lists the resource catalog (`qudt`, `ucum`, `sirp`, `wikidata`, `iec-60050-845`), lets you trigger a **Download**.
- **Review External Resources** — lists downloaded resources still pending a license/provenance review, lets you **Approve** or **Disapprove**.

**Download** fetches the resource's source artifact (e.g. QUDT's combined `qudt-all.ttl`) to local disk under `TERMINOLOGY_DIR` (or `DATA_HOME_DIR/terminology` as a fallback), and writes a fresh draft manifest with `license_review_status = pending_review`. Downloading again **always** resets the draft manifest back to `pending_review`, even if it had previously been approved — this is the mechanism for re-triggering approval on unchanged or updated content (see §6).

**Approve** does two things for every resource:
1. Flips the local draft manifest to `license_review_status = approved` and records who approved it and when (a local file edit, not a database write). If the manifest is already `approved` or `disapproved`, this step fails closed with an HTTP 409 ("already approved"/"already disapproved") — **Approve is not idempotent by itself; Download is what resets it** (§6).
2. Runs the source's import into the database. This is where behavior now diverges by resource.

**Disapprove** records a rejection on the local manifest. It never imports anything, for any resource.

---

## 4. What Approve writes to the database

### 4.1 All resources — the keyword-lexicon staging import (unchanged)

For every resource, a successful Approve runs `terminology.Runner.Import`, which writes into the keyword lexicon's **immutable staging/evidence layer**:

- `kb.keyword_sources` (source/release governance row — immutable after insert)
- `kb.keyword_source_artifacts`
- `kb.keyword_catalog_entries`, `kb.keyword_catalog_labels`, `kb.keyword_catalog_relations`
- `kb.keyword_catalog_negative_decisions`, `kb.keyword_ucum_codes` (resource-specific)

This layer is **not** governed ontology content — it's provenance-preserving evidence for the Tier-6 keyword-reconciliation validator. As of 2026-08-09 (§4.3 below), Approve *also* auto-promotes this staging data into the actual keyword lexicon in the background — promotion is no longer a separate, human-gated step that Approve merely sets up for later.

If a resource with the same `(source, release)` was already imported with **byte-identical** content, this step is a no-op replay (checksum-matched), not an error. If the content differs from what's already registered under that same release, it fails — changed content under an existing release is an error, never a silent replacement.

### 4.2 QUDT only — the governed ontology-term write (new, 2026-08-09)

For the `qudt` resource specifically, Approve **also**:

1. Parses the same downloaded `qudt-all.ttl` for **all three** QUDT classes — `quantity_kind`, `unit`, and `dimension` (the keyword-lexicon adapter above only ever keeps `quantity_kind`; this is a separate, independent parse of the same file).
2. Batch-inserts any terms not already present into `kb.ontology_terms` (module `quantity`), plus their preferred/symbol labels into `kb.ontology_term_labels` and an exact source-IRI mapping into `kb.ontology_mappings`. This step and the keyword-lexicon import above run in **one shared database transaction** — both commit together or neither does.
3. If the `quantity` module now has any content sitting at `status = 'approved'` (whether from this call or a previous one whose release step failed), creates a new `kb.ontology_module_releases` row and activates it (`kb.ontology_active_releases`), auto-incrementing the patch version (`1.0.0` → `1.0.1` → …). This step runs in its **own** transaction, separate from step 2, because the module/release stores manage their own transactions internally.
4. Re-approving already-registered, unchanged content is idempotent here too: existing terms/labels/mappings are skipped (not duplicated), and if nothing is pending, no new release is created.

**Why this exists:** the `quantity` 4a module has had seed/import code (`cmd/qudt-import`) since 2026-07-31, but nobody had ever run it against a live database — `kb.ontology_terms` had zero `quantity` rows despite the module's real content (the QUDT catalog) already having been fetched and reviewed. Approve is now the operator-triggered equivalent of running that CLI, without needing shell/CLI access.

### 4.3 All resources — keyword-catalog auto-promotion (new, 2026-08-09)

For every resource (not just QUDT), after the keyword-lexicon staging import in §4.1 succeeds, Approve fires a **background** step — it does not block the HTTP response:

1. Checks `kb.keyword_source_promotion_policy` for that resource. No row means enabled; an admin can explicitly disable a specific resource via a toggle on the External Terminology Resources page (`PUT /api/v1/terminology-resources/:source/promotion-policy`).
2. If enabled, walks every non-deprecated `kb.keyword_catalog_entries` row just staged and creates (or converges on, if already present) a `status='provisional'` `kb.keyword_concepts` row per entry, tagged `gloss_source='auto:import:<source>'`, plus a matching `kb.keyword_surfaces` row tagged `provenance='auto:import:<source>'`.

This is deliberately **not** gated by the source's `authority_role` (`exact_identity_authority` vs `proposal_only` etc.) — access to this page is already restricted to System Admin, and that's treated as the authorization. It mirrors the same "autonomous, clearly flagged, optionally human-reviewed" pattern already used by the online document-processing resolve path (which auto-creates a provisional concept tagged `gloss_source='auto:d11'` when it can't confidently resolve a name) — human review via the existing concept-merge endpoint stays available, it's just never required.

**Not part of this step:** anything about *merging* or cleaning up the resulting provisional concepts (deduping against existing concepts, resolving near-duplicates, etc.). That's the keyword-lexicon reconciler's job (`Reconciler.Run`/`ReconcileAmbiguous`), a separate subsystem with its own automation story, out of scope for Approve.

---

## 5. What you will and won't see

**In the UI:** the same "Approved" success state as before, for every resource including `qudt`. The term/label/mapping counts and the new release version are **not** rendered anywhere on the page — this was a deliberate scope decision (see the openspec change's design.md), not an oversight. The §4.3 auto-promotion step is *entirely* invisible in the UI/response — it runs in the background after the response has already been sent, so there is nothing to show even if the page tried to. The only per-resource UI change is the new auto-promote toggle itself (§4.3, point 1); whether promotion actually happened for a given approve has to be checked via SQL:

```sql
SELECT concept_id, pref_label, status, gloss_source, create_time
FROM kb.keyword_concepts
WHERE gloss_source = 'auto:import:qudt'
ORDER BY create_time DESC LIMIT 20;
```

**In the raw API response** (`POST /api/v1/terminology-resources/qudt/approve`), there is now an additional top-level `ontology` object alongside the existing `resource` and `import` fields:

```json
{
  "status": true,
  "resource": { "...": "..." },
  "import": { "ok": true, "result": { "...": "..." } },
  "ontology": {
    "ok": true,
    "terms_inserted": 3968,
    "labels_inserted": 7076,
    "mappings_inserted": 3968,
    "release_version": "1.0.1"
  }
}
```

(Numbers above are real figures from a run against the actual production QUDT 3.5.0 catalog: 1125 `quantity_kind` + 2843 `unit` + 0 `dimension` = 3968 governed terms, out of 4151 total parsed resources — the rest are deprecated entries, which are skipped. The zero `dimension` count is a known, separate finding, not a bug in this feature: the real `qudt-all.ttl` doesn't appear to expose top-level `qudt:DimensionVector`-typed resources the way the parser expects, inherited unchanged from the original `cmd/qudt-import` logic. Worth investigating separately.)

**To confirm what actually happened**, query the database directly:

```sql
-- term counts by kind
SELECT term_kind, status, count(*) FROM kb.ontology_terms WHERE module_id = 'quantity' GROUP BY term_kind, status;

-- active release
SELECT r.version, r.released_at FROM kb.ontology_active_releases ar
JOIN kb.ontology_module_releases r ON r.id = ar.release_id
WHERE ar.module_id = 'quantity' AND ar.deactivated_at IS NULL;
```

---

## 6. Common situations

**"I click Approve and get a 409 / 'already approved' error."**
Expected if the draft manifest was already approved (by anyone, at any time) and hasn't been reset. Click **Download** again first — this always resets the manifest to `pending_review` regardless of prior approval state — then Approve.

**"I re-download and re-approve QUDT, but the keyword-lexicon side did nothing."**
Expected if the re-downloaded content is byte-identical to a previously-registered release (same checksum). The keyword-lexicon import is a no-op replay in that case. The governed-term write (§4.2) is evaluated independently and is **not** skipped just because the keyword-lexicon side was a replay — if `kb.ontology_terms` doesn't yet have the corresponding rows (e.g. this is the first time this feature has run against that database), it will genuinely insert them even though the rest of the response looks like "nothing changed."

**"Approve took much longer than I remember."**
Expected for `qudt` now: parsing ~150K lines of Turtle and batch-inserting ~15,000 rows across three tables, plus a release+activate pass, all synchronously in one HTTP request. Still expected to complete in seconds, not minutes, but it is no longer the near-instant response it used to be for an unchanged-checksum replay.

**"I re-downloaded QUDT and the content actually changed upstream (different checksum) from what's already registered under the same release string."**
The keyword-lexicon import will fail closed (changed content under an existing release is rejected, never silently replaced) — and because the governed-term write shares a transaction with it, the whole Approve call fails and neither side is written. This is intentional: partial writes across the two subsystems are not possible by construction.

**"How do I know if the `quantity` module is actually live/usable yet, versus just present as unreleased rows?"**
Only terms at `status = 'included_in_release'` are visible to downstream consumers (e.g. unit resolution during Phase D). A term sitting at `status = 'approved'` with no active release is written but not yet live — this can happen if the governed-term write succeeded but the release/activate step failed on the same call; the very next Approve of the same resource will pick up and release that stranded content automatically, without re-inserting the terms themselves.
