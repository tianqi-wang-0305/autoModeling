---
description: "基于模型接口自动生成并执行 Simulink Test 单元测试用例（Gherkin .feature + model_test 执行 + HTML 报告）。"
name: "Generate Unit Tests"
argument-hint: "<model.slx> [Strategy] [RunTests] [Coverage]"
agent: "agent"
---

# Generate Unit Tests (Simulink Test / MIL)

根据模型接口（Inport/Outport + 数据类型 + Min/Max）自动生成 MIL 单元测试用例，写入 Gherkin `.feature` 文件，并通过 `model_test` 执行，输出 HTML 报告。

## Usage

```
/generateUnitTests Model.slx
/generateUnitTests Model.slx Strategy=boundary
/generateUnitTests Model.slx Strategy=comprehensive Coverage=decision
/generateUnitTests Model.slx RunTests=false
```

## 步骤

1. **定位脚本**：`work/scripts/test_gen/src/generateUnitTests.m`
2. **构建 MATLAB 命令**：

   ```matlab
   % 基本测试（常值/零/最大输入）
   result = generateUnitTests('path/to/Model.slx');

   % 边界 + 阶跃响应
   result = generateUnitTests('path/to/Model.slx', 'Strategy', 'boundary');

   % 综合 + 执行 + 决策覆盖率
   result = generateUnitTests('path/to/Model.slx', ...
       'Strategy', 'comprehensive', ...
       'Coverage', 'decision');

   % 只生成不执行（快速预览 .feature）
   result = generateUnitTests('path/to/Model.slx', 'RunTests', false);
   ```

3. **在 MATLAB 终端执行**，展示生成的 feature 文件和测试报告

## 测试策略

| Strategy | 场景 |
|----------|------|
| `basic` | 常值输入 / 零输入 / 最大输入 |
| `boundary` | + 每个数值输入的阶跃响应 |
| `comprehensive` | + 布尔开关切换 + 斜坡输入 |

## 输出

- `_tests/{Model}_NominalTests.feature`
- `_tests/{Model}_BoundaryTests.feature`
- `_tests/{Model}_FaultTests.feature`
- `_tests/{Model}_test_report.html`

## Prerequisites

- Simulink Test 许可证
- Simulink Coverage 许可证（`Coverage=decision` 时）
- 已 `satk_initialize`

## 注意

- 枚举端口生成 `const(0)` 占位，复杂枚举值需人工补充场景
- `RunTests=true` 时通过 `model_test` 执行；DraftMode=true 快速迭代
