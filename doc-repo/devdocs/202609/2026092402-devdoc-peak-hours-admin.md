# Peak Hours Admin — Data Model, API, and Frontend

**Date:** 2026-09-24 \
**Scope:** Source of truth for the Peak Hours admin feature — what the table means, the full API
surface, which frontend files implement it, and how it's wired into navigation.
**Code root:** `ChenWeb/server/api/peakhourshandler/`, `ChenWeb/web/src/lib/components/home3/peak-hours-*`

**Traceability — openspec:**
- `ChenWeb/openspec/changes/archive/2026-09-24-peak-hours-admin/proposal.md` — why this exists
- `ChenWeb/openspec/changes/archive/2026-09-24-peak-hours-admin/design.md` — data-model rationale,
  alternatives considered, risks/trade-offs
- `ChenWeb/openspec/changes/archive/2026-09-24-peak-hours-admin/tasks.md` — implementation log,
  including a latent auth-gating bug found and fixed along the way (see §5)
- `ChenWeb/openspec/specs/peak-hours-admin/spec.md` — the canonical, currently-in-force
  requirements (SHALL/scenario form). **Update this spec file, not just this doc, if behavior
  changes** — this doc explains mechanics and points at code; the spec is the contract.

The page lives at **Development → System Admin → System → Peak Hours** in `/home3`, admin/root
only. It sits alongside the existing Calendar page (`sysadmin-system-calendar`) under the same
"System" nav group.

## 1. Concept

A "peak hours" record is a named, reusable rule for "is now within this window?" — for example,
DeepSeek's stated peak pricing/availability window: 9:00am–12:00pm and 2:00pm–6:00pm, Beijing
time, on workdays, excluding holidays and weekends. It exists so other features (routing,
throttling, or any code that needs to behave differently during a named window) can ask a single
question — "is `<name>` active right now?" — instead of re-implementing day/hour/exclusion logic
each time.

Three rule fields compose to decide whether a record is "active" at a given moment, always
evaluated in the record's own timezone:

1. **`applicable_days`** — which days the window can ever be active on: all workdays, a specific
   set of weekdays, or a specific set of days-of-month.
2. **`exclude_days`** — days that are *always* inactive regardless of `applicable_days`, ORed
   together: weekends, holidays (see §1.1), and/or specific dates or date ranges.
3. **`hours`** — the time-of-day ranges within an applicable, non-excluded day when the record is
   active.

### 1.1 Holiday exclusion reuses the Calendar feature

"Holidays" is not defined by this feature — it reads (read-only) from the existing Holiday
Calendar admin tables (`public.holiday_info` / `public.calendars` / `public.calendar_holidays`;
see `2026092401-devdoc-holiday-calendar-admin.md`). Each peak-hours record carries its own
`country` field so it knows which country's holiday calendar to check; if `country` is blank, or
no calendar row exists yet for that country/year, "holidays" simply excludes nothing for that
record — this is a deliberate fail-open choice, not an error, so a record that doesn't care about
holidays isn't forced to pick a country.

## 2. Schema

Database `miner`, schema `public` (via `ApiTypes.ProjectDBHandle`, the centralized connection
pool — this feature does not open its own pool). Migration:
`ChenWeb/project_migrations/20260924122346_create_peak_hours.sql`.

```sql
CREATE TABLE public.peak_hours (
    id                BIGSERIAL PRIMARY KEY,
    name              TEXT NOT NULL UNIQUE,
    hours             JSONB NOT NULL,
    timezone          TEXT NOT NULL,
    applicable_days   JSONB NOT NULL,
    exclude_days      JSONB NOT NULL DEFAULT '[]',
    country           TEXT NOT NULL DEFAULT '',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

One row per named definition; `name` is both the unique identity and the lookup key used by the
evaluation endpoint (§3). The three rule fields are stored as JSONB rather than normalized into
child tables — they're always read/written as a whole and never queried by their internal
structure, so a normalized schema would only add joins for no benefit (see design.md's Decisions
section).

**`hours`** — a JSON array of `"HH:MM-HH:MM"` strings, 24-hour, two-digit, start strictly before
end. Example: `["09:00-12:00", "14:00-18:00"]`.

**`applicable_days`** — a discriminated object:
- `{"mode": "workdays"}` — Monday through Friday.
- `{"mode": "weekdays", "days": ["mon", "fri"]}` — an explicit set of weekday names (`mon`..`sun`).
- `{"mode": "days_of_month", "days": [1, 15]}` — an explicit set of day-of-month numbers (1–31);
  a day that doesn't exist in a given month (e.g. 31 in April) simply never matches that month —
  there is no rollover/clamping.

**`exclude_days`** — a flat JSON array of strings, ORed together (any single match excludes the
day): the literal keywords `"weekends"` and `"holidays"`, an ISO date (`"2026-12-25"`), or an ISO
date range joined by `..` (`"2026-12-24..2026-12-31"`, inclusive both ends).

**`country`** — free text (matches whatever `country` values the Holiday Calendar feature uses,
e.g. `"CN"`), or blank to opt out of holiday exclusion entirely.

## 3. Backend

Package: `ChenWeb/server/api/peakhourshandler/` — `store.go` (validation + SQL, all functions take
`*sql.DB` directly), `evaluate.go` (`EvaluateActive`, the active/inactive decision logic), and
`handler.go` (HTTP layer). Routes registered in `ChenWeb/server/api/routes.go` under
`/api/v1/peak-hours`.

| Method | Path | Handler func | Auth | Notes |
|---|---|---|---|---|
| GET | `/peak-hours` | `List` | admin | all records, ordered by name |
| POST | `/peak-hours` | `Create` | admin | 409 on duplicate `name`, 400 on validation failure |
| PUT | `/peak-hours/:name` | `Update` | admin | `name` itself is immutable |
| DELETE | `/peak-hours/:name` | `Delete` | admin | |
| GET | `/peak-hours/:name/is-active?at=<RFC3339>` | `IsActive` | **authenticated, not admin-only** | `at` defaults to server `time.Now()`; 404 unknown name, 400 unparseable `at` |

Response envelope matches every other admin CRUD page in this codebase:
`{status, record?, results?, total?, error_msg?}`; `IsActive` additionally returns `active: bool`.

`IsActive` is deliberately not gated behind the admin check — any other authenticated backend
caller can ask whether a named window is active. It is still behind the shared, app-wide
`authmiddleware.AuthMiddleware` on `apiGroup` (every route under `/api/v1/*` requires *some*
authenticated session; there is no fully public/unauthenticated path here).

**Evaluation logic (`EvaluateActive`, `evaluate.go`):** convert the queried instant into the
record's `timezone`, then check in order — `applicable_days` (cheap, no DB) → `exclude_days`
(`"holidays"` is the only branch needing a DB lookup, against `calendar_holidays` joined to
`calendars` for `(year, country, calendar_type='holidays')`) → each `hours` range. The first
matching exclusion, or falling on a non-applicable day, short-circuits to inactive without
checking `hours` at all.

## 4. Frontend

- `peak-hours-view.svelte` — the page itself: a filterable table (name/timezone/country) plus a
  create/edit modal. The modal has: a name field (immutable once created), a timezone `<select>`
  populated from `Intl.supportedValuesOf('timeZone')` (falling back to a ~20-zone curated list on
  older browsers, and always including the record's current value even if not in that list), a
  repeatable hours-range chip list with a format hint, a mode picker (workdays / weekdays /
  days-of-month) with the matching sub-editor, weekends/holidays exclusion checkboxes plus a
  free-text specific-dates/ranges field, and a country dropdown (reusing `country-list.ts` from
  the Calendar feature) with a hint shown when "holidays" is checked but country is blank.
- `peak-hours-client.ts` — typed `fetch` wrappers for every endpoint in §3, using the same
  `Envelope<T>` parsing pattern as `keyword-rewrite-rules-client.ts`, plus
  `validatePeakHoursDraft` (client-side mirror of the server-side validation, so bad input is
  caught before a round trip).

### Nav wiring

- `nav-rail.svelte` — `{ id: 'sysadmin-system-peak-hours', label: 'Peak Hours' }` added as a
  second child of the existing `sysadmin-system` group, alongside `sysadmin-system-calendar`.
- `content-panel.svelte` — renders `<PeakHoursView {darkMode} />` when `activeMenu?.childId ===
  'sysadmin-system-peak-hours'`.

There is no SvelteKit route for this page — `/home3` is a client-side SPA driven entirely by
`activeMenu` state, the same pattern every other System Admin leaf uses.

## 5. A bug found and fixed while building this

While writing handler-level tests, an actual latent bug turned up in the `requireAdmin` pattern
this feature's `handler.go` initially copied verbatim from `calendarhandler`: it used `return rc,
c.JSON(...)` to signal "authorization failed, stop here" — but `c.JSON` returns `nil` on a
successful write, so the caller's `if err != nil { return err }` check never actually fired. A
denied (401/403) request would still fall through and run the protected logic afterward. This
package now uses a dedicated sentinel error (`errAdminCheckFailed`) instead. **`calendarhandler`
itself was left unchanged** — fixing it was out of scope for this change — so it likely still has
this issue; anyone touching that package, or copying its `requireAdmin` pattern into a new one,
should check for and fix this first.

## 6. Known limitations (by design — see design.md's Risks/Trade-offs and Non-Goals)

- No scheduler or push notification when a window opens or closes — evaluation is pull-only, one
  instant at a time, on request.
- No caching for `IsActive` — each call re-runs the applicable-days/exclude-days/hours logic and,
  when relevant, one small holiday-lookup query. Not expected to matter at this feature's scale.
- `country` is free text with no server-side validation against a fixed list (same as the Holiday
  Calendar feature's `country` column) — a typo'd country simply never matches any calendar rows,
  silently excluding nothing rather than erroring.
- No ownership/multi-tenant model — same single admin-only access tier as every other System
  Admin page.

## 7. Verification status (as of 2026-09-24)

17 backend Go tests (validation edge cases, `EvaluateActive` against the DeepSeek worked example
across an active window, between windows, on a weekend, and on a configured holiday) and 8
frontend tests (client-side draft validation) all pass; `go vet` and `svelte-check` are clean. The
migration was confirmed live against the `miner` dev DB via `psql`. The user then manually
exercised the page in a live logged-in browser session — create/edit/delete of the DeepSeek
example record — and confirmed it works, including a follow-up UI pass (timezone dropdown, text
selection inside the page/modal, hours-format hint) prompted by that session.
