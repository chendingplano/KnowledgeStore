# Qwen3.8-Flash / Qwen3.8-27B 本地部署用户手册

**适用模型**：Qwen3.8-Flash（约 125B–180B 总参 / 6B 激活，MoE）与 Qwen3.8-27B（27B 稠密）  
**文档性质**：基于社区实测数据与框架文档整理，非阿里官方手册  
**重要提示**：两者定位截然不同。**Flash 是“大而稀疏”的 MoE 模型**，靠极低激活参数在消费级硬件上勉强可跑；**27B 是稠密模型**，硬件门槛低得多，4-bit 量化在 16–19GB 显存即可运行。选型时优先考虑 27B，除非你明确需要 Flash 的更大容量。


## 一、量化选项与影响

### 1.1 Qwen3.8-27B（稠密模型）

Unsloth 提供了完整的 GGUF 量化系列，是 27B 本地部署的首选来源。

| 量化级别 | 下载大小（约） | 最低运行内存/显存 | 质量影响 |
|---------|-------------|----------------|----------|
| UD-IQ2_XXS | 7.27 GB | 9–11 GB | 损失明显，仅适合验证 |
| UD-Q3_K_XL | 13.15 GB | 12–14 GB | 有可感知损失 |
| **UD-Q4_K_XL** | **17.56 GB** | **16–19 GB VRAM**（RTX 4090/5080 或 24GB Mac） | **社区推荐平衡点**，Unsloth 主推 |
| UD-Q6_K | 21.98 GB | 23–26 GB | 接近无损 |
| BF16 | 56 GB | 64GB+ | 无量化损失 |

**NVFP4 特殊选项**：Unsloth 还发布了 Qwen3.8-27B 的 NVFP4 动态量化版，在 Blackwell 架构 GPU（RTX 50 系、DGX Spark、B200）上比 BF16 **快约 1.5 倍**，24GB VRAM 即可运行。仅支持 vLLM（SGLang 不支持），需 `vllm>=0.25.0`。

### 1.2 Qwen3.8-Flash（MoE 模型）

Flash 的量化策略与 27B 完全不同。由于总参极大（社区实测 Q4_K_M 约 111 GiB），**纯 GPU 部署不现实**，必须依赖 CPU/SSD 卸载。

| 方案 | 来源 | 体积 | 硬件要求 | 实测速度 |
|------|------|------|---------|----------|
| UD-IQ1_S | PyPI `qwen38-flash-next` 包 | 约 74GB 磁盘 | 48GB 内存可纯 CPU 运行 | 社区未公布精确 tok/s |
| Q4_K_M | POCKET 打包 | 111 GiB | 32GB RAM + 8GB VRAM 笔记本实测可跑 | **4.17 tok/s**（生成），提示处理仅 1–2 tok/s |

**关键认知**：Flash 的 Q4 量化体积（111 GiB）是笔记本内存的 3.5 倍，能跑起来靠的是 llama.cpp 的 **mmap 按需加载**——专家层留在 RAM/SSD，每 token 只触碰激活的少数专家。**速度由 RAM 容量和 SSD 读取速度决定，而非 GPU 性能**。实测反直觉结论：不要把专家层塞进 GPU，8GB 显存用到 4.1GB 时速度最快，推到 7.9GB 反而因驱动分页降到 1.75 tok/s。


## 二、硬件要求

### 2.1 Qwen3.8-27B 硬件门槛

| 量化 | 内存/显存底线 | 典型硬件 | 备注 |
|------|-------------|---------|------|
| Q4_K_XL | **16–19 GB VRAM** | RTX 4090 / 5080 / 24GB Mac | 社区验证的可流畅运行档位 |
| Q3_K_XL | 12–14 GB | RTX 4060 Ti 16G / 12GB 卡（紧） | 质量有损失 |
| IQ2_XXS | 9–11 GB | 8GB 卡勉强 | 仅实验 |
| NVFP4 | 24GB VRAM | RTX 50 系 / DGX Spark | 需 Blackwell GPU + vLLM |

**独立显存 vs 统一内存**：Apple Silicon 的统一内存可被 GPU 直接使用，24GB Mac 跑 Q4 的体验接近 24GB 独显。但 **16GB 统一内存的 Mac 不能仅凭总内存判断可运行**，需给 macOS 留空间，建议从 Q3 或 IQ2 起步。

### 2.2 Qwen3.8-Flash 硬件门槛

| 方案 | RAM | VRAM | 存储 | 可行性 |
|------|-----|------|------|--------|
| IQ1_S（纯 CPU） | 48GB | 0 | 74GB+ | 可跑通，速度慢 |
| Q4_K_M（笔记本实测） | 32GB | 8GB | 111GB+ NVMe | **4.17 tok/s**，仅适合短回答 |
| 更大 RAM（64GB+） | 64GB+ | 8GB+ | 同上 | 预期更快（社区未精确实测） |

**Flash 不适合的场景**：需要快速多轮对话、长提示处理、或生产级吞吐。它的定位是“在现有笔记本上跑通前沿规模模型”的实验性方案，而非日常助手。


## 三、推荐配置与 Tokens/s 估算

> **说明**：以下 tok/s 为公开实测的单流生成速度。框架、量化、上下文长度、硬件差异均会影响结果。

### 配置一：Qwen3.8-27B 甜点配置（单卡 16–24GB GPU）

| 项目 | 规格 |
|------|------|
| 硬件 | RTX 4090 / 5080（16–24GB VRAM），或 24GB+ 统一内存 Mac |
| 量化 | Unsloth UD-Q4_K_XL（17.56 GB） |
| 框架 | llama.cpp（GGUF）或 MLX（Mac） |
| **参考 TG 速度** | **Mac M4 Max（40c）oQ8e-fp16-mtp 量化：约 13–18 tok/s**（16k–64k 上下文） |
| 备注 | 该数据来自 MLX 8-bit 量化而非 GGUF Q4，GGUF 速度可能略有差异但量级相近 |

**为什么推荐这个配置**：Q4_K_XL 在 17.56GB 体积下保持了接近无损的质量，16–24GB 显卡或 24GB Mac 即可容纳，是 27B 在“质量可接受”与“硬件可得性”之间的最佳交点。如果追求更快速度，可尝试 vLLM + NVFP4（需 Blackwell GPU），官方称比 BF16 快 1.5 倍，但**未公布具体 tok/s 数值**。

### 配置二：Qwen3.8-Flash 笔记本实验配置（32GB RAM + 8GB VRAM）

| 项目 | 规格 |
|------|------|
| 硬件 | Intel Core Ultra 7 356H（16 核）/ RTX 5060 Laptop 8GB / 32GB RAM / NVMe SSD |
| 量化 | POCKET Q4_K_M（111 GiB，3 分片） |
| 框架 | llama.cpp（stock 版本） |
| **实测生成** | **4.17 ± 0.17 tok/s**（8 线程） |
| **实测提示处理** | **1.02 ± 0.12 tok/s**（pp64） |
| 显存占用 | 4.1 GB（仅 8GB 的一半） |
| 优化要点 | 不要把专家层 offload 到 GPU，保持 `-ngl` 低值，让 mmap 管理专家层 |

**适用场景**：离线批量处理短文本、隐私敏感场景下的实验、验证 Flash 能力上限。**不适合**交互式聊天（提示处理太慢）或长文档任务。

### 配置三：Qwen3.8-27B 高性能配置（vLLM + NVFP4，Blackwell GPU）

| 项目 | 规格 |
|------|------|
| 硬件 | RTX 5090 / DGX Spark / B200 等 Blackwell 架构 GPU，24GB+ VRAM |
| 量化 | Unsloth Qwen3.8-27B-NVFP4 |
| 框架 | vLLM ≥ 0.25.0 + flashinfer-python ≥ 0.6.13 + nvidia-cutlass-dsl ≥ 4.5.2 |
| 加速选项 | 可加 `--speculative-config '{"method": "mtp", "num_speculative_tokens": 2}'` 启用投机解码 |
| **相对速度** | **约 BF16 的 1.5 倍**（官方数据，绝对 tok/s 未公布） |
| KV Cache 优化 | 附带 FP8 KV cache 校准，上下文长度可延长 2 倍 |

**适用场景**：已有 Blackwell GPU、追求 27B 最高推理速度、能接受 vLLM 部署复杂度。如果你用的是 RTX 40 系或更早的 GPU，**不要选这条路**，NVFP4 不兼容，应回到配置一的 GGUF/MLX 方案。


## 四、部署步骤速查

### 4.1 Qwen3.8-27B（llama.cpp / GGUF）

```bash
# 1. 下载模型（Unsloth GGUF）
pip install -U "huggingface_hub[cli]"
hf download unsloth/Qwen3.8-27B-GGUF \
  --local-dir ./Qwen3.8-27B-GGUF \
  --include "*UD-Q4_K_XL*"

# 2. 用 llama.cpp 运行
./llama.cpp/llama-cli \
  --model ./Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q4_K_XL.gguf \
  --ctx-size 8192 \
  --n-gpu-layers 99   # 全部 offload 到 GPU（显存足够时）
```
如果显存不足 16GB，降低 `--n-gpu-layers` 让部分层跑在 CPU 上，速度会下降但可运行。

### 4.2 Qwen3.8-27B（vLLM + NVFP4，仅 Blackwell）

```bash
uv venv nvfp4-env --python 3.13
source nvfp4-env/bin/activate
uv pip install "vllm>=0.25.0" "flashinfer-python>=0.6.13" \
  "nvidia-cutlass-dsl>=4.5.2" --torch-backend=auto

vllm serve unsloth/Qwen3.8-27B-NVFP4 \
  --speculative-config '{"method": "mtp", "num_speculative_tokens": 2}'
```
如遇 Torchcodec 报错，先 `sudo apt install ffmpeg` 再重启。

### 4.3 Qwen3.8-Flash（一键包 / 手动 llama.cpp）

**一键包方式**（最简）：
```bash
pip install qwen38-flash-next
qwen38-flash                    # 首次自动下载模型和运行时
qwen38-flash --say "你好"        # 单发测试
```
首次运行约需 74GB 磁盘。48GB 内存机器默认 `-ngl 0` 纯 CPU 运行（Metal 会因超大嵌入层 OOM）。

**手动 llama.cpp 方式**（使用 POCKET Q4_K_M）：
需使用支持 `qwen4exp` 架构的 llama.cpp 构建（PR #27742 尚未合入主线），按 POCKET 页面说明设置低 `-ngl` 值（如 1–2），保持专家层在 RAM/SSD 中。


## 五、注意事项

1. **Flash 的“能跑”不等于“好用”**：4.17 tok/s 的生成速度接近人类阅读速度，但提示处理仅 1–2 tok/s。输入 500 token 的提示需要 4–8 分钟才能开始生成。**它适合“给时间就能出结果”的离线任务，不适合交互**。

2. **27B 的 Q4 是社区共识起点**：Unsloth 主推 UD-Q4_K_XL，16–19GB 显存即可运行。如果你的硬件恰好在这个区间，不要盲目上更低量化——Q3 的质量损失可能比你节省的 4GB 显存更不划算。

3. **NVFP4 有硬件锁定**：仅 Blackwell（RTX 50 系、DGX Spark、B200/B300）支持。RTX 40 系及更早显卡无法使用，不要尝试。

4. **Flash 的模型版本需确认**：PyPI 包名为 `qwen38-flash-next`，对应的是 Flash-Next 版本。POCKET 打包标注为“180B total / 6B active”，而 PyPI 页面标注“125B MoE，6B 激活”。部署前务必核对模型卡中的确切参数量，避免下载错误版本。

5. **本手册基于 2026 年 11 月前的公开信息**。Qwen3.8 系列发布较新，框架支持仍在快速变化（尤其是 Flash 所需的 llama.cpp 特殊构建）。部署前查阅 Unsloth 文档的最新更新和 llama.cpp PR 状态。