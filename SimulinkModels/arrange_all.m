function arrange_all(mdl)
%ARRANGE_ALL 通用模型自动布局脚本（Simulink + Stateflow）
%   arrange_all               使用当前打开的模型
%   arrange_all('MyModel')    指定模型名（未加载会自动打开）
%
% 功能：
%   1) 对模型根与所有子系统逐层调用 Simulink.BlockDiagram.arrangeSystem，
%      顺序为“从最内层到顶层”，保证父级按子级重排后的新尺寸摆放；
%   2) 对模型内每个 Stateflow 图表，按父子层级排成可读网格：
%      - 先自底向上计算每个状态的尺寸（含子状态的状态自动放大以容纳子状态）；
%      - 再自顶向下定位：根状态横向排列，子状态排在其父状态框内的网格中；
%   3) 按状态边界自动放大图表块，保证所有状态可见。
%
% 特点：
%   - 完全通用，不依赖具体模型结构，任意模型可直接调用；
%   - arrangeSystem 不处理 Stateflow 图表内部，脚本对图表单独处理；
%   - 单个系统布局失败不会中断，会打印跳过信息。
%
% 注意：
%   - 该脚本使用 Simulink/Stateflow 原生布局 API，不经过 model_edit 的
%     撤销栈，重要模型建议先保存副本；
%   - 布局会覆盖手工微调过的块位置。

if nargin < 1 || isempty(mdl)
    mdl = bdroot;
    if isempty(mdl)
        error('未指定模型且当前没有打开的模型。用法: arrange_all(''MyModel'')');
    end
end

if ~bdIsLoaded(mdl)
    open_system(mdl);
end

% ---------- 1) Stateflow 图表内部状态布局 ----------
nChart = 0;
nState = 0;
try
    rt = sfroot;
    prefix = [mdl '/'];
    charts = rt.find('-isa', 'Stateflow.Chart');
    for c = 1:numel(charts)
        ch = charts(c);
        if ~startsWith(ch.Path, prefix)
            continue;   % 跳过其他已加载模型中的图表
        end
        st = ch.find('-isa', 'Stateflow.State');
        if isempty(st)
            continue;
        end
        chSegs = numel(strsplit(ch.Path, '/'));
        % Stateflow 的 Path 是“父级路径”：根状态 Path == 图表路径，
        % 子状态 Path == 父状态完整路径。自身完整路径 = [Path '/' Name]。
        ownPath = arrayfun(@(s) [s.Path '/' s.Name], st, 'UniformOutput', false);
        depth = cellfun(@(p) numel(strsplit(p, '/')) - chSegs, ownPath);
        [~, orderDeep] = sort(depth, 'descend');   % 尺寸：先子后父
        [~, orderTop] = sort(depth);               % 定位：先父后子

        % 父 -> 子索引映射
        childrenIdx = containers.Map('KeyType', 'char', 'ValueType', 'any');
        for i = 1:numel(st)
            par = st(i).Path;                       % 父状态自身完整路径
            if isKey(childrenIdx, par)
                childrenIdx(par) = [childrenIdx(par), i];
            else
                childrenIdx(par) = i;
            end
        end
        % 每个父状态使用的列数（与子状态网格一致）
        colsMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
        keysC = keys(childrenIdx);
        for i = 1:numel(keysC)
            colsMap(keysC{i}) = min(3, numel(childrenIdx(keysC{i})));
        end

        szW = zeros(1, numel(st));
        szH = zeros(1, numel(st));
        for k = 1:numel(orderDeep)
            i = orderDeep(k);
            kids = [];
            if isKey(childrenIdx, ownPath{i})
                kids = childrenIdx(ownPath{i});
            end
            if isempty(kids)
                cur = st(i).Position;
                if numel(cur) == 4 && cur(3) > 0 && cur(4) > 0
                    szW(i) = cur(3);
                    szH(i) = cur(4);
                else
                    szW(i) = 160;
                    szH(i) = 90;
                end
            else
                cw = max(szW(kids));
                chh = max(szH(kids));
                cols = colsMap(ownPath{i});
                rows = ceil(numel(kids) / cols);
                szW(i) = max(160, 20 + cols * (cw + 30));
                szH(i) = max(90, 50 + rows * (chh + 30));
            end
        end

        posOf = containers.Map('KeyType', 'char', 'ValueType', 'any');
        nextChild = containers.Map('KeyType', 'char', 'ValueType', 'double');
        rootCount = 0;
        for k = 1:numel(orderTop)
            i = orderTop(k);
            w = szW(i);
            h = szH(i);
            if depth(i) == 1
                x = 50 + rootCount * (w + 70);
                y = 50;
                rootCount = rootCount + 1;
            else
                parPath = st(i).Path;
                if ~isKey(posOf, parPath)
                    continue;
                end
                pp = posOf(parPath);
                ci = nextChild(parPath);
                cols = colsMap(parPath);
                col = mod(ci, cols);
                row = floor(ci / cols);
                x = pp(1) + 20 + col * (w + 30);
                y = pp(2) + 50 + row * (h + 30);
                nextChild(parPath) = ci + 1;
            end
            st(i).Position = [x y w h];
            posOf(ownPath{i}) = [x y w h];
            if ~isKey(nextChild, ownPath{i})
                nextChild(ownPath{i}) = 0;
            end
            nState = nState + 1;
        end
        % 按状态边界放大图表块，保证所有状态可见
        try
            xs = arrayfun(@(s) s.Position(1), st);
            ys = arrayfun(@(s) s.Position(2), st);
            ws = arrayfun(@(s) s.Position(1) + s.Position(3), st);
            hs = arrayfun(@(s) s.Position(2) + s.Position(4), st);
            x0 = min(xs) - 30;
            y0 = min(ys) - 30;
            w0 = max(ws) - min(xs) + 60;
            h0 = max(hs) - min(ys) + 60;
            if w0 > 0 && h0 > 0
                set_param(ch.Path, 'Position', [x0 y0 w0 h0]);
            end
        catch
        end
        nChart = nChart + 1;
    end
catch err
    warning('Stateflow 布局跳过: %s', err.message);
end

% ---------- 2) 所有 Simulink 系统从内到外布局 ----------
sysBlks = find_system(mdl, 'FindAll', 'on', 'BlockType', 'SubSystem');
paths = cell(numel(sysBlks) + 1, 1);
paths{1} = mdl;
for i = 1:numel(sysBlks)
    paths{i + 1} = getfullname(sysBlks(i));
end
depth = cellfun(@(p) numel(strsplit(p, '/')) - 1, paths);
[~, order] = sort(depth, 'descend');
nSys = 0;
for k = 1:numel(order)
    try
        Simulink.BlockDiagram.arrangeSystem(paths{order(k)});
        nSys = nSys + 1;
    catch err
        fprintf('跳过布局 %s: %s\n', paths{order(k)}, err.message);
    end
end

fprintf('arrange_all 完成: 布局系统 %d 个，Stateflow 图表 %d 个（状态 %d 个）。\n', ...
    nSys, nChart, nState);
end
