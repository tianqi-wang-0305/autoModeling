# EMB_LRM_LaneRoleManager_v2 — MIL 测试用例规范

被测对象：`EMB_LRM_LaneRoleManager_v2.slx`（LRM 主从角色管理，10ms 离散周期）
输入顺序（8 路）：`u8OperMode, u8LclLaneOperMode, u8RmtLaneRole, u8LclFitnessScore, u8RmtFitnessScore, u8LclIlcStatus, bLclIlcStatusQf, u8HeartbeatLostCount`
输出（4 路）：`bLaneSwtgInProgs, bActvCtrlr, u8RmtLaneSts, u8LaneRole`
采样周期：`dt = 0.01s`；所有用例须显式设置有限 `StopTime`（模型默认 StopTime=inf）
覆盖目标：**decision / condition / MCDC**（Simulink Coverage）

## 需求映射

| 需求ID | 文档章节 | 内容 |
|--------|----------|------|
| REQ-1 | 2.1.2.2.4.1.2 | 心跳丢失判定：HEARTBEAT LOST COUNT 连续递增(0..255 回卷) 时 HB_Failure=0，否则=1 |
| REQ-2 | 2.1.2.2.4.2.2.1 | LaneStatusCntrInPrgs = HB_Failure>0 或 ILC 质量异常 |
| REQ-3 | 2.1.2.2.4.2.2.2 | LaneStatus 状态机：监控激活时优先级 Operating>Failed>HbLost；进入非 Operating 清零计数器 |
| REQ-4 | 2.1.2.2.4.2.2.3.1 | INIT 复位；OperMode∈{NORMAL,LIMP_HOME,LIMP_ASIDE,CRAWL} 激活监控 |
| REQ-5 | 2.1.2.2.4.2.2.3.2 | Operating 进入条件：ILC 正常 且 HB_Failure=0 |
| REQ-6 | 2.1.2.2.4.2.2.3.3 | HbLost：Hb 与故障计数器均≥窗口(20)；HbLost→Operating 当 HB 恢复 |
| REQ-7 | 2.1.2.2.4.2.2.3.4 | Failed：abs(Hb-ILC 计数器)≤5 且故障计数≥20；Failed 优先于 HbLost；Failed→Operating 当 HB 恢复 |
| REQ-8 | 2.1.2.3 | MLR 角色仲裁状态机：Init/Disabled/ShuttingDown/OperationalRoles{Support,FallBack,Master} 及其转移（条件 A-G 按 spec assumptions 实现） |
| REQ-9 | 2.1.2.4 | LSP 切换防抖：A>B>C 优先级，防抖阈值 10 周期 |
| REQ-10 | 顶层输出 | bActvCtrlr=角色==MASTER；u8RmtLaneSts 由远控角色/健康度映射 |

## 测试用例总表

| 用例ID | 需求ID | 场景 | StopTime | 覆盖意图 |
|--------|--------|------|----------|----------|
| TC01 | REQ-1/REQ-5 | 心跳正常递增（含回卷） | 1.0s | decision/condition |
| TC02 | REQ-1/REQ-6 | 心跳停滞→HbLost | 0.5s | decision/MCDC |
| TC03 | REQ-2/REQ-4 | 仅 ILC 质量异常 | 0.4s | decision/condition |
| TC04 | REQ-7 | 心跳+ILC 双故障→Failed | 0.5s | MCDC（Failed 优先级） |
| TC05 | REQ-6/REQ-7 | Failed→心跳恢复→Operating | 1.2s | decision |
| TC06 | REQ-4 | OperMode=INIT 监控不激活 | 0.3s | decision |
| TC07 | REQ-8 | 初始化等待后仲裁为 MASTER | 1.5s | decision/MCDC |
| TC08 | REQ-8 | 远程 MASTER→本地 FALLBACK | 0.4s | decision |
| TC09 | REQ-8 | 运行模式关闭→SHUTTING_DOWN | 0.3s | decision |
| TC10 | REQ-8 | 本地健康度=62→DISABLED | 0.3s | decision |
| TC11 | REQ-8 | MASTER→SUPPORT（条件A） | 2.0s | MCDC |
| TC12 | REQ-8 | FALLBACK→MASTER（条件C） | 1.0s | MCDC |
| TC13 | REQ-9 | 角色切换防抖 10 周期 | 1.8s | decision/MCDC |
| TC14 | REQ-9 | 任一计时器进行中→标志=1 | 0.3s | decision |
| TC15 | REQ-10 | 远控状态映射 4 段 | 1.6s | decision/MCDC |

## 用例详情（输入按端口顺序，时间为秒，周期=0.01s）

### TC01_HB_HealthyNormal（REQ-1/REQ-5）
- 目的：心跳计数连续递增（0..99，覆盖回卷语义 254→255→0 的等价类），HB_Failure=0，链路保持 OPERATING。
- 输入：`{1, 1, 0, 100, 100, 1, 0, hb}`，`hb = mod(0:99,256)`。
- 期望：初始化后 LaneStatus=1(OPERATING)；LaneStatusCntrInPrgs=0；LaneRole=1(INIT)（健康度均势不仲裁）。
- 覆盖：心跳健康判定 decision（递增真/假分支）、MonitoringOn→Operating 转移。

### TC02_HB_Stuck_HbLost（REQ-1/REQ-6）
- 目的：心跳计数停滞（非连续递增）→ HB_Failure=1 → Hb/故障计数器连续计数，≥20 周期进入 HbLost。
- 输入：`{1, 1, 0, 100, 100, 1, 0, 5}`（恒定 5，0.5s=50 周期）。
- 期望：约 0.2s 后 LaneStatus=2(HB_LOST)；LaneStatusCntrInPrgs=1；Hb 计数器诊断=20。
- 覆盖：`curr==prev+1 || wrap` 的假分支（MCDC：回卷条件独立）、`HbMon>=thd && FailureMon>=thd`。

### TC03_ILC_QF_FaultOnly（REQ-2/REQ-4）
- 目的：仅 ILC 质量异常（QF=1）：ILC 计数器累计但故障计数器为 0 → 不满足 Failed/HbLost，状态保持 INITIALISING；LaneStatusCntrInPrgs=1。
- 输入：`{1, 1, 0, 100, 100, 1, 1, hb}`，`hb = mod(0:39,256)`。
- 期望：LaneStatus=0；bLaneStatusCntrInPrgs=1。
- 覆盖：`bIlcFault` 真分支（condition）、Failed/HbLost 组合的假分支。

### TC04_BothFaults_Failed（REQ-7）
- 目的：心跳停滞 + ILC 质量异常，双计数器同步增长（差值≤5）且故障计数≥20 → Failed，且 Failed 优先级高于 HbLost。
- 输入：`{1, 1, 0, 100, 100, 1, 1, 5}`。
- 期望：约 0.2s 后 LaneStatus=3(FAILED)（而非 HbLost）。
- 覆盖：`abs(Hb-ILC)<=5 && Failure>=thd`（MCDC：abs 条件独立影响）、优先级 Operating>Failed>HbLost。

### TC05_FailedRecovery_Operating（REQ-6/REQ-7）
- 目的：双故障进入 Failed 后心跳恢复递增 → Failed→Operating（HB_Failure=0）。
- 输入：`{1, 1, 0, 100, 100, 1, qf, hb}`，前 0.4s `hb=5,qf=1`，0.4s 后 `hb` 递增、`qf=0`。
- 期望：LaneStatus 3→1；LaneStatusCntrInPrgs 归 0。
- 覆盖：Failed→Operating 转移、计数器清零路径。

### TC06_OperInit_NoMonitor（REQ-4）
- 目的：OperMode=INIT 时监控不激活，即使心跳故障 LaneStatus 保持 INITIALISING。
- 输入：`{0, 0, 0, 100, 100, 1, 0, 5}`。
- 期望：LaneStatus=0 全程；LaneRole=INIT。
- 覆盖：bMonitoringActive 假分支（condition）。

### TC07_Arb_Master（REQ-8）
- 目的：初始化等待（≥100 周期）后本地健康度>远程 → 仲裁为 MASTER；bActvCtrlr=1。
- 输入：`{1, 1, 0, 200, 100, 1, 0, hb}`，`hb=mod(0:149,256)`。
- 期望：约 1.1s 后 LaneRole=2(MASTER)；bActvCtrlr=1；bLaneSwtgInProgs 在切换期间=1、防抖后=0。
- 覆盖：`bInitWaitDone && bLclGtRmt`（MCDC）、Init→OperationalRoles.Master 转移、bActvCtrlr 真分支。

### TC08_Arb_Fallback_RmtMaster（REQ-8）
- 目的：远程角色=MASTER → 本地仲裁为 FALLBACK。
- 输入：`{1, 1, 2, 100, 100, 1, 0, hb}`，`hb=mod(0:39,256)`。
- 期望：LaneRole=3(FALLBACK)；bActvCtrlr=0。
- 覆盖：`bArbRmtMaster` 真分支、Init→OperationalRoles.FallBack 转移。

### TC09_Shutdown（REQ-8）
- 目的：本链路运行模式=SHUTTING_DOWN → 角色 SHUTTING_DOWN。
- 输入：`{1, 5, 0, 100, 100, 1, 0, hb}`，`hb=mod(0:29,256)`。
- 期望：LaneRole=6；LaneStatus 保持 OPERATING（若心跳正常）。
- 覆盖：`bShutdown` 真分支（Init 与 OperationalRoles 两级退出）。

### TC10_Disabled（REQ-8）
- 目的：本地健康度=62（禁用）→ 角色 DISABLED，禁止参与仲裁。
- 输入：`{1, 1, 0, 62, 100, 1, 0, hb}`，`hb=mod(0:29,256)`。
- 期望：LaneRole=5(DISABLED)。
- 覆盖：`bLclDisabled` 真分支。

### TC11_MasterToSupport（REQ-8）
- 目的：MASTER 下 ILC 故障且本地<远程且远程有效（条件A）→ 直接降级 SUPPORT。
- 输入：`{1, 1, 0, lcl, 100, ilc, 0, hb}`：前 1.3s `lcl=200, ilc=1`（MASTER），后 0.7s `lcl=50, ilc=0`。
- 期望：LaneRole 2→4(SUPPORT)。
- 覆盖：`bCondA = bIlcFailed && bRmtFitnessValid && Lcl<Rmt` 三条件 MCDC。

### TC12_FallbackToMaster_StsFailed（REQ-8）
- 目的：FALLBACK 下 LaneStatus=FAILED（条件C：LaneStatus==FAILED 或远程禁用/关闭）→ 立即升级 MASTER。
- 输入：`{1, 1, 2, 100, 100, 1, qf, hb}`：前 0.6s 心跳正常，0.6s 后心跳停滞且 qf=1 触发 MLS Failed。
- 期望：LaneStatus=3 后 LaneRole 3→2(MASTER)；bActvCtrlr=1。
- 覆盖：`bCondC = bLaneStsFailed || bRmtDisabledOrShutdown` 的 MCDC（LaneStatus 分支）、MLS Failed 与 MLR 升级联动。

### TC13_LSP_Debounce（REQ-9）
- 目的：角色切换（MASTER→FALLBACK）触发 LaneSwtInProgs=1 与计数器，角色稳定 10 周期后防抖复位 0。
- 输入：`{1, 1, rmt, 200, 100, 1, 0, hb}`：前 1.5s `rmt=0`（本地 MASTER），后 0.3s `rmt=2`（远程 MASTER→本地降级 FALLBACK）。
- 期望：切换后 bLaneSwtgInProgs=1；约 10 周期后=0；u32LaneSwtInPrgsCntr 计数后清零。
- 覆盖：LSP 优先级 A>B>C（MCDC）、`cnt+1 > cal_u8RoleChangeDebounceTime` 边界。

### TC14_LSP_AnyTimer（REQ-9）
- 目的：角色保持 INIT（LaneRoleCntrInPrgs=1）→ 任一计时器进行中 → 切换标志持续 1。
- 输入：`{1, 1, 0, 100, 100, 1, 0, hb}`，`hb=mod(0:29,256)`。
- 期望：bLaneSwtgInProgs=1 持续（条件C 分支）。
- 覆盖：`bLaneRoleCntrInPrgs || bLaneStatusCntrInPrgs` 真分支。

### TC15_RmtStsMapping（REQ-10）
- 目的：分 4 段验证 u8RmtLaneSts 映射与 bActvCtrlr：
  段1(0~0.4s) rmtRole=5(DISABLED) → 3(FAILED)；段2(0.4~0.8s) rmtFit=255 → 2(HB_LOST)；段3(0.8~1.2s) rmtRole=1(INIT) → 0(INITIALISING)；段4(1.2~1.6s) rmtRole=2(MASTER) → 1(OPERATING)。
- 输入：`{1, 1, rmt, 100, fit, 1, 0, hb}`（rmt/fit 按段切换）。
- 期望：u8RmtLaneSts 按段为 3/2/0/1。
- 覆盖：u8RmtLaneSts 映射 Switch 链各分支（decision/MCDC）。

## 执行方式（模型修复后）

1. 修复模型 Stateflow 图表（见下方阻塞说明）后，运行 `mil/create_mil_tests.m`：
   - 创建正式 harness：`sltest.harness.create(mdl,'Name','Harness_LRM','Source','Inport','Sink','Outport')`；
   - 创建 `MIL_EMB_LRM_LaneRoleManager_v2.mldatx`（15 个 baseline 用例，挂接 harness，StopTime 有限，输入 Dataset 已写入 `mil/*.mat`）；
   - 文件级覆盖设置开启 Decision/Condition/MCDC。
2. 逐用例 `captureBaselineCriteria` 捕获 golden，再 `sltest.testmanager.run` 执行；
3. 读取覆盖率，按未覆盖项补测（MCDC 真值表法）。

## 阻塞说明（本次未执行）

- 模型 `EMB_LRM_LaneRoleManager_v2.slx` 的 Stateflow 图表在今日 harness 编译过程中被破坏：干净编译报“状态机解析失败”，`stateflow_lint` 报 14 项错误（转移遮蔽、自然父级外的转移循环、缺失默认转移、状态重叠），主文件与 autosave 均为该状态。
- 修复建议：删除并重建两个 Stateflow 图表（复用 v2 build 的 SF 操作模板），数据显式设 `Props.Array.Size='1'`，状态排成无重叠布局、转移端点用 OClock 设置；编译通过后即可按上述流程执行。
- 恢复副本保留在 `mil/../_autosave_check.slx`（与主文件同为受损状态，仅作比对参考）。
