# LLM Exact-Match Cache — reusing a stored answer when the identical request comes back

**Date:** 2026-11-11 \
**Scope:** How an exact-match cache for LLM responses works, what its key must
contain, and how it applies to this workspace. Read this before building any cache
that stores model answers. It also separates this kind of cache from the provider
prompt cache we already use. **No exact-match cache is built in the workspace yet**
(see *Status*). \
**Code root:** none yet. The closest code is `shared/go/api/llm` (the client every
model call goes through) and `ChenWeb/server/api/doc-processing` (where ADR
2026082202 proposes the first cache).

## Summary

Calling a large language model (LLM) is slow and costs money. Many of our requests
repeat word for word: the same document chunk is processed again with the same
prompt, a benchmark is rerun, a test suite calls the same prompt. An exact-match
cache saves the model's answer the first time and files it under a fingerprint of
everything that went into the request. When an identical request arrives, the saved
answer is returned and the model is not called at all.

It only helps when the new request is exactly identical. A reworded question, a
changed prompt, or a chunk that shifted by one line gets no benefit. Matching
reworded questions is "semantic caching", which this workspace has decided not to
use for document extraction, because "similar" is not proof that two chunks
contain the same facts.

This is not the "prompt cache" we already use with DeepSeek. That one only makes a
repeated call cheaper: the provider reuses the start of the prompt, but the model
still runs and still bills for the call. An exact-match cache skips the call
completely.

The hard part is the fingerprint. If it leaves out anything that changes the
answer, the cache silently returns a wrong answer. If it includes things that
change on every call, such as run IDs, it never gets a hit.

## Details

### Source

DZone, <https://dzone.com/articles/llm-exact-match-prompt-caching>, Part 1 of a series on
LLM caching. Part 2 covers semantic caching (embedding similarity plus a
verification step). This devdoc restates Part 1's guidance and maps it onto
workspace code and decisions; where the workspace has decided differently, the
difference is stated.

### Status in the workspace (2026-11-11)

| Layer | What it reuses | Status | Where |
| --- | --- | --- | --- |
| Provider prompt cache | The provider's work on a repeated prompt *prefix*; the model still runs | **Built** | ADR `2026062501-adr-deepseek-cache.md`, ADR `2026070301-adr-llm-cache-optimize.md` (Implemented: first call, stagger, then the rest); `prompt_cache_hit_tokens` captured in `shared/go/api/llm/openai.go` and `ChenWeb/server/api/llmusage/sink.go` |
| Exact-match result cache | The whole answer; no model call | **Proposed, not built** | ADR `2026082202-adr-content-addressed-llm-result-cache.md` (Status: Proposed). No `kb.llm_task_cache` table, no `llm_cache_mode`, no `DOC_PROCESS_LLM_CACHE_MODE` exist in code |
| Semantic cache | An answer to a *similar* request | **Rejected** for authoritative extraction | ADR 2026082202 DR4 |

ADR 2026082202 was written from a different DZone article ("Stop Paying Your AI
Agent to Do the Same Job Twice") and already covers most of this article's ground
for `extract_metrics`. Treat the ADR as the design for that use. This devdoc is the
general reference for the pattern and for any other place that wants a cache.

### Two caches that are easy to confuse

| | Provider prompt cache | Exact-match result cache |
| --- | --- | --- |
| Request sent to the provider | Yes | No (on a hit) |
| Saves | Part of the input-token price | The whole call: price, latency, rate-limit budget |
| Matches on | An identical prompt *prefix* | The identical *complete* request |
| Measured by | `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` on `llm_usage_event` | Its own hit/miss log; a hit creates no `llm_usage_event` row |

Reports must never add these together. A result-cache hit means no call happened;
prompt-cache hit tokens mean a call happened at a discount.

### The key: what goes in and what stays out

The article's rule: hash the full context that matters (system prompt, user
messages, tool definitions, and every setting that changes the output) and leave
out anything that changes per call without affecting the answer, such as request or
trace IDs.

Mapped onto `llm.Request` (`shared/go/api/llm/types.go`):

| Field | In the key? | Why |
| --- | --- | --- |
| `Model` | Yes | Different model, different answer |
| `Messages` (all roles: system, user, assistant, tool; `Content`, `Parts`) | Yes | This is the prompt. The system prompt is a `RoleSystem` message |
| `Messages[].ToolCalls` name + arguments | Yes | Prior tool calls in an agent loop shape the answer |
| `ToolCall.ID`, `Message.ToolCallID` | **Replace with position** | Provider-generated, different on every run; keep only which call a tool reply answers |
| `Tools` (name, description, parameters schema) | Yes | The article stresses the *full* tool schema, not just names |
| `ToolChoice`, `Temperature`, `TopP`, `MaxTokens` | Yes | All change the output (`MaxTokens` can truncate it) |
| `JevQuestions` | Yes | Part of the Jev request |
| `UserID`, `RecordID`, `RunID`, `CallReason`, `CallLoc`, `Metadata`, `Capture` | No | Bookkeeping; changes every call, does not affect the answer |
| `PromptName` | No | A label. Hash the prompt *contents* (already in `Messages`), so editing a prompt file causes a miss |
| `Stream` | No | Delivery only; a stored answer can be replayed either way |

Inputs that are not in `llm.Request` but must be in the key:

- **Provider** (`ProviderConfig.ID`) and any provider-specific option that changes
  output, such as reasoning mode.
- **Model revision.** Model names like `deepseek-chat` are aliases whose behaviour
  can change behind the same name. Use the provider's immutable revision, or a
  `cache_revision` you bump by hand (ADR 2026082202 DR5).
- **Output contract version.** If code parses or normalizes the answer, a change to
  that schema must cause a miss.
- **Key version.** One integer you bump to invalidate everything after a deliberate
  change to how keys are built.
- **Sharing scope.** Identity fields stay out of the hash *as bookkeeping*, but you
  must decide on purpose who may share an entry. Put that scope in the key. ADR
  2026082202 uses `ks_store_id`, so an answer never crosses knowledge stores even
  when the documents are byte-identical.

Canonicalization (making equal requests produce equal bytes):

- **Sort tool lists** when their order does not change how the model behaves.
- **Sort JSON object keys.** The article names this as one of the two common ways a
  cache silently breaks: different parts of one codebase write the same JSON with
  keys in a different order. In Go, `json.Marshal` is already stable for structs
  (field declaration order) and maps (sorted keys), but `json.RawMessage` and JSON
  held in strings pass through untouched. In `llm.Request` that means
  `ToolDef.Parameters` and `ToolCall.Arguments`. Re-encode them before hashing
  (decode with `UseNumber()`, then re-marshal), or use RFC 8785 JSON
  Canonicalization Scheme (JCS) as ADR 2026082202 requires.
- **Whitespace: be careful.** The article suggests cleaning up whitespace. In our
  document processors whitespace, line breaks and line numbers are part of the
  input the model reads (`canonicalChunkInputText`), so do not normalize them there.
  Only collapse whitespace where the model's answer cannot depend on it.
- **Do not count on order matching by chance** (the article's words). Sort
  explicitly.

The article's own Python example builds its key from `prompt`, `model` and
`temperature` only, which is narrower than its own rule. Do not copy that key. It
misses the system prompt, the tools and the other settings.

### Key construction in Go (sketch)

This sketch is not in the codebase. It was compiled and tested against
`shared/go/api/llm` on 2026-11-11: volatile fields, tool order, JSON key order and
provider tool-call IDs leave the key unchanged; model, temperature, system prompt,
tool description, scope and model revision change it.

```go
const keyVersion = 1 // bump to invalidate every entry after a deliberate change

// keyDescriptor lists every input that can change the model's answer.
// llm.Request's volatile fields (UserID, RecordID, RunID, CallReason, CallLoc,
// Metadata, Capture, PromptName, Stream) are deliberately absent.
type keyDescriptor struct {
	KeyVersion   int              `json:"key_version"`
	Scope        string           `json:"scope"`     // who may share entries, e.g. "ks:17"
	Provider     string           `json:"provider"`  // ProviderConfig.ID
	Model        string           `json:"model"`
	ModelRev     string           `json:"model_rev"` // bump when an alias changes behaviour
	Messages     []keyMessage     `json:"messages"`
	Tools        []keyTool        `json:"tools"`
	ToolChoice   string           `json:"tool_choice"`
	Temperature  *float64         `json:"temperature"`
	TopP         *float64         `json:"top_p"`
	MaxTokens    *int             `json:"max_tokens"`
	JevQuestions llm.JevQuestions `json:"jev_questions,omitempty"`
}

type keyMessage struct {
	Role      llm.Role          `json:"role"`
	Content   string            `json:"content"`
	Parts     []llm.ContentPart `json:"parts,omitempty"`
	ToolCalls []keyToolCall     `json:"tool_calls,omitempty"`
	ReplyTo   string            `json:"reply_to,omitempty"` // positional, not the provider's ID
}

type keyToolCall struct {
	Ref       string          `json:"ref"`
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments"`
}

type keyTool struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"`
}

// ExactKey returns "llm:exact:<sha256>" for req. Sort tools only when their
// order does not change how the model behaves.
func ExactKey(scope string, provider llm.ProviderID, modelRev string, req llm.Request) (string, error) {
	d := keyDescriptor{
		KeyVersion: keyVersion, Scope: scope, Provider: string(provider),
		Model: req.Model, ModelRev: modelRev, ToolChoice: req.ToolChoice,
		Temperature: req.Temperature, TopP: req.TopP, MaxTokens: req.MaxTokens,
		JevQuestions: req.JevQuestions,
	}
	// Provider tool-call IDs differ on every run; replace them with positions.
	refs := map[string]string{}
	for _, m := range req.Messages {
		km := keyMessage{Role: m.Role, Content: m.Content, Parts: m.Parts}
		for _, tc := range m.ToolCalls {
			ref := fmt.Sprintf("call%d", len(refs))
			refs[tc.ID] = ref
			args, err := canonicalJSON([]byte(tc.Arguments))
			if err != nil {
				return "", fmt.Errorf("tool call %s arguments: %w", tc.Name, err)
			}
			km.ToolCalls = append(km.ToolCalls, keyToolCall{Ref: ref, Name: tc.Name, Arguments: args})
		}
		if m.ToolCallID != "" {
			km.ReplyTo = refs[m.ToolCallID]
		}
		d.Messages = append(d.Messages, km)
	}
	for _, t := range req.Tools {
		params, err := canonicalJSON(t.Parameters)
		if err != nil {
			return "", fmt.Errorf("tool %s parameters: %w", t.Name, err)
		}
		d.Tools = append(d.Tools, keyTool{Name: t.Name, Description: t.Description, Parameters: params})
	}
	slices.SortFunc(d.Tools, func(a, b keyTool) int { return strings.Compare(a.Name, b.Name) })

	payload, err := json.Marshal(d)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(payload)
	return "llm:exact:" + hex.EncodeToString(sum[:]), nil
}

// canonicalJSON re-encodes raw JSON with object keys sorted and numbers kept
// exactly as written, so two code paths that emit keys in different orders
// still produce the same bytes.
func canonicalJSON(raw []byte) (json.RawMessage, error) {
	if len(bytes.TrimSpace(raw)) == 0 {
		return nil, nil
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		return nil, err
	}
	return json.Marshal(v)
}
```

Not covered by the sketch: the output-contract version and provider-specific
options. Add them as descriptor fields when a real cache is built.

### What to store with each entry

The article: the full response (or the structured output), plus timestamp, model
version and time-to-live (TTL). Store the parsed, validated output rather than raw
provider bytes, and validate a cached payload again before using it. ADR 2026082202
caches `ValidatedStageResultV1` and re-runs all downstream normalization on hits, so
a fix to that code applies without clearing the cache.

### Where the cache lives

| Option | Speed | Behaviour across instances | Use when |
| --- | --- | --- | --- |
| In-process LRU (least-recently-used) map | Under 1 ms, no network | Each process warms its own copy; low hit rate until all have warmed | One instance, or answers cheap to recompute per instance |
| Shared store | A few ms per round trip | A hit on instance A also serves instance B | The default beyond a single instance |
| Two levels: small in-process LRU in front of the shared store | Hot keys never leave the process | Shared for everything else | A few keys carry most traffic (FAQ-style workloads) |

Workspace facts that change the article's defaults:

- **There is no Redis or Memcached** in `shared/go`, `ChenWeb` or `tax` (none in
  their `go.mod`). The shared store we have is PostgreSQL, through the centralized
  connection pools. ADR 2026082202 puts the cache in a PostgreSQL table, which also
  gives it persistence across restarts, per-knowledge-store scoping, deletion
  cascades and an audit trail. Adding Redis would be a new infrastructure decision,
  not an implementation detail.
- New tables go through goose migrations (workspace CLAUDE.md, *Database*).

### Keeping entries fresh

The article's three tools:

1. **Fixed TTL** for time-sensitive answers (its example: 60 seconds for travel
   prices or stock levels; its code defaults to 300 seconds).
2. **LRU eviction** when the store fills.
3. **Deliberate clearing** when something changes (a price update, an outage, a
   policy change).

For document processing, ADR 2026082202 DR5 decides differently: an answer about
an unchanged chunk, prompt, contract and model revision does not go stale with time.
The key *is* the freshness check (change any input and the key changes), so
`expires_at` defaults to `NULL`. A TTL belongs only to answers that depend on live
outside state. Explicit invalidation stays available for operators.

### Failures: the cache must never break a request

- **Fail open.** If the cache cannot be read or written, log it and call the model.
  The article: "Treat the cache as a nice-to-have, not something the app depends
  on." (ADR 2026082202 DR7 agrees, and adds that a corrupt or contract-invalid
  cached entry is treated as a miss.)
- **Never cache provider failures** (HTTP 429 rate limit, 5xx) as if they were
  answers. Retry with backoff instead.
- **Guardrail rejections are a judgment call.** Some teams cache their own
  content-filter rejections for a few seconds to a minute, to stop a broken or
  hostile client from repeating an expensive rejection. Others never do, so a fixed
  input is not met with a stale rejection. If you cache them, use a separate key
  prefix (`llm:reject:` beside `llm:exact:`) and a separate, short TTL, so they can
  be cleared on their own and kept out of hit-rate figures.
- **Workspace rule for document processing:** no negative caching at all. Only
  validated, complete, successful outputs are stored. Transport errors, parse
  failures, partial JSON and cancelled calls are never stored (ADR 2026082202 DR1).

### Thundering herd: coalesce identical concurrent requests

If fifty identical requests arrive before the first one has filled the cache, all
fifty miss and all fifty call the model. This is a cache stampede. A viral post, a
batch job starting up, or another system's retry storm can trigger it. Without a
fix, an exact-match cache can make traffic spikes worse, because every process
learns about a busy key at the same moment and calls the model when it can least
handle the load.

The fix is request coalescing ("single-flight"):

1. The first request for a key takes a short lock or sets an in-flight marker.
2. Other requests for the same key wait for that result instead of calling the
   model.
3. The in-progress state is visible too, not just finished answers.
4. The wait has a fair timeout. A waiter that is not served in time makes its own
   call, so one stuck request does not hold up everyone.

In this workspace:

- `golang.org/x/sync/singleflight` is already a direct dependency of ChenWeb and is
  used in `ChenWeb/server/api/doc-processing/artifact_category_resolver.go` to
  coalesce concurrent category-creation LLM calls. Use that as the pattern.
- `singleflight.Group.Do` has no timeout. For the bounded wait, use `DoChan` and
  `select` on the result channel, a timer and the caller's context.
- The shared call runs on behalf of every waiter, so the first caller cancelling must
  not fail the others. Run it on a context detached from that caller
  (`context.WithoutCancel`) with its own deadline. Treat the shared result as
  read-only, because all callers receive the same value.
- `singleflight` only coalesces within one process. Across processes the article
  uses a shared in-flight marker (Redis `SET NX`). ADR 2026082202 instead accepts
  duplicate cross-process cold fills in phase 1, uses a PostgreSQL advisory lock
  only for the short publish transaction ("first valid writer wins"), and rejects
  holding a lock across the remote LLM call.

### Warming the cache

A newly deployed in-memory or Redis cache starts empty, so hit rate drops after any
deploy that clears it. The article loads the most common prompts and answers from
the last few days of logs before the cache takes traffic. This matters most when a
small set of questions makes up most of the volume.

A persistent PostgreSQL cache is not cleared by a deploy, so it needs no warm-up
(ADR 2026082202 DR9: "No backfill job is required").

### Measuring

Log every lookup outcome (hit, miss, expired, invalid, bypass, write failure).
Count hits on cached rejections separately, or leave them out. Derive hit rate,
avoided calls and avoided cost from your own lookup log joined with real
`llm_usage_event` rows, never from provider prompt-cache token counters. ADR
2026082202 DR8 defines the record for document processing: `kb.doc_proc_logs`,
`activity_name = 'llm_result_cache'`.

### Where it pays off

The article: templated queries, form-driven flows, test suites and batch jobs, where
the same request keeps coming back. Hit rates can be very high in narrow domains
and close to zero in open, free-form chat.

In this workspace the likely payers are document-processing reruns over unchanged
chunks, benchmark and scoring reruns, and tests. Free-form chat (Knowledge Desk,
the harness front ends) will see almost no hits.

## Known limitations

- **Identical means identical.** One changed character in a prompt, a different
  model option, or a chunk boundary that moved by one line is a miss. This is
  intended. It is what makes a hit safe to serve.
- **A key that leaves out an input that changes the answer serves wrong answers
  silently.** This is the main risk of the pattern. Every prompt, schema or model
  option change must either be in the key or bump the key version.
- **A cache freezes one sample.** With temperature above zero, the model's answer
  varies between runs, and the cache keeps returning the first one. Experiments that
  rerun extraction to find more results must bypass the cache (ADR 2026082202 DR6:
  `refresh` or `off`).
- **Coalescing in one process does not stop duplicate calls from other
  processes** without a shared in-flight marker.
- **Cached answers are copies of the data they describe.** For document extraction
  they inherit the same access, backup, retention and deletion rules as other `kb`
  document data.
- **Nothing here is built yet.** When an exact-match cache ships, update this
  devdoc's *Status* section and point it at the code.

## Related documents

- `KnowledgeStore/doc-repo/adrs/202608/2026082202-adr-content-addressed-llm-result-cache.md`:
  the proposed result cache for `extract_metrics`
- `KnowledgeStore/doc-repo/research/202608/2026082201-rsch-llm-prompt-cache.md`:
  analysis behind that ADR (semantic retrieval compared with scope comparison)
- `KnowledgeStore/doc-repo/adrs/202606/2026062501-adr-deepseek-cache.md`: provider
  prompt-prefix caching
- `KnowledgeStore/doc-repo/adrs/202607/2026070301-adr-llm-cache-optimize.md`: call
  staggering so parallel chunk calls share the provider prompt cache
