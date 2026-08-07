---
description: "AI 增强的详细设计文档 (SDD) 生成。深度分析 Simulink 模型（每个子系统的 I/O、内部逻辑、标定），自动生成非手工、符合规范的 Detail Design 文档。"
name: "Generate AI SDD"
argument-hint: "<model.slx> [KnowledgeFile] [ExcelFile] [Format]"
agent: "agent"
---

# Generate AI-Enhanced SDD (Detailed Design Document)

使用 Simulink Agentic Toolkit 深度分析模型，自动生成非手工的、符合规范的详细设计文档。这是两阶段流程，可重复运行（分析结果 JSON 可缓存）。

## Usage

```
/generateSDD Model.slx
/generateSDD Model.slx ExcelFile=Foc_interface.xlsx
/generateSDD Model.slx Format=pdf
/generateSDD Model.slx KnowledgeFile=Model_model_knowledge.json
```

## 工作流程（必须按此顺序）

### Phase 1: 深度分析模型

1. **定位脚本**：`work/scripts/ai_sdd/src/analyzeModelDeepForSDD.m`
2. **构建 MATLAB 命令**：

   ```matlab
   % 分析模型，生成 knowledge JSON（慢，可缓存）
   result = analyzeModelDeepForSDD('path/to/Model.slx', ...
       'OutputDir', 'reports/', 'Verbose', true);
   ```

3. **确认产物**：`reports/Model_model_knowledge.json` 已生成，包含：
   - 模型层次结构（model_overview）
   - 每个子系统的 I/O 契约、内部模块、逻辑表达式（model_read）
   - 标定参数（cal_* 变量）
   - 求解器配置

### Phase 2: 生成详细设计文档

1. **定位脚本**：`work/scripts/ai_sdd/src/DdGeneration_AI.m`
2. **构建 MATLAB 命令**：

   ```matlab
   % Markdown（默认，便于 review）
   DdGeneration_AI('path/to/Model.slx');

   % PDF（需要 MATLAB Report Generator）
   DdGeneration_AI('path/to/Model.slx', 'Format', 'pdf');

   % 带 Excel 接口/标定补充
   DdGeneration_AI('path/to/Model.slx', 'ExcelFile', 'Model_interface.xlsx');
   ```

3. **展示结果**：打开生成的 `Model_DetailDesign.md` / `.pdf` 向用户展示关键章节（概述、顶层接口、标定、子系统详细设计）

## 输出文档结构

```
Model_DetailDesign.md
├── 1. 概述          ← 模型层次结构
├── 2. 顶层接口      ← 输入/输出信号表（名称/类型/Min/Max/描述）
├── 3. 标定参数      ← 从模型提取的 cal_* 变量
└── 4. 子系统详细设计 ← 每个子系统的 I/O + 内部模块 + 标定 + 逻辑表达式
```

## 原则

- **非手工**：所有描述 100% 从模型派生，零人工编辑
- **可缓存**：分析（慢）与成文（快）分离，JSON 可复用
- **可追溯**：每个子系统附 model_read 逻辑表达式，可追溯至模型

## Prerequisites

- MATLAB 已运行 `satk_initialize`
- 模型可加载（依赖脚本已在 base workspace 运行）
- PDF 模式需要 MATLAB Report Generator（`slreportgen`）

## 一键流水线（可选）

如果要同时生成 SDD + 单元测试：

```matlab
runAIPipeline('path/to/Model.slx', 'ExcelFile', 'Model_interface.xlsx');
```

详见 `/runAIPipeline` 命令。
