# 接口审查（模型 vs 需求）

## 1. 解析需求接口

从需求文档提取顶层接口表（输入/输出），逐项记录：名称、数据类型、单位、范围/编码、含义。
- docx → 文本（python-docx / pandoc / MATLAB 读 word XML）；spec JSON → 直接读 `inputs` / `outputs`。

## 2. 读取模型接口

- `model_overview(model, scope='root', detail='interfaces')` → 顶层与 MainSubsystem 端口；
- `model_query_params` 核对每个端口的 `OutDataTypeStr`（类型）与端口顺序。

## 3. 逐项比对清单

| 检查项 | 通过条件 |
|--------|----------|
| 端口集合 | 模型端口与需求接口一一对应：无缺失、无多余 |
| 端口名称 | 与需求一致，或按建模风格合法化后仍可追溯 |
| 端口顺序 | 顶层与 MainSubsystem 端口 1:1 同序 |
| 数据类型 | 与需求一致（enum→uint8、boolean、uint8/16、single 等） |
| 单位/范围 | 与需求一致；Min/Max 或描述符合 |
| 质量/状态标志方向 | 布尔“1=异常 or 1=正常”与需求一致（易反向） |

## 4. 常见接口问题

- 端口缺失/多余（需求有但模型没有，或反之）；
- 类型不匹配（double 替代 single、enum 编码错误、boolean 反向）；
- 单位/范围不一致（阈值标定单位换算错误）；
- MainSubsystem 与顶层端口未 1:1 镜像；
- 命名不可追溯（与需求信号名无法映射）。

## 5. 输出示例

| 编号 | 需求ID | 位置 | 问题 | 严重度 | 建议 |
|------|--------|------|------|--------|------|
| I-01 | REQ-1 | 模型顶层 Inport | 需求为 boolean(1=异常)，模型类型为 uint8 | 高 | 改为 boolean 并核对方向 |
