#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#show heading: it => {
  set text(fill: blue) if it.level == 1
  if it.numbering != none {
    counter(heading).display(it.numbering)
    h(0.5em) // Adds a little gap after the number
  }
  it.body
}

#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "Reading-202602"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

= TOON

#let a_001 = link(
  "https://dzone.com/articles/token-efficient-apis-for-the-agentic-era"
)[#text(fill: blue)[article]]

Link: #a_001

Source: dzone

JSON:
```json
[
{"id": 1001, "name": "John Doe", "role": "architect", "active": true},
{"id": 1002, "name": "Chris Smith", "role": "engineer", "active": false}
]
```

TOON equivalent:
```text
HEADERS: id, name, role, active
1001 | John Doe | architect | true
1002 | Chris Smith | engineer | false
```

TRON is one step further: it eliminates keys (no headers). It relies on schemas,
which is not sent with every TOON.

I am not sure whether this is needed.

= Use Claude Code to Write PPT

帮我生成一份技术方案演示稿，主题是[你的主题]。
需要讲清楚：
- [要点1]
- [要点2]
- [要点3]

直接给我HTML代码，黑色主题，支持键盘←→切换。

= Video of Claude Code Author

#let a_002 = link(
  "https://www.toutiao.com/video/7613339642754318372/?app=news_article&category_new=tt_video_immerse&module_name=iOS_tt_others&req_id_new=202603042012286429A8EF4BC85CD4526F&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=b1b8de58-17c3-11f1-8fb2-fa163e60b263&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1772626469&tt_from=weixin&upstream_biz=iOS_wechat&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect"
)[#text(fill: blue)[article]]

Link: #a_002

Source: TouTiao

= Pi Article

#let a_003 = link(
  "https://mp.weixin.qq.com/s/vjdMPgnGJ7wPEBTjbcq4qg"
)[#text(fill: blue)[article]]

Link: #a_003

Source: TouTiao

