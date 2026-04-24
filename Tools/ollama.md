# API Access

Ollama exposes a local API at `http://localhost:11434`. Use it with coding agents:

```text
# Chat completion (OpenAI-compatible)
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "model-name", // replace it with your model name
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```
# Install a Model

# Useful Commands

| Command	| Description |
|:----------|:------------|
|ollama list	| List downloaded models |
|ollama ps	| Show running models & memory usage |
|ollama pull gemma4:latest	| Update model to latest version |
|ollama pull qwen3.6:35b-a3b | Pull Qwen 3.6 |
| ollama run gemma4:26b | Pull Gemma 4 26B |
|ollama run gemma4:latest	| Interactive chat |
|ollama stop gemma4:latest	| Unload model from memory |
|ollama rm gemma4:latest	| Delete model |


# Uninstall ollama

```bash
brew uninstall --cask ollama-app
```

# What's New in Ollama v0.19+ (March 31, 2026)
## MLX Backend on Apple Silicon
On Apple Silicon, Ollama automatically uses Apple's MLX framework for faster inference — no manual configuration needed. M5/M5 Pro/M5 Max chips get additional acceleration via GPU Neural Accelerators. M4 and earlier still benefit from general MLX speedups.

## NVFP4 Support (NVIDIA)
Ollama now leverages NVIDIA's NVFP4 format to maintain model accuracy while reducing memory bandwidth and storage requirements for inference workloads. As more inference providers scale inference using NVFP4 format, this allows Ollama users to share the same results as they would in a production environment. It further opens up Ollama to run models optimized by NVIDIA's model optimizer.

## Improved Caching for Coding and Agentic Tasks
- Lower memory utilization: Ollama reuses its cache across conversations, meaning less memory utilization and more cache hits when branching with a shared system prompt — especially useful with tools like Claude Code.
- Intelligent checkpoints: Ollama stores snapshots of its cache at intelligent locations in the prompt, resulting in less prompt processing and faster responses.
- Smarter eviction: Shared prefixes survive longer even when older branches are dropped.

# Referece
[1] https://gist.github.com/greenstevester/fc49b4e60a4fef9effc79066c1033ae5
