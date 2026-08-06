new_system('EMB_LRM');
add_block('built-in/SubSystem', 'EMB_LRM/SS');
try
    helper('EMB_LRM/SS');
    fprintf('FUNC TEST OK\n');
catch ME
    fprintf('FUNC TEST ERR: %s\n', ME.message);
end
close_system('EMB_LRM', 0);

function helper(parent)
    add_block('simulink/Discrete/Unit Delay', [parent '/UD1']);
    add_block('simulink/Math Operations/Sum', [parent '/S1']);
    add_line(parent, 'UD1/1', 'S1/1', 'autorouting', 'on');
end
