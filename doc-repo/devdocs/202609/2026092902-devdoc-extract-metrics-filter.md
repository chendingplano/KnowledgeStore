# Purpose
After metrics being retrieved, use LLM to decide whether they are true metrics. 

Example:
Context: 农村生活垃圾分为易腐垃圾、可回收物、有害垃圾和其他垃圾四大类，分类标志见附录A。

It extracted:
- Value: 4
- Threshold: 4
- Unit: 类
- Class: definition
- Data Type: integer

Apparently, this is not a metric.

Example:
Context: 表1 易腐垃圾及其他垃圾主要处理模式 易腐垃圾-机器成肥

It extracted:


The source does not mention the actual value of 
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

- Metric 416_mtc_2: Jev, source "农村生活垃圾分为易腐垃圾、可回收物、有害垃圾和其他垃圾四大类，分类标志见附录A。"
