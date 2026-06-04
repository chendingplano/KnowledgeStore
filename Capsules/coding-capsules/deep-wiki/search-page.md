# Deep Wiki Search Page

## Overview

The Deep Wiki search page is the SemOS knowledge-base result surface behind the
LLM Wiki search box. It is intentionally shaped like a Wikipedia-style result
page: a clear title, a persistent query field, scoped result filters, result
counts, snippets, and pagination.

The page lives inside the Home3 Knowledge workspace rather than as a separate
top-level route:

```text
LLM Wiki search form
  └─ GET /home3/knowledge?section=kb-search&dark=1&q=<query>
       └─ home3/knowledge route selects kb-search
            └─ KbSearchResultsView fetches /api/v1/kb/search
```

The most important interaction contract is that the entrance search fields use
native browser `GET` form submission. Clicking **Search** or pressing Enter must
navigate to the search-results route even if client-side SvelteKit navigation is
not running, stale, or interrupted.

## Status

Implemented in ChenWeb.

- The Wiki v3 entrance search submits to the search page.
- The standalone `/deep-wiki` ("LLM Wiki") entrance submits to the same page.
- Both entrances share one `SemosKbHero` component for the diagram + search box.
- The results page reads the query from the URL and performs the initial search.
- Results can be narrowed by artifact type without leaving the page.
- Pagination fetches additional result pages for the active query and scope.
- The active result page is carried in the URL via `page=<n>` so deep links and refresh keep position.
- Empty, loading, and error states are rendered in-page.

## Files

| Layer | Path | Role |
|---|---|---|
| Route switch | `ChenWeb/web/src/routes/home3/knowledge/+page.svelte` | Reads `section=kb-search` and `q`, then renders `KbSearchResultsView` when a query exists |
| Results view | `ChenWeb/web/src/lib/components/home3/kb-search-results-view.svelte` | Search page UI, state, filters, loading/error/empty states, result list, pagination |
| Hero module | `ChenWeb/web/src/lib/components/home3/semos-kb-hero.svelte` | Reusable Top Panel: wired SemOS KB diagram + search form (shared entrance) |
| Wiki v3 entrance | `ChenWeb/web/src/lib/components/home3/llm-wiki-v3-view.svelte` | Main SemOS wiki page; Panel A renders `SemosKbHero` |
| Deep Wiki entrance | `ChenWeb/web/src/routes/deep-wiki/+page.svelte` | Standalone `/deep-wiki` ("LLM Wiki"); Panel A renders `SemosKbHero` |
| Search service | `ChenWeb/web/src/lib/services/kbArtifactSearch.ts` | Frontend API wrapper for artifact search |
| Scope options | `ChenWeb/web/src/lib/components/home3/kb-search-lab-state` | Artifact-type option labels reused by the results page |
| Backend search | `ChenWeb/server/api/kbhandler/search_registry.go` | Registry search handler over `kb.search_artifacts` |

## Route contract

The search page is addressed by query parameters on `/home3/knowledge`:

```text
/home3/knowledge?section=kb-search&dark=1&q=tsvector&page=2
```

| Parameter | Required | Meaning |
|---|---:|---|
| `section=kb-search` | yes | Selects the search surface in the Home3 Knowledge route |
| `q` | for results | Search query. If missing, the route falls back to the Knowledge Store view |
| `page` | optional | 1-based result page. Omitted for page 1 |
| `dark` | optional | Preserves the active visual theme (`1` dark, `0` light) |

The entrance forms include hidden `section` and `dark` fields plus a named
search input, and they carry `data-sveltekit-reload`:

```svelte
<form action="/home3/knowledge" method="GET" role="search" data-sveltekit-reload>
  <input type="hidden" name="section" value="kb-search" />
  <input type="hidden" name="dark" value={darkMode ? '1' : '0'} />
  <input type="search" name="q" bind:value={query} />
  <button type="submit">Search</button>
</form>
```

This deliberately avoids making the entrance depend on `goto()`. The
`data-sveltekit-reload` attribute is what actually makes the browser own the
navigation: without it SvelteKit intercepts `method="GET"` form submissions and
performs a client-side navigation, which can be swallowed by a stale or
interrupted client router in the proxied Home3 shell. With it, the Search button
triggers a full browser navigation with normal HTML semantics.

## Shared entrance hero (`SemosKbHero`)

The entrance "Top Panel" — the artistically wired SemOS KB diagram plus the
knowledge-base search box — is one reusable component,
`semos-kb-hero.svelte`. It was extracted from the LLM Wiki v3 Top Panel so every
wiki surface presents an identical entrance. Both the Wiki v3 view and the
standalone `/deep-wiki` page render it as their Panel A.

```ts
{
  darkMode?: boolean;                       // default true
  overview?: WikiOverviewResponse | null;   // corpus counts for the node values
  loading?: boolean;                        // dims the nodes while counts load
}
```

The component is self-contained: it carries its own dark/light palette, owns the
`query` and locale state, and renders the `data-sveltekit-reload` search form, so
the Search-button fix above travels with it. The parent only fetches the overview
once and passes it down (the parent still needs `overview` for its activity feeds,
so the hero does not fetch independently).

**Responsive behavior — the layout gotcha.** The hero measures its own width and,
below `900px`, collapses the wired stage into a compact stacked-node grid. So the
hero must be given (near) full width to render the diagram. When it was first
dropped into `/deep-wiki`'s old two-column masthead (Panel A `1.55fr` | Panel B
`0.85fr`), its column was only ~800px, so it silently fell back to the compact
layout and looked different from v3 even though it was the same component. The fix
was to stop squeezing it: `/deep-wiki` now stacks its panels (hero, then the
directory, then activity — Top/Middle/Bottom, like v3) so Panel A spans full width
and clears the breakpoint.

One intentional difference remains: `/deep-wiki` passes `darkMode={false}` (it is a
light standalone page) while the v3 view runs dark inside the knowledge shell.
Matching the theme is postponed.

## Result page behavior

`KbSearchResultsView` accepts:

```ts
{
  darkMode: boolean;
  initialQuery?: string;
  initialPage?: number;
}
```

Local state:

- `query` - current text in the search field.
- `submittedQuery` - query that results currently represent.
- `artifactType` - active scope tab, default `all`.
- `pageNumber` - active result page, default `1`.
- `payload` - latest `KbSearchResponse`.
- `loading` / `error` - request state.

On first render, the component trims `initialQuery`, normalizes `initialPage`,
and immediately fetches that page. Later URL/query changes update `query`,
`submittedQuery`, and pagination before fetching again.

Submitting the search form on the results page:

1. Prevents default submission.
2. Trims the query.
3. Resets to page 1.
4. Updates the URL with `section=kb-search&q=<query>` and removes `page` for page 1.
5. Fetches results for the new query.

Changing the artifact scope keeps the same submitted query, resets to page 1,
and fetches the selected artifact type.

Using the pagination controls:

1. Keeps the active query and scope.
2. Updates the URL with `page=<n>` when moving beyond page 1.
3. Fetches the selected result page.
4. Renders direct page buttons with ellipses for long result sets, alongside Previous / Next.
5. Shows pagination above the result list so the next page is reachable without scrolling past every result.

## UI structure

The page is a dense, work-focused search surface:

- Header: `SemOS knowledge index` eyebrow, `Search results` title, and result
  range when data is loaded.
- Search form: icon, query field, clear button, and submit button.
- Scope row: tabs for All plus artifact-specific slices.
- Result status:
  - loading skeletons while a request is in flight;
  - inline error panel on request failure;
  - empty state when the query has no matches;
  - prompt state when no query is present.
- Result list:
  - compact thumbnail containing the artifact initial;
  - title;
  - metadata line with artifact type, record id, source, and score;
  - snippet when available.
- Pagination: Previous / Next buttons with `Page N of M`.

The visual style uses the SemOS dark/light palette rather than copying
Wikipedia directly. The layout borrows Wikipedia's information hierarchy:
search first, result count second, result list third.

## Search scopes

The page reuses `kbSearchArtifactOptions`, with the `all` label normalized to
`All`. Current scopes include:

- All
- Metrics
- Summaries
- Topics
- Scene Blocks
- Provisions
- Products

These map to backend artifact-type filters. Adding a new artifact type should
update the shared option list first so the Search Lab and Search Page stay in
sync.

## Backend dependency

The frontend calls `searchKbArtifacts(artifactType, { q, page, pageSize })`.
All scopes now resolve to the registry endpoint `/api/v1/kb/search`; scoped tabs
pass `artifact_types` (`metric`, `summary`, `topic`, `scene_block`, `provision`,
`product`) instead of using older per-artifact search endpoints. This is
important for testing hybrid search: the Metrics tab must use
`kb.search_artifacts`, not the legacy `/api/v1/kb/metrics/search` path, so it can
exercise ParadeDB BM25 plus pgvector semantic ranking when the server has
`SEARCH_LEXICAL_BACKEND=paradedb` and `SEARCH_SEMANTIC_ENABLED=true`.
The API is authenticated with the rest of `/api/v1/kb`; an unauthenticated
browser may successfully navigate to the page but receive a search API error.

A search with no matches is a valid outcome. The backend (or a proxy in front of
it) can answer with a dropped connection (`net::ERR_EMPTY_RESPONSE`) or an empty
body instead of a JSON envelope. `searchKbArtifacts` treats both as "zero
results" — it catches the `fetch` rejection and the empty-body case and returns a
well-formed empty `KbSearchResponse`, so the results page renders its normal
"No results found" empty state rather than a raw network error. Genuine HTTP
error statuses that carry a body still throw and surface as an error panel.

The result view expects a `KbSearchResponse` with:

- `total`
- `results`
- artifact display fields such as `primary_label`, `metric_name`, `topicText`,
  `summaryText`, `provisionText`, `productName`
- snippet/search text fields such as `snippet`, `search_document`,
  `metric_desc`, `metric_context`
- optional metadata fields such as `source_title`, `source_filename`,
  `input_record_id`, `score`

## Important bug fix: Search button did nothing

The original Wiki entrance forms intercepted submit and called SvelteKit
`goto()`:

```ts
function runSearch(event: SubmitEvent) {
  event.preventDefault();
  goto(`/home3/knowledge?section=kb-search&q=${encodeURIComponent(q)}`);
}
```

In the proxied Home3 environment, the user could type a query and click
**Search** but see no visible navigation. The first fix removed the
JavaScript-only submit handler and used native `method="GET"` forms — but that
was not enough on its own, because SvelteKit intercepts GET form submissions and
routes them client-side, so the same stale-router problem still swallowed the
submit and nothing happened.

The robust fix adds `data-sveltekit-reload` to the entrance form. This opts the
form out of SvelteKit's client-side interception so the browser performs a real
navigation. The form now lives in the shared `SemosKbHero` module used by both
the Wiki v3 entrance and the standalone `/deep-wiki` entrance, so both inherit
the fix. The standalone `/deep-wiki` entrance was additionally converted from its
old `goto()` submit handler to this native reload form.

This keeps the user-facing behavior simple:

- click **Search** -> URL changes to `section=kb-search&q=<query>`;
- press Enter in the field -> same result;
- reload/share/bookmark -> the query is preserved in the URL;
- stale client-side routing cannot swallow the entrance action.

## Verification

Focused checks performed after implementation:

```text
npm exec svelte-check -- --tsconfig ./tsconfig.json
```

No new diagnostics were reported for the touched search files. The retired
`llm-wiki-v2-view.svelte` (and its lone unused-CSS-selector warning) was deleted
with the v2 entrance.

Chrome/Playwright interaction checks:

- Opened `/home3/knowledge?section=kb-llm-wiki-v3&dark=1`.
- Filled the v3 search field.
- Clicked Search.
- Verified URL became
  `/home3/knowledge?section=kb-search&dark=1&q=native+vector`.
- Verified the page heading was `Search results`.
- Repeated the same flow from the standalone `/deep-wiki` entrance.

## Future work

- Make result titles link to the most useful artifact detail page instead of
  linking back to the current search URL.
- Add direct document/source links where `input_record_id` is available.
- Add a "Did you mean" or query rewrite hint when lexical search returns zero
  results.
- Preserve artifact scope in the URL so scoped searches are shareable.
- Show whether the backend used lexical-only or hybrid lexical+semantic search.
- Add exact hybrid totals once semantic search is fully enabled, since interim
  hybrid totals can undercount semantic-only matches.
