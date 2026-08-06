# Requirement Spec JSON and Documentation Attributes

## Purpose

Transform the user's natural-language requirement into a structured spec JSON, build the model strictly from it, and mirror the same information into Simulink block attributes so the model is self-documenting.

Read this file during workflow steps 1 and 4 of `SKILL.md`.

## Spec JSON Schema

Write `<ModelName>.spec.json` into the model output directory. Use this structure:

```json
{
  "model": {
    "name": "EngineCoolingFanController",
    "purpose": "One-sentence purpose of the model"
  },
  "inputs": [
    {
      "name": "f32CoolantTemp",
      "type": "single",
      "description": "冷却液温度传感器读数",
      "unit": "degC",
      "range": "-40 .. 150"
    }
  ],
  "outputs": [
    {
      "name": "u8FanSpeedCmd",
      "type": "uint8",
      "description": "风扇转速指令",
      "unit": "pct",
      "range": "0 .. 100"
    }
  ],
  "calibrations": [
    {
      "name": "cal_f32TempThresh",
      "type": "single",
      "description": "滞环中心温度阈值",
      "unit": "degC",
      "range": "80 .. 110",
      "default": 90
    }
  ],
  "subsystems": [
    {
      "name": "SignalAcquisition",
      "role": "acquisition",
      "description": "信号调理与类型转换",
      "logic": "输入类型已匹配时直通；类型不一致时用 Data Type Conversion 统一为内部类型",
      "inputs": ["f32CoolantTemp", "u16VehicleSpeed", "bIgnOn"],
      "outputs": ["f32CoolantTempOut", "u16VehicleSpeedOut", "bIgnOnOut"]
    },
    {
      "name": "FanHysteresisControl",
      "role": "function",
      "description": "滞环死区控制",
      "logic": "上阈值=cal_f32TempThresh+cal_f32HystHalf，下阈值=cal_f32TempThresh-cal_f32HystHalf；温度高于上阈值置位开启，低于下阈值复位关闭，区间内由 Unit Delay 保持上一状态；由 Relational Operator / Logical Operator / Unit Delay 组合实现",
      "inputs": ["f32CoolantTemp"],
      "outputs": ["bFanOn"]
    },
    {
      "name": "OutputArbitration",
      "role": "arbitration",
      "description": "输出仲裁与门控",
      "logic": "点火关闭时强制风扇关闭（bIgnOn AND bFanOn），门控结果经 Switch 选择 cal_u8FanSpeedCmd 或 0；故障标志直通",
      "inputs": ["bFanOn", "bFaultFlag", "bIgnOn", "u16VehicleSpeed"],
      "outputs": ["u8FanSpeedCmd", "bFaultFlag"]
    }
  ],
  "signal_flow": "In -> SignalAcquisition -> FanHysteresisControl / FaultDetection -> OutputArbitration -> Out",
  "assumptions": [
    "车速信号本期不参与控制，仅保留端口供后续扩展"
  ]
}
```

Field rules:

- `name` must follow `naming.md`; `type` must follow `data-types.md`.
- `description` is the definition of the port / calibration / subsystem: what it is, in one sentence. Fill `unit` and `range` whenever they are known or inferable; leave them out only when truly undefined.
- `subsystems[].logic` must describe the internal implementation in concrete terms: which blocks realize the behavior and how (e.g., "Relop + Logical + Unit Delay 实现滞环锁存"). This text is later written into the subsystem `Description` attribute.
- `assumptions` records every inference made from an ambiguous requirement.
- The spec must cover every element that will exist in the model; the model must not contain top-level elements absent from the spec.

## Documentation Attributes (Simulink block properties)

During the build, mirror the spec into block `Description` attributes via configure operations:

- **Top-level ports** (`Inport` / `Outport`): `Description` = the definition, e.g. `"冷却液温度传感器读数，类型 single，单位 degC，范围 -40..150"`.
- **Calibrations** (Constant blocks named `cal_*`): `Description` = `"标定量名称；类型；含义；单位；范围；默认值"`, e.g. `"cal_f32TempThresh；滞环中心温度阈值；single；degC；80..110；默认 90"`.
- **Subsystems**: `Description` = responsibility plus internal logic, e.g. `"滞环死区控制：上阈值=cal_f32TempThresh+cal_f32HystHalf，下阈值=...；由 Relational Operator / Logical Operator / Unit Delay 组合实现"`.

Example configure operations:

```json
[
  {"op": "configure", "block": "#in_t", "params": {"Description": "冷却液温度传感器读数，类型 single，单位 degC，范围 -40..150"}},
  {"op": "configure", "block": "#c_th", "params": {"Description": "cal_f32TempThresh；滞环中心温度阈值；single；degC；80..110；默认 90"}},
  {"op": "configure", "block": "#fan", "params": {"Description": "滞环死区控制：上阈值=cal_f32TempThresh+cal_f32HystHalf，下阈值=cal_f32TempThresh-cal_f32HystHalf；区间内由 Unit Delay 保持；由 Relational Operator / Logical Operator / Unit Delay 组合实现"}}
]
```

If a `Description` attribute cannot be set through `model_edit` in the current scope, set it directly with `set_param(blockPath, 'Description', text)` and note this in the build log.
