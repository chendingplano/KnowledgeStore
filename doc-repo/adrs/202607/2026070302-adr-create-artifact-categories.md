# ADR 2026070302 - Create Artifact Categories With Optional Non-LLM Mode

**Date:** 2026-07-03 \
**Status:** Proposal \ 
**Component:** ChenWeb \
**Authors**: Chen Ding \

## Change Logs
* 2026/07/03, ADR Created

## Context

Artifact category creation currently supports creating a missing category by
calling an LLM. That path is useful because it can canonicalize keys, translate
non-English names, propose aliases, and produce richer metadata such as
descriptions and keywords.

However, category creation may happen frequently across batch document
processing. When many new category keys appear, LLM-backed creation adds direct
model cost, latency, and operational dependence on model availability.

This ADR records a two-mode design:

1. `CREATE_CATEGORY_MODE = 'use-llm'`
   - Use the current LLM-backed category creation path.
2. Any other value, or unset
   - Do **not** use LLM calls.
   - Default mode is `not-use-llm`.

The implementation is in
`ChenWeb/server/api/doc-processing/artifact_category_wiring.go`.

## Problems

### Problem 01: Cost of LLM-backed category creation

Using an LLM for every novel category key costs money. This is the primary
reason to support a non-LLM mode.

The cost issue is amplified by:

- high-volume document ingestion;
- many first-seen category keys in one run;
- repeated processing across environments;
- occasional low-value categories that do not justify an LLM call.

### Problem 02: Operational dependence on LLM availability

When category creation requires an LLM, the pipeline depends on prompt files,
model configuration, network access, and model endpoint availability. If any of
those fail, category creation may fail.

### Problem 03: Chinese and multilingual category keys still need to work

If LLM creation is disabled, category creation still needs deterministic behavior
for Chinese keys and other non-English names. We must define what "works"
means without translation or semantic expansion.

## Decision

### DR1: Support two category creation modes

Artifact category creation supports two modes controlled by
`CREATE_CATEGORY_MODE`.

- `use-llm`
  - Use the existing `llmCategoryCreator`.
- default / anything else
  - Use `deterministicCategoryCreator`.
  - No LLM calls are made.

The default is `not-use-llm`.

### DR2: In non-LLM mode, create the category from the normalized raw key

In non-LLM mode, a new category is created deterministically from the raw input
key:

- `category_key` = `normalizeCategoryKey(rawKey)`
- `display_names` includes the original trimmed raw key
- no LLM-generated aliases, acronyms, keywords, description, related categories,
  or parent categories are added

This mirrors the object-node philosophy from ADR 2026070101: creation must work
from deterministic source data alone, without depending on an LLM for
correctness.

### DR3: Chinese category names are stored and matched as first-class keys, not translated

When not using an LLM, Chinese category names are **not** translated to English.

Instead:

- the original Chinese surface form is preserved in `display_names`;
- the normalized Chinese key becomes the `category_key`;
- matching relies on deterministic normalization and alias absorption;
- later occurrences of the same Chinese key resolve directly through
  `match_keys`.

Example:

```text
rawKey: 调制解调器
category_key: 调制解调器
display_names: ["调制解调器"]
```

This means Chinese categories still work operationally:

- they can be created;
- they can be looked up again;
- they can participate in `match_keys`, `category_instance`, and graph edges.

But they are **not** automatically canonicalized into English in non-LLM mode.

### DR4: Aliases in non-LLM mode are learned operationally, not inferred semantically

In non-LLM mode, aliases are not invented at create time. Instead, aliases are
learned through the existing resolution flow:

- if a later key resolves to an existing category,
  `artifactCategoryRegistry.absorbAlias(...)` adds that normalized key into
  `match_keys`;
- the process-wide index then resolves that alias deterministically next time.

This produces an operational alias set over time, based on observed usage, not
on LLM inference.

### DR5: Logging must happen in both modes

Creating a new artifact category must emit the same create start/end logs in
both modes.

This ensures observability regardless of whether the category came from:

- an LLM-backed create, or
- a deterministic non-LLM create.

The current implementation logs:

- `Create Category start`
- `Create Category end`

In `use-llm` mode, the create log includes `mode=use-llm` and `modelName`.
In non-LLM mode, the create log includes `mode=not-use-llm`.

## Consequences

### Positive Consequences

- category creation no longer requires an LLM by default;
- processing cost is reduced, especially for ingestion-heavy workloads;
- creation remains available even if prompt/model configuration is absent;
- behavior is deterministic and easier to reason about in tests and operations;
- Chinese category names continue to work as stored lexical keys.

### Negative Consequences

- no automatic translation of Chinese category names to English;
- no semantic alias generation at create time;
- no LLM-authored descriptions, keywords, related categories, or parent
  categories in non-LLM mode;
- category quality may be less curated and less normalized across languages;
- duplicate concepts across languages may remain separate until explicit alias
  absorption or later review merges them.

### Important Clarification on Chinese Keys

Without LLM creation:

- `压力` and `pressure` are treated as different keys unless the system later
  observes one resolving to the other and absorbs it as an alias, or a human
  review process merges them.
- Therefore, Chinese handling is **lexical continuity**, not **semantic
  translation**.

This is the central tradeoff of the non-LLM mode.

## Operational Behaviors

### Non-LLM creation flow

When a normalized key misses the category index:

1. `deterministicCategoryCreator.CreateCategory(...)` is called.
2. It normalizes the raw key.
3. It returns a minimal `createdCategory`.
4. `mintCategory(...)` persists the row.
5. The canonical key and original key are inserted into the in-memory index.
6. `absorbAlias(...)` keeps the DB `match_keys` aligned.

### Chinese handling flow

For a Chinese key:

1. the raw Chinese text is normalized;
2. the normalized Chinese text becomes the category key;
3. the original Chinese text is retained in `display_names`;
4. subsequent occurrences hit exact/alias lookup directly.

This ensures stable lookup behavior even though no translation occurs.

### Alias handling flow

Aliases come from observed successful resolutions:

- exact key hit;
- previously absorbed alternate form;
- future human review / merge workflows.

They do **not** come from LLM expansion in non-LLM mode.

## Alternative Decisions

### AD1: Always require the LLM

Rejected. This preserves the richest metadata, but it keeps the cost and
availability dependency that this ADR is specifically trying to reduce.

### AD2: Disable category creation entirely when LLM is unavailable

Rejected. That would make ingestion fragile and would turn category creation
into an infrastructure dependency rather than a deterministic data operation.

### AD3: Add a built-in machine translation step for Chinese keys

Rejected for now. It would reduce some multilingual fragmentation, but it adds
another external dependency and another source of non-deterministic
normalization. The current ADR chooses lower cost and operational simplicity.

## Environment Variables

- `CREATE_CATEGORY_MODE`
  - `use-llm` => use LLM-backed creation
  - unset or any other value => non-LLM deterministic creation
  - default behavior is `not-use-llm`

## Implementation

### Code Changes

- `ChenWeb/server/api/doc-processing/artifact_category_wiring.go`
  - add `createCategoryMode()`
  - default mode to `not-use-llm`
  - wire `newMetricCategoryResolver(...)` to choose between
    `llmCategoryCreator` and `deterministicCategoryCreator`
  - ensure create logs are emitted in both modes

### Tests

- `ChenWeb/server/api/doc-processing/artifact_category_resolver_test.go`
  - verify default resolver behavior creates categories without LLM mode config
- `ChenWeb/server/api/doc-processing/artifact_category_wiring_test.go`
  - verify deterministic creator normalizes and logs
  - preserve existing LLM logging coverage

## Documentation Impact

### What knowledge changed?

Artifact category creation is no longer implicitly "LLM-only". It now has a
deterministic default mode.

### Which docs/specs/ADRs/tests are affected?

- This ADR
- category creation tests in `ChenWeb/server/api/doc-processing`

### Which docs were updated?

- `KnowledgeStore/doc-repo/adrs/202607/2026070302-adr-create-artifact-categories.md`

### Which docs are now stale?

- Any document that assumes artifact category creation always requires an LLM is
  now stale.

### What was intentionally left undocumented?

- No new review-side merge workflow for cross-language category unification is
  defined here.
- No automatic Chinese-to-English translation strategy is introduced here.

## References

- `ChenWeb/server/api/doc-processing/artifact_category_wiring.go`
- `ChenWeb/server/api/doc-processing/artifact_category_resolver.go`
- `ChenWeb/server/api/doc-processing/artifact_category_registry.go`
- `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
- `KnowledgeStore/doc-repo/adrs/202606/2026061502-adr-artifact-categories.md`
