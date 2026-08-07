---
description: "AI 应用层软件开发一键流水线：深度分析模型 → 生成详细设计文档 (SDD) → 生成并执行 Simulink Test 单元测试。一条命令完成 SDD + 测试。"
name: "Run AI Pipeline"
argument-hint: "<model.slx> [Strategy] [Coverage] [ExcelFile]"
agent: "agent"
---

# Run AI Pipeline (SDD + Unit Tests)

针对一个 Simulink 模型，一键执行完整自动化流水线：

```
[1] 深度分析模型   → analyzeModelDeepForSDD  (knowledge JSON)
[2] 生成详细设计   → DdGeneration_AI         (SDD 文档)
[3] 生成+执行测试  → generateUnitTests        (Simulink Test + 报告)
```

## Usage

```
/runAIPipeline Model.slx
/runAIPipeline Model.slx Strategy=comprehensive
/runAIPipeline Model.slx Strategy=boundary Coverage=decision
/runAIPipeline Model.slx ExcelFile=Model_interface.xlsx
```

## 步骤

1. **定位脚本**：`work/scripts/pipeline/runAIPipeline.m`
2. **构建 MATLAB 命令**：

   ```matlab
   % 完整流水线（默认 basic 测试策略）
   results = runAIPipeline('path/to/Model.slx');

   % 完整流水线 + 综合测试 + 决策覆盖率 + Excel 接口
   results = runAIPipeline('path/to/Model.slx', ...
       'Strategy', 'comprehensive', ...
       'Coverage', 'decision', ...
       'ExcelFile', 'Model_interface.xlsx');
   ```

3. **在 MATLAB 终端执行**（确保已 `satk_initialize`），展示输出

## 输出产物

| 阶段 | 产物 | 位置 |
|------|------|------|
| 分析 | `{Model}_model_knowledge.json` | 模型目录 |
| SDD | `{Model}_DetailDesign.md` | 模型目录 |
| 测试 | `{Model}_*Tests.feature` + HTML 报告 | `_tests/` 目录 |

## 阶段可单独运行

如果只需要其中一步：

- 只分析：`/generateSDD`（含 analyze + DdGeneration_AI）
- 只测试：`/generateModelTests`（或 `/generateUnitTests`）

## Prerequisites

- MATLAB 已运行 `satk_initialize`
- Simulink Test 许可证（执行测试时）
- Simulink Coverage 许可证（`Coverage=decision` 时）
- 模型可加载

## 注意

- `RunTests=false` 可只生成测试不执行（快速预览 .feature 内容）
- `DraftMode=true` 快速迭代；如遇类型/维度错误需回退到完整编译
