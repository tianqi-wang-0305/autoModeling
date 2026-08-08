%% 探测 sltest API：SUT 设置、覆盖设置、harness 创建
mdl = 'EMB_LRM_LaneRoleManager_v2';
if ~bdIsLoaded(mdl)
    open_system(['/Users/wangtianqi/SimulinkModels/EMB_LRM_LaneRoleManager_v2/' mdl '.slx']);
end
probeFile = '/Users/wangtianqi/SimulinkModels/EMB_LRM_LaneRoleManager_v2/_probe.mldatx';
sltest.testmanager.clear;
try
    sltest.harness.create(mdl, 'Name', 'Harness_LRM', 'Source', 'Model', 'Open', false);
    fprintf('HARNESS create OK: %s\n', sltest.harness.get(mdl));
catch e
    fprintf('HARNESS err: %s\n', e.message);
end
tf = sltest.testmanager.TestFile(probeFile);
ts = createTestSuite(tf, 'S');
tc = createTestCase(ts, 'baseline', 'C1');
try, v = tc.getProperty('Model'); fprintf('getProperty Model = %s\n', v); catch e, fprintf('getProp Model err: %s\n', e.message); end
try, tc.setProperty('Model', mdl); fprintf('setProperty Model OK\n'); catch e, fprintf('setProp Model err: %s\n', e.message); end
try, tc.setProperty('HarnessName', 'Harness_LRM'); fprintf('setProperty HarnessName OK\n'); catch e, fprintf('setProp Harness err: %s\n', e.message); end
try, v = tc.getProperty('StopTime'); fprintf('StopTime prop = %s\n', v); catch e, fprintf('StopTime err: %s\n', e.message); end
try, tc.setProperty('StopTime', '2'); fprintf('setProperty StopTime OK\n'); catch e, fprintf('setProp StopTime err: %s\n', e.message); end
try
    cs = tf.getCoverageSettings();
    cs.RecordCoverage = true;
    disp(cs.MetricSettings);
    fprintf('COV record OK\n');
catch e
    fprintf('COV err: %s\n', e.message);
end
% 清理
tf.close;
sltest.testmanager.clear;
try
    sltest.harness.delete(mdl, 'Harness_LRM');
    fprintf('HARNESS deleted\n');
catch e
    fprintf('HARNESS delete err: %s\n', e.message);
end
delete(probeFile);
