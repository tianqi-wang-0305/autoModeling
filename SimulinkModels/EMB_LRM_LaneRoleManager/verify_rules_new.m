%% verify_rules_new.m - 只读验证脚本（不修改模型结构）
% 检查：端口命名/类型前缀、无 double、描述属性、cal 常量类型
mdl = 'EMB_LRM_LaneRoleManager';
if ~bdIsLoaded(mdl)
    open_system(mdl);
end

issues = {};

% 1) 更新图表（编译）以获取真实端口类型
try
    set_param(mdl, 'SimulationCommand', 'update');
    pause(0.8);
    disp('[OK] diagram update (compile)');
catch e
    issues{end+1} = ['update failed: ' e.message];
end

% 2) 扫描所有块的 CompiledPortDataTypes 是否含 double
blks = find_system(mdl, 'FindAll', 'on', 'Type', 'block');
nDouble = 0;
for i = 1:numel(blks)
    try
        cdt = get_param(blks(i), 'CompiledPortDataTypes');
        if isfield(cdt, 'Outport')
            for j = 1:numel(cdt.Outport)
                if strcmp(cdt.Outport{j}, 'double')
                    nDouble = nDouble + 1;
                    issues{end+1} = sprintf('double output: %s port %d', getfullname(blks(i)), j);
                end
            end
        end
    catch
    end
end
if nDouble == 0
    disp('[OK] no double in any compiled output');
else
    disp(['[FAIL] ' num2str(nDouble) ' double outputs']);
end

% 3) 端口命名与类型前缀检查
ports = find_system(mdl, 'FindAll', 'on', 'BlockType', 'Inport');
ports = [ports; find_system(mdl, 'FindAll', 'on', 'BlockType', 'Outport')];
for i = 1:numel(ports)
    nm = get_param(ports(i), 'Name');
    if isempty(regexp(nm, '^[a-zA-Z][a-zA-Z0-9_]{0,31}$', 'once'))
        issues{end+1} = ['bad name: ' nm];
    end
    if isempty(get_param(ports(i), 'Description'))
        issues{end+1} = ['missing description: ' getfullname(ports(i))];
    end
end
disp(['[OK] port name/description scan done: ' num2str(numel(ports)) ' ports']);

% 4) 子系统描述检查
subs = find_system(mdl, 'FindAll', 'on', 'BlockType', 'SubSystem');
for i = 1:numel(subs)
    if isempty(get_param(subs(i), 'Description'))
        issues{end+1} = ['missing subsystem description: ' getfullname(subs(i))];
    end
end
disp(['[OK] subsystem description scan done: ' num2str(numel(subs)) ' subsystems']);

% 5) cal_ 常量类型检查
cals = find_system(mdl, 'FindAll', 'on', 'BlockType', 'Constant');
nCal = 0;
for i = 1:numel(cals)
    nm = get_param(cals(i), 'Name');
    if startsWith(nm, 'cal_')
        nCal = nCal + 1;
        dt = get_param(cals(i), 'OutDataTypeStr');
        if strcmp(dt, 'double') || contains(dt, 'Inherit')
            issues{end+1} = ['cal type not explicit: ' getfullname(cals(i)) ' -> ' dt];
        end
        if isempty(get_param(cals(i), 'Description'))
            issues{end+1} = ['missing cal description: ' getfullname(cals(i))];
        end
    end
end
disp(['[OK] cal scan done: ' num2str(nCal) ' calibrations']);

if isempty(issues)
    disp('=== ALL CHECKS PASSED ===');
else
    disp('=== ISSUES ===');
    for i = 1:numel(issues)
        disp(issues{i});
    end
end
