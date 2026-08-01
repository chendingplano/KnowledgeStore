# SemOS Ontology — Content Model, Compiler, and Release Workflow

**Status:** built (P2 chunks A–F, 2026-08-01). **Storage:** data lives in the database; no data-only repository (2026-07-31 storage decision, ADR `2026072901` DR2/DR17 revision).

## What this is

SemOS's governed ontology: versioned terms, labels, axioms, and mappings in `kb.*`, authored as data and activated through the module compiler. This capsule is the "how to use" for the content model, the `ontology-compiler`/`ontology-seed`/`qudt-import` tools, and the release lifecycle.

## Content tables and lifecycle

| Table | Holds | Versioning |
|---|---|---|
| `kb.ontology_terms` | governed terms (`term_kind`: class/property/individual/concept/metric_definition/quantity_kind/unit/dimension) | `UNIQUE(term_id, version)`; an accepted change inserts a new version row |
| `kb.ontology_term_labels` | language labels (`label_role`: prefLabel/altLabel/hiddenLabel); one prefLabel per term+language | per-term version |
| `kb.ontology_axioms` | compiler-approved axiom kinds over governed term refs | per-axiom version |
| `kb.ontology_mappings` | mappings to governed terms or external IRIs (`relation`: exact/close/broad/narrow/related); exact requires approval | per-mapping version |
| `kb.ontology_candidates` | proposals (LLM/import/discovery); spec §9.3 state machine | `fingerprint` UNIQUE (dedup) |

Lifecycle: `discovered → draft → in_review → approved → included_in_release` (plus rejected/deferred/superseded). **No LLM path activates content** — `included_in_release` is set only by the module release path.

## Module releases

- `kb.ontology_modules` — module identity + declared dependencies.
- `kb.ontology_module_releases` — immutable release (payload snapshot + content checksum + pinned dependency releases).
- `kb.ontology_active_releases` — activation pointer; at most one active release per module; rollback re-points, deletes nothing.

The compiler validates a module's approved content, snapshots it, checksums it, writes the immutable release, tags the included content rows `included_in_release`, marks the promoted candidates, and supersedes the module's prior release — all in one transaction. A failed validation leaves the previous active release untouched.

## Tools

| Tool | Purpose |
|---|---|
| `mise run ontology-compiler ...` | compiler CLI: `validate` / `release` / `activate` / `rollback` / `modules` / `active` |
| `go run ./server/cmd/ontology-seed` | author the curated 4a vocabulary (`core`, `document-authority`, `measurement`); `--author-only` to skip release |
| `go run ./server/cmd/qudt-import` | import the QUDT catalog into `quantity` from the published TTL files |

DB via `PG_HOST`/`PG_PORT`/`PG_USER`/`PG_DB_NAME` (defaults: local socket `/tmp`, user `cding`, `chenweb_test`).

## Authoring a term as data (no code change)

1. Author content (direct `kb.ontology_terms` insert, a candidate→promote, or a seed tool).
2. `mise run ontology-compiler release --module <id> --version <v>`
3. `mise run ontology-compiler activate --module <id> --release-id <n>`

Installing a domain module never requires a processor, normalizer, or API change (the DR1 property).

## Canonicalization kernel

`server/api/ontology/semid` implements the DR15 kernel (normalizers → candidates → scoring → adjudication → merge/split with tombstones → audit) with a family-adapter interface. The ontology-term family is the first instantiation (governed — adjudication ends at a change set, never an auto-accept). `semrules` (`server/api/ontology/semrules`) is the DR3 predicate-evaluator seam; operators register through `RegisterOperator`.

## Related documents

- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (DR1–DR25, P0–P7)
- Spec `2026072702-spec-ontology-canonical-artifacts.md` (§9 lifecycle, §16 acceptance)
- P2 plan `2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel.md`
- P2 implementation log `2026073105-devdoc-semos-p2-implementation-log.md`
