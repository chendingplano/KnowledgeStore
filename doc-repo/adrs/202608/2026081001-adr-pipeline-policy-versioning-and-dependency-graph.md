# ADR 2026081001 — Pipeline Redesign: Git-Like Versioning, a Persisted Processor DAG, and Retiring `kb.pipeline_policies`

**Date:** 2026-08-10 \
**Status:** Accepted — implemented \
**Component:** ChenWeb — `kb.pipelines`, `kb.pipeline_bindings`, `kb.pipeline_rules`, `kb.pipeline_policies` (retired by this ADR), `kb.processor_registry` (new), `server/api/doc-processing/{policy_compile.go,policy_seed.go,processor_plan.go,runtime.go,pipeline_bindings.go,pipeline_gates.go,pipeline_version_validate.go,processor_dependency_registry.go,routing_clearance.go,routing_enforcement.go,control.go,pipeline_selection.go,policy_promotion.go}`, `server/api/kbhandler/{pipelines_handler.go,pipeline_bindings_handler.go,pipeline_rules_handler.go,pipeline_routing_clearances_handler.go,pipeline_reload.go}` (the `pipeline_policies_handler.go`/`pipeline_policies_store.go` this ADR named for retirement are deleted), `server/api/ontology/policyaudit/store.go` \
**Authors:** Chen Ding (with Claude) \
**Tags:** pipeline routing, doc-processing, schema redesign, versioning, DAG, processor dependencies

## 1. Change Logs

* 2026/08/10, ADR created. Reviews eight proposed changes to `kb.pipelines`/
  `kb.pipeline_policies` against the current implementation
  (`2026081001-bug-pipeline-policies-vs-pipelines-schema-review.md`).
* 2026/08/10, full revision. A Q&A pass surfaced that `kb.pipeline_policies`
  is never consulted at runtime as anything more than a status filter
  (confirmed against every call site), that the real gap is a *persisted,
  per-pipeline* processor DAG rather than a per-policy one, and that the
  `defer` gate effect should become a creation-time error rather than a
  runtime-recoverable state. This revision replaces the original DR2–DR11
  with the converged design: `kb.pipeline_policies` is retired outright
  (not merged, not kept for compatibility), `kb.pipeline_rules` gains real
  DAG edges, and processor dependency metadata adopts incrementally
  (existing processors stay hardcoded; only new ones move to the database).
* 2026/08/10, implemented via OpenSpec change `ChenWeb/openspec/changes/
  pipeline-versioning-dependency-graph/` (design.md/specs/tasks.md). DR1–DR9
  are all live: `kb.pipelines` is versioned/immutable with atomic per-version
  authoring and closure/DAG/gate-fact validation
  (`pipeline_version_validate.go`); `kb.pipeline_policies` is dropped (`miner`
  backfill discarded the 3 archived-policy rows per §3.3's "data decision,"
  kept the active policy's 2 bindings/rules); `defer` is unstorable
  (CHECK constraint + creation-time validator) and
  `resolveIndeterminateGate`'s fallback branch is gone -- an indeterminate
  gate now hard-fails in every conflict mode, not just `block`. The real
  implementation surface was larger than this ADR's Component line
  originally scoped: every `policy_id`/`PolicyID`/`PolicyVersion` call site
  across the D2 routing-clearance/enforcement subsystem
  (`routing_clearance.go`, `routing_enforcement.go`,
  `pipeline_routing_clearances_handler.go`, plus the `kb.pipeline_routing_clearances`/
  `kb.pipeline_routing_clearance_coverage`/`kb.pipeline_policy_events` schemas),
  `control.go`'s plan-fact/alarm/audit-event plumbing, `pipeline_selection.go`,
  `policy_promotion.go` (module-release promotion now authors inactive
  conditional bindings directly, `active=false` standing in for the retired
  draft-policy envelope), and the binding/rule CRUD handlers all needed the
  same policy→pipeline-provenance rekey, confirmed via full-repo grep before
  and after. One design decision the ADR left implicit was resolved during
  implementation and should be reviewed: DR8 check 3 (gate-fact availability)
  needed a concrete fact→producer mapping the ADR doesn't specify: baseline
  routing facts (the four `document.*` fields known before any processor
  runs) are always available, and every other fact requires an upstream
  processor whose `Produces` includes the coarse `"facets"` artifact kind --
  the same granularity check 1 already uses, applied to document facts
  instead of processor outputs. `go build`/`go vet`/`go test ./...` are clean
  workspace-wide (pre-existing unrelated failures unaffected, confirmed via
  `git stash` diffing).

## 2. Context

`2026081001-bug` found `kb.pipelines` fully mutable with no audit trail, and
`kb.pipeline_policies.checksum` hashing the whole `kb.pipelines` table on
every compile without ever being re-checked after activation. The first
draft of this ADR proposed fixing both, plus making the active policy map
1:1 to one pipeline. A review pass then asked, concretely: what *is* a
policy, why does it map to more than one pipeline today, and is that
richness actually used anywhere at runtime?

Checked directly: every runtime read of `kb.pipeline_policies` has the same
shape —

```sql
-- pipeline_bindings.go:125, pipeline_gates.go:253,
-- pipeline_rules_store.go:35, extract-doc-metadata-store.go:68
WHERE b.active AND b.policy_id = (SELECT id FROM kb.pipeline_policies WHERE status = 'active' LIMIT 1)
```

`kb.pipeline_policies` is consulted only as a `WHERE`-clause filter picking
which bindings/rules are "live," never as an object with its own routing
behavior — and `kb.pipeline_bindings`/`kb.pipeline_rules` already carry their
own independent `active` column, making the policy-level filter redundant
with something that already exists per row. `ActivePolicyID`/`ActivePolicyVersion`
(`processor_plan.go:78`) are pure audit provenance ("which generation was
live when this ran"), never consulted for a routing decision. So the
"system-wide routing table, versioned as one unit" concept — the reason one
policy could point at multiple pipelines — turned out not to be load-bearing
anywhere. This ADR retires it rather than preserving it in a 1:1-narrowed
form.

Separately, a second gap surfaced: the processor dependency graph
(`extract_metrics` needs `chunking`'s output, etc.) exists only as a
hardcoded Go literal (`productionProcessorSpecs`, `processor_plan.go:421-439`),
and its own doc comment admits the fields meant to drive real ordering
(`Requires`/`Produces`) are declared but **not yet consumed by any planner**.
Today's execution order is a fixed Phase-A/B/C bucket concatenation, not a
dependency-ordered sort. This ADR fixes that by putting real, validated
dependency edges into `kb.pipeline_rules` itself.

## 3. Decision

### 3.1 DR1 — `kb.pipelines` becomes immutable and versioned, on processor-set changes only

Add `kb.pipelines.version INT NOT NULL DEFAULT 1`; replace the bare
`UNIQUE (name)` constraint (`20260731000004`) with `UNIQUE (name, version)`.
Editing `processors[]` never runs `UPDATE` on an existing row again — it
inserts a new row, same `name`, `version = MAX(version WHERE name = $1) + 1`.
`display_name`/`description` are cosmetic and stay mutable in place on
whichever row is current — they do not trigger a new version (confirmed
scope, per review).

Add `kb.pipelines.status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status
IN ('active','superseded'))`. `DeletePipeline`'s current hard-`DELETE`
semantics (`kbhandler/pipelines_handler.go:312-339`) are removed — a version
that is immutable can't also be deletable out from under whatever binding
still points at it (`kb.pipeline_bindings.pipeline_id` is `ON DELETE
RESTRICT` today and should stay that way). Creating version N+1 marks
version N `superseded`; nothing physically deletes a pipeline row.

### 3.2 DR2 — a pipeline version is authored atomically, in one transaction, and is never incrementally edited afterward

Creating a new pipeline version means: insert the `kb.pipelines` row, insert
every `kb.pipeline_rules` row for its processors (including the DAG edges
from DR6 and the gates from DR5), validate everything (DR8), and commit — all
in one transaction, all at once. There is no separate `PUT`/`POST` path that
adds a rule to an *already-created* version afterward; "I want to change
something" always means "author a new version," never "mutate this one."
This is what makes DR8's create-time-only validation sufficient — there is no
window after creation in which content could still change, so nothing needs
re-validating later (this also removes the concurrency concern the original
draft raised around `kb.pipeline_policies.checksum`, which no longer exists
per DR3).

### 3.3 DR3 — retire `kb.pipeline_policies` entirely

Per §2's evidence: nothing at runtime needs a separate versioned "system-wide
snapshot" object — every consumer only ever wanted "is this row currently
live," which `active` already answers per-row. Concretely:

- `DROP TABLE kb.pipeline_policies` (and `CreatePipelinePolicy`/
  `ActivatePipelinePolicy`, `pipeline_policies_handler.go`, entirely).
- `kb.pipeline_bindings.policy_id` / `kb.pipeline_rules.policy_id` columns
  drop. The four `WHERE ... policy_id = (SELECT ... active ...)` filters
  (§2) simplify to `WHERE active`.
- The uniqueness DR3 removes (`kb.pipeline_policies` guaranteed at most one
  *system-wide* active row) is replaced by a **per-binding-target**
  constraint directly on `kb.pipeline_bindings`, restoring the spirit of the
  original pre-policy constraint (`UNIQUE (ks_store_id)`,
  `20260731000006`, later widened to `(ks_store_id, policy_id)` when
  multi-version bindings arrived): a partial unique index scoped to the
  binding's own scope columns and `binding_kind = 'store_default'`, e.g.
  `ON kb.pipeline_bindings (COALESCE(ks_store_id,-1), COALESCE(user_id,''),
  COALESCE(tenant_id,''), COALESCE(input_record_id,-1)) WHERE active AND
  binding_kind = 'store_default'` — at most one *active* unconditional
  binding per context, full stop, no separate table needed to express it.
- `ActivePolicyID`/`ActivePolicyVersion` provenance (`processor_plan.go:78`,
  recorded on execution plans and alarm events) is replaced by recording the
  winning `kb.pipeline_bindings.id` and the resolved `kb.pipelines.name` +
  `version` directly — strictly more precise than a generic policy version
  number, since it names the actual pipeline used rather than an opaque
  system-wide counter.

**Migration risk, called out explicitly:** `miner` currently has 4
`kb.pipeline_policies` rows, and the active one's 2 bindings/rules carry a
real `policy_id`. The migration needs to backfill: keep the *currently
active* policy's bindings/rules (drop their `policy_id`, set `active` per
their existing value), and either discard the 3 archived policies' rows or
move them to a plain audit/history table if that lineage is worth keeping
for its own sake — that's a data decision, not an architecture one, and is
not resolved by this ADR.

### 3.4 DR4 — `kb.pipeline_bindings`: context → pipeline, corrected scope explanation

A binding answers "for a request arriving in *this context*, which pipeline
processes it?" Context is one of: the whole system by default (no scope
column set), one specific knowledge store, one specific user, one specific
tenant, or one specific document — which kind a given row is isn't a
separate label, it's read off of which of `ks_store_id`/`user_id`/
`tenant_id`/`input_record_id` is populated (`policy_compile.go:286-290`'s
`CASE` expression). `binding_kind` separately says whether the binding is
unconditional (`store_default`, one per context) or predicate-gated
(`conditional`, prioritized — the mechanism `EnsureDraftFromModuleRelease`
uses to materialize approved ontology-module proposals as routing overrides).
None of this changes under this ADR; `pipeline_id` already points directly
at `kb.pipelines` (always has), so DR3's retirement of the intermediate
policy layer is a clean removal, not a rewire.

### 3.5 DR5 — `kb.pipeline_rules`: the per-processor gate layer (should this processor run at all)

Confirmed, not the DAG. A rule row (`target_processor`, `effect`
∈ `{require,enable,skip}`, `predicate` over document facts) is an isolated
per-processor on/off decision — no edges, no ordering. The `predicate`
mechanism already supports arbitrary conditional logic (`semrules.Document`,
analyzed for required facets and overlap conflicts at compile time,
`policy_compile.go:106-129`); nothing has ever authored a non-trivial one —
every seeded rule uses the vacuously-true predicate
(`policy_seed.go:31-37`). No schema change here; conditional gate authoring
is future frontend work, not a mechanism gap.

### 3.6 DR6 — `kb.pipeline_rules` gains real DAG edges: `depends_on_processors`

This is the actual fix for the missing dependency graph. Add
`kb.pipeline_rules.depends_on_processors TEXT[] NOT NULL DEFAULT '{}'` —
names of sibling processors, within the same pipeline version, that must
finish successfully before `target_processor` runs. Orthogonal to
`predicate`/`effect` (which govern *whether* a processor runs; this governs
*when*, relative to other processors already selected to run). Worked
example, three processors A, B, C where C needs A's output:

```
R1: target_processor='A', depends_on_processors='{}'
R2: target_processor='B', depends_on_processors='{}'
R3: target_processor='C', depends_on_processors='{A}'
```

This is what a real execution-order engine should consume (a topological
sort over these edges) in place of today's fixed Phase-A/B/C bucket
concatenation (`ProductionProcessorPlan.ExecutionOrder()`,
`processor_plan.go`). **Building that execution engine is out of scope for
this ADR** — this ADR fixes where the dependency data lives and how it's
validated (DR8); wiring the runtime processor loop to actually walk it in
topological order is follow-on implementation work.

### 3.7 DR7 — processor `Requires`/`Produces`: incremental adoption, existing processors stay hardcoded

No migration of `productionProcessorSpecs` (`processor_plan.go:421-439`).
Every processor already declared there stays exactly as-is, in Go, untouched.
New:

```sql
CREATE TABLE kb.processor_registry (
    name             VARCHAR(128) PRIMARY KEY,
    phase            VARCHAR(1) NOT NULL,          -- A | B | C
    class            VARCHAR(16) NOT NULL,         -- mandatory | routed | on_demand
    cost             VARCHAR(16) NOT NULL,         -- free | cheap_llm | expensive_llm
    on_undetermined  VARCHAR(8) NOT NULL DEFAULT 'run',
    idempotent       BOOLEAN NOT NULL DEFAULT false,
    requires         TEXT[] NOT NULL DEFAULT '{}', -- artifact kinds needed as input
    produces         TEXT[] NOT NULL DEFAULT '{}', -- artifact kinds emitted
    create_time      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    modify_time      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Only **new** processors, going forward, get a row here instead of a new line
in the Go literal. Anything that needs the full dependency picture (DR8's
validator; a future execution planner) reads the **union** of the Go literal
and this table — old processors resolve from Go, new ones resolve from the
table, neither side needs to know the other exists.

### 3.8 DR8 — validate at creation/modification time only; hard-reject; never re-check at runtime

Per DR2, a pipeline version's content can't change after creation, so
validation happens exactly once, when the version is authored, and never
again. Three checks, all fail-closed (reject the whole creation, name the
specific violation):

1. **Processor closure.** For every processor `P` in the version's
   `processors[]` and every artifact kind `A` in `P.Requires` (from DR7's
   union), some processor `Q` in the same set must have `A` in `Q.Produces`
   (or be one of the always-run baseline processors, `static_analyzer`/
   `chunking`).
2. **DAG well-formedness.** `depends_on_processors` (DR6) edges must form an
   actual DAG (no cycles), and every name referenced must itself be one of
   the version's own selected processors — no dangling reference to a
   processor this pipeline doesn't include.
3. **Gate-fact availability (new, folds in DR9 below).** For every
   `kb.pipeline_rules` gate's `predicate`, every document fact it references
   must be guaranteed available by the time that gate is evaluated — i.e.
   produced by some processor that the DAG guarantees has already run
   (an upstream node reachable via `depends_on_processors`, or a baseline
   processor that always runs first). If no such guarantee exists, reject
   creation and name the gate and the missing fact.

Nothing in this list is re-checked at runtime. Once a version exists, its
correctness is a proven, permanent property of that (immutable) row.

### 3.9 DR9 — retire `defer` as a runtime-recoverable gate effect

`GateEffectDefer` (`pipeline_gates.go:22,150-160`) exists today because a
gate's predicate can reference a document fact the system doesn't yet know
(e.g. a tier-3-classifier-sourced facet), and the old model had no way to
prove, ahead of time, that the fact would be known by the time the gate ran
— so it retried later instead (`DeferredPaths`/`DeferFingerprint`,
`resolveIndeterminateGate`). DR8 check 3 closes exactly that gap: if a
pipeline version passes creation-time validation, every gate's required
facts are *provably* produced by an upstream processor in the same DAG
before that gate ever evaluates — there is nothing left to defer.

**Decision.**
- **At creation/modification time:** if DR8 check 3 would fail — a gate
  references a fact with no guaranteed upstream producer — reject pipeline
  creation with an error naming the gate and the missing fact, prompting the
  author to fix the pipeline (add the missing processor as a dependency, or
  remove/rewrite the gate). `effect = 'defer'` is no longer something a
  valid, saved pipeline version can contain.
- **At runtime:** if the gate resolver ever still produces a
  defer/indeterminate outcome anyway (it shouldn't, once every live pipeline
  version has passed DR8 — this is a safety net, not an expected path),
  treat it as a hard processing failure for that record's run (raise an
  alarm, fail the run), not a deferred retry. `resolveIndeterminateGate`'s
  current fallback-to-`enable`/`skip` behavior and the retry-later plumbing
  around `DeferredPaths` are removed.

## 4. Consequences

- `kb.pipeline_policies` and its two handler endpoints disappear entirely —
  this is a real deletion, not a deprecation, once the `miner` backfill
  (DR3) is done.
- `kb.pipelines`/`kb.pipeline_bindings`/`kb.pipeline_rules` each gain one or
  two columns (`version`/`status`; drop `policy_id`; add
  `depends_on_processors`) — no new tables except `kb.processor_registry`.
- The routing/audit provenance recorded on execution plans changes shape
  (pipeline name+version instead of policy id+version) — anything reading
  `P5RoutingSnapshot.PolicyID`/`PolicyVersion` downstream (alarms, plan
  inspection endpoints) needs the equivalent update.
- Out of scope for this ADR, left as follow-on implementation: the actual
  topological-sort execution engine that consumes `depends_on_processors`
  (today's `ExecutionOrder()` stays a fixed phase-bucket concatenation until
  that lands); a frontend for authoring conditional gate predicates (DR5).

## 5. References

1. `2026081001-bug-pipeline-policies-vs-pipelines-schema-review.md` (`doc-repo/bugs/202608/`) — the investigation this ADR is built on.
2. `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` §3.7 DR6 (`doc-repo/adrs/202607/`) — original two-tier routing design this ADR revises in light of how it was actually built and used.
3. `ChenWeb/docs/superpowers/specs/2026-08-08-doc-processing-policy-design.md` — the `config.local.toml`-driven bootstrap seed tool, which stays as a one-time bootstrap path (prior-session decision) and will need updating to target the post-retirement schema.
