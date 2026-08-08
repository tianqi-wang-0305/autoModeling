---
name: simulink-sw-architecture-docs
description: "Generate a full set of application software functional architecture deliverables from all provided software requirements and all application Simulink models (which may be scattered across multiple folders). The MANDATORY core deliverable is a System Composer architecture model (built with the building-architecture-models skill: multi-layer F/L/P components, interface dictionaries, allocation sets, stereotypes, requirements links), plus architecture overview, interface specification, per-component functional specification, requirement traceability matrix, and calibration list. Use when the user asks to create application software architecture documentation/models from requirements and models, or build a traceability matrix across requirements and models."
---

# Simulink 软件架构文档生成

根据用户提供的**全部软件需求**与**全部应用软件 Simulink 模型**（可分布在多个文件夹），生成软件功能架构交付物。**System Composer 架构模型是必选核心交付物**（用户最关心），其余为配套文档。全程调用 Simulink Agentic Toolkit 技能，只读使用现有模型，输出为新增工件。

## Workflow

1. **输入收集**
   - 用户给出需求文件与模型文件（可能在不同文件夹）；
   - 用 `find` / `rg` 扫描给定根目录，收集全部 `.slx` 模型、需求文档（docx / md / spec JSON）、已有 spec JSON；
   - 建立“输入清单”：每个模型的路径/名称、每份需求的路径/类型。
2. **解析需求（多文档汇总）**
   - 逐份提取：功能需求、接口表（输入/输出）、标定量、状态机/阈值要求；
   - 汇总为统一需求清单（REQ-01..n），记录来源文档。
3. **模型盘点与读取（只读）**
   - 逐个加载模型：`model_overview`（接口/层级）、`model_read`（子系统逻辑）、`model_query_params`（类型/阈值）、`model_resolve_params`（标定值）；
   - 归纳每个模型的组件/子系统、输入输出、主要逻辑。
4. **架构划分与映射**
   - 按 `building-architecture-models` 的思路划分功能架构层（如 SignalAcquisition / 功能模块 / OutputArbitration，或按需求功能聚类）；
   - 建立“需求 ↔ 组件 ↔ 模型”追溯矩阵；未覆盖需求、无需求对应的模型/组件都要标记。
5. **生成 System Composer 架构模型（必选，核心交付物）**
   - 调用 `building-architecture-models` 技能创建多层层级架构模型：
     - **层划分**：按 F/L/P 约定（功能层动词短语、逻辑层角色名词、物理层具体单元）或按用户已有分层，创建各层独立模型；
     - **组件**：由步骤 4 的需求↔组件映射驱动，每个组件承载对应需求/模型功能；
     - **组件间连接（必做）**：同一层内组件之间的信号连接必须显式建立，不得留空：
       - 端口来源：组件内部的 In/Out Bus Element 块，块名即架构端口名；
       - 接线方式：`model_edit` 的 connect 操作，格式 `blk_源.y1 -> blk_目标.端口名`；接线前先用 `model_read` 读取目标组件的可用端口名再连；
       - 连接规则：1:1 单向连接；支持扇出（一路输出可接多个输入）；**禁止扇入**——一个输入端口只能有一个源，多路源时为目标组件拆分为多个命名输入端口（如 `Status_Cook` / `Status_Pack` / `Status_Load`）再逐一 1:1 接线；
       - **端口名陷阱**：端口名以 `u<数字>` 开头（如 `u16VehicleSpeed`、`u8FanSpeedCmd`）会被连接解析器误判成端口编号设计符（`u1`/`y1` 式），报 "Cannot resolve port 'in16VehicleSpeed'" 之类的错误；此时改用端口序号接线：目标 `blk_X.u2`（第 2 个输入口）、源 `blk_X.y1`（第 1 个输出口），顺序以 `model_read` 显示的端口顺序为准；或者先重命名端口规避；
       - 覆盖要求：除作为架构边界的端口外，每个组件的端口都必须接线；未接线的端口必须在 `model_check`（unconnected_ports）中被检出并补线或说明用途；
     - **接口**：每层使用独立接口字典 `.sldd`（`linkDictionary` 后再 `setInterface`），端口带类型/单位；
     - **分配集**：用 `systemcomposer.allocation.createAllocationSet` 建立 F→L→P 分配，保存各层模型后再创建；
     - **stereotype**：按生命周期（创建 profile → 保存 → 应用 → 设置属性，使用全限定名 `Profile.Stereotype.Property`）；
     - **需求链接**：有 Requirements Toolbox 时，为架构组件建 Implement/Verify 链接到需求；
   - **校验（必做）**：每个层模型 `model_check`（unconnected_ports，未连接端口必须为 0 或逐项说明用途）+ `set_param(...,'SimulationCommand','update')` 检查接口类型问题；分配集在重建后需重新创建。
6. **生成文档集**（见 `references/architecture-doc-templates.md`）
   - 00_架构模型说明：System Composer 模型的层级/组件/接口/分配/需求链接说明（与模型对应）；
   - 01_架构总览：架构层次、组件职责、数据流；
   - 02_接口规格：每组件输入/输出表、组件间信号流、数据字典；
   - 03_功能规格：每组件行为规格（触发、逻辑、阈值、状态机、输出）；
   - 04_需求追溯矩阵：REQ ↔ 组件 ↔ 模型 ↔ 架构模型 ↔ 文档章节；
   - 05_标定参数清单：cal_* 名称/类型/默认值/范围/用途；
   - 06_模型地图：模型文件 → 实现组件/需求。
   - 可选：用 `generate-requirement-drafts` 生成 `.slreqx` 需求工件。
7. **输出与校验**
   - 交付物：System Composer 架构模型（各层 `.slx` + `.sldd` + 分配集）+ 文档集，输出到指定目录；
   - 自检：架构模型与追溯矩阵一致、层间分配完整、需求覆盖度、模型覆盖度、接口一致性。

## 关键约束

- **System Composer 架构模型是必选交付物**，不得省略或仅输出文档；必须调用 `building-architecture-models` 技能生成并完成 `model_check` 校验；
- **组件间接线是必做步骤**：同层组件之间的信号连接必须用 `model_edit` connect 显式建立（1:1、单向、支持扇出、禁止扇入，多源需拆分命名输入端口）；跨层（F→L→P）不做信号直连，层间关系通过 allocation set 追溯映射；
- **只读使用现有模型**：不修改任何 `.slx`；架构模型/文档是新增工件；
- **输入分散多文件夹**：必须先在给定根目录扫描收集，避免遗漏模型或需求；
- **需求/模型映射要显式**：未映射项（无模型的需求、无需求的模型）必须列出；
- **调用 Toolkit 技能**：
  - `building-architecture-models`（System Composer 架构模型：F/L/P 分层、接口字典、分配集、stereotype、需求链接）——必用
  - `building-simulink-models`（model_read / model_overview / model_query_params / model_resolve_params / model_edit / model_check）
  - `generate-requirement-drafts`（.slreqx / 需求工件）
  - `specifying-mbd-algorithms`（算法规格编写参考）
  - `simulink-modeling-style`（若模型按该风格，架构描述沿用其分层）
  - `checking-model-compliance`（可选预检）
- 文档语言默认中文；与用户确认输出目录与格式。

## Resources

- `references/architecture-doc-templates.md` — 架构模型（System Composer）说明 + 六类文档的模板与字段说明
- `references/input-collection-and-mapping.md` — 多文件夹输入收集、模型盘点、需求↔组件↔模型映射方法
