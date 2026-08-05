# Keyword Module — Review Findings

Date: 2026-08-05
Reviewer scope: `2026080403-spec`, `2026080404-spec` (addendum), `2026080501-bug`, and the shipped code in `ChenWeb/server/api/ontology/{keywords,semid}/`, `kbhandler/keyword_handlers.go`, `doc-processing/keyword_mention_collector.go`.

This document states problems and decisions. It does not re-explain the design; for that, read `2026080403-spec` §3–§11.

---

## 0. Root cause — one explanation for most of what follows

The module was built **bottom-up, one table per chunk, with no consumer at any point**. Chunk A = concept store, B = surface stores, C = mention/unresolved/rewrite stores, D = normalizer, E = family adapter, F = REST, G/H = mode + collector. Each chunk produced a complete-looking CRUD layer, and nothing above it ever called most of what the chunk below produced.

That single fact explains, without needing separate explanations: the dead code (F3), the duplicated normalizer (F1), the duplicated merge implementation (F4), the unwired collector, and the assertion-free exit tests (`2026080403-spec` §16.4). **No layer was ever forced to justify itself against a real caller.** Every remedy below is, at bottom, the same remedy: connect one real path end to end, and delete what that path doesn't need.

---

## F1 — Two normalizers exist that should be one. **Severity: high.**

**Problem.** `semid.Normalizer`'s built-in and `keywords.KeywordNormalizer` are two implementations of the same lexical operation, in two packages, with copy-pasted primitives.

**Evidence (verified, not inferred):**

- `semid/normalizer.go:collapseSpace` and `keywords/normalizer.go:collapseWhitespace` are **byte-for-byte identical logic** — same loop, same conditions, same `TrimSpace` return. The only textual difference is `WriteRune(' ')` vs `WriteByte(' ')`, which for U+0020 emit the same byte.
- The CJK-preservation threshold `0x2E80` is hardcoded independently in both files (`semid/normalizer.go:45`, `keywords/normalizer.go:250`).
- `semid`'s built-in, in full, is: `strings.ToLower` → `strings.TrimSpace` → `collapseSpace`, plus `stripPunct` only at `Version >= 2`. **That is a strict subset of steps 5 and 7 of the keyword pipeline.** It is not a different approach to normalization; it is less of the same approach.
- `NormFunc` — the extension point that exists specifically to let a family replace the built-in — has **exactly one user in the entire codebase**: `KeywordFamily`. It was added so one family could bypass a normalizer that does a subset of its own work.

**Why the "each family declares its own profile" justification fails.** Normalization is purely lexical — collapsing spelling, casing, whitespace, and punctuation variation in a human-language string. That operation depends on the **language of the string**, never on which identity family happens to be asking. A Chinese term label and a Chinese keyword surface need identical treatment. There is no property of "being a governed term" that changes what NFKC or case-folding should do. I previously argued the split might be deliberate conservatism for governed content; that argument is dead — `TermFamily.AutoAcceptPolicy{Enabled: false}` already blocks every auto-accept regardless of normalization strength, so conservative normalization buys no safety that isn't already bought, while costing candidate recall (a real duplicate term can fail to surface as a candidate at all).

**Decision.**

1. **Delete `NormFunc` and the `semid` built-in normalizer.** One normalizer implementation, in one package, shared by every family.
2. **Move the shared primitives** (`collapseSpace`, CJK threshold, NFKC, case-fold) into that one implementation. No package gets its own copy.
3. **If profiles are needed, key them on language and version — never on family.** `Normalize(s, lang, version)`, not `family.Normalizer()`.
4. `norm_version` remains the re-index trigger, unchanged.

---

## F2 — `FamilyAdapter` carries a method that isn't family-specific. **Severity: medium.**

**Problem.** The interface has five methods. `Normalizer()` is not among the things that legitimately differ per family (F1), so the interface advertises a variation point that shouldn't exist and that one family exploited to fork the implementation.

| Method | Genuinely family-specific? | Why |
|---|---|---|
| `CandidateNodes` | **Yes** | keyword queries `kb.keyword_surfaces`; term queries `kb.ontology_terms` — genuinely different data |
| `AutoAcceptPolicy` | **Yes** | ungoverned auto-accepts; governed never does |
| `Scope` | **Yes** in principle | keyword = knowledge store, term = module (both broken today — F5) |
| `FamilyName` | Metadata only | a string label for the decision log |
| `Normalizer` | **No** | F1 — lexical normalization is a property of the string, not the family |

**Decision.** Remove `Normalizer()` from `FamilyAdapter`. The kernel calls the one shared normalizer directly. This also removes the mechanism by which the two implementations diverged, so F1 cannot recur.

---

## F3 — 11 of 12 audited exported functions have zero production callers. **Severity: high.**

**Problem.** Not "some dead code" — the dominant condition of the module.

**Evidence.** Non-test call sites, counted across the whole repository:

| Function | Prod callers | What it was for |
|---|---|---|
| `MentionStore.ListMentions` | 0 | reading back mentions — nothing reads mentions |
| `MentionStore.InsertMentions` (batch) | 0 | batch insert — only the single-row version is used |
| `SurfaceKeyStore.UpsertSurfaceKeys` | 0 | **this is K1** — tiers 2/4 query a table nothing writes |
| `UnresolvedStore.ListUnresolved` | 0 | reading the backlog — no API, no worker |
| `UnresolvedStore.UpdateUnresolvedStatus` | 0 | draining the backlog — no reconciler |
| `TermFamily.ResolveCandidate` | 0 | the only path that writes `candidate_matches` |
| `semid.MergeGraph` (`NewMergeGraph`, `SetNeverMerge`, `Unmerge`) | 0 | see F4 |
| `SnapshotStore.Record` / `.Latest` | 0 | snapshots — no snapshot flow exists |
| `NeverMergeStore.IsNeverMerge` | 0 (the 1 hit is `MergeGraph` calling itself) | the guardrail nothing consults |

**Answering "why write dead code in the first place" directly** — it matters because the answer determines the remedy, and the three categories need different treatment:

1. **Speculative construction for an unbuilt consumer.** `ListUnresolved`, `UpdateUnresolvedStatus`, `SnapshotStore`, `UpsertSurfaceKeys`. Written because the plan said the reconciliation pipeline will eventually need them. This is the bottom-up build order (§0) producing a complete CRUD surface per table whether or not anything calls it. **These are not for a GUI** — no admin page exists in any plan or spec for the backlog; `2026080403-spec` §10 lists "no REST surface for the unresolved backlog" as a gap, not as a deliberate deferral to a UI.
2. **Genuinely orphaned duplicates.** `MergeGraph` (F4) — superseded by `ConceptStore.MergeConcept` before it ever had a caller.
3. **One real, load-bearing gap misfiled as dead code.** `UpsertSurfaceKeys` is not speculative — tiers 2 and 4 are *built and querying* the table it would populate. It is the missing half of a feature that is otherwise complete.

**Decision.**

- **Delete** categories 1 and 2 outright, except where a named, scheduled consumer exists in the addendum's build list. Rebuilding a CRUD method when its consumer is written costs less than carrying, testing, and reasoning about an unreachable one. Given the planned data reset, there is no migration argument for keeping any of it.
- **Wire** `UpsertSurfaceKeys` (category 3) as part of the K1 fix — it is not dead code, it is an unfinished feature.
- **Rule going forward:** no store method merges without a caller in the same change. The sqlmock tests currently make unreachable code look tested (they assert SQL shape against a mock, proving nothing about reachability), which is what let this accumulate invisibly.

---

## F4 — Merge is implemented twice; neither implementation is complete. **Severity: high.**

**Problem.** Two merge implementations exist with **disjoint** capabilities. Neither is usable alone.

| | `semid.MergeGraph` | `keywords.ConceptStore.MergeConcept` |
|---|---|---|
| Persistence | **None** — in-memory Go maps, discarded when the process exits | Postgres `UPDATE` |
| Refuses self-merge | Yes | Yes |
| Refuses `never_merge` pairs | Yes | **No** |
| Refuses already-merged source | Yes | **No** |
| Cycle-guarded chain resolution | Yes | **No** — nothing follows `merged_into` at read time |
| Production callers | **0** | the `POST .../merge` handler |

So the implementation with the guardrails persists nothing and is called by nothing; the implementation that actually runs has none of the guardrails. This is the same disease as F1 — a shared-kernel abstraction and a family implementation solving the same problem in parallel, neither aware of the other.

**Decision.** Delete `semid.MergeGraph`. Port its four guardrails (never-merge check via the persisted `NeverMergeStore`, already-merged refusal, cycle-guarded `merged_into` chase at read time, `Unmerge`) into `ConceptStore.MergeConcept` and the resolve path. One merge implementation, persisted, guarded.

---

## F5 — `TermFamily.Scope` contradicts its own comment and disables the module filter. **Severity: medium.**

**Problem.** The comment says "the term family scopes by module." The code is `func (f TermFamily) Scope(surface string) string { return "" }` — unconditional empty string. `CandidateNodes`' SQL then reads `WHERE ($1 = '' OR t.module_id = $1)`; with `$1` permanently `""`, the module filter is not merely unused, it is **structurally impossible to apply**. Every term-candidate search runs across every module.

This is K2's twin, independently present in the other family. Both families compute a real scope in their outer wrapper and use it only to label output, never to filter.

**Decision.** Fix both families together as one change: thread the caller's scope through `Kernel.Resolve` (it must become a parameter — see F6), and make each family's `Scope` either return a real value or be removed from the interface if the caller always supplies it.

---

## F6 — `Kernel.Resolve`'s signature contradicts its own behavior. **Severity: medium.**

**Problem.** `Resolve(ctx, surface) (Resolution, error)` takes one input but needs two — the scope it actually filters on is fetched behind the caller's back via `Family.Scope()`, which is exactly why K2 and F5 are invisible at every call site. A caller cannot pass a scope even if it has one; both families work around this by overwriting `res.Scope` *after* the search already ran with the wrong value.

Additionally, the parameter name `surface` is keyword-family vocabulary imposed on a family-agnostic mechanism — `TermFamily` reuses the same name for a materially different thing (an `kb.ontology_candidates` proposal, not a persisted entity with its own table).

**Decision.** `Kernel.Resolve(ctx, input string, scope string)`. Scope becomes an explicit parameter; `Family.Scope()` is deleted from the interface (F2 reduces it to `CandidateNodes` + `AutoAcceptPolicy` + `FamilyName`). Rename the parameter to `input`.

---

## F7 — `TermFamily` can never return `ambiguous`. **Severity: low, but must be stated deliberately.**

**Problem.** `AutoAcceptPolicy{Enabled: false, MinScore: 0}` leaves `MaxCandidates` at its zero value. `Adjudicate`'s tie-detection is gated on `policy.MaxCandidates > 0`, so it never fires: a five-way tie and a single clean match both return `human_review`. With `Enabled: false` also blocking `auto_accepted`, this family can only ever produce `deferred` or `human_review` — two of the four documented verdicts are unreachable.

This may be correct behavior (a governed family arguably should route everything to a human). But it is currently an accident of a zero value, not a stated choice, and a reviewer loses the "these two candidates tie" signal that `ambiguous` carries.

**Decision.** Set `MaxCandidates` explicitly. If the intent is "always human review," write `MaxCandidates: 1` so ties still surface as `ambiguous` in the record, and let the disabled policy handle the routing — the reviewer benefits from knowing *why* something needs review.

---

## F8 — The two spec documents are no longer usable as specs. **Severity: medium. I caused this.**

**Problem.** `2026080403-spec` is now 1,294 lines, with ten inline Q&A blocks embedded mid-section in §3.1, several containing corrections of my own earlier statements. A reader looking for "what is the design" must now separate design from conversation transcript. This is the "getting blurrier" problem directly, and it came from answering questions in place rather than folding conclusions into the design and recording the reasoning elsewhere.

**Decision.**

1. **Extract every `Open Question NN` block out of `2026080403-spec` §3.1.** The *conclusions* fold into the relevant design sections as plain statements; the *reasoning and corrections* move here, to the bugs/review record where they belong.
2. **§3.1 returns to being a design section** — the four layers, the persistence table, the tier-to-table map. It should be roughly its pre-Q&A length.
3. Findings F1–F7 above become the input to that rewrite, not more inline annotations.

---

## Consolidated decisions, in dependency order

| # | Decision | Blocks |
|---|---|---|
| 1 | One normalizer; delete `NormFunc` and the `semid` built-in; shared primitives (F1) | everything downstream — do first |
| 2 | `Kernel.Resolve(ctx, input, scope)`; drop `Normalizer()` and `Scope()` from `FamilyAdapter` (F2, F5, F6) | correct scope behavior in both families |
| 3 | One merge implementation: `ConceptStore.MergeConcept` + `MergeGraph`'s guardrails; delete `MergeGraph` (F4) | any reconciler that merges |
| 4 | Wire `UpsertSurfaceKeys`; delete the rest of the unreachable surface (F3) | tiers 2/4 |
| 5 | Set `TermFamily.MaxCandidates` explicitly (F7) | — |
| 6 | Restructure `2026080403-spec` §3.1; move Q&A here (F8) | readability of everything else |

Items 1–2 are one change in practice: both touch the same interface and the same call sites, and splitting them would mean editing `kernel.go`, `termfamily.go`, and `keywordfamily.go` twice.

**These supersede, where they conflict, the inline answers currently embedded in `2026080403-spec` §3.1** — specifically the conclusion that `TermFamily` should get "its own deliberately-chosen normalizer profile" (F1 replaces it: there should be one normalizer, not two well-chosen ones).
