# Jev Provider — Using Jev's structured decision API from Go

**Date:** 2026-09-25  
**Scope:** How ChenWeb and other Go callers configure and call the Jev provider through the shared LLM client.  
**Code root:** `shared/go/api/llm`

## Summary

ChenWeb's backend can now send text to Jev and ask named questions about it, such as whether a support message is urgent or which team should handle it. To use Jev, a caller provides those questions with the request and configures the API key on the server. Jev requires named questions for each request; it does not answer a general chat prompt by itself.

## Details

### Configuration

ChenWeb's local `.models.toml` contains a `jev-latest` profile with the provider URL and an empty `api_key`. Keep the API key out of this file and configure it in the server environment instead:

```sh
JEV_AI_API_KEY=<your Jev API key>
```

`llm.NewClient` reads `JEV_AI_API_KEY` when `ProviderConfig.APIKey` is empty. It trims surrounding whitespace and returns `llm.ErrMissingAPIKey` if the environment variable is unset or blank. A nonempty `ProviderConfig.APIKey` takes precedence.

The shared client defaults to `https://jev-ai.pro/api`. Its request path is `/v1/systemone`, producing the documented endpoint `https://jev-ai.pro/api/v1/systemone`. ChenWeb's TOML importer recognizes `jev-ai.pro` and its subdomains as provider `jev`.

### Sending a request

Set `ProviderConfig.ID` to `llm.ProviderJev`. The last `RoleUser` message's `Content` is sent as Jev's `state`; earlier chat messages are ignored. State must contain non-whitespace text. Multipart user messages are not supported. Each request must include one or more questions keyed by the IDs that callers use to find answers in the response.

```go
client, err := llm.NewClient(llm.ProviderConfig{ID: llm.ProviderJev}, logger)
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

### Response and failures

`Response.Content` is the compact JSON encoding of Jev's `answers` object. Answer IDs match the keys supplied in `Request.JevQuestions`. When Jev includes usage, `Response.Usage.InputTokens` and `OutputTokens` contain its `input_tokens` and `output_tokens` counts.

The adapter sends a JSON `POST` to `/v1/systemone` with a Bearer authorization header. HTTP errors and malformed provider responses are returned as `*llm.ProviderError`; provider response bodies stored in the error are capped at 512 bytes. `Client.Stream` returns an error because Jev does not support streaming.

For Jev's full API contract, request examples, and account billing details, see the [Jev API documentation](https://jev-ai.pro/jev-api).

## Known limitations

- Jev is a structured decision API, not a drop-in chat-completions model. Callers must supply question IDs, types, instructions, and any required criteria.
- Jev requests use only the last plain-text user message as state. Chat history and multipart content are not sent.
- Streaming is unsupported.
