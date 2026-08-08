%% 方式A：为每个用例捕获 baseline（golden）
wf = '/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/mil';
tfFile = fullfile(wf, 'MIL_ECFC_Harness.mldatx');
sltest.testmanager.clear;
tf = sltest.testmanager.TestFile(tfFile);
ts = getTestSuiteByName(tf, 'MIL_ECFC');
tcs = ts.getTestCases();
for i = 1:numel(tcs)
    tc = tcs(i);
    baseFile = fullfile(wf, ['base_' tc.Name '.mat']);
    if exist(baseFile, 'file'), continue; end
    tc.captureBaselineCriteria(baseFile, false);
    fprintf('captured %s\n', tc.Name);
end
disp('mil_a_capture done');
