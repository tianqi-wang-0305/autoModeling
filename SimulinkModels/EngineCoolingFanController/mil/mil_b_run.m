%% 方式B：vnv test_run 执行并输出结果
addpath('/Users/wangtianqi/.matlab/agentic-toolkits/simulink/skills-catalog/verification-validation-and-test/testing-simulink-models/scripts');
wf = '/Users/wangtianqi/SimulinkModels/EngineCoolingFanController/mil';
tfv = fullfile(wf, 'MIL_ECFC_VNV.mldatx');
try
    r = vnv.internal.agentic.test_run(tfv, save_to=fullfile(wf, 'mil_b_results.yaml'));
    disp(r);
catch e
    fprintf('test_run ERR: %s\n', e.message);
end
disp('mil_b_run done');
