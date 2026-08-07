# 应用层软件自动化开发方案

本文档汇总如何基于 **Simulink Agentic Toolkit** 实现应用层软件（汽车/嵌入式）开发三大环节的自动化：

1. **模型搭建**（NL 需求 → Simulink 模型骨架）
2. **详细设计文档 SDD 生成**（深分析 + 自动成文，减少人工）
3. **单元测试用例生成 + 执行**（Simulink Test / MIL）

## 总览

```
┌─────────────────────────────────────────────────────────────────┐
│  runAIPipeline.m  (一键流水线)                                    │
│                                                                 │
│  [1] 需求 → 模型搭建                                              │
│      /buildModel 命令 + model_edit MCP 工具                       │
│      SKILL: build-simulink-from-requirements                     │
│                                                                 │
│  [2] 模型 → 详细设计文档 (SDD)                                    │
│      analyzeModelDeepForSDD.m  (深分析 → knowledge JSON)         │
│      DdGeneration_AI.m          (knowledge JSON → SDD 文档)      │
│                                                                 │
│  [3] 模型 → 单元测试 (MIL)                                       │
│      generateUnitTests.m       (接口 → Gherkin .feature)         │
│      model_test                (执行 Simulink Test)             │
└─────────────────────────────────────────────────────────────────┘
```

## 一、模型搭建（Model Building）

- **入口**：`/buildModel` 命令（`.github/prompts/create-model.prompt.md`）
- **Skill**：`work/scripts/model_gen/.github/skills/build-simulink-from-requirements/SKILL.md`
- **核心工具**：`model_edit`（MCP / MATLAB 函数）
- **架构规范**：
  - 命名 `{type}{Name}`（`u16VehicleSpeed`），标定 `cal_{type}{Name}`
  - 禁止 `double`，浮点一律 `single`
  - 只用基本模块（Gain+Sum+Integrator 搭 PID，禁用 PID Controller 库模块）
  - 结构：Root → `MainSubsystem` → `SignalAcquisition` / `{功能SS}` / `OutputArbitration`
- **收尾**：`autoLayoutModel('ModelName')` 递归布局

## 二、详细设计文档生成（SDD Generation）

### 两阶段架构

```
阶段 A：深度分析（慢，可缓存）
    analyzeModelDeepForSDD('Model.slx')
    → 输出 {Model}_model_knowledge.json
       ├── 模型层次结构 (model_overview)
       ├── 每个子系统的 I/O 契约、内部模块、逻辑表达式 (model_read)
       ├── 标定参数 (cal_* 变量)
       └── 求解器配置

阶段 B：快速成文（复用 JSON，秒级）
    DdGeneration_AI('Model.slx')   % 自动定位 JSON
    → 输出 {Model}_DetailDesign.md / .pdf
```

### 相比传统 `DdGeneration.m` 的改进

| 维度 | 传统 DdGeneration | AI 增强 (本方案) |
|------|------------------|-----------------|
| 描述来源 | 浅层 keyword 匹配 | `model_read` 深度读取每个子系统 |
| 内部逻辑 | 只列模块名 | 提取模块参数、逻辑表达式、信号流 |
| 标定参数 | 依赖 Excel | 从模型直接提取 `cal_*` 并解析数值 |
| 一致性 | 手工维护 | 100% 从模型派生，零人工编辑 |
| 格式 | PDF 单一 | Markdown（可 review）+ PDF |

## 三、单元测试生成与执行（Unit Test / MIL）

### 自动化流程

```
generateUnitTests('Model.slx', 'Strategy', 'comprehensive', 'Coverage', 'decision')
    ├── [1] 读取目标接口（Inport/Outport + 类型 + Min/Max）
    ├── [2] 按策略生成场景
    │        basic          → 常值 / 零输入 / 最大输入
    │        boundary       → + 每个数值输入的阶跃响应
    │        comprehensive  → + 布尔开关切换 + 斜坡输入
    ├── [3] 写出 Gherkin .feature 文件（TOML front-matter 规范）
    └── [4] model_test 执行（draft_mode 快速迭代）→ HTML 报告
```

### 测试文件规范

- 每个 `.feature` 文件带 TOML front-matter（model/component/inputs/outputs）
- 激励语法：`const(x)` / `step(a -> b @ ts)` / `ramp(a -> b over ts)` / `pulse(width, period)`
- 输出校验：`{Signal}: {Signal} == [min .. max]`（有限性检查）
- 与 `feature2SignalEditor.m` 兼容（可转 Signal Editor `.mat`）

## 四、一键流水线

```matlab
% 在 MATLAB 中（先 satk_initialize）
runAIPipeline('Foc_2024b.slx');
runAIPipeline('Foc_2024b.slx', 'Strategy', 'comprehensive', 'Coverage', 'decision', ...
              'ExcelFile', 'Foc_2024b_interface.xlsx');
```

## 文件清单

| 文件 | 说明 |
|------|------|
| `scripts/ai_sdd/src/analyzeModelDeepForSDD.m` | 深度分析 → knowledge JSON |
| `scripts/ai_sdd/src/DdGeneration_AI.m` | knowledge JSON → SDD 文档 |
| `scripts/test_gen/src/generateUnitTests.m` | 接口 → 单元测试 + 执行 |
| `scripts/pipeline/runAIPipeline.m` | 三合一流水线 |
| `scripts/model_gen/...` | 模型搭建 Skill + Prompt |
| `scripts/layout_gen/src/autoLayoutModel.m` | 自动布局 |

## 环境要求

- MATLAB R2025a（含 Simulink、Simulink Test、Simulink Coverage、Report Generator）
- Simulink Agentic Toolkit 已初始化（`satk_initialize`）
- 模型需可加载（依赖的 InitVar/校准脚本需先在 base workspace 运行）

## 已知限制 / 后续优化

- `model_test` 执行依赖 toolkit 的 Gherkin 解析器；`draft_mode=true` 快但类型问题需回退
- `DdGeneration_AI` PDF 模式依赖 `slreportgen`（MATLAB Report Generator 工具箱）
- 状态机类逻辑（Stateflow）建议在 SDD 中人工补充状态转移图说明
