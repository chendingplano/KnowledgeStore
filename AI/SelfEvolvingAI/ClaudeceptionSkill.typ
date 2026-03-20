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

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

// #table(
//  columns: 3,
//  align: left,
//  [Name], [Description], [Documentation],
//  [Bicep], [Microsoft], [Azure-specific],
//
// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

= Claudeception Skill

#let a_001 = link(
  "https://mp.weixin.qq.com/s/uy8ICLLFYreH9kusmZ3sUg"
)[#text(fill: blue)[Article]]

#let a_002 = link(
  "https://github.com/blader/Claudeception"
)[#text(fill: blue)[GitHub]]

#a_001 \
#a_002 \
Date: 2026/05/16 \
Source: WeChat

Claudeception is a Meta-Skill: a skill that creates skills. 
It specializes at converting your dev experiences into skills
so that your AI learn gradually from the mistakes you made in the past.

== Where Claudeception Came From

Claudeception is inspired by several projects.

=== Voyager

Voyager是2023年发布的AI研究项目，其核心创新是通过"代码即技能"的方式实现终身学习。该项目在《Minecraft》开放世界中验证了无需微调模型，而是通过编写、执行和迭代JavaScript代码来掌握新技能的可行性。代码片段会被存入向量数据库，形成可复用的技能库，为后续开发提供经验积累。

这一设计为Claudeception等后续AI辅助开发工具提供了关键灵感。

=== Reflecxion (2023)

Reflexion 提出了"语言强化"（Verbal Reinforcement）的概念：当 Agent 失败时，不只是收到负分，而是强制生成"自我反思"将试错过程中的隐性信息转化为显性的语言反馈极大提升后续决策的成功率

=== CASCADE (2024)

CASCADE 提出了 Meta-Skills（元技能）的概念：Agent 可以通过网络搜索、代码提取和内省来自主掌握复杂工具强调递归式的自我增强能力

=== SEAgent (2025)

SEAgent 将战场拓展到完全陌生的软件环境：
- 通过 World State Model 和 Curriculum Generator 进行自主探索
- 强调"从经验中学习"（Learning from Experience）

Claudeception 融合了这些研究的精髓：Voyager 的技能库、Reflexion 的反思循环、CASCADE 的元技能、SEAgent 的经验学习。

== 自动触发条件

Claudeception 在以下情况会自动激活：
- 非显而易见的调试：解决方案需要深入调查，且文档中找不到
- 错误解决：错误消息具有误导性，根本原因不明显
- 变通方案：发现了工具/框架限制的绕过方法
- 配置洞察：发现了项目特定的非标准配置
- 试错成功：尝试多种方法后才找到解决方案

== 提取流程

1. 语义分析：回顾对话历史，提取核心因果关系
2 .网络验证（可选）：搜索最新最佳实践，确保知识不过时
3. 结构化写入：生成标准化的 Markdown 技能文件
