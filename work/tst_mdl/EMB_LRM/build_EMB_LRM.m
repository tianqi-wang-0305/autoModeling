function build_EMB_LRM()
% build_EMB_LRM  Build EMB_LRM (Lane Role Manager) Simulink model from
%   EMB_Software_ReqSpec.docx requirements.
%
%   命名规范（与参考模型 Foc_2024b 一致）：
%     - 顶层 Inport/Outport:        {type}{Name}（如 u8OperMode）
%     - 子系统内部 Inport/Outport:  用真实信号名命名（便于跨层级追溯）
%     - 跨层级连线:                 子系统输入用位置号 (SS/1), 输出用 SS/OutN
%
%   Run:  build_EMB_LRM   (MATLAB, needs Simulink)

    modelName = 'EMB_LRM';
    outDir = fileparts(mfilename('fullpath'));
    if isempty(outDir), outDir = pwd; end

    % ============ 信号定义（唯一事实来源）============
    inNames = {'u8OperMode','u8LclIlcStatus','bIlcStsQf','u8HeartbeatLost', ...
               'u8LclFitness','u8RmtFitness','u8RmtLaneRole','u8LclLaneOperMode'};
    outNames = {'u8LaneRole','u8LaneStatus','bLaneSwtgInProgs','bActvCtrlr','u8RmtLaneSts'};

    fprintf('=== Building %s from requirements ===\n', modelName);
    % 强制关闭并清理旧模型
    if bdIsLoaded(modelName)
        try, close_system(modelName, 0); catch, end
    end
    slxFile = fullfile(outDir, [modelName '.slx']);
    if exist(slxFile, 'file'), delete(slxFile); end

    new_system(modelName);
    set_param(modelName, 'Solver', 'FixedStepDiscrete');
    set_param(modelName, 'FixedStep', '0.01');
    set_param(modelName, 'StopTime', '100');

    %% ============ Phase 1: Root Inports/Outports ============
    addRootInports(modelName);
    addRootOutports(modelName);

    %% ============ Phase 2: MainSubsystem wrapper + children ============
    main = [modelName '/MainSubsystem'];
    add_block('built-in/SubSystem', main);
    set_param(main, 'Description', '主功能包装层：信号调理 → 功能模块 → 输出仲裁');

    subs = {'SignalAcquisition', 'LRM_MLS_ManageLaneStatus', ...
            'LRM_MLR_ManageLaneRole', 'LRM_LSP_LaneSwitchInProgs', ...
            'LRM_LSD_LaneStatusDig', 'LRM_LRD_LaneRoleDig', 'OutputArbitration'};
    for k = 1:numel(subs)
        add_block('built-in/SubSystem', [main '/' subs{k}]);
    end

    % MainSubsystem 内部端口用真实信号名（与顶层一致）
    addNamedInports(main, inNames);
    addNamedOutports(main, outNames);

    %% ============ Phase 3: Wire root -> MainSubsystem ============
    % 根 Inport -> MainSubsystem 位置输入 (SS/1..8)
    for i = 1:numel(inNames)
        add_line(modelName, [inNames{i} '/1'], ['MainSubsystem/' num2str(i)], 'autorouting', 'on');
    end
    % MainSubsystem 位置输出 (SS/Out1..5) -> 根 Outport
    for i = 1:numel(outNames)
        add_line(modelName, ['MainSubsystem/Out' num2str(i)], [outNames{i} '/1'], 'autorouting', 'on');
    end

    %% ============ Phase 4: Populate each subsystem ============
    populateSignalAcquisition([main '/SignalAcquisition'], inNames);
    populateManageLaneStatus([main '/LRM_MLS_ManageLaneStatus']);
    populateManageLaneRole([main '/LRM_MLR_ManageLaneRole']);
    populateLaneSwitch([main '/LRM_LSP_LaneSwitchInProgs']);
    populateLaneStatusDig([main '/LRM_LSD_LaneStatusDig']);
    populateLaneRoleDig([main '/LRM_LRD_LaneRoleDig']);
    populateOutputArbitration([main '/OutputArbitration'], outNames);

    %% ============ Phase 5: Wire MainSubsystem internals ============
    wireMainInternals(main, inNames, outNames);

    %% ============ Phase 6: Save + verify ============
    save_system(modelName, slxFile);
    fprintf('=== Saved: %s ===\n', slxFile);

    % Auto layout
    try
        addpath(fullfile(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))), 'scripts', 'layout_gen', 'src'));
        if exist('autoLayoutModel', 'file')
            autoLayoutModel(modelName);
            fprintf('=== Auto-layout complete ===\n');
        end
    catch ME
        fprintf('Layout skipped: %s\n', ME.message);
    end

    % model_check
    try
        tk = fullfile(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))), 'simulink-agentic-toolkit', 'tools');
        addpath(genpath(tk));
        if exist('model_check', 'file')
            chk = model_check(modelName, 'root', '["all"]');
            fprintf('=== model_check result ===\n');
            disp(chk);
        end
    catch ME
        fprintf('model_check skipped: %s\n', ME.message);
    end
    fprintf('=== DONE ===\n');
end

%% =====================================================================
function addRootInports(m)
    defs = {
        'u8OperMode',       'uint8',  '0', '5', '系统运行模式: 0=INIT,1=NORMAL_OPERATION,2=LIMP_HOME,3=LIMP_ASIDE,4=CRAWL,5=SHUTTING_DOWN'
        'u8LclIlcStatus',   'uint8',  '0', '2', '本控制链路ILC状态: 0=Failed,1=Normal,2=Initialized'
        'bIlcStsQf',        'boolean','0', '1', 'ILC状态信号质量: 0=QF_Full,1=QF_NotFull'
        'u8HeartbeatLost',  'uint8',  '0', '255','心跳丢失计数'
        'u8LclFitness',     'uint8',  '0', '255','本控制链路健康度得分(62=禁用,255=无效)'
        'u8RmtFitness',     'uint8',  '0', '255','远控制链路健康度得分(62=禁用,255=无效)'
        'u8RmtLaneRole',    'uint8',  '0', '5', '远控制链路角色: 0=INIT,1=MASTER,2=FALLBACK,3=SUPPORT,4=DISABLED,5=SHUTTING_DOWN'
        'u8LclLaneOperMode','uint8',  '0', '5', '本控制链路运行模式: 0=INIT,1=NORMAL_OPERATION,2=LIMP_HOME,3=LIMP_ASIDE,4=CRAWL,5=SHUTTING_DOWN'
    };
    for i = 1:size(defs,1)
        nm = [m '/' defs{i,1}];
        add_block('built-in/Inport', nm);
        set_param(nm, 'OutDataTypeStr', defs{i,2});
        set_param(nm, 'OutMin', defs{i,3});
        set_param(nm, 'OutMax', defs{i,4});
        set_param(nm, 'Description', defs{i,5});
    end
end

function addRootOutports(m)
    defs = {
        'u8LaneRole',      'uint8',  '0', '6', '本控制链路角色: 0=UNKNOWN,1=INIT,2=MASTER,3=FALLBACK,4=SUPPORT,5=DISABLED,6=SHUTTING_DOWN'
        'u8LaneStatus',    'uint8',  '0', '3', '控制链路状态: 0=INITIALISING,1=OPERATING,2=HB_LOST,3=FAILED'
        'bLaneSwtgInProgs','boolean','0', '1', '控制链路切换进行中: 0=NotProgress,1=Progress'
        'bActvCtrlr',      'boolean','0', '1', '活动控制器实例: 0=NotActive,1=Active'
        'u8RmtLaneSts',    'uint8',  '0', '3', '远控制链路状态: 0=INITIALISING,1=OPERATING,2=HB_LOST,3=FAILED'
    };
    for i = 1:size(defs,1)
        nm = [m '/' defs{i,1}];
        add_block('built-in/Outport', nm);
        set_param(nm, 'OutDataTypeStr', defs{i,2});
        set_param(nm, 'OutMin', defs{i,3});
        set_param(nm, 'OutMax', defs{i,4});
        set_param(nm, 'Description', defs{i,5});
    end
end

%% =====================================================================
function addNamedInports(scope, names)
    for i = 1:numel(names)
        add_block('built-in/Inport', [scope '/' names{i}]);
    end
end

function addNamedOutports(scope, names)
    for i = 1:numel(names)
        add_block('built-in/Outport', [scope '/' names{i}]);
    end
end

%% =====================================================================
function populateSignalAcquisition(scope, inNames)
% N 路 1:1 直通 + DataTypeConversion。输入端口名 = 信号名。
% 同 scope 内 In/Out 不能同名 → 输出端口名加 _Out 后缀
    addNamedInports(scope, inNames);
    outNames = cellfun(@(n) [n '_Out'], inNames, 'UniformOutput', false);
    addNamedOutports(scope, outNames);
    for i = 1:numel(inNames)
        conv = [scope '/DTC_' inNames{i}];
        add_block('built-in/DataTypeConversion', conv);
        set_param(conv, 'OutDataTypeStr', 'Inherit: Inherit via back propagation');
        add_line(scope, [inNames{i} '/1'], ['DTC_' inNames{i} '/1'], 'autorouting', 'on');
        add_line(scope, ['DTC_' inNames{i} '/1'], [outNames{i} '/1'], 'autorouting', 'on');
    end
end

%% =====================================================================
function populateManageLaneStatus(scope)
% 输入: u8LclIlcStatus, bIlcStsQf, u8HeartbeatLost, u8OperMode
% 输出: u8LaneStatus, bLaneStatusCntrInPrgs
    addNamedInports(scope, {'u8LclIlcStatus','bIlcStsQf','u8HeartbeatLost','u8OperMode'});
    addNamedOutports(scope, {'u8LaneStatus','bLaneStatusCntrInPrgs'});
    blk = @(b) [scope '/' b];

    % HB_Failure = (HB - delay(HB) == 0) → counter 未变化=故障
    add_block('built-in/UnitDelay', blk('UD_HB'), 'Position', [200 60 240 100]);
    add_block('built-in/Sum', blk('S_HbDiff'), 'Position', [300 60 340 100]);
    set_param(blk('S_HbDiff'), 'Inputs', '+-');
    add_block('built-in/RelationalOperator', blk('R_HbStuck'), 'Position', [400 60 460 100]);
    set_param(blk('R_HbStuck'), 'Operator', '==');
    add_block('built-in/Constant', blk('C_Zero'), 'Value', 'uint8(0)', 'Position', [360 140 410 170]);
    % HB monitor counter
    add_block('built-in/UnitDelay', blk('UD_HbCnt'), 'Position', [500 40 540 80]);
    add_block('built-in/Sum', blk('S_HbCnt'), 'Position', [420 40 460 80]);
    set_param(blk('S_HbCnt'), 'Inputs', '++');
    add_block('built-in/Constant', blk('C_One'), 'Value', 'uint8(1)', 'Position', [360 10 400 40]);
    add_block('built-in/Switch', blk('Sw_HbCnt'), 'Position', [560 20 610 100]);
    set_param(blk('Sw_HbCnt'), 'Criteria', 'u2 ~= 0');

    % ILC quality monitor counter
    add_block('built-in/UnitDelay', blk('UD_IlcCnt'), 'Position', [500 220 540 260]);
    add_block('built-in/Sum', blk('S_IlcCnt'), 'Position', [420 220 460 260]);
    set_param(blk('S_IlcCnt'), 'Inputs', '++');
    add_block('built-in/Switch', blk('Sw_IlcCnt'), 'Position', [560 200 610 280]);
    set_param(blk('Sw_IlcCnt'), 'Criteria', 'u2 ~= 0');

    % OperMode: 未用于简化逻辑 → Terminator
    add_block('built-in/Terminator', blk('Term_OperMode'));

    % LaneStatus 选择
    add_block('built-in/RelationalOperator', blk('R_HbThd'), 'Position', [650 40 710 80]);
    set_param(blk('R_HbThd'), 'Operator', '>=');
    add_block('built-in/Constant', blk('C_Thd'), 'Value', 'uint8(20)', 'Position', [600 90 640 120]);
    add_block('built-in/Constant', blk('C_HbLost'), 'Value', 'uint8(2)', 'Position', [720 10 760 40]);
    add_block('built-in/Constant', blk('C_Operating'), 'Value', 'uint8(1)', 'Position', [720 130 760 160]);
    add_block('built-in/Constant', blk('C_Failed'), 'Value', 'uint8(3)', 'Position', [720 250 760 280]);
    add_block('built-in/Constant', blk('C_Init'), 'Value', 'uint8(0)', 'Position', [720 320 760 350]);
    add_block('built-in/Switch', blk('Sw_HbLost'), 'Position', [800 20 860 120]);
    set_param(blk('Sw_HbLost'), 'Criteria', 'u2 ~= 0');
    add_block('built-in/Switch', blk('Sw_Op'), 'Position', [800 150 860 210]);
    set_param(blk('Sw_Op'), 'Criteria', 'u2 ~= 0');
    add_block('built-in/Switch', blk('Sw_Failed'), 'Position', [800 270 860 340]);
    set_param(blk('Sw_Failed'), 'Criteria', 'u2 ~= 0');

    % bLaneStatusCntrInPrgs = LaneStatus != Operating
    add_block('built-in/RelationalOperator', blk('R_NotOp'), 'Position', [880 150 940 190]);
    set_param(blk('R_NotOp'), 'Operator', '~=');
    add_block('built-in/Constant', blk('C_OpVal'), 'Value', 'uint8(1)', 'Position', [860 200 900 230]);
    add_block('built-in/DataTypeConversion', blk('DTC_Bool'), 'Position', [960 150 1010 190]);
    set_param(blk('DTC_Bool'), 'OutDataTypeStr', 'boolean');

    %% Wiring（内部用信号名）
    % HB_Failure
    add_line(scope, 'u8HeartbeatLost/1', 'UD_HB/1', 'autorouting','on');
    add_line(scope, 'UD_HB/1', 'S_HbDiff/2', 'autorouting','on');
    add_line(scope, 'u8HeartbeatLost/1', 'S_HbDiff/1', 'autorouting','on');
    add_line(scope, 'S_HbDiff/1', 'R_HbStuck/1', 'autorouting','on');
    add_line(scope, 'C_Zero/1', 'R_HbStuck/2', 'autorouting','on');
    % HB counter
    add_line(scope, 'R_HbStuck/1', 'Sw_HbCnt/2', 'autorouting','on');
    add_line(scope, 'S_HbCnt/1', 'Sw_HbCnt/1', 'autorouting','on');
    add_line(scope, 'UD_HbCnt/1', 'S_HbCnt/1', 'autorouting','on');
    add_line(scope, 'C_One/1', 'S_HbCnt/2', 'autorouting','on');
    add_line(scope, 'C_Zero/1', 'Sw_HbCnt/3', 'autorouting','on');
    add_line(scope, 'Sw_HbCnt/1', 'UD_HbCnt/1', 'autorouting','on');
    % ILC counter
    add_line(scope, 'bIlcStsQf/1', 'Sw_IlcCnt/2', 'autorouting','on');
    add_line(scope, 'S_IlcCnt/1', 'Sw_IlcCnt/1', 'autorouting','on');
    add_line(scope, 'UD_IlcCnt/1', 'S_IlcCnt/1', 'autorouting','on');
    add_line(scope, 'C_One/1', 'S_IlcCnt/2', 'autorouting','on');
    add_line(scope, 'C_Zero/1', 'Sw_IlcCnt/3', 'autorouting','on');
    add_line(scope, 'Sw_IlcCnt/1', 'UD_IlcCnt/1', 'autorouting','on');
    % OperMode → Term
    add_line(scope, 'u8OperMode/1', 'Term_OperMode/1', 'autorouting','on');
    % HbLost 条件
    add_line(scope, 'UD_HbCnt/1', 'R_HbThd/1', 'autorouting','on');
    add_line(scope, 'C_Thd/1', 'R_HbThd/2', 'autorouting','on');
    % Switch chain
    add_line(scope, 'R_HbThd/1', 'Sw_HbLost/2', 'autorouting','on');
    add_line(scope, 'C_HbLost/1', 'Sw_HbLost/1', 'autorouting','on');
    add_line(scope, 'C_Operating/1', 'Sw_HbLost/3', 'autorouting','on');
    add_line(scope, 'Sw_HbLost/1', 'Sw_Op/3', 'autorouting','on');
    add_line(scope, 'u8LclIlcStatus/1', 'Sw_Op/2', 'autorouting','on');
    add_line(scope, 'C_Failed/1', 'Sw_Failed/1', 'autorouting','on');
    add_line(scope, 'C_Init/1', 'Sw_Failed/3', 'autorouting','on');
    add_line(scope, 'u8LclIlcStatus/1', 'Sw_Failed/2', 'autorouting','on');
    add_line(scope, 'Sw_Failed/1', 'Sw_Op/1', 'autorouting','on');
    add_line(scope, 'Sw_Op/1', 'u8LaneStatus/1', 'autorouting','on');
    % bLaneStatusCntrInPrgs
    add_line(scope, 'Sw_Op/1', 'R_NotOp/1', 'autorouting','on');
    add_line(scope, 'C_OpVal/1', 'R_NotOp/2', 'autorouting','on');
    add_line(scope, 'R_NotOp/1', 'DTC_Bool/1', 'autorouting','on');
    add_line(scope, 'DTC_Bool/1', 'bLaneStatusCntrInPrgs/1', 'autorouting','on');
end

%% =====================================================================
function populateManageLaneRole(scope)
% 输入: u8LclFitness, u8RmtFitness, u8LclIlcStatus, u8LclLaneOperMode, u8RmtLaneRole, u8LaneStatus
% 输出: u8LaneRole, bLaneRoleCntrInPrgs
    addNamedInports(scope, {'u8LclFitness','u8RmtFitness','u8LclIlcStatus','u8LclLaneOperMode','u8RmtLaneRole','u8LaneStatus'});
    addNamedOutports(scope, {'u8LaneRole','bLaneRoleCntrInPrgs'});
    blk = @(b) [scope '/' b];

    % Disabled: LclFitness == 62
    add_block('built-in/RelationalOperator', blk('R_Disabled'), 'Position', [300 40 360 80]);
    set_param(blk('R_Disabled'), 'Operator', '==');
    add_block('built-in/Constant', blk('C_DisVal'), 'Value', 'uint8(62)', 'Position', [250 90 290 120]);
    % ShuttingDown: OperMode == 5
    add_block('built-in/RelationalOperator', blk('R_Shut'), 'Position', [300 140 360 180]);
    set_param(blk('R_Shut'), 'Operator', '==');
    add_block('built-in/Constant', blk('C_ShutVal'), 'Value', 'uint8(5)', 'Position', [250 190 290 220]);
    % Master: LclFitness > RmtFitness
    add_block('built-in/RelationalOperator', blk('R_Master'), 'Position', [300 240 360 280]);
    set_param(blk('R_Master'), 'Operator', '>');
    % Fallback: LclFitness < RmtFitness
    add_block('built-in/RelationalOperator', blk('R_Fallback'), 'Position', [300 340 360 380]);
    set_param(blk('R_Fallback'), 'Operator', '<');
    % Support: ILC Failed (u8LclIlcStatus == 0)
    add_block('built-in/RelationalOperator', blk('R_Support'), 'Position', [300 440 360 480]);
    set_param(blk('R_Support'), 'Operator', '==');
    add_block('built-in/Constant', blk('C_IlcFail'), 'Value', 'uint8(0)', 'Position', [250 490 290 520]);

    % Role 常量
    add_block('built-in/Constant', blk('C_Master'), 'Value', 'uint8(2)', 'Position', [400 240 440 270]);
    add_block('built-in/Constant', blk('C_Fallback'), 'Value', 'uint8(3)', 'Position', [400 340 440 370]);
    add_block('built-in/Constant', blk('C_Support'), 'Value', 'uint8(4)', 'Position', [400 440 440 470]);
    add_block('built-in/Constant', blk('C_Disabled'), 'Value', 'uint8(5)', 'Position', [400 40 440 70]);
    add_block('built-in/Constant', blk('C_Shutting'), 'Value', 'uint8(6)', 'Position', [400 140 440 170]);
    add_block('built-in/Constant', blk('C_Init'), 'Value', 'uint8(1)', 'Position', [400 540 440 570]);
    % 未用输入 → Terminator
    add_block('built-in/Terminator', blk('Term_RmtRole'));
    add_block('built-in/Terminator', blk('Term_LaneSts'));

    % Switch 级联
    add_block('built-in/Switch', blk('Sw_Dis'), 'Position', [500 30 560 100]);
    set_param(blk('Sw_Dis'), 'Criteria', 'u2 ~= 0');
    add_block('built-in/Switch', blk('Sw_Shut'), 'Position', [580 120 640 190]);
    set_param(blk('Sw_Shut'), 'Criteria', 'u2 ~= 0');
    add_block('built-in/Switch', blk('Sw_Master'), 'Position', [660 220 720 300]);
    set_param(blk('Sw_Master'), 'Criteria', 'u2 ~= 0');
    add_block('built-in/Switch', blk('Sw_Fb'), 'Position', [740 320 800 400]);
    set_param(blk('Sw_Fb'), 'Criteria', 'u2 ~= 0');
    add_block('built-in/Switch', blk('Sw_Supp'), 'Position', [820 420 880 500]);
    set_param(blk('Sw_Supp'), 'Criteria', 'u2 ~= 0');

    % bLaneRoleCntrInPrgs: Role != Master(2)
    add_block('built-in/RelationalOperator', blk('R_NotMaster'), 'Position', [900 420 960 460]);
    set_param(blk('R_NotMaster'), 'Operator', '~=');
    add_block('built-in/Constant', blk('C_MasterVal'), 'Value', 'uint8(2)', 'Position', [880 470 920 500]);
    add_block('built-in/DataTypeConversion', blk('DTC_Bool'), 'Position', [980 420 1030 460]);
    set_param(blk('DTC_Bool'), 'OutDataTypeStr', 'boolean');

    %% Wiring（内部用信号名）
    add_line(scope, 'u8LclFitness/1', 'R_Disabled/1', 'autorouting','on');
    add_line(scope, 'C_DisVal/1', 'R_Disabled/2', 'autorouting','on');
    add_line(scope, 'u8LclLaneOperMode/1', 'R_Shut/1', 'autorouting','on');
    add_line(scope, 'C_ShutVal/1', 'R_Shut/2', 'autorouting','on');
    add_line(scope, 'u8LclFitness/1', 'R_Master/1', 'autorouting','on');
    add_line(scope, 'u8RmtFitness/1', 'R_Master/2', 'autorouting','on');
    add_line(scope, 'u8LclFitness/1', 'R_Fallback/1', 'autorouting','on');
    add_line(scope, 'u8RmtFitness/1', 'R_Fallback/2', 'autorouting','on');
    add_line(scope, 'u8LclIlcStatus/1', 'R_Support/1', 'autorouting','on');
    add_line(scope, 'C_IlcFail/1', 'R_Support/2', 'autorouting','on');
    % Switch u1/u2/u3
    add_line(scope, 'C_Disabled/1', 'Sw_Dis/1', 'autorouting','on');
    add_line(scope, 'R_Disabled/1', 'Sw_Dis/2', 'autorouting','on');
    add_line(scope, 'C_Shutting/1', 'Sw_Shut/1', 'autorouting','on');
    add_line(scope, 'R_Shut/1', 'Sw_Shut/2', 'autorouting','on');
    add_line(scope, 'C_Master/1', 'Sw_Master/1', 'autorouting','on');
    add_line(scope, 'R_Master/1', 'Sw_Master/2', 'autorouting','on');
    add_line(scope, 'C_Fallback/1', 'Sw_Fb/1', 'autorouting','on');
    add_line(scope, 'R_Fallback/1', 'Sw_Fb/2', 'autorouting','on');
    add_line(scope, 'C_Support/1', 'Sw_Supp/1', 'autorouting','on');
    add_line(scope, 'R_Support/1', 'Sw_Supp/2', 'autorouting','on');
    add_line(scope, 'C_Init/1', 'Sw_Supp/3', 'autorouting','on');
    % 级联
    add_line(scope, 'Sw_Supp/1', 'Sw_Fb/3', 'autorouting','on');
    add_line(scope, 'Sw_Fb/1', 'Sw_Master/3', 'autorouting','on');
    add_line(scope, 'Sw_Master/1', 'Sw_Shut/3', 'autorouting','on');
    add_line(scope, 'Sw_Shut/1', 'Sw_Dis/3', 'autorouting','on');
    add_line(scope, 'Sw_Dis/1', 'u8LaneRole/1', 'autorouting','on');
    % bLaneRoleCntrInPrgs
    add_line(scope, 'Sw_Dis/1', 'R_NotMaster/1', 'autorouting','on');
    add_line(scope, 'C_MasterVal/1', 'R_NotMaster/2', 'autorouting','on');
    add_line(scope, 'R_NotMaster/1', 'DTC_Bool/1', 'autorouting','on');
    add_line(scope, 'DTC_Bool/1', 'bLaneRoleCntrInPrgs/1', 'autorouting','on');
    % 未用输入 → Terminator
    add_line(scope, 'u8RmtLaneRole/1', 'Term_RmtRole/1', 'autorouting','on');
    add_line(scope, 'u8LaneStatus/1', 'Term_LaneSts/1', 'autorouting','on');
end

%% =====================================================================
function populateLaneSwitch(scope)
% 输入: u8LaneRole, bLaneRoleCntrInPrgs, bLaneStatusCntrInPrgs
% 输出: bLaneSwtgInProgs, u8LaneSwtInPrgsCntr
    addNamedInports(scope, {'u8LaneRole','bLaneRoleCntrInPrgs','bLaneStatusCntrInPrgs'});
    addNamedOutports(scope, {'bLaneSwtgInProgs','u8LaneSwtInPrgsCntr'});
    blk = @(b) [scope '/' b];

    % LaneRoleChanged = LaneRole != delay(LaneRole)
    add_block('built-in/UnitDelay', blk('UD_Role'), 'Position', [200 60 240 100]);
    add_block('built-in/RelationalOperator', blk('R_Changed'), 'Position', [300 60 360 100]);
    set_param(blk('R_Changed'), 'Operator', '~=');
    % Debounce counter
    add_block('built-in/UnitDelay', blk('UD_Cnt'), 'Position', [400 60 440 100]);
    add_block('built-in/Sum', blk('S_Cnt'), 'Position', [330 150 370 190]);
    set_param(blk('S_Cnt'), 'Inputs', '++');
    add_block('built-in/Constant', blk('C_One'), 'Value', 'uint8(1)', 'Position', [280 200 320 230]);
    add_block('built-in/Switch', blk('Sw_Cnt'), 'Position', [440 140 500 240]);
    set_param(blk('Sw_Cnt'), 'Criteria', 'u2 ~= 0');
    % Debounce 阈值
    add_block('built-in/RelationalOperator', blk('R_Timeout'), 'Position', [540 60 600 100]);
    set_param(blk('R_Timeout'), 'Operator', '>');
    add_block('built-in/Constant', blk('C_Debounce'), 'Value', 'uint8(10)', 'Position', [500 110 540 140]);
    % 输出逻辑
    add_block('simulink/Logic and Bit Operations/Logical Operator', blk('L_Or'), 'Position', [540 200 590 280]);
    set_param(blk('L_Or'), 'Operator', 'OR');
    set_param(blk('L_Or'), 'Inputs', '3');
    add_block('built-in/Switch', blk('Sw_Out'), 'Position', [640 60 700 160]);
    set_param(blk('Sw_Out'), 'Criteria', 'u2 ~= 0');
    add_block('built-in/Constant', blk('C_True'), 'Value', 'boolean(true)', 'Position', [600 10 640 40]);
    add_block('built-in/Constant', blk('C_False'), 'Value', 'boolean(false)', 'Position', [600 180 640 210]);

    %% Wiring（内部用信号名）
    add_line(scope, 'u8LaneRole/1', 'UD_Role/1', 'autorouting','on');
    add_line(scope, 'UD_Role/1', 'R_Changed/2', 'autorouting','on');
    add_line(scope, 'u8LaneRole/1', 'R_Changed/1', 'autorouting','on');
    add_line(scope, 'R_Changed/1', 'Sw_Cnt/2', 'autorouting','on');
    add_line(scope, 'C_One/1', 'Sw_Cnt/1', 'autorouting','on');
    add_line(scope, 'S_Cnt/1', 'Sw_Cnt/3', 'autorouting','on');
    add_line(scope, 'UD_Cnt/1', 'S_Cnt/1', 'autorouting','on');
    add_line(scope, 'C_One/1', 'S_Cnt/2', 'autorouting','on');
    add_line(scope, 'Sw_Cnt/1', 'UD_Cnt/1', 'autorouting','on');
    add_line(scope, 'UD_Cnt/1', 'R_Timeout/1', 'autorouting','on');
    add_line(scope, 'C_Debounce/1', 'R_Timeout/2', 'autorouting','on');
    add_line(scope, 'R_Timeout/1', 'Sw_Out/2', 'autorouting','on');
    add_line(scope, 'C_False/1', 'Sw_Out/1', 'autorouting','on');
    add_line(scope, 'C_True/1', 'Sw_Out/3', 'autorouting','on');
    add_line(scope, 'Sw_Out/1', 'L_Or/1', 'autorouting','on');
    add_line(scope, 'bLaneRoleCntrInPrgs/1', 'L_Or/2', 'autorouting','on');
    add_line(scope, 'bLaneStatusCntrInPrgs/1', 'L_Or/3', 'autorouting','on');
    add_line(scope, 'L_Or/1', 'bLaneSwtgInProgs/1', 'autorouting','on');
    add_line(scope, 'UD_Cnt/1', 'u8LaneSwtInPrgsCntr/1', 'autorouting','on');
end

%% =====================================================================
function populateLaneStatusDig(scope)
% 输入: u8LaneStatus
% 输出: u8RmtLaneSts (诊断透传), bActvCtrlr (LaneStatus==Operating)
    addNamedInports(scope, {'u8LaneStatus'});
    addNamedOutports(scope, {'u8RmtLaneSts','bActvCtrlr'});
    blk = @(b) [scope '/' b];
    add_block('built-in/RelationalOperator', blk('R_Op'), 'Position', [300 60 360 100]);
    set_param(blk('R_Op'), 'Operator', '==');
    add_block('built-in/Constant', blk('C_Op'), 'Value', 'uint8(1)', 'Position', [250 110 290 140]);
    add_block('built-in/DataTypeConversion', blk('DTC_Bool'), 'Position', [400 60 450 100]);
    set_param(blk('DTC_Bool'), 'OutDataTypeStr', 'boolean');
    add_line(scope, 'u8LaneStatus/1', 'R_Op/1', 'autorouting','on');
    add_line(scope, 'C_Op/1', 'R_Op/2', 'autorouting','on');
    add_line(scope, 'R_Op/1', 'DTC_Bool/1', 'autorouting','on');
    add_line(scope, 'DTC_Bool/1', 'bActvCtrlr/1', 'autorouting','on');
    add_line(scope, 'u8LaneStatus/1', 'u8RmtLaneSts/1', 'autorouting','on');
end

%% =====================================================================
function populateLaneRoleDig(scope)
% 输入: u8LaneRole
% 输出: s16LaneRoleDelta (诊断)
    addNamedInports(scope, {'u8LaneRole'});
    addNamedOutports(scope, {'s16LaneRoleDelta'});
    blk = @(b) [scope '/' b];
    add_block('built-in/UnitDelay', blk('UD_Prev'), 'Position', [250 60 290 100]);
    add_block('built-in/Sum', blk('S_Delta'), 'Position', [360 60 400 100]);
    set_param(blk('S_Delta'), 'Inputs', '+-');
    add_line(scope, 'u8LaneRole/1', 'UD_Prev/1', 'autorouting','on');
    add_line(scope, 'u8LaneRole/1', 'S_Delta/1', 'autorouting','on');
    add_line(scope, 'UD_Prev/1', 'S_Delta/2', 'autorouting','on');
    add_line(scope, 'S_Delta/1', 's16LaneRoleDelta/1', 'autorouting','on');
end

%% =====================================================================
function populateOutputArbitration(scope, outNames)
% 输入: u8LaneRole, u8LaneStatus, bLaneSwtgInProgs, bActvCtrlr, u8RmtLaneSts
% 输出: 与顶层输出一致（5 路 1:1）
%   注意: 仲裁输入信号名 = 顶层输出名，同 scope 内 In/Out 不能同名
%         故输入端口加 _In 后缀
    inNames = {'u8LaneRole_In','u8LaneStatus_In','bLaneSwtgInProgs_In', ...
               'bActvCtrlr_In','u8RmtLaneSts_In'};
    addNamedInports(scope, inNames);
    addNamedOutports(scope, outNames);
    for i = 1:numel(inNames)
        add_line(scope, [inNames{i} '/1'], [outNames{i} '/1'], 'autorouting', 'on');
    end
end

%% =====================================================================
function wireMainInternals(main, inNames, outNames)
% 内部连线: MainIn -> SignalAcquisition -> 功能模块 -> OutputArbitration -> MainOut
%   跨层级引用子系统端口规则（已验证）：
%     子系统输入 = 位置号 (Sub/1, Sub/2, ...)
%     子系统输出 = 位置 (Sub/Out1, Sub/Out2, ...)
%   （子系统的 Inport/Outport 名称仅用于内部逻辑可读性）

    % 1) MainIn(信号名) -> SignalAcquisition(位置1..8)
    for i = 1:numel(inNames)
        add_line(main, [inNames{i} '/1'], ['SignalAcquisition/' num2str(i)], 'autorouting', 'on');
    end

    % 2) SignalAcquisition 输出(Out1..8) -> 功能子系统输入(位置)
    %    [1] u8OperMode -> MLS(4)
    add_line(main, 'SignalAcquisition/Out1', 'LRM_MLS_ManageLaneStatus/4', 'autorouting','on');
    %    [2] u8LclIlcStatus -> MLS(1) + MLR(3)
    add_line(main, 'SignalAcquisition/Out2', 'LRM_MLS_ManageLaneStatus/1', 'autorouting','on');
    add_line(main, 'SignalAcquisition/Out2', 'LRM_MLR_ManageLaneRole/3', 'autorouting','on');
    %    [3] bIlcStsQf -> MLS(2)
    add_line(main, 'SignalAcquisition/Out3', 'LRM_MLS_ManageLaneStatus/2', 'autorouting','on');
    %    [4] u8HeartbeatLost -> MLS(3)
    add_line(main, 'SignalAcquisition/Out4', 'LRM_MLS_ManageLaneStatus/3', 'autorouting','on');
    %    [5] u8LclFitness -> MLR(1)
    add_line(main, 'SignalAcquisition/Out5', 'LRM_MLR_ManageLaneRole/1', 'autorouting','on');
    %    [6] u8RmtFitness -> MLR(2)
    add_line(main, 'SignalAcquisition/Out6', 'LRM_MLR_ManageLaneRole/2', 'autorouting','on');
    %    [7] u8RmtLaneRole -> MLR(5)
    add_line(main, 'SignalAcquisition/Out7', 'LRM_MLR_ManageLaneRole/5', 'autorouting','on');
    %    [8] u8LclLaneOperMode -> MLR(4)
    add_line(main, 'SignalAcquisition/Out8', 'LRM_MLR_ManageLaneRole/4', 'autorouting','on');

    % 3) MLS 输出(Out1=u8LaneStatus, Out2=bLaneStatusCntrInPrgs)
    %    LaneStatus -> LSD(1) + MLR(6)
    add_line(main, 'LRM_MLS_ManageLaneStatus/Out1', 'LRM_LSD_LaneStatusDig/1', 'autorouting','on');
    add_line(main, 'LRM_MLS_ManageLaneStatus/Out1', 'LRM_MLR_ManageLaneRole/6', 'autorouting','on');
    %    bLaneStatusCntrInPrgs -> LSP(3)
    add_line(main, 'LRM_MLS_ManageLaneStatus/Out2', 'LRM_LSP_LaneSwitchInProgs/3', 'autorouting','on');

    % 4) MLR 输出(Out1=u8LaneRole, Out2=bLaneRoleCntrInPrgs)
    %    LaneRole -> LSP(1) + LRD(1)
    add_line(main, 'LRM_MLR_ManageLaneRole/Out1', 'LRM_LSP_LaneSwitchInProgs/1', 'autorouting','on');
    add_line(main, 'LRM_MLR_ManageLaneRole/Out1', 'LRM_LRD_LaneRoleDig/1', 'autorouting','on');
    %    bLaneRoleCntrInPrgs -> LSP(2)
    add_line(main, 'LRM_MLR_ManageLaneRole/Out2', 'LRM_LSP_LaneSwitchInProgs/2', 'autorouting','on');

    % 5) LSP 输出(Out1=bLaneSwtgInProgs, Out2=u8LaneSwtInPrgsCntr 诊断→Term)
    add_line(main, 'LRM_LSP_LaneSwitchInProgs/Out1', 'OutputArbitration/3', 'autorouting','on');
    addTerminator(main, 'LRM_LSP_LaneSwitchInProgs/Out2');

    % 6) LSD 输出(Out1=u8RmtLaneSts, Out2=bActvCtrlr)
    add_line(main, 'LRM_LSD_LaneStatusDig/Out1', 'OutputArbitration/5', 'autorouting','on');
    add_line(main, 'LRM_LSD_LaneStatusDig/Out2', 'OutputArbitration/4', 'autorouting','on');

    % 7) LRD 输出(Out1=s16LaneRoleDelta 诊断→Term)
    addTerminator(main, 'LRM_LRD_LaneRoleDig/Out1');

    % 8) 直接透传: MLR/Out1(LaneRole)->Arb(1), MLS/Out1(LaneStatus)->Arb(2)
    add_line(main, 'LRM_MLR_ManageLaneRole/Out1', 'OutputArbitration/1', 'autorouting','on');
    add_line(main, 'LRM_MLS_ManageLaneStatus/Out1', 'OutputArbitration/2', 'autorouting','on');

    % 9) OutputArbitration Out1..5 -> MainSubsystem Out(信号名)
    for i = 1:numel(outNames)
        add_line(main, ['OutputArbitration/Out' num2str(i)], [outNames{i} '/1'], 'autorouting', 'on');
    end
end

%% =====================================================================
function addTerminator(scope, srcPort)
% 在给定子系统内添加 Terminator 并连接指定输出端口（相对 scope）
    persistent termCnt
    if isempty(termCnt), termCnt = 0; end
    termCnt = termCnt + 1;
    tname = sprintf('Term_%d', termCnt);
    add_block('built-in/Terminator', [scope '/' tname]);
    add_line(scope, srcPort, [tname '/1'], 'autorouting', 'on');
end
