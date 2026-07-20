## 命名规范

### 通用规则
- 所有块名、信号线名、子系统名和 Stateflow 图名应仅包含 `A-Z`, `a-z`, `0-9`, `_`
- 名称不能以数字开头
- 名称应尽量使用业务语义词，而不是泛化占位词

### 信号命名规范

**格式：`{数据类型前缀}{描述}`** — 类型前缀与描述直接拼接，中间无下划线。

使用 `/setPortTypes` 可自动按此规则批量更新模型中所有端口的数据类型。

| 前缀 | 数据类型 | 示例 |
|------|---------|------|
| `s8` | int8 | `s8Temperature` |
| `s16` | int16 | `s16VehicleSpeed` |
| `s32` | int32 | `s32Position` |
| `u8` | uint8 | `u8DoorStatus` |
| `u16` | uint16 | `u16Counter` |
| `u32` | uint32 | `u32TimeStamp` |
| `f32` | single | `f32Current` |
| `f64` | double | `f64Voltage` |
| `b` | boolean | `bLockRequest` |
| `bool` | boolean | `boolEnabled` |
| 无前缀 | 继承 (Inherit) | `RawSignal` |

> **无下划线规则**：类型前缀后不能有下划线分隔符。格式必须为 `{type}{Name}` 如 `u16VehicleSpeed`。描述内部可以有下划线如 `u16Vehicle_Speed`，但类型前缀 `u16` 后必须紧跟大写字母。

### 信号名归一化规则

当需求中的信号名不符合 `{type}{Name}` 格式时，按以下步骤处理：

```
Step 1 — 清理非法前缀：删除非类型前缀的前缀
  "xxx_u8Signal"  → "u8Signal"     ✅
  "data_s16Speed" → "s16Speed"    ✅

Step 2 — 检测或添加类型前缀：
  无类型前缀时根据信号含义推断：
  速度/位置 → u16，温度/电流 → f32，使能/标志 → b

Step 3 — 精简长度 ≤ 20 字符：
  删除冗余词：Signal/Value/Data/Info
  缩写方向词：LeftFront→LF, RightRear→RR, FrontLeft→FL
```

### 标定命名规范

**格式：`cal_{数据类型前缀}{描述}`** — `cal_` 前缀后紧跟数据类型前缀，再紧跟描述，中间无多余下划线。

| 前缀 | 数据类型 | 示例 |
|------|---------|------|
| `cal_u8` | uint8 | `cal_u8Threshold` |
| `cal_s16` | int16 | `cal_s16SpeedLimit` |
| `cal_u16` | uint16 | `cal_u16Timeout` |
| `cal_s32` | int32 | `cal_s32PositionMax` |
| `cal_f32` | single | `cal_f32GainValue` |
| `cal_f64` | double | `cal_f64ScaleFactor` |
| `cal_b` | boolean | `cal_bEnableFlag` |

### 建议
- 子系统名优先描述功能，例如 `BrakeRequestArbiter`、`LampStatusMgr`
- 信号名：`{类型}{描述}`，如 `u16VehicleSpeed`（类型和描述间无下划线）
- 标定名：`cal_{类型}{描述}`，如 `cal_u16Threshold`（`cal_` 后有下划线，类型和描述间无下划线）
- 如果需要临时命名，也应尽快在提交前改成可读语义名

### 常见问题
- `Subsystem`、`Chart`、`Gain` 这类默认名可通过正则，但不建议作为最终提交命名
- 数字后缀堆叠过多通常说明复用块没有被重新命名
- 如果同层出现多个非常接近的名称，建议统一词根和后缀规则

### 结果解读
- `check_naming_convention.m` 会返回命名违规和通用名称预警
- 报告里会分别统计块名违规、信号线名违规和通用名称数量