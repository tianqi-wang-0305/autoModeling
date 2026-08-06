% Rebuild LRM_MLR_ManageLaneRole in EMB_LRM as a boolean-gated Stateflow
% chart: all comparisons/counters/guards computed in Simulink, only boolean
% conditions enter the chart; the chart only performs state transitions and
% outputs the role code.

model = 'EMB_LRM';
outDir = '/Users/wangtianqi/SimulinkModels/EMB_LRM';
load_system(fullfile(outDir, [model '.slx']));
ms = [model '/MainSubsystem'];
mlr = [ms '/LRM_MLR_ManageLaneRole'];

%% --- Clear current MLR internals ---
% First remove MainSubsystem lines that touch MLR ports
delLine(ms, 'SignalAcquisition/4', 'LRM_MLR_ManageLaneRole/1');
delLine(ms, 'SignalAcquisition/5', 'LRM_MLR_ManageLaneRole/2');
delLine(ms, 'SignalAcquisition/6', 'LRM_MLR_ManageLaneRole/3');
delLine(ms, 'SignalAcquisition/2', 'LRM_MLR_ManageLaneRole/4');
delLine(ms, 'SignalAcquisition/3', 'LRM_MLR_ManageLaneRole/5');
delLine(ms, 'LRM_MLS_ManageLaneStatus/1', 'LRM_MLR_ManageLaneRole/6');
delLine(ms, 'LRM_MLS_ManageLaneStatus/6', 'LRM_MLR_ManageLaneRole/7');
delLine(ms, 'LRM_MLR_ManageLaneRole/1', 'LRM_LSP_LaneSwitchInProgs/1');
delLine(ms, 'LRM_MLR_ManageLaneRole/3', 'LRM_LSP_LaneSwitchInProgs/2');
delLine(ms, 'LRM_MLR_ManageLaneRole/1', 'OutputArbitration/2');
delLine(ms, 'LRM_MLR_ManageLaneRole/2', 'Term_MLR_PrevRole/1');
delLine(ms, 'LRM_MLR_ManageLaneRole/4', 'Term_MLR_InitWait/1');
delLine(ms, 'LRM_MLR_ManageLaneRole/5', 'Term_MLR_MasterSwap/1');
delLine(ms, 'LRM_MLR_ManageLaneRole/6', 'Term_MLR_FbMasterTakeover/1');
delLine(ms, 'LRM_MLR_ManageLaneRole/7', 'Term_MLR_FbSupportSwap/1');
delLine(ms, 'LRM_MLR_ManageLaneRole/8', 'Term_MLR_SpMasterTakeover/1');

lh = get_param(mlr, 'LineHandles');
allLines = [lh.Inport(:); lh.Outport(:); lh.Enable(:); lh.Trigger(:); lh.Ifaction(:); lh.Reset(:)];
allLines = allLines(allLines ~= -1);
for i = 1:numel(allLines)
    delete_line(allLines(i));
end
inner = find_system(mlr, 'SearchDepth', 1, 'Type', 'block');
inner = inner(~strcmp(inner, mlr));
for i = 1:numel(inner)
    delete_block(inner{i});
end

%% --- Rebuild ports (same names/types/order as before) ---
inNames = {'u8LclFitnessScore','u8RmtFitnessScore','u8LclIlcStatus','u8LclLaneOperMode', ...
           'u8RmtLaneRole','u8LaneStatus','u32FailureMonitorCounter'};
inTypes = {'uint8','uint8','uint8','uint8','uint8','uint8','uint32'};
outNames = {'u8LaneRole','u8PrevLaneRole','bLaneRoleCntrInPrgs','u32InitWaitTimeCounter', ...
            'u32MasterFallbackSwapCntr','u32FallbackMasterTakeoverCntr', ...
            'u32FallbackSupportSwapCntr','u32SupportMasterTakeoverCntr'};
outTypes = {'uint8','uint8','boolean','uint32','uint32','uint32','uint32','uint32'};
for i = 1:numel(inNames)
    add_block('built-in/Inport', [mlr '/' inNames{i}]);
    set_param([mlr '/' inNames{i}], 'OutDataTypeStr', inTypes{i});
end
for i = 1:numel(outNames)
    add_block('built-in/Outport', [mlr '/' outNames{i}]);
    set_param([mlr '/' outNames{i}], 'OutDataTypeStr', outTypes{i});
end

%% --- Condition layer (Simulink, all boolean outputs) ---
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

addLogic(mlr, 'Logic_NotOperShutdown', 'NOT', 1); w(mlr, 'Relop_OperShutdown', 'Logic_NotOperShutdown');
addLogic(mlr, 'Logic_NotRmtMaster', 'NOT', 1);    w(mlr, 'Relop_RmtMaster', 'Logic_NotRmtMaster');
addLogic(mlr, 'Logic_NotIlcFailed', 'NOT', 1);    w(mlr, 'Relop_IlcFailed', 'Logic_NotIlcFailed');
addLogic(mlr, 'Logic_NotLclGtRmt', 'NOT', 1);     w(mlr, 'Relop_LclGtRmt', 'Logic_NotLclGtRmt');

%% --- Calibration constants and counters (Simulink) ---
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

%% --- Stateflow chart (boolean-gated, states only) ---
add_block('sflib/Chart', [mlr '/MLR_STM']);
rt = sfroot;
ch = find(rt, '-isa', 'Stateflow.Chart', 'Path', [mlr '/MLR_STM']);
if isempty(ch)
    error('Chart object not found');
end

inputNames = {'bOperShutdown','bLclDisabled','bLclGtRmt','bLclLtRmt','bRmtMaster', ...
              'bRmtFallback','bRmtDisabled','bRmtShutdown','bRmtUnknown','bIlcFailed', ...
              'bLaneStsFailed','bRmtScoreValid','bNotOperShutdown','bNotRmtMaster', ...
              'bNotIlcFailed','bExitInitMaster','bExitInitFallback','bMasterToSupport', ...
              'bMasterToFallbackImm','bMasterToFallbackCnt','bFbToMasterImm', ...
              'bFbToMasterTakeover','bFbToSupport','bFbToSupportFail','bSpToMasterTakeover', ...
              'bSpToFallback'};
for i = 1:numel(inputNames)
    d = Stateflow.Data(ch); d.Name = inputNames{i}; d.Scope = 'Input'; d.DataType = 'boolean';
end
o = Stateflow.Data(ch); o.Name = 'u8LaneRole'; o.Scope = 'Output'; o.DataType = 'uint8';
try
    o.Props.InitialValue = '1';
catch
end

sInit = addSFState(ch, 'INIT', 1);
sMaster = addSFState(ch, 'MASTER', 2);
sFallback = addSFState(ch, 'FALLBACK', 3);
sSupport = addSFState(ch, 'SUPPORT', 4);
sDisabled = addSFState(ch, 'DISABLED', 5);
sShutdown = addSFState(ch, 'SHUTTING_DOWN', 6);

td = Stateflow.Transition(ch); td.Source = []; td.Destination = sInit; td.LabelString = '';

% from-any-state: shutdown / disabled (creation order = priority)
allStates = {sInit, sMaster, sFallback, sSupport, sDisabled, sShutdown};
for i = 1:numel(allStates)
    addSFTrans(ch, allStates{i}, sShutdown, '[bOperShutdown]');
    addSFTrans(ch, allStates{i}, sDisabled, '[bLclDisabled]');
end
addSFTrans(ch, sShutdown, sInit, '[bNotOperShutdown]');

% INIT exits
addSFTrans(ch, sInit, sMaster, '[bExitInitMaster]');
addSFTrans(ch, sInit, sFallback, '[bExitInitFallback]');

% MASTER exits (priority: support > fallback immediate > fallback count)
addSFTrans(ch, sMaster, sSupport, '[bMasterToSupport]');
addSFTrans(ch, sMaster, sFallback, '[bMasterToFallbackImm]');
addSFTrans(ch, sMaster, sFallback, '[bMasterToFallbackCnt]');

% FALLBACK exits (priority: master immediate > master takeover > support > support fail)
addSFTrans(ch, sFallback, sMaster, '[bFbToMasterImm]');
addSFTrans(ch, sFallback, sMaster, '[bFbToMasterTakeover]');
addSFTrans(ch, sFallback, sSupport, '[bFbToSupport]');
addSFTrans(ch, sFallback, sSupport, '[bFbToSupportFail]');

% SUPPORT exits (priority: master immediate > master takeover > fallback)
addSFTrans(ch, sSupport, sMaster, '[bFbToMasterImm]');
addSFTrans(ch, sSupport, sMaster, '[bSpToMasterTakeover]');
addSFTrans(ch, sSupport, sFallback, '[bSpToFallback]');

% State equality from chart output (u8LaneRole)
addConst(mlr, 'Const_StateInit', '1', 'uint8');
addConst(mlr, 'Const_StateMaster', '2', 'uint8');
addConst(mlr, 'Const_StateFallback', '3', 'uint8');
addConst(mlr, 'Const_StateSupport', '4', 'uint8');
addRelop(mlr, 'Relop_StateInit', '==');     w2(mlr, 'MLR_STM', 'Relop_StateInit', 1);     w2(mlr, 'Const_StateInit', 'Relop_StateInit', 2);
addRelop(mlr, 'Relop_StateMaster', '==');   w2(mlr, 'MLR_STM', 'Relop_StateMaster', 1);   w2(mlr, 'Const_StateMaster', 'Relop_StateMaster', 2);
addRelop(mlr, 'Relop_StateFallback', '=='); w2(mlr, 'MLR_STM', 'Relop_StateFallback', 1); w2(mlr, 'Const_StateFallback', 'Relop_StateFallback', 2);
addRelop(mlr, 'Relop_StateSupport', '==');  w2(mlr, 'MLR_STM', 'Relop_StateSupport', 1);  w2(mlr, 'Const_StateSupport', 'Relop_StateSupport', 2);

% Counters (enable = state + condition, threshold booleans out)
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

addRelop(mlr, 'Relop_InitWaitReady', '>=');        w2(mlr, 'Delay_InitWait', 'Relop_InitWaitReady', 1);         w2(mlr, 'DTC_InitWaitThd', 'Relop_InitWaitReady', 2);
addRelop(mlr, 'Relop_MasterSwapExpired', '>');     w2(mlr, 'Delay_MasterSwap', 'Relop_MasterSwapExpired', 1);   w2(mlr, 'DTC_MasterSwapThd', 'Relop_MasterSwapExpired', 2);
addRelop(mlr, 'Relop_FbMasterTakeoverExpired', '>'); w2(mlr, 'Delay_FbMasterTakeover', 'Relop_FbMasterTakeoverExpired', 1); w2(mlr, 'DTC_TakeoverThd', 'Relop_FbMasterTakeoverExpired', 2);
addRelop(mlr, 'Relop_FbSupportSwapExpired', '>');  w2(mlr, 'Delay_FbSupportSwap', 'Relop_FbSupportSwapExpired', 1); w2(mlr, 'DTC_FbSpSwapThd', 'Relop_FbSupportSwapExpired', 2);
addRelop(mlr, 'Relop_SpMasterTakeoverExpired', '>'); w2(mlr, 'Delay_SpMasterTakeover', 'Relop_SpMasterTakeoverExpired', 1); w2(mlr, 'DTC_TakeoverThd', 'Relop_SpMasterTakeoverExpired', 2);
addRelop(mlr, 'Relop_FbFailWindowExpired', '>');   w2(mlr, 'u32FailureMonitorCounter', 'Relop_FbFailWindowExpired', 1); w2(mlr, 'DTC_FailWatch', 'Relop_FbFailWindowExpired', 2);

%% --- Guard combination logic (Simulink, boolean) ---
addLogic(mlr, 'Logic_ExitInitMaster', 'AND', 2);
w2(mlr, 'Relop_InitWaitReady', 'Logic_ExitInitMaster', 1);
w2(mlr, 'Relop_LclGtRmt', 'Logic_ExitInitMaster', 2);
addLogic(mlr, 'Logic_InitReadyNotGt', 'AND', 2);
w2(mlr, 'Relop_InitWaitReady', 'Logic_InitReadyNotGt', 1);
w2(mlr, 'Logic_NotLclGtRmt', 'Logic_InitReadyNotGt', 2);
addLogic(mlr, 'Logic_ExitInitFallback', 'OR', 2);
w2(mlr, 'Logic_InitReadyNotGt', 'Logic_ExitInitFallback', 1);
w2(mlr, 'Relop_RmtMaster', 'Logic_ExitInitFallback', 2);

addLogic(mlr, 'Logic_MasterToSupport', 'AND', 3);
w2(mlr, 'Relop_IlcFailed', 'Logic_MasterToSupport', 1);
w2(mlr, 'Relop_RmtScoreValid', 'Logic_MasterToSupport', 2);
w2(mlr, 'Relop_LclLtRmt', 'Logic_MasterToSupport', 3);
addLogic(mlr, 'Logic_MasterToFallbackImm', 'AND', 2);
w2(mlr, 'Relop_LclLtRmt', 'Logic_MasterToFallbackImm', 1);
w2(mlr, 'Relop_RmtMaster', 'Logic_MasterToFallbackImm', 2);
addLogic(mlr, 'Logic_MasterToFallbackCnt', 'AND', 3);
w2(mlr, 'Relop_LclLtRmt', 'Logic_MasterToFallbackCnt', 1);
w2(mlr, 'Relop_RmtFallback', 'Logic_MasterToFallbackCnt', 2);
w2(mlr, 'Relop_MasterSwapExpired', 'Logic_MasterToFallbackCnt', 3);

addLogic(mlr, 'Logic_FbToMasterImm', 'OR', 3);
w2(mlr, 'Relop_LaneStsFailed', 'Logic_FbToMasterImm', 1);
w2(mlr, 'Relop_RmtDisabled', 'Logic_FbToMasterImm', 2);
w2(mlr, 'Relop_RmtShutdown', 'Logic_FbToMasterImm', 3);
addLogic(mlr, 'Logic_FbToMasterTakeover', 'AND', 3);
w2(mlr, 'Relop_LclGtRmt', 'Logic_FbToMasterTakeover', 1);
w2(mlr, 'Relop_FbMasterTakeoverExpired', 'Logic_FbToMasterTakeover', 2);
w2(mlr, 'Logic_NotRmtMaster', 'Logic_FbToMasterTakeover', 3);
addLogic(mlr, 'Logic_FbToSupport', 'AND', 2);
w2(mlr, 'Relop_LclLtRmt', 'Logic_FbToSupport', 1);
w2(mlr, 'Relop_FbSupportSwapExpired', 'Logic_FbToSupport', 2);
addLogic(mlr, 'Logic_FbToSupportFail', 'AND', 2);
w2(mlr, 'Relop_RmtUnknown', 'Logic_FbToSupportFail', 1);
w2(mlr, 'Relop_FbFailWindowExpired', 'Logic_FbToSupportFail', 2);

addLogic(mlr, 'Logic_SpToMasterTakeover', 'AND', 3);
w2(mlr, 'Relop_LclGtRmt', 'Logic_SpToMasterTakeover', 1);
w2(mlr, 'Relop_SpMasterTakeoverExpired', 'Logic_SpToMasterTakeover', 2);
w2(mlr, 'Logic_NotRmtMaster', 'Logic_SpToMasterTakeover', 3);
addLogic(mlr, 'Logic_SpToFallback', 'AND', 2);
w2(mlr, 'Logic_NotIlcFailed', 'Logic_SpToFallback', 1);
w2(mlr, 'Relop_RmtMaster', 'Logic_SpToFallback', 2);

%% --- Wire chart inputs (boolean conditions) ---
srcMap = containers.Map(inputNames, { ...
    'Relop_OperShutdown','Relop_LclDisabled','Relop_LclGtRmt','Relop_LclLtRmt','Relop_RmtMaster', ...
    'Relop_RmtFallback','Relop_RmtDisabled','Relop_RmtShutdown','Relop_RmtUnknown','Relop_IlcFailed', ...
    'Relop_LaneStsFailed','Relop_RmtScoreValid','Logic_NotOperShutdown','Logic_NotRmtMaster', ...
    'Logic_NotIlcFailed','Logic_ExitInitMaster','Logic_ExitInitFallback','Logic_MasterToSupport', ...
    'Logic_MasterToFallbackImm','Logic_MasterToFallbackCnt','Logic_FbToMasterImm', ...
    'Logic_FbToMasterTakeover','Logic_FbToSupport','Logic_FbToSupportFail','Logic_SpToMasterTakeover', ...
    'Logic_SpToFallback'});
for i = 1:numel(inputNames)
    add_line(mlr, [srcMap(inputNames{i}) '/1'], ['MLR_STM/' num2str(i)], 'autorouting', 'on');
end

%% --- Wire outputs ---
w(mlr, 'MLR_STM', 'u8LaneRole');
addUD(mlr, 'Delay_PrevRole', '1', 'uint8');
w(mlr, 'MLR_STM', 'Delay_PrevRole');
w(mlr, 'Delay_PrevRole', 'u8PrevLaneRole');
w(mlr, 'Relop_StateInit', 'bLaneRoleCntrInPrgs');
w(mlr, 'Delay_InitWait', 'u32InitWaitTimeCounter');
w(mlr, 'Delay_MasterSwap', 'u32MasterFallbackSwapCntr');
w(mlr, 'Delay_FbMasterTakeover', 'u32FallbackMasterTakeoverCntr');
w(mlr, 'Delay_FbSupportSwap', 'u32FallbackSupportSwapCntr');
w(mlr, 'Delay_SpMasterTakeover', 'u32SupportMasterTakeoverCntr');

%% --- Re-wire MainSubsystem MLR connections ---
add_line(ms, 'SignalAcquisition/4', 'LRM_MLR_ManageLaneRole/1', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/5', 'LRM_MLR_ManageLaneRole/2', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/6', 'LRM_MLR_ManageLaneRole/3', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/2', 'LRM_MLR_ManageLaneRole/4', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/3', 'LRM_MLR_ManageLaneRole/5', 'autorouting', 'on');
add_line(ms, 'LRM_MLS_ManageLaneStatus/1', 'LRM_MLR_ManageLaneRole/6', 'autorouting', 'on');
add_line(ms, 'LRM_MLS_ManageLaneStatus/6', 'LRM_MLR_ManageLaneRole/7', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/1', 'LRM_LSP_LaneSwitchInProgs/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/3', 'LRM_LSP_LaneSwitchInProgs/2', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/1', 'OutputArbitration/2', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/2', 'Term_MLR_PrevRole/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/4', 'Term_MLR_InitWait/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/5', 'Term_MLR_MasterSwap/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/6', 'Term_MLR_FbMasterTakeover/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/7', 'Term_MLR_FbSupportSwap/1', 'autorouting', 'on');
add_line(ms, 'LRM_MLR_ManageLaneRole/8', 'Term_MLR_SpMasterTakeover/1', 'autorouting', 'on');

%% --- Description ---
set_param(mlr, 'Description', ...
    '基于健康度得分、ILC 状态、远链路角色与控制链路状态仲裁本链路角色 LaneRole。状态机采用 boolean 门控 Stateflow 模式：全部比较/计数/条件组合在 Simulink 内完成（Relational Operator、Unit Delay+Sum+Switch 计数器、Logical Operator），Chart(MLR_STM) 仅接收 boolean 条件（bOperShutdown/bLclDisabled/bExitInitMaster/bFbToMasterImm 等 26 路）并执行 6 状态（INIT/MASTER/FALLBACK/SUPPORT/DISABLED/SHUTTING_DOWN）转移，输出 u8LaneRole 状态编码；prevLaneRole、LaneRoleCntrInPrgs、各切换/接管计数器在 Simulink 由状态输出派生');
set_param([mlr '/MLR_STM'], 'Description', ...
    'MLR 角色仲裁状态机（boolean 门控 Stateflow）：26 路 boolean 条件输入，6 状态（INIT/MASTER/FALLBACK/SUPPORT/DISABLED/SHUTTING_DOWN）转移，输出 u8LaneRole 状态编码；全部逻辑判断在 Simulink 侧完成');

save_system(model, fullfile(outDir, [model '.slx']));
fprintf('MLR Stateflow version saved to %s\n', fullfile(outDir, [model '.slx']));
close_system(model, 0);

%% ---------- Local helper functions ----------
function s = addSFState(ch, name, code)
    s = Stateflow.State(ch);
    s.Name = name;
    s.LabelString = sprintf('%s\nen: u8LaneRole = %d;', name, code);
end

function addSFTrans(ch, src, dst, guard)
    t = Stateflow.Transition(ch);
    t.Source = src;
    t.Destination = dst;
    t.LabelString = guard;
end

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

function delLine(parent, src, dst)
    try
        delete_line(parent, src, dst);
    catch
    end
end
