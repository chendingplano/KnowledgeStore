# Jev Provider — Using Jev's structured decision API from Go

**Date:** 2026-09-25  
**Scope:** How ChenWeb and other Go callers configure and call the Jev provider through the shared LLM client.  
**Code root:** `shared/go/api/llm`

## 1. Summary

ChenWeb's backend can now send text to Jev and ask named questions about it, such as whether a support message is urgent or which team should handle it. To use Jev, a caller provides those questions with the request and configures the API key on the server. Jev requires named questions for each request; it does not answer a general chat prompt by itself.

## 2. Details

### 2.1 Configuration

#### 2.1.1 ChenWeb `.models.toml`

Add a profile to `ChenWeb/.models.toml`. Set `model_type = 'decision-model'` to select the Jev-compatible System One protocol; the section name and `model_name` can be chosen independently. Multiple profiles can use this type, including profiles that point to another Jev-compatible service:

```toml
[jev-latest]
host = 'cloud'
model_name = 'jev-latest'
model_type = 'decision-model'
api_key = ''
base_url = 'https://jev-ai.pro/api'
timeout_sec = 300
thinking_type = ''
max_inflight = 100
max_requests_per_minute = 3000
max_tokens_per_minute = 200000
token_reserve_per_call = 256
max_output_tokens = 0
```

The blank `api_key` is intentional. Keep the key out of `.models.toml` and configure it in the server environment instead:

```sh
JEV_AI_API_KEY=<your Jev API key>
```

ChenWeb's `.models.toml` is Git-ignored, so this profile is configured locally in each ChenWeb environment that needs Jev.

`llm.NewClient` reads `JEV_AI_API_KEY` when `ProviderConfig.APIKey` is empty and the configured base URL is the official `jev-ai.pro` host (or a subdomain). It trims surrounding whitespace and returns `llm.ErrMissingAPIKey` if the environment variable is unset or blank. A nonempty `ProviderConfig.APIKey` takes precedence. Other Jev-compatible hosts require an explicit `api_key`. The `.models.toml` profile tells ChenWeb which provider URL and model name to use; keep secrets out of the file where possible.

The shared client defaults to `https://jev-ai.pro/api`. Its request path is `/v1/systemone`, producing the documented endpoint `https://jev-ai.pro/api/v1/systemone`. ChenWeb's TOML importer maps every `decision-model` profile to provider `jev_compatible`, independent of its section name or model name. It also recognizes `jev-ai.pro` and its subdomains as a legacy fallback for profiles without that model type.

### 2.2 Sending a request

Set `ProviderConfig.ID` to `llm.ProviderJevCompatible` (the `llm.ProviderJev` compatibility alias is also available). This provider name describes the protocol, not a vendor. The last `RoleUser` message's `Content` is sent as Jev's `state`; earlier chat messages are ignored. State must contain non-whitespace text. Multipart user messages are not supported. Each request must include one or more questions keyed by the IDs that callers use to find answers in the response.

```go
client, err := llm.NewClient(llm.ProviderConfig{ID: llm.ProviderJevCompatible}, logger)
if err != nil {
	return err
}

response, err := client.Complete(ctx, llm.Request{
	Model:    "jev-latest",
	Messages: []llm.Message{{Role: llm.RoleUser, Content: "My payment failed. Please help."}},
	JevQuestions: llm.JevQuestions{
		"urgent": {
			Type:         "noul",
			Instructions: "Does this message need urgent support?",
		},
	},
})
```

Question types and criteria:

| Type | Criteria value | Answer field |
| --- | --- | --- |
| `noul` | Omit criteria | `noul` is a 0–1 probability of yes |
| `choice` | Nonempty `map[string]string` from option ID to description | `choice` contains the selected option ID |
| `score` | Nonempty ordered `[]string` of labels | `score` is numeric and interpreted using the ordered labels; the response includes a legend |

The request JSON contains a `questions` object keyed by question ID. For example, a choice question is constructed like this:

```go
"department": {
	Type:         "choice",
	Instructions: "Which team should handle this?",
	Criteria: map[string]string{
		"billing":   "Payments and refunds",
		"technical": "Bugs and outages",
	},
}
```

The `score` criteria list preserves the label order. `noul` questions must not have criteria. The shared adapter validates question types and criteria shapes before sending the request.

### 2.3 Response and failures

`Response.Content` is the compact JSON encoding of Jev's `answers` object. Answer IDs match the keys supplied in `Request.JevQuestions`. When Jev includes usage, `Response.Usage.InputTokens` and `OutputTokens` contain its `input_tokens` and `output_tokens` counts.

The adapter sends a JSON `POST` to `/v1/systemone` with a Bearer authorization header. HTTP errors and malformed provider responses are returned as `*llm.ProviderError`; provider response bodies stored in the error are capped at 512 bytes. `Client.Stream` returns an error because Jev does not support streaming.

For Jev's full API contract, request examples, and account billing details, see the [Jev API documentation](https://jev-ai.pro/jev-api).

## 3. Known limitations

- Jev is a structured decision API, not a drop-in chat-completions model. Callers must supply question IDs, types, instructions, and any required criteria.
- Jev requests use only the last plain-text user message as state. Chat history and multipart content are not sent.
- Streaming is unsupported.

## 4. Emulated decision model (`jev_emulated`)

*Added 2026-10-05.* `llm.ProviderJevEmulated` answers the same `JevQuestions` with any OpenAI-compatible chat model — DashScope/Qwen, OpenAI, DeepSeek, llama.cpp, vLLM — so no Jev account is needed. It follows the technique in [A Jev-like wrapper for LLMs](https://allanrbo.blogspot.com/2026/09/a-jev-like-wrapper-for-llms-including.html). Code: `shared/go/api/llm/jev_emulated.go`.

### 4.1 How it works

Each question becomes a lettered multiple-choice prompt:

```text
State:
<state>

Question: Which team should handle this?
Options:
[A] billing: Payments and refunds
[B] technical: Bugs and outages

Answer with the letter of the best option only, without brackets or explanation.
```

The adapter asks for **one** output token with `logprobs: true` and `top_logprobs`, then turns the probabilities of the letters into a distribution over the options. The model never writes an answer; we read how likely it was to write each letter.

- **noul**: options are `yes` / `no`; `noul` is the probability of `yes`.
- **choice**: options are the criteria keys, sorted alphabetically so letter assignment is stable.
- **score**: options are the levels in order; `score` is the probability-weighted level index, as in Jev.
- `confidence` uses Jev's published formulas (Choice: `(p_max − 1/n)/(1 − 1/n)`; Score: `1 − spread / spread_of_uniform`, floored at 0).
- Tokens such as ` A`, `a` or `[A` all count toward letter A.
- If an option's letter is not among the returned alternatives, its probability is at most that of the least likely alternative returned. The adapter treats it as 0 only when that bound is below 1e-6 overall; otherwise it fails and tells you to raise `top_logprobs`.

Questions run in parallel and independently, as in Jev. The state comes first in every prompt so a backend with prefix caching reuses it across questions. Every question is a separate LLM call and is recorded in `llm_usage_event`; `Response.Usage` is the sum, with each call's event ID in `EventIDs`.

### 4.2 Configuration

```go
client, err := llm.NewClient(llm.ProviderConfig{
	ID:      llm.ProviderJevEmulated,
	BaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", // required; "/v1" is optional
	APIKey:  key,                                                // may be empty for a local server
	Extra:   map[string]string{"top_logprobs": "5"},
}, logger)
```

`Extra` settings:

| Key | Default | Meaning |
| --- | --- | --- |
| `top_logprobs` | `20` | Alternatives requested per call. DashScope allows at most 5, OpenAI and DeepSeek at most 20; llama.cpp allows more. |
| `concurrency` | `4` | Questions evaluated at once. |
| `temperature` | `0` | Sent as-is; `omit` leaves it out for models that reject it. |
| `reasoning_effort` | unset | Sent as-is when set, e.g. `none` for llama.cpp thinking models. |

The request and response are the same as in §2.2–2.3: `Response.Content` is the answers object and `llm.ParseJevAnswers` decodes it into typed `llm.JevAnswer` values for either provider. Unlike `jev_compatible`, a multipart user message is accepted: text parts form the state and image parts are attached to every question (needs a vision model).

### 4.3 Limitations

- The model must return logprobs. Reasoning models (e.g. `deepseek-reasoner`, OpenAI o-series) do not, and fail with "response has no logprobs".
- At most 26 options per question (letters A–Z), and in practice no more than `top_logprobs` unless the unlisted options are negligible. Jev allows 255 choice options.
- The probabilities are the model's raw token probabilities, not calibrated like Jev's. Chat models are often overconfident: a live run on `qwen-plus` returned probabilities of 0.9999… where Jev reports values such as 0.85. Choose thresholds for `confidence` per model.
- Noul `criteria`, and object/array `instructions` or `criteria`, are not supported, matching the current `JevQuestion` type.
- ChenWeb's `.models.toml` importer does not map any profile to `jev_emulated` yet; callers construct the client in code.
