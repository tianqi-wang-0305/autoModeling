---
name: simulink-requirement-review
description: "Review a Simulink model against software requirements: verify the input/output interface (port names, types, units, ranges, order, MainSubsystem mirroring) and the functional logic (per-subsystem behavior, thresholds, comparison directions, calibrations, state machines, counters/debounce, gating/arbitration) using the Simulink Agentic Toolkit skills and MCP tools. Use when the user asks to check whether a built Simulink model correctly implements a requirements document (docx/md/spec JSON), review model vs requirements, or validate I/O interface and logic against requirements."
---

# Simulink 需求审查（模型 vs 需求）

根据软件需求文档，**只读**审查 Simulink 模型是否正确实现需求：

1. **输入输出接口**：端口名称/类型/单位/范围/顺序、MainSubsystem 1:1 镜像、缺失/多余端口、枚举与布尔标志方向；
2. **功能逻辑**：每个需求对应的子系统实现、阈值与比较方向、标定量、状态机转移与优先级、计数/防抖/超时、门控/仲裁；
3. **输出审查报告**：发现项按需求 ID 映射，含位置、问题描述、严重度、建议。

统一调用 Simulink Agentic Toolkit 的 MCP 工具与自带技能，不修改模型。

## Workflow

1. **输入确认**
   - 需求文件（docx / md / spec JSON）路径 + 模型名/路径；
   - `detect_matlab_toolboxes` 确认 Simulink 可用；打开/加载模型（只读）。
2. **解析需求**（见 `references/interface-review.md`）
   - 提取：顶层接口表（输入/输出：名称、类型、单位、范围、含义）、功能需求（按子系统/功能点）、标定量（cal_*）、状态机与阈值要求；
   - 建立“需求 ID → 接口/功能点”清单。
3. **读取模型（只读）**
   - `model_overview`（层级/接口）、`model_read`（逐子系统逻辑表达式）、`model_query_params`（端口类型、阈值、常量）、`model_resolve_params`（标定量数值）；
   - `model_check`（未连接端口/线、stateflow_lint）作为结构健康度证据。
4. **接口审查**（见 `references/interface-review.md`）
   - 顶层端口 vs 需求接口表逐项比对：名称/类型/单位/范围/顺序；
   - MainSubsystem 端口 1:1 镜像；枚举/编码、布尔质量标志方向等易错点。
5. **功能逻辑审查**（见 `references/logic-review.md`）
   - 每个功能需求 → 定位实现子系统 → 用 `model_read` 表达式核对语义（比较方向、滞环、防抖周期数、状态机转移/优先级、门控/仲裁、标定量数值与单位）；
   - 状态机用 `stateflow_lint` 与转移表核对可达性/优先级/缺失转移；
   - 可选：对关键场景用 `sim` 或 `model_test` 快速验证行为（佐证，不改模型）。
6. **输出报告**
   - 发现项清单：| 编号 | 需求ID | 位置 | 问题描述 | 严重度 | 建议 |
   - 通过项摘要；“需求未覆盖 / 模型多余功能”清单。

## 关键约束

- **只读**：不 `set_param` / `add_block` / 改结构；结论不依赖修改模型；
- 接口以需求文档为准，模型偏差均记录（含“需求未要求但模型存在”的端口/逻辑）；
- 统一调用 Toolkit 技能：
  - `building-simulink-models`（model_read / model_overview / model_query_params / model_resolve_params / model_check 工作流）
  - `simulink-modeling-style`（若模型按该风格建模，一并核对命名/类型/描述规范）
  - `checking-model-compliance`（如需 MISRA/MAB 等规范预检）
  - `testing-simulink-models`（可选：用测试/仿真佐证功能正确性）
- 严重度定义：高=功能与需求相悖或接口错误；中=边界/时序/类型偏差；低=命名/描述/风格问题。

## Resources

- `references/interface-review.md` — 接口审查清单与比对方法
- `references/logic-review.md` — 功能逻辑审查方法、需求→子系统映射、严重度与报告模板
