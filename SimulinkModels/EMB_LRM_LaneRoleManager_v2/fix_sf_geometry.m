%% fix_sf_geometry.m - 重排 Stateflow 状态/转移几何，使模型可干净编译
mdl = 'EMB_LRM_LaneRoleManager_v2';
rt = sfroot;
charts = rt.find('-isa', 'Stateflow.Chart');
posMap = containers.Map;
posMap('INIT') = [50 50 320 220];
posMap('MonitoringOff') = [70 95 130 60];
posMap('MonitoringOn') = [220 95 130 60];
posMap('Operating') = [430 50 180 70];
posMap('HbLost') = [670 50 180 70];
posMap('Failed') = [910 50 180 70];
posMap('MLR_STM_Init') = [50 50 180 70];
posMap('MLR_STM_Disabled') = [280 50 180 70];
posMap('MLR_STM_ShuttingDown') = [510 50 180 70];
posMap('MLR_STM_OperationalRoles') = [740 50 560 260];
posMap('MLR_STM_FallBack') = [770 105 160 60];
posMap('MLR_STM_Support') = [950 105 160 60];
posMap('MLR_STM_Master') = [1130 105 160 60];

for c = 1:numel(charts)
    ch = charts(c);
    if ~startsWith(ch.Path, [mdl '/']), continue; end
    st = ch.find('-isa', 'Stateflow.State');
    for i = 1:numel(st)
        if isKey(posMap, st(i).Name)
            st(i).Position = posMap(st(i).Name);
        end
    end
    % 转移路径：源状态右边 -> 目标状态左边；默认转移从目标顶边
    tr = ch.find('-isa', 'Stateflow.Transition');
    for i = 1:numel(tr)
        t = tr(i);
        s = t.Source;
        d = t.Destination;
        if isa(d, 'Stateflow.State') && isKey(posMap, d.Name)
            dp = posMap(d.Name);
            dx = dp(1) + dp(3) / 2;
            dy = dp(2) + dp(4) / 2;
            if isa(s, 'Stateflow.State') && isKey(posMap, s.Name)
                sp = posMap(s.Name);
                sx = sp(1) + sp(3);
                sy = sp(2) + sp(4) / 2;
            else
                sx = dx - 120;
                sy = dy - 40;
            end
            if isa(s, 'Stateflow.State')
                t.SourceOClock = 3;      % 源状态右边界出
                t.DestinationOClock = 9; % 目标状态左边界入
                t.MidPoint = [];
            else
                t.SourceEndpoint = [sx sy];
                t.DestinationEndpoint = [dx dy];
                t.MidPoint = [];
            end
        end
    end
    fprintf('chart %s geometry fixed\n', ch.Name);
end
% 编译验证
try
    set_param(mdl, 'SimulationCommand', 'update');
    pause(1);
    fprintf('UPDATE OK\n');
catch e
    fprintf('UPDATE FAIL: %s\n', e.message);
end
