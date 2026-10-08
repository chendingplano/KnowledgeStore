# Emulated Decision Model — Jev-style typed answers from any chat model

**Date:** 2026-10-05 \
**Scope:** What the `jev_emulated` provider is, how it turns an ordinary chat model into a decision model, how to configure and call it, and where its answers differ from real Jev. Open this when you want yes/no, pick-one, or rating answers from a model without a Jev account.
**Code root:** `shared/go/api/llm` (`jev_emulated.go`, `jev_emulated_test.go`)

## Summary

Jev is a "decision model": instead of writing a reply, it answers short, typed questions about a piece of text — *is this urgent?*, *which team should handle it?*, *how angry is the customer?* — and says how likely each possible answer is. Our code can already call the real Jev service (see [2026092501-devdoc-jev-provider](../202609/2026092501-devdoc-jev-provider.md)).

This feature gives us the same kind of answers from the ordinary chat models we already use, such as Qwen, DeepSeek, OpenAI, or a model running on our own machine. Each question is turned into a multiple-choice quiz with lettered options, and the model is asked to answer with one letter. We don't use the letter it writes. Instead, we read how likely the model thought each letter was, and those odds become the answer.

Code that asks Jev questions can switch between real Jev and the emulated version by changing configuration only; the questions and the shape of the answers stay the same. The trade-off is that a chat model's odds are less trustworthy than Jev's (see Known limitations).

## Details

### Background

- Jev API contract: <https://docs.typesafe.ai/api>; confidence formulas: <https://docs.typesafe.ai/confidence>.
- Technique: [A Jev-like wrapper for LLMs](https://allanrbo.blogspot.com/2026/09/a-jev-like-wrapper-for-llms-including.html) — single-token answer plus `logprobs` / `top_logprobs` on an OpenAI-compatible Chat Completions endpoint.

### Provider and construction

| Item | Value |
| --- | --- |
| Provider ID | `llm.ProviderJevEmulated` = `"jev_emulated"` |
| Factory | `llm.NewClient(cfg, logger)` → `newJevEmulatedClient` |
| `BaseURL` | Required (`ErrMissingBaseURL` otherwise). With or without a trailing `/v1`; requests go to `…/v1/chat/completions` (via `buildChatCompletionsEndpoint`). |
| `APIKey` | Optional — the only provider exempt from `ErrMissingAPIKey`, so local servers (llama.cpp, vLLM) work. Sent as `Authorization: Bearer` only when non-empty. |
| `logger` | Optional; a default `JimoLogger` is created when nil (usage capture requires one). |
| `Stream` | Unsupported; returns an error. |

`ProviderConfig.Extra` settings (invalid values make `NewClient` fail):

| Key | Default | Meaning |
| --- | --- | --- |
| `top_logprobs` | `20` | Alternatives requested per call. Provider caps: DashScope 5, OpenAI and DeepSeek 20; llama.cpp allows more. |
| `concurrency` | `4` | Max questions in flight at once. |
| `temperature` | `0` | Sent as-is; `omit` leaves the field out for models that reject it. |
| `reasoning_effort` | unset | Sent as-is when set (e.g. `none` for llama.cpp thinking models). |
| `thinking` | unset | `enabled` or `disabled`, sent as `{"thinking":{"type":…}}`. DeepSeek V4 needs `disabled`. |

### Request

Same as `jev_compatible`: questions go in `Request.JevQuestions` (`map[string]JevQuestion`), and the state is the **last `RoleUser` message**. Earlier messages are ignored. Differences from `jev_compatible`:

- A multipart user message is accepted. `Content` and `text` parts are joined with a blank line to form the state. `image_url` and `image_b64` parts (`MIME` defaults to `image/jpeg`) are attached to every question; this needs a vision model. Other part types are rejected.
- The state must contain text or at least one image.

Task-specific instructions that all questions share (a **policy**, such as a definition of prompt injection) belong in the state, e.g. `{"text": …, "policy": …}`. That way they lead every prompt and can be prefix-cached. Policies are stored and versioned in the decision policy store; see [2026100503-devdoc-decision-policy-store](2026100503-devdoc-decision-policy-store.md).

Question validation (`jevEmulatedOptions`), per type:

| Type | Criteria | Options shown to the model | Answer key per option |
| --- | --- | --- | --- |
| `noul` | must be nil | `yes`, `no` | `"true"`, `"false"` |
| `choice` | `map[string]string`, ≥ 2 entries | keys sorted alphabetically, `key: description` | option key |
| `score` | `[]string`, ≥ 2 levels | levels in order | `"0"` … `"n-1"` |

`Instructions` must be non-empty. A question can have at most 26 options (letters A–Z).

### Prompt and call

One Chat Completions call per question, all in parallel, each independent of the others:

```text
State:
<state>
                                   ← image parts go here, if any
Question: <instructions>
Options:
[A] <label>[: <description>]
[B] ...

Answer with the letter of the best option only, without brackets or explanation.
```

Body: `{"model", "messages":[{"role":"user","content":…}], "max_tokens":1, "logprobs":true, "top_logprobs":N, "temperature":0}`, plus `reasoning_effort` if configured. Content is a plain string when there are no images, otherwise a parts array. Because the `State:` block leads every prompt, backends with prefix caching can reuse it across questions.

### Turning logprobs into probabilities (`jevEmulatedNormalize`)

Reads `choices[0].logprobs.content[0].top_logprobs` — the alternatives for the single output token.

1. Each candidate token is trimmed of whitespace and `[]().:*"`, then upper-cased. A single letter within the first *n* letters counts toward that option. Duplicates such as `A`, ` A`, `a` and `[A` are combined with log-sum-exp. Logprobs ≤ −9999 are ignored.
2. Probabilities are normalized over the options that were found.
3. **Missing-option guard:** an option absent from the alternatives can be no likelier than the least likely alternative returned (the cutoff). If `missing × e^(cutoff − peak)` is ≥ 1e-6 of the total, the call fails ("raise top_logprobs"). Otherwise the missing options get 0.
4. If no option letter appears at all, the call fails.

### Answers (`jevEmulatedAnswer`)

`Response.Content` is the compact JSON answers object keyed by question ID, in Jev's shape. `llm.ParseJevAnswers(content)` decodes it into `map[string]llm.JevAnswer`; this works for both providers.

| Type | Fields | Formula |
| --- | --- | --- |
| `noul` | `noul` | P(`yes`) |
| `choice` | `choice`, `probabilities`, `confidence` | `choice` = argmax; confidence = `(p_max − 1/n) / (1 − 1/n)` |
| `score` | `score`, `legend`, `probabilities`, `confidence` | score = Σ i·pᵢ; confidence = `max(0, 1 − Σ pᵢ·|i − m| / MAD_unif)`, where m = most likely level and MAD_unif = mean |i − (n−1)/2| |

`Response.Raw` is `{"model", "answers", "usage":{"input_tokens","output_tokens"}}`, mirroring Jev's response body.

### Usage, logging, and errors

- Every question is a real LLM call and gets its own `llm_usage_event` row via `captureUsageRecord`. That includes failed calls, which record the error message. The capture provider comes from the base URL (`deepseek`, `qwen`, `openai`, or `openai_compatible`).
- `Response.Usage` is the sum over questions; per-call event IDs are in `Usage.EventIDs`.
- The request is all-or-nothing, like Jev. The first failed question cancels the rest, and the root error is returned (not the cancellations it caused) as `jev_emulated: question "<id>": …`. HTTP failures are `*llm.ProviderError` with `Provider: jev_emulated` and the body capped at 512 bytes.
- Each request's outcome is logged through `JimoLogger`: `Info` with question count and token totals on success, `Error` with the root error on failure.

### Example

```go
client, err := llm.NewClient(llm.ProviderConfig{
	ID:      llm.ProviderJevEmulated,
	BaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
	APIKey:  os.Getenv("DASHSCOPE_API_KEY"),
	Extra:   map[string]string{"top_logprobs": "5"},
}, logger)
if err != nil {
	return err
}
resp, err := client.Complete(ctx, llm.Request{
	Model: "qwen-plus", UserID: userID,
	PromptName: "ticket_triage", CallReason: "ticket_triage", CallLoc: "20261005-118",
	Messages: []llm.Message{{Role: llm.RoleUser, Content: ticketText}},
	JevQuestions: llm.JevQuestions{
		"is_urgent":  {Type: "noul", Instructions: "The message conveys urgency or time-sensitivity"},
		"department": {Type: "choice", Instructions: "Which team should handle this",
			Criteria: map[string]string{"billing": "Payment issues", "technical": "Bugs or integration problems", "sales": "Pricing questions"}},
		"frustration": {Type: "score", Instructions: "How frustrated the customer appears",
			Criteria: []string{"Calm", "Frustrated but civil", "Very angry"}},
	},
})
if err != nil {
	return err
}
answers, err := llm.ParseJevAnswers(resp.Content)
// answers["department"].Choice == "technical"; *answers["is_urgent"].Noul ≈ 1.0
```

Verified live on 2026-10-05 with `qwen-plus` and `qwen-turbo` on Jev's quickstart ticket. Both returned `technical`, score 1.0, and urgency ≈ 1.0, the same as Jev's documented answers.

### Tests

`jev_emulated_test.go` uses a fake logprob server. It covers all three question types and their confidence values, request body fields, usage summing, state-first prompt layout, image attachment, token merging, the missing-option guard, and validation errors.

## Known limitations

- **Probabilities are not calibrated.** Jev is trained so its probabilities mean what they say; a chat model's token probabilities are often near 0 or 1 (Qwen gave 0.9999… where Jev reports e.g. 0.85). Thresholds on `noul` or `confidence` must be tuned per model and do not carry over from Jev.
- **The model must return logprobs.** Reasoning models (e.g. `deepseek-reasoner`, OpenAI o-series) don't, and fail with "response has no logprobs".
- **DeepSeek V4 (`deepseek-v4-flash`, `deepseek-v4-pro`) needs two settings.** It thinks by default, which uses up the single output token and fails with "response has no logprobs", so set `thinking = disabled`. Its logprobs are also reported after temperature: at `temperature = 0` the chosen letter gets 0 and every other option −9999, which fails the missing-option guard. Use `temperature = 1` to get the model's real distribution; the sampled token itself is never used. The ChenWeb Decision Model Playground applies both for any `deepseek` base URL. Verified live on 2026-10-05.
- **Few options.** At most 26 per question, and in practice no more than `top_logprobs` unless the unlisted options are negligible. Jev allows 255 choice options. On DashScope (cap 5), questions with more than 5 options usually fail the missing-option guard.
- **One call per question.** Cost and latency grow with the number of questions, unlike Jev's single call. Prefix caching only reduces the cost of the repeated state.
- **Letter position bias.** Choice options are lettered in alphabetical key order, and a model may slightly favour early letters.
- **Narrower question format than Jev.** No `noul` criteria, and no object/array `instructions` or `criteria`; this matches the shared `JevQuestion` type.
- **Not selectable from ChenWeb config.** ChenWeb's `.models.toml` importer maps `decision-model` profiles only to `jev_compatible`; `jev_emulated` clients must be constructed in code. Exception: the Decision Model Playground (System Admin → LLM → Decision Models → Playground, requirement `2026100502-rqmt`) runs any `model_type = 'llm'` entry through `jev_emulated`, with `top_logprobs = 5` for DashScope base URLs and `temperature = omit` when `omit_temperature` is set. Since 2026-10-08 that mapping lives in `ChenWeb/server/api/decisionmodel` and is also used by `extract_metrics`, which picks its decision model with `METRIC_DECISION_MODEL` (a `.models.toml` profile) to judge value-open requirements (openspec change `metric-row-soft-drop-decision-model`).
