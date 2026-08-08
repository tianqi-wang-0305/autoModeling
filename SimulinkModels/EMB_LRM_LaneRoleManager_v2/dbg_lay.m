%% 调试 layout_model 内部逻辑（SignalAcquisition）
sys = 'EMB_LRM_LaneRoleManager_v2/MainSubsystem/LRM_MLS_ManageLaneStatus/MLS_HB_Failure';
disp('STEP1 blocks');
blks = find_system(sys, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'block');
names = {};
types = containers.Map;
pos = containers.Map;
for i = 1:numel(blks)
    if strcmp(getfullname(blks(i)), sys), continue; end
    nm = get_param(blks(i), 'Name');
    names{end + 1} = nm;
    types(nm) = get_param(blks(i), 'BlockType');
    pos(nm) = get_param(blks(i), 'Position');
end
fprintf('names=%d\n', numel(names));
disp('STEP2 edges');
edges = {};
seen = containers.Map;
lines = find_system(sys, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'line');
for i = 1:numel(lines)
    sp = get_param(lines(i), 'SrcPortHandle');
    dp = get_param(lines(i), 'DstPortHandle');
    if sp <= 0, continue; end
    sb = get_param(sp, 'Parent');
    if strcmp(sb, sys), continue; end
    [~, sn] = fileparts(sb);
    if ~isKey(types, sn), continue; end
    for d = 1:numel(dp)
        if dp(d) <= 0, continue; end
        db = get_param(dp(d), 'Parent');
        if strcmp(db, sys), continue; end
        [~, dn] = fileparts(db);
        if ~isKey(types, dn), continue; end
        key = [sn '|' dn];
        if ~isKey(seen, key)
            seen(key) = 1;
            edges{end + 1} = {sn, dn};
        end
    end
end
fprintf('edges=%d\n', numel(edges));
disp('STEP3 SCC');
comp = dbgScc(names, edges);
fprintf('comp keys=%d\n', numel(keys(comp)));
cnames = unique(values(comp));
fprintf('cnames=%d\n', numel(cnames));
for i = 1:numel(names)
    if ~isKey(comp, names{i})
        fprintf('comp MISSING name: %s\n', names{i});
    end
end
cidxt = containers.Map;
for i = 1:numel(cnames)
    cidxt(cnames{i}) = i;
end
for i = 1:numel(edges)
    e = edges{i};
    if ~isKey(comp, e{1}), fprintf('edge src missing in comp: %s\n', e{1}); end
    if ~isKey(comp, e{2}), fprintf('edge dst missing in comp: %s\n', e{2}); end
    if isKey(comp, e{1}) && ~isKey(cidxt, comp(e{1}))
        fprintf('comp value not in cnames: %s -> [%s]\n', e{1}, comp(e{1}));
    end
end
disp('SCC CHECK DONE');
disp('STEP4 layer');
nc = numel(cnames);
cidx = containers.Map;
for i = 1:nc
    cidx(cnames{i}) = i;
end
csucc = cell(nc, 1);
for i = 1:nc
    csucc{i} = [];
end
indeg = zeros(nc, 1);
for i = 1:numel(edges)
    e = edges{i};
    if ~strcmp(comp(e{1}), comp(e{2}))
        ci = cidx(comp(e{1}));
        cj = cidx(comp(e{2}));
        if isempty(find(csucc{ci} == cj, 1))
            csucc{ci}(end + 1) = cj;
            indeg(cj) = indeg(cj) + 1;
        end
    end
end
layer = zeros(nc, 1);
q = find(indeg == 0);
head = 1;
while head <= numel(q)
    ci = q(head);
    head = head + 1;
    for cj = csucc{ci}
        layer(cj) = max(layer(cj), layer(ci) + 1);
        indeg(cj) = indeg(cj) - 1;
        if indeg(cj) == 0
            q(end + 1) = cj;
        end
    end
end
mx = max(layer);
for i = 1:nc
    if indeg(i) > 0
        layer(i) = mx + 1;
    end
end
disp('STEP5 blayer');
blayer = containers.Map;
for i = 1:numel(names)
    blayer(names{i}) = layer(cidx(comp(names{i})));
end
for i = 1:numel(names)
    if strcmp(types(names{i}), 'Inport')
        blayer(names{i}) = 0;
    end
end
mx = max(cell2mat(values(blayer)));
for i = 1:numel(names)
    if strcmp(types(names{i}), 'Outport')
        blayer(names{i}) = mx + 1;
    end
end
mx = max(cell2mat(values(blayer)));
for i = 1:numel(names)
    if strcmp(types(names{i}), 'Constant')
        lv = inf;
        for j = 1:numel(edges)
            if strcmp(edges{j}{1}, names{i})
                lv = min(lv, blayer(edges{j}{2}));
            end
        end
        if isfinite(lv)
            blayer(names{i}) = lv;
        else
            blayer(names{i}) = max(0, mx - 1);
        end
    end
end
disp('STEP6 columns');
L = sort(unique(cell2mat(values(blayer))));
disp('L =');
disp(L);
cols = containers.Map;
for l = L'
    cols(num2str(l)) = {};
end
disp('cols keys:');
disp(keys(cols));
for lk = L'
    fprintf('key cand: [%s] len=%d\n', num2str(lk), numel(num2str(lk)));
end
for i = 1:numel(names)
    l = blayer(names{i});
    if ~isKey(cols, num2str(l))
        fprintf('MISSING KEY for %s: blayer=%s\n', names{i}, mat2str(l));
    end
    col = cols(num2str(l));
    col{end + 1} = names{i};
    cols(num2str(l)) = col;
end
disp('STEP7 barycenter');
row = containers.Map;
preds = containers.Map;
for i = 1:numel(names)
    preds(names{i}) = {};
end
for i = 1:numel(edges)
    e = edges{i};
    p = preds(e{2});
    p{end + 1} = e{1};
    preds(e{2}) = p;
end
for li = 1:numel(L)
    l = L(li);
    col = cols(num2str(l));
    [~, si] = sort(col);
    col = col(si);
    keys = zeros(numel(col), 1);
    for i = 1:numel(col)
        pr = preds(col{i});
        vals = [];
        for j = 1:numel(pr)
            if isKey(row, pr{j})
                vals(end + 1) = row(pr{j});
            end
        end
        if isempty(vals)
            keys(i) = 0;
        else
            vals = sort(vals);
            keys(i) = vals(ceil(numel(vals) / 2));
        end
    end
    [~, oi] = sort(keys);
    col = col(oi);
    for i = 1:numel(col)
        row(col{i}) = i - 1;
    end
    cols(num2str(l)) = col;
end
disp('STEP8 positions');
MARGIN = 60; COLGAP = 150; ROWGAP = 90;
colw = containers.Map;
for l = L'
    col = cols(num2str(l));
    w = 0;
    for i = 1:numel(col)
        p = pos(col{i});
        w = max(w, p(3) - p(1));
    end
    colw(num2str(l)) = w;
end
xs = containers.Map;
cur = MARGIN;
for li = 1:numel(L)
    l = L(li);
    xs(num2str(l)) = cur;
    cur = cur + colw(num2str(l)) + COLGAP;
end
for li = 1:numel(L)
    l = L(li);
    col = cols(num2str(l));
    rh = 0;
    for i = 1:numel(col)
        p = pos(col{i});
        rh = max(rh, p(4) - p(2));
    end
    for i = 1:numel(col)
        nm = col{i};
        p = pos(nm);
        w = p(3) - p(1);
        h = p(4) - p(2);
        y = MARGIN + (i - 1) * (rh + ROWGAP);
        set_param([sys '/' nm], 'Position', [xs(num2str(l)), y, xs(num2str(l)) + w, y + h]);
    end
end
disp('DONE');

function comp = dbgScc(names, edges)
adj = containers.Map;
for i = 1:numel(names)
    adj(names{i}) = {};
end
for i = 1:numel(edges)
    e = edges{i};
    a = adj(e{1});
    a{end + 1} = e{2};
    adj(e{1}) = a;
end
idx = containers.Map;
low = containers.Map;
onst = containers.Map;
stk = {};
comp = containers.Map;
counter = 0;
    function strong(v)
        fprintf('  strong enter: %s\n', v);
        counter = counter + 1;
        idx(v) = counter;
        low(v) = counter;
        stk{end + 1} = v;
        onst(v) = true;
        aw = adj(v);
        for ii = 1:numel(aw)
            w = aw{ii};
            if ~isKey(idx, w)
                strong(w);
                low(v) = min(low(v), low(w));
            elseif isKey(onst, w)
                low(v) = min(low(v), idx(w));
            end
        end
        if low(v) == idx(v)
            fprintf('  pop SCC root: %s\n', v);
            while true
                w = stk{end};
                stk(end) = [];
                onst(w) = false;
                comp(w) = v;
                fprintf('    comp(%s)=%s\n', w, v);
                if strcmp(w, v)
                    break;
                end
            end
        end
    end
for i = 1:numel(names)
    if ~isKey(idx, names{i})
        strong(names{i});
    end
end
end
