%% sim_test_new.m - 端到端仿真冒烟测试（只读，不修改模型结构）
mdl = 'EMB_LRM_LaneRoleManager';
if ~bdIsLoaded(mdl)
    open_system(mdl);
end

t = (0:0.01:0.3)';
n = numel(t);

% 场景 A：全零（应无错误运行；ILC=Failed、心跳不递增 -> 故障计数 -> Failed 状态）
names = {'u8OperMode','u8LclLaneOperMode','u8RmtLaneRole','u8LclFitnessScore', ...
         'u8RmtFitnessScore','u8LclIlcStatus','bLclIlcStatusQf','u8HeartbeatLostCount'};
    vals = {uint8(zeros(n,1)), uint8(zeros(n,1)), uint8(zeros(n,1)), uint8(zeros(n,1)), ...
            uint8(zeros(n,1)), uint8(zeros(n,1)), logical(zeros(n,1)), uint8(zeros(n,1))};

inA = Simulink.SimulationInput(mdl);
dsA = Simulink.SimulationData.Dataset;
for i = 1:numel(names)
    dsA = dsA.addElement(timeseries(vals{i}, t), names{i});
end
inA = inA.setExternalInput(dsA);
inA = inA.setModelParameter('SaveOutput', 'on');
inA = inA.setModelParameter('OutputSaveName', 'youtA');
inA = inA.setModelParameter('StopTime', '0.3');
outA = sim(inA);
yA = outA.youtA;
disp('--- Scenario A (zeros) final outputs ---');
for i = 1:yA.numElements
    el = yA{i};
    fprintf('%s = %g\n', el.Name, el.Data(end));
end

% 场景 B：正常心跳递增 + ILC Normal + 运行模式 NORMAL（应进入 Operating/INIT 链）
hb = mod(0:(n-1), 256);   % 0,1,2,...,255,0,1,... 连续递增
    valsB = {uint8(ones(n,1)), uint8(ones(n,1)), uint8(zeros(n,1)), uint8(100*ones(n,1)), ...
             uint8(100*ones(n,1)), uint8(ones(n,1)), logical(zeros(n,1)), uint8(hb)};
inB = Simulink.SimulationInput(mdl);
dsB = Simulink.SimulationData.Dataset;
for i = 1:numel(names)
    dsB = dsB.addElement(timeseries(valsB{i}, t), names{i});
end
inB = inB.setExternalInput(dsB);
inB = inB.setModelParameter('SaveOutput', 'on');
inB = inB.setModelParameter('OutputSaveName', 'youtB');
inB = inB.setModelParameter('StopTime', '0.3');
outB = sim(inB);
yB = outB.youtB;
disp('--- Scenario B (healthy heartbeat) final outputs ---');
for i = 1:yB.numElements
    el = yB{i};
    fprintf('%s = %g\n', el.Name, el.Data(end));
end
