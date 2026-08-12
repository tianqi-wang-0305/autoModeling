---
name: simulink-mil-testing
description: "Generate and execute MIL (Model-in-the-Loop) test cases for Simulink models using ONLY the testing-simulink-models toolchain (vnv.internal.agentic.test_create / test_edit / test_run), producing .mldatx test files that run in Test Manager, with both .mat and Excel input files per case for manual editing. Coverage must reach decision 100%, condition 100%, and MCDC at least 80% (target 100%). Optionally run the same cases in SIL (Software-in-the-Loop) and perform MIL/SIL back-to-back equivalence comparison. Use when the user asks to create or run MIL test cases for a Simulink model, generate tests from a requirements document (docx/md/spec JSON) or from the model itself when no requirements are given, needs Simulink Coverage (decision/condition/MCDC) results, or asks for SIL testing / MIL-SIL comparison."
---

# Simulink MIL Testing

为 Simulink 模型生成 MIL（Model-in-the-Loop）测试用例并用 Simulink Test 执行，覆盖指标为 **decision / condition / MCDC**（Simulink Coverage）。

- 用户给了需求文件（docx / md / spec JSON）→ 按需求生成用例，用例映射到需求 ID；
- 用户没给需求 → 基于模型结构推导用例；
- **测试执行与覆盖率收集只通过 `testing-simulink-models` 技能的工具链（test_create / test_edit / test_run）完成**，基于生成的 `.mldatx` 在 Test Manager 中运行。

## Workflow

1. **确认被测对象与接口**（只读）
   - 模型名/路径、顶层 Inport/Outport 名称与类型、采样周期、求解器；
   - 用 MCP 工具读取：`model_overview`、`model_read`、`model_query_params`（端口、标定量 cal_*、子系统、Stateflow、阈值/比较器）；
   - 用 `detect_matlab_toolboxes` 确认已安装 **Simulink Test** 与 **Simulink Coverage**；MATLAB 会话先 `addpath("~/.matlab/agentic-toolkits/simulink"); satk_initialize`。

2. **需求输入**
   - 有需求文件：docx 用 python-docx/pandoc 或 MATLAB 读文本；spec JSON 直接读 `inputs/outputs/calibrations/subsystems/assumptions`。提取功能点（正常/边界/异常/故障/时序防抖/状态机转移/标定阈值），建立“需求 → 场景 → 用例”映射，每条用例记录需求 ID。
   - 无需求文件：按模型推导（见 `references/mil-test-case-design.md` 第 2 节）。

3. **设计测试用例**（见 `references/mil-test-case-design.md`）
   - 每条用例：用例 ID、需求 ID、目的、前置条件、输入时序（timeseries / Dataset）、期望输出/判定、覆盖意图；
   - 覆盖矩阵：等价类 + 边界（decision）、布尔条件独立翻转（condition）、条件独立影响结果（MCDC）；
   - MIL 要点：离散周期信号、状态机防抖/超时计数需持续多个周期、输出判定留出延迟窗口。

4. **实现与执行**（见 `references/test-execution-coverage.md`）
   - **只用 `testing-simulink-models` 工具链**：`test_create`（model scope；unit scope 自动建 harness 亦可，若工具报内部错误则回退 model scope）→ `test_edit`（StopTime 有限值、挂接输入）→ 捕获 baseline → `test_run` 在 Test Manager 中执行并读取覆盖率；
   - 每个用例同时生成 **`.mat` 与 Excel（.xlsx）输入文件**（同一组信号），Excel 便于用户手动变更优化；`.mat` 必须包含**模型全部顶层输入端口**的信号（元素名/类型与端口严格一致，如 `f32CoolantTemp`→single、`u16VehicleSpeed`→uint16、`bIgnOn`→logical）；
   - **输入映射（执行前必做）**：`test_edit` 设置 `InputFile` 后**不会自动映射**——必须对每个 `TestInput` 显式调用 `map()`，且映射必须**另存为新文件**才持久化（`saveToFile()` 无参不写盘、原路径报“文件已打开”、`close()` 丢映射）；重新打开校验 `MappingStatus` 含“成功映射”后再捕获 baseline / `test_run`。未映射时用例以零输入运行，覆盖度严重虚低（典型症状：decision 50%、condition 50%、MCDC 0%，且所有用例覆盖数字完全相同）；
   - **顶层 function-call 外部调度**：若模型顶层存在 function-call 输入端口（外部调度触发，如 AUTOSAR runnable），先用 `sltest.harness.create` 创建带 `SchedulerBlock`（Test Sequence / MATLAB Function / Chart）的模型级测试 harness 驱动该端口（有 Init/Reset/Terminate 端口时加 `ScheduleInitTermReset=true`），再以 harness 作为被测对象走工具链生成用例；function-call 端口不是数据输入，**不进 .mat**；先单独仿真 harness 确认 runnable 已执行（执行覆盖 > 0%）再跑用例；
   - 覆盖由工具自动启用（metrics `dmc` = decision/mcdc/condition）；若未启用则显式开启。

5. **覆盖分析与补测**
   - 对未覆盖项逐个定位（未覆盖的分支 / 条件 / MCDC 组合）→ 补充用例；MCDC 用真值表法：每个条件独立翻转、其余条件固定为“使结果随该条件变化”的组合；
   - **达标要求：decision = 100%，condition = 100%，MCDC ≥ 80%（目标 100%）**；不达标必须补测，不得通过修改模型来刷覆盖率。

6. **SIL 测试与 MIL/SIL back-to-back 对比**（用户要求时必做；见 `references/test-execution-coverage.md` 第 2.8 节）
   - 前置：确认已装 **Simulink Coder / Embedded Coder** 与可用 C 编译器；模型可生成代码；MIL 用例已完成且覆盖达标；
   - **方式 A（推荐，back-to-back）**：`test_create(TestType="equivalence", ...)` 生成等价用例，仿真 1 = Normal（MIL）、仿真 2 = Software-in-the-loop（SIL），同一输入/StopTime，Test Manager 按等价容差自动对比两个仿真输出；
   - **方式 B（复用 MIL baseline）**：MIL 用例捕获 baseline 后，用 `test_edit(SimulationMode="Software-in-the-loop (SIL)")` 把同一用例切到 SIL 直接跑，SIL 输出与 MIL baseline 不一致即失败；
   - 判定：全部 passed = MIL/SIL 一致；failed 时列出不一致信号与最大偏差，先判断是否落在数值精度内（调容差），再排查代码生成/采样配置差异，禁止改模型或生成配置来“对平”结果；
   - 顶层 function-call 场景：在已建 harness 上同样切 SIL（`SimulationMode` 或 harness `VerificationMode="SIL"`）。

7. **输出**
   - 用例清单（需求映射、输入、期望、覆盖意图）、执行结果（通过/失败）、覆盖率汇总（decision/condition/MCDC 百分比 + 未覆盖项列表）；
   - 若做了 SIL：MIL/SIL back-to-back 对比结论（一致/不一致、容差、最大偏差、不一致信号列表）；
   - 用例失败时给出根因判断（模型缺陷 vs 用例设计问题）。

## 关键约束

- **不修改被测模型结构**：激励/观测用测试输入文件或 `SimulationInput`（`setExternalInput` / `SaveOutput`），禁止用 `set_param`/`add_block` 改模型来“刷覆盖率”；
- **只允许用 `testing-simulink-models` 工具链生成测试用例**（`test_create` / `test_edit` / `test_run`），产物必须是 `.mldatx` 并能在 Test Manager 中直接运行；**禁止**用手工 `sltest.harness.create`、直接 sltest API 或脚本拼装用例来替代（用户明确要求对比实验时除外）。**唯一例外：被测模型顶层存在 function-call 输入端口（外部调度）时，允许先手工创建带 `SchedulerBlock` 的模型级测试 harness 作为被测对象，再走工具链生成用例**。若工具链使用 unit scope 自动建 harness，需验证其可编译且可在 Test Manager 中运行；工具内部错误时回退 model scope（仍属该工具链）。
- **每个用例必须同时提供 `.mat` 与 Excel 输入文件**：Excel 列 = 时间 + 各输入信号（同名同类型），方便用户手动修改输入、重录 baseline 后复用。
- **.mat 输入完整性**：`.mat` 必须包含模型**全部顶层输入端口**的信号，元素名与类型和端口严格一致；执行前必须校验输入映射状态（`getInputs()` 的 `MappingStatus` 含“成功映射”），未映射时先 `map()` 并另存持久化，否则用例实际以零输入运行、覆盖结果严重失真（典型症状：decision 50%、condition 50%、MCDC 0%，且所有用例覆盖数字完全相同）。
- **覆盖达标要求**：decision = 100%、condition = 100%、MCDC ≥ 80%（目标 100%）；未达标必须补测，禁止修改被测模型结构来“刷覆盖率”。
- **MIL/SIL 一致性判定**：back-to-back 以等价容差为准；SIL 与 MIL 不一致时先排查容差/浮点精度/代码生成与采样配置，禁止为对平结果修改被测模型或生成代码设置。
- 覆盖率以 Simulink Coverage 报告为准（decision / condition / MCDC），以整份 `.mldatx` 聚合口径评估。
- 相关 Toolkit 技能：`testing-simulink-models`（生成/执行/覆盖）、`simulating-simulink-models`（sim）、`authoring-simulink-inputs`（createInputDataset 合成波形）、`checking-model-compliance`（规范预检）。

## Resources

- `references/mil-test-case-design.md` — 需求/模型驱动的用例设计：等价类、边界值、状态机转移覆盖、MCDC 真值表法、MIL 时序要点、Excel 输入配套
- `references/test-execution-coverage.md` — testing-simulink-models 工具链实现、.mldatx/Test Manager 执行、decision/condition/MCDC 覆盖配置与读取、补测循环
