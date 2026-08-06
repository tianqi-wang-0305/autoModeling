% Verify EMB_LRM.slx against EMB_LRM.spec.json and the
% simulink-modeling-style rules (spec conformance, Description attributes,
% no double, basic blocks only, layered architecture).

outDir = '/Users/wangtianqi/SimulinkModels/EMB_LRM';
model = 'EMB_LRM';
spec = jsondecode(fileread(fullfile(outDir, 'EMB_LRM.spec.json')));

fails = 0;
report = @(ok, msg) fprintf('[%s] %s\n', string(ok) + "", msg) + (0);
pass = @(msg) fprintf('[PASS] %s\n', msg);
fail = @(msg) fprintf('[FAIL] %s\n', msg);

load_system(fullfile(outDir, [model '.slx']));

nameOf = @(p) regexp(p, '[^/]+$', 'match', 'once');

%% 1. spec JSON exists + model implements every top-level port, no extras
assert(exist(fullfile(outDir, 'EMB_LRM.spec.json'), 'file') == 2, 'spec JSON missing');
topIn  = find_system(model, 'SearchDepth', 1, 'BlockType', 'Inport');
topOut = find_system(model, 'SearchDepth', 1, 'BlockType', 'Outport');
topInNames = cellfun(nameOf, topIn, 'UniformOutput', false);
topOutNames = cellfun(nameOf, topOut, 'UniformOutput', false);
specIn = {spec.inputs.name}; specOut = {spec.outputs.name};
topInNames = reshape(topInNames, 1, []); topOutNames = reshape(topOutNames, 1, []);
specIn = reshape(specIn, 1, []); specOut = reshape(specOut, 1, []);

if isequal(topInNames, specIn)
    pass('顶层输入端口与 spec.inputs 名称一致（8 个）');
else
    fail(['顶层输入端口不一致: model=' strjoin(topInNames, ',') ' spec=' strjoin(specIn, ',')]); fails = fails + 1;
end
if isequal(topOutNames, specOut)
    pass('顶层输出端口与 spec.outputs 名称一致（4 个）');
else
    fail(['顶层输出端口不一致: model=' strjoin(topOutNames, ',') ' spec=' strjoin(specOut, ',')]); fails = fails + 1;
end

%% 2. Calibration blocks exist and have Description
calBlocks = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', 'Constant');
calBlocks = calBlocks(cellfun(@(p) startsWith(nameOf(p), 'cal_'), calBlocks));
specCal = {spec.calibrations.name};
calNames = cellfun(nameOf, calBlocks, 'UniformOutput', false);
calNamesS = reshape(sort(calNames), 1, []); specCalS = reshape(sort(specCal), 1, []);
if isequal(calNamesS, specCalS)
    pass(['标定量与 spec.calibrations 一致: ' strjoin(calNamesS, ', ')]);
else
    fail(['标定量不一致: model=' strjoin(calNamesS, ',') ' spec=' strjoin(specCalS, ',')]); fails = fails + 1;
end
for i = 1:numel(calBlocks)
    d = get_param(calBlocks{i}, 'Description');
    if isempty(strtrim(d))
        fail(['标定 ' nameOf(calBlocks{i}) ' 的 Description 为空']); fails = fails + 1;
    else
        pass(['标定 ' nameOf(calBlocks{i}) ' 的 Description 已写入']);
    end
end

%% 3. Top-level ports have Description
allTopPorts = [topIn; topOut];
for i = 1:numel(allTopPorts)
    d = get_param(allTopPorts{i}, 'Description');
    if isempty(strtrim(d))
        fail(['顶层端口 ' nameOf(allTopPorts{i}) ' 的 Description 为空']); fails = fails + 1;
    else
        pass(['顶层端口 ' nameOf(allTopPorts{i}) ' 的 Description 已写入']);
    end
end

%% 4. Subsystems exist with non-empty Description; match spec
subsys = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', 'SubSystem');
subsys = subsys(~cellfun(@(p) strcmp(p, model), subsys));
subNames = cellfun(nameOf, subsys, 'UniformOutput', false);
specSub = {spec.subsystems.name};
required = [{ [model '/MainSubsystem'] }, ...
            cellfun(@(n) [model '/MainSubsystem/' n], specSub, 'UniformOutput', false)];
missing = required(~cellfun(@(p) any(strcmp(p, subsys)), required));
if isempty(missing)
    pass(['子系统与 spec.subsystems 一致（含 MainSubsystem）: ' strjoin(specSub, ', ')]);
else
    fail(['缺少子系统: ' strjoin(missing, ', ')]); fails = fails + 1;
end
for i = 1:numel(subsys)
    d = get_param(subsys{i}, 'Description');
    if isempty(strtrim(d))
        fail(['子系统 ' subsys{i} ' 的 Description 为空']); fails = fails + 1;
    else
        pass(['子系统 ' subsys{i} ' 的 Description 已写入（职责+逻辑）']);
    end
end

%% 5. No double anywhere
allBlocks = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on');
allBlocks = allBlocks(~strcmp(allBlocks, model));
doubleFound = false;
for i = 1:numel(allBlocks)
    try
        t = get_param(allBlocks{i}, 'OutDataTypeStr');
        if contains(t, 'double')
            fail(['发现 double 类型: ' allBlocks{i} ' -> ' t]); doubleFound = true; fails = fails + 1;
        end
    catch
    end
end
if ~doubleFound
    pass('全模型未发现 double 类型（浮点/整型均显式指定）');
end

%% 6. Basic blocks only
allowed = {'Inport','Outport','SubSystem','Constant','RelationalOperator','Terminator', ...
           'UnitDelay','Sum','Abs','DataTypeConversion','Logic','Switch'};
rt6 = sfroot;
charts6 = find(rt6, '-isa', 'Stateflow.Chart');
chartPrefixes = cellfun(@(p) [p '/'], {charts6.Path}, 'UniformOutput', false);
allBlocks = allBlocks(~cellfun(@(p) any(startsWith(p, chartPrefixes)), allBlocks));
bt = get_param(allBlocks, 'BlockType');
if iscell(bt), bt = bt; else, bt = {bt}; end
bad = find(~ismember(bt, allowed));
if isempty(bad)
    pass(['模块类型全部为基本模块: ' strjoin(unique(bt), ', ')]);
else
    for i = 1:numel(bad)
        fail(['非基本模块: ' allBlocks{bad(i)} ' (' bt{bad(i)} ')']); fails = fails + 1;
    end
end

%% 7. Port 1:1 between top level and MainSubsystem
ms = [model '/MainSubsystem'];
msIn = find_system(ms, 'SearchDepth', 1, 'BlockType', 'Inport');
msOut = find_system(ms, 'SearchDepth', 1, 'BlockType', 'Outport');
msInNames = cellfun(nameOf, msIn, 'UniformOutput', false);
msOutNames = cellfun(nameOf, msOut, 'UniformOutput', false);
msInNames = reshape(msInNames, 1, []); msOutNames = reshape(msOutNames, 1, []);
if isequal(msInNames, topInNames) && isequal(msOutNames, topOutNames)
    pass('顶层与 MainSubsystem 端口 1:1 一致');
else
    fail('顶层与 MainSubsystem 端口不一致'); fails = fails + 1;
end

%% 8. Architecture roles present
roles = {'SignalAcquisition','LRM_MLS_ManageLaneStatus','LRM_MLR_ManageLaneRole', ...
         'LRM_LSP_LaneSwitchInProgs','OutputArbitration'};
missingRoles = roles(~cellfun(@(r) ~isempty(find_system(ms, 'SearchDepth', 1, 'Name', r)), roles));
if isempty(missingRoles)
    pass('架构角色完整：SignalAcquisition / 功能模块 / OutputArbitration');
else
    fail(['缺少架构角色: ' strjoin(missingRoles, ', ')]); fails = fails + 1;
end

%% 9. Stateflow charts: all inputs boolean
rt = sfroot;
allCharts = find(rt, '-isa', 'Stateflow.Chart');
charts = allCharts(~cellfun(@(p) isempty(strfind(p, [model '/'])), {allCharts.Path}));
if isempty(charts)
    fail('未找到 Stateflow Chart（MLR 应为 Stateflow 实现）'); fails = fails + 1;
else
    chartOk = true;
    for k = 1:numel(charts)
        ins = find(charts(k), '-isa', 'Stateflow.Data', 'Scope', 'Input');
        for j = 1:numel(ins)
            if ~strcmp(ins(j).DataType, 'boolean')
                fail(['Chart ' charts(k).Path ' 输入 ' ins(j).Name ' 类型为 ' ins(j).DataType '（应全为 boolean）']);
                chartOk = false; fails = fails + 1;
            end
        end
    end
    if chartOk
        pass(['Stateflow Chart 全部输入为 boolean（' charts(1).Name '，输入数 ' num2str(numel(find(charts(1), '-isa', 'Stateflow.Data', 'Scope', 'Input'))) '）']);
    end
end

close_system(model, 0);
fprintf('\n===== 验证总结: %d 项失败 =====\n', fails);
if fails > 0
    exit(1);
end
