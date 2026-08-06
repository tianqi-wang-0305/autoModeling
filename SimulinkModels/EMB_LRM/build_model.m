% Build EMB_LRM.slx strictly from EMB_LRM.spec.json following
% simulink-modeling-style. Implements the detailed logic of
% LRM_MLS_ManageLaneStatus (HB failure + 4-state machine + counters),
% LRM_MLR_ManageLaneRole (6-state role machine + counters) and
% LRM_LSP_LaneSwitchInProgs (debounce logic) with basic blocks only.

model = 'EMB_LRM';
outDir = '/Users/wangtianqi/SimulinkModels/EMB_LRM';

if bdIsLoaded(model)
    close_system(model, 0);
end
new_system(model);

%% ---------- Top level ----------
inNames = {'u8OperMode','u8LclLaneOperMode','u8RmtLaneRole','u8LclFitnessScore', ...
           'u8RmtFitnessScore','u8LclIlcStatus','bLclIlcStatusQf','u8HeartbeatLostCount'};
inTypes = {'uint8','uint8','uint8','uint8','uint8','uint8','boolean','uint8'};
outNames = {'bLaneSwtgInProgs','bActvCtrlr','u8RmtLaneSts','u8LaneRole'};
outTypes = {'boolean','boolean','uint8','uint8'};
inDesc = {
  '系统运行模式（enum：0 INIT，1 NORMAL_OPERATION，2 LIMP_HOME，3 LIMP_ASIDE，4 CRAWL，5 SHUTTING_DOWN），类型 uint8'
  '本控制链路运行模式（enum，编码同 OPER MODE），类型 uint8'
  '远控制链路当前角色（enum：0 INIT，1 MASTER，2 FALLBACK，3 SUPPORT，4 DISABLED，5 SHUTTING_DOWN），类型 uint8'
  '本控制链路健康度得分（62=禁用，255=无效），类型 uint8'
  '远控制链路健康度得分（62=禁用，255=无效），类型 uint8'
  '本控制链路 ILC 状态（0x0 Failed，0x1 Normal，0x2 Initialized），类型 uint8'
  '本控制链路状态信号质量（0x0 QF_Full，0x1 QF_Not Full），类型 boolean'
  '心跳丢失计数（0-255），类型 uint8'};
outDesc = {
  '控制链路切换进行中标志（0x0 Not Progress，0x1 Progress），类型 boolean'
  '活动控制器实例标志（0x0 Not Active，0x1 Active），类型 boolean'
  '远控制链路状态（0 INITIALISING，1 OPERATING，2 HB_LOST，3 FAILED），类型 uint8'
  '本控制链路角色状态（enum：0 UNKNOWN，1 INIT，2 MASTER，3 FALLBACK，4 SUPPORT，5 DISABLED，6 SHUTTING_DOWN），类型 uint8'};

for i = 1:numel(inNames)
    add_block('built-in/Inport', [model '/' inNames{i}]);
    set_param([model '/' inNames{i}], 'OutDataTypeStr', inTypes{i}, 'Description', inDesc{i});
end
for i = 1:numel(outNames)
    add_block('built-in/Outport', [model '/' outNames{i}]);
    set_param([model '/' outNames{i}], 'OutDataTypeStr', outTypes{i}, 'Description', outDesc{i});
end
add_block('built-in/SubSystem', [model '/MainSubsystem']);
set_param([model '/MainSubsystem'], 'Description', ...
    'EMB_LRM 主逻辑包装层：SignalAcquisition -> 功能子系统(LRM_MLS / LRM_MLR -> LRM_LSP) -> OutputArbitration -> Out；运行周期 10ms，ASIL-D');

%% ---------- MainSubsystem ----------
ms = [model '/MainSubsystem'];
for i = 1:numel(inNames)
    add_block('built-in/Inport', [ms '/' inNames{i}]);
    set_param([ms '/' inNames{i}], 'OutDataTypeStr', inTypes{i});
end
for i = 1:numel(outNames)
    add_block('built-in/Outport', [ms '/' outNames{i}]);
    set_param([ms '/' outNames{i}], 'OutDataTypeStr', outTypes{i});
end
add_block('built-in/SubSystem', [ms '/SignalAcquisition']);
add_block('built-in/SubSystem', [ms '/LRM_MLS_ManageLaneStatus']);
add_block('built-in/SubSystem', [ms '/LRM_MLR_ManageLaneRole']);
add_block('built-in/SubSystem', [ms '/LRM_LSP_LaneSwitchInProgs']);
add_block('built-in/SubSystem', [ms '/OutputArbitration']);

%% ---------- SignalAcquisition (pass-through) ----------
sa = [ms '/SignalAcquisition'];
saOut = {'u8OperModeOut','u8LclLaneOperModeOut','u8RmtLaneRoleOut','u8LclFitnessScoreOut', ...
         'u8RmtFitnessScoreOut','u8LclIlcStatusOut','bLclIlcStatusQfOut','u8HeartbeatLostCountOut'};
for i = 1:numel(inNames)
    add_block('built-in/Inport', [sa '/' inNames{i}]);
    add_block('built-in/Outport', [sa '/' saOut{i}]);
    add_line(sa, [inNames{i} '/1'], [saOut{i} '/1'], 'autorouting', 'on');
end
set_param(sa, 'Description', ...
    '信号调理与类型转换：本期 8 路输入类型已与内部约定一致，按原类型直通；后续类型不一致时在此集中加入 Data Type Conversion');

%% ============================================================
%% LRM_MLS_ManageLaneStatus : HB failure + 4-state machine + 3 counters
%% ============================================================
mls = [ms '/LRM_MLS_ManageLaneStatus'];
add_block('built-in/Inport', [mls '/u8OperMode']);
add_block('built-in/Inport', [mls '/u8LclIlcStatus']);
add_block('built-in/Inport', [mls '/bLclIlcStatusQf']);
add_block('built-in/Inport', [mls '/u8HeartbeatLostCount']);
add_block('built-in/Outport', [mls '/u8LaneStatus']);
add_block('built-in/Outport', [mls '/u8PrevLaneStatus']);
add_block('built-in/Outport', [mls '/bLaneStatusCntrInPrgs']);
add_block('built-in/Outport', [mls '/u32HbMonitorCounter']);
add_block('built-in/Outport', [mls '/u32IlcStsMonitorCounter']);
add_block('built-in/Outport', [mls '/u32FailureMonitorCounter']);

% HB continuity: HB_Failure = NOT(heartbeat == delay+1 mod 256)
addUD(mls, 'Delay_Hb', '0', 'uint8');
w(mls, 'u8HeartbeatLostCount', 'Delay_Hb');
addConst(mls, 'Const_One_Hb', '1', 'uint8');
addSum(mls, 'Sum_Expected', '++', 'uint8');
w2(mls, 'Delay_Hb', 'Sum_Expected', 1);
w2(mls, 'Const_One_Hb', 'Sum_Expected', 2);
addRelop(mls, 'Relop_HbOk', '==');
w2(mls, 'u8HeartbeatLostCount', 'Relop_HbOk', 1);
w2(mls, 'Sum_Expected', 'Relop_HbOk', 2);
addLogic(mls, 'Logic_NotHbOk', 'NOT', 1);
w(mls, 'Relop_HbOk', 'Logic_NotHbOk');      % hbFail

% OPER MODE active (1..4)
addConst(mls, 'Const_OpMode1', '1', 'uint8');
addConst(mls, 'Const_OpMode2', '2', 'uint8');
addConst(mls, 'Const_OpMode3', '3', 'uint8');
addConst(mls, 'Const_OpMode4', '4', 'uint8');
addRelop(mls, 'Relop_Om1', '==');
addRelop(mls, 'Relop_Om2', '==');
addRelop(mls, 'Relop_Om3', '==');
addRelop(mls, 'Relop_Om4', '==');
w2(mls, 'u8OperMode', 'Relop_Om1', 1); w2(mls, 'Const_OpMode1', 'Relop_Om1', 2);
w2(mls, 'u8OperMode', 'Relop_Om2', 1); w2(mls, 'Const_OpMode2', 'Relop_Om2', 2);
w2(mls, 'u8OperMode', 'Relop_Om3', 1); w2(mls, 'Const_OpMode3', 'Relop_Om3', 2);
w2(mls, 'u8OperMode', 'Relop_Om4', 1); w2(mls, 'Const_OpMode4', 'Relop_Om4', 2);
addLogic(mls, 'Logic_OperModeActive', 'OR', 4);
w2(mls, 'Relop_Om1', 'Logic_OperModeActive', 1);
w2(mls, 'Relop_Om2', 'Logic_OperModeActive', 2);
w2(mls, 'Relop_Om3', 'Logic_OperModeActive', 3);
w2(mls, 'Relop_Om4', 'Logic_OperModeActive', 4);

% QF semantics: 0=Full(ok), 1=NotFull(bad) -> QfBad = bLclIlcStatusQf
addLogic(mls, 'Logic_NotQf', 'NOT', 1);
w(mls, 'bLclIlcStatusQf', 'Logic_NotQf');    % qfOk

% State register
addUD(mls, 'Delay_State', '0', 'uint8');
addConst(mls, 'Const_StateInit', '0', 'uint8');
addConst(mls, 'Const_StateOp', '1', 'uint8');
addConst(mls, 'Const_StateHbLost', '2', 'uint8');
addConst(mls, 'Const_StateFailed', '3', 'uint8');
addRelop(mls, 'Relop_StateInit', '==');
addRelop(mls, 'Relop_StateOp', '==');
addRelop(mls, 'Relop_StateHbLost', '==');
addRelop(mls, 'Relop_StateFailed', '==');
w2(mls, 'Delay_State', 'Relop_StateInit', 1);    w2(mls, 'Const_StateInit', 'Relop_StateInit', 2);
w2(mls, 'Delay_State', 'Relop_StateOp', 1);      w2(mls, 'Const_StateOp', 'Relop_StateOp', 2);
w2(mls, 'Delay_State', 'Relop_StateHbLost', 1);  w2(mls, 'Const_StateHbLost', 'Relop_StateHbLost', 2);
w2(mls, 'Delay_State', 'Relop_StateFailed', 1);  w2(mls, 'Const_StateFailed', 'Relop_StateFailed', 2);

% counters active = (INIT && operModeActive) || OPERATING
addLogic(mls, 'Logic_InitActive', 'AND', 2);
w2(mls, 'Relop_StateInit', 'Logic_InitActive', 1);
w2(mls, 'Logic_OperModeActive', 'Logic_InitActive', 2);
addLogic(mls, 'Logic_CountersActive', 'OR', 2);
w2(mls, 'Logic_InitActive', 'Logic_CountersActive', 1);
w2(mls, 'Relop_StateOp', 'Logic_CountersActive', 2);

% Counter enables
addLogic(mls, 'Logic_HbCntEn', 'AND', 2);
w2(mls, 'Logic_CountersActive', 'Logic_HbCntEn', 1);
w2(mls, 'Logic_NotHbOk', 'Logic_HbCntEn', 2);
addLogic(mls, 'Logic_IlcCntEn', 'AND', 2);
w2(mls, 'Logic_CountersActive', 'Logic_IlcCntEn', 1);
w2(mls, 'bLclIlcStatusQf', 'Logic_IlcCntEn', 2);
addLogic(mls, 'Logic_FailCntEn', 'AND', 2);
w2(mls, 'Logic_CountersActive', 'Logic_FailCntEn', 1);
w2(mls, 'Logic_NotHbOk', 'Logic_FailCntEn', 2);

% Counters: Hb / ILC / Failure
addCounter(mls, 'HbCnt', 'Logic_HbCntEn');
addCounter(mls, 'IlcCnt', 'Logic_IlcCntEn');
addCounter(mls, 'FailCnt', 'Logic_FailCntEn');

% Watch window constant (cal_u8RmtLaneFailThd, compared as uint32)
addConst(mls, 'cal_u8RmtLaneFailThd', 'cal_u8RmtLaneFailThd', 'uint8', ...
    'cal_u8RmtLaneFailThd；故障监控窗口阈值（周期数），对应 P_MLR_RMTLaneFallThd；uint8；单位 cycle；范围 0..255；默认 20');
addDTC(mls, 'DTC_Watch', 'uint32');
w(mls, 'cal_u8RmtLaneFailThd', 'DTC_Watch');

% abs(int32(Hb - ILC)) <= 5
addDTC(mls, 'DTC_HbCntI', 'int32');
addDTC(mls, 'DTC_IlcCntI', 'int32');
w(mls, 'Delay_HbCnt', 'DTC_HbCntI');
w(mls, 'Delay_IlcCnt', 'DTC_IlcCntI');
addSum(mls, 'Sum_Diff', '+-', 'int32');
w2(mls, 'DTC_HbCntI', 'Sum_Diff', 1);
w2(mls, 'DTC_IlcCntI', 'Sum_Diff', 2);
add_block('simulink/Math Operations/Abs', [mls '/Abs_Diff']);
set_param([mls '/Abs_Diff'], 'OutDataTypeStr', 'int32');
w(mls, 'Sum_Diff', 'Abs_Diff');
addConst(mls, 'Const_DiffLe5', '5', 'int32');
addRelop(mls, 'Relop_DiffLe5', '<=');
w2(mls, 'Abs_Diff', 'Relop_DiffLe5', 1);
w2(mls, 'Const_DiffLe5', 'Relop_DiffLe5', 2);

% Counter >= watch window
addRelop(mls, 'Relop_HbCntWatch', '>=');
w2(mls, 'Delay_HbCnt', 'Relop_HbCntWatch', 1);
w2(mls, 'DTC_Watch', 'Relop_HbCntWatch', 2);
addRelop(mls, 'Relop_FailCntWatch', '>=');
w2(mls, 'Delay_FailCnt', 'Relop_FailCntWatch', 1);
w2(mls, 'DTC_Watch', 'Relop_FailCntWatch', 2);

% enterOperating
addLogic(mls, 'Logic_OpFromInit', 'AND', 4);
w2(mls, 'Relop_StateInit', 'Logic_OpFromInit', 1);
w2(mls, 'Logic_OperModeActive', 'Logic_OpFromInit', 2);
w2(mls, 'Logic_NotQf', 'Logic_OpFromInit', 3);
w2(mls, 'Logic_NotHbOk', 'Logic_OpFromInit', 4);
addLogic(mls, 'Logic_OpFromHbLost', 'AND', 2);
w2(mls, 'Relop_StateHbLost', 'Logic_OpFromHbLost', 1);
w2(mls, 'Logic_NotHbOk', 'Logic_OpFromHbLost', 2);
addLogic(mls, 'Logic_OpFromFailed', 'AND', 2);
w2(mls, 'Relop_StateFailed', 'Logic_OpFromFailed', 1);
w2(mls, 'Logic_NotHbOk', 'Logic_OpFromFailed', 2);
addLogic(mls, 'Logic_EnterOp', 'OR', 3);
w2(mls, 'Logic_OpFromInit', 'Logic_EnterOp', 1);
w2(mls, 'Logic_OpFromHbLost', 'Logic_EnterOp', 2);
w2(mls, 'Logic_OpFromFailed', 'Logic_EnterOp', 3);

% enterFailed
addLogic(mls, 'Logic_StateInitOrOp', 'OR', 2);
w2(mls, 'Relop_StateInit', 'Logic_StateInitOrOp', 1);
w2(mls, 'Relop_StateOp', 'Logic_StateInitOrOp', 2);
addLogic(mls, 'Logic_EnterFailed', 'AND', 3);
w2(mls, 'Logic_StateInitOrOp', 'Logic_EnterFailed', 1);
w2(mls, 'Relop_DiffLe5', 'Logic_EnterFailed', 2);
w2(mls, 'Relop_FailCntWatch', 'Logic_EnterFailed', 3);

% enterHbLost
addLogic(mls, 'Logic_HbLostFromInitOp', 'AND', 3);
w2(mls, 'Logic_StateInitOrOp', 'Logic_HbLostFromInitOp', 1);
w2(mls, 'Relop_HbCntWatch', 'Logic_HbLostFromInitOp', 2);
w2(mls, 'Relop_FailCntWatch', 'Logic_HbLostFromInitOp', 3);
addLogic(mls, 'Logic_HbLostFromFailed', 'AND', 2);
w2(mls, 'Relop_StateFailed', 'Logic_HbLostFromFailed', 1);
w2(mls, 'Logic_NotQf', 'Logic_HbLostFromFailed', 2);
addLogic(mls, 'Logic_EnterHbLost', 'OR', 2);
w2(mls, 'Logic_HbLostFromInitOp', 'Logic_EnterHbLost', 1);
w2(mls, 'Logic_HbLostFromFailed', 'Logic_EnterHbLost', 2);

% next state priority chain: Operating > Failed > HbLost > hold
addSwitch(mls, 'Sw_Next3', 'uint8');
w2(mls, 'Const_StateHbLost', 'Sw_Next3', 1);
w2(mls, 'Logic_EnterHbLost', 'Sw_Next3', 2);
w2(mls, 'Delay_State', 'Sw_Next3', 3);
addSwitch(mls, 'Sw_Next2', 'uint8');
w2(mls, 'Const_StateFailed', 'Sw_Next2', 1);
w2(mls, 'Logic_EnterFailed', 'Sw_Next2', 2);
w2(mls, 'Sw_Next3', 'Sw_Next2', 3);
addSwitch(mls, 'Sw_Next1', 'uint8');
w2(mls, 'Const_StateOp', 'Sw_Next1', 1);
w2(mls, 'Logic_EnterOp', 'Sw_Next1', 2);
w2(mls, 'Sw_Next2', 'Sw_Next1', 3);
w(mls, 'Sw_Next1', 'Delay_State');

% LaneStatus / prevLaneStatus / LaneStatusCntrInPrgs
w(mls, 'Delay_State', 'u8LaneStatus');
add_block('simulink/Sinks/Terminator', [mls '/Term_LclIlcStatus']);
w(mls, 'u8LclIlcStatus', 'Term_LclIlcStatus');
addUD(mls, 'Delay_PrevState', '0', 'uint8');
w(mls, 'Delay_State', 'Delay_PrevState');
w(mls, 'Delay_PrevState', 'u8PrevLaneStatus');
addLogic(mls, 'Logic_CntrInPrgs', 'OR', 2);
w2(mls, 'Logic_NotHbOk', 'Logic_CntrInPrgs', 1);
w2(mls, 'bLclIlcStatusQf', 'Logic_CntrInPrgs', 2);
w(mls, 'Logic_CntrInPrgs', 'bLaneStatusCntrInPrgs');
w(mls, 'Delay_HbCnt', 'u32HbMonitorCounter');
w(mls, 'Delay_IlcCnt', 'u32IlcStsMonitorCounter');
w(mls, 'Delay_FailCnt', 'u32FailureMonitorCounter');

%% ============================================================
%% LRM_MLR_ManageLaneRole : 6-state role machine + 5 counters
%% state encoding: 1=INIT 2=MASTER 3=FALLBACK 4=SUPPORT 5=DISABLED 6=SHUTTING_DOWN
%% ============================================================
mlr = [ms '/LRM_MLR_ManageLaneRole'];
add_block('built-in/Inport', [mlr '/u8LclFitnessScore']);
add_block('built-in/Inport', [mlr '/u8RmtFitnessScore']);
add_block('built-in/Inport', [mlr '/u8LclIlcStatus']);
add_block('built-in/Inport', [mlr '/u8LclLaneOperMode']);
add_block('built-in/Inport', [mlr '/u8RmtLaneRole']);
add_block('built-in/Inport', [mlr '/u8LaneStatus']);
add_block('built-in/Inport', [mlr '/u32FailureMonitorCounter']);
add_block('built-in/Outport', [mlr '/u8LaneRole']);
add_block('built-in/Outport', [mlr '/u8PrevLaneRole']);
add_block('built-in/Outport', [mlr '/bLaneRoleCntrInPrgs']);
add_block('built-in/Outport', [mlr '/u32InitWaitTimeCounter']);
add_block('built-in/Outport', [mlr '/u32MasterFallbackSwapCntr']);
add_block('built-in/Outport', [mlr '/u32FallbackMasterTakeoverCntr']);
add_block('built-in/Outport', [mlr '/u32FallbackSupportSwapCntr']);
add_block('built-in/Outport', [mlr '/u32SupportMasterTakeoverCntr']);

addUD(mlr, 'Delay_State', '1', 'uint8');
addConst(mlr, 'Const_StateInit', '1', 'uint8');
addConst(mlr, 'Const_StateMaster', '2', 'uint8');
addConst(mlr, 'Const_StateFallback', '3', 'uint8');
addConst(mlr, 'Const_StateSupport', '4', 'uint8');
addConst(mlr, 'Const_StateDisabled', '5', 'uint8');
addConst(mlr, 'Const_StateShutdown', '6', 'uint8');
addRelop(mlr, 'Relop_StateInit', '==');
addRelop(mlr, 'Relop_StateMaster', '==');
addRelop(mlr, 'Relop_StateFallback', '==');
addRelop(mlr, 'Relop_StateSupport', '==');
addRelop(mlr, 'Relop_StateDisabled', '==');
addRelop(mlr, 'Relop_StateShutdown', '==');
w2(mlr, 'Delay_State', 'Relop_StateInit', 1);       w2(mlr, 'Const_StateInit', 'Relop_StateInit', 2);
w2(mlr, 'Delay_State', 'Relop_StateMaster', 1);     w2(mlr, 'Const_StateMaster', 'Relop_StateMaster', 2);
w2(mlr, 'Delay_State', 'Relop_StateFallback', 1);   w2(mlr, 'Const_StateFallback', 'Relop_StateFallback', 2);
w2(mlr, 'Delay_State', 'Relop_StateSupport', 1);    w2(mlr, 'Const_StateSupport', 'Relop_StateSupport', 2);
w2(mlr, 'Delay_State', 'Relop_StateDisabled', 1);   w2(mlr, 'Const_StateDisabled', 'Relop_StateDisabled', 2);
w2(mlr, 'Delay_State', 'Relop_StateShutdown', 1);   w2(mlr, 'Const_StateShutdown', 'Relop_StateShutdown', 2);

% Basic conditions
addConst(mlr, 'Const_Zero', '0', 'uint8');
addConst(mlr, 'Const_62', '62', 'uint8');
addConst(mlr, 'Const_255', '255', 'uint8');
addConst(mlr, 'Const_1', '1', 'uint8');
addConst(mlr, 'Const_2', '2', 'uint8');
addConst(mlr, 'Const_3', '3', 'uint8');
addConst(mlr, 'Const_5', '5', 'uint8');
addConst(mlr, 'Const_6', '6', 'uint8');
addRelop(mlr, 'Relop_OperShutdown', '==');  w2(mlr, 'u8LclLaneOperMode', 'Relop_OperShutdown', 1); w2(mlr, 'Const_5', 'Relop_OperShutdown', 2);
addRelop(mlr, 'Relop_LclDisabled', '==');   w2(mlr, 'u8LclFitnessScore', 'Relop_LclDisabled', 1); w2(mlr, 'Const_62', 'Relop_LclDisabled', 2);
addRelop(mlr, 'Relop_LclGtRmt', '>');       w2(mlr, 'u8LclFitnessScore', 'Relop_LclGtRmt', 1); w2(mlr, 'u8RmtFitnessScore', 'Relop_LclGtRmt', 2);
addRelop(mlr, 'Relop_LclLtRmt', '<');       w2(mlr, 'u8LclFitnessScore', 'Relop_LclLtRmt', 1); w2(mlr, 'u8RmtFitnessScore', 'Relop_LclLtRmt', 2);
addRelop(mlr, 'Relop_RmtMaster', '==');     w2(mlr, 'u8RmtLaneRole', 'Relop_RmtMaster', 1); w2(mlr, 'Const_2', 'Relop_RmtMaster', 2);
addRelop(mlr, 'Relop_RmtFallback', '==');   w2(mlr, 'u8RmtLaneRole', 'Relop_RmtFallback', 1); w2(mlr, 'Const_3', 'Relop_RmtFallback', 2);
addRelop(mlr, 'Relop_RmtDisabled', '==');   w2(mlr, 'u8RmtLaneRole', 'Relop_RmtDisabled', 1); w2(mlr, 'Const_5', 'Relop_RmtDisabled', 2);
addRelop(mlr, 'Relop_RmtShutdown', '==');   w2(mlr, 'u8RmtLaneRole', 'Relop_RmtShutdown', 1); w2(mlr, 'Const_6', 'Relop_RmtShutdown', 2);
addRelop(mlr, 'Relop_RmtUnknown', '==');    w2(mlr, 'u8RmtLaneRole', 'Relop_RmtUnknown', 1); w2(mlr, 'Const_1', 'Relop_RmtUnknown', 2);
addRelop(mlr, 'Relop_IlcFailed', '==');     w2(mlr, 'u8LclIlcStatus', 'Relop_IlcFailed', 1); w2(mlr, 'Const_Zero', 'Relop_IlcFailed', 2);
addRelop(mlr, 'Relop_LaneStsFailed', '=='); w2(mlr, 'u8LaneStatus', 'Relop_LaneStsFailed', 1); w2(mlr, 'Const_3', 'Relop_LaneStsFailed', 2);
addRelop(mlr, 'Relop_RmtScoreValid', '~='); w2(mlr, 'u8RmtFitnessScore', 'Relop_RmtScoreValid', 1); w2(mlr, 'Const_255', 'Relop_RmtScoreValid', 2);
addLogic(mlr, 'Logic_NotRmtMaster', 'NOT', 1);
w(mlr, 'Relop_RmtMaster', 'Logic_NotRmtMaster');

% Calibration constants (uint16) -> uint32 for comparison
addConst(mlr, 'cal_u16LaneInitWaitTime', 'cal_u16LaneInitWaitTime', 'uint16', 'cal_u16LaneInitWaitTime；初始化等待时间阈值（周期数），对应 LANE_INIT_WAIT_TIME；uint16；cycle；默认 100（待确认）');
addConst(mlr, 'cal_u16TakeoverTime', 'cal_u16TakeoverTime', 'uint16', 'cal_u16TakeoverTime；接管时间阈值（周期数），对应 TAKEOVER_TIME；uint16；cycle；默认 50（待确认）');
addConst(mlr, 'cal_u16FallbackSupportSwapTime', 'cal_u16FallbackSupportSwapTime', 'uint16', 'cal_u16FallbackSupportSwapTime；Fallback 向 Support 降级时间阈值，对应 LANE_FALLBACK_SUPPORT_SWAP_TIME；uint16；cycle；默认 50（待确认）');
addConst(mlr, 'cal_u16FailWatchWindow', 'cal_u16FailWatchWindow', 'uint16', 'cal_u16FailWatchWindow；故障监控窗口阈值，对应 FAIL_WATCH_WINDOW；uint16；cycle；默认 20（待确认）');
addConst(mlr, 'cal_u16MasterFallbackSwapThd', 'cal_u16MasterFallbackSwapThd', 'uint16', 'cal_u16MasterFallbackSwapThd；Master 向 Fallback 切换计数阈值；uint16；cycle；默认 20');
addDTC(mlr, 'DTC_InitWaitThd', 'uint32');  w(mlr, 'cal_u16LaneInitWaitTime', 'DTC_InitWaitThd');
addDTC(mlr, 'DTC_TakeoverThd', 'uint32');  w(mlr, 'cal_u16TakeoverTime', 'DTC_TakeoverThd');
addDTC(mlr, 'DTC_FbSpSwapThd', 'uint32');  w(mlr, 'cal_u16FallbackSupportSwapTime', 'DTC_FbSpSwapThd');
addDTC(mlr, 'DTC_FailWatch', 'uint32');    w(mlr, 'cal_u16FailWatchWindow', 'DTC_FailWatch');
addDTC(mlr, 'DTC_MasterSwapThd', 'uint32');w(mlr, 'cal_u16MasterFallbackSwapThd', 'DTC_MasterSwapThd');

% Counters (created before the branch logic that references them)
addCounter(mlr, 'InitWait', 'Relop_StateInit');
addLogic(mlr, 'Logic_MasterSwapEn', 'AND', 2);
w2(mlr, 'Relop_StateMaster', 'Logic_MasterSwapEn', 1);
w2(mlr, 'Relop_LclLtRmt', 'Logic_MasterSwapEn', 2);
addCounter(mlr, 'MasterSwap', 'Logic_MasterSwapEn');
addLogic(mlr, 'Logic_FbMasterTakeoverEn', 'AND', 2);
w2(mlr, 'Relop_StateFallback', 'Logic_FbMasterTakeoverEn', 1);
w2(mlr, 'Relop_LclGtRmt', 'Logic_FbMasterTakeoverEn', 2);
addCounter(mlr, 'FbMasterTakeover', 'Logic_FbMasterTakeoverEn');
addLogic(mlr, 'Logic_FbSupportSwapEn', 'AND', 2);
w2(mlr, 'Relop_StateFallback', 'Logic_FbSupportSwapEn', 1);
w2(mlr, 'Relop_LclLtRmt', 'Logic_FbSupportSwapEn', 2);
addCounter(mlr, 'FbSupportSwap', 'Logic_FbSupportSwapEn');
addLogic(mlr, 'Logic_SpMasterTakeoverEn', 'AND', 2);
w2(mlr, 'Relop_StateSupport', 'Logic_SpMasterTakeoverEn', 1);
w2(mlr, 'Relop_LclGtRmt', 'Logic_SpMasterTakeoverEn', 2);
addCounter(mlr, 'SpMasterTakeover', 'Logic_SpMasterTakeoverEn');

% INIT exit condition
addRelop(mlr, 'Relop_InitWaitReady', '>=');
w2(mlr, 'Delay_InitWait', 'Relop_InitWaitReady', 1);
w2(mlr, 'DTC_InitWaitThd', 'Relop_InitWaitReady', 2);
addLogic(mlr, 'Logic_InitReady', 'AND', 2);
w2(mlr, 'Relop_InitWaitReady', 'Logic_InitReady', 1);
w2(mlr, 'Relop_LclGtRmt', 'Logic_InitReady', 2);
addLogic(mlr, 'Logic_ExitInit', 'OR', 2);
w2(mlr, 'Logic_InitReady', 'Logic_ExitInit', 1);
w2(mlr, 'Relop_RmtMaster', 'Logic_ExitInit', 2);
addSwitch(mlr, 'Sw_RoleTarget', 'uint8');
w2(mlr, 'Const_StateMaster', 'Sw_RoleTarget', 1);
w2(mlr, 'Relop_LclGtRmt', 'Sw_RoleTarget', 2);
w2(mlr, 'Const_StateFallback', 'Sw_RoleTarget', 3);
addLogic(mlr, 'Logic_Sw4Gate', 'AND', 2);
w2(mlr, 'Relop_StateInit', 'Logic_Sw4Gate', 1);
w2(mlr, 'Logic_ExitInit', 'Logic_Sw4Gate', 2);

% Master branch
addLogic(mlr, 'Logic_MSupport', 'AND', 3);
w2(mlr, 'Relop_IlcFailed', 'Logic_MSupport', 1);
w2(mlr, 'Relop_RmtScoreValid', 'Logic_MSupport', 2);
w2(mlr, 'Relop_LclLtRmt', 'Logic_MSupport', 3);
addLogic(mlr, 'Logic_MFallbackImm', 'AND', 2);
w2(mlr, 'Relop_LclLtRmt', 'Logic_MFallbackImm', 1);
w2(mlr, 'Relop_RmtMaster', 'Logic_MFallbackImm', 2);
addRelop(mlr, 'Relop_MasterSwapCnt', '>');
w2(mlr, 'Delay_MasterSwap', 'Relop_MasterSwapCnt', 1);
w2(mlr, 'DTC_MasterSwapThd', 'Relop_MasterSwapCnt', 2);
addLogic(mlr, 'Logic_MFallbackCnt', 'AND', 3);
w2(mlr, 'Relop_LclLtRmt', 'Logic_MFallbackCnt', 1);
w2(mlr, 'Relop_RmtFallback', 'Logic_MFallbackCnt', 2);
w2(mlr, 'Relop_MasterSwapCnt', 'Logic_MFallbackCnt', 3);
addSwitch(mlr, 'Sw_M3', 'uint8');
w2(mlr, 'Const_StateFallback', 'Sw_M3', 1);
w2(mlr, 'Logic_MFallbackCnt', 'Sw_M3', 2);
w2(mlr, 'Const_StateMaster', 'Sw_M3', 3);
addSwitch(mlr, 'Sw_M2', 'uint8');
w2(mlr, 'Const_StateFallback', 'Sw_M2', 1);
w2(mlr, 'Logic_MFallbackImm', 'Sw_M2', 2);
w2(mlr, 'Sw_M3', 'Sw_M2', 3);
addSwitch(mlr, 'Sw_M1', 'uint8');
w2(mlr, 'Const_StateSupport', 'Sw_M1', 1);
w2(mlr, 'Logic_MSupport', 'Sw_M1', 2);
w2(mlr, 'Sw_M2', 'Sw_M1', 3);

% Fallback branch
addLogic(mlr, 'Logic_FbMasterImm', 'OR', 3);
w2(mlr, 'Relop_LaneStsFailed', 'Logic_FbMasterImm', 1);
w2(mlr, 'Relop_RmtDisabled', 'Logic_FbMasterImm', 2);
w2(mlr, 'Relop_RmtShutdown', 'Logic_FbMasterImm', 3);
addRelop(mlr, 'Relop_FbMasterCnt', '>');
w2(mlr, 'Delay_FbMasterTakeover', 'Relop_FbMasterCnt', 1);
w2(mlr, 'DTC_TakeoverThd', 'Relop_FbMasterCnt', 2);
addLogic(mlr, 'Logic_FbMasterTakeover', 'AND', 3);
w2(mlr, 'Relop_LclGtRmt', 'Logic_FbMasterTakeover', 1);
w2(mlr, 'Relop_FbMasterCnt', 'Logic_FbMasterTakeover', 2);
w2(mlr, 'Logic_NotRmtMaster', 'Logic_FbMasterTakeover', 3);
addRelop(mlr, 'Relop_FbSupportCnt', '>');
w2(mlr, 'Delay_FbSupportSwap', 'Relop_FbSupportCnt', 1);
w2(mlr, 'DTC_FbSpSwapThd', 'Relop_FbSupportCnt', 2);
addLogic(mlr, 'Logic_FbSupportSwap', 'AND', 2);
w2(mlr, 'Relop_LclLtRmt', 'Logic_FbSupportSwap', 1);
w2(mlr, 'Relop_FbSupportCnt', 'Logic_FbSupportSwap', 2);
addRelop(mlr, 'Relop_FbFailCnt', '>');
w2(mlr, 'u32FailureMonitorCounter', 'Relop_FbFailCnt', 1);
w2(mlr, 'DTC_FailWatch', 'Relop_FbFailCnt', 2);
addLogic(mlr, 'Logic_FbSupportFail', 'AND', 2);
w2(mlr, 'Relop_RmtUnknown', 'Logic_FbSupportFail', 1);
w2(mlr, 'Relop_FbFailCnt', 'Logic_FbSupportFail', 2);
addSwitch(mlr, 'Sw_F4', 'uint8');
w2(mlr, 'Const_StateSupport', 'Sw_F4', 1);
w2(mlr, 'Logic_FbSupportFail', 'Sw_F4', 2);
w2(mlr, 'Const_StateFallback', 'Sw_F4', 3);
addSwitch(mlr, 'Sw_F3', 'uint8');
w2(mlr, 'Const_StateSupport', 'Sw_F3', 1);
w2(mlr, 'Logic_FbSupportSwap', 'Sw_F3', 2);
w2(mlr, 'Sw_F4', 'Sw_F3', 3);
addSwitch(mlr, 'Sw_F2', 'uint8');
w2(mlr, 'Const_StateMaster', 'Sw_F2', 1);
w2(mlr, 'Logic_FbMasterTakeover', 'Sw_F2', 2);
w2(mlr, 'Sw_F3', 'Sw_F2', 3);
addSwitch(mlr, 'Sw_F1', 'uint8');
w2(mlr, 'Const_StateMaster', 'Sw_F1', 1);
w2(mlr, 'Logic_FbMasterImm', 'Sw_F1', 2);
w2(mlr, 'Sw_F2', 'Sw_F1', 3);

% Support branch
addRelop(mlr, 'Relop_SpMasterCnt', '>');
w2(mlr, 'Delay_SpMasterTakeover', 'Relop_SpMasterCnt', 1);
w2(mlr, 'DTC_TakeoverThd', 'Relop_SpMasterCnt', 2);
addLogic(mlr, 'Logic_SpMasterTakeover', 'AND', 3);
w2(mlr, 'Relop_LclGtRmt', 'Logic_SpMasterTakeover', 1);
w2(mlr, 'Relop_SpMasterCnt', 'Logic_SpMasterTakeover', 2);
w2(mlr, 'Logic_NotRmtMaster', 'Logic_SpMasterTakeover', 3);
addLogic(mlr, 'Logic_NotIlcFailed', 'NOT', 1);
w(mlr, 'Relop_IlcFailed', 'Logic_NotIlcFailed');
addLogic(mlr, 'Logic_SpFallback', 'AND', 2);
w2(mlr, 'Logic_NotIlcFailed', 'Logic_SpFallback', 1);
w2(mlr, 'Relop_RmtMaster', 'Logic_SpFallback', 2);
addSwitch(mlr, 'Sw_S3', 'uint8');
w2(mlr, 'Const_StateFallback', 'Sw_S3', 1);
w2(mlr, 'Logic_SpFallback', 'Sw_S3', 2);
w2(mlr, 'Const_StateSupport', 'Sw_S3', 3);
addSwitch(mlr, 'Sw_S2', 'uint8');
w2(mlr, 'Const_StateMaster', 'Sw_S2', 1);
w2(mlr, 'Logic_SpMasterTakeover', 'Sw_S2', 2);
w2(mlr, 'Sw_S3', 'Sw_S2', 3);
addSwitch(mlr, 'Sw_S1', 'uint8');
w2(mlr, 'Const_StateMaster', 'Sw_S1', 1);
w2(mlr, 'Logic_FbMasterImm', 'Sw_S1', 2);
w2(mlr, 'Sw_S2', 'Sw_S1', 3);

% Priority chain
addSwitch(mlr, 'Sw_8', 'uint8');
w2(mlr, 'Const_StateDisabled', 'Sw_8', 1);
w2(mlr, 'Relop_StateDisabled', 'Sw_8', 2);
w2(mlr, 'Delay_State', 'Sw_8', 3);
addSwitch(mlr, 'Sw_7', 'uint8');
w2(mlr, 'Sw_S1', 'Sw_7', 1);
w2(mlr, 'Relop_StateSupport', 'Sw_7', 2);
w2(mlr, 'Sw_8', 'Sw_7', 3);
addSwitch(mlr, 'Sw_6', 'uint8');
w2(mlr, 'Sw_F1', 'Sw_6', 1);
w2(mlr, 'Relop_StateFallback', 'Sw_6', 2);
w2(mlr, 'Sw_7', 'Sw_6', 3);
addSwitch(mlr, 'Sw_5', 'uint8');
w2(mlr, 'Sw_M1', 'Sw_5', 1);
w2(mlr, 'Relop_StateMaster', 'Sw_5', 2);
w2(mlr, 'Sw_6', 'Sw_5', 3);
addSwitch(mlr, 'Sw_4', 'uint8');
w2(mlr, 'Sw_RoleTarget', 'Sw_4', 1);
w2(mlr, 'Logic_Sw4Gate', 'Sw_4', 2);
w2(mlr, 'Sw_5', 'Sw_4', 3);
addSwitch(mlr, 'Sw_3', 'uint8');
w2(mlr, 'Const_StateInit', 'Sw_3', 1);
w2(mlr, 'Relop_StateShutdown', 'Sw_3', 2);
w2(mlr, 'Sw_4', 'Sw_3', 3);
addSwitch(mlr, 'Sw_2', 'uint8');
w2(mlr, 'Const_StateDisabled', 'Sw_2', 1);
w2(mlr, 'Relop_LclDisabled', 'Sw_2', 2);
w2(mlr, 'Sw_3', 'Sw_2', 3);
addSwitch(mlr, 'Sw_1', 'uint8');
w2(mlr, 'Const_StateShutdown', 'Sw_1', 1);
w2(mlr, 'Relop_OperShutdown', 'Sw_1', 2);
w2(mlr, 'Sw_2', 'Sw_1', 3);
w(mlr, 'Sw_1', 'Delay_State');

% Outputs
w(mlr, 'Delay_State', 'u8LaneRole');
addUD(mlr, 'Delay_PrevRole', '1', 'uint8');
w(mlr, 'Delay_State', 'Delay_PrevRole');
w(mlr, 'Delay_PrevRole', 'u8PrevLaneRole');
w(mlr, 'Relop_StateInit', 'bLaneRoleCntrInPrgs');
w(mlr, 'Delay_InitWait', 'u32InitWaitTimeCounter');
w(mlr, 'Delay_MasterSwap', 'u32MasterFallbackSwapCntr');
w(mlr, 'Delay_FbMasterTakeover', 'u32FallbackMasterTakeoverCntr');
w(mlr, 'Delay_FbSupportSwap', 'u32FallbackSupportSwapCntr');
w(mlr, 'Delay_SpMasterTakeover', 'u32SupportMasterTakeoverCntr');

%% ============================================================
%% LRM_LSP_LaneSwitchInProgs : role-change debounce
%% ============================================================
lsp = [ms '/LRM_LSP_LaneSwitchInProgs'];
add_block('built-in/Inport', [lsp '/u8LaneRole']);
add_block('built-in/Inport', [lsp '/bLaneRoleCntrInPrgs']);
add_block('built-in/Inport', [lsp '/bLaneStatusCntrInPrgs']);
add_block('built-in/Outport', [lsp '/bLaneSwtgInProgs']);
add_block('built-in/Outport', [lsp '/u32LaneSwtInPrgsCntr']);

addUD(lsp, 'Delay_Role', '0', 'uint8');
w(lsp, 'u8LaneRole', 'Delay_Role');
addRelop(lsp, 'Relop_RoleChanged', '~=');
w2(lsp, 'u8LaneRole', 'Relop_RoleChanged', 1);
w2(lsp, 'Delay_Role', 'Relop_RoleChanged', 2);
addLogic(lsp, 'Logic_AnyTimer', 'OR', 2);
w2(lsp, 'bLaneRoleCntrInPrgs', 'Logic_AnyTimer', 1);
w2(lsp, 'bLaneStatusCntrInPrgs', 'Logic_AnyTimer', 2);

addConst(lsp, 'cal_u8RoleChangeDebounceTime', 'cal_u8RoleChangeDebounceTime', 'uint8', ...
    'cal_u8RoleChangeDebounceTime；角色切换防抖时间阈值（周期数），对应 ROLE_CHANGE_DEBOUNCE_TIME；uint8；cycle；0..255；默认 10');
addDTC(lsp, 'DTC_Debounce', 'uint32');
w(lsp, 'cal_u8RoleChangeDebounceTime', 'DTC_Debounce');

addUD(lsp, 'Delay_Cntr', '0', 'uint32');
addConst(lsp, 'Const_One_U32', '1', 'uint32');
addConst(lsp, 'Const_Zero_U32', '0', 'uint32');
addSum(lsp, 'Sum_Cntr', '++', 'uint32');
w2(lsp, 'Delay_Cntr', 'Sum_Cntr', 1);
w2(lsp, 'Const_One_U32', 'Sum_Cntr', 2);
addRelop(lsp, 'Relop_CntrGt0', '>');
w2(lsp, 'Delay_Cntr', 'Relop_CntrGt0', 1);
w2(lsp, 'Const_Zero_U32', 'Relop_CntrGt0', 2);
addRelop(lsp, 'Relop_CntrGtDeb', '>');
w2(lsp, 'Sum_Cntr', 'Relop_CntrGtDeb', 1);
w2(lsp, 'DTC_Debounce', 'Relop_CntrGtDeb', 2);

addSwitch(lsp, 'SwB_Cntr', 'uint32');
w2(lsp, 'Const_Zero_U32', 'SwB_Cntr', 1);
w2(lsp, 'Relop_CntrGtDeb', 'SwB_Cntr', 2);
w2(lsp, 'Sum_Cntr', 'SwB_Cntr', 3);
addSwitch(lsp, 'SwL3', 'uint32');
w2(lsp, 'Const_Zero_U32', 'SwL3', 1);
w2(lsp, 'Logic_AnyTimer', 'SwL3', 2);
w2(lsp, 'Delay_Cntr', 'SwL3', 3);
addSwitch(lsp, 'SwL2', 'uint32');
w2(lsp, 'SwB_Cntr', 'SwL2', 1);
w2(lsp, 'Relop_CntrGt0', 'SwL2', 2);
w2(lsp, 'SwL3', 'SwL2', 3);
addSwitch(lsp, 'SwL1', 'uint32');
w2(lsp, 'Const_One_U32', 'SwL1', 1);
w2(lsp, 'Relop_RoleChanged', 'SwL1', 2);
w2(lsp, 'SwL2', 'SwL1', 3);
w(lsp, 'SwL1', 'Delay_Cntr');

addConst(lsp, 'Const_One_Bool', 'true', 'boolean');
addConst(lsp, 'Const_Zero_Bool', 'false', 'boolean');
addSwitch(lsp, 'SwB_Flag', 'boolean');
w2(lsp, 'Const_Zero_Bool', 'SwB_Flag', 1);
w2(lsp, 'Relop_CntrGtDeb', 'SwB_Flag', 2);
w2(lsp, 'Const_One_Bool', 'SwB_Flag', 3);
addSwitch(lsp, 'SwF3', 'boolean');
w2(lsp, 'Const_One_Bool', 'SwF3', 1);
w2(lsp, 'Logic_AnyTimer', 'SwF3', 2);
w2(lsp, 'Const_Zero_Bool', 'SwF3', 3);
addSwitch(lsp, 'SwF2', 'boolean');
w2(lsp, 'SwB_Flag', 'SwF2', 1);
w2(lsp, 'Relop_CntrGt0', 'SwF2', 2);
w2(lsp, 'SwF3', 'SwF2', 3);
addSwitch(lsp, 'SwF1', 'boolean');
w2(lsp, 'Const_One_Bool', 'SwF1', 1);
w2(lsp, 'Relop_RoleChanged', 'SwF1', 2);
w2(lsp, 'SwF2', 'SwF1', 3);
w(lsp, 'SwF1', 'bLaneSwtgInProgs');
w(lsp, 'Delay_Cntr', 'u32LaneSwtInPrgsCntr');

%% ============================================================
%% OutputArbitration
%% ============================================================
oa = [ms '/OutputArbitration'];
add_block('built-in/Inport', [oa '/bLaneSwtgInProgs']);
add_block('built-in/Inport', [oa '/u8LaneRole']);
add_block('built-in/Inport', [oa '/u8RmtLaneRole']);
add_block('built-in/Outport', [oa '/bLaneSwtgInProgsOut']);
add_block('built-in/Outport', [oa '/bActvCtrlr']);
add_block('built-in/Outport', [oa '/u8RmtLaneSts']);
add_block('built-in/Outport', [oa '/u8LaneRoleOut']);
addRelop(oa, 'RelOp_MasterCheck', '==');
addConst(oa, 'Const_MasterRole', '2', 'uint8', 'LN_ROLE_MASTER 枚举值 2，用于 bActvCtrlr 判定');
w2(oa, 'u8LaneRole', 'RelOp_MasterCheck', 1);
w2(oa, 'Const_MasterRole', 'RelOp_MasterCheck', 2);
add_line(oa, 'bLaneSwtgInProgs/1', 'bLaneSwtgInProgsOut/1', 'autorouting', 'on');
add_line(oa, 'RelOp_MasterCheck/1', 'bActvCtrlr/1', 'autorouting', 'on');
add_line(oa, 'u8RmtLaneRole/1', 'u8RmtLaneSts/1', 'autorouting', 'on');
add_line(oa, 'u8LaneRole/1', 'u8LaneRoleOut/1', 'autorouting', 'on');
set_param(oa, 'Description', ...
    '输出仲裁与合并：bLaneSwtgInProgs 由 LSP 直通；bActvCtrlr=(u8LaneRole==LN_ROLE_MASTER)（Relational Operator 判等）；u8RmtLaneSts 暂由 u8RmtLaneRole 直通占位（映射待确认）；u8LaneRole 直通');

%% ============================================================
%% Wire MainSubsystem
%% ============================================================
add_line(ms, 'u8OperMode/1', 'SignalAcquisition/1', 'autorouting', 'on');
add_line(ms, 'u8LclLaneOperMode/1', 'SignalAcquisition/2', 'autorouting', 'on');
add_line(ms, 'u8RmtLaneRole/1', 'SignalAcquisition/3', 'autorouting', 'on');
add_line(ms, 'u8LclFitnessScore/1', 'SignalAcquisition/4', 'autorouting', 'on');
add_line(ms, 'u8RmtFitnessScore/1', 'SignalAcquisition/5', 'autorouting', 'on');
add_line(ms, 'u8LclIlcStatus/1', 'SignalAcquisition/6', 'autorouting', 'on');
add_line(ms, 'bLclIlcStatusQf/1', 'SignalAcquisition/7', 'autorouting', 'on');
add_line(ms, 'u8HeartbeatLostCount/1', 'SignalAcquisition/8', 'autorouting', 'on');

add_line(ms, 'SignalAcquisition/1', 'LRM_MLS_ManageLaneStatus/1', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/6', 'LRM_MLS_ManageLaneStatus/2', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/7', 'LRM_MLS_ManageLaneStatus/3', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/8', 'LRM_MLS_ManageLaneStatus/4', 'autorouting', 'on');

add_line(ms, 'SignalAcquisition/4', 'LRM_MLR_ManageLaneRole/1', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/5', 'LRM_MLR_ManageLaneRole/2', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/6', 'LRM_MLR_ManageLaneRole/3', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/2', 'LRM_MLR_ManageLaneRole/4', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/3', 'LRM_MLR_ManageLaneRole/5', 'autorouting', 'on');
add_line(ms, 'LRM_MLS_ManageLaneStatus/1', 'LRM_MLR_ManageLaneRole/6', 'autorouting', 'on');
add_line(ms, 'LRM_MLS_ManageLaneStatus/6', 'LRM_MLR_ManageLaneRole/7', 'autorouting', 'on');

add_line(ms, 'LRM_MLR_ManageLaneRole/1', 'LRM_LSP_LaneSwitchInProgs/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/3', 'LRM_LSP_LaneSwitchInProgs/2', 'autorouting', 'on');
add_line(ms, 'LRM_MLS_ManageLaneStatus/3', 'LRM_LSP_LaneSwitchInProgs/3', 'autorouting', 'on');

add_line(ms, 'LRM_LSP_LaneSwitchInProgs/1', 'OutputArbitration/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/1', 'OutputArbitration/2', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/3', 'OutputArbitration/3', 'autorouting', 'on');

add_line(ms, 'OutputArbitration/1', 'bLaneSwtgInProgs/1', 'autorouting', 'on');
add_line(ms, 'OutputArbitration/2', 'bActvCtrlr/1', 'autorouting', 'on');
add_line(ms, 'OutputArbitration/3', 'u8RmtLaneSts/1', 'autorouting', 'on');
add_line(ms, 'OutputArbitration/4', 'u8LaneRole/1', 'autorouting', 'on');

% Terminate diagnostic outputs inside MainSubsystem
add_block('simulink/Sinks/Terminator', [ms '/Term_MLS_PrevLaneStatus']);
add_block('simulink/Sinks/Terminator', [ms '/Term_MLS_HbCnt']);
add_block('simulink/Sinks/Terminator', [ms '/Term_MLS_IlcCnt']);
add_block('simulink/Sinks/Terminator', [ms '/Term_MLR_PrevRole']);
add_block('simulink/Sinks/Terminator', [ms '/Term_MLR_InitWait']);
add_block('simulink/Sinks/Terminator', [ms '/Term_MLR_MasterSwap']);
add_block('simulink/Sinks/Terminator', [ms '/Term_MLR_FbMasterTakeover']);
add_block('simulink/Sinks/Terminator', [ms '/Term_MLR_FbSupportSwap']);
add_block('simulink/Sinks/Terminator', [ms '/Term_MLR_SpMasterTakeover']);
add_block('simulink/Sinks/Terminator', [ms '/Term_LSP_Cntr']);
add_line(ms, 'LRM_MLS_ManageLaneStatus/2', 'Term_MLS_PrevLaneStatus/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLS_ManageLaneStatus/4', 'Term_MLS_HbCnt/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLS_ManageLaneStatus/5', 'Term_MLS_IlcCnt/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/2', 'Term_MLR_PrevRole/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/4', 'Term_MLR_InitWait/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/5', 'Term_MLR_MasterSwap/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/6', 'Term_MLR_FbMasterTakeover/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/7', 'Term_MLR_FbSupportSwap/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/8', 'Term_MLR_SpMasterTakeover/1', 'autorouting', 'on');
add_line(ms, 'LRM_LSP_LaneSwitchInProgs/2', 'Term_LSP_Cntr/1', 'autorouting', 'on');

%% ---------- Wire top level ----------
for i = 1:numel(inNames)
    add_line(model, [inNames{i} '/1'], ['MainSubsystem/' num2str(i)], 'autorouting', 'on');
end
for i = 1:numel(outNames)
    add_line(model, ['MainSubsystem/' num2str(i)], [outNames{i} '/1'], 'autorouting', 'on');
end

%% ---------- Subsystem Descriptions ----------
set_param(mls, 'Description', ...
    '监控 LCL ILC STATUS_QF、OPER MODE 与 LCL ILC STATUS，判定控制链路健康状态 LaneStatus。已实现：MLR_HB_Failure=(HEARTBEAT LOST COUNT != delay+1 mod 256)；计数器 HbMonitorCounter/ILCStsMonitorCounter/FailureMonitorCounter 仅监控激活时计数（Hb/Failure 以 HB_Failure>0 增量，ILC 以 QF!=FULL 增量）；四状态机 INIT/Operating/HbLost/Failed（优先级 Operating>Failed>HbLost）：INIT 在 OPER MODE 为 NORMAL/LIMP_HOME/LIMP_ASIDE/CRAWL 时激活监控；Operating 需 QF_FULL 且 HB_Failure=0；Failed 需 abs(int32(Hb-ILC))<=5 且 FailureCnt>=cal_u8RmtLaneFailThd；HbLost 需 HbCnt>=cal_u8RmtLaneFailThd 且 FailureCnt>=cal_u8RmtLaneFailThd（或从 Failed 且 QF_FULL）；进入非 Operating 状态清零计数器；LaneStatusCntrInPrgs=HB_Failure>0 OR QF!=FULL。由 Unit Delay / Sum / Relational Operator / Logical Operator / Switch 组合实现');
set_param(mlr, 'Description', ...
    '基于健康度得分、ILC 状态、远链路角色与控制链路状态仲裁本链路角色 LaneRole。已实现：6 状态编码（1=INIT，2=MASTER，3=FALLBACK，4=SUPPORT，5=DISABLED，6=SHUTTING_DOWN），Unit Delay 状态寄存器+Switch 优先级链（SHUTTING_DOWN>DISABLED>退出 SHUTTING_DOWN>各运行态）；INIT 等待 InitWaitTimeCounter>=cal_u16LaneInitWaitTime 且 Lcl>Rmt（或 Rmt==MASTER）后进入运行态（Lcl>Rmt 选 MASTER 否则 FALLBACK）；Master 在 ILC_FAILED 且 RmtScore!=255 且 Lcl<Rmt 时立即转 SUPPORT，Rmt==MASTER 立即转 FALLBACK，Lcl<Rmt 持续且 MasterFallbackSwapCntr>cal_u16MasterFallbackSwapThd 转 FALLBACK；Fallback 在 LaneStatus==FAILED 或 Rmt==DISABLED/SHUTTING_DOWN 时立即转 MASTER，Lcl>Rmt 持续且 FallbackMasterTakeoverCntr>cal_u16TakeoverTime 且 Rmt!=MASTER 时转 MASTER，Lcl<Rmt 持续且 FallbackSupportSwapCntr>cal_u16FallbackSupportSwapTime 转 SUPPORT，Rmt==UNKNOWN 且 FailureMonitorCounter>cal_u16FailWatchWindow 转 SUPPORT；Support 在 LaneStatus==FAILED 或 Rmt==DISABLED/SHUTTING_DOWN 时立即转 MASTER，Lcl>Rmt 持续且 SupportMasterTakeoverCntr>cal_u16TakeoverTime 且 Rmt!=MASTER 转 MASTER，!ILC_FAILED 且 Rmt==MASTER 转 FALLBACK。计数器按状态与条件使能（Unit Delay+Sum+Switch）；LaneRoleCntrInPrgs=(state==INIT)');
set_param(lsp, 'Description', ...
    '检测角色变化并管理切换过渡过程。已实现：LaneRoleChanged=(u8LaneRole != delay)；IfAnyTimerNonZero=bLaneRoleCntrInPrgs OR bLaneStatusCntrInPrgs；切换计数器按优先级 A>B>C：A) 角色变化置计数=1/标志=1；B) 计数>0 时递增，超过 cal_u8RoleChangeDebounceTime 后清零标志并清零计数；C) 任一计数进行中时计数清零、标志=1；否则标志=0。由 Unit Delay / Sum / Relational Operator / Logical Operator / Switch 组合实现');

%% ---------- Save ----------
save_system(model, fullfile(outDir, [model '.slx']));
fprintf('Model saved to %s\n', fullfile(outDir, [model '.slx']));
close_system(model, 0);

%% ---------- Local helper functions ----------
function addConst(parent, name, value, dt, desc)
    p = [parent '/' name];
    add_block('simulink/Sources/Constant', p);
    set_param(p, 'Value', value, 'OutDataTypeStr', dt);
    if nargin >= 5 && ~isempty(desc)
        set_param(p, 'Description', desc);
    end
end

function addUD(parent, name, init, dt)
    p = [parent '/' name];
    add_block('simulink/Discrete/Unit Delay', p);
    set_param(p, 'InitialCondition', init, 'SampleTime', '0.01');
end

function addRelop(parent, name, op)
    p = [parent '/' name];
    add_block('simulink/Logic and Bit Operations/Relational Operator', p);
    set_param(p, 'Operator', op);
end

function addLogic(parent, name, op, nIn)
    p = [parent '/' name];
    add_block('simulink/Logic and Bit Operations/Logical Operator', p);
    set_param(p, 'Operator', op, 'Inputs', num2str(nIn));
end

function addSum(parent, name, signs, dt)
    p = [parent '/' name];
    add_block('simulink/Math Operations/Sum', p);
    set_param(p, 'Inputs', signs, 'OutDataTypeStr', dt);
end

function addSwitch(parent, name, dt)
    p = [parent '/' name];
    add_block('simulink/Signal Routing/Switch', p);
    set_param(p, 'Criteria', 'u2 ~= 0', 'OutDataTypeStr', dt);
end

function addDTC(parent, name, dt)
    p = [parent '/' name];
    add_block('simulink/Signal Attributes/Data Type Conversion', p);
    set_param(p, 'OutDataTypeStr', dt);
end

function addCounter(parent, stem, enBlock)
    addUD(parent, ['Delay_' stem], '0', 'uint32');
    addConst(parent, ['Const_One_' stem], '1', 'uint32');
    addConst(parent, ['Const_Zero_' stem], '0', 'uint32');
    addSum(parent, ['Sum_' stem], '++', 'uint32');
    addSwitch(parent, ['Sw_' stem], 'uint32');
    cl(parent, ['Delay_' stem], ['Sum_' stem]);
    cl2(parent, ['Const_One_' stem], ['Sum_' stem], 2);
    cl2(parent, ['Sum_' stem], ['Sw_' stem], 1);
    cl2(parent, enBlock, ['Sw_' stem], 2);
    cl2(parent, ['Const_Zero_' stem], ['Sw_' stem], 3);
    cl(parent, ['Sw_' stem], ['Delay_' stem]);
end

function w(parent, src, dst)
    add_line(parent, [src '/1'], [dst '/1'], 'autorouting', 'on');
end

function w2(parent, src, dst, dstPort)
    add_line(parent, [src '/1'], [dst '/' num2str(dstPort)], 'autorouting', 'on');
end

function cl(parent, src, dst)
    try
        add_line(parent, [src '/1'], [dst '/1'], 'autorouting', 'on');
    catch
        add_line(parent, [src '/1'], [dst '/1'], 'autorouting', 'on');
    end
end

function cl2(parent, src, dst, dstPort)
    try
        add_line(parent, [src '/1'], [dst '/' num2str(dstPort)], 'autorouting', 'on');
    catch
        add_line(parent, [src '/1'], [dst '/' num2str(dstPort)], 'autorouting', 'on');
    end
end
