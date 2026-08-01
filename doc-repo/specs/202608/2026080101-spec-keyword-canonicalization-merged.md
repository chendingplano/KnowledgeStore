# Spec 2026080101 - Keyword Canonicalization: Merged Design (DR16)

- **DocID:** `doc-2026080101`
- **Status:** Accepted — supersedes `doc-2026072301` and `doc-2026072703`
- **Date:** 2026-08-01
- **Component:** SemOS / ChenWeb — keyword lexicon, the DR15 keyword identity family
- **Supersedes:** `2026072301-spec-keyword-canonicalization-reconciliation.md` (File 6), `2026072703-spec-keyword-canonicalization-reconciliation-2.md` (File 7)
- **Authored per:** ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` DR16
- **Implementation status:** Design only. Code lands in P3 behind `KEYWORD_RESOLVER_MODE=observe`; deferred by explicit scope decision on 2026-08-01 (see the P3 implementation log). This document exists so that later work has a single source of truth instead of two disagreeing specs.

## 1. Why this document exists

DR16 found that File 6 and File 7 describe the same module and disagree in ways that matter: identity layering (File 6 has none; File 7 has four layers), storage engine (File 6 assumes Postgres; File 7 recommends SQLite-first), and reconciliation ownership (both specs assume the keyword module owns its own resolver engine; DR15 replaces that with the shared `semid` kernel built in P2). Neither is adopted whole. This document is the one merged design DR16 calls for, written before any keyword-lexicon code is implemented.

## 2. What is taken from each source, verbatim per DR16

**From File 7 (`2026072703`) — the model and the guardrails:**

- the four-layer identity stack — occurrence → surface → lexform → concept — with `lexform` as the working-mode index key (§3.1 here);
- store surfaces, derive keys, version the normalizer; a normalizer change is a re-index, never data loss (§4);
- merges are tombstones (`merged_into`), never deletes (§6.1);
- `never_merge` negative assertions; human-asserted (`locked`) aliases the reconciler may not touch (§6.2, §7);
- no transitive closure over pairwise merge decisions (§6.1);
- `alias_type` drives mechanical validation — an `acronym` is checkable against its target's label, a `misspelling` must be a hidden label, a `translation` must differ in language (§7.3);
- the token-economics discipline: harvest → prune → block → batch → decide → validate → apply, with negative caching so an unchanged item is never re-sent to a model (§7).

**From File 6 (`2026072301`) — the ChenWeb integration:**

- the `kb.` schema and Postgres storage (§3.2, resolving File 7's SQLite-first recommendation in File 6's favor — SemOS already runs `pg_trgm` and `pgvector` and needs one backup/migration story, not two storage engines);
- the mention/observation table, shaped as a first-class evidence queue rather than an optional add-on (§3.3, `kb.keyword_mentions`);
- ambiguity as a first-class stored result, not an error (§5.4, carried from File 6's D4 and File 7's §5.3 — they agree here);
- the seeding strategy (curated lists, artifact backfill, manual import) and the online/reconciliation/candidate metric split (§9).

**Rejected from both, per DR16:**

- File 7's SQLite-first storage recommendation;
- both specs' assumption that the keyword module owns its own reconciliation engine. DR15 replaces this with the shared `semid` kernel (P2, `ChenWeb/server/api/ontology/semid/`): normalize → candidates → score → adjudicate → link → merge/split → audit is built once and instantiated per family. The keyword family supplies only what DR15 requires a `FamilyAdapter` to supply — surface store, node store, normalizer profile, scoring, scope, auto-accept policy — not a second copy of the mechanism.

## 3. Data model

### 3.1 Identity layers

Adopted from File 7 §3.1, unchanged:

```text
occurrence   raw surface as observed, plus where it came from   (optional; folds into kb.keyword_mentions)
   |
surface      one exact distinct string, stored verbatim
   |
lexform      normalization-equivalence class (the working-mode index key)
   |
concept      unit of meaning: canonical label + gloss
```

`surface -> lexform` is many-to-one and computed by the normalizer. `lexform -> concept` is many-to-many — this is where homonyms live (`ML` -> machine learning or millilitre) — disambiguated by scope, and failing that, by context. The `lexform` layer is what makes deterministic O(1) working-mode resolution possible, and it is the layer invalidated by a normalizer-version bump (never by an edit to stored surfaces).

### 3.2 Schema (`kb.keyword_*`, Postgres, File 6's engine choice)

This is the ADR P3 sketch (`2026072901` lines 1136-1149), specified to column level. Table names, column names, and cardinal rules below are binding; exact Go/SQL types are an implementation detail of the P3 build.

```text
kb.keyword_concepts
  concept_id        TEXT PRIMARY KEY      -- opaque, immutable (File 7 §3.2 rule 1); never a slug of the label
  pref_label         TEXT NOT NULL         -- mutable display attribute
  gloss               TEXT                  -- 1-2 sentences; disambiguation + LLM context
  scope               TEXT NOT NULL DEFAULT '_'   -- namespace: knowledge store / domain / '_' = global (DR18 OD9)
  status               TEXT NOT NULL CHECK (status IN ('active','provisional','merged','deprecated'))
  merged_into         TEXT REFERENCES kb.keyword_concepts(concept_id)   -- tombstone pointer (File 7 §3.2 rule 3, §9.1)
  gloss_source        TEXT NOT NULL DEFAULT 'none'  -- human | llm | import | none
  create_time / modify_time

kb.keyword_surfaces
  surface_id          TEXT PRIMARY KEY
  concept_id          TEXT NOT NULL REFERENCES kb.keyword_concepts(concept_id)
  surface              TEXT NOT NULL         -- as written, verbatim (File 7 §3.2 rule 2: derive keys, never store only a key)
  norm_key             TEXT NOT NULL         -- primary normalizer output
  norm_version         INT NOT NULL
  label_role           TEXT NOT NULL CHECK (label_role IN ('pref','alt','hidden'))   -- SKOS roles, File 7 §2
  alias_type           TEXT NOT NULL         -- expansion|acronym|initialism|abbreviation|synonym|near_synonym
                                              -- |misspelling|plural|inflection|translation|legacy|brand|code
  lang                 TEXT NOT NULL DEFAULT 'en'
  scope                TEXT NOT NULL DEFAULT '_'
  confidence           DOUBLE PRECISION NOT NULL
  provenance           TEXT NOT NULL         -- human:<user> | rule:<id> | llm:<model>@<prompt_version> | import:<src>
  locked               BOOLEAN NOT NULL DEFAULT FALSE   -- human-asserted; reconciler may propose but never apply (File 7 §3.2 rule 5)
  evidence              TEXT                  -- snippet/doc ref that justified the surface
  create_time

kb.keyword_surface_keys
  surface_id           TEXT NOT NULL REFERENCES kb.keyword_surfaces(surface_id) ON DELETE CASCADE
  key_kind             TEXT NOT NULL         -- alnum | sorted | phonetic | initials (File 7 §3.3 alias_key)
  key_value            TEXT NOT NULL
  norm_version         INT NOT NULL
  PRIMARY KEY (surface_id, key_kind)

kb.keyword_mentions
  mention_id           BIGSERIAL PRIMARY KEY
  artifact_ref          TEXT                  -- artifact/input-record reference (File 6 mention/observation table)
  chunk_ref              TEXT
  context_text          TEXT                  -- bounded snippet (File 7 §5.5: reservoir sample, capped length)
  ks_id                  TEXT                  -- knowledge-store scope (DR18)
  create_time

kb.keyword_unresolved
  norm_key             TEXT NOT NULL
  scope                 TEXT NOT NULL DEFAULT '_'
  surfaces              JSONB NOT NULL        -- distinct raw forms observed, capped
  contexts              JSONB                 -- reservoir sample of <=5 snippets, <=200 chars each
  hits                   INT NOT NULL DEFAULT 1
  status                 TEXT NOT NULL DEFAULT 'pending'
                                              -- pending|batched|needs_human|resolved|junk|insufficient_context
  attempts               INT NOT NULL DEFAULT 0
  last_attempt           TEXT                  -- '<model>@<prompt_version>' -- negative-caching key (File 7 §7.2)
  priority                DOUBLE PRECISION NOT NULL DEFAULT 0
  first_seen / last_seen
  PRIMARY KEY (norm_key, scope)

kb.keyword_rewrite_rules
  rule_id               TEXT PRIMARY KEY
  pattern                TEXT NOT NULL         -- constrained pattern syntax, never arbitrary LLM-authored regex
  replacement             TEXT NOT NULL
  scope                   TEXT NOT NULL DEFAULT '_'
  enabled                 BOOLEAN NOT NULL DEFAULT FALSE   -- default off; a human enables (File 7 §7.7)
  provenance
  create_time
```

Merge/split audit, never-merge guardrails, and the decision log are **not duplicated** here: the keyword family uses the `semid` kernel's shared tables (`kb.semid_decision_log`, `kb.semid_never_merge`, `kb.semid_snapshots`, built in P2 chunk D), scoped by `family = 'keyword'`. This is the concrete effect of DR15 rejecting "the keyword module owns its own reconciliation engine" — File 7's `decision_log`, `never_merge`, and `snapshot` tables (§3.3) become rows in the kernel's shared tables rather than a second set of keyword-specific tables.

### 3.3 Cardinal rules (File 7 §3.2, binding)

1. `concept_id` is opaque and immutable. The canonical label is a mutable display attribute; the id is the identity.
2. Store surfaces; derive keys. Every normalization key is recomputable from `surface` + `norm_version`, so a normalizer change is a re-index job, not data loss.
3. Merges are tombstones, never deletes. A merged concept keeps its row with `merged_into` set.
4. Everything carries provenance and confidence.
5. Human assertions (`locked = true`) are locked against the reconciler: it may propose changes but never apply them.

## 4. Normalization

Adopted from File 7 §4 without change. The normalizer pipeline (Unicode NFKC, strip zero-width chars, normalize dashes/quotes, collapse whitespace, case-fold while recording a casing signal, collapse dotted initialisms, drop possessive `'s`, then the two explicitly risky policy steps — strip leading articles, exception-list-aware singularization, never a Porter/Snowball stemmer) and the key bundle (`exact`, `norm`, `alnum`, `sorted`, `phonetic`, `initials`) are the DR15 kernel's `Normalizer` for the keyword family — the same `normalize(surface, normalizer_version) -> key bundle` contract the kernel already defines for the ontology-term family (`ChenWeb/server/api/ontology/semid/normalizer.go`), instantiated with the keyword-specific pipeline instead of the term family's simpler one. `norm_version` is the family's `KEYWORD_NORMALIZER_VERSION` (ADR config table); bumping it triggers the kernel's re-index, never data loss.

## 5. Working mode

Adopted from File 7 §5, mapped onto the DR15 kernel's `Kernel.Resolve` flow:

| File 7 tier | Kernel mapping |
|---|---|
| 0 — exact surface hit | exact key match, kernel score 1.0 |
| 1 — `norm` key hit | exact key match on the primary key, kernel score 1.0 |
| 2 — `alnum`/`sorted` key hit | alternate key match, kernel score 0.8 |
| 3 — enabled rewrite rules, retry 0-2 | pre-normalization rewrite pass ahead of `Kernel.Resolve`, keyword-family-specific |
| 4 — `initials` bridge within scope | alternate key match, kernel score 0.8, scope-filtered |
| 5 — fuzzy (trigram block, edit distance) | `CandidateNodes` blocking; kernel `Adjudicate` returns `ambiguous`/`deferred`, never `auto_accepted`, under the guardrails in §5.1 below |
| 6 — ANN over embeddings | same as tier 5: candidate generation only, never auto-accept |
| 7 — miss | kernel returns no candidates; family records `kb.keyword_unresolved` |

Tiers 0-4 are deterministic and O(1); they are what P3 ships behind `KEYWORD_RESOLVER_MODE=observe` (mention collection, backlog population — see §8) before resolution is allowed to affect retrieval. Tiers 5-6 remain candidate-only regardless of resolver mode, consistent with DR15.1's "governed families never auto-accept on similarity alone" pattern already enforced for ontology terms.

### 5.1 Fuzzy-matching guardrails (File 7 §5.2, binding, unchanged)

```text
len <= 4          -> no fuzzy matching at all; exact keys only
5 <= len <= 8      -> max edit distance 1, AND first character must match
len >= 9           -> max edit distance 2, AND normalized similarity >= 0.88
```

Three absolute vetoes applied before any threshold: digit veto (strings differing in any digit never fuzzy-match), canonical veto (a query that is itself an exact `pref_label` never fuzzy-matches elsewhere), and negation/affix veto (`un-`/`non-`/`de-`/`anti-`/`-less` differences never fuzzy-match).

### 5.2 Ambiguity (File 6 D4 + File 7 §5.3 — the two sources agree)

When a key maps to multiple concepts and scope does not disambiguate, the kernel returns `ambiguous`, not a forced pick. This is the same `Verdict` the kernel already returns for the ontology-term family; the keyword family adds context-token disambiguation (File 7 §5.3's IDF-weighted overlap-with-margin heuristic) as a family-specific step before falling back to `ambiguous`.

## 6. Merge, split, and cluster mechanics

Adopted from File 7 §9, delegated to the kernel's existing `MergeGraph` (`ChenWeb/server/api/ontology/semid/merge.go`), which already implements tombstones, refuses self/never-merge/already-merged, and takes no transitive closure (kernel fixtures 19-21, proven in P2). No new merge mechanism is designed here; the keyword family's `Merge`/`Resolve`/`Unmerge` calls are the kernel's, scoped by `family = 'keyword'`.

## 7. Reconciliation mode

Adopted from File 7 §6-§7 (the seven-stage pipeline) with File 6's audit/telemetry shape:

```text
R1 harvest      free extractors (Schwartz-Hearst parenthetical acronym extraction, reverse pattern,
                 definitional patterns) -- zero tokens, resolves what needs no model
R2 prune        drop junk/dedup/frequency-floor; negative-cache anything already marked
                 junk/insufficient_context by the same model@prompt_version
R3 block        lexical (pg_trgm) union semantic (pgvector) blocking to k candidates per unknown --
                 the biggest cost lever; also blocks pending items against each other
R4 assemble     batch clusters into compact (pipe-row, not JSON) prompts; tag unreviewed
                 LLM-sourced glosses in the prompt to avoid self-confirmation
R5 decide       structured output, cheap-model bulk pass, escalate ambiguous/high-blast-radius/
                 high-traffic items to a stronger model
R6 validate     deterministic gates (schema, referential, acronym plausibility via Schwartz-Hearst
                 matching rule, role consistency, never-merge, lock, scope, blast-radius, confidence,
                 digit veto) -- the biggest safety lever, reject before writing
R7 apply+learn  transactional write through the kernel's Merge/link primitives, append to the
                 shared semid_decision_log, promote candidate rules, rebuild snapshot
```

R7's audit record is the kernel's `DecisionLogStore` (shared, not a keyword-specific `decision_log` table, per §3.2 above), and its telemetry follows File 6's online/reconciliation/candidate metric split: coverage and hit rate are working-mode (online) metrics; false-merge rate, backlog burn-down, and human-override rate are reconciliation-mode metrics; blocking recall/precision/reduction-ratio are candidate-generation metrics.

Backlog draining reuses the DR5/DR6/DR7 pattern already built for ambiguous object reconciliation (ADR `2026070701`): a bulk backfill endpoint, a human-review admin page, and an optional confidence-gated LLM adjudication path — not a bespoke queue mechanism.

## 8. `KEYWORD_RESOLVER_MODE` — what `observe` means concretely

Per the ADR config table (`2026072901`), `KEYWORD_RESOLVER_MODE` has three values: `off` (default), `observe`, `on`.

`observe` means:

- the doc-processing mention collector (a new Phase B/C hook, symmetric to the existing facet producers) runs and writes `kb.keyword_mentions` for every artifact-bearing chunk it sees;
- surfaces are derived and written to `kb.keyword_surfaces`/`kb.keyword_surface_keys` when they match an existing concept deterministically (tiers 0-4), but **no resolution result is attached to retrieval, search payloads, or any downstream consumer** — mention/surface/backlog volume is purely measured;
- `kb.keyword_unresolved` accumulates the backlog exactly as it would in `on` mode, so the reconciliation pipeline (§7) can be exercised and evaluated against real volume before any resolution is allowed to affect a live path;
- no `aligns_to_term` assertion (DR15.2, connecting a keyword concept to a governed ontology term) is created or consumed in `observe` mode.

`on` mode is the same pipeline with the gate removed: resolved concepts become available to retrieval and `aligns_to_term` alignment becomes an accepted-assertion consumer (P3's assertion/evidence schema, DR9). The graduation from `observe` to `on` is a config flip, not a code change — this is why `observe` is specified now even though the code that reads it is deferred.

## 9. Seeding strategy (File 6 §"Seeding Strategy", adopted)

Seed sources, each recording provenance so later cleanup is possible:

1. curated keyword lists already present in KnowledgeStore and prompts (`provenance = import:prompt_seed`);
2. existing aliases/acronyms already recorded on entities, metrics, provisions, products, object nodes (`provenance = import:artifact_backfill`);
3. manually curated domain glossaries (`provenance = human:<curator>`).

## 10. DR15.2 — the bridge to governed ontology terms

A keyword concept is an ungoverned canonical *lexical* identity: fast, high-volume, auto-mergeable under the guardrails above, and good enough for search expansion. A governed ontology term (P2) is a reviewed *meaning* with a definition, an owner, and a release. The two are connected by an accepted `aligns_to_term` assertion (P3's assertion schema, DR9) — exactly as an object node connects to its class via `instance_of` — never by merging the keyword concept into the term space. This keeps the fast, high-volume lexicon separate from the slow, governed vocabulary, per DR15.2.

## 11. What is explicitly deferred beyond this document

This spec resolves the design disagreement (DR16's stated purpose). It does not itself implement anything. The P3 implementation log records the actual build boundary; as of this document's authoring, the keyword-lexicon code (kernel `FamilyAdapter` instantiation, the mention collector, the reconciliation pipeline, the admin backlog-drain surfaces) is deferred to a follow-up P3 slice, in favor of the assertion/evidence schema and Phase D association tracks landing first. `KEYWORD_RESOLVER_MODE` stays at its `off` default until that slice ships.

## 12. Documentation Impact

**What knowledge changed?** The two disagreeing keyword-canonicalization specs are superseded by one merged design that adopts the DR15 kernel instead of a bespoke reconciliation engine.

**Which docs/specs/ADRs/tests are affected?** ADR `2026072901` DR16 is now satisfied (its own text should be annotated to point here); the P3 implementation plan and log reference this document as the design source for the keyword-lexicon chunk when it is built.

**Which docs were updated?** This new spec only, plus an ADR DR16 annotation pointing to it.

**Which docs are now stale?** `2026072301-spec-keyword-canonicalization-reconciliation.md` and `2026072703-spec-keyword-canonicalization-reconciliation-2.md` are superseded; they remain on disk as historical inputs (per the workspace convention already used for the research/spec/ADR lineage feeding into `2026072901`) but are no longer independently authoritative.

**What was intentionally left undocumented?** Exact Go package/API signatures, exact migration filenames, and the mention-collector's precise hook point in the doc-processing pipeline — these are implementation decisions for the P3 slice that actually builds this family, not design decisions.
