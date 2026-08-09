# Simulink Test 执行与覆盖率（testing-simulink-models 工具链）

> 只用 Simulink Agentic Toolkit 的 `testing-simulink-models` 技能工具链：`vnv.internal.agentic.test_create / test_edit / test_run`。精确 API 以该技能的 `references/simulink-test-authoring.md` 为准。

## 1. 前置

- 需要 **Simulink Test** 与 **Simulink Coverage**（`detect_matlab_toolboxes` 确认）；
- MATLAB 会话：`addpath("~/.matlab/agentic-toolkits/simulink"); satk_initialize`；
- 被测模型已加载、可干净编译；标定量（cal_*）变量在工作区或模型工作区中定义。

## 2. 创建用例（只用 testing-simulink-models 工具链）

```matlab
% 调用工具链（evaluate_matlab_code 的 project_path 指向该技能 scripts/ 目录，
% 或在脚本内 addpath 该目录；TestFile 必须用绝对路径）
vnv.internal.agentic.test_create(Component="<Model>", TestType="baseline", ...
    TestScope="model", TestFile=fullfile(wf,"MIL_<Model>.mldatx"), ...
    SuiteName="MIL_<Model>", TestName="TC_001");
vnv.internal.agentic.test_edit(TestFile=fullfile(wf,"MIL_<Model>.mldatx"), ...
    SuiteName="MIL_<Model>", TestCaseName="TC_001", StopTime="2", ...
    InputFile=fullfile(wf,"TC_001.mat"));
```

- 覆盖由 `test_create` **自动启用**（`coverage.metrics = dmc`，即 decision/mcdc/condition）；若输出显示未启用，在 TestFile 上显式设置 `MetricSettings='cdm'` 与 `RecordCoverage=true`。
- baseline 类型用例：输入/StopTime 配好后，用 `tc.captureBaselineCriteria(baseFile, false)` 捕获 golden，再 `test_run` 执行比对。
- 快速冒烟可用 Gherkin `model_test`（draft_mode=true），但正式用例仍以工具链生成的 `.mldatx` 为准。

## 2.5 产物与 Test Manager 执行规则

- **产物必须是 `.mldatx`**：工具链生成的文件就是 Test Manager 原生格式，可在界面（`sltest.testmanager.open`）或命令行（`tf.run()`）中直接运行。
- **scope 选择**：`TestScope="model"` 直接跑整个模型（无 harness）；`TestScope="unit"` 由工具链自动创建子系统 harness——若该版本工具包在 unit scope 报内部错误，回退 model scope（仍属本工具链，不手工建 harness）。
- **禁止**用手工 `sltest.harness.create` 或直接 sltest API 编写/替换用例，除非用户明确要求做对比实验。**唯一例外：被测模型顶层存在 function-call 输入端口（外部调度）时，允许先手工创建带 `SchedulerBlock` 的模型级测试 harness 作为被测对象，再走工具链生成用例**（见 2.7）。
- **可运行性校验（交付前必须做）**：`test_run` 执行整份 `.mldatx`，确认每个用例 outcome 为 passed，且覆盖报告可读取。
- **常见失败原因**：模型未保存/标定量变量缺失、StopTime=inf 未覆盖、输入 .mat/.xlsx 与端口映射不符（典型表现为 `MappingStatus=输入未映射`，用例以零输入运行，覆盖度虚低且各用例数字相同）、baseline 文件路径被移动。

## 2.6 每个用例同时生成 .mat 与 Excel 输入

- `.mat`：保存 `Simulink.SimulationData.Dataset`，**必须包含模型全部顶层输入端口**的 timeseries，元素名与端口名严格一致、类型与端口一致（如 `f32CoolantTemp`→single、`u16VehicleSpeed`→uint16、`bIgnOn`→logical）。缺失任一信号会让 Test Manager 无法映射（`MappingStatus=输入未映射`），用例实际以零输入运行，覆盖度严重失真。`test_edit` 的 `InputFile` 指向该 .mat；
- **Excel（.xlsx）**：同一组信号写成表格，列为 `时间` + 各输入信号名（与端口同名同类型），供用户手动修改；Test Manager 的 Inputs 可直接绑定 .xlsx。
- 生成 Excel 示例：
  ```matlab
  t = (0:0.01:2)';
  T = table(t, single(temp), uint16(speed), logical(ign), ...
      'VariableNames', {'Time','f32CoolantTemp','u16VehicleSpeed','bIgnOn'});
  writetable(T, 'TC_001.xlsx');
  ```
- 用户改完 Excel 后：绑定新 xlsx → 重跑 → 重新捕获 baseline，即可复用。
- **输入映射（执行前必做）**：`test_edit` 设置 `InputFile` 后**不会自动映射**——必须显式调用 `map()`，并且映射要**另存为新文件才持久化**（`saveToFile()` 无参会静默不写盘、`saveToFile(原路径)` 报“文件已打开”、`close()` 会丢弃映射）。标准流程：
  ```matlab
  tc = getTestCaseByName(getTestSuiteByName(tf, "<Suite>"), "<TC>");
  ins = tc.getInputs();
  for i = 1:numel(ins)
      ins(i).map();   % 必须先 map，否则用例以零输入运行
      assert(contains(char(ins(i).MappingStatus), "成功映射"), ...
          "输入未映射：%s", char(ins(i).Name));
  end
  tf.saveToFile(fullfile(wf, "<新文件名>.mldatx"));  % 另存为新文件，映射才持久化
  % 重新打开新文件抽查 MappingStatus 后，再捕获 baseline / test_run；
  % 需保持原文件名时，另存后替换原文件（保留备份）。
  ```

## 2.7 顶层 function-call 外部调度（AUTOSAR runnable 场景）

**识别**：`model_overview` 显示模型顶层有 function-call 输入端口（触发口），runnable 子系统由外部调度器/RTE 触发；model-scope 裸跑时没有任何东西发 function-call，runnable 一次都不执行 → 执行覆盖 0%，decision/condition/MCDC 加多少用例都不涨。

**处理**（唯一允许手工建 harness 的场景）：

```matlab
mdl = "MyModel";
sltest.harness.create(mdl, Name="MyModel_MIL_Harness", ...
    Source="Inport", Sink="Outport", SchedulerBlock="Test Sequence");
% 若模型还有 Init/Reset/Terminate 类 function-call 端口：
%   sltest.harness.create(..., SchedulerBlock="Test Sequence", ScheduleInitTermReset=true)
```

- harness 自动把模型**数据**输入端口生成 Inport；**function-call 端口不生成 Inport**，而是接在 SchedulerBlock（Test Sequence / MATLAB Function / Chart）输出上；
- 在调度块里按 runnable 真实触发周期配置 function-call（如每 0.01s 调一次）；周期要与真实调度一致，状态机/防抖/计数逻辑需留足调用次数（N+1 次）；
- 先单独仿真 harness，确认 runnable 执行覆盖 > 0%，再继续；
- 以 harness 为被测对象走工具链：
  ```matlab
  vnv.internal.agentic.test_create(Component="MyModel_MIL_Harness", ...
      TestType="baseline", TestScope="model", TestFile=fullfile(wf,"MIL_MyModel.mldatx"), ...
      SuiteName="MIL_MyModel", TestName="TC_001");
  ```
  之后流程不变：`test_edit` 挂 .mat → `map()` → 另存新文件 → 重录 baseline → `test_run`。
- `.mat` 只含**数据**输入端口信号（名称/类型与 harness 的 Inport 即模型数据端口一致）；function-call 端口不进 .mat。

**诊断**：覆盖报告中 runnable 子系统“执行”列 0%（模块 0/0 执行）→ function-call 未触发，检查 SchedulerBlock 是否连接、周期是否发出；若执行 100% 但条件/MCDC 低 → 才是输入场景设计问题。

## 3. 覆盖率设置（decision / condition / MCDC）

- 工具链 `test_create` 自动启用覆盖（`dmc`）；如未启用，在 TestFile 上显式设置：
  ```matlab
  cs = tf.getCoverageSettings(); cs.RecordCoverage = true; cs.MetricSettings = 'cdm';
  ```
- 覆盖以 `test_run` 返回的 Simulink Coverage 报告为准；多次用例的覆盖率在 Test Manager 中聚合（MCDC 跨用例组合是常态，以整份文件聚合口径评估）。
- **达标要求**：decision = 100%，condition = 100%，MCDC ≥ 80%（目标 100%）。

## 4. 执行与读取

```matlab
r = vnv.internal.agentic.test_run(fullfile(wf, "MIL_<Model>.mldatx"), ...
    save_to=fullfile(wf, "results.yaml"));
% r.summary: total/passed/failed；r.coverage: decision/condition/mcdc 百分比
```

## 5. 补测循环

1. 读取未覆盖目标列表（以整份 `.mldatx` 聚合口径）；
2. 对每个未覆盖目标设计补充用例（MCDC 按真值表逐条件补组合）；
3. 重跑 → 聚合 → 复查，直到 **decision=100%、condition=100%、MCDC≥80%（目标100%）**；
4. 输出覆盖率报告：三项百分比、未覆盖目标清单、需求映射。

## 注意事项

- 覆盖设置改完后必须重新 run 才生效；
- 不要通过修改被测模型结构来“刷覆盖率”；未覆盖通常意味着场景缺失或模型存在死逻辑（可用 `resolve-design-errors` 排查）；
- 编译较慢时先用 draft/Gherkin 快速迭代，最终以正式 `test_run` 的覆盖报告为准。
