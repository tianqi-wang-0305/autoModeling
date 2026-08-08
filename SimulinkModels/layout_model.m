function layout_model(mdl)
%LAYOUT_MODEL 通用 Simulink 自动布局脚本（仅 Simulink，不布局 Stateflow 内部）
%   layout_model              使用当前打开的模型
%   layout_model('MyModel')   指定模型（未加载会自动打开）
%
% 布局原理（数据流感知分层布局）：
%   - 每个作用域（根 + 所有子系统）按信号流向分层：输入端口在最左，
%     输出端口在最右，其余块按“距输入的最长路径”分列；
%   - 同一列的块纵向堆叠，顺序用 Barycenter（前驱行号中位数）减少交叉；
%   - 反馈回路（Unit Delay 等形成的环）用强连通分量压缩为同一列；
%   - Constant 常量贴近其消费块所在列，避免散落在最左边；
%   - 只移动块位置（set_param Position），不改结构、不动 Stateflow
%     图表内部状态，也不调用 Simulink.BlockDiagram.arrangeSystem。
%
% 用法示例：
%   layout_model('EMB_LRM_LaneRoleManager_v2')

if nargin < 1 || isempty(mdl)
    mdl = bdroot;
    if isempty(mdl)
        error('未指定模型且当前没有打开的模型。用法: layout_model(''MyModel'')');
    end
end
if ~bdIsLoaded(mdl)
    open_system(mdl);
end

% 收集所有系统（根 + 所有子系统，跳过 Stateflow 图表），按层级从深到浅处理
sysBlks = find_system(mdl, 'FindAll', 'on', 'BlockType', 'SubSystem');
tmp = {mdl};
for i = 1:numel(sysBlks)
    try
        if strcmp(get_param(sysBlks(i), 'MaskType'), 'Stateflow')
            continue;   % 跳过 Stateflow 图表（不布局其内部）
        end
    catch
    end
    tmp{end + 1} = getfullname(sysBlks(i)); %#ok<AGROW>
end
paths = tmp;
depth = cellfun(@(p) numel(strfind(p, '/')), paths);
[~, order] = sort(depth, 'descend');

for k = 1:numel(order)
    sys = paths{order(k)};
    try
        layScope(sys);
        fprintf('laid out %s\n', sys);
    catch err
        fprintf('skip %s: %s (line %d)\n', sys, err.message, err.stack(1).line);
    end
end
disp('layout_model done');
end

function layScope(sys)
% 对单个作用域做分层布局
blks = find_system(sys, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'block');
names = {};
types = containers.Map;
pos = containers.Map;
for i = 1:numel(blks)
    if strcmp(getfullname(blks(i)), sys)
        continue;   % 跳过系统自身的幻影块
    end
    nm = get_param(blks(i), 'Name');
    names{end + 1} = nm; %#ok<AGROW>
    types(nm) = get_param(blks(i), 'BlockType');
    pos(nm) = get_param(blks(i), 'Position');
end
if numel(names) < 2
    return;
end

% 连线 -> 边（去重）
edges = {};
seen = containers.Map;
lines = find_system(sys, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'line');
for i = 1:numel(lines)
    try
        sp = get_param(lines(i), 'SrcPortHandle');
        dp = get_param(lines(i), 'DstPortHandle');
        if sp <= 0
            continue;
        end
        sb = get_param(sp, 'Parent');
        if strcmp(sb, sys)
            continue;
        end
        [~, sn] = fileparts(sb);
        if ~isKey(types, sn)
            continue;
        end
        for d = 1:numel(dp)
            if dp(d) <= 0
                continue;
            end
            db = get_param(dp(d), 'Parent');
            if strcmp(db, sys)
                continue;
            end
            [~, dn] = fileparts(db);
            if ~isKey(types, dn)
                continue;
            end
            key = [sn '|' dn];
            if ~isKey(seen, key)
                seen(key) = 1;
                edges{end + 1} = {sn, dn}; %#ok<AGROW>
            end
        end
    catch
    end
end

% 强连通分量（反馈环压缩）
comp = sccTarjan(names, edges);
cnames = unique(values(comp));
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

% 分量分层：从源（无入边）出发求最长路径
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
            q(end + 1) = cj; %#ok<AGROW>
        end
    end
end
mx = max(layer);
for i = 1:nc
    if indeg(i) > 0
        layer(i) = mx + 1;
    end
end

% 每块的层
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
% 常量贴近消费块
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

% 分列
L = sort(unique(cell2mat(values(blayer))));
cols = containers.Map;
for l = L(:)'
    cols(num2str(l)) = {};
end
for i = 1:numel(names)
    l = blayer(names{i});
    col = cols(num2str(l));
    col{end + 1} = names{i};
    cols(num2str(l)) = col;
end

% 列内排序：Barycenter（前驱行号中位数），同层按名字稳定
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
                vals(end + 1) = row(pr{j}); %#ok<AGROW>
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

% 计算坐标并设置
MARGIN = 60;
COLGAP = 150;
ROWGAP = 90;
colw = containers.Map;
for l = L(:)'
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
end

function comp = sccTarjan(names, edges)
% Tarjan 强连通分量；comp: 名字 -> 代表根名字
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
            while true
                w = stk{end};
                stk(end) = [];
                onst(w) = false;
                comp(w) = v;
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
