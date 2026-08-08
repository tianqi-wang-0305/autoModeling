%% 方式B：捕获 baseline（直接 sltest）
wf = '/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/mil';
tfv = fullfile(wf, 'MIL_ECFC_VNV.mldatx');
sltest.testmanager.clear;
tf = sltest.testmanager.TestFile(tfv);
ts = getTestSuiteByName(tf, 'MIL_ECFC');
tcs = ts.getTestCases();
for i = 1:numel(tcs)
    tc = tcs(i);
    baseFile = fullfile(wf, ['base_vnv_' tc.Name '.mat']);
    if exist(baseFile, 'file'), continue; end
    tc.captureBaselineCriteria(baseFile, false);
    fprintf('captured %s\n', tc.Name);
end
disp('mil_b_capture done');
