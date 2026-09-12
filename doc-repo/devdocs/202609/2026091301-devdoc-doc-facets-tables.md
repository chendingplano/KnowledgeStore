# `kb.doc_facets` and `kb.doc_facet_values` — Schema and Generation Mechanics

**Date:** 2026-09-13 \
**Scope:** What these two tables are for, their exact schema, and — the part not obvious
from the schema alone — which code paths write to them and when, across the three-tier
"cheapest-first" facet classifier (ADR 2026072901 S3.5 DR4, S16.1 "Facet tiers 1-2"; tier-3
routing spec 2026080102). 

**Code root:** `ChenWeb/server/api/doc-processing/`

**Update, later the same day (2026-09-13):** this doc originally documented that tier-3
(`classify_document`) could never fire under the currently active policy (see §2 Tier 3
below for that evidence — it's still true as a description of the policy). On review, that
was judged a product bug even though no line of code was incorrect: a fully built, tested,
LLM-backed feature that can never be invoked is dead weight, not a working "safety" behavior.
**Fixed the same day**: `classify_document` now runs by default for every document,
independent of whether any routing predicate needs its answers, with a new
`CLASSIFY_DOCUMENT_ENABLED` env var (default `true`) as a full kill switch. §2 Tier 3 below
now documents the fixed behavior; the original "why it never fired" evidence is kept as
historical context for why the fix was needed.

## 1. `kb.doc_facets` — one row per document, current-state snapshot

Migration: `project_migrations/20260731000007_create_kb_doc_facets.sql`.

```sql
CREATE TABLE kb.doc_facets (
    record_id BIGINT PRIMARY KEY REFERENCES kb.inputs(id) ON DELETE CASCADE,
    ks_store_id BIGINT NOT NULL DEFAULT 0,
    knowledge_store_binding VARCHAR(32) NOT NULL DEFAULT 'absent',
    input_doc_type VARCHAR(128) NOT NULL DEFAULT '',
    source_language VARCHAR(32) NOT NULL DEFAULT '',
    has_document_number BOOLEAN NOT NULL DEFAULT false,
    create_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    modify_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

`record_id` is the primary key — this is **not** an observation log, it's the current
routing-facts snapshot for the document, upserted in place every time it's recomputed.

**Writer:** `ControlService.persistDocFacets` (`control.go:1412`), called once from
`ControlService.handleEvent` (`control.go:675`) via:

```go
INSERT INTO kb.doc_facets (record_id, ks_store_id, knowledge_store_binding,
                           input_doc_type, source_language, has_document_number)
VALUES (...)
ON CONFLICT (record_id) DO UPDATE SET ... , modify_time = NOW()
```

**Trigger:** `handleEvent` runs on every `LineFileGeneratedEvent` the control service
receives for a record, regardless of which processors were requested in that event's
`operations` list. It calls `resolveProductionPlanFacts` to compute routing facts
(knowledge-store binding, doc type, source language, document-number presence — the same
facts `BuildProductionProcessorPlanFromFacts` uses to pick which processors actually run),
then immediately persists that snapshot. **No processor writes this table directly** — it's
a side effect of the control plane resolving the plan for the event, upstream of dispatching
any of `static_analyzer` / `chunking` / `extract_doc_metadata` / `extract_metrics` /
`extract_products`.

`handleEvent` is called when the doc processor service receives a JetStream event.
There are two sources to generate the event:
- Users use the Doc Process page (currently: `/development, Dashboard => Doc Processor`)
- Automatically triggered when a new doc is added to the staging directory

## 2. `kb.doc_facet_values` — append-only observation log, many rows per document

Migration: `project_migrations/20260801000016_create_kb_doc_facet_values.sql` (FK on
`vocabulary_release_id` dropped by `20260811000004`).

```sql
CREATE TABLE kb.doc_facet_values (
    id BIGSERIAL PRIMARY KEY,
    record_id BIGINT NOT NULL REFERENCES kb.inputs(id) ON DELETE CASCADE,
    path TEXT NOT NULL,                    -- e.g. "document.page_count"
    value JSONB,
    state TEXT NOT NULL DEFAULT 'known'
        CHECK (state IN ('known', 'missing', 'conflicting', 'invalid')),
    method TEXT NOT NULL
        CHECK (method IN ('deterministic', 'metadata', 'classifier')),
    confidence DOUBLE PRECISION,
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    source_fingerprint TEXT NOT NULL DEFAULT '',
    decision_attempt_id TEXT NOT NULL DEFAULT '',
    invocation_id TEXT NOT NULL DEFAULT '',
    vocabulary_release_id BIGINT NOT NULL DEFAULT 0,
    create_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    modify_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (record_id, path, decision_attempt_id, invocation_id)
);
```

`method` is exactly the three tiers (`applicability_facts.go`:
`FacetMethodDeterministic = "deterministic"`, `FacetMethodMetadata = "metadata"`,
`FacetMethodClassifier = "classifier"`). The unique key is `(record_id, path,
decision_attempt_id, invocation_id)`, and every insert is `ON CONFLICT DO NOTHING` — a
retried attempt with the same attempt/invocation id is a no-op, but a genuinely new attempt
adds a new row rather than overwriting history. This table is a log, not a snapshot.

### What is a "fact" / a `document.xxx` path? (plain English, applies to all 3 tiers)

**`document` is not a database table.** Each row in `kb.doc_facet_values` records the answer
to one specific yes/no-or-multiple-choice **question about a single document** — "how many
pages does it have?", "does it use mandatory language like 'shall'/'must'?", "what kind of
document is this?". The system's internal name for "a question about a document" is a
**path**, always written `document.<something>`, e.g. `document.page_count` or
`document.doc_kind`. Think of it as a form field name, not a table or a column in a table —
`document` here just means "this is a property of the document," the same way you might
label a form field "Applicant.Age" without there being an "Applicant" table anywhere.

So a row like `(record_id=362, path='document.page_count', value=42)` reads as: *"For
document #362, the answer to 'how many pages?' is 42."* The three tiers below are three
different, increasingly expensive ways the system can come up with an answer to one of
these questions — the value is the same kind of thing regardless of which tier answered it,
only `method` records which one did.

### Tier 1 — cheap, automatic, look-and-count (`method = 'deterministic'`)

**In plain English:** the system skims the document's already-extracted text and counts
things — how many pages, whether it has a table of contents, how often it uses words like
"shall"/"must"/必须, how many figures/tables it has, and so on. No AI model is involved —
it's pattern-matching, like a spell-checker. It's free and instantaneous, so it always runs,
for every document, with no configuration needed.

- **Code:** `ComputeTier1Facets` / `tier1FacetsFromLines` (`facet_tier1.go`).
- **Paths produced:** `document.page_count`, `document.toc_presence`,
  `document.heading_count`, `document.table_line_ratio`, `document.numeric_unit_density`,
  `document.modal_verb_density`, `document.figure_density`, `document.language_mix`.
- **Input:** the line file already written to disk — regex/heuristics only (numeric+unit
  patterns, `shall`/`must`/应/必须 modal verbs, figure/table caption lines). No
  `doc_metadata`, no LLM.
- **Trigger:** inline in `ControlService.handleEvent` (`control.go:699`), immediately after
  `persistDocFacets`. Runs unconditionally as long as `s.Facets != nil`, **gated only** by an
  optional `kb.pipeline_rules` row (`target_processor = "facet_tier1"`, effect `skip`) — a
  gate-resolution error fails **open** (runs anyway) rather than silently dropping facets.
  It needs the line file `static_analyzer` produces, but `static_analyzer` does not call this
  code — the control service does, as part of handling the same event that carries
  `static_analyzer` in its operations list.
- **Where `facet_tier1` is "defined":** it's listed, by name, in one hard-coded table inside
  the application's own source code — `productionProcessorSpecs` in `processor_plan.go:480`.
  This isn't a setting a person edits at runtime; it's part of the compiled program, the same
  way `static_analyzer` or `extract_metrics` are. Being listed there just registers the name
  and its default ("run unless a database rule says otherwise") — it doesn't by itself
  schedule the code to run; the actual call happens in `control.go` as described above.

### Tier 2 — cheap, automatic, reuse-what-we-already-know (`method = 'metadata'`)

**In plain English:** `extract_doc_metadata` already asks an AI model to read the document
and pull out its title, document number, and publish date (that's its own job, unrelated to
these two tables). Tier 2 is just a few extra lines of free bookkeeping tacked onto the end
of that same step: it looks at the document number and publish date `extract_doc_metadata`
already found, and derives two more answers from them — no second AI call.

- **Code:** `ComputeTier2Facets` / `tier2FacetsFromSource` (`facet_tier2.go`).
- **Paths produced:** `document.publish_date` (passthrough of the extracted publish date),
  `document.authority_hint` (regex over the extracted document-number prefix: `gb`, `iso`,
  `iec`, `ansi`, `astm`).
- **Trigger:** **this is the one tier genuinely owned by a named processor.**
  `ExtractDocMetadataProcessor.HandleEvent` (`extract-doc-metadata.go:260`) calls it directly,
  right after its own LLM call extracts title/doc_no/publish_date and
  `UpdateInputMetadata` commits them to `kb.inputs` — no new LLM call, it's free
  post-processing of output `extract_doc_metadata` already paid for. Also individually
  gate-able via `kb.pipeline_rules` (`target_processor = "facet_tier2"`).
- **Where `facet_tier2` is "defined":** same place as `facet_tier1` — a hard-coded entry
  named `facet_tier2` in `productionProcessorSpecs`, `processor_plan.go:481`.

### Tier 3 — ask an AI model, only as a last resort (`method = 'classifier'`)

#### Plain-English summary — read this first

Tier 3 answers four specific questions about a document that tiers 1 and 2 *can't* answer,
because answering them requires actually understanding what the document is about, not just
counting words or reusing an already-extracted number. The four questions, and their only
allowed answers, are:

| Question (path) | Allowed answers |
|---|---|
| What kind of document is this? (`document.doc_kind`) | product specification, regulated reference (a standard/regulation), narrative research, or test report |
| What industry/domain is it about? (`document.domain`) | medical devices, pharmaceuticals, or industrial equipment |
| How mandatory is it? (`document.normative_status`) | mandatory, recommended, or informative |
| Which jurisdiction does it belong to? (`document.jurisdiction`) | China, US, EU, or ISO (international) |

It's multiple choice, not free text — the AI is told the exact list of allowed answers for
each question and is not allowed to invent a new one.

**When does the system actually ask these questions? (fixed 2026-09-13)** Originally, tier-3
questions were asked only when some other part of the system's configuration — a **routing
rule** — said, in effect, *"I can't decide what to do with this document until I know its
`doc_kind`."* If no routing rule ever needed one of the four answers, the system had no
reason to ask, so it never called the AI model, and no row was ever written. That was
in fact the situation for every document in this project: no routing rule of that shape had
ever been authored (see "Historical evidence" below), so the AI classifier — fully built,
tested, and turned on — never had a reason to run, for *any* document.

**Is this a bug?** Not a coding bug — the classification code itself worked correctly (it has
its own passing test suite) and the AI model it needs was already configured (see "What is
`s.Resolver`?" below). But something the team built and considers important could never
actually run, for any document, ever, by construction — that's a product/config bug even
though no line of code was wrong. **Fixed 2026-09-13**: tier-3 now runs by default, described
below.

**The fix — tier 3 now runs by default.** `classify_document` no longer waits for a routing
rule to ask for its answers. For every document, it now checks which of the four governed
questions don't have an answer yet and asks the AI model about all of them, in one call —
regardless of whether any routing rule currently cares. A routing rule that *does* reference
one of these facts still works exactly as before and doesn't cause a second, redundant call.
To turn this off, set the environment variable **`CLASSIFY_DOCUMENT_ENABLED=false`** — that
disables tier-3 entirely for document processing (a full stop, including the old
routing-rule-triggered path), leaving the previous "never runs" state as an explicit,
deliberate choice rather than an accidental one. Leaving it unset, or setting it to `true`,
keeps the new default-on behavior.

**What is `s.Resolver`?** It's an internal object the server builds once when it starts up —
not a table, not an env var by itself, and not literally hardcoded either. At startup, the
server tries to build the tier-3 **classifier** — the piece of code that actually knows how
to call the AI model and validate its answer (see "What is the classifier, and what can make
it fail to build?" below). If that succeeds, `s.Resolver` holds the working classifier; if it
fails, `s.Resolver` is left empty and tier-3 is disabled outright, everywhere, for the whole
server, no matter what routing rules exist or what `CLASSIFY_DOCUMENT_ENABLED` says. Whether
it succeeds depends on two settings in this project's local config (`mise.local.toml`):
`CLASSIFY_DOCUMENT_MODEL_NAME` (which AI model to use — currently set to
`deepseek-flash-chen`) and `MODEL_DEF_FILE` (a file listing what that model name means —
currently `.models.toml`). **Both are set in this environment**, so under normal
circumstances the classifier should build successfully and `s.Resolver` should never be nil
here — which is exactly why, as of this fix, a failure to build it is now logged as an
**Error** (previously a Warning) at server startup: if you ever see that error in this
environment, something is actually broken (a bad model name, a missing/malformed
`.models.toml`, etc. — see below), not an expected/tolerated state.

**What is "the classifier," and what can make it fail to build?** "The classifier" just means
the piece of Go code (`DocumentClassifier`) that holds everything needed to make one of these
AI calls: which AI service/model to talk to, the API key, the prompt text, and the closed
list of allowed answers per question. Building it means reading configuration and doing some
file I/O, any of which can fail:

1. `CLASSIFY_DOCUMENT_MODEL_NAME` isn't set at all.
2. `MODEL_DEF_FILE` isn't set, or points to a file that doesn't exist.
3. That file (`.models.toml` in this environment) can't be read (permissions, etc.) or isn't
   valid TOML.
4. The model name (`deepseek-flash-chen`) isn't actually listed as an entry in that file.
5. That entry is listed but is missing its own model name field internally.

None of these are expected to happen in this environment right now, since both settings are
already correctly in place — which is exactly why a failure here now logs loudly (previous
paragraph) instead of quietly.

#### Technical detail (for readers who want to check the code)

- **Code:** `DocumentClassifier.Classify` (`classify-document.go:152`), invoked by
  `ApplicabilityResolver.Resolve` (`applicability_resolver.go:183`).
- **Governed paths:** `document.doc_kind`, `document.domain`, `document.normative_status`,
  `document.jurisdiction` (`DefaultGovernedVocabulary`, `classify-document.go:485`) — a
  fixed, closed vocabulary per path; the classifier never returns a value outside it.
- **Trigger (as of the 2026-09-13 fix):** also inline in `ControlService.handleEvent`
  (`control.go:723`, via `Resolver.ResolveExtractionFacts`), **not** a named processor in any
  operations list. `ResolveExtractionFacts` (`applicability_resolver.go:448`) now:
  1. short-circuits with no resolver call at all if `!ClassifyDocumentEnabledFromEnv()`
     (`CLASSIFY_DOCUMENT_ENABLED=false`) — a full kill switch;
  2. otherwise builds `ResolverRequest.AlwaysClassifyPaths` from `unresolvedTier3Paths(baseFacts)`
     — every `Tier3Paths()` entry not already `FactKnown` — **and** still passes
     `activeRoutingPredicates()` as `Predicates`;
  3. inside `Resolve`, `missing := unionTier3Paths(decisionRelevantTier3Paths(pass1),
     req.AlwaysClassifyPaths)` — the union of "a predicate needs it" and "it's simply
     unanswered" now decides what gets classified, so it always includes at least the four
     governed paths (`AlwaysClassifyPaths`) unless every one of them is already known;
  4. `s.Resolver != nil` still required (a classifier must have built successfully at
     startup);
  5. an authored `kb.pipeline_rules` row can still gate `classify_document` off for a
     specific document/scope (`target_processor = "classify_document"`) even when the env
     var is on — the env var is the global switch, the DB gate is the per-document override.
- `ResolveReviewFacts` (the separate review-profile-selection entry point, spec 2026080102
  section 7) is **unaffected** by this fix — it leaves `AlwaysClassifyPaths` unset and keeps
  the original predicate-only behavior, since the "run by default" request was specifically
  about extraction-time facet population (this doc's subject), not review-scope selection.
- **Stable retry:** before calling the LLM, it checks `ListFacetObservations` for an existing
  row with the same `invocation_id` and `method = 'classifier'` and short-circuits if found —
  so re-running the same attempt never double-calls the model.
- **Failure handling:** an LLM/parse failure returns `Failed: true` with no rows written —
  "preserve indeterminate, don't overwrite prior known facts" (spec section 11). A
  well-formed response that legitimately classifies nothing (`{"classifications": []}`) is
  *not* treated as failure and still reaches persistence (there's just nothing to persist).
- **Where `classify_document` is "defined":** same mechanism as `facet_tier1`/`facet_tier2` —
  a hard-coded entry in `productionProcessorSpecs`, `processor_plan.go:497`.
- **Where `s.Resolver` is built:** `buildProductionResolver` (`runtime.go:105`), called once
  when the server starts. It calls `newProductionDocumentClassifier`
  (`classify-document.go:512` → `loadModelConfigFromEnvKeys`/`loadModelConfigByRef`,
  `extract-products.go:2162`), which reads `CLASSIFY_DOCUMENT_MODEL_NAME` and
  `MODEL_DEF_FILE` to construct the AI client; on any error it now logs at **Error** level
  (was Warn) and returns `nil` (still nil-safe / graceful-degrade, not a startup failure) —
  that `nil`/non-`nil` result becomes `ControlService.Resolver`. See "What is 'the
  classifier'..." above for the concrete list of what can make this fail.
- **New env var:** `ClassifyDocumentEnabledFromEnv` (`classify-document.go`, reads
  `CLASSIFY_DOCUMENT_ENABLED`, default `true`) — same unset-or-unparseable-means-true
  convention as `SemanticAssociationEnabledFromEnv` (`phase_d.go`, Phase D's own on-by-default
  switch).

#### Historical evidence: why it never fired before this fix

`decisionRelevantTier3Paths(pass1)` (`applicability_resolver.go:253`) is built from evaluating
`activeRoutingPredicates()` (`applicability_resolver.go:304`) against the known facts.
`activeRoutingPredicates()` collects exactly two sources, both read from an in-process cache
loaded at startup from the DB (not re-queried per event):

- each **active `conditional`** row in `kb.pipeline_bindings` (`binding_kind = 'conditional'`)
  that has a non-empty predicate — a `store_default` binding is skipped even if `active`;
- every **active** row in `kb.pipeline_rules` whose `predicate` is non-empty (no filtering by
  `effect` — `require`/`enable`/`skip` gates are all included the same way).

Each collected predicate is evaluated (`semrules.EvaluateDocumentValidated`) against the
merged tier-1+2 fact set. A predicate only contributes to `DecisionRelevantMissingPaths` if
its truth value actually *depends* on a fact that's still unknown — an `"all"` node with zero
`items` evaluates to a vacuous `TruthTrue` with **no** missing paths at all
(`semrules/evaluate.go:124-127`), i.e. a predicate that references no fact can never make any
path decision-relevant, tier-3 or otherwise. In everyday terms: a routing rule that says
"always do X, no conditions" never needs to ask any question, so it can never be the reason
tier 3 gets invoked.

**Checked directly against the dev DB (`miner`) on 2026-09-13** — this is why records 362,
373, 386, 395 have zero tier-3 rows:

```
kb.pipeline_bindings, active = true:
  id=5 "system-default"    binding_kind='store_default'  predicate=NULL
  id=6 "store:Research"    binding_kind='store_default'  predicate=NULL
  -- both store_default -> activeRoutingPredicates() contributes 0 binding predicates

kb.pipeline_rules, active = true:
  14 rows, all named "all: <processor>" / "no-entities-relations: <processor>"
  (extract_entity, extract_inventory_items, extract_metrics, extract_provisions,
  extract_relation, extract_semantic_projections, generate_scene_blocks, generate_topics)
  every predicate = {"version":1,"expression":{"kind":"all"}}  -- no "items", i.e. empty AND
```

These 14 gate rows are exactly the unconditional per-processor "require" rows
`SeedDocProcessingPolicies` auto-writes (migration `20260809000001`, see
`user-manuals/database-tables.md`'s `kb.pipeline_rules` entry) — they gate *whether a
processor runs at all*, not *what kind of document this is*, so their predicate is
authored as an always-true empty `all`, referencing no fact whatsoever.

**Conclusion (historical — this was the bug, now fixed):** under the policy active on
2026-09-13, no binding or gate predicate anywhere referenced `document.doc_kind`,
`document.domain`, `document.normative_status`, or `document.jurisdiction`. `evaluateAll`
therefore returned 14 trivially-true results with empty `DecisionRelevantMissingPaths` on
every single document, `decisionRelevantTier3Paths` was always `[]`, and
`classify_document`/tier-3 **never fired for any document, in any environment with this same
policy shape** — not because tier-1/2 already answered its questions, and not because a
`kb.pipeline_rules` gate skipped it, but because nothing in the active policy ever asked a
question only tier-3 could answer, and (before the fix) nothing else did either. This
`decisionRelevantTier3Paths` mechanism is **not removed** — a conditional binding or gate
predicate that references one of those four paths still works and still contributes to what
gets classified — it's just no longer the *only* thing that can trigger tier-3, now that
`ResolveExtractionFacts` also unions in every still-unresolved governed path by default (see
"The fix" above).

## 3. Handle Event

Inside `handleEvent`:

1. resolves + persists (i.e., upsert) the `kb.doc_facets` routing snapshot,
2. computes and inserts tier-1 facets from the line file,
3. runs pipeline/gate predicate evaluation against those facts, then (as of the 2026-09-13
   fix) calls the tier-3 classifier for every still-unresolved governed path by default —
   unless `CLASSIFY_DOCUMENT_ENABLED=false` — inserting `method = 'classifier'` rows. See
   "The fix — tier 3 now runs by default" under §2 Tier 3 above for exactly how.

`extract_doc_metadata` separately adds its own `method = 'metadata'` rows as a side effect
of its normal run.

**Net effect:** `kb.doc_facet_values` rows for a document can come from control-plane code
that ran, not only from the processors named in the request — and as of this fix, tier-3
rows now appear for every processed document by default, not only when an authored
binding/gate predicate happens to reference one of the four tier-3 governed paths.

## 4. Tier-3 prompt

`LoadClassifyDocumentPrompt` (`classify-document.go:456`) loads
`ChenWeb/prompts/prompt-classify-document-v1.md` — never embedded in Go, per spec section 7.
As of 2026-09-13 the ref is overridable via **`CLASSIFY_DOCUMENT_PROMPT`** (previously
hard-coded; fixed to match the existing pattern used by `EXTRACT_DOCMETA_PROMPT`,
`RESOLVE_AMBIGUOUS_OBJECT_PROMPT`, etc.):

```go
func LoadClassifyDocumentPrompt() (promptText, promptRef, promptPath string, err error) {
	ref := strings.TrimSpace(os.Getenv("CLASSIFY_DOCUMENT_PROMPT"))
	if ref == "" {
		ref = defaultClassifyDocumentPromptRef // "prompt-classify-document-v1.md"
	}
	return loadPromptByRef(ref)
}
```

`loadPromptByRef` resolves a relative ref by searching (first match wins): the literal ref
relative to CWD, `$PROMPT_DIR/<ref>`, `server/cmd/doc-processor/<ref>`,
`server/cmd/doc-processor/prompts/<ref>`, then `prompts/<ref>` — the same search order every
other prompt loader in this package uses.

## 5. Known stale documentation

`KnowledgeStore/doc-repo/user-manuals/database-tables.md` (§ pipeline tables) currently
describes `kb.doc_facets` with a `facet_key`/`facet_value`/`value_kind`/`policy_version`/
`run_id` shape and says tiers 1–2 of `kb.doc_facet_values` are "unwired" — both are stale
against the schema and code as of this writing: `kb.doc_facets` has the flat
routing-snapshot shape in §1 above, and tiers 1–2 are wired and writing rows (§2). Not
corrected here since fixing that reference table is out of scope for this note; flagging so
it isn't relied on for this pair of tables.
