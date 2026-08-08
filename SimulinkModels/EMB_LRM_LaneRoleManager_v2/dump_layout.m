%% dump_layout.m - 导出各作用域块/连线数据为 JSON（只读）
mdl = 'EMB_LRM_LaneRoleManager_v2';
outDir = '/Users/wangtianqi/SimulinkModels/EMB_LRM_LaneRoleManager_v2/layout_preview/';
sysList = {mdl, ...
  [mdl '/MainSubsystem'], ...
  [mdl '/MainSubsystem/SignalAcquisition'], ...
  [mdl '/MainSubsystem/LRM_MLS_ManageLaneStatus'], ...
  [mdl '/MainSubsystem/LRM_MLS_ManageLaneStatus/MLS_HB_Failure'], ...
  [mdl '/MainSubsystem/LRM_MLS_ManageLaneStatus/MLS_STM_StateMachine'], ...
  [mdl '/MainSubsystem/LRM_MLR_ManageLaneRole'], ...
  [mdl '/MainSubsystem/LRM_LSP_LaneSwitchInProgs'], ...
  [mdl '/MainSubsystem/OutputArbitration']};
names = {'root','main','sa','mls','hbf','stm','mlr','lsp','oa'};
for i = 1:numel(sysList)
    sys = sysList{i};
    blks = find_system(sys, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'block');
    blocks = {};
    for b = 1:numel(blks)
        try
            if strcmp(getfullname(blks(b)), sys)
                continue;   % 跳过系统自身的幻影块
            end
            blocks{end+1} = struct('name', get_param(blks(b), 'Name'), ...
                'type', get_param(blks(b), 'BlockType'), ...
                'pos', get_param(blks(b), 'Position'));
        catch
        end
    end
    lines = find_system(sys, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'line');
    conns = {};
    for l = 1:numel(lines)
        try
            sp = get_param(lines(l), 'SrcPortHandle');
            dp = get_param(lines(l), 'DstPortHandle');
            if sp <= 0, continue; end
            srcBlk = get_param(sp, 'Parent');
            if strcmp(srcBlk, sys), continue; end
            for d = 1:numel(dp)
                if dp(d) > 0
                    dstBlk = get_param(dp(d), 'Parent');
                    if strcmp(dstBlk, sys), continue; end
                    [~, srcName] = fileparts(srcBlk);
                    [~, dstName] = fileparts(dstBlk);
                    conns{end+1} = struct('src', srcName, 'dst', dstName);
                end
            end
        catch
        end
    end
    data = struct('scope', sys, 'blocks', {blocks}, 'conns', {conns});
    fid = fopen([outDir names{i} '.json'], 'w');
    fprintf(fid, '%s', jsonencode(data));
    fclose(fid);
    fprintf('dumped %s: %d blocks, %d conns\n', names{i}, numel(blocks), numel(conns));
end
