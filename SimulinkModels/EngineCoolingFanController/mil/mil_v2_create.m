%% 按新规则重新生成：只用 testing-simulink-models 工具链；.mldatx + .mat + .xlsx
addpath('/Users/wangtianqi/.matlab/agentic-toolkits/simulink/skills-catalog/verification-validation-and-test/testing-simulink-models/scripts');
mdl = 'EngineCoolingFanController';
wf = '/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/mil';
if ~bdIsLoaded(mdl)
    open_system(['/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/' mdl '.slx']);
end
if ~evalin('base', 'exist(''cal_f32TempThresh'',''var'')')
    assignin('base','cal_f32TempThresh',single(90));
    assignin('base','cal_f32HystHalf',single(5));
    assignin('base','cal_f32TempHighLim',single(110));
    assignin('base','cal_u8FanSpeedCmd',uint8(80));
end
dt = 0.01;

% ---------- 用例定义（10 功能 + 3 MCDC 真值表补充） ----------
C = struct([]);
C(1).name='TC01_OffBelowLo';       C(1).desc='温度<85：风扇关，无故障'; C(1).sigs={80,100,1};
C(2).name='TC02_HoldOff_Deadband'; C(2).desc='80->90 滞环区间：保持关'; C(2).sigs={[80*ones(100,1);90*ones(100,1)],100,1};
C(3).name='TC03_OnAboveHi';        C(3).desc='80->96 超95：风扇开'; C(3).sigs={[80*ones(100,1);96*ones(100,1)],100,1};
C(4).name='TC04_HoldOn_Deadband';  C(4).desc='96->90 滞环区间：保持开'; C(4).sigs={[96*ones(100,1);90*ones(100,1)],100,1};
C(5).name='TC05_ResetBelowLo';     C(5).desc='96->84 低于85：风扇关'; C(5).sigs={[96*ones(100,1);84*ones(100,1)],100,1};
C(6).name='TC06_IgnOff_Gate';      C(6).desc='96 但点火关：指令0；点火开：80'; C(6).sigs={96*ones(200,1),100,[false(100,1);true(100,1)]};
C(7).name='TC07_Fault_HighTemp';   C(7).desc='115>110：故障1，风扇开'; C(7).sigs={115,100,1};
C(8).name='TC08_FaultRecovery';    C(8).desc='115->105：故障1->0，风扇开'; C(8).sigs={[115*ones(100,1);105*ones(100,1)],100,1};
C(9).name='TC09_Boundary_Exact';   C(9).desc='恰为95/85：不触发，保持关'; C(9).sigs={[80*ones(60,1);95*ones(70,1);85*ones(70,1)],100,1};
C(10).name='TC10_Hysteresis_Cycle';C(10).desc='80->96->84->100：关->开->关->开'; C(10).sigs={[80*ones(50,1);96*ones(50,1);84*ones(50,1);100*ones(50,1)],100,1};
C(11).name='MC11_SetHold_TruthTable';C(11).desc='MCDC：AboveHi/Hold/BelowLo 组合真值表（80->96->90->84->90->96）'; C(11).sigs={[80*ones(50,1);96*ones(50,1);90*ones(50,1);84*ones(50,1);90*ones(50,1);96*ones(50,1)],100,1};
C(12).name='MC12_FanGate_TruthTable';C(12).desc='MCDC：IgnOn/FanOn 组合（80/ign1, 96/ign0, 96/ign1, 84/ign1）'; C(12).sigs={[80*ones(50,1);96*ones(50,1);96*ones(50,1);84*ones(50,1)],100,[true(50,1);false(50,1);true(50,1);true(50,1)]};
C(13).name='MC13_Fault_TruthTable';C(13).desc='MCDC：Fault 真/假 + 风扇开/关（100->112->105->80）'; C(13).sigs={[100*ones(50,1);112*ones(50,1);105*ones(50,1);80*ones(50,1)],100,1};

% ---------- 生成 .mat 与 .xlsx（每用例双输入） ----------
for i = 1:numel(C)
    t = (0:dt:3)';
    ds = buildDS(C(i).sigs, t);
    matFile = fullfile(wf, [C(i).name '.mat']);
    dsVar = ds; %#ok<NASGU>
    save(matFile, 'dsVar');
    % Excel：时间 + 各输入信号（boolean 转 0/1）
    temp = ds{1}.Data; speed = double(ds{2}.Data); ign = double(ds{3}.Data);
    T = table(t, single(temp), uint16(speed), ign, ...
        'VariableNames', {'Time','f32CoolantTemp','u16VehicleSpeed','bIgnOn'});
    writetable(T, fullfile(wf, [C(i).name '.xlsx']));
    fprintf('inputs %s (.mat + .xlsx)\n', C(i).name);
end

% ---------- 工具链生成 .mldatx ----------
tfv = fullfile(wf, 'MIL_ECFC_VNV.mldatx');
if exist(tfv, 'file'), delete(tfv); end
for i = 1:numel(C)
    vnv.internal.agentic.test_create(Component=mdl, TestType='baseline', ...
        TestScope='model', TestFile=tfv, SuiteName='MIL_ECFC', TestName=C(i).name);
end
for i = 1:numel(C)
    vnv.internal.agentic.test_edit(TestFile=tfv, SuiteName='MIL_ECFC', ...
        TestCaseName=C(i).name, StopTime='3', InputFile=fullfile(wf,[C(i).name '.mat']));
end
fprintf('TEST FILE: %s (%d cases)\n', tfv, numel(C));
disp('mil_v2_create done');

function ds = buildDS(sigs, t)
names = {'f32CoolantTemp','u16VehicleSpeed','bIgnOn'};
types = {'single','uint16','boolean'};
ds = Simulink.SimulationData.Dataset;
for i = 1:3
    v = sigs{i};
    if isscalar(v), v = repmat(v, numel(t), 1); end
    v = v(:);
    if numel(v) < numel(t), v = [v; repmat(v(end), numel(t)-numel(v), 1)]; end
    if numel(v) > numel(t), v = v(1:numel(t)); end
    if strcmp(types{i},'boolean'), v = logical(v); else, v = cast(v, types{i}); end
    ts = timeseries(v, t); ts.Name = names{i};
    ds = ds.addElement(ts, names{i});
end
end
