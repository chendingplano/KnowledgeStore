# ADR: Artifact Categories

**Date:** 2026-06-15 \
**Status:** Proposal \ 
**Component:** ChenWeb \
**Authors**: Chen Ding \
**Tags**: deep wiki, search result wiki page \

## Change Logs
* 2026/06/15, ADR Created
* 2026/06/15, Change 01 updated after first cross-artifact rollout wave beyond metrics

## Change 01
Date: 2026/06/15 \
Type: new feature \
Status: active

In ChenWeb 'localhost:8080/deep-wiki', when users enter a query and clicks the "Search"
button, it shows the search results in 'localhost:8080/home3/knowledge?section=kb-search'.
Clicking an entry will open its wiki page 'home3/knowledge?section=kb-metric-wiki'.

There are two problems. First, this works only when the entry is a metric (`kb.metrics`).
Second, the page (Search Result Detail Page, or Wiki Page) is identified (I believe) 
by the metric's `kb.metrics.input_record_id`
and the page is saved in the corresponding directory in `ARTIFACTS` directory.
Also, the wiki page is lazy created.

Here is the proposed change:
1. Wiki pages are still created upon request
2. Wiki pages layout has two panels (refer to the current implementation):
   (1) Left Panel: an HTML page created by LLM dynamically, and (2) Right 
   Panel: shows the record.
3. The wiki page language is specified in the search page. If the page 
   exists, but not in the right language, use LLM to translate it,
   save it, and then show it.
   This should apply not just to metrics but to all searchable artifacts.
4. Right Panel needs to show all the fields (currently, it only shows few of them)
5. When the page does not exist, it uses LLM to create Left Panel, which can
   be slow, but should show Right Panel instantly.

Work on metrics first. After testing and being green, apply the fix to all 
other artifacts.

### Context
- The current search results page deep-links only metric results to a wiki page.
  Other artifact types route users back to search instead of opening a detail page.
- The current wiki implementation is metric-specific in both route shape and
  backend contract.
- Search results already use `artifact_type` + `artifact_id` as the cross-artifact
  identity in `kb.search_artifacts`, so this pair can serve as the generic wiki
  page identity.
- The current metric wiki cache is language-specific and lazy-created. That
  behavior should be preserved while generalizing it to all searchable artifacts.
- The new page must prioritize fast grounded inspection: the artifact record
  should appear immediately even when LLM article generation or translation is slow.

### Alternative Decisions
- **Chosen**: introduce one generic artifact wiki contract now, then adapt metrics
  first behind that contract.
  - Why: this avoids building a metric-only page that would later need to be
    replaced or wrapped when extending the experience to all searchable artifacts.
- Considered: keep metric-specific and artifact-specific wiki implementations,
  then unify only the frontend layout.
  - Rejected because it would preserve backend divergence and make language
    caching, translation, and search-result routing harder to standardize.
- Considered: keep the current metric wiki API and add a thin generic facade.
  - Rejected because it would reduce short-term code churn but would defer the
    real contract cleanup.

### Database Migrations
- No database migration is required for Change 01 as currently designed.
- The implementation should reuse existing artifact identity and search metadata
  from `kb.search_artifacts`, plus existing artifact source tables such as
  `kb.metrics`.

### Data Formats
- Generic wiki page identity is the tuple:
  - `artifact_type`
  - `artifact_id`
  - `lang`
- Frontend route should use a generic section and query parameters, for example:
  - `home3/knowledge?section=kb-artifact-wiki&artifact_type=metric&artifact_id=5_mtc_3&lang=en`
- Generic backend API should also use `artifact_type` + `artifact_id` rather than
  a metric-only or opaque synthetic id.
- Generic wiki response should separate:
  - `article`: the left-panel article payload created by LLM or translation
  - `record`: the grounded artifact record used to render the right-panel inspector
  - `source_document`: source document metadata when available
  - `generated`: metadata such as model, language, schema version, and source hash
- Cache files should remain language-specific and lazy-created. The cache key
  should be based on `artifact_type + artifact_id + lang`.

### Environment Variables
- Reuse the existing wiki-generation model configuration and artifact directory
  configuration already used by the metric wiki implementation.
- `ARTIFACT_DIR` remains required because wiki pages continue to be cached in the
  artifacts directory.
- No new environment variable is required by this ADR revision.

### Implementation
- Introduce a generic artifact wiki route and backend contract now.
- Metrics are the first artifact type to be adapted to the generic contract.
- Search results should link all supported artifacts to the generic wiki route.
- The page layout remains two-panel:
  - Left panel: generated article
  - Right panel: grounded artifact record
- For metrics, the left panel should preserve the stronger legacy metric wiki
  article experience during the generic-contract rollout, including the richer
  article presentation and visible in-progress build state, while the new
  grouped inspector is introduced on the right.
- The right panel should be implemented as a **curated grouped inspector** that
  still exposes all stored fields for the artifact. This is preferred over a raw
  JSON dump.
- The grouped inspector should be reusable across artifact types, with artifact-
  specific grouping definitions where necessary.
- The implementation should preserve lazy creation:
  - if the wiki page cache exists in the requested language, return it
  - if the requested language cache is missing but the English cache exists,
    translate from the English cached page and save the translated cache
  - if no cache exists, generate the English wiki page first; for non-English
    requests, translate from the generated English page and save the target-language cache
- If a non-English page is requested but no translation model is configured,
  the system should generate the page directly in the requested language rather
  than serving an English article under non-English metadata.
- The right panel must render immediately from grounded data even when the left
  panel is still generating or translating.
- After the metrics path is tested and green under the generic contract, extend
  the same contract and page behavior to all searchable artifact types.
- The first rollout wave after metrics should onboard:
  - `summary`
  - `topic`
  - `semantic_projection`
  - `scene_block`
  - `product`
  - `inventory_item`
  - `provision`
  - `entity`
  - `relation`
  - `knowledge`
- `chunk` may remain temporarily outside this wave until its detail-page
  grounding and article shape are specified.

### Code Changes
- Replace the metric-only search result deep link behavior with generic artifact
  wiki links based on `artifact_type` + `artifact_id`.
- Add a generic artifact wiki frontend page/component instead of a metric-only page.
- Add a generic artifact wiki backend handler/API that dispatches by `artifact_type`.
- Adapt the current metric wiki implementation into a metric-specific adapter or
  provider behind the generic contract.
- Reuse existing metric compile/generate logic where possible rather than
  duplicating LLM generation logic.
- For non-metric artifacts, decode search-facing `artifact_id` values using the
  same artifact-type conventions used by `kb.search_artifacts`, then resolve the
  grounded source record from the owning artifact table or artifact files.
- Add a reusable grouped inspector component for artifact records. For metrics,
  the inspector must expose all stored fields, including structured JSON fields.

### Operational Behaviors
- A cache miss may still be slow because LLM generation is performed on demand.
- Even on a cache miss, the right panel should load immediately with grounded record data.
- Translation should prefer the English cached page as the source when available,
  to preserve structure and reduce generation cost.
- Language caches are independent. A cached English page does not imply a cached
  non-English page.
- This change should preserve existing lazy generation semantics while improving
  user-perceived responsiveness.

### Consequences
- Positive:
  - One durable wiki contract for all searchable artifacts
  - Consistent search-result navigation
  - Better responsiveness because record inspection is no longer blocked on LLM generation
  - Cleaner future extension to topics, summaries, provisions, products, scenes, and other searchable artifacts
  - The first post-metric rollout wave can reuse one generic cache/translation
    path while still resolving grounded records from artifact-specific storage
- Tradeoff:
  - The first implementation slice is larger than a metric-only patch because
    the generic contract is introduced up front.
  - `chunk` still needs a later onboarding pass because its artifact identity or
    article requirements are not yet standardized for this page.

### Tests
- Verify that metric search results open the generic artifact wiki route.
- Verify that the generic route uses `artifact_type` + `artifact_id` correctly.
- Verify cache-hit behavior for English and non-English requests.
- Verify translation behavior when:
  - English cache exists and target-language cache does not
  - neither English nor target-language cache exists
- Verify that the right panel renders grounded record data immediately while the
  left panel is still generating or translating.
- Verify that the metric grouped inspector exposes all stored fields, including
  JSON-backed fields.
- After metrics are green, add equivalent tests for each additional supported
  artifact type as it is onboarded to the generic contract.

## References
