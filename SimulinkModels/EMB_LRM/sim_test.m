% Simulation test for EMB_LRM: verify MLR role transitions (INIT -> MASTER ->
% FALLBACK), LSP switch flag, ACTV CTRLR and RMT LANE STS passthrough.

outDir = '/Users/wangtianqi/SimulinkModels/EMB_LRM';
model = 'EMB_LRM';

% Calibration values (workspace variables referenced by Constant blocks)
cal_u8RmtLaneFailThd = uint8(20);
cal_u8RoleChangeDebounceTime = uint8(10);
cal_u16LaneInitWaitTime = uint16(100);
cal_u16TakeoverTime = uint16(50);
cal_u16FallbackSupportSwapTime = uint16(50);
cal_u16FailWatchWindow = uint16(20);
cal_u16MasterFallbackSwapThd = uint16(20);

% Input time series (2 s @ 10 ms)
t = (0:0.01:2.5)';
n = numel(t);
idxDeg = t >= 1.5;   % after 1.5 s: degrade fitness and keep remote FALLBACK

in.time = t;
in.signals(1).values = uint8(t < 0.02);          % u8OperMode: 0 (INIT) until 0.02, then 1
in.signals(1).dimensions = 1;
in.signals(2).values = uint8(ones(n, 1));        % u8LclLaneOperMode: NORMAL_OPERATION
in.signals(2).dimensions = 1;
in.signals(3).values = uint8(3 * ones(n, 1));    % u8RmtLaneRole: FALLBACK
in.signals(3).dimensions = 1;
in.signals(4).values = uint8(100 * ones(n, 1));  % u8LclFitnessScore
in.signals(4).values(idxDeg) = 70;
in.signals(4).dimensions = 1;
in.signals(5).values = uint8(80 * ones(n, 1));   % u8RmtFitnessScore
in.signals(5).values(idxDeg) = 90;
in.signals(5).dimensions = 1;
in.signals(6).values = uint8(ones(n, 1));        % u8LclIlcStatus: Normal
in.signals(6).dimensions = 1;
in.signals(7).values = logical(zeros(n, 1));     % bLclIlcStatusQf: QF_Full
in.signals(7).dimensions = 1;
in.signals(8).values = uint8(mod(0:n-1, 256)');  % u8HeartbeatLostCount: continuous 0..255 wrap
in.signals(8).dimensions = 1;

load_system(fullfile(outDir, [model '.slx']));
simOut = sim(model, 'StopTime', '2.5', 'Solver', 'FixedStepDiscrete', 'FixedStep', '0.01', ...
    'LoadExternalInput', 'on', 'ExternalInput', 'in', ...
    'SaveOutput', 'on', 'OutputSaveName', 'yout', 'SaveFormat', 'StructureWithTime');

tt = simOut.yout.time;
s1 = double(simOut.yout.signals(1).values);  % bLaneSwtgInProgs
s2 = double(simOut.yout.signals(2).values);  % bActvCtrlr
s3 = double(simOut.yout.signals(3).values);  % u8RmtLaneSts
s4 = double(simOut.yout.signals(4).values);  % u8LaneRole

role = s4;
actv = s2;
swtg = s1;
rmtSts = s3;

fails = 0;
chk = @(cond, msg) deal(cond);

% 1) Early phase: INIT role
early = tt < 0.1;
if all(role(early) == 1)
    fprintf('[PASS] 0..0.1s 角色为 INIT(1)\n');
else
    fprintf('[FAIL] 0..0.1s 角色应为 INIT(1)，实际=%d\n', role(find(early, 1))); fails = fails + 1;
end

% 2) After init wait: MASTER (lcl 100 > rmt 80), active controller = 1
mid = tt >= 1.1 & tt < 1.4;
if all(role(mid) == 2) && all(actv(mid) == 1)
    fprintf('[PASS] 1.1..1.4s 角色为 MASTER(2) 且 bActvCtrlr=1\n');
else
    fprintf('[FAIL] 1.1..1.4s 期望 MASTER(2)/actv=1，实际 role=%d actv=%d\n', role(find(mid,1)), actv(find(mid,1))); fails = fails + 1;
end

% 3) After degradation: FALLBACK (lcl 70 < rmt 90, remote FALLBACK, swap counter > 20)
late = tt >= 1.8 & tt < 1.95;
if all(role(late) == 3)
    fprintf('[PASS] 1.4s 后角色降级为 FALLBACK(3)\n');
else
    fprintf('[FAIL] 1.8..1.95s 期望 FALLBACK(3)，实际=%d\n', role(find(late, 1))); fails = fails + 1;
end
if all(actv(late) == 0)
    fprintf('[PASS] 降级后 bActvCtrlr=0\n');
else
    fprintf('[FAIL] 降级后 bActvCtrlr 应为 0\n'); fails = fails + 1;
end

% 3b) Sustained Lcl<Rmt in FALLBACK -> SUPPORT after swap time (50 cycles)
sup = tt >= 2.35;
if all(role(sup) == 4)
    fprintf('[PASS] 持续 Lcl<Rmt 后角色降级为 SUPPORT(4)\n');
else
    fprintf('[FAIL] 2.35s 后期望 SUPPORT(4)，实际=%d\n', role(find(sup, 1))); fails = fails + 1;
end

% 4) LSP: switch-in-progress flag is 1 while roles change, 0 in steady state
if any(swtg(tt >= 0.95 & tt < 1.15) == 1)
    fprintf('[PASS] 角色切换期间 bLaneSwtgInProgs=1\n');
else
    fprintf('[FAIL] 角色切换期间 bLaneSwtgInProgs 应为 1\n'); fails = fails + 1;
end
if all(swtg(tt > 2.4) == 0)
    fprintf('[PASS] 稳态 bLaneSwtgInProgs=0\n');
else
    fprintf('[FAIL] 稳态 bLaneSwtgInProgs 应为 0\n'); fails = fails + 1;
end

% 5) RMT LANE STS passthrough of RMT LANE ROLE (3 = FALLBACK)
if all(rmtSts == 3)
    fprintf('[PASS] u8RmtLaneSts 直通 Rmt 角色(=3)\n');
else
    fprintf('[FAIL] u8RmtLaneSts 应为 3\n'); fails = fails + 1;
end

fprintf('\n===== 仿真验证总结: %d 项失败 =====\n', fails);
close_system(model, 0);
if fails > 0
    exit(1);
end
