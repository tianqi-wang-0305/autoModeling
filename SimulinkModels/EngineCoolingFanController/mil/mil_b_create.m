%% 方式B：testing-simulink-models 的 vnv 工具链生成用例（model scope）
addpath('/Users/wangtianqi/.matlab/agentic-toolkits/simulink/skills-catalog/verification-validation-and-test/testing-simulink-models/scripts');
wf = '/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/mil';
tfv = fullfile(wf, 'MIL_ECFC_VNV.mldatx');
C = { 'TC01_OffBelowLo', 'TC02_HoldOff_Deadband', 'TC03_OnAboveHi', 'TC04_HoldOn_Deadband', ...
      'TC05_ResetBelowLo', 'TC06_IgnOff_Gate', 'TC07_Fault_HighTemp', 'TC08_FaultRecovery', ...
      'TC09_Boundary_Exact', 'TC10_Hysteresis_Cycle' };
% 已创建 TC01；创建其余
for i = 2:numel(C)
    try
        r = vnv.internal.agentic.test_create(Component='EngineCoolingFanController', ...
            TestType='baseline', TestScope='model', TestFile=tfv, ...
            SuiteName='MIL_ECFC', TestName=C{i});
        fprintf('created %s\n', C{i});
    catch e
        fprintf('create %s ERR: %s\n', C{i}, e.message);
    end
end
% 配置 StopTime 与输入
for i = 1:numel(C)
    matFile = fullfile(wf, [C{i} '.mat']);
    if ~exist(matFile, 'file')
        fprintf('missing input file for %s\n', C{i});
        continue;
    end
    try
        vnv.internal.agentic.test_edit(TestFile=tfv, SuiteName='MIL_ECFC', ...
            TestCaseName=C{i}, StopTime='2', InputFile=matFile);
        fprintf('edited %s\n', C{i});
    catch e
        fprintf('edit %s ERR: %s\n', C{i}, e.message);
    end
end
disp('mil_b_create done');
