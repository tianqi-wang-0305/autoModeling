%% 方式V2：为 13 条 vnv 用例捕获 baseline（逐个，含错误定位）
wf = '/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/mil';
sltest.testmanager.clear;
tf = sltest.testmanager.TestFile(fullfile(wf, 'MIL_ECFC_VNV.mldatx'));
ts = getTestSuiteByName(tf, 'MIL_ECFC');
names = {'TC01_OffBelowLo','TC02_HoldOff_Deadband','TC03_OnAboveHi', ...
         'TC04_HoldOn_Deadband','TC05_ResetBelowLo','TC06_IgnOff_Gate', ...
         'TC07_Fault_HighTemp','TC08_FaultRecovery','TC09_Boundary_Exact', ...
         'TC10_Hysteresis_Cycle','MC11_SetHold_TruthTable', ...
         'MC12_FanGate_TruthTable','MC13_Fault_TruthTable'};
for i = 1:numel(names)
    tc = getTestCaseByName(ts, names{i});
    baseFile = fullfile(wf, ['base_v2_' names{i} '.mat']);
    try
        tc.captureBaselineCriteria(baseFile, false);
        fprintf('captured %s\n', names{i});
    catch e
        fprintf('FAIL %s: %s\n', names{i}, e.message);
        for k = 1:numel(e.stack)
            fprintf('   at %s:%d\n', e.stack(k).name, e.stack(k).line);
        end
    end
end
disp('mil_v2_capture done');
