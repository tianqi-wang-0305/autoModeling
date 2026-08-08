%% 调试：复现 arrange_all 中 Stateflow 深度计算
mdl = 'EMB_LRM_LaneRoleManager';
rt = sfroot;
charts = rt.find('-isa', 'Stateflow.Chart');
for c = 1:numel(charts)
    ch = charts(c);
    if ~startsWith(ch.Path, [mdl '/'])
        continue;
    end
    fprintf('== chart: %s\n', ch.Path);
    st = ch.find('-isa', 'Stateflow.State');
    chSegs = numel(strsplit(ch.Path, '/'));
    fprintf('chSegs=%d\n', chSegs);
    for k = 1:numel(st)
        s = st(k);
        op = [s.Path '/' s.Name];
        d = numel(strsplit(op, '/')) - chSegs;
        fprintf('  [%d] name=<%s> ownPath=<%s> segs=%d depth=%d\n', k, s.Name, op, numel(strsplit(op, '/')), d);
    end
end
