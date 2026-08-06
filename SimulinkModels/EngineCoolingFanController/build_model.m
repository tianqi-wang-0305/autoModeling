% Build EngineCoolingFanController.slx following simulink-modeling-style
% standards: {type}{Name} ports, cal_{type}{Name} calibrations, single
% precision floats, basic blocks only, layered architecture.

model = 'EngineCoolingFanController';
outDir = '/Users/wangtianqi/SimulinkModels/EngineCoolingFanController';

if bdIsLoaded(model)
    close_system(model, 0);
end
new_system(model);

%% Top level: ports + MainSubsystem (wiring happens last)
add_block('built-in/Inport', [model '/f32CoolantTemp']);
add_block('built-in/Inport', [model '/u16VehicleSpeed']);
add_block('built-in/Inport', [model '/bIgnOn']);
add_block('built-in/Outport', [model '/u8FanSpeedCmd']);
add_block('built-in/Outport', [model '/bFaultFlag']);
add_block('built-in/SubSystem', [model '/MainSubsystem']);

set_param([model '/f32CoolantTemp'], 'OutDataTypeStr', 'single');
set_param([model '/u16VehicleSpeed'], 'OutDataTypeStr', 'uint16');
set_param([model '/bIgnOn'], 'OutDataTypeStr', 'boolean');
set_param([model '/u8FanSpeedCmd'], 'OutDataTypeStr', 'uint8');
set_param([model '/bFaultFlag'], 'OutDataTypeStr', 'boolean');

%% MainSubsystem: mirror ports + four role subsystems
ms = [model '/MainSubsystem'];
add_block('built-in/Inport', [ms '/f32CoolantTemp']);
add_block('built-in/Inport', [ms '/u16VehicleSpeed']);
add_block('built-in/Inport', [ms '/bIgnOn']);
add_block('built-in/Outport', [ms '/u8FanSpeedCmd']);
add_block('built-in/Outport', [ms '/bFaultFlag']);
add_block('built-in/SubSystem', [ms '/SignalAcquisition']);
add_block('built-in/SubSystem', [ms '/FanHysteresisControl']);
add_block('built-in/SubSystem', [ms '/FaultDetection']);
add_block('built-in/SubSystem', [ms '/OutputArbitration']);

set_param([ms '/f32CoolantTemp'], 'OutDataTypeStr', 'single');
set_param([ms '/u16VehicleSpeed'], 'OutDataTypeStr', 'uint16');
set_param([ms '/bIgnOn'], 'OutDataTypeStr', 'boolean');
set_param([ms '/u8FanSpeedCmd'], 'OutDataTypeStr', 'uint8');
set_param([ms '/bFaultFlag'], 'OutDataTypeStr', 'boolean');

%% SignalAcquisition: pass-through (type conversion happens here when needed)
sa = [ms '/SignalAcquisition'];
add_block('built-in/Inport', [sa '/f32CoolantTemp']);
add_block('built-in/Inport', [sa '/u16VehicleSpeed']);
add_block('built-in/Inport', [sa '/bIgnOn']);
add_block('built-in/Outport', [sa '/f32CoolantTempOut']);
add_block('built-in/Outport', [sa '/u16VehicleSpeedOut']);
add_block('built-in/Outport', [sa '/bIgnOnOut']);
add_line(sa, 'f32CoolantTemp/1', 'f32CoolantTempOut/1', 'autorouting', 'on');
add_line(sa, 'u16VehicleSpeed/1', 'u16VehicleSpeedOut/1', 'autorouting', 'on');
add_line(sa, 'bIgnOn/1', 'bIgnOnOut/1', 'autorouting', 'on');

%% FanHysteresisControl: hysteresis deadband with basic blocks
fh = [ms '/FanHysteresisControl'];
add_block('built-in/Inport', [fh '/f32CoolantTemp']);
add_block('built-in/Outport', [fh '/bFanOn']);
add_block('simulink/Sources/Constant', [fh '/cal_f32TempThresh']);
add_block('simulink/Sources/Constant', [fh '/cal_f32HystHalf']);
add_block('simulink/Math Operations/Sum', [fh '/Sum_HiTh']);
add_block('simulink/Math Operations/Sum', [fh '/Sum_LoTh']);
add_block('simulink/Logic and Bit Operations/Relational Operator', [fh '/Relop_AboveHi']);
add_block('simulink/Logic and Bit Operations/Relational Operator', [fh '/Relop_BelowLo']);
add_block('simulink/Logic and Bit Operations/Logical Operator', [fh '/Logic_NotBelow']);
add_block('simulink/Logic and Bit Operations/Logical Operator', [fh '/Logic_Hold']);
add_block('simulink/Logic and Bit Operations/Logical Operator', [fh '/Logic_Set']);
add_block('simulink/Discrete/Unit Delay', [fh '/Delay_FanState']);

set_param([fh '/cal_f32TempThresh'], 'Value', 'cal_f32TempThresh', 'OutDataTypeStr', 'single');
set_param([fh '/cal_f32HystHalf'], 'Value', 'cal_f32HystHalf', 'OutDataTypeStr', 'single');
set_param([fh '/Sum_HiTh'], 'Inputs', '++', 'OutDataTypeStr', 'single');
set_param([fh '/Sum_LoTh'], 'Inputs', '+-', 'OutDataTypeStr', 'single');
set_param([fh '/Relop_AboveHi'], 'Operator', '>');
set_param([fh '/Relop_BelowLo'], 'Operator', '<');
set_param([fh '/Logic_NotBelow'], 'Operator', 'NOT', 'Inputs', '1');
set_param([fh '/Logic_Hold'], 'Operator', 'AND');
set_param([fh '/Logic_Set'], 'Operator', 'OR');
set_param([fh '/Delay_FanState'], 'InitialCondition', '0');

add_line(fh, 'cal_f32TempThresh/1', 'Sum_HiTh/1', 'autorouting', 'on');
add_line(fh, 'cal_f32HystHalf/1', 'Sum_HiTh/2', 'autorouting', 'on');
add_line(fh, 'cal_f32TempThresh/1', 'Sum_LoTh/1', 'autorouting', 'on');
add_line(fh, 'cal_f32HystHalf/1', 'Sum_LoTh/2', 'autorouting', 'on');
add_line(fh, 'f32CoolantTemp/1', 'Relop_AboveHi/1', 'autorouting', 'on');
add_line(fh, 'Sum_HiTh/1', 'Relop_AboveHi/2', 'autorouting', 'on');
add_line(fh, 'f32CoolantTemp/1', 'Relop_BelowLo/1', 'autorouting', 'on');
add_line(fh, 'Sum_LoTh/1', 'Relop_BelowLo/2', 'autorouting', 'on');
add_line(fh, 'Relop_BelowLo/1', 'Logic_NotBelow/1', 'autorouting', 'on');
add_line(fh, 'Delay_FanState/1', 'Logic_Hold/1', 'autorouting', 'on');
add_line(fh, 'Logic_NotBelow/1', 'Logic_Hold/2', 'autorouting', 'on');
add_line(fh, 'Relop_AboveHi/1', 'Logic_Set/1', 'autorouting', 'on');
add_line(fh, 'Logic_Hold/1', 'Logic_Set/2', 'autorouting', 'on');
add_line(fh, 'Logic_Set/1', 'bFanOn/1', 'autorouting', 'on');
add_line(fh, 'Logic_Set/1', 'Delay_FanState/1', 'autorouting', 'on');

%% FaultDetection: high-temperature fault
fd = [ms '/FaultDetection'];
add_block('built-in/Inport', [fd '/f32CoolantTemp']);
add_block('built-in/Outport', [fd '/bFaultFlag']);
add_block('simulink/Sources/Constant', [fd '/cal_f32TempHighLim']);
add_block('simulink/Logic and Bit Operations/Relational Operator', [fd '/Relop_Fault']);
set_param([fd '/cal_f32TempHighLim'], 'Value', 'cal_f32TempHighLim', 'OutDataTypeStr', 'single');
set_param([fd '/Relop_Fault'], 'Operator', '>');
add_line(fd, 'f32CoolantTemp/1', 'Relop_Fault/1', 'autorouting', 'on');
add_line(fd, 'cal_f32TempHighLim/1', 'Relop_Fault/2', 'autorouting', 'on');
add_line(fd, 'Relop_Fault/1', 'bFaultFlag/1', 'autorouting', 'on');

%% OutputArbitration: enable gating + fan command switch
oa = [ms '/OutputArbitration'];
add_block('built-in/Inport', [oa '/bFanOn']);
add_block('built-in/Inport', [oa '/bFaultFlag']);
add_block('built-in/Inport', [oa '/bIgnOn']);
add_block('built-in/Inport', [oa '/u16VehicleSpeed']);
add_block('built-in/Outport', [oa '/u8FanSpeedCmd']);
add_block('built-in/Outport', [oa '/bFaultFlagOut']);
add_block('simulink/Logic and Bit Operations/Logical Operator', [oa '/Logic_FanGate']);
add_block('simulink/Sources/Constant', [oa '/cal_u8FanSpeedCmd']);
add_block('simulink/Sources/Constant', [oa '/Zero_FanCmd']);
add_block('simulink/Signal Routing/Switch', [oa '/Switch_FanCmd']);
add_block('simulink/Sinks/Scope', [oa '/Scope_VehicleSpeedMonitor']);

set_param([oa '/Logic_FanGate'], 'Operator', 'AND');
set_param([oa '/cal_u8FanSpeedCmd'], 'Value', 'cal_u8FanSpeedCmd', 'OutDataTypeStr', 'uint8');
set_param([oa '/Zero_FanCmd'], 'Value', '0', 'OutDataTypeStr', 'uint8');
set_param([oa '/Switch_FanCmd'], 'Criteria', 'u2 >= Threshold', 'Threshold', '0.5', 'OutDataTypeStr', 'uint8');

add_line(oa, 'bIgnOn/1', 'Logic_FanGate/1', 'autorouting', 'on');
add_line(oa, 'bFanOn/1', 'Logic_FanGate/2', 'autorouting', 'on');
add_line(oa, 'cal_u8FanSpeedCmd/1', 'Switch_FanCmd/1', 'autorouting', 'on');
add_line(oa, 'Zero_FanCmd/1', 'Switch_FanCmd/3', 'autorouting', 'on');
add_line(oa, 'Logic_FanGate/1', 'Switch_FanCmd/2', 'autorouting', 'on');
add_line(oa, 'Switch_FanCmd/1', 'u8FanSpeedCmd/1', 'autorouting', 'on');
add_line(oa, 'bFaultFlag/1', 'bFaultFlagOut/1', 'autorouting', 'on');
add_line(oa, 'u16VehicleSpeed/1', 'Scope_VehicleSpeedMonitor/1', 'autorouting', 'on');

%% Wire MainSubsystem internals (ports now exist)
add_line(ms, 'f32CoolantTemp/1', 'SignalAcquisition/1', 'autorouting', 'on');
add_line(ms, 'u16VehicleSpeed/1', 'SignalAcquisition/2', 'autorouting', 'on');
add_line(ms, 'bIgnOn/1', 'SignalAcquisition/3', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/1', 'FanHysteresisControl/1', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/1', 'FaultDetection/1', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/2', 'OutputArbitration/4', 'autorouting', 'on');
add_line(ms, 'SignalAcquisition/3', 'OutputArbitration/3', 'autorouting', 'on');
add_line(ms, 'FanHysteresisControl/1', 'OutputArbitration/1', 'autorouting', 'on');
add_line(ms, 'FaultDetection/1', 'OutputArbitration/2', 'autorouting', 'on');
add_line(ms, 'OutputArbitration/1', 'u8FanSpeedCmd/1', 'autorouting', 'on');
add_line(ms, 'OutputArbitration/2', 'bFaultFlag/1', 'autorouting', 'on');

%% Wire top level (MainSubsystem now has ports)
add_line(model, 'f32CoolantTemp/1', 'MainSubsystem/1', 'autorouting', 'on');
add_line(model, 'u16VehicleSpeed/1', 'MainSubsystem/2', 'autorouting', 'on');
add_line(model, 'bIgnOn/1', 'MainSubsystem/3', 'autorouting', 'on');
add_line(model, 'MainSubsystem/1', 'u8FanSpeedCmd/1', 'autorouting', 'on');
add_line(model, 'MainSubsystem/2', 'bFaultFlag/1', 'autorouting', 'on');

%% Save
save_system(model, fullfile(outDir, [model '.slx']));
fprintf('Model saved to %s\n', fullfile(outDir, [model '.slx']));
close_system(model, 0);
