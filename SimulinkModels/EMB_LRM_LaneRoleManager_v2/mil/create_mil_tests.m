%% create_mil_tests.m - 按需求生成 MIL 测试（harness + Test Manager 用例 + 覆盖配置）
mdl = 'EMB_LRM_LaneRoleManager_v2';
wf = '/Users/wangtianqi/SimulinkModels/EMB_LRM_LaneRoleManager_v2/mil';
if ~exist(wf, 'dir'), mkdir(wf); end
if ~bdIsLoaded(mdl)
    open_system(['/Users/wangtianqi/SimulinkModels/EMB_LRM_LaneRoleManager_v2/' mdl '.slx']);
end
dt = 0.01;

% ---------- 1) 正式 Test Manager harness ----------
harnessName = 'Harness_LRM';
if isempty(sltest.harness.find(mdl))
    sltest.harness.create(mdl, 'Name', harnessName, 'Source', 'Inport', ...
        'Sink', 'Outport', 'VerificationMode', 'Normal');
end
fprintf('harness: %s\n', strjoin(sltest.harness.find(mdl), ', '));

% ---------- 2) Test File / Suite ----------
tfFile = fullfile(wf, 'MIL_EMB_LRM_LaneRoleManager_v2.mldatx');
if exist(tfFile, 'file'), delete(tfFile); end
sltest.testmanager.clear;
tf = sltest.testmanager.TestFile(tfFile);
ts = createTestSuite(tf, 'MIL_LRM');

% ---------- 3) 文件级覆盖设置：decision/condition/MCDC ----------
cs = tf.getCoverageSettings();
cs.RecordCoverage = true;
ms = cs.MetricSettings;
fn = fieldnames(ms);
fprintf('metric fields: %s\n', strjoin(fn, ', '));
for i = 1:numel(fn)
    if contains(lower(fn{i}), 'decision') || contains(lower(fn{i}), 'condition') || ...
       contains(lower(fn{i}), 'mcdc')
        ms.(fn{i}) = true;
    end
end
cs.MetricSettings = ms;
tf.setProperty('CoverageSettings', cs);

% ---------- 4) 用例定义（需求驱动） ----------
% 输入顺序: u8OperMode, u8LclLaneOperMode, u8RmtLaneRole, u8LclFitnessScore,
%           u8RmtFitnessScore, u8LclIlcStatus, bLclIlcStatusQf, u8HeartbeatLostCount
C = struct([]);
add = @(n,d,s,sigs) deal(struct('name',n,'desc',d,'stop',s,'sigs',{sigs}));

hbRamp = @(n) mod(0:(n-1), 256);

C(1).name = 'TC01_HB_HealthyNormal'; C(1).desc = 'R1 心跳计数连续递增(0..255 回卷)，HB_Failure=0，链路保持 OPERATING';
C(1).stop = 1.0; C(1).sigs = {1,1,0,100,100,1,0,hbRamp(100)};

C(2).name = 'TC02_HB_Stuck_HbLost'; C(2).desc = 'R1/R6 心跳计数停滞，20 周期后进入 HbLost(LaneStatus=2)';
C(2).stop = 0.5; C(2).sigs = {1,1,0,100,100,1,0,5};

C(3).name = 'TC03_ILC_QF_FaultOnly'; C(3).desc = 'R2/R4 ILC 质量异常仅 QF=1：LaneStatusCntrInPrgs=1，状态保持 INITIALISING';
C(3).stop = 0.4; C(3).sigs = {1,1,0,100,100,1,1,hbRamp(40)};

C(4).name = 'TC04_BothFaults_Failed'; C(4).desc = 'R7 心跳+ILC 同时异常，双计数器同步，20 周期后进入 Failed(LaneStatus=3)，Failed 优先级高于 HbLost';
C(4).stop = 0.5; C(4).sigs = {1,1,0,100,100,1,1,5};

C(5).name = 'TC05_FailedRecovery_Operating'; C(5).desc = 'R6/R7 Failed 后心跳恢复正常，状态回到 OPERATING';
C(5).stop = 1.2;
hb5 = [5*ones(40,1); hbRamp(80)'];
qf5 = [true(40,1); false(80,1)];
C(5).sigs = {1,1,0,100,100,1,qf5,hb5};

C(6).name = 'TC06_OperInit_NoMonitor'; C(6).desc = 'R4 OPER_MODE=INIT：监控不激活，即使心跳故障 LaneStatus 保持 INITIALISING';
C(6).stop = 0.3; C(6).sigs = {0,0,0,100,100,1,0,5};

C(7).name = 'TC07_Arb_Master'; C(7).desc = 'R8 初始化等待后本地健康度>远程，仲裁为 MASTER(LaneRole=2)，ACTV CTRLR=1';
C(7).stop = 1.5; C(7).sigs = {1,1,0,200,100,1,0,hbRamp(150)};

C(8).name = 'TC08_Arb_Fallback_RmtMaster'; C(8).desc = 'R8 远程角色=MASTER，本地仲裁为 FALLBACK(LaneRole=3)';
C(8).stop = 0.4; C(8).sigs = {1,1,2,100,100,1,0,hbRamp(40)};

C(9).name = 'TC09_Shutdown'; C(9).desc = 'R8 本链路运行模式=SHUTTING_DOWN，角色=SHUTTING_DOWN(LaneRole=6)';
C(9).stop = 0.3; C(9).sigs = {1,5,0,100,100,1,0,hbRamp(30)};

C(10).name = 'TC10_Disabled'; C(10).desc = 'R8 本地健康度=62(禁用)，角色=DISABLED(LaneRole=5)';
C(10).stop = 0.3; C(10).sigs = {1,1,0,62,100,1,0,hbRamp(30)};

C(11).name = 'TC11_MasterToSupport'; C(11).desc = 'R8 MASTER 下 ILC 故障且本地<远程(条件A)，直接降级 SUPPORT(LaneRole=4)';
C(11).stop = 2.0;
lcl11 = [200*ones(130,1); 50*ones(70,1)];
ilc11 = [ones(130,1); zeros(70,1)];
C(11).sigs = {1,1,0,lcl11,100,ilc11,0,hbRamp(200)};

C(12).name = 'TC12_FallbackToMaster_StsFailed'; C(12).desc = 'R8 FALLBACK 下 LaneStatus=FAILED(条件C)，立即升级 MASTER';
C(12).stop = 1.0;
qf12 = [false(60,1); true(40,1)];
hb12 = [hbRamp(60)'; 5*ones(40,1)];
C(12).sigs = {1,1,2,100,100,1,qf12,hb12};

C(13).name = 'TC13_LSP_Debounce'; C(13).desc = 'R9 角色切换触发 LaneSwtInProgs=1，防抖 10 周期后复位 0';
C(13).stop = 1.8;
rmt13 = [zeros(150,1); 2*ones(30,1)];
C(13).sigs = {1,1,rmt13,200,100,1,0,hbRamp(180)};

C(14).name = 'TC14_LSP_AnyTimer'; C(14).desc = 'R9 角色仍 INIT(LaneRoleCntrInPrgs=1)，切换标志持续 1';
C(14).stop = 0.3; C(14).sigs = {1,1,0,100,100,1,0,hbRamp(30)};

C(15).name = 'TC15_RmtStsMapping'; C(15).desc = 'R10 远控状态映射：DISABLED->FAILED(3)，FITNESS=255->HB_LOST(2)，INIT->INITIALISING(0)，MASTER->OPERATING(1)';
C(15).stop = 1.6;
rmt15 = [5*ones(40,1); 2*ones(40,1); 1*ones(40,1); 2*ones(40,1)];
fit15 = [100*ones(40,1); 255*ones(40,1); 100*ones(40,1); 100*ones(40,1)];
C(15).sigs = {1,1,rmt15,100,fit15,1,0,hbRamp(160)};

% ---------- 5) 创建用例 ----------
for i = 1:numel(C)
    tc = createTestCase(ts, 'baseline', C(i).name);
    tc.setProperty('Model', mdl);
    tc.setProperty('HarnessOwner', mdl);
    tc.setProperty('HarnessName', harnessName);
    tc.setProperty('StopTime', C(i).stop);
    tc.setProperty('Description', C(i).desc);
    t = (0:dt:C(i).stop)';
    ds = buildDS(C(i).sigs, t, dt);
    matFile = fullfile(wf, [C(i).name '.mat']);
    dsVar = ds; %#ok<NASGU>
    save(matFile, 'dsVar');
    tc.addInput(matFile);
    fprintf('case %s created (stop=%g)\n', C(i).name, C(i).stop);
end
tf.saveToFile;
fprintf('TEST FILE: %s\n', tfFile);
disp('create_mil_tests done');

function ds = buildDS(sigs, t, dt)
names = {'u8OperMode','u8LclLaneOperMode','u8RmtLaneRole','u8LclFitnessScore', ...
         'u8RmtFitnessScore','u8LclIlcStatus','bLclIlcStatusQf','u8HeartbeatLostCount'};
types = {'uint8','uint8','uint8','uint8','uint8','uint8','boolean','uint8'};
ds = Simulink.SimulationData.Dataset;
for i = 1:8
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
