% Apply the auto-layout rule to EMB_LRM: arrange every Simulink scope and
% the MLR Stateflow chart states.

model = 'EMB_LRM';
outDir = '/Users/wangtianqi/SimulinkModels/EMB_LRM';
load_system(fullfile(outDir, [model '.slx']));

% Inner scopes first, then parents, then root
scopes = {[model '/MainSubsystem/SignalAcquisition'], ...
          [model '/MainSubsystem/LRM_MLS_ManageLaneStatus'], ...
          [model '/MainSubsystem/LRM_MLR_ManageLaneRole'], ...
          [model '/MainSubsystem/LRM_LSP_LaneSwitchInProgs'], ...
          [model '/MainSubsystem/OutputArbitration'], ...
          [model '/MainSubsystem'], ...
          model};
for i = 1:numel(scopes)
    try
        Simulink.BlockDiagram.arrangeSystem(scopes{i});
        fprintf('arranged: %s\n', scopes{i});
    catch ME
        fprintf('arrange skipped %s: %s\n', scopes{i}, ME.message);
    end
end

% Arrange MLR chart states in a grid
rt = sfroot;
ch = find(rt, '-isa', 'Stateflow.Chart', 'Path', [model '/MainSubsystem/LRM_MLR_ManageLaneRole/MLR_STM']);
if isempty(ch)
    error('MLR chart not found');
end
st = find(ch, '-isa', 'Stateflow.State');
for i = 1:numel(st)
    st(i).Position = [50 + mod(i-1,3)*240, 50 + floor((i-1)/3)*170, 200, 110];
end
fprintf('arranged %d chart states\n', numel(st));

save_system(model, fullfile(outDir, [model '.slx']));
fprintf('Layout saved to %s\n', fullfile(outDir, [model '.slx']));
close_system(model, 0);
