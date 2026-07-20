---
agent: agent
description: "Build any Simulink model from natural language requirements. AI uses model_edit to create ports, subsystems, and logic dynamically."
name: "create-model"
argument-hint: "<describe your requirements>"
---

# Build Simulink Model

> **🚨 关键**：执行此命令前，AI 必须**先读取 skill 文件** `work/scripts/model_gen/.github/skills/build-simulink-from-requirements/SKILL.md`，该文件包含：
> - 详细的端口/标定命名规范（`{type}{Name}` / `cal_{type}{Name}`）
> - 禁止使用 double，所有浮点用 single
> - 禁止使用库模块（PID Controller 等），必须用基本模块组合
> - 完整的模型架构和要求

Transform natural language software requirements into a Simulink model skeleton. **First read the SKILL.md** for naming/data type rules, then build with `model_edit`.

## 模型架构要求

生成的模型必须遵循以下架构：

```
ModelName
├── Inports:  u16VehicleSpeed, f32Temperature, bEnable  ({type}{Name} 规范)
├── Outports: u8MotorCmd, s16Position                   ({type}{Name} 规范)
│
└── SubSystem: MainSubsystem (wrapper, 包含所有逻辑)
    ├── Inports  (与顶层一一对应)
    ├── Outports (与顶层一一对应)
    │
    ├── SubSystem: SignalAcquisition    ← 信号调理/类型转换
    ├── SubSystem: {功能模块1}          ← 根据需求创建
    ├── SubSystem: {功能模块2}          ← 根据需求创建
    ├── SubSystem: OutputArbitration    ← 输出仲裁/合并
    │
    └── 内部连线: In → Acquisition → 功能模块 → Arbitration → Out
```

## Usage

Describe what you want the model to do.

```
/buildModel A PID speed controller with:
  - Input: target speed (uint16), actual speed (single)
  - Output: throttle command (single, 0-100)
  - Logic: P=2.0, I=0.5, D=0.1, saturate output
```

```
/buildModel A signal processing chain:
  - Input: raw sensor signal
  - Output: filtered and scaled signal
  - Steps: low-pass filter → gain scaling → saturation clamp
```

## Build Steps (must follow exactly)

### Phase 1: Read SKILL.md
Read `work/scripts/model_gen/.github/skills/build-simulink-from-requirements/SKILL.md` for all naming and data type rules.

### Phase 2: Create root model
```
model_edit(create, modelName)
Configure: Solver=FixedStepDiscrete, FixedStep=0.01, StopTime=100
```

### Phase 3: Add root Inport/Outport blocks (含名称归一化 + Description + OutMin/OutMax)
```
model_edit(add_block, Inport)   × N   // ref: p1, p2, ...
model_edit(add_block, Outport)  × M   // ref: q1, q2, ...
Names must follow: {type}{Name}       // e.g. u16VehicleSpeed
Data types: single for float, never double
```

**🚨 端口名称归一化规则（必须执行）：**

如果需求中的信号名不符合 `{type}{Name}` 格式，AI 必须按以下步骤归一化：

```
输入: 需求中的原始信号名（如 "xxx_u8aaaa"、"sensorValue"、"veryLongDescriptiveSignalName123"）

Step 1 — 清理非法前缀：
  如果信号名中有不合规的前缀（如 xxx_、abc_、data_ 等非类型前缀），
  直接删除该前缀。保留类型前缀（如 u8、s16、f32、b）。

  "xxx_u8aaaa"     → 删除 "xxx_" → "u8aaaa"     ✅
  "abc_s16Speed"   → 删除 "abc_" → "s16Speed"    ✅
  "data_bEnable"   → 删除 "data_" → "bEnable"    ✅
  "cal_u16Value"   → 保留 "cal_" → "cal_u16Value" ✅ （标定参数）

Step 2 — 检测类型前缀：
  清理后的信号名开头是否有类型前缀（u8/s16/f32/b 等）？
  如果有 → 使用该前缀对应的数据类型。
  如果没有 → 根据信号含义推断最合适的类型并添加前缀。

  "s16Speed"       → 有 s16 → int16     ✅
  "Temperature"    → 无前缀 → 推断为 f32 → "f32Temperature"  ✅
  "EnableFlag"     → 无前缀 → 推断为 b → "bEnable"          ✅

Step 3 — 精简名称（不超过20字符）：
  如果归一化后的名称超过 20 个字符，按信号定义描述精简。

  原始名: "u16LeftFrontDoorWindowStatusSignal"
  精简为: "u16LFDoorStatus"   ← 保留核心语义，删除冗余词
  原则: Signal/Value/Data/Info 等通用后缀可删除
        LeftFront → LF, RightRear → RR, Front/Rear → F/R

示例:
  "xxx_u8LeftFrontDoorStatusSignal"  → "u8LFDoorStatus"   (12字符 ✅)
  "abc_s16VehicleSpeedMeasurement"   → "s16VehicleSpeed"   (16字符 ✅)
  "data_bAntiPinchProtectionEnabled" → "bAntiPinchEnable"  (18字符 ✅)
```

**每个端口必须设置以下属性：**

| 属性 | 参数名 | 必须？ | 说明 |
|------|--------|--------|------|
| 数据类型 | `OutDataTypeStr` | ✅ | `single`, `uint8`, `uint16`, `boolean` |
| 名称 | `name` | ✅ | 归一化后，遵循 `{type}{Name}`，总长 ≤ 20 |
| 描述 | `Description` | ✅ | 中文描述该信号的含义、单位、枚举值。如 `"车速(km/h), 范围0-300"` |
| 最小值 | `OutMin` | ✅ | 物理意义的最小值。如 `'0'` |
| 最大值 | `OutMax` | ✅ | 物理意义的最大值。如 `'300'` |

**在 model_edit 中实现：**
```json
{"op": "add_block", "type": "Inport", "name": "u16VehicleSpeed", "ref": "p1",
 "params": {
   "OutDataTypeStr": "uint16",
   "Description": "车速(km/h), 范围0-300",
   "OutMin": "0",
   "OutMax": "300"
 }}
```

> **注意**：`Inport`/`Outport` 块的 `Description`/`OutMin`/`OutMax` 参数名就是 `Description`/`OutMin`/`OutMax`。
> **`Constant` 块**的极值参数名是 `Min`/`Max`（不带 `Out` 前缀）。

### Phase 4: Create MainSubsystem wrapper + internal subsystems
```
model_edit(create_subsystem, "MainSubsystem")   // wrapper
model_edit(create_subsystem, "SignalAcquisition")  // inside wrapper
model_edit(create_subsystem, "...")              // functional subsystems
model_edit(create_subsystem, "OutputArbitration")  // output merge
```

### Phase 5: Add Inport/Outport inside each subsystem
Each subsystem must have its own Inport/Outport blocks (R2025a creates empty subsystems).
Use `add_block('built-in/Inport', ...)` and `add_block('built-in/Outport', ...)` inside each.

### Phase 5.5: I/O Port Completeness Check (Critical — 端口对应性)
**在连线之前，必须验证每个子系统的端口完整性：**

```
检查准则（每一条都必须满足）：
┌────────────────────────────────────────────────────────────────────┐
│ 1. 端口-逻辑对应：内部 Inport 的「名称和数量」必须与其下游逻辑      │
│    块实际需要的输入信号完全匹配。不能多，不能少。                  │
│                                                                    │
│ 2. 内部 Inport 数量 = 该子系统需要从外部接收的信号数               │
│    内部 Outport 数量 = 该子系统需要输出到外部的信号数              │
│                                                                    │
│ 3. 逐个检查每个模块：该模块的每个输入端口(u1, u2, ...)             │
│    都有一条信号线连接到一个 Inport 或上游模块的输出                │
│                                                                    │
│ 4. 无悬空端口：每个 Inport 至少有 1 条出线连到下游块               │
│    每个 Outport 至少有 1 条入线来自上游块                          │
│                                                                    │
│ 5. model_check 不能报任何 "unconnected port" 错误                  │
└────────────────────────────────────────────────────────────────────┘
```

在执行 Phase 6～8 的每一步连线后，立即用 `model_read` 或 `model_check` 验证该子系统内是否有悬空端口。发现丢失连线立即补上。

### Phase 6: Wire top level
```
Root Inports  → MainSubsystem (port-to-port)
MainSubsystem → Root Outports (port-to-port)
In R2025a, use add_line(modelName, 'InportName/1', 'MainSubsystem/1', 'autorouting','on')
```
**连线后验证**：`model_check` 确认顶层无悬空端口。

### Phase 7: Wire inside MainSubsystem
```
MainSubsystem Inports → SignalAcquisition → functional subsystems → OutputArbitration
OutputArbitration → MainSubsystem Outports
```
**连线顺序与验证（必须逐步验证）：**
```
Step 7.1: MainSubsystem Inports → SignalAcquisition Inports
          → model_read 确认所有内部 Inport 都有入线
Step 7.2: SignalAcquisition Outports → 各功能子系统的 Inports
          → model_read 确认 SignalAcquisition 每个出线端口都连到目标
Step 7.3: 各功能子系统 Outports → OutputArbitration Inports
          → model_read 确认 OutputArbitration 的 Inports 都有来源
Step 7.4: OutputArbitration Outports → MainSubsystem Outports
          → model_read 确认 MainSubsystem 的 Outports 都有来源
```

### Phase 8: Populate functional logic — 尽可能生成内部设计

**🚨 关键原则：不要只建空壳子系统，要尽可能填充内部逻辑！**
AI 必须根据需求文档的逻辑描述，使用基本 Simulink 模块组合来实现完整的信号处理链路。

每个功能子系统必须包含完整的内部逻辑，而不仅仅是 I/O 端口。

#### 8.1 需求 → 逻辑映射模板

| 需求描述模式 | Simulink 实现 | 示例 |
|------------|--------------|------|
| "如果 X > 阈值，则 Y" | `RelationalOperator(>=)` → `Switch` | 车速 > 15km/h → 落锁 |
| "将 A 和 B 相加" | `Sum(++)` | 误差 = 目标 - 实际 |
| "将输入乘以 K" | `Gain(K)` | 比例控制 P*Kp |
| "A 和 B 同时成立" | `LogicalOperator(AND)` | 闭锁 AND 暴雨 → 关窗 |
| "A 或 B 任一成立" | `LogicalOperator(OR)` | 电流超 OR 位置异常 → 防夹 |
| "累积/积分" | `DiscreteIntegrator` 或 `UnitDelay + Sum` | 积分控制 |
| "限幅" | `Saturation` | 输出 0~100% |
| "延迟 N 步" | `UnitDelay` | 信号同步 |
| "选择/仲裁" | `Switch(Criteria=u2!=0)` | 防夹 > 手动 > 自动 |
| "上升沿检测" | `DetectRisePositive` | 按键下降沿触发 |
| "计数/计时" | `CounterFreeRunning` 或 `MATLAB Function` | 超时保护 |

#### 8.2 填充策略 — 通用示例

根据需求逻辑，从 8.1 映射表中选择对应的基本模块组合。以下为通用示例而非特定应用：

```
信号调理（SignalAcquisition）:
  - Inport → DataTypeConversion(type匹配) → Outport（N路1:1直通）

阈值检测（如 ThrottleDetection/LimitCheck）:
  - RelationalOperator(>=) + Constant(阈值) 判断输入是否超限
  - Switch: 超限时选择默认值/报警信号，否则直通

条件组合（如 ModeLogic/ConditionMerge）:
  - LogicalOperator(AND): 多个条件同时满足
  - LogicalOperator(OR): 多个条件任一满足
  - NOT → AND: 条件取反后再组合

控制器（如 SpeedControl/PositionControl）:
  - Sum(+-): 计算误差 = 目标 - 反馈
  - Gain: 比例增益
  - DiscreteIntegrator 或 UnitDelay + Sum: 积分
  - Saturation: 输出限幅

仲裁/选择（如 PriorityArbiter/OutputSelector）:
  - Switch 级联: 高优先级输入 → Switch(u1) 覆盖低优先级 → Switch(u3)
  - 诊断事件: Switch(触发时选择事件码，否则0)
```

#### 8.3 填充步骤

```
Step 1: 分析需求 → 确定该子系统的功能逻辑
Step 2: 选择对应模板（8.1 节）中的基本模块组合
Step 3: 添加模块（每个模块命名有语义，如 "R_CurOver"、"S_Error"、"Sw_Output"）
Step 4: 逐步连线: Inport → 逻辑块1 → 逻辑块2 → ... → Outport
Step 5: 每连 3～5 条线 → model_read → 确认无悬空
Step 6: 重复直到该子系统所有逻辑块的全部端口都有连线
Step 7: 进入下一个子系统的填充
```

**注意：严禁只建空壳子系统！每个子系统都必须有具体的内部逻辑块和完整连线。**

### Phase 9: Verify
```
model_check → validate structure (fix any error-severity issues)
model_read  → read back structure
```

### Phase 10: Auto-Layout (Critical — 端口和连线对齐)
调用 `work/scripts/layout_gen/src/autoLayoutModel.m` 进行自动布局：

```matlab
autoLayoutModel('ModelName');  % 递归布局所有层级
```

布局规则：
| 规则 | 说明 |
|------|------|
| **Inport 对齐** | 所有 Inport 靠左对齐，端口垂直均匀分布（端口间距一致） |
| **Outport 对齐** | 所有 Outport 靠右对齐，端口垂直均匀分布，与 Inport 保持行对齐 |
| **信号流方向** | 信号从左到右：Inports(左) → SubSystems(中) → Outports(右) |
| **子系统排布** | 子系统在中间区域水平排列，同层子系统保持相同高度/宽度 |
| **连线不交叉** | 避免信号线交叉，用 `From`/`Goto` 替代远距离跨接 |
| **层级传播** | 上述规则递归应用到所有子系统层级 |

布局后重新验证：
```matlab
model_check → 确认无新错误
model_read  → 确认布局正确
```

## Prerequisites

- MATLAB running with `satk_initialize` executed
- Simulink Agentic Toolkit configured
- **重要**：R2025a 中 SubSystem 无默认 In1/Out1，必须手动添加
