# `kb.pipelines` vs `kb.pipeline_policies` — schema semantics Q&A ahead of a pipeline-policy management frontend

Date: 2026-08-10

Status: open — discussion only, no code changed in this session. Captured ahead of building
a frontend page to let users create and manage pipeline policies (replacing
`config.local.toml`-driven bootstrapping as the primary authoring path).

Scope: `kb.pipelines`, `kb.pipeline_policies`, `kb.pipeline_bindings`, `kb.pipeline_rules`.
Code read: `server/api/doc-processing/{policy_compile.go,policy_seed.go,policy_promotion.go,
pipeline_registry_store.go}`, `server/api/kbhandler/{pipeline_policies_handler.go,
pipelines_handler.go}`, migrations `20260731000004/11/12/13`, `20260801000023`,
`20260809000001`. Related: ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md`
§3.7 DR6.

---

## Summary

A conversation walking through what `kb.pipelines` and `kb.pipeline_policies` actually store,
prompted by the user preparing to build a frontend CRUD page for pipeline policies. Landed on
one agreed schema change (add `kb.pipeline_policies.description`), one settled non-change
(`config.local.toml` stays a one-time bootstrap path, not removed), one confirmed-by-evidence
technical fact (the policy `checksum` is a whole-table hash recomputed from live state, not a
snapshot), and one genuinely open design question (`kb.pipelines` rows are mutable in place
with **no audit trail at all** — worse than the "add-only" restriction the user assumed exists;
no such restriction was found in code).

---

## Q1 — Is `source_ref` a reference to anything? What should a frontend "create policy" form prompt for?

**Finding.** `source_ref` has no FK and no uniqueness constraint. Tracing every writer:

| Writer | Value | Nature |
|---|---|---|
| bootstrap migration (`20260731000011`) | `'bootstrap'` | machine tag |
| `SeedDocProcessingPolicies` (`policy_seed.go:96`) | `'doc-processing-policy-seed'` | machine tag |
| `EnsureDraftFromModuleRelease` (`policy_promotion.go:93-95`) | `'module_release:<id>'` | machine tag, **also used as an idempotency lookup key** (`WHERE source_ref = $1`, `policy_promotion.go:71`) |
| `POST /kb/pipeline-policies` (`pipeline_policies_handler.go:174-189`) | caller-supplied, unvalidated | free text |

So it's two purposes wearing one column: a stable machine-written provenance/dedup tag on
automated paths, and unconstrained free text on the one human-facing path. That's functionally
a description, not a reference.

Separately found: `CreatePipelinePolicy` also accepts a client-supplied `checksum` directly
(`pipeline_policies_handler.go:174-176,184-189`). `checksum` is a server-computed content hash
(see Q5) — a human has no meaningful value to type there, and it should not be a form field.

**Decision (agreed).** Add `kb.pipeline_policies.description` (mirrors `kb.pipelines.description`,
added in `20260809000001`). The frontend create-policy form prompts for **Description**, not
"Source Ref." `source_ref` stays machine-only provenance; the frontend never sets it. `checksum`
is never a form field — the server always computes it.

**Still owed.** Migration to add the column; drop `source_ref`/`checksum` from the
`CreatePipelinePolicy` request payload; frontend form field.

---

## Q2 — Future of `config.local.toml` / `doc-processing-policy-seed`

**Settled.** Stays as a one-time bootstrap path. Not removed, not deprecated. The frontend
becomes the primary day-to-day authoring surface going forward; the TOML seed tool is not
touched by this work.

---

## Q3 — "I have no idea what the active policy is" (production `miner`, not `chenweb_test`)

The first pass of this discussion queried `chenweb_test`, where there is exactly one
`kb.pipeline_policies` row (`id=1`, bootstrap, active, zero bindings) — genuinely empty
scaffolding, which is a `chenweb_test`-only artifact, not representative.

Re-queried the actual production database, `miner`:

```
 id | version |  status  |         source_ref         | activated_by
----+---------+----------+-----------------------------+-----------------------------
  1 |       1 | archived | bootstrap                   | system
  2 |       2 | archived | doc-processing-policy-seed  | doc-processing-policy-seed
  3 |       3 | archived | doc-processing-policy-seed  | doc-processing-policy-seed
  4 |       4 | active   | doc-processing-policy-seed  | doc-processing-policy-seed
```

Four rows, three archived, one active — matching what the user reported. `kb.pipeline_bindings`
for policies 2/3/4 each has exactly 2 rows:

```
policy_id | binding_kind  | ks_store_id |      name      |     pipeline_name
----------+---------------+-------------+-----------------+-----------------------
        2 | store_default |    (null)   | system-default  | no-entities-relations
        2 | store_default |      4      | store:Research  | all
        3 | store_default |    (null)   | system-default  | no-entities-relations
        3 | store_default |      4      | store:Research  | all
        4 | store_default |    (null)   | system-default  | no-entities-relations
        4 | store_default |      4      | store:Research  | all
```

So on `miner` the policy rows are not opaque — each one resolves to a real, inspectable pair of
bindings. The opacity the user first saw was specific to the empty `chenweb_test` fixture state,
not a structural property of the table. (The "no description, no way to know why we have this"
complaint from Q1 still applies on `miner` too — `description` is still worth adding.)

---

## Q4 — Is `kb.pipelines` actually append-only / immutable? Is "add processors but not delete" a real restriction?

The user pushed back on the earlier claim (paraphrased from the ADR: "there is deliberately no
update/delete on the policy row itself... a versioned, append-only audit trail") — correctly
noting that claim was about `kb.pipeline_policies`, not `kb.pipelines`, and asking to confirm
whether `kb.pipelines` itself is mutable, and specifically whether edits are restricted to
additive-only (add processors, not remove them).

**Finding: no such restriction exists.** `UpdatePipeline` (`kbhandler/pipelines_handler.go:199-310`,
routed at `PUT /kb/pipelines/:id`, `routes.go:437`) replaces the entire `processors` array with
whatever the caller sends — `case "processors": ... addSet(field, pq.Array(*value))` — additions,
removals, or a completely different list are all accepted identically. `DeletePipeline`
(`routes.go:438`) removes the row outright (subject only to the FK from `kb.pipeline_bindings`,
which would block deleting a currently-referenced pipeline, not a historical one). Neither handler
calls `writePolicyAuditEvent` or any other audit hook — confirmed against
`server/api/ontology/policyaudit/store.go:22-35`'s full event-kind list, which has
`EventBindingAuthored` and `EventRuleAuthored` but nothing for pipeline create/update/delete.

So the real situation is stricter than what the user was pushing back on: it isn't "add allowed,
delete disallowed" — it's **fully mutable, in both directions, with zero audit trail**, and the
`kb.pipelines` table has no version column or history table at all.

**Corroborating evidence from `miner`:** pipelines `id=4` ("all") and `id=5`
("no-entities-relations") — the two pipelines policies 2/3/4 all bind to — show
`create_time = 2026-08-08 10:38:25` (when policy 2's seed run first created them) but
`modify_time = 2026-08-09 09:57:59` (matching policy 4's seed run, a day later). `policy_seed.go`'s
`upsertDocProcessingPipeline` runs an unconditional `UPDATE ... SET ... modify_time = NOW()` on
every re-run regardless of whether the content actually changed, so this alone doesn't prove the
processor lists differed between policy version 2 and version 4 — but it does confirm there is no
mechanism that would let anyone find out either way. If policy 2 is ever inspected later ("what did
this archived policy actually do"), its bindings point at pipeline rows `4`/`5` by id, and those
rows only ever reflect current content — there is no way to reconstruct what they contained when
policy 2 was active.

**Open question (not resolved this session).** Two internally-consistent models exist; the current
state is neither:

- **A — Immutable, git-like.** `kb.pipelines` rows are frozen once referenced by any activated
  policy. Any edit (add or remove a processor) creates a new row/version; add a `version` column
  (or a new row with the same `name` and an incremented version) rather than mutating in place.
  Old policies remain exactly reconstructable forever.
- **B — Mutable, audited.** Keep in-place edits (both additive and destructive), but write an
  audit event for every `kb.pipelines` create/update/delete — same mechanism
  `EventBindingAuthored`/`EventRuleAuthored` already use — so there's a trail even without
  versioning.

The user's framing: pick one. An asymmetric "can add, can't remove" rule was never actually
implemented and isn't being proposed as the fix — it was a misreading of the current (accidental,
not designed) state, now corrected.

**Still owed.** Decide A vs. B before or alongside building the frontend's pipeline-edit UI —
the UI's shape differs materially (a "new version" action vs. an in-place "save" that also emits
an audit event).

---

## Q5 — What does `kb.pipeline_policies.checksum` actually hash, and does any `kb.pipelines` change invalidate every policy's checksum?

**Confirmed: yes**, with a specific mechanism. `CompilePolicy` (`policy_compile.go:46-168`) hashes
`sha256(json{policy ID, policy version, pipelineList, bindings, gates})`. Critically,
`loadDefinition` (`policy_compile.go:228-272`) populates `pipelineList` from:

```sql
SELECT name, display_name, processors, legacy_equivalent
FROM kb.pipelines ORDER BY name FOR SHARE
```

— **every row in the table**, not scoped to the pipelines this specific policy's bindings
reference. `bindings`/`gates` *are* scoped to `policy_id`. So recomputing the checksum for
**any** policy — even one whose bindings never touch the changed pipeline — after **any** edit
to **any** `kb.pipelines` row (add, edit, or delete a pipeline anywhere in the table) produces a
different hash than before. The user's "any change to `kb.pipelines` invalidates all policies" is
correct as stated.

**What value this actually adds — narrower than it looks.** `CompilePolicy` is called from exactly
two places, both inside the same request: `ActivatePipelinePolicy` compiles once at request start
(`pipeline_policies_handler.go:227`), then recompiles inside the transaction after taking
`FOR UPDATE`/`FOR SHARE` locks (`recompilePipelinePolicyInTx`, line 255), and rejects activation if
the two checksums disagree (line 260-265) or if a checksum already stored on the row disagrees
(line 263-264). That's the entire consumption of `checksum` in the codebase — grepped for every
`CompilePolicy(` call site; there are three, and all three are `policy_seed.go`'s own
compile-then-activate, or this same activate-handler pair. **Nothing ever recomputes and compares
an already-activated or archived policy's checksum against later state.** So despite looking like
a content-addressed fingerprint that would let you verify "does archived policy 2 still match what
`kb.pipelines` looked like back then," it does not and cannot serve that purpose — the value it
actually adds is a same-request optimistic-concurrency guard (detect a concurrent edit to
pipelines/bindings/gates between compile and commit of one activation), nothing more. This
reinforces the Q4 gap: the checksum is not, and was never meant to be, the audit mechanism that
would answer "what did this policy really do historically" — and no other mechanism fills that
role today.

**Still owed.** No action agreed this session. Worth deciding, alongside Q4: if pipelines become
immutable/versioned (option A), the checksum's whole-table scope stops being a problem (old
`kb.pipelines` rows never change, so recomputing an old policy's checksum would still match). If
pipelines stay mutable (option B), the checksum should probably be re-scoped to only the
pipelines this policy's bindings actually reference, since hashing the whole table is currently
both wasteful (any unrelated pipeline edit "invalidates" unrelated policies for zero reason) and
not aligned with what a human would expect "did policy 2's world change" to mean.
