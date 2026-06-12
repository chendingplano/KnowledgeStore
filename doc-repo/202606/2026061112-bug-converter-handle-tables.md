# Bug: Parser Result Converter Misses Table Images

- DocID: `doc-2026061112`
- **Status:** Implemented
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** parser result converter, extract table images, reference table images, table html representation

## Change Logs
- Created by Chen Ding on 2026/06/11
- Implemented by Codex on 2026/06/11: MinerU table conversion now emits table image references and preserves table HTML.

# Context
The parser result converter (refer to [1]) has two problems:
1. did not convert table images to the line files (reference to the table image).
1. should convert tables to the standard HTML format

Below is from the '.json' file:
```json
        {
          "type": "table",
          "img_path": "images/c9c09e1420e2ccd4d58cdc9684c47e0f9f014bff959e0b2f71324a91781fee2c.jpg",
          "table_caption": [
            "表1 室内家庭场景特点"
          ],
          "table_footnote": [],
          "table_body": "<table><tr><td>序号</td><td>特点</td><td>备注</td></tr><tr><td>1</td><td>长距离通信方式</td><td>有线或无线网络</td></tr><tr><td>2</td><td>近距离通信方式</td><td>星型、树型等结构的多级组合。</td></tr><tr><td>3</td><td>数据类型</td><td>双向低速率,间断或连续。</td></tr><tr><td>4</td><td>电信网可靠性要求</td><td>网关需有一个以上的不同路径路由到业务平台和服务器。</td></tr><tr><td>5</td><td>网关协作要求</td><td>同一个区域相同服务的多个网关之间不必相互协作。</td></tr><tr><td>6</td><td>网关处理能力要求</td><td>需要将各个传感器定时发送的信令和数据信息转换成广域网中传输的信令和数据格式,当下属节点数目众多时,信令处理能力要求较高。</td></tr><tr><td>7</td><td>业务平台处理能力</td><td>需要实时处理海量的信令信息,不要求能够管理到每一个传感器节点。</td></tr><tr><td>8</td><td>安全需求</td><td>电信网络和业务平台提供网关的认证与授权,各个节点的认证与授权可以由所属的网关来完成,也可以由电信网络和业务平台来完成。</td></tr><tr><td>9</td><td>加密</td><td>根据客户的需求和信息的敏感度,选择WSN网络数据和信令的加密以及网络数据和信令上、下行方向的加密。采集数据加密、存储数据加密</td></tr><tr><td>10</td><td>数据存储能力</td><td>传感器节点应能根据要求存储一定时间内(例如24小时、7天等)采集的数据;网关应至少具备保存下属传感器节点的位置、路由、拓扑信息的能力,在需要时还可以存储下属节点的数据信息。在需要网关作为传感器节点的认证点的时候,网关还应保存下属节点的认证与授权的信息。</td></tr><tr><td>11</td><td>终端辐射</td><td>终端设备中密封源的质量应符合GB4075;放射性安全性能应符合GB14052;符合GB18871规定的电离辐射指标。</td></tr><tr><td>12</td><td>终端功耗</td><td>终端功耗应符合卫生部2010年1月21日《医疗器械临床使用安全管理规范(试行)》。</td></tr><tr><td>13</td><td>能源供给方式</td><td>各种健康监测仪器采用电力或者电池供电方式;有线终端采用电力供电方式;无线终端采用电池供电方式。</td></tr><tr><td>14</td><td>覆盖能力</td><td>半开放性空间即有隔间的区域内覆盖范围应能达到10m~75m左右。</td></tr><tr><td>15</td><td>抗干扰能力</td><td>室内终端运转应能抵抗微波炉、电冰箱等家用电器的电磁干扰,并符合家用电器电磁干扰限制要求。</td></tr></table>",
          "bbox": [
            90,
            529,
            926,
            935
          ],
          "page_idx": 7
        },
```
But its line file does not have the corresponding line to reference to the table image
and the table is not expressed in the HTML format.
```text
132	8	table-row	unknown-font	12	[90, 529, 926, 935]	|序号|特点|备注|
133	8	table-row	unknown-font	12	[90, 529, 926, 935]	|1|长距离通信方式|有线或无线网络|
134	8	table-row	unknown-font	12	[90, 529, 926, 935]	|2|近距离通信方式|星型、树型等结构的多级组合。|
135	8	table-row	unknown-font	12	[90, 529, 926, 935]	|3|数据类型|双向低速率,间断或连续。|
136	8	table-row	unknown-font	12	[90, 529, 926, 935]	|4|电信网可靠性要求|网关需有一个以上的不同路径路由到业务平台和服务器。|
137	8	table-row	unknown-font	12	[90, 529, 926, 935]	|5|网关协作要求|同一个区域相同服务的多个网关之间不必相互协作。|
```

# Decision

For MinerU `table` items, the line file should preserve the parser-provided HTML table instead of converting it to Markdown-style `table-row` fragments.

The table image reference is represented as its own line:

```text
<n>	<page>	table-image	unknown-font	12	<bbox>	<item.img_path>
```

The table body is represented as one HTML line:

```text
<n>	<page>	table	unknown-font	12	<bbox>	<item.table_body>
```

Caption and footnote lines remain unchanged.

## Implementation

### Modified Files

- `ChenWeb/server/api/file-converters/mineru.go` — changed MinerU `table` handling to emit `table-caption`, optional `table-image`, one `table` line containing `table_body`, and `table-footnote`; removed the MinerU-only HTML-to-Markdown row parsing path.
- `ChenWeb/server/api/file-converters/service_test.go` — updated MinerU table tests to verify `table-image`, preserved HTML table content, entity preservation, and pipe preservation inside HTML.

### Output Order

For each MinerU table item the converter now emits:

1. One `table-caption` line per non-empty `table_caption` entry.
2. One `table-image` line when `img_path` is non-empty.
3. One `table` line when `table_body` is non-empty.
4. One `table-footnote` line per non-empty `table_footnote` entry.

## Operational Behavior

The example table in this bug should now produce a `table-image` line pointing to:

```text
images/c9c09e1420e2ccd4d58cdc9684c47e0f9f014bff959e0b2f71324a91781fee2c.jpg
```

and one `table` line whose content is the original `<table>...</table>` HTML string from `table_body`.

## Consequences

### Positive

- Table images are no longer silently dropped.
- Table structure is preserved as HTML, including multi-row content and HTML entities.
- Downstream processors can choose whether to render the table image, parse the HTML table, or use both.

### Trade-offs

- MinerU table output is no longer the same line shape as OpenData table output. OpenData still emits `table-row`; MinerU now emits `table`.
- Any downstream prompt or processor that only looks for `table-row` must be updated to also understand `table` HTML lines.

## Verification

Focused verification:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/file-converters
```

Result: passed.

## Documentation Impact

- Updated this bug document.
- Affected specs/docs:
  - `KnowledgeStore/Capsules/coding-capsules/pdf-result-convert/+pdf-result-convert.md`
  - `KnowledgeStore/Capsules/coding-capsules/pdf-result-convert/mineru-converter.md`
- Stale until separately updated: converter docs that still describe MinerU tables as `table-row` Markdown output.
- Intentionally left undocumented here: downstream prompt/processor changes for consuming `table` HTML lines; those require separate review because OpenData still emits `table-row`.

# References
[1] KnowledgeStore/Capsules/coding-capsules/pdf-result-convert/+pdf-result-convert.md
