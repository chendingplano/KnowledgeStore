
# Rule Engines

Date: 2026/07/31 \
Link: "https://www.toutiao.com/article/7667012700145041961/?app=news_article&category_new=__all__&module_name=iOS_tt_others&req_id_new=20260729014836F09D9F7595A9B17DFC7E&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=0735059d-8aae-11f1-85d5-00163e744ada&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1785261547&tt_from=weixin&upstream_biz=iOS_wechat&use_new_style=1&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect&wid=1785489832956"


The process is:
```text
corpus-documents => LLM Extraction => Ontology => Rules => Rule Engine

user-input .............................................=> Rule Engine => Verdict + Reasoning

```

The above model has a problem: we can't go directly from inputs to
Rule Engine. We should do the same thing as processing corpus
documents.

In ontology, there are classes and instances.

Rule Example
```json
{
  "rule_id": "xxx",
  "source": "line numbers",
  "condition": {
    "type": "and",
    "operands": [
      {"field":"temperature", "op":"<", "value":80},
      {"field":"pressure" "op":"<", "value":1.5}
    ]
  },
  "requirements":"acceptable",
  "explanation":"xxx"
}
```

There are many challenges:
- How to extract rules
- How to handle the inputs
- How to match inputs to rules
- How to reason
- How to handle exceptions
- What to do if no rules are found
