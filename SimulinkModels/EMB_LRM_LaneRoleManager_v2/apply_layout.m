%% apply_layout.m - 把 compute_layout.py 计算的目标位置应用到模型（仅移动块，不改结构）
mdl = 'EMB_LRM_LaneRoleManager_v2';
targets = jsondecode(fileread('/Users/wangtianqi/SimulinkModels/EMB_LRM_LaneRoleManager_v2/layout_preview/layout_targets.json'));
sysMap = struct('root', mdl, 'main', [mdl '/MainSubsystem'], ...
  'sa', [mdl '/MainSubsystem/SignalAcquisition'], ...
  'mls', [mdl '/MainSubsystem/LRM_MLS_ManageLaneStatus'], ...
  'hbf', [mdl '/MainSubsystem/LRM_MLS_ManageLaneStatus/MLS_HB_Failure'], ...
  'stm', [mdl '/MainSubsystem/LRM_MLS_ManageLaneStatus/MLS_STM_StateMachine'], ...
  'mlr', [mdl '/MainSubsystem/LRM_MLR_ManageLaneRole'], ...
  'lsp', [mdl '/MainSubsystem/LRM_LSP_LaneSwitchInProgs'], ...
  'oa', [mdl '/MainSubsystem/OutputArbitration']);
scopes = fieldnames(targets);
for s = 1:numel(scopes)
    sc = scopes{s};
    if ~isfield(sysMap, sc), continue; end
    sys = sysMap.(sc);
    blks = find_system(sys, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'block');
    tgt = targets.(sc);
    n = 0;
    for b = 1:numel(blks)
        if strcmp(getfullname(blks(b)), sys)
            continue;   % 跳过系统自身的幻影块
        end
        nm = get_param(blks(b), 'Name');
        if isfield(tgt, nm)
            set_param(blks(b), 'Position', tgt.(nm));
            n = n + 1;
        end
    end
    fprintf('%s: positioned %d blocks\n', sc, n);
end
% 布局后再补设样式参数（脚本移动不会重置，但确保一致）
lb = find_system(mdl, 'FindAll', 'on', 'BlockType', 'Logic');
for i = 1:numel(lb)
    set_param(lb(i), 'IconShape', 'rectangular');
end
map = { 'Relop_HbThd','>='; 'Relop_FailThd','>='; 'Relop_InitWaitDone','>='; ...
        'Relop_MasterSwapDone','>'; 'Relop_TakeoverDone','>'; ...
        'Relop_SupportTakeoverDone','>'; 'Relop_FallbackSwapDone','>'; ...
        'Relop_FailWatchDone','>'; 'Relop_DebounceExceed','>' };
for i = 1:size(map,1)
    b = find_system(mdl,'FindAll','on','BlockType','RelationalOperator','Name',map{i,1});
    for j = 1:numel(b)
        set_param(b(j), 'Operator', map{i,2});
    end
end
disp('apply_layout done');
