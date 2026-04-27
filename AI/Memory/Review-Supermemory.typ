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

*Change History*
#table(
  columns: 2,
  align: left,
  [Date], [Remarks],
  [2026/04/10], [Created, file name: Supermemory.typ],
)

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
    "Supermemory"
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


= Overview
[[def:Supermemory, ref:Memory]]

Supermemory is a unified memory + knowledge bas system. It is designed to store:
- Memory-like data:
  - conversations
  - user preferences
  - session history
- Knowledge Base:
  - Documents
  - Notes
  - External Content (Notion, Drive, etc.)
  - Arbitrary text/artifacts

Supermemory does not distinguish strongly between memory and knowledge - everything becomes retrievable context.
For large content, such as documents, it does do chunking.

A simplified pipeline of Supermemory:
- Ingest content
- Chunk it
- Generate embeddings
- Store + link to memory graph
- Retriever Layer

#let a_001 = link(
  "https://mp.weixin.qq.com/s/EKxJAS5WNhDV-ksQtV5ZBQ"
)[#text(fill: blue)[Article]]

#a_001 is a good article about Supermemory.

== Atomic Memory
[[def:Atomic Memory]]
Example:
```text
原始对话：
用户：我最近在考虑换工作，现在在ABC公司做软件工程师，
     但我觉得薪资不太满意，而且通勤太远了。

提取的原子记忆：
1. 用户在ABC公司担任软件工程师
2. 用户对当前薪资不满意
3. 用户通勤距离过长
4. 用户正在考虑换工作
```
This is important. First of all, we can use this technique to collect/derive information
about users, projects, etc.

== Memory Management

[[def:memory management]]
Below shows how Supermemory manages its memory:
```ts
for (const existing of related) {
    // 检测矛盾（updates关系）
    if (isContradiction(newMemory, existing)) {
      awaitcreateRelationship({
        type: 'updates',
        sourceId: newMemory.id,
        targetId: existing.id
      });
      // 标记旧记忆为过期，但不删除（保留历史）
      awaitmarkAsExpired(existing.id);
    }
    
    // 检测补充信息（extends关系）
    if (isExtension(newMemory, existing)) {
      awaitcreateRelationship({
        type: 'extends',
        sourceId: newMemory.id,
        targetId: existing.id
      });
    }
    
    // 推理衍生关系（derives）
    const derived = awaitinferRelationships(newMemory, existing);
    if (derived) {
      awaitcreateRelationship({
        type: 'derives',
        sourceId: derived.id,
        targetId: existing.id
      });
    }
  }

return related;
}
```

When creating a new memory, it checks whether it contradicts with existing one. If yes,
it marks the existing one 'expired' and add the new memory. 

*Comment*: I am not sure 
whether this is safe. When contradict memory (or SemObj) is found, we should list them
and let human users to resolve, or use LLMs (possibly another LLM) to review and resolve.

Function `isExtension(...)`:\ 
a new memory may add additional information
to existing one, such as "Project A uses Go and Svelte". This is important.

Function `inferRelationships(...)`:\ 
derive new relations when a new memory is added.

== Dual Timestamps [[def:dual timestamps]]

Supermemory uses two timestamps:
- Document Time
- Event Time
```ts
interface TemporalContext {
documentDate: Date;  // 对话记录的时间
eventDate: Date[];   // 事件实际发生的时间
```

This is important:
```text
// 示例：
// Day 30的对话："我的阿迪达斯上个月坏了"
// documentDate: 2025-01-30（对话发生时间）
// eventDate: [2024-12-30]（鞋子坏掉的时间）
}为什么需要双层时间戳？考虑这个场景：2025-01-01的对话："我去年在Facebook工作"
2025-06-01的查询："用户在哪工作？"

系统需要理解：
- documentDate = 2025-01-01（对话时间）
- eventDate = 2024年（工作时间）
- 当前时间 = 2025-06-01
- 结论：用户可能已经不在Facebook了
```

== Search

Its search system is a hybrid layered retrieval system:
- Vector search (primary): semantic similarity, embedding-based retrieval
- Keyword / lexical signals: exact match, text overlap
- Graph / Relationship search: links between memories, contextual associations
- Memory-aware ranking: recency, frequency, importance, personalization

[[def:Supermemory search]]
```ts
async functionhybridSearch(query: string, userId: string) {
// 第一步：在原子记忆中搜索（高信噪比）
const queryEmbedding = awaitgenerateEmbedding(query);
const memoryResults = awaitvectorSearch({
    embedding: queryEmbedding,
    collection: 'memories',
    filter: { userId },
    topK: 10
  });

// 第二步：获取原始内容块（保留细节）
const enrichedResults = awaitPromise.all(
    memoryResults.map(async (memory) => {
      const sourceChunks = awaitgetDocumentChunks(memory.sourceDocumentId);
      
      return {
        memory: {
          title: memory.content,
          confidence: memory.score,
          temporalContext: {
            documentDate: memory.documentDate,
            eventDate: memory.eventDate
          }
        },
        chunks: sourceChunks,
        // 第三步：附加关系图谱
        relationships: awaitgetRelatedMemories(memory.id)
      };
    })
  );

// 第四步：时间过滤和排序
const filteredResults = applyTemporalFiltering(
    enrichedResults,
    { currentDate: newDate() }
  );

return filteredResults;
}
```

== Issues

The main issue is about explorability. It is basically semantic + keyword search, plus memory-awareness.


