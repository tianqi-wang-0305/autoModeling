%% check_layout.m - 布局质量检查（只读）：统计每个系统内的块重叠对数
mdl = 'EMB_LRM_LaneRoleManager';
if ~bdIsLoaded(mdl)
    open_system(mdl);
end

sysBlks = find_system(mdl, 'FindAll', 'on', 'BlockType', 'SubSystem');
paths = cell(numel(sysBlks) + 1, 1);
paths{1} = mdl;
for i = 1:numel(sysBlks)
    paths{i + 1} = getfullname(sysBlks(i));
end

totalOverlap = 0;
for s = 1:numel(paths)
    p = paths{s};
    blks = find_system(p, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'block');
    if numel(blks) < 2
        continue;
    end
    pos = zeros(numel(blks), 4);
    ok = true(numel(blks), 1);
    for b = 1:numel(blks)
        try
            pos(b, :) = get_param(blks(b), 'Position');
        catch
            ok(b) = false;
        end
    end
    nOverlap = 0;
    for i = 1:numel(blks)
        if ~ok(i)
            continue;
        end
        for j = i + 1:numel(blks)
            if ~ok(j)
                continue;
            end
            ix = min(pos(i, 3), pos(j, 3)) - max(pos(i, 1), pos(j, 1));
            iy = min(pos(i, 4), pos(j, 4)) - max(pos(i, 2), pos(j, 2));
            if ix > 0 && iy > 0
                nOverlap = nOverlap + 1;
            end
        end
    end
    totalOverlap = totalOverlap + nOverlap;
    fprintf('%s: blocks=%d overlaps=%d\n', p, numel(blks), nOverlap);
end

% Stateflow 状态重叠
rt = sfroot;
charts = rt.find('-isa', 'Stateflow.Chart');
for c = 1:numel(charts)
    if ~startsWith(charts(c).Path, [mdl '/'])
        continue;
    end
    st = charts(c).find('-isa', 'Stateflow.State');
    nOverlap = 0;
    for i = 1:numel(st)
        for j = i + 1:numel(st)
            a = st(i).Position;
            b = st(j).Position;
            ix = min(a(1) + a(3), b(1) + b(3)) - max(a(1), b(1));
            iy = min(a(2) + a(4), b(2) + b(4)) - max(a(2), b(2));
            if ix > 0 && iy > 0
                nOverlap = nOverlap + 1;
            end
        end
    end
    totalOverlap = totalOverlap + nOverlap;
    fprintf('chart %s: states=%d overlaps=%d\n', charts(c).Path, numel(st), nOverlap);
end
fprintf('TOTAL overlap pairs: %d\n', totalOverlap);
