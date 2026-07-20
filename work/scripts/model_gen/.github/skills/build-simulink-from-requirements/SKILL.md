---
name: build-simulink-from-requirements
description: "Build Simulink models from natural language software requirements. Use when user describes a control algorithm, signal processing chain, or state machine they want implemented as a Simulink model. Parses requirements, designs architecture, builds with model_edit, and validates with model_check."
license: MIT
metadata:
  author: MASA
  version: "1.0"
---

# Build Simulink Models from Requirements

Use this skill when the user gives you **natural language software requirements** and asks you to build a Simulink model. This skill provides a systematic process to transform requirements into a working Simulink model skeleton that the user can then optimize.

## When to Use

- User describes a controller, algorithm, or function in plain language
- User says "build a model that..." or "create a Simulink model for..."
- User provides a spec with inputs, outputs, and logic descriptions
- User asks for a model skeleton/framework that they will refine later

## When NOT to Use

- User only wants to read or query an existing model → use `model_overview` / `model_read`
- User wants to edit one specific block or parameter → use `model_edit` directly
- User wants tests or documentation → use `testing-simulink-models` or `sdd-detail-design-generation`

## Core Workflow

```
User Requirements (natural language)
        │
        ▼
  Step 1: Parse Requirements
    ├── Identify inputs (sensors, commands, signals)
    ├── Identify outputs (actuators, commands, indicators)
    ├── Identify logic/algorithm (control, arithmetic, state machine)
    └── Identify parameters/calibrations (thresholds, gains, lookup tables)
        │
        ▼
  Step 2: Design Architecture
    ├── Decompose into functional subsystems
    ├── Define data flow between subsystems
    ├── Choose block types (Gain, Sum, Logical, Relational, Stateflow, etc.)
    └── Plan model hierarchy (top-level → subsystems → leaf blocks)
        │
        ▼
  Step 3: Build Model (model_edit)
    ├── Create model: new_system + open_system
    ├── Add top-level Inport/Outport blocks
    ├── Add subsystems for functional decomposition
    ├── Populate each subsystem with internal logic
    └── Wire connections between blocks
        │
        ▼
  Step 4: Verify (model_read + model_check)
    ├── Read back the structure with model_read
    ├── Validate connectivity with model_check
    └── Fix any error-severity issues
        │
        ▼
  Step 5: Present to User
    ├── Show model structure
    ├── List what was built
    └── Suggest manual optimizations
```

## Step 1: Parse Requirements

Extract structured information from the user's natural language description.

### Input Identification

| Clue in Requirements | Simulink Block |
|---------------------|----------------|
| "sensor", "measurement", "speed", "temperature", "position" | Inport |
| "button", "switch", "request", "command" | Inport (boolean) |
| "status", "flag", "state" | Inport (boolean/enum) |

### Output Identification

| Clue in Requirements | Simulink Block |
|---------------------|----------------|
| "actuator", "motor", "valve", "lamp", "LED" | Outport |
| "command", "instruction", "setpoint" | Outport |
| "indicator", "display", "signal" | Outport |

### Logic Pattern Recognition

| Requirement Pattern | Implementation Strategy |
|--------------------|----------------------|
| "if X then Y", "when X, do Y", "X triggers Y" | RelationalOperator → LogicalOperator, or DetectRisePositive |
| "X > threshold", "X exceeds limit" | RelationalOperator (>=, >) + Constant |
| "combine X and Y", "X OR Y", "X AND Y" | LogicalOperator (OR, AND) |
| "sum of X and Y", "difference", "error = target - actual" | Sum |
| "scale by K", "multiply by gain" | Gain |
| "filter", "smooth", "average" | DiscreteFilter or TransferFcn |
| "integrate", "accumulate" | Integrator or DiscreteIntegrator |
| "look up table", "map", "characteristic curve" | LookupTable or 1-D Lookup Table |
| "state machine", "mode", "state transition" | Stateflow Chart |
| "counter", "count up/down" | CounterFree-Running or CounterLimited |
| "delay", "hold", "sample and hold" | Delay or UnitDelay |
| "priority", "arbitration", "override" | Switch or LogicalOperator with priority logic |
| "clamp", "limit", "saturate" | Saturation |
| "pulse", "timer", "timeout" | DiscretePulseGenerator or MATLAB Function with timer |

### Parameter/Calibration Identification

| Clue in Requirements | Recommended Practice |
|---------------------|---------------------|
| "threshold", "limit", "trigger point" | Extract to a named workspace variable (e.g., `Threshold_Speed`, `Limit_Temperature`) |
| "gain", "coefficient", "factor", "Kp", "Ki" | Use Gain block with a descriptive variable name (e.g., `Gain_Speed`, `Kp_Controller`) |
| "lookup table", "map", "curve", "characteristic" | Use Lookup Table block with variable data (e.g., `TableData_Map`, `Breakpoints_Speed`) |
| "timeout", "period", "duration", "interval" | Use DiscretePulseGenerator or MATLAB Function with named variable (e.g., `Timeout_Period`, `Sample_Interval`) |

## Mandatory Naming & Data Type Rules

### 🧱 模块使用规则：只使用基本模块

**禁止使用 Simulink 库中的复合模块**（如 PID Controller、Discrete Filter 等库函数）。  
所有算法必须用最基本的 Simulink 模块搭建：

| ❌ 禁止使用（库模块） | ✅ 改为基本模块组合 |
|---------------------|------------------|
| `PID Controller` | `Gain` + `Sum` + `DiscreteIntegrator` / `Integrator` |
| `Discrete Filter` / `Transfer Fcn` | `Gain` + `Sum` + `UnitDelay` 组合 |
| `PID Controller (2DOF)` | `Gain` × 3 + `Sum` × 2 + `Integrator` |
| `State-Space` | `Gain` + `Sum` + `Integrator` + `UnitDelay` |
| `Lead-Lag Filter` | `Gain` + `Sum` + `UnitDelay` |

**允许使用的基本模块列表：**

| 类别 | 允许的模块 |
|------|-----------|
| 数学运算 | `Gain`, `Sum`, `Product`, `Bias`, `Abs` |
| 逻辑运算 | `LogicalOperator`, `RelationalOperator`, `Switch` |
| 连续/离散 | `Integrator`, `DiscreteIntegrator`, `UnitDelay`, `Memory` |
| 信号路由 | `BusCreator`, `BusSelector`, `Mux`, `Demux`, `From`, `Goto` |
| 信号属性 | `DataTypeConversion`, `Saturation`, `RateTransition` |
| 信号源 | `Inport`, `Outport`, `Constant`, `Ground`, `Terminator` |
| 查找表 | `LookupTable`, `1-D Lookup Table`, `2-D Lookup Table` |

> **原则**：用 Gain + Sum + Integrator 搭建任何控制器，而非使用封装好的库模块。  
> 这样生成的模型结构透明、可读性强，且不依赖特定工具箱版本。

### 端口命名规则（必须遵守）

所有 Inport/Outport 的名称必须使用 `{type}{Name}` 格式，**类型前缀后不能有下划线**。

**🚨 信号名归一化（AI 必须执行）：**
如果需求中的信号名不符合 `{type}{Name}` 格式，按以下三步处理：

```
Step 1 — 清理非法前缀：
  删除所有非类型前缀的前缀（如 xxx_、abc_、data_ 等）。
  "xxx_u8Signal" → "u8Signal"  ✅
  "abc_f32Temp"  → "f32Temp"   ✅

Step 2 — 检测或添加类型前缀：
  清理后若无类型前缀，根据信号含义推断最合适的类型并添加。
  "Temperature"  → 推断为 f32 → "f32Temperature"  ✅
  "EnableFlag"   → 推断为 b   → "bEnable"         ✅

Step 3 — 精简长度 ≤ 20：
  若名称超过 20 字符，删除冗余词（Signal/Value/Data/Info），
  缩写方向词（LeftFront→LF、RightRear→RR）。
  "u8LeftFrontDoorStatusSignal" → "u8LFDoorStatus"  (14字符 ✅)
```

**命名→数据类型推断表：**

| 需求关键词 | 推断类型 | 前缀 |
|-----------|---------|------|
| "speed"/"velocity"/"position" | uint16 | `u16` |
| "temperature"/"current"/"voltage"/"pressure" | single(f32) | `f32` |
| "enable"/"lock"/"flag"/"status"(bool) | boolean | `b` |
| "counter"/"index"/"mode" | uint8 | `u8` |
| "encoder"/"tick"/"pulse" | uint16 | `u16` |
| "error"/"deviation"/"delta" | int16 | `s16` |
| "command"/"request" | uint8/enum | `u8`/`e` |

| 数据类型 | 前缀 | 端口名示例 | 适用场景 |
|---------|------|-----------|---------|
| boolean | `b` / `bool` | `bEnable`、`boolReady` | 开关、状态、标志位 |
| uint8 | `u8` | `u8DoorStatus` | 小范围枚举、计数器 |
| uint16 | `u16` | `u16VehicleSpeed` | 一般传感器值 |
| uint32 | `u32` | `u32TimeStamp` | 时间戳、大范围计数 |
| int16 | `s16` | `s16Position` | 有符号位置/误差信号 |
| int32 | `s32` | `s32EncoderTicks` | 大范围有符号信号 |
| single (f32) | `f32` | `f32Temperature` | 浮点信号（最常用） |
| **~~double (f64)~~** | **禁止使用** | ❌ `f64Voltage` | **不允许使用 double** |

> ⚠ **double 类型禁止使用**。所有浮点数必须使用 `single`（即 f32），`OutDataTypeStr` 设置为 `'single'`。

### 标定命名规则（必须遵守）

所有标定参数（Constant/Gain 块引用工作区变量）必须使用 `cal_{type}{Name}` 格式：

| 数据类型 | 前缀 | 标定名示例 |
|---------|------|-----------|
| uint16 | `cal_u16` | `cal_u16Threshold` |
| int16 | `cal_s16` | `cal_s16SpeedLimit` |
| single | `cal_f32` | `cal_f32GainValue` |
| boolean | `cal_b` | `cal_bEnableFlag` |

### 数据使用规则

| 规则 | 说明 |
|------|------|
| ✅ 允许 | `single` (f32), `int8/16/32`, `uint8/16/32`, `boolean` |
| ❌ 禁止 | `double` (f64) — 即使是 Constant/Inport/Outport 也不允许 |
| ✅ 默认 | 无符号信号用 `uint16`，浮点信号用 `single`，逻辑信号用 `boolean` |
| ✅ 标定 | Constant 块的 Value 使用 `cal_{type}Name` 工作区变量引用 |

### 端口命名示例

```matlab
% 正确 ✅
Inport:  'u16VehicleSpeed'   → OutDataTypeStr = 'uint16'
Inport:  'f32Temperature'    → OutDataTypeStr = 'single'
Inport:  'bLockRequest'      → OutDataTypeStr = 'boolean'
Outport: 's16Position'       → OutDataTypeStr = 'int16'
Outport: 'u8ErrorCode'       → OutDataTypeStr = 'uint8'

% 错误 ❌
Inport:  'VehicleSpeed'      → 缺少类型前缀
Outport: 'f64Voltage'        → double 禁止使用
Inport:  'doubleValue'       → double 禁止使用
Constant: 'Threshold'        → 标定缺少 cal_ 前缀
```

### 在 model_edit 中实现

**🚨 端口必须设置 Description + OutMin/OutMax：**
```json
// 正确 ✅ 命名 + 类型 + 描述 + 最值
{"op": "add_block", "type": "Inport", "name": "u16VehicleSpeed", "ref": "p1",
 "params": {"OutDataTypeStr": "uint16",
            "Description": "车速(km/h), 范围0-300",
            "OutMin": "0",
            "OutMax": "300"}},
{"op": "add_block", "type": "Inport", "name": "f32Temperature", "ref": "p2",
 "params": {"OutDataTypeStr": "single",
            "Description": "介质温度(℃)",
            "OutMin": "-40",
            "OutMax": "150"}},
{"op": "add_block", "type": "Inport", "name": "bLockRequest", "ref": "p3",
 "params": {"OutDataTypeStr": "boolean",
            "Description": "上锁请求(0=解锁/1=上锁)",
            "OutMin": "0",
            "OutMax": "1"}}

// 标定 Constant 块 — Value 使用 cal_ 变量引用
{"op": "add_block", "type": "Constant", "name": "SpeedThreshold", "ref": "c1",
 "params": {"Value": "cal_u16Threshold", "OutDataTypeStr": "uint16"}}
```

每个端口必须设置以下属性：

| 属性 | 参数名 | 必须？ | 设置方式 |
|------|--------|--------|---------|
| 数据类型 | `OutDataTypeStr` | ✅ | `params` 中设置 |
| 描述 | `Description` | ✅ | 中文描述含义/单位/枚举值 |
| 最小值 | `OutMin` | ✅ | 物理意义最小值（字符串） |
| 最大值 | `OutMax` | ✅ | 物理意义最大值（字符串） |

> **注意**：Inport/Outport 的最小值/最大值参数名为 `OutMin`/`OutMax`（不是 `Min`/`Max`）。Constant/Gain 等块的最小值/最大值参数名为 `Min`/`Max`。

## Step 2: Design Architecture

### Architecture Patterns

**Pattern A: Feed-forward chain** (signal processing)
```
Inport → [Filter] → [Gain] → [Sum] → Outport
```

**Pattern B: Feedback control** (PID, closed-loop)
```
Inport(ref) → [Sum] → [PID Controller] → Outport(actuator)
                ↑                          │
                └──── Sensor ──────────────┘
```

**Pattern C: Decision/routing** (logic-based)
```
Inport(decision_var) → [RelationalOp] → [Switch] → Outport
Inport(signal_A) ──────────────────────────┘
Inport(signal_B) ──────────────────────────┘
```

**Pattern D: State machine** (mode-based)
```
Inport(events) → [Stateflow Chart] → Outport(commands)
                └── [enable/trigger] ──┘
```

**Pattern E: Multi-function** (combined, most common for real applications)
```
Top Level
├── SubSystem: Signal Conditioning    ── filter, scale, convert
├── SubSystem: Logic/Core Algorithm   ── main decision logic or state machine
├── SubSystem: Output Processing      ── saturate, format, drive
└── SubSystem: Diagnostics            ── fault detection, monitoring (if applicable)
```

### Decomposition Guidelines

- If requirements have 3-5 distinct functions → use **Pattern E** (subsystems)
- If requirements describe a single formula/math → use **Pattern A** (flat)
- If requirements describe states/modes → use **Pattern D** (Stateflow)
- Combine patterns as needed for complex requirements

## Step 3: Build with model_edit

### Sequence of model_edit Calls

```json
// Call 1: Create model and add ports + subsystems at root
// Use layout_mode="full" for new model
[
  {"op": "add_block", "type": "Inport", "name": "InputName1", "ref": "p1"},
  {"op": "add_block", "type": "Inport", "name": "InputName2", "ref": "p2"},
  {"op": "add_block", "type": "Outport", "name": "OutputName1", "ref": "p3"},
  {"op": "add_block", "type": "SubSystem", "name": "SubName1", "ref": "ss1"},
  {"op": "add_block", "type": "SubSystem", "name": "SubName2", "ref": "ss2"}
]

// Call 2: Populate SubName1's scope with internal blocks
// First read discovered block IDs: model_read("Model", "root", "1")
// Then edit using the blk_X ID for the subsystem scope
```

> **Important**: model_edit's `scope` parameter requires block ID (like `blk_5`), NOT full path strings. Use `model_read` after creating a subsystem to discover its `blk_X` ID.

### Block Type Reference (Common)

| Block Type | JSON type field | Notes |
|-----------|----------------|-------|
| Input port | `Inport` | |
| Output port | `Outport` | |
| Constant | `Constant` | Set `Value` param |
| Gain | `Gain` | Set `Gain` param |
| Sum | `Sum` | Set `Inputs` param (`++`, `+--`, `++++`) |
| Product | `Product` | Set `Inputs` param |
| Relational Op | `RelationalOperator` | Set `Operator`: `==`, `>=`, `>`, `<`, `<=`, `!=` |
| Logical Op | `LogicalOperator` | Set `Operator`: `AND`, `OR`, `NAND`, `NOR`, `XOR`, `NOT` |
| Switch | `Switch` | Routes input based on threshold |
| Saturation | `Saturation` | Set `UpperLimit`, `LowerLimit` |
| Integrator | `Integrator` | |
| Discrete Filter | `DiscreteFilter` | |
| Unit Delay | `UnitDelay` | |
| Detect Rise | `DetectRisePositive` | Outputs true on rising edge |
| Lookup Table | `LookupTable` | Set `Table`, `BP1` params |
| SubSystem | `SubSystem` | Container for grouping |
| Stateflow Chart | `Chart` | Added as SubSystem then populated via SF scope |
| MATLAB Function | `MATLAB Function` | Custom algorithm |
| Bus Creator | `BusCreator` | Group signals |
| Bus Selector | `BusSelector` | Extract signals from bus |
| Data Store Memory | `DataStoreMemory` | Shared data across subsystems |
| From/Goto | `From`, `Goto` | Signal routing without lines |
| Scope | `Scope` | Debug/visualization |

### Wiring (connect operations)

```json
// Standard signal connection
{"op": "connect", "target": "blk_X.y1 -> blk_Y.u1"}

// Named signal
{"op": "connect", "target": "blk_X.y1 -> blk_Y.u1",
 "params": {"SignalName": "MySignal"}}

// Chained refs (within same call)
{"op": "add_block", "type": "Gain", "name": "MyGain", "ref": "g1"},
{"op": "connect", "target": "#p1.y1 -> #g1.u1"}
```

### Configuration After Building

After the structure is built, configure block parameters if the requirements specify values:

```json
// Set block parameters
{"op": "configure", "target": "blk_X",
 "params": {"Gain": "2.5", "SampleTime": "0.01"}}

// Set model solver settings
{"op": "configure", "target": "config:ModelName",
 "params": {"Solver": "FixedStepDiscrete", "FixedStep": "0.01"}}
```

## Step 4: Port Completeness & Wiring Integrity (Critical)

**🚨 每完成一步连线，必须立即验证，不能留到最后统一检查。**

### 4.1 端口完整性检查准则

在连线之前和执行过程中，用以下清单逐项验证：

```
┌─────────────────────────────────────────────────────────────────────┐
│ 端口完整性清单（每一条都必须满足）：                                 │
│                                                                     │
│ □ 内部 Inport 数量 = 该子系统需要从外部接收的信号数                  │
│ □ 内部 Outport 数量 = 该子系统需要输出到外部的信号数                 │
│ □ 每个 Inport 块至少有 1 条出线（连到下游逻辑块）                   │
│ □ 每个 Outport 块至少有 1 条入线（来自上游逻辑块）                   │
│ □ 逻辑块的每个输入端口(u1, u2, ...)都有一条信号线                   │
│ □ 逻辑块的所有输出端口至少连接到 1 个目标                           │
│ □ model_check 不报 "unconnected port" 错误                          │
│ □ 没有孤立的块（既无入线也无出线的块）                              │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 子系统间信号对应规则

```
子系统 A 的 Outport ⇔ 子系统 B 的 Inport

检查规则:
  1. 子系统 A 的每个 Outport 名称，必须有对应的信号线
     连接到子系统 B 的对应 Inport
  2. 两个子系统之间不能有「A 的 Outport 多但 B 的 Inport 少」
     或相反的情况出现
  3. 每个功能子系统的 Inport 必须都有 SignalAcquisition
     输出的对应信号
  4. OutputArbitration 的 Inport 必须覆盖所有功能子系统的输出
```

### 4.3 逐层连线与即时验证流程

每完成一层连线后，立即执行：

```matlab
% 1. 用 model_read 查看当前 scope 的完整结构
readBack = model_read(modelName, scope, "1");
if contains(readBack, "unconnected")
    error("未连接的端口: 请修复后再继续")
end

% 2. 用 model_check 验证结构
checkResult = model_check(modelName, scope, ["all"]);
% 若有 error 级别问题，立即修复

% 3. 发现 missing line 的处理：
%    - 找到哪个块的哪个端口没有连线
%    - 分析该端口应该连接什么信号
%    - 用 model_edit connect 补上
%    - 重新 model_check 确认修复
```

### 4.4 典型错误及修复

| 错误类型 | 现象 | 修复方法 |
|---------|------|---------|
| 悬空 Inport | Inport 块无出线 | 添加从 Inport 到下游块的连线 |
| 悬空 Outport | Outport 块无入线 | 添加上游块到 Outport 的连线 |
| 块输入未连 | Gain/Sum 等块的 u1 或 u2 未连 | 找到对应信号来源并连线 |
| 端口号不匹配 | 子系统间 I/O 数量不一致 | 检查两端的端口定义，补全缺失端口 |
| 孤立块 | 块既无入线也无出线 | 确认该块是否多余，若需要则补全连线 |

## Step 5: Populate Internal Logic (Critical — 不要空壳)

**🚨 不能只建子系统框架！每个子系统必须有完整的内部逻辑。**

### 5.1 逻辑映射模板

| 需求描述 | 实现方案 |
|---------|---------|
| "如果 X > 阈值，则 Y" | `RelationalOperator(>=)` → `Switch` |
| "将 A 和 B 相减得误差" | `Sum(+-)` |
| "乘以增益 K" | `Gain(K)` |
| "A AND B" | `LogicalOperator(AND)` |
| "A OR B" | `LogicalOperator(OR)` |
| "积分/累积" | `DiscreteIntegrator` 或 `UnitDelay + Sum` |
| "限幅" | `Saturation(UpperLimit, LowerLimit)` |
| "选择/仲裁" | `Switch(Criteria="u2 ~= 0")` |
| "上升沿" | `DetectRisePositive` |
| "延迟" | `UnitDelay` |

### 5.2 按子系统类型的最小实现要求

```
SignalAcquisition:
  每个输入通道 → DataTypeConversion → 对应输出
  （N路信号 → N个转换 → N路输出，与顶层Inport一一对应）

功能子系统（如 SpeedControl/LimitDetection/ModeManager 等）:
  必须包含: 条件判断（RelationalOp）+ 逻辑运算（LogicalOp）+ 选择/仲裁（Switch）
  至少 3 个以上的逻辑块，不能只有直通。例如：
  - 阈值判断: RelationalOperator(>=) + Constant(阈值) → Switch
  - 条件组合: LogicalOperator(AND/OR) 合并多个条件
  - 输出选择: Switch(Criteria="u2 ~= 0") 选择不同输出路径

OutputArbitration:
  必须包含: 优先级 Switch 级联（多路输入 → 仲裁 → 单路输出）
  至少 3 个 Switch 级联，每级 Switch 的 u1/u2/u3 必须有信号来源
  示例: 输入A(高优先级) → Switch(u1) vs 输入B(低优先级) → Switch(u3)
```

### 5.3 填充流程

```
每个子系统 = 至少 3 个逻辑块 + 完整连线
逐个连线 → 每 3～5 条线 model_read → 无悬空后继续
直到该子系统所有内部块都连接到信号为止
```

## Step 6: Verify (最终验证)

After ALL model_edit calls AND all connectivity checks are complete:

1. **Read back**: `model_read("Model", "root", "1")` to verify structure
2. **Check**: `model_check("Model", "root", "["all"])` to find issues
3. **Fix**: Any `error`-severity unconnected ports or dangling lines
4. **Final confirmation**: `model_check` 不再报任何 error-severity 问题

## Step 6: Auto-Layout (端口和连线对齐)

调用 `autoLayoutModel` 进行自动布局，确保模型可读性：

```matlab
% 递归布局所有层级（Inport靠左、Outport靠右、水平排列子系统）
autoLayoutModel('ModelName');
```

### 布局规则

| 规则 | 详细说明 |
|------|---------|
| **Inport 对齐** | 所有 Inport 块靠左边缘对齐，**端口垂直均匀分布**。同一层级有 N 个 Inport 时，间距 = 层级高度 / (N+1) |
| **Outport 对齐** | 所有 Outport 块靠右边缘对齐，端口垂直均匀分布。Outport 的位置行必须与 Inport **保持行对齐** |
| **子系统排布** | 子系统在中间区域从左到右水平排列。同层级的子系统保持**相同的高度和宽度** |
| **信号流方向** | 严格保持 **左→右**：Inports(左) → SubSystems(中) → Outports(右) |
| **连线最小交叉** | 信号线应避免交叉。远距离跨接使用 `From`/`Goto` 替代直接连线 |
| **层级传播** | 以上规则**递归应用到所有子系统层级**，每个子系统的内部布局也遵循上述规则 |
| **子系统高度自适应** | 当子系统有多个 I/O 时，子系统高度应适应端口数量，确保端口不挤压在一起 |

### 布局时机

```
Phase 3 (添加端口)  → 初步位置摆放
Phase 7 (连线完成)  → 再次布局，对齐端口行
Phase 8 (填充逻辑)  → 对每个子系统内部布局
Phase 9 (最终验证)  → 全局 autoLayoutModel 收尾
```

### 布局后验证

```matlab
% 验证对齐性
ports = find_system(modelName, 'SearchDepth', 1, 'BlockType', 'Inport');
positions = zeros(numel(ports), 4);
for i = 1:numel(ports)
    positions(i,:) = get_param(ports{i}, 'Position');
end
% Inport 的左边 X 坐标应一致
assert(all(positions(:,1) == positions(1,1)), 'Inport 左对齐失败')

% model_check 确认布局后无新错误
model_check(modelName, "root", ["all"])
```

## Step 7: Present to User

Provide a summary in this format:

```
## Model: ModelName

### Architecture
Top Level
├── SubSystem1     ── {role description}
├── SubSystem2     ── {role description}
└── SubSystem3     ── {role description}

### Interfaces
- Inputs:  {input names}
- Outputs: {output names}

### Key Logic
- {logic point 1}
- {logic point 2}

### Suggested Manual Optimizations
1. {layout adjustment}
2. {parameter extraction}
3. {add Stateflow for complex logic}
```

## Common Pitfalls

1. **Block ID vs Path**: After creating blocks with model_edit, use the returned `blk_X` IDs or `model_read` to discover them. Never guess block IDs.

2. **Scope per call**: Each model_edit call operates in exactly one scope. To edit inside a subsystem, you need a separate call with that subsystem's scope.

3. **Autolayout**: model_edit has built-in autolayout. Use `layout_mode="full"` for new/empty scopes, `"incremental"` when adding to existing layouts.

4. **Stateflow two-step**: Add Chart block in SL scope first, then use `model_read` to discover the chart's scope ID (`sf_X`), then populate internals in SF scope.

5. **Keep it simple**: Build a skeleton that works - the user will optimize layout, add detail, and refine parameters. Don't try to build a production-ready model in one shot.

6. **Model config**: After building, set solver type and step size appropriate for the application (FixedStepDiscrete for discrete controllers, VariableStep for plant models).

7. **🚨 布局对齐要求（必须遵守）**：每次 `model_edit` 调用后必须调用 `autoLayoutModel` 布局。Inport 必须左对齐且端口间距均匀，Outport 必须右对齐且与 Inport 保持行对齐。违反此规则的 PR/review 将被驳回。每完成一个子系统内部填充后立即对该子系统调用布局，不要留到最后统一布局。

8. **层级布局顺序**：先布局最内层子系统的内部，再逐层向外。内层布局完成后，外层自动布局会受益于内层已确定的端口位置，避免跨层级连线交叉。

9. **🚨 端口完整性是硬性要求**：`model_check` 报 "unconnected port" 时必须**立即停下来修复**，不能跳过或忽略。所有子系统 I/O 必须与它们的内部逻辑块完全对应。一个端口未连 = 模型不完整。

10. **边建边验**：不要等全部 Phase 完成后再验证。每连 3～5 条线 → 跑一次 `model_read` → 确认无悬空 → 继续。这样可以尽早发现端口数量或名称不匹配的问题。

11. **子系统间接口契约**：两个子系统之间的连线数量必须严格等于发送方 Outport 数 = 接收方 Inport 数。如果出现不匹配，说明需求分析或子系统划分有误，应返工 Phase 1～2 修正设计。
