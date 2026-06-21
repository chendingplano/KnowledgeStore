# ADR 2026061802 — Process-Wide LLM Lease And Rate Controller

**Date:** 2026-06-18 \
**Status:** Proposal \
**Component:** ChenWeb / shared/go — doc processing, LLM client concurrency and rate control \
**Authors:** Chen Ding \
**Tags:** llm, concurrency, rate limit, fallback, doc processor

---

## Change Logs
* 2026/06/18, ADR Created.
* 2026/06/19, documented the rolling one-minute throttling algorithm and burst semantics.
* 2026/06/19, updated the TPM throttling design to a 64-slot per-second bucket scheduler.

## Context

The doc-processing runtime is highly concurrent.

Within one process:

1. the controller may run up to `MAX_DOC_PROCESS_PIPELINES` pipelines concurrently,
2. each pipeline may run all configured doc processors concurrently,
3. each doc processor may launch multiple worker goroutines,
4. each worker may make one or more LLM calls, sometimes with primary/fallback retry.

The result is multiplicative fan-out. A per-processor concurrency limit such as
`EXTRACT_ENTITY_RELATION_MAX_TASKS` bounds only one local worker pool; it does not
bound total LLM concurrency for the process.

This became operationally visible in `extract-entity-relation`: when the primary
model failed, many workers retried the fallback model at once and exceeded the
provider-side concurrency quota. The failure mode was not specific to one
processor. Any processor using the same model could contribute to the same
oversubscription.

The key observation is that the scarce resource is not "chunk workers in one
processor" but process-wide provider budget for model X across the whole process.

That provider budget has at least two distinct dimensions:

1. **in-flight request concurrency**
2. **rate budget over time**
   * requests per minute (RPM)
   * tokens per minute (TPM)

The first issue surfaced as fallback-model oversubscription. The second surfaced
later when category creation hit provider TPM limits even though per-model
in-flight leasing already existed. This proved that concurrency control alone is
necessary but not sufficient.

## Decision

Introduce a **process-wide per-model lease and rate controller** for LLM calls.

### DR1 — One permit pool per resolved model name

Concurrency is controlled by resolved model name (for example
`gpt-5.4-mini`, `deepseek-v4-flash`), not by processor name, prompt, or pipeline.

All calls that use the same resolved model draw permits from the same pool inside
one process. This includes:

* primary calls,
* fallback calls,
* structured-output calls,
* plain JSON/text calls,
* embedding calls.

### DR2 — Lease semantics, not permanent ownership

Each acquired permit carries a lease timer.

* A caller must acquire a permit before making an LLM request.
* The caller returns the permit when the request finishes.
* If the caller does not return the permit before the lease expires, the permit is
  reclaimed automatically.
* If requests are waiting, the reclaimed capacity may be used immediately by the
  next waiter.

This prevents a stuck goroutine, abandoned context, or leaked request path from
holding model capacity forever.

### DR3 — Request-rate and token-rate pacing

Before issuing an LLM chat / structured-output request, the shared client must
also pass through a process-wide rate scheduler.

The scheduler enforces both, on a per-model basis:

* **requests per minute**
* **tokens per minute**

Token budgeting uses a conservative estimate derived from the prompt text, input
text, and a configurable per-call reserve for completion/output tokens. Exact
provider token accounting is not required for the scheduler to be useful; the
goal is to prevent predictable local stampedes into provider 429s.

Embedding calls already had process-wide RPM/TPM pacing. This ADR extends the
same control model to non-embedding LLM requests.

### DR3.1 — Throttling algorithm

The scheduler is **burst-tolerant**. It must not behave like a fixed
inter-request spacer such as `60s / RPM` or `tokens * 60s / TPM`.

Instead, it uses two different pacing structures per resolved model:

1. an exact rolling `60`-second request-start window for RPM
2. a **64-slot, 1-second token bucket ring** for TPM

The `64` token buckets exist to provide a simple per-second approximation of
the provider's token-per-minute budget while giving a small safety margin around
the `60`-second operational horizon.

For each new request:

1. estimate request tokens as approximately
   `prompt_tokens + input_tokens + token_reserve_per_call`
2. prune request starts older than `60` seconds from the RPM window
3. prune token buckets that are at least `60` seconds old from the TPM window
4. check whether adding the request now would exceed either:
   * `max_requests_per_minute`
   * `max_tokens_per_minute`
5. if neither budget would be exceeded, admit the request immediately and add:
   * one request start to the RPM window
   * the estimated token count to the current-second TPM bucket
6. if the request would exceed budget, return a delay and retry admission after
   that delay; the request is **not** pre-reserved into future buckets

This means requests are only reserved when they are actually admitted to start.
Blocked callers sleep, wake up, and try admission again under the same
process-wide lock.

### DR3.1.1 — TPM wait calculation

When TPM would be exceeded, the scheduler computes:

`overflow_tokens = current_tpm + request_tokens - max_tokens_per_minute`

The wait target is based on **overflow**, not on the full request size.

Then:

1. inspect active per-second token buckets from oldest to newest
2. accumulate bucket token counts until the accumulated total is at least
   `overflow_tokens`
3. the number of bucket expirations required to reach that total determines the
   wait time

This is important because the request may need only a small amount of old token
usage to age out before it fits within budget.

Example:

* `current_tpm = 487360`
* `request_tokens = 13147`
* `max_tokens_per_minute = 500000`
* overflow is `507`, not `13147`

If the oldest active bucket contains at least `507` tokens, the request waits
only until that oldest bucket expires.

### DR3.1.2 — Behavioral consequences

The scheduler therefore behaves like a **per-second bucketed rolling budget
controller**:

* bursts are allowed up to the configured one-minute RPM budget
* bursts are allowed up to the configured one-minute TPM budget
* only the first request that would push the model over budget is delayed
* blocked requests do not consume future budget until they are admitted
* TPM waits are quantized to one-second bucket boundaries rather than exact
  sub-second reservation timestamps

This is intentional. The ADR's goal is still to enforce provider budgets over
time, not to force a single-file request queue when budget is available.

### DR3.2 — What is delayed, and what is not

The scheduler delays **request start time**, not request completion time.

It does not cancel or preempt in-flight requests merely because the trailing
window later becomes full. Once a request has started, it is governed by the
separate `max_inflight` lease controller and the request context timeout.

The scheduler and the permit controller therefore serve different roles:

* the rolling scheduler decides whether a new request may start now
* the permit controller decides whether the process may add one more in-flight
  request for that model right now

Both checks are required before issuing the outbound call.

### DR4 — Default lease duration

The default lease duration is **320 seconds**.

Rationale:

* current timeouts are commonly around 300 seconds,
* the lease must be slightly longer than the request timeout,
* the lease must still recover capacity in bounded time after failures.

### DR5 — The enforcement boundary is the shared LLM client

The lease controller and the RPM/TPM scheduler must be enforced at the shared
`shared/go/api/llm.OpenAIJSONClient` boundary.

Reason:

* many processors use the shared client directly or indirectly,
* the same process may run multiple processors at once,
* the same model may be used by several processors,
* processor-local gating cannot see or control total process-wide model usage.

Processor-local controllers may still exist as test hooks or fallback wrappers for
non-shared extractors, but the authoritative control point is the shared client.

### DR6 — Model budgets live in `.models.toml`

Per-model server-side budgets must be configured on the model definition itself,
not through process-wide env vars plus `...OVERRIDES`.

Reason:

* RPM and TPM are provider budgets for a specific resolved model,
* the model identity is already resolved through `.models.toml`,
* a process-wide variable such as `DOC_PROCESS_LLM_MAX_REQUESTS_PER_MINUTE`
  does not express which model it applies to,
* a second env var such as `...OVERRIDES` is indirect and easy to misread,
* the configuration should stay attached to the model entry that owns the
  budget.

The `.models.toml` schema should therefore be extended so each model entry may
define its own concurrency and pacing budget, for example:

```toml
[gpt-5.4-mini]
host = "cloud"
model_name = "gpt-5.4-mini"
api_key = "..."
base_url = "https://api.openai.com"
timeout_sec = 300
thinking_type = "disabled"
max_inflight = 16
max_requests_per_minute = 250
max_tokens_per_minute = 200000
token_reserve_per_call = 256
```

The example above is illustrative only. The values do **not** need to be
numerically aligned with each other.

Semantics:

* `max_inflight`
  * maximum concurrent in-flight calls for this resolved model in one process
  * this is a concurrency cap, not a per-minute rate cap
  * yes, this means **maximum concurrent requests**
* `max_requests_per_minute`
  * maximum request start rate for this resolved model in one process
  * this is the local scheduler's RPM budget for the provider-side model limit
* `max_tokens_per_minute`
  * maximum estimated token rate for this resolved model in one process
* `token_reserve_per_call`
  * extra output-token allowance added to the local TPM estimate for this model
  * estimated request tokens are approximately:
    `prompt + input + token_reserve_per_call`

The important distinction is:

* `max_inflight` controls **how many requests may run at the same time**
* `max_requests_per_minute` controls **how many requests may start within one minute**
* `max_tokens_per_minute` controls **how much estimated token volume may be sent within one minute**

These controls are complementary. In-flight limits alone do not guarantee RPM
or TPM safety, and RPM/TPM limits alone do not prevent local concurrency spikes
or leaked permits.

Why both are needed:

* RPM answers: "how fast may new requests start over time?"
* `max_inflight` answers: "how many requests may be executing at once right now?"

They solve different failure modes.

`max_requests_per_minute` alone does **not** bound instantaneous concurrency.
For example, if the process starts `250` requests in one minute and each request
takes `30` seconds, then roughly `125` requests may still be in flight at the
same time. If each request takes `60` seconds, concurrency may approach `250`
even though RPM is being respected.

That is why a model may still need a separate `max_inflight` cap:

* to bound local memory, goroutine, socket, and HTTP connection pressure,
* to respect provider-side concurrent-request limits that are separate from RPM,
* to recover from leaked/stuck calls via lease expiry,
* to stop long-running requests from piling up even when request start rate is
  within the RPM budget.

Conversely, `max_inflight` alone does **not** guarantee RPM compliance. If
`max_inflight = 16` and average latency is `10` seconds, the process could still
start about `96` requests per minute. If average latency drops to `3` seconds,
the same `max_inflight = 16` could imply about `320` request starts per minute,
which may exceed provider RPM.

So the configuration rule is:

* use `max_requests_per_minute` to stay within provider request-rate budget,
* use `max_tokens_per_minute` to stay within provider token-rate budget,
* use `max_inflight` to cap concurrent execution pressure and concurrent-call
  risk.

In practice, for slow non-embedding LLM calls, RPM and TPM will often become the
primary throughput limit while `max_inflight` acts as a safety ceiling rather
than the main steady-state throttle.

### DR6.1 — Lease TTL remains a runtime control

Lease TTL is not a provider quota; it is local runtime safety behavior.

`DOC_PROCESS_LLM_PERMIT_TTL_SEC` remains acceptable as a process/runtime
configuration knob, with default `320` seconds, because it controls permit
reclamation behavior rather than provider model budget.

### DR6.2 — Disable switches, if any, are runtime controls

If the implementation keeps an emergency runtime switch such as
`DOC_PROCESS_LLM_RATE_LIMIT_ENABLED`, it should be documented as an operational
override only.

It must not be the source of truth for per-model quotas. The source of truth for
server-side RPM/TPM and model concurrency is the corresponding `.models.toml`
entry.

### DR6.3 — Token reserve default and override

`DOC_PROCESS_LLM_TOKEN_RESERVE_PER_CALL` may remain as the global default token
reserve, with default value `256`.

Per-model `.models.toml` entries may override that default via
`token_reserve_per_call`.

Precedence:

1. `token_reserve_per_call` on the resolved model entry
2. `DOC_PROCESS_LLM_TOKEN_RESERVE_PER_CALL`
3. built-in default `256`

### DR7 — Error logs should surface model identity explicitly

When a downstream warning/error is caused by a provider-side rate limit and the
model identity can be recovered, logs should emit `model_name` as a structured
field rather than burying it only inside the raw error string.

This is especially important in post-processing/indexing flows such as category
creation, where operators need to know quickly which model exhausted which
budget without manually parsing a nested provider message.

## Alternatives Considered

### A1 — Per-processor goroutine limits only

Rejected.

This controls local fan-out but does not control aggregate process-wide load.
If eight processors each stay within their own limits, the process may still
exceed provider concurrency on a shared fallback model.

### A2 — Gate only fallback calls

Rejected.

Fallback surges are the visible symptom, but the underlying scarce resource is
all in-flight calls for a model. Primary calls and embeddings also consume the
same provider-side concurrency budget.

### A3 — Gate at the pipeline controller layer

Rejected.

The pipeline controller understands pipelines, not individual model selection.
LLM calls happen deeper in the stack, and different processors can choose
different models at runtime. The shared client has the correct visibility.

### A4 — Rely only on provider 429 retry/backoff

Rejected.

Provider-side rate limiting is reactive and noisy. It still allows stampedes,
wasted work, and synchronized fallback retries. The system should avoid
oversubscription before the request is sent.

### A5 — Use only in-flight permits, without RPM/TPM pacing

Rejected.

In-flight permits cap concurrency but do not cap time-distributed demand. A
small number of large prompts can still exceed TPM, and a steady sequence of
short calls can still exceed RPM.

## Consequences

### Positive

* prevents process-local model stampedes across pipelines and processors,
* protects fallback models from retry bursts,
* gives one consistent concurrency policy for chat, structured output, and
  embeddings,
* gives one consistent RPM/TPM pacing policy for non-embedding and embedding
  requests,
* bounds capacity leakage through lease expiry,
* makes model concurrency and rate budgets tunable without changing individual
  processors,
* improves operator visibility by surfacing `model_name` in rate-limit warnings.

### Negative

* adds queueing delay when a model is saturated,
* one process still has no visibility into other processes; cross-process
  coordination is out of scope,
* a too-small global limit can reduce throughput,
* the lease duration must stay aligned with real request timeouts,
* token-rate pacing depends on estimation rather than exact provider token
  accounting.

## Scope

This ADR defines **per-process** control only.

It does **not** introduce:

* cross-process distributed leasing,
* provider-specific adaptive quota discovery,
* weighted fairness across processors,
* priority scheduling between primary and fallback traffic.

Those may be added later if needed.

## Implementation Notes

1. Add a shared per-model permit controller to `shared/go/api/llm`.
2. Add a shared RPM/TPM scheduler to `shared/go/api/llm` for non-embedding LLM
   requests, mirroring the existing embedding limiter style.
3. Extend `ApiTypes.LLMModelDef` so `.models.toml` can carry per-model
   `max_inflight`, `max_requests_per_minute`, `max_tokens_per_minute`, and
   `token_reserve_per_call`.
4. Propagate those fields through model-loading helpers into
   `OpenAIJSONClient`.
5. Acquire/release permits inside `OpenAIJSONClient` before chat/structured-output
   and embedding requests.
6. Wait on RPM/TPM budget inside `OpenAIJSONClient` before sending chat /
   structured-output requests.
7. Keep rate-limit-related warnings structured, including `model_name` where it
   can be recovered from the provider error.
8. Keep a lightweight processor-side wrapper only for non-`OpenAIJSONClient`
   extractors used in tests or special adapters.
9. Document `.models.toml` model budget fields and lease/runtime behavior in the
   relevant processor specs.

## Testing

Required tests:

* acquire blocks when the model pool is full,
* releasing a permit wakes a waiter,
* lease expiry automatically reclaims capacity,
* chat / structured-output requests respect RPM pacing,
* chat / structured-output requests respect TPM pacing,
* chat / structured-output requests respect per-model RPM from `.models.toml`,
* chat / structured-output requests respect per-model TPM from `.models.toml`,
* embedding calls are also gated,
* processor-level concurrent workers cannot exceed the model permit ceiling even
  when their local worker count is higher,
* rate-limit warnings can emit `model_name` as a structured field.

## Documentation Impact

Docs/specs affected:

* entity-relation extraction spec: must mention per-model permit acquisition,
* any shared LLM client docs/specs: must mention `.models.toml` per-model
  RPM/TPM/in-flight budgets in addition to lease behavior,
* implementation notes for processors that rely on shared `OpenAIJSONClient`,
* any concurrency docs that previously described processor-local goroutine limits
  as the effective LLM concurrency bound.

Intentionally left undocumented for now:

* exact production values for each model budget,
* any future distributed/global concurrency control design.

## References

* `ChenWeb/server/api/doc-processing/control.go`
* `ChenWeb/server/api/doc-processing/extract-entity-relation.go`
* `ChenWeb/server/api/doc-processing/entity_name_indexing.go`
* `shared/go/api/llm/openai_client.go`
* `shared/go/api/llm/model_permit_controller.go`
* `shared/go/api/llm/request_rate_limiter.go`
