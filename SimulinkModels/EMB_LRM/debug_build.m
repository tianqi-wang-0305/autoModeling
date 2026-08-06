try
    run('/Users/wangtianqi/SimulinkModels/EMB_LRM/build_model.m');
catch ME
    fprintf('ERR: %s\n', ME.message);
    if bdIsLoaded('EMB_LRM')
        p = 'EMB_LRM/MainSubsystem/LRM_MLS_ManageLaneStatus';
        try
            fprintf('Ports of Delay_HbCnt: ');
            disp(get_param([p '/Delay_HbCnt'], 'Ports'));
        catch MEp
            fprintf('Ports query ERR: %s\n', MEp.message);
        end
        try
            add_line(p, 'Delay_HbCnt/1', 'Sum_HbCnt/1', 'autorouting', 'on');
            fprintf('RETRY add_line OK\n');
        catch ME2
            fprintf('RETRY ERR: %s\n', ME2.message);
        end
    end
    rethrow(ME);
end
