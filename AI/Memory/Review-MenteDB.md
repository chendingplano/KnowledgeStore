---
name: [[def:Stash]]
file_id: file-2026042502
links: [[Memory, Memory System, Memory Database]]
note_date: 2026/04/25
source-url: https://github.com/nambok/mentedb
document-date: 2026/04/25
---

**MenteDB** is an experimental, from-scratch **database engine specifically designed for AI agent memory**, 
rather than a general-purpose database. Unlike traditional systems (PostgreSQL, Redis, etc.), 
it is built around the idea that **LLMs don’t just query data—they need cognitively 
structured context**. ([Crates][1]) [[mind-like memory system]]

At its core, MenteDB models data as a **“mind-like memory system.”** Instead of tables and rows, it uses abstractions such as *MemoryNodes* (units of knowledge) and *MemoryEdges* (relationships), forming a **knowledge graph combined with embeddings and temporal signals**. ([Docs.rs][2]) This allows it to represent not just facts, but also relationships, salience, and time—closer to how an agent “remembers” rather than how a database stores records.

A key differentiator is its focus on **context assembly for LLMs**. Rather than returning raw query results, MenteDB tries to **pre-digest and assemble context optimized for transformer models**, taking into account token limits and attention patterns. ([Docs.rs][2]) In other words, it acts less like a storage system and more like a **“cognition preparation engine”**—deciding *what* information should be surfaced and *how* it should be structured for an LLM in a single pass.

Technically, the project combines several advanced components into one engine:

* **Hybrid retrieval** (vector search via HNSW + tags + temporal + graph traversal)
* **Knowledge graph reasoning** with weighted relationships
* **Custom query language (MQL)** tailored for memory operations
* **Storage engine features** like WAL-based recovery and compression ([Docs.rs][2])

Finally, MenteDB fits into the emerging pattern: **unifying memory + RAG into a single system**. It explicitly introduces “cognitive tiers” (working, episodic, semantic, etc.), suggesting a design where agent memory is **stateful, structured, and continuously evolving**, rather than a stateless retrieval layer. ([Docs.rs][2])

**In short:** MenteDB is not trying to be “another database.” It’s an attempt to build a **native memory substrate for AI agents**, where storage, retrieval, and reasoning are co-designed around how LLMs actually consume information.

[1]: https://crates.io/crates/mentedb?utm_source=chatgpt.com "mentedb - crates.io: Rust Package Registry"
[2]: https://docs.rs/mentedb/latest/mentedb/?utm_source=chatgpt.com "mentedb - Rust"

