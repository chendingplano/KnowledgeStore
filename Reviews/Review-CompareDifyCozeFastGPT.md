---
logical name: [[compare dify coze fastgpt]]
description: >
  Set up hierarchical Intent Layer (AGENTS.md files) for codebases.
  Use when initializing a new project, adding context infrastructure to an existing repo,
  user asks to set up AGENTS.md, add intent layer, make agents understand the codebase,
  or scaffolding AI-friendly project documentation.
---

# AI Workflow Platform Comparison: Dify vs Coze vs FastGPT

> Research date: 2026-04-18

## Overview

| Feature | Dify | Coze | FastGPT |
|---------|------|------|---------|
| Developer | LangGenius | ByteDance | Sealos / labring |
| Open Source | Yes (Apache 2.0) | Yes (Apache 2.0, since July 2025) | Yes (Apache 2.0) |
| Primary Focus | LLM app development platform | AI agent building platform | Knowledge-base-centric AI agent |
| GitHub | [langgenius/dify](https://github.com/langgenius/dify) | [coze-dev/coze-studio](https://github.com/coze-dev/coze-studio) | [labring/FastGPT](https://github.com/labring/FastGPT) |

---

## 1. Supported Node Types

### Dify [[def:dify]]

| Category | Nodes |
|----------|-------|
| **Input/Output** | Start, End, Answer (Chatflow only) |
| **AI** | LLM, Agent (autonomous reasoning + tool selection), Knowledge Retrieval |
| **Logic & Control** | If/Else (conditional branching), Question Classifier, Iteration (loop over lists), Loop, Human Input (pause for human review) |
| **Data Processing** | Code (Python / Node.js), Template (Jinja2), Variable Assigner, List Operator |
| **Integration** | HTTP Request, Tool (built-in tools, custom tools, sub-workflows) |

**Highlights:** Agent node enables autonomous multi-step reasoning; Human Input node (v1.13+) supports human-in-the-loop workflows.

### Coze [[def:coze]]

| Category | Nodes |
|----------|-------|
| **Input/Output** | Start, End |
| **AI** | LLM, Intent Recognition, Knowledge Base Retrieval, Knowledge Base Writing |
| **Logic & Control** | Condition (if-else), Loop, Batch Processing |
| **Data Processing** | Code, Variable, Variable Assign, Variable Merge, Text Processing |
| **Integration** | HTTP Request, Plugin, Workflow (nested sub-workflows), Question (user input prompt) |
| **Database** | SQL Customization, Add/Query/Update/Delete Data |
| **Media** | Image Generation, Canvas, Image Processing |
| **Conversation** | Create/Edit/Delete/Query Conversation |

**Highlights:** Native database CRUD nodes; rich image processing nodes; conversation management nodes for multi-turn dialogue control.

### FastGPT [[def:fastgpt]]

| Category | Nodes |
|----------|-------|
| **Input/Output** | Workflow Start (User Question), Specified Reply |
| **AI** | AI Chat, Knowledge Base Search, Knowledge Base Search Merge |
| **Logic & Control** | Conditional branching (via triggers), Loop / Batch Processing |
| **Data Processing** | Code Execution, Text Processing (string merge) |
| **Integration** | HTTP Request |
| **System** | User Guidance (dialog configuration) |

**Highlights:** Strong RAG-oriented design with knowledge base search merge; supports plugins as reusable workflow components; node system is more streamlined but extensible.

### Node Type Comparison Matrix

| Node Type | Dify | Coze | FastGPT |
|-----------|------|------|---------|
| LLM Call | Yes | Yes | Yes |
| Knowledge Base / RAG | Yes | Yes | Yes (core strength) |
| Code Execution | Python, Node.js | Yes | Yes |
| HTTP Request | Yes | Yes | Yes |
| Conditional Branching | Yes | Yes | Yes |
| Loop / Iteration | Yes | Yes | Yes |
| Variable Management | Yes | Yes | Limited |
| Sub-workflow / Nesting | Yes | Yes | Yes (plugins) |
| Human-in-the-Loop | Yes (v1.13+) | Via Question node | No |
| Database CRUD | No (via HTTP) | Yes (native) | No (via HTTP) |
| Image Generation | No (via tools) | Yes (native) | No |
| Agent (autonomous) | Yes | No | No |
| Template Engine | Yes (Jinja2) | No | No |

---

## 2. Model Integration

### Dify

- **Supported Providers:** 100+ providers including OpenAI, Anthropic, Google Gemini, Cohere, Azure OpenAI, Hugging Face, Replicate, Mistral, and many more
- **Local Models:** Ollama, vLLM, Xinference, LocalAI
- **Custom Models:** Any OpenAI API-compatible endpoint; plugin-based model provider system for adding new providers
- **Integration Method:** Configure API keys via workspace settings UI; each provider has a dedicated configuration page
- **Model Types:** LLM, Embedding, Rerank, Speech-to-Text, Text-to-Speech

### Coze

- **Cloud (coze.com):** Built-in access to GPT-4o, GPT-4-Turbo, Gemini 1.5 Flash, and ByteDance's Doubao models; users select models from a curated list
- **Coze Studio (self-hosted):** Bring your own API keys via YAML configuration files
  - OpenAI (model_template_openai.yaml)
  - Volcengine Ark / Doubao (model_template_ark.yaml)
  - Anthropic Claude (protocol: "claude")
  - Alibaba Cloud Bailian (OpenAI-compatible protocol)
  - Ollama (local models)
- **Integration Method:** Copy model template YAML, fill in API key and model name, restart service
- **Custom Models:** Any OpenAI-compatible endpoint supported via protocol configuration

### FastGPT

- **Integration Hub:** [OneAPI](https://github.com/songquanpeng/one-api) as the unified model management layer
- **Supported via OneAPI:** OpenAI (GPT-5 series, GPT-4.1, o3/o4), Anthropic Claude (Opus 4.6, Sonnet 4.6, Haiku 4.5), Google Gemini (3-flash, 3-pro, 2.5-pro/flash), xAI Grok (4, 3-mini, 3), DeepSeek (V3.2, Reasoner), Qwen (3.5, 3, 2.5 series), GLM (5, 4.6, 4.5), Moonshot/Kimi (K2.5), MiniMax (M2.7, M2.5), Doubao/Seed, Baidu ERNIE, Tencent Hunyuan
- **Local Models:** Ollama integration (connects through OneAPI)
- **Model Types:** LLM, Embedding, Rerank, TTS, STT
- **Integration Method:** Configure OneAPI with provider API keys -> set OneAPI base URL and token in FastGPT config; model IDs must match between OneAPI channel and FastGPT config

### Model Integration Comparison

| Aspect | Dify | Coze | FastGPT |
|--------|------|------|---------|
| Provider Count | 100+ | ~5-6 (cloud); extensible (self-hosted) | 15+ via OneAPI |
| Config Method | UI-based | YAML files | OneAPI admin panel |
| Custom Endpoints | Yes (OpenAI-compatible) | Yes (OpenAI-compatible) | Yes (via OneAPI) |
| Local Model Support | Ollama, vLLM, etc. | Ollama | Ollama (via OneAPI) |
| Plugin/Extension System | Model provider plugins | Template YAML | OneAPI channels |
| Ease of Setup | Easiest (GUI) | Moderate (YAML) | Most complex (OneAPI layer) |

---

## 3. Private / Self-Hosted Deployment

### Dify

| Aspect | Details |
|--------|---------|
| **Available** | Yes, fully supported |
| **Methods** | Docker Compose (primary), local source code, Kubernetes, platform guides (AWS, aaPanel) |
| **Min Requirements** | 2 CPU cores, 4 GB RAM |
| **Components** | 11 containers: API, worker, worker_beat, web, plugin_daemon, PostgreSQL, Redis, Weaviate (vector DB), nginx, SSRF proxy, sandbox |
| **License** | Apache 2.0 for community edition |
| **Enterprise Self-Hosted** | Available -- contact sales for pricing |

### Coze

| Aspect | Details |
|--------|---------|
| **Available** | Yes, since open-sourcing in July 2025 |
| **Methods** | Docker Compose (primary) |
| **Min Requirements** | 2 CPU cores, 4 GB RAM |
| **Components** | coze-server, database, Redis, Elasticsearch |
| **Tech Stack** | Go (backend), React/TypeScript (frontend), containerized microservices |
| **License** | Apache 2.0 |
| **Note** | Relatively new to self-hosting; community and ecosystem still growing |

### FastGPT

| Aspect | Details |
|--------|---------|
| **Available** | Yes, core deployment model |
| **Methods** | Docker Compose, Sealos (managed Kubernetes), local source code |
| **Sealos Advantage** | No server/domain purchase needed; auto-scaling; KubeBlocks for better I/O than plain Docker |
| **Components** | FastGPT app, MongoDB, PostgreSQL (pgvector), OneAPI |
| **License** | Apache 2.0 |
| **Note** | Self-hosting is the primary use case; cloud version is secondary |

### Deployment Comparison

| Aspect | Dify | Coze | FastGPT |
|--------|------|------|---------|
| Docker Compose | Yes | Yes | Yes |
| Kubernetes | Yes | Community | Yes (Sealos) |
| Min Resources | 2C/4G | 2C/4G | ~2C/4G |
| Vector DB | Weaviate (built-in) | Elasticsearch | pgvector (PostgreSQL) |
| Maturity | High (long-standing) | Moderate (since mid-2025) | High |
| Enterprise Support | Yes (paid) | Limited | Yes (commercial license) |

---

## 4. Pricing Strategy

### Dify (Cloud -- dify.ai)

| Plan | Price | Message Credits | Apps | Knowledge Docs | Storage | Team Members |
|------|-------|----------------|------|---------------|---------|-------------|
| **Sandbox** (Free) | $0 | 200 | 5 | 50 | 50 MB | 1 |
| **Professional** | $59/mo ($590/yr) | 5,000/mo | 50 | 500 | 5 GB | 3 |
| **Team** | $159/mo | 10,000/mo | 200 | 1,000 | 20 GB | 50 |
| **Enterprise** | Contact sales | Custom | Custom | Custom | Custom | Custom |

- Self-hosted community edition is **free** (Apache 2.0)
- Users bring their own model API keys (model costs separate)

### Coze (Cloud -- coze.com)

| Plan | Price | Daily Credits | Key Limits |
|------|-------|--------------|------------|
| **Free** | $0 | 10 credits/day | ~5 GPT-4o messages/day |
| **Premium** | $9/mo | 100 credits/day | ~50 GPT-4o messages/day, unlimited GPT-3.5 |
| **Premium Plus** | $39/mo | 1,000 credits/day | ~500 GPT-4o messages/day |

- 3-day free trial for paid plans
- Coze Studio (self-hosted) is **free** (Apache 2.0), users bring their own API keys
- China version (coze.cn) has separate pricing, primarily uses Doubao models

### FastGPT (Cloud -- cloud.fastgpt.io)

| Plan | Price (CNY) | AI Points | Dataset Indexes | Members | Agents | QPM |
|------|-------------|-----------|----------------|---------|--------|-----|
| **Free** | 0 | 100 | 600 | 1 | 10 | 30 |
| **Basic** | 99/mo | 4,000 | 6,000 | 5 | 50 | 300 |
| **Advanced** | 599/mo | 25,000 | 36,000 | 50 | 200 | 1,500 |
| **Custom** | Contact sales | Custom | Custom | Custom | Custom | Custom |

- AI Points are consumed per-token, rates vary by model (e.g., GPT-5-mini: 0.2 input / 1.6 output per 1K tokens)
- Extra resource packs available: 1K points = 15 CNY, up to 200K points with bulk pricing
- Annual plan: pay 10 months, get 12
- Self-hosted is **free** (Apache 2.0), users bring their own API keys via OneAPI

### Pricing Comparison

| Aspect | Dify | Coze | FastGPT |
|--------|------|------|---------|
| Free Tier | Yes (200 msgs) | Yes (10 credits/day) | Yes (100 points) |
| Entry Paid Plan | $59/mo | $9/mo | 99 CNY/mo (~$14) |
| Pricing Model | Monthly message credits | Daily message credits | AI Points (token-based) |
| Self-Hosted Cost | Free (OSS) | Free (OSS) | Free (OSS) |
| Model Costs | Separate (BYOK) | Included (cloud) / BYOK (self-hosted) | Included (cloud) / BYOK (self-hosted) |
| Currency | USD | USD | CNY |
| Best Value For | Teams needing many integrations | Individual / small projects | RAG-heavy Chinese market users |

---

## Summary & Recommendations

| Use Case | Recommended Platform |
|----------|---------------------|
| **Richest node ecosystem & integrations** | Dify -- 100+ model providers, extensive node types, mature plugin system |
| **Lowest cost entry for cloud** | Coze -- $9/mo Premium plan; generous free tier for exploration |
| **Best RAG / Knowledge Base focus** | FastGPT -- purpose-built for knowledge-base Q&A with strong Chinese model support |
| **Enterprise self-hosted** | Dify -- most mature deployment options, enterprise support available |
| **Quick prototyping** | Coze -- drag-and-drop with built-in database and image nodes |
| **Chinese market / domestic models** | FastGPT -- native support for Qwen, GLM, Doubao, Kimi, ERNIE via OneAPI |

---

## Sources

- [Dify Documentation](https://docs.dify.ai)
- [Dify Pricing](https://dify.ai/pricing)
- [Dify GitHub](https://github.com/langgenius/dify)
- [Coze Documentation](https://docs.coze.com)
- [Coze Pricing](https://www.coze.com/premium)
- [Coze Studio GitHub](https://github.com/coze-dev/coze-studio)
- [FastGPT Documentation](https://doc.fastgpt.io)
- [FastGPT Pricing](https://cloud.fastgpt.io/price)
- [FastGPT GitHub](https://github.com/labring/FastGPT)
- [OneAPI (Model Management)](https://github.com/songquanpeng/one-api)
