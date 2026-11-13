# Extract Products 产品提取用户手册

- **title:** Extract Products 产品提取用户手册
- **language:** zh-hans
- **format:** markdown
- **version:** 1.0
- **status:** 草稿
- **author:** Codex
- **owner:** 未指定
- **audience:** 文档处理用户、审核人员和运维人员
- **create-time:** 2026-11-13T04:59:07-06:00
- **last-modify-time:** 2026-11-13T05:19:26-06:00
- **keywords:** extract_products, 产品提取, 产品关系, 文档处理, 证据, 产品审核, 知识库

## Extract Products 的用途

`extract_products` 从已处理的文档中查找提及的产品，并记录文档与这些产品的关系。审核标准、法规或其他文档时，它可以帮助查找文档涉及的物品、材料、设备或产品类别，以及与其有关的要求或其他表述。

该处理器使用 AI 模型，输出结果应作为审核的起点。重要发现需要与原文核对；模型可能遗漏产品、判断错关系或误解文段。

产品可以是实物、设备、材料、部件、产品类别、软件，也可以是废弃物类别或废弃物流。提取规则会区分可移动的物品与场所、设施：例如，垃圾容器是产品，而垃圾收集点是场所。如果某产品只出现在被引用文献的标题中，这不足以证明当前文档讨论了该产品。

## 如何理解提取结果

每条结果表示一个产品及其与文档的一种关系。因此，当文档以不同方式涉及同一产品时，该产品可能有多条记录。记录可能包含：

- 产品名称、规范化名称、产品类型和类别信息。
- 关系类型，以及对文档相关内容的摘要。
- 支持该结果的证据，包括可用的原文引文或来源行号。
- 识别出的要求、义务程度、条件、例外、参数和责任主体。
- 置信度及其说明（如有）。置信度由模型给出，不能证明结果正确。
- 启用翻译时，受支持字段的英文内容。

例如，如果文档既定义了某种容器，又规定了它的存储要求，结果可能分别记录定义关系和要求关系。审核时应结合上下文检查每条记录的证据和措辞；字段为空只表示没有记录值，并不证明文档中没有相关内容。

## 处理阶段

产品提取前必须完成文档分块。下表中的“必须”指正常的完整提取流程；仅供测试的第一遍模式会提前结束。

| 阶段 | 产生的内容 | 必须或可选 | 相关环境变量 |
| --- | --- | --- | --- |
| 第一遍：提取产品提及 | 从各文档块中提取产品名称、类型提示、证据和置信度。 | 标准流程必须执行；启用合并模式时由合并阶段替代。 | `EXTRACT_PRODUCT_MENTIONS_PROMPT`、`EXTRACT_PRODUCT_MENTIONS_MODEL_NAME`、`EXTRACT_PRODUCT_MODEL_NAME` |
| 步骤 A：合并提及 | 合并去重，生成产品候选项；不调用 LLM。 | 标准流程（包括仅第一遍测试）必须执行；合并模式下被替代。 | `EXTRACT_PRODUCTS_MERGED_PASS`、`EXTRACT_PRODUCT_PASS_1_ONLY` |
| 第二遍：补充关系 | 识别产品与文档的关系、摘要、证据，以及发现的要求、条件、例外、参数和责任主体。 | 标准完整流程必须执行；合并模式替代此阶段，仅第一遍测试会跳过此阶段。 | `ENRICH_PRODUCT_MENTION_PROMPT`、`ENRICH_PRODUCT_RELATIONS_MODEL_NAME`、`EXTRACT_PRODUCT_MODEL_NAME` |
| 合并阶段 | 同时提取产品提及及其关系，以及证据和其他支持的细节。 | 可选，替代第一遍、步骤 A 和第二遍。 | `EXTRACT_PRODUCTS_MERGED_PASS`、`EXTRACT_PRODUCT_MERGED_PROMPT`、`EXTRACT_PRODUCT_MENTIONS_MODEL_NAME`、`EXTRACT_PRODUCT_MODEL_NAME` |
| 步骤 B：最终去重 | 删除重复的产品关系记录；不调用 LLM。 | 标准或合并完整流程中，关系提取后执行。 | 测试模式下由 `EXTRACT_PRODUCT_PASS_1_ONLY` 跳过。 |
| 第三遍 a：翻译 | 为支持的已提取文本字段生成英文内容。 | 可选；翻译提示词和可用翻译模型均存在时启用。个别失败的批次或记录可能未翻译。 | `TRANSLATE_PRODUCTS_PROMPT`、`TRANSLATION_MODEL_NAME`、`ENRICH_PRODUCT_RELATIONS_MODEL_NAME`、`EXTRACT_PRODUCT_MODEL_NAME`、`TRANSLATE_PRODUCTS_BATCH_SIZE`、`TRANSLATE_PRODUCTS_THINKING` |
| 第三遍 b：解析名称和类别 | 将名称匹配至产品目录并复制可用的目录类别；未匹配的名称会作为待审核名称提出。不调用 LLM。 | 标准或合并完整流程中执行；仅第一遍测试会跳过。未匹配名称可能没有类别。 | `EXTRACT_PRODUCTS_MAX_TASKS`；`CATEGORIZE_PRODUCTS_MODEL_NAME` 已停用，不再使用。 |
| 保存和索引 | 将记录保存到 `kb.products`，写入 `.products` 产物并更新产品索引。 | 正常完成的完整流程会执行；仅第一遍测试保存的是不完整的候选记录。 | `ARTIFACT_DIR` |

是的：当 `EXTRACT_PRODUCTS_MERGED_PASS=true` 时，处理器对**每个文档块调用一次 LLM**，同时识别产品并提取其关系。它替代第一遍、步骤 A 和第二遍；后续的最终去重、可选翻译、目录解析和保存仍会执行。重试或翻译可能产生额外调用。合并阶段使用产品提及模型和 `EXTRACT_PRODUCT_MERGED_PROMPT`。该开关未设置或为 `false` 时，运行标准的分阶段流程。如果同时启用合并模式和仅第一遍模式，则以合并模式为准。

`EXTRACT_PRODUCTS_MAX_TASKS` 控制提取任务的并发数量，也用于翻译和目录解析。`EXTRACT_PRODUCTS_REASONING` 和 `EXTRACT_PRODUCT_MODEL_FALLBACK` 对提取调用的作用见下文。

结果保存在 `kb.products` 中。提交目录审核的待审核名称不等同于已批准的目录条目。

## 运行和审核

1. 在文档处理流程中选择文档，确保流程包含分块步骤，或该文档已完成分块。在本次运行的处理器中选择 `extract_products`。
2. 启动处理，并查看文档中 `extract_products` 的处理状态。如果失败，查看报告的错误，或请运维人员检查处理器日志。
3. 打开 Products（产品）视图，找到该文档的提取记录。对照原文审核每个产品、关系和支持证据，尤其注意条件、例外和责任主体。
4. 如果需要评估提取是否完整，可在已有经审核的产品基准时，将结果与基准比较。基准及其评分独立于生产环境中的提取结果。

具体可用的操作控件取决于已配置的文档处理流程。如果无法选择 `extract_products`，请运维人员检查所选处理流程及其配置。

## 重新处理文档

如果文档已有产品记录，普通运行会跳过该文档的产品提取。如需重新生成，请使用处理流程中的强制选项。强制运行会替换该文档现有的产品记录；运行前请审核或保留需要的结果。处理可能失败，因此应检查最终状态和记录，不要直接假定替换成功。

## 运维设置和故障排查

模型、提示词和运行设置在处理器的环境中配置。运维人员应核实正在运行的服务实际使用的配置，在比较不同环境时尤其如此。模型引用通过 `MODEL_DEF_FILE` 解析。

| 设置 | 用途 |
| --- | --- |
| `EXTRACT_PRODUCT_MENTIONS_PROMPT` | 第一遍提示词；默认为 `prompt-extract-product-mentions-v2.md`。 |
| `EXTRACT_PRODUCT_MENTIONS_MODEL_NAME` | 第一遍和合并阶段使用的模型；回退到 `EXTRACT_PRODUCT_MODEL_NAME`。 |
| `ENRICH_PRODUCT_MENTION_PROMPT` | 第二遍提示词；默认为 `prompt-enrich-product-mention-v4.md`。 |
| `ENRICH_PRODUCT_RELATIONS_MODEL_NAME` | 第二遍使用的模型；回退到 `EXTRACT_PRODUCT_MODEL_NAME`。也可作为翻译模型的后备设置。 |
| `EXTRACT_PRODUCT_MODEL_NAME` | 未设置对应阶段的产品提及或关系模型时使用的通用后备模型引用；也是翻译模型的最后一个后备选项。它不同于下方的重试模型。 |
| `EXTRACT_PRODUCT_MODEL_FALLBACK` | 可选的重试模型引用，在主要提取调用失败时使用。某些旧版空响应情况会直接作为空结果处理，不会重试。 |
| `EXTRACT_PRODUCT_MERGED_PROMPT` | 合并模式使用的提示词；默认为 `prompt-extract-products-merged-v3.md`。 |
| `EXTRACT_PRODUCTS_MERGED_PASS` | 启用按文档块合并执行的提取调用；默认为 `false`。 |
| `EXTRACT_PRODUCTS_REASONING` | 控制产品提及、关系、合并及后备提取模型的服务端思考。默认 `true` 保留各模型配置的思考设置；`false` 强制关闭。此设置不控制翻译，且可能影响提取质量。 |
| `EXTRACT_PRODUCTS_MAX_TASKS` | 受支持阶段的并发任务上限；默认为 1。 |
| `TRANSLATE_PRODUCTS_PROMPT` | 翻译提示词；默认为 `prompt-translate-products-v2.md`。 |
| `TRANSLATION_MODEL_NAME` | 翻译模型；依次回退到 `ENRICH_PRODUCT_RELATIONS_MODEL_NAME` 和 `EXTRACT_PRODUCT_MODEL_NAME`。 |
| `TRANSLATE_PRODUCTS_BATCH_SIZE` | 每次翻译调用处理的产品记录数；默认为 10。 |
| `TRANSLATE_PRODUCTS_THINKING` | 翻译的思考设置，独立于提取推理设置；默认关闭。 |
| `CATEGORIZE_PRODUCTS_MODEL_NAME` | 已停用：此处理器不读取该变量。类别来自产品目录，不再由 LLM 分类阶段生成。 |
| `EXTRACT_PRODUCT_PASS_1_ONLY` | 仅用于测试：保存去重后的产品提及候选项，不进行关系补充、翻译或名称与类别解析。默认为 `false`；不要在生产环境启用。合并模式优先。 |
| `ARTIFACT_DIR` | 正常 `.products` 产物文件的基础目录。 |

在 `mise.local.toml` 中设置布尔值时，应使用 `"false"` 这样的带引号字符串；不带引号的 TOML `false` 会取消设置该变量，使处理器可能使用默认值。启动环境中的提示词和模型设置可以覆盖默认值。

如果没有看到结果，请检查分块是否成功、选择的文档是否正确，以及处理流程是否包含该处理器且已完成。已有结果会使普通运行跳过提取。如果运行报告模型、提示词或产物文件错误，应由运维人员检查服务配置和日志。如果结果缺少关系或类别，请检查是否启用了仅供测试的第一遍提取设置。翻译字段为空也可能是因为翻译未启用或缺少源内容。

## 更多信息

- [产品提取规格说明](../../Capsules/coding-capsules/doc-processor/extract-products-spec.md)详细介绍了处理过程、配置、失败处理和输出字段。
- [产品基准开发文档](../devdocs/202611/2026110803-devdoc-products-benchmark.md)介绍了经审核的基准及其评分。

## Change Log

| 版本 | 时间 | 作者 | 原因 | 摘要 |
| --- | --- | --- | --- | --- |
| 1.0 | 2026-11-13T05:19:26-06:00 | Codex | 补充处理过程与配置 | 增加各阶段要求、合并调用行为和环境变量说明。 |
| 1.0 | 2026-11-13T04:59:07-06:00 | Codex | 创建中文译本 | 翻译产品提取、结果审核、重新运行和运维设置说明。 |
