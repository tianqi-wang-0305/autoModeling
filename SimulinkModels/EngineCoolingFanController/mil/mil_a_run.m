%% 方式A：执行全部用例并汇总结果与覆盖率
wf = '/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/mil';
tfFile = fullfile(wf, 'MIL_ECFC_Harness.mldatx');
sltest.testmanager.clear;
tf = sltest.testmanager.TestFile(tfFile);
result = tf.run();
fprintf('fileResults=%d suiteResults=%d caseResults=%d\n', ...
    numel(result.getTestFileResults()), numel(result.getTestSuiteResults()), ...
    numel(result.getTestCaseResults()));
fr = result.getTestFileResults();
for i = 1:numel(fr)
    fprintf('FILE %s: %s\n', fr(i).Name, fr(i).Outcome);
end
sr = result.getTestSuiteResults();
for i = 1:numel(sr)
    fprintf('SUITE %s: %s\n', sr(i).Name, sr(i).Outcome);
end
tcrs = result.getTestCaseResults();
for i = 1:numel(tcrs)
    fprintf('CASE %s: %s\n', tcrs(i).Name, tcrs(i).Outcome);
end
try
    cr = result.getCoverageResults();
    cvd = cr.cvdata;
    fprintf('decision=%.2f%% condition=%.2f%% mcdc=%.2f%%\n', ...
        cvd.decisioncoverage, cvd.conditioncoverage, cvd.mcdccoverage);
catch e
    fprintf('coverage read err: %s\n', e.message);
end
disp('mil_a_run done');
