#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

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
    "Prompts"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

#let frontmatter = (
  created: "2026/04/21",
  logical_name: "Prompts",
  file_id: "2026042101",
  file_type: "Typst",
  keywords: ["Prompts"],
)

= Prompt for Creating GUI

#let a_001 = link(
  "https://www.toutiao.com/video/7630928806543229476/?app=news_article&category_new=tt_video_immerse&module_name=iOS_tt_others&req_id_new=20260421041651F1002F585A5759E0ED50&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=87e7b10d-3cfa-11f1-b05f-cee1d2a8ef97&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1776718214&tt_from=weixin&upstream_biz=iOS_wechat&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect"
)[#text(fill: blue)[Video]]

#a_001 \
Source: WeChat

一定使用 taste-skill，帮我做一个高端室内设计网站首页，整体像高端家居品牌 campaign：大量留白、杂志感排版、克制动效、浅色中性色。

Hero 要求：

- 必须是全屏 (100vh)，图片 / 视频占满整个 Hero 区域，不留边距空白
- 下方留空给视频背景，视频全屏覆盖，文字叠加在上方
- 整体构图参考截图里的 ESTUDIO ANÓNIMO 风格：超大衬线字体标题，极简导航克制，充足留白
- 不要模板味，不要普通 SaaS hero，不要居中布局
其余页面：杂志感排版，大量留白，克制动效，浅色中性色（米白/暖灰/炭灰），全英文。

