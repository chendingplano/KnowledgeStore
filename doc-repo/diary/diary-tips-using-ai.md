# 1. Overview

Using AI is a skill.

# 2. Tips on using AI

## 2.1 Learning in the AI area

link: https://www.toutiao.com/video/7691879372491325479/?app=news_article&category_new=tt_video_immerse&module_name=iOS_tt_others&req_id_new=20261107184218D08735F33CF50DE86F85&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=e1601a7c-da98-11f1-a258-e8ebd303282c&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1794048557&tt_from=weixin&upstream_biz=iOS_wechat&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect)

Normally, people will do:
- Generate summary
- List major points
- Explain the core concepts

In addition, an MIT student does (refer to the above link):
- Upload whatever you should, if not in the database yet
- Question: "What are the 5 core mental models that every expert in this
  area shares?"
- List three fundamental disagreements among the experts in this area
  and write down the most favorable arguments of each side
- Generate 10 questions to test my knowledge in this area, aiming at
  checking whether I really know this area. If I answered wrong, why
  it is wrong, the reasons, what I missed, etc.

Generate the fundamental models and disagrements in an area, then 
let LLM test whether I am an expert in this area by asking questions.
This method of quickly establish a mental model on a subject, understand
the major concepts, and then, instead of reading tons of books, articles,
papers, textbooks, learn knowledge by question-answering. This is the
major difference.

In addition, don't just answer questions, but dive into them. For each
question, what major points the question tries to test. If I am correct,
where I am correct. If I am wrong, where I went wrong, explain the reasons,
list the knowledge points that I should master, keeps on diving into
every details by asking LLM questions, asking LLM gave examples.

Before AI, people learn by reading. In the AI era, people learn by answering
questions. Each question laser-focuses on one specific topic.

<a id="ref-learning-in-ai-era"></a>

## 2.2 Vibe coding

### 2.2.1 Lauren Tan
URL: https://x.com/mvanhorn/article/2111481455906103390

**Tip 1**
> Don't create too many agents. 

**Tip 2**
> Make agents trustworthy

The real values of agents is the trust. Initially, agents can't be trusted.
They do make mistakes, and possibly many, though very helpful when they
do not make mistakes. The challenges are how to let agents make less
mistakes to the level that you can largely trust they.

Lauren fixes agent mistakes in five layers:
- strongest first: make the mistake impossible in the codebase
- fail the build with lints and CI
- rules and review bots
- skills
- only last a human style guide

Her reasoning is that agents copy whatever patterns they see. Or, as she put it: 

> "Before AI slop, we had human slop."

**Tip 3**

> "If you want to go fast, go deep first"

### 2.2.2 Skills

**Tip 1**

> You need your own set of skills

Don't just copy skills from the Internet. Understand and memorize the skills
you use.

**Tip 2**

> The skill to create skills

### 2.2.3 Rules

Rules are knowledge. Rules are simple form of skills. Rules create
guardrails to prevent things going wrong.

Most rules have exceptions, a lot of them. Know when to follow, when 
not to follow, and when to break.

## Scalffolding

**Tip 1**

When fixing a bug, developing a new feature, if it needs something and that something
may be reused by others, create the reusable module first and make it 
discoverable.