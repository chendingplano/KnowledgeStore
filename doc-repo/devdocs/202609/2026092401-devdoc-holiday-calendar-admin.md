# Holiday Calendar Admin — Data Model, API, and Frontend

**Date:** 2026-09-24 \
**Scope:** Source of truth for the Holiday Calendar admin feature — what the tables mean, the
full API surface, which frontend files implement it, and how it's wired into navigation.
**Code root:** `ChenWeb/server/api/calendarhandler/`, `ChenWeb/web/src/lib/components/home3/calendar-admin-*`

**Traceability — openspec:**
- `ChenWeb/openspec/changes/archive/2026-09-24-holiday-calendar-admin/proposal.md` — why this
  exists
- `ChenWeb/openspec/changes/archive/2026-09-24-holiday-calendar-admin/design.md` — data-model
  rationale, alternatives considered, risks/trade-offs
- `ChenWeb/openspec/changes/archive/2026-09-24-holiday-calendar-admin/tasks.md` — implementation
  log, including what was *not* independently verified (no browser click-through as a logged-in
  admin was performed by the implementing agent — only DB-level SQL checks and `go
  build`/`svelte-check`)
- `ChenWeb/openspec/specs/holiday-calendar-admin/spec.md` — the canonical, currently-in-force
  requirements (SHALL/scenario form). **Update this spec file, not just this doc, if behavior
  changes** — this doc explains mechanics and points at code; the spec is the contract.

The page lives at **Development → System Admin → System → Calendar** in `/home3`, admin/root
only.

## 1. Concepts

Two things are deliberately kept separate:

- **Holiday info** (`public.holiday_info`) — a year-independent holiday *definition*: name,
  country, optional description/note. "Independence Day" for the US exists once, regardless of
  how many years it's scheduled for.
- **Calendar** (`public.calendars` + `public.calendar_holidays`) — a year-specific *binding* of
  holiday infos to actual dates, keyed by `(year, country, calendar_type)`. Because holidays like
  "Thanksgiving" fall on different dates each year, dates are entered explicitly per year — there
  is no recurrence-rule engine.

A `calendars` row is created lazily: selecting a `(year, country, calendar_type)` with nothing
saved yet just shows an empty grid; the row is only inserted when the first date binding is
saved (`upsertCalendarDates`, see §3).

## 2. Schema

Database `miner`, schema `public` (via `ApiTypes.ProjectDBHandle` — the centralized connection
pool per workspace convention; this feature does not open its own pool). Migrations, in order:

- `ChenWeb/project_migrations/20260924060319_create_holiday_calendars.sql` — `holiday_info`,
  `calendars`, `calendar_holidays`
- `ChenWeb/project_migrations/20260924063520_create_calendar_default_country.sql` —
  `calendar_default_country`
- `ChenWeb/project_migrations/20260924140000_add_holiday_display_seqno.sql` — adds and backfills
  `holiday_info.display_seqno` and enforces unique per-country ordering

```sql
CREATE TABLE public.holiday_info (
    id              BIGSERIAL PRIMARY KEY,
    country         TEXT NOT NULL,
    name            TEXT NOT NULL,
    display_seqno   INT NOT NULL,
    description     TEXT,
    note            TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (country, name)
    ,UNIQUE (country, display_seqno)
);

CREATE TABLE public.calendars (
    id              BIGSERIAL PRIMARY KEY,
    year            INT NOT NULL,
    country         TEXT NOT NULL,
    calendar_type   TEXT NOT NULL DEFAULT 'holidays',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (year, country, calendar_type)
);

CREATE TABLE public.calendar_holidays (
    id              BIGSERIAL PRIMARY KEY,
    calendar_id     BIGINT NOT NULL REFERENCES public.calendars(id) ON DELETE CASCADE,
    holiday_info_id BIGINT NOT NULL REFERENCES public.holiday_info(id) ON DELETE RESTRICT,
    holiday_date    DATE NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (calendar_id, holiday_date)
);

CREATE TABLE public.calendar_default_country (
    id          INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    country     TEXT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Key constraints and what they enforce:

- `holiday_info` unique on `(country, name)` — no duplicate holiday name within a country.
- `calendars` unique on `(year, country, calendar_type)` — this triple *is* the calendar's
  identity; there is no separate surrogate "calendar key" concept anywhere else in the system.
- `calendar_holidays` unique on `(calendar_id, holiday_date)` — a given date in a given calendar
  maps to exactly one holiday. Attaching a different holiday to an already-bound date **replaces**
  the binding via `INSERT ... ON CONFLICT (calendar_id, holiday_date) DO UPDATE SET
  holiday_info_id = EXCLUDED.holiday_info_id` — it never creates a second row for that date.
- `calendar_holidays.holiday_info_id` is `ON DELETE RESTRICT` — a holiday info still bound to any
  date **cannot** be deleted at the database level. `deleteHolidayInfo`
  (`store.go`) pre-checks `EXISTS(SELECT 1 FROM calendar_holidays WHERE holiday_info_id = $1)`
  and returns `ErrHolidayInfoInUse`, which the handler maps to HTTP `409 Conflict`. Bindings must
  be removed first.
- `calendar_default_country` is a **singleton** — `id` is pinned to `1` via `CHECK (id = 1)` plus
  being the primary key, so there is structurally at most one row ever. `setDefaultCountry`
  upserts that one row (`ON CONFLICT (id) DO UPDATE`); it does not need to "clear all other
  flags" because there is no other row that could hold one — this was a deliberate design
  substitution for an earlier, rejected idea of an `is_default BOOLEAN` column on `holiday_info`
  itself (see design.md's Decisions section for why that was rejected: the default is a property
  of a *country*, not of an individual holiday, and a country with zero holidays yet should still
  be settable as default).

## 3. Backend

Package: `ChenWeb/server/api/calendarhandler/` — `handler.go` (HTTP layer) and `store.go` (SQL
layer, all functions take `*sql.DB` directly, no `DBX` interface abstraction — this mirrors the
`pageconfighandler` package's style rather than `kbhandler`'s `DBX`-interface style, since there's
only ever one caller, `ApiTypes.ProjectDBHandle`). Routes registered in
`ChenWeb/server/api/routes.go` under `/api/v1/calendars/...`.

**Authorization:** every handler calls `requireAdmin(c, loc)` — authenticated **and** (owner OR
`Admin` flag OR role `admin`/`root`), mirroring `kbhandler.requireKeywordRewriteAdmin`. This is a
second, feature-specific check layered on top of the pre-existing global
`authmiddleware.AuthMiddleware` on `apiGroup`, which already rejects any unauthenticated request
before it reaches this package at all (verified live: an unauthenticated `GET
/api/v1/calendars/holiday-info` returns `401 {"error":"Authentication required"}` from the
middleware, not from `calendarhandler`).

| Method | Path | Handler func | Notes |
|---|---|---|---|
| GET | `/calendars/holiday-info?country=` | `ListHolidayInfo` | optional country filter |
| POST | `/calendars/holiday-info` | `CreateHolidayInfo` | 409 on duplicate `(country, name)` |
| PUT | `/calendars/holiday-info/:id` | `UpdateHolidayInfo` | |
| DELETE | `/calendars/holiday-info/:id` | `DeleteHolidayInfo` | 409 if still bound to a date |
| GET | `/calendars?year=&country=&calendar_type=` | `GetCalendar` | empty-shape record if no row exists yet (never auto-creates) |
| PUT | `/calendars/dates` | `UpsertCalendarDates` | body: `{year, country, calendar_type, dates: [], holiday_info_id}`; creates the `calendars` row if missing, one holiday attached to N dates in one call |
| DELETE | `/calendars/:id/dates/:date` | `DeleteCalendarDate` | removes one binding |
| DELETE | `/calendars/:id` | `DeleteCalendar` | cascades bindings via FK |
| GET | `/calendars/default-country` | `GetDefaultCountry` | `{record: {country}}` or `{record: null}` |
| PUT | `/calendars/default-country` | `SetDefaultCountry` | body `{country}`; replaces any existing default |
| DELETE | `/calendars/default-country` | `ClearDefaultCountry` | reverts to the frontend's hardcoded `'US'` fallback |

Response envelope matches every other admin CRUD page in this codebase:
`{status, record?, results?, total?, error_msg?}`.

Holiday-info results are ordered by `display_seqno`. New definitions use the current
country’s maximum sequence number plus one. Updating a sequence number transactionally moves
the definition to that position and shifts affected definitions, preserving unique positive
sequence numbers within the country.

`calendar_type` defaults to `"holidays"` wherever omitted, both in the DB column default and in
`parseCalendarKey`/handler payload defaulting. It exists so a `(year, country)` pair could host
more than one kind of calendar later (e.g. a "school-closures" calendar type distinct from
"holidays"); only `"holidays"` is used anywhere today, and nothing enforces a closed list of
calendar types — it's a plain string column, not an enum or a foreign key.

## 4. Frontend

- `calendar-admin-view.svelte` — the page itself: year (number input) / country (dropdown) /
  calendar-type (text input) selectors; a 12-month CSS-grid calendar for the selected year
  (`monthCells` computes each month's leading blanks + day numbers from `Date`); click-to-toggle
  multi-select on empty day cells, click-to-remove on already-bound day cells; an "Attach
  Holiday" modal (pick an existing holiday info for the selected country, or check "Create a new
  holiday" to define one inline before attaching); and a "Holiday Definitions ({country})" table
  (list/create/edit/delete), scoped to whichever country is currently selected. The definitions
  table displays `display_seqno`, and the edit form allows administrators to change it.
- `calendar-admin-client.ts` — typed `fetch` wrappers for every endpoint in §3, using the same
  `Envelope<T>` parsing pattern as `keyword-rewrite-rules-client.ts`.
- `country-list.ts` — the fixed ISO 3166-1 alpha-2 country dropdown list (15 entries as of this
  writing: US, CN, GB, CA, AU, DE, FR, JP, KR, IN, SG, HK, TW, MX, BR). This is a plain hardcoded
  array, not backed by any table — add entries here to support more countries.

**Default-country flow:** on mount, the view calls `getDefaultCountry()` *before* loading the
calendar or holiday-info list, and uses the result as the initial `country` state if present;
otherwise it keeps the hardcoded fallback `COUNTRIES[0].code` (`'US'`). The "Set as default
country" checkbox in the Holiday Definitions panel header is bound to `isDefaultCountry =
$derived(defaultCountry === country)` — checking it calls `setDefaultCountry(country)`,
unchecking calls `clearDefaultCountry()`; either way the local `defaultCountry` state is updated
immediately from the response rather than re-fetched.

### Nav wiring

- `nav-rail.svelte` — a new `sysadmin-system` group (label "System") was added as a sibling of
  the existing `sysadmin-page-config` entry inside `system-admin`'s `children`, containing one
  leaf: `{ id: 'sysadmin-system-calendar', label: 'Calendar' }`.
- `content-panel.svelte` — renders `<CalendarAdminView {darkMode} />` when `activeMenu?.childId
  === 'sysadmin-system-calendar'`.

There is no SvelteKit route for this page — `/home3` is a client-side SPA driven entirely by
`activeMenu` state, the same pattern every other System Admin leaf uses (no
`+page.svelte`/`+page.ts` files to look for).

## 5. Known limitations (by design — see design.md's Risks/Trade-offs and Non-Goals)

- No recurring-holiday rule engine (e.g. "4th Thursday of November" computed automatically).
  Every year's dates are entered explicitly by an admin.
- No public/non-admin consumption API for other features to query holidays (e.g. a business-day
  calculator). This is admin management only; a read API for other consumers is a separate future
  change if/when one is actually needed.
- No timezone handling — `holiday_date` is a plain SQL `date`, no time-of-day component anywhere.
- The country list is a hardcoded frontend array (§4), not a DB table — there is no server-side
  validation that a submitted `country` value is one of the 15 listed codes.

## 6. Extending this feature

- **Add a country to the dropdown:** edit `country-list.ts`'s `COUNTRIES` array. No backend or
  migration change needed — `country` is a free-text column everywhere.
- **Query holidays from another feature:** there is currently no exported/shared Go package for
  this — either add read-only functions to `calendarhandler/store.go` and export them, or extract
  a small `calendarstore` package if a second consumer needs the same queries. Do this only once
  an actual consumer exists (see §5).
- **Support a second calendar type:** the schema already supports it — `calendar_type` is a plain
  string column, and the frontend's calendar-type field already accepts arbitrary text — so no
  schema change should be needed, only UI/UX decisions about how multiple types are presented
  side by side.

## 7. Verification status (as of 2026-09-24)

Confirmed by direct SQL against the live `miner` dev DB and by the user manually exercising the
UI in a browser (screenshot review, 2026-09-24): creating holiday info, the `(country, name)`
uniqueness constraint, attaching a holiday to multiple selected dates, re-binding a date to a
different holiday, `RESTRICT`-blocked deletion of an in-use holiday info, cascade-delete of a
calendar, and the default-country singleton overwrite/clear behavior all work as specified. Not
independently re-verified by the implementing agent beyond that: role-based `403` for an
authenticated-but-non-admin user (only the `401`-unauthenticated path was checked directly).
