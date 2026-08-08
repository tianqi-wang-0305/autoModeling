%% 方式A：sltest.harness 正式 harness + 直接 sltest 生成 MIL 用例
mdl = 'EngineCoolingFanController';
wf = '/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/mil';
if ~exist(wf, 'dir'), mkdir(wf); end
if ~bdIsLoaded(mdl)
    open_system(['/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/' mdl '.slx']);
end
% 标定变量（若不在工作区）
if ~evalin('base', 'exist(''cal_f32TempThresh'',''var'')')
    assignin('base','cal_f32TempThresh',single(90));
    assignin('base','cal_f32HystHalf',single(5));
    assignin('base','cal_f32TempHighLim',single(110));
    assignin('base','cal_u8FanSpeedCmd',uint8(80));
end
dt = 0.01;

% ---------- 1) 正式 harness ----------
harnessName = 'Harness_ECFC';
if isempty(sltest.harness.find(mdl))
    sltest.harness.create(mdl, 'Name', harnessName, 'Source', 'Inport', ...
        'Sink', 'Outport', 'VerificationMode', 'Normal');
end
disp(sltest.harness.find(mdl));

% ---------- 2) Test File / Suite / 覆盖 ----------
tfFile = fullfile(wf, 'MIL_ECFC_Harness.mldatx');
if exist(tfFile, 'file'), delete(tfFile); end
sltest.testmanager.clear;
tf = sltest.testmanager.TestFile(tfFile);
ts = createTestSuite(tf, 'MIL_ECFC');
cs = tf.getCoverageSettings();
cs.RecordCoverage = true;
cs.MetricSettings = 'cdm';   % condition + decision + MCDC

% ---------- 3) 用例定义（模型驱动：滞环/故障/门控） ----------
C = struct([]);
C(1).name='TC01_OffBelowLo';      C(1).desc='温度<低阈值(85)：风扇关，无故障'; C(1).sigs={80,100,1};
C(2).name='TC02_HoldOff_Deadband';C(2).desc='温度 80->90 进入滞环区间：保持关'; C(2).sigs={[80*ones(100,1);90*ones(100,1)],100,1};
C(3).name='TC03_OnAboveHi';       C(3).desc='温度 80->96 超过高阈值(95)：风扇开'; C(3).sigs={[80*ones(100,1);96*ones(100,1)],100,1};
C(4).name='TC04_HoldOn_Deadband'; C(4).desc='温度 96->90 滞环区间：保持开'; C(4).sigs={[96*ones(100,1);90*ones(100,1)],100,1};
C(5).name='TC05_ResetBelowLo';    C(5).desc='温度 96->84 低于低阈值：风扇关'; C(5).sigs={[96*ones(100,1);84*ones(100,1)],100,1};
C(6).name='TC06_IgnOff_Gate';     C(6).desc='温度96但点火关闭：风扇指令为0；点火开后为80'; C(6).sigs={96*ones(200,1),100,[false(100,1);true(100,1)]};
C(7).name='TC07_Fault_HighTemp';  C(7).desc='温度115>110：故障=1，风扇开'; C(7).sigs={115,100,1};
C(8).name='TC08_FaultRecovery';   C(8).desc='温度115->105：故障1->0，风扇仍开'; C(8).sigs={[115*ones(100,1);105*ones(100,1)],100,1};
C(9).name='TC09_Boundary_Exact';  C(9).desc='温度恰为95/85：不触发置位/复位，保持关'; C(9).sigs={[80*ones(60,1);95*ones(70,1);85*ones(70,1)],100,1};
C(10).name='TC10_Hysteresis_Cycle';C(10).desc='完整滞环周期 80->96->84->100：关->开->关->开'; C(10).sigs={[80*ones(50,1);96*ones(50,1);84*ones(50,1);100*ones(50,1)],100,1};

for i = 1:numel(C)
    tc = createTestCase(ts, 'baseline', C(i).name);
    tc.setProperty('Model', mdl);
    tc.setProperty(struct('HarnessOwner', mdl, 'HarnessName', harnessName));
    tc.setProperty('StopTime', 2);
    tc.Description = C(i).desc;
    t = (0:dt:2)';
    ds = buildDS(C(i).sigs, t);
    matFile = fullfile(wf, [C(i).name '.mat']);
    dsVar = ds; %#ok<NASGU>
    save(matFile, 'dsVar');
    tc.addInput(matFile);
    fprintf('case %s created\n', C(i).name);
end
tf.saveToFile;
fprintf('TEST FILE (A): %s\n', tfFile);
disp('mil_a_create done');

function ds = buildDS(sigs, t)
names = {'f32CoolantTemp','u16VehicleSpeed','bIgnOn'};
types = {'single','uint16','boolean'};
ds = Simulink.SimulationData.Dataset;
for i = 1:3
    v = sigs{i};
    if isscalar(v)
        v = repmat(v, numel(t), 1);
    end
    v = v(:);
    if numel(v) < numel(t)
        v = [v; repmat(v(end), numel(t)-numel(v), 1)];
    elseif numel(v) > numel(t)
        v = v(1:numel(t));
    end
    if strcmp(types{i}, 'boolean')
        v = logical(v);
    else
        v = cast(v, types{i});
    end
    ts = timeseries(v, t);
    ts.Name = names{i};
    ds = ds.addElement(ts, names{i});
end
end
