
```text
State: My order arrived broken and I want a refund.
Question: Which team should handle this?
[A] billing
[B] shipping
[C] returns
Answer with the letter of the best option only.
```

Then add a few JSON request parameters to a compatible Chat Completions request:

```text
{
  "max_completion_tokens": 1,
  "logprobs": true,
  "top_logprobs": 20
}
```

