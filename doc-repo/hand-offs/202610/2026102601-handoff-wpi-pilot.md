# Web Page Interpreter (WPI) Pilot — Session Handoff

Date: 2026-10-26

## 1. State in one paragraph

The user wrote a short design note for a Web Page Interpreter: web pages described as JSON
descriptors and drawn by one generic interpreter. Over several rounds it was reviewed and
rewritten into the guiding devdoc `2026102601`, with the user deciding the model as we went:
WPI apps, layout templates, panes holding panels, menu-bound panels, lists that query their
own data, last save wins, load/save on any table, and i18n of descriptor text deferred. The
pilot was then planned as the ChenWeb OpenSpec change `wpi-pilot` and implemented end to
end: 43/43 tasks done, a Go backend (`server/api/wpi`), a Svelte frontend
(`web/src/lib/wpi`, route `/wpi/[appId]`), three migrations including a seeded demo app,
and docs. Everything is committed with `jj` in ChenWeb and KnowledgeStore (not pushed). The
demo app `customer-admin` passed all four "done when" checks of devdoc 2601 §8 in a headless
browser against the real backend, database and frontend, with a stand-in user because
ChenWeb has no test login. **The OpenSpec change is not archived**; that is the first thing
to do when the user agrees (§9).

## 2. Document lineage (read in this order if picking this up cold)

1. **Devdoc `2026102601-devdoc-web-page-interpreter.md`** (`KnowledgeStore/doc-repo/devdocs/202610/`):
   the guiding design for all phases. §8 is the pilot, §9 the roadmap, §10 the four rules
   the user confirmed, §11 what the pilot taught. Updated at the end of this session to
   match what was built.
2. **Devdoc `2026102602-devdoc-web-page-interpreter-research-report.md`**: a research report
   the user brought from ChatGPT. Background only; it still contains ChatGPT artefacts
   (images.openai.com links, favicon lines, `utm_source=chatgpt.com`) and is **not
   committed**; it is the user's file.
3. **`ChenWeb/openspec/changes/wpi-pilot/`**: `proposal.md`, `design.md` (decisions D1–D14,
   the exact descriptor format for schema_version `0.1`, the API table), four specs
   (`wpi-descriptor-store`, `wpi-data-actions`, `wpi-app-shell`, `wpi-page-rendering`),
   `tasks.md`. The design and data-actions spec were amended during implementation (§5).
4. **Devdoc `2026102603-devdoc-wpi-pilot.md`**: what was built, where it lives, how to change
   an app, known limitations. Written for people, not as a contract.
5. **Reusable modules** `KnowledgeStore/doc-repo/modules/module-web-page-interpreter-frontend.md`
   (`20261026-01`) and `module-web-page-interpreter-backend.md` (`20261026-02`), with
   matching rows in `kb.reusable_modules`.
6. **Claude memory**: `project_web_page_interpreter.md` and
   `reference_chenweb_migrations_apply.md` in `~/.claude/projects/-Users-cding-Workspace/memory/`.

## 3. What was done this session

1. **Review of the original note.** First misread as "add a cross-reference" (reverted),
   then reviewed. The main gaps raised: the action model was promised but undefined,
   page/pane/panel were unclear, there was no list repetition, element type and instance
   were mixed, the i18n conflict with Paraglide, storage was in `public`.
2. **Rewrite into the guiding doc**, then three rounds of user decisions:
   - pages, panes and panels, then the user's new **WPI App** concept with layout templates;
   - no split pages; embedding an app in a page is deferred (the `<iframe>` vs `<div>`
     analogy); Collapse is deferred;
   - menu-item → panel-instance bindings, kept by the menu's pane;
   - refresh specified per page; hidden panels age out or are closed manually;
   - every page lives in an app; the URL holds only the app ID; the pilot is the menu
     example;
   - last save wins; lists always query their own data in iteration 1; load/save on any
     table;
   - the four §10 rules were proposed by Claude and confirmed by the user.
3. **OpenSpec propose**: `wpi-pilot`, validated `--strict`.
4. **Apply, backend:**
   - migrations `20261026000001` (descriptors table), `…02` (demo table + 3 rows), `…03`
     (13 seed descriptors);
   - package `server/api/wpi` with structure and graph validation, the bundle endpoint, the
     admin PUT endpoint, the action-run endpoint, SQL builders and save rules;
   - routes in `server/api/routes.go`; sqlmock tests throughout, plus a test that parses the
     seed migration and validates the demo app.
5. **Apply, frontend:**
   - pure TypeScript modules (refs, dirty, panels, layout, entries, api) with `bun` tests;
   - the `$state` runtime, templates, Pane/Panel, the flow layouter and six element types;
   - the unsaved-changes dialog, the route, and 26 `wpi_*` messages in English and Chinese.
6. **Verification:**
   - a read-only live check of the bundle and the loads;
   - a Playwright end-to-end run (§7) through checks 9.1–9.5, plus the prompt's save
     failing and the browser leave warning;
   - test rows removed afterwards; bob's email restored.
7. **Docs:** devdoc 2603, module docs and catalogue rows, and updates to 2601 (status,
   pilot markers, storage as built, §8 status, new §9 items, new §11).

## 4. Exact revisions this session produced

ChenWeb (`jj`, on `main`, not pushed):

| Change | Content |
| --- | --- |
| `qqky` | OpenSpec change `wpi-pilot` (proposal, design, specs, tasks) |
| `kolv` | Backend + three migrations + design/spec amendments |
| `olsq` | Frontend + message keys + design D9/D10 amendments |
| `pwrl` | `tasks.md` 43/43 |

KnowledgeStore (`jj`, not pushed):

| Change | Content |
| --- | --- |
| `vppw` | Rewrite of devdoc 2601 as the guiding design |
| `nlwm` | WPI App review round; list/save/table decisions |
| `nwno` | Apps with layout templates, menu-bound panels, refresh, retention; pilot = menu app |
| `uouq` | §10 rules confirmed |
| `mtpr` | Devdoc 2603, module docs, 2601 status line |
| `wzny` | 2601 updated to match the build; this handoff |

Database (`miner`): `kb.wpi_descriptors` (13 seed rows, version 1), `kb.wpi_demo_customers`
(alice, bob, chen), and `kb.reusable_modules` rows `20261026-01` and `20261026-02`.

## 5. Decisions and judgment calls not obvious from the code

- **Action reference generalised** from `{page, pointer}` to `{kind, id, pointer}`, because a
  stored element (a list or menu) can carry an inline action. Spec and design were amended.
- **The browser never sends table or column names.** Load and save run only from stored
  descriptors. This is the one safeguard kept after the user chose "any table"; it is
  stated in devdoc 2601 §5.2. If it is removed, any logged-in user can read and write any
  table through developer tools.
- **Resizing:** only fixed-pixel panes get a drag handle. paneforge (`ui/resizable`) sizes
  in percentages, so it was not used. In the seed, `middle.resizable: true` therefore has
  no effect.
- **Native `<select>` and `<dialog>`** instead of bits-ui select and dialog (simpler; other
  ChenWeb dialogs are native).
- **Field errors are codes** (`required`, `max_length`, `pattern`, `format`), translated in
  the browser (`web/src/lib/wpi/text.ts`).
- **The validator is strict:** unknown attributes are errors. That is why the planned
  `panel_retention` and `every_seconds` appear only in prose in devdoc 2601 §4.
- **Closing a panel shows the most recently shown remaining panel** in that pane, a "back"
  behaviour nobody specified. Panels are kept in recency order in `panels.ts`.
- **PUT validates structure only**, not references, so descriptors can be written in any
  order. The bundle request reports dangling references.
- **Database value errors** (PostgreSQL error classes 22 and 23) become 400 "The database
  rejected the values"; other errors are 500, with details only in the log.

## 6. What was deliberately not built

From devdoc 2601 §8: timed refresh, panel age-out, editable lists, records passed into
lists, refreshing a visible list after a save elsewhere, paging and non-equality filters,
conflict detection, embedding apps in pages, Collapse, user-defined templates, page state,
conditions, sequences, i18n of descriptor text, LLM-generated descriptors. Also: no
descriptor editor UI, no ChenWeb menu entry for WPI apps (because of the i18n gap), no
per-action permissions, no `kb.page_def` registration.

## 7. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb
go test ./server/api/wpi/                 # includes TestSeedCustomerAdminIsValid
openspec validate wpi-pilot --strict
cd web && bun test src/lib/wpi && bun run check   # 25 tests; svelte-check + i18n
```

Live database checks use `PG*` variables only (never credentials on the command line):

```bash
cd ~/Workspace/ChenWeb && mise exec -- sh -c 'PGHOST=$PG_HOST PGPORT=$PG_PORT PGUSER=$PG_USER_NAME \
  PGPASSWORD=$PG_PASSWORD PGDATABASE=$PG_DB_NAME psql -X -c "select kind, count(*) from kb.wpi_descriptors group by kind"'
```

**Browser end to end without a login.** Local files in `ChenWeb/.cache/wpi-e2e-server/`,
git-ignored and never committed:

1. `main.go`: Echo on `127.0.0.1:18090` serving the real `wpi.Handler` with a stand-in
   user, connected to the project database.
2. `wpi_e2e.py`: a Playwright script that opens `http://localhost:5173/wpi/customer-admin`
   (the ChenWeb vite dev server), routes `**/api/v1/wpi/**` to port 18090, and asserts
   checks 9.2–9.5 plus the leave warning.

```bash
cd ~/Workspace/ChenWeb
mise exec -- go build -o .cache/wpi-e2e-server/server ./.cache/wpi-e2e-server
mise exec -- ./.cache/wpi-e2e-server/server &      # stop it afterwards
python3 .cache/wpi-e2e-server/wpi_e2e.py /tmp      # screenshots go to the given dir
```

The script **inserts a customer and changes bob's email**. Clean up afterwards:
`delete from kb.wpi_demo_customers where email like '%@wpi-test.local';` and
`update kb.wpi_demo_customers set email='bob@example.com' where id=2;`.

## 8. Traps for the next session

- **The project's Paraglide base locale is `zh-cn`.** Without a `PARAGLIDE_LOCALE` cookie
  the interpreter's own text is Chinese; set `PARAGLIDE_LOCALE=en` for English assertions.
  Also, "未保存的更改" occurs inside the dialog body sentence, so locate the title with
  `exact=True`.
- **No test login.** Don't drive the user's everyday Chrome (it listens on port 9222); use
  the stand-in backend above.
- **Vite ports:** ChenWeb's dev server is `:5173`; `:5174` belongs to another project. The
  Go server is `:8080` and requires a session for `/wpi/...`.
- **Migrations:** air watches only non-test `server/**/*.go`, so a new `.sql` migration is
  applied at the next server restart. To apply one now:
  `cd server/cmd/doc-service && mise exec -- go run . --migrate-only`.
  `mise doc-service-migrate` from the repo root fails (it reads `../../../config.toml`); this
  was already broken before this session and was not fixed. Dry-run any seed migration in
  `BEGIN; … ROLLBACK;` first, because a broken migration stops the server at startup.
- **Adding an element type, attribute or action touches three places:** `server/api/wpi`
  (`types.go`, `validate.go`, and `bundle.go` if it references other descriptors),
  `web/src/lib/wpi/types.ts`, and a registry (`elements/index.ts`, `layouters/index.ts`,
  `templates/index.ts`).
- **A string that starts with `$` is a reference.** A literal `$5` in a descriptor fails
  validation.
- **jj:** commit with explicit paths. KnowledgeStore's working copy holds the user's own
  uncommitted files (research report 2602, three images under `Images/`, a moved design
  doc, devdoc 2026102302, the October diary); never include them.
- **Never point `TEST_DATABASE_URL` at `miner`.** The WPI tests use sqlmock only.

## 9. Where to resume

1. **Archive the change** when the user agrees: `/opsx:archive wpi-pilot`. Its four specs
   move to `ChenWeb/openspec/specs/`, and devdoc 2603 already names those paths.
2. **Next-phase candidates** (devdoc 2601 §9, ordered by what the pilot exposed). Let the
   user choose:
   - updating visible pages after a save elsewhere (an event such as "record saved");
   - an ADR for translating descriptor text, which unblocks a ChenWeb menu entry;
   - a way to browse, edit and preview descriptors;
   - timed refresh and panel age-out;
   - more element types (checkbox, date, textarea) and editable lists.
3. **Worth proposing:** turn the end-to-end script into a committed test once ChenWeb has
   a test login or a test-only auth bypass, then delete `.cache/wpi-e2e-server/`.
