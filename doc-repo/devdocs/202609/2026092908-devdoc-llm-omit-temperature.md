# omit_temperature Model Setting — using models that reject temperature 0

**Date:** 2026-09-29 \
**Scope:** Why some models (e.g. OpenAI's `gpt-6-luna`) failed every call from the shared
LLM client, the `.models.toml` setting that fixes it, and which callers honour that
setting. Open this when a model fails with a `temperature` error, or when wiring a new
caller to a model definition.
**Code root:** `shared/go/api/llm/openai_client.go`, `shared/go/api/ApiTypes/ApiTypes.go`

## Summary

The shared LLM client asks every model for `temperature: 0`, which makes answers as
repeatable as possible. Some newer models — OpenAI's reasoning models such as
`gpt-6-luna` — refuse any request that sets temperature, and reply with an error instead of
an answer:

> Unsupported value: 'temperature' does not support 0 with this model. Only the default (1)
> value is supported.

This showed up on 2026-09-29 when the Review Metrics page
([2026092907-devdoc-review-metrics-page.md](2026092907-devdoc-review-metrics-page.md)) was
switched to `gpt-6-luna`: every review failed immediately.

There is now a per-model switch in `.models.toml`, `omit_temperature`. Set it to `true` on a
model that rejects temperature, and the client stops sending the field for that model.
Models without the switch behave exactly as before, so nothing else changed.

## Details

### Configuration

In the model's section of `.models.toml` (ChenWeb: `ChenWeb/.models.toml`, not version-controlled):

```toml
[gpt-6-luna]
model_name = 'gpt-6-luna'
base_url = 'https://api.openai.com'
# ...
omit_temperature = true  # rejects temperature 0 ("Only the default (1) value is supported")
```

| Value | Request sent |
|---|---|
| absent / `false` (default) | `"temperature": 0` — unchanged behaviour |
| `true` | no `temperature` field; the provider uses its default |

The setting is set locally for `gpt-6-luna` in the dev `.models.toml`. **Each environment's
`.models.toml` (including production) needs the same line** for any model that rejects
temperature — the file is not in the repository.

### Plumbing

The value travels through three structs, following the same path as `max_output_tokens`:

1. `ApiTypes.LLMModelDef.OmitTemperature` — parsed from TOML key `omit_temperature`.
2. `llm.OpenAIJSONClientConfig.OmitTemperature` — the caller copies it from the model definition.
3. `llm.OpenAIJSONClient.OmitTemperature` — set by `NewOpenAIJSONClientFromConfig`; the chat
   request builder adds `"temperature": 0` only when it is `false`.

Step 2 is manual: each place that builds a client from a model definition lists the fields it
copies. **A caller that does not copy `OmitTemperature` keeps sending temperature 0**, even if
`.models.toml` sets the switch.

### Which callers honour it (as of 2026-09-29)

| Caller | Honours `omit_temperature` |
|---|---|
| Review Metrics — `ChenWeb/server/api/kbhandler/metric_review_handler.go` | yes |
| `defaultNewExtractMetricsClient` — `extract-metric-handler.go` (also used by metric wiki generation) | no |
| `extract-provision-handler.go`, `doc-processing/review_exports.go`, `productnameimporthandler/handler.go`, `cmd/keyword-reconcile` | no |

To make another caller work with such a model, add `OmitTemperature: cfg.OmitTemperature` to
its `OpenAIJSONClientConfig{...}` literal.

### Verification

- Unit test `TestExtractJSON_Temperature` (`shared/go/api/llm/openai_client_test.go`) checks both
  cases: temperature 0 by default, no temperature field when the switch is on.
- A live call to `gpt-6-luna` with the switch on returned a normal JSON answer (2026-09-29).
- Commits: shared `oror 146c` (setting + client), ChenWeb `vytq c0bb` (Review Metrics passes it).

## Known limitations

- **Opt-in per model, and per caller.** The client does not detect these models by name or
  retry without temperature; someone has to set the switch in `.models.toml`, and the calling
  code has to pass it through (see the table above).
- **Output-length field.** When a model has `max_output_tokens` above 0, the client sends it as
  `max_tokens`. OpenAI's reasoning models may reject that name and expect
  `max_completion_tokens` instead. With `max_output_tokens = 0` (the current `gpt-6-luna`
  setting) nothing is sent and calls work; setting a limit for such a model is untested.
- **Answers are less repeatable** for models with the switch on, because they run at the
  provider's default temperature rather than 0.
