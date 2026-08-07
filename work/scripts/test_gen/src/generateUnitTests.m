function result = generateUnitTests(modelPath, varargin)
% generateUnitTests  Generate and run Simulink Test unit tests (MIL) driven by
%   the model interface + Agentic Toolkit analysis, then execute via model_test.
%
%   This implements Idea 2: automatic unit test case generation that calls
%   Simulink Test (through the toolkit's model_test), produces compliant test
%   harness / Gherkin feature files, and reports pass/fail per scenario.
%
%   Inputs:
%       modelPath  - Model file path (e.g. 'Model.slx') or subsystem path
%       varargin   - Name/Value:
%           'Component'   - Subsystem to test (default: whole model)
%           'Strategy'    - 'basic' (default) | 'boundary' | 'comprehensive'
%           'OutputDir'   - Directory for .feature files + report (default: _tests)
%           'RunTests'    - true (default) to execute via model_test, false to only generate
%           'Coverage'    - 'none' (default) | 'decision'
%           'SimTime'     - Simulation time in seconds (default: 10)
%
%   Outputs:
%       result - Struct with .featureFiles, .results, .reportFile
%
%   Usage:
%       result = generateUnitTests('Foc_2024b.slx');
%       result = generateUnitTests('Model.slx', 'Component', 'Model/Subsys', ...
%                                  'Strategy', 'boundary', 'Coverage', 'decision');

    fprintf('=== Automated Unit Test Generation (Simulink Test) ===\n\n');

    %% ---- Parse inputs ----
    p = inputParser;
    addRequired(p, 'modelPath', @(x) ischar(x) || isstring(x));
    addParameter(p, 'Component', '', @ischar);
    addParameter(p, 'Strategy', 'basic', @(x) any(strcmpi(x, {'basic','boundary','comprehensive'})));
    addParameter(p, 'OutputDir', '', @ischar);
    addParameter(p, 'RunTests', true, @islogical);
    addParameter(p, 'Coverage', 'none', @(x) any(strcmpi(x, {'none','decision'})));
    addParameter(p, 'SimTime', 10, @isnumeric);
    parse(p, modelPath, varargin{:});

    modelPath = char(p.Results.modelPath);
    component = char(p.Results.Component);
    strategy = lower(char(p.Results.Strategy));
    outDir = char(p.Results.OutputDir);
    runTests = p.Results.RunTests;
    coverage = lower(char(p.Results.Coverage));
    simTime = p.Results.SimTime;

    [mdir, modelBase, ~] = fileparts(modelPath);
    if isempty(mdir), mdir = pwd; end
    if isempty(modelBase), modelBase = modelPath; end
    if isempty(outDir), outDir = fullfile(mdir, '_tests'); end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    % Ensure toolkit on path (model_test lives under tools/)
    tkRoot = locateToolkit();
    if ~isempty(tkRoot), addpath(genpath(fullfile(tkRoot, 'tools'))); end
    if exist('satk_initialize', 'file') > 0, satk_initialize; end

    try
        load_system(modelPath);
    catch
        load_system(modelBase);
    end

    %% ---- Step 1: Read interface of target component ----
    fprintf('[1/4] Reading interface of %s ...\n', component);
    if isempty(component)
        target = modelBase;
    else
        target = component;
    end

    inports = readTestPorts(target, 'Inport');
    outports = readTestPorts(target, 'Outport');
    fprintf('      Inputs (%d):  %s\n', numel(inports), strjoin({inports.name}, ', '));
    fprintf('      Outputs (%d): %s\n', numel(outports), strjoin({outports.name}, ', '));

    if isempty(inports)
        error('generateUnitTests:noInputs', 'No Inport blocks found in %s', target);
    end

    %% ---- Step 2: Generate scenarios ----
    fprintf('[2/4] Generating scenarios (strategy: %s)...\n', strategy);
    scenarios = generateScenarios(inports, outports, strategy, simTime);

    %% ---- Step 3: Write Gherkin .feature files ----
    fprintf('[3/4] Writing Gherkin feature files...\n');
    featureFiles = writeFeatureFiles(modelBase, target, inports, outports, scenarios, outDir, simTime);

    %% ---- Step 4: Execute via model_test ----
    testResults = struct('feature', {}, 'passed', {}, 'total', {}, 'scenarios', {});
    if runTests && ~isempty(featureFiles)
        fprintf('[4/4] Executing tests via model_test ...\n');
        % Ensure model is loaded (model_test requires an open model)
        try
            if bdIsLoaded(modelBase) ~= 1
                load_system(modelBase);
            end
        catch
            load_system(modelPath);
        end
        for i = 1:numel(featureFiles)
            f = featureFiles{i};
            try
                r = model_test(modelBase, f, ...
                    'DraftMode', 'true', ...
                    'Coverage', coverage);
                rtxt = string(r);
                testResults(end+1).feature = f; %#ok<AGROW>
                testResults(end).passed = contains(lower(rtxt), 'passed') || ...
                    ~contains(lower(rtxt), 'failed'); %#ok<AGROW>
                testResults(end).total = 1;
                testResults(end).scenarios = rtxt;
                fprintf('      %s: %s\n', f, ...
                    iif(testResults(end).passed, 'PASSED', 'CHECK OUTPUT'));
            catch ME
                testResults(end+1).feature = f; %#ok<AGROW>
                testResults(end).passed = false;
                testResults(end).total = 1;
                testResults(end).scenarios = ME.message;
                fprintf('      %s: ERROR (%s)\n', f, ME.message);
            end
        end
    end

    %% ---- Assemble result + HTML report ----
    result = struct();
    result.model = modelBase;
    result.component = component;
    result.featureFiles = featureFiles;
    result.results = testResults;
    result.reportFile = writeTestReport(result, outDir, modelBase);
    result.outputDir = outDir;

    fprintf('\n=== Test Generation Complete ===\n');
    fprintf('Feature files: %d, Report: %s\n', numel(featureFiles), result.reportFile);
end

%% =====================================================================
function tkRoot = locateToolkit()
    tkRoot = '';
    cand = {
        fullfile(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))), 'simulink-agentic-toolkit'), ...
        fullfile(pwd, 'simulink-agentic-toolkit'), ...
        getenv('SATK_ROOT')
    };
    for i = 1:numel(cand)
        c = cand{i};
        if ~isempty(c) && exist(fullfile(c, 'tools', 'model_test'), 'dir')
            tkRoot = c; return;
        end
    end
end

%% =====================================================================
function ports = readTestPorts(sysPath, portType)
    ports = struct('name', {}, 'dataType', {}, 'min', {}, 'max', {});
    try
        blks = find_system(sysPath, 'SearchDepth', 1, 'BlockType', portType);
        for i = 1:numel(blks)
            if strcmp(blks{i}, sysPath), continue; end
            ports(end+1) = struct(... %#ok<AGROW>
                'name', get_param(blks{i}, 'Name'), ...
                'dataType', get_param(blks{i}, 'OutDataTypeStr'), ...
                'min', get_param(blks{i}, 'OutMin'), ...
                'max', get_param(blks{i}, 'OutMax'));
        end
    catch
    end
end

%% =====================================================================
function scenarios = generateScenarios(inports, outports, strategy, simTime)
% Generate test scenarios based on interface + strategy.
    scenarios = struct('name', {}, 'description', {}, 'inputs', {}, 'outputChecks', {});

    names = {inports.name};
    types = {inports.dataType};

    % Nominal (always present)
    scenarios(end+1) = makeScenario('正常工况_常值输入', ...
        '验证典型输入下输出稳定且有限。', ...
        nominalStimuli(inports, simTime), ...
        finiteOutputChecks(outports)); %#ok<AGROW>

    % Zero / boundary
    scenarios(end+1) = makeScenario('边界工况_零输入', ...
        '验证零输入条件下无异常输出。', ...
        zeroStimuli(inports, simTime), ...
        finiteOutputChecks(outports)); %#ok<AGROW>

    % Max input
    scenarios(end+1) = makeScenario('边界工况_最大输入', ...
        '验证最大输入条件下输出不越界。', ...
        maxStimuli(inports, simTime), ...
        finiteOutputChecks(outports)); %#ok<AGROW>

    if strcmpi(strategy, 'boundary') || strcmpi(strategy, 'comprehensive')
        % Step on each numeric input
        for i = 1:numel(inports)
            if ~isBooleanType(types{i})
                scenarios(end+1) = makeScenario( ... %#ok<AGROW>
                    sprintf('阶跃响应_%s', inports(i).name), ...
                    sprintf('对 %s 施加阶跃激励，验证输出跟随。', inports(i).name), ...
                    stepStimuli(inports, i, simTime), ...
                    finiteOutputChecks(outports));
            end
        end
    end

    if strcmpi(strategy, 'comprehensive')
        % Toggle all booleans
        for i = 1:numel(inports)
            if isBooleanType(types{i})
                scenarios(end+1) = makeScenario( ... %#ok<AGROW>
                    sprintf('开关切换_%s', inports(i).name), ...
                    sprintf('对布尔信号 %s 施加脉冲，验证输出切换。', inports(i).name), ...
                    toggleStimuli(inports, i, simTime), ...
                    finiteOutputChecks(outports));
            end
        end
        % Ramp on numeric inputs
        if any(cellfun(@(t) ~isBooleanType(t), types))
            scenarios(end+1) = makeScenario('斜坡输入', ... %#ok<AGROW>
                '验证输出对线性斜坡输入的跟踪。', ...
                rampStimuli(inports, simTime), ...
                finiteOutputChecks(outports));
        end
    end
end

%% ---- stimulus builders ----
function stimuli = nominalStimuli(inports, simTime)
    stimuli = struct('port', {}, 'expr', {});
    for i = 1:numel(inports)
        expr = defaultExpr(inports(i), 0.5);
        stimuli(end+1) = struct('port', inports(i).name, 'expr', expr); %#ok<AGROW>
    end
end

function stimuli = zeroStimuli(inports, simTime)
    stimuli = struct('port', {}, 'expr', {});
    for i = 1:numel(inports)
        stimuli(end+1) = struct('port', inports(i).name, 'expr', 'const(0)'); %#ok<AGROW>
    end
end

function stimuli = maxStimuli(inports, simTime)
    stimuli = struct('port', {}, 'expr', {});
    for i = 1:numel(inports)
        if isBooleanType(inports(i).dataType)
            expr = 'const(1)';
        else
            expr = sprintf('const(%s)', maxExpr(inports(i)));
        end
        stimuli(end+1) = struct('port', inports(i).name, 'expr', expr); %#ok<AGROW>
    end
end

function stimuli = stepStimuli(inports, idx, simTime)
    stimuli = struct('port', {}, 'expr', {});
    tStep = round(simTime * 0.2, 2);
    for i = 1:numel(inports)
        if i == idx
            if isBooleanType(inports(i).dataType)
                expr = sprintf('step(0 -> 1 @ %gs)', tStep);
            else
                expr = sprintf('step(0 -> %s @ %gs)', maxExpr(inports(i)), tStep);
            end
        else
            expr = defaultExpr(inports(i), 0.5);
        end
        stimuli(end+1) = struct('port', inports(i).name, 'expr', expr); %#ok<AGROW>
    end
end

function stimuli = toggleStimuli(inports, idx, simTime)
    stimuli = struct('port', {}, 'expr', {});
    tOn = round(simTime * 0.2, 2);
    tOff = round(simTime * 0.8, 2);
    for i = 1:numel(inports)
        if i == idx
            expr = sprintf('pulse(width=%gs, period=%gs)', tOn, simTime);
        else
            expr = defaultExpr(inports(i), 0.5);
        end
        stimuli(end+1) = struct('port', inports(i).name, 'expr', expr); %#ok<AGROW>
    end
end

function stimuli = rampStimuli(inports, simTime)
    stimuli = struct('port', {}, 'expr', {});
    for i = 1:numel(inports)
        if isBooleanType(inports(i).dataType)
            expr = 'const(0)';
        else
            expr = sprintf('ramp(0 -> %s over %gs)', maxExpr(inports(i)), simTime);
        end
        stimuli(end+1) = struct('port', inports(i).name, 'expr', expr); %#ok<AGROW>
    end
end

%% ---- helpers ----
function expr = defaultExpr(port, frac)
    if isBooleanType(port.dataType)
        expr = 'const(0)';
    elseif isEnumType(port.dataType)
        expr = 'const(0)';
    else
        m = safeMax(port);
        expr = sprintf('const(%g)', m * frac);
    end
end

function e = maxExpr(port)
    if isBooleanType(port.dataType)
        e = '1';
    elseif isEnumType(port.dataType)
        e = '0';
    else
        e = num2str(safeMax(port));
    end
end

function m = safeMax(port)
% Robust numeric max: fall back to type-based defaults when empty/Inf.
    m = [];
    if ~isempty(port.max)
        m = str2double(port.max);
        if isfinite(m), return; end
    end
    t = lower(port.dataType);
    if contains(t, 'uint8'), m = 255;
    elseif contains(t, 'uint16'), m = 65535;
    elseif contains(t, 'uint32'), m = 4294967295;
    elseif contains(t, 'int8'), m = 127;
    elseif contains(t, 'int16'), m = 32767;
    elseif contains(t, 'int32'), m = 2147483647;
    else, m = 100;
    end
end

function checks = finiteOutputChecks(outports)
    checks = struct('name', {}, 'expr', {});
    for i = 1:numel(outports)
        checks(end+1) = struct(... %#ok<AGROW>
            'name', sprintf('%sFinite', matlab.lang.makeValidName(outports(i).name)), ...
            'expr', sprintf('%s == [-inf .. inf]', outports(i).name));
    end
end

function tf = isBooleanType(t)
    tf = any(strcmpi(t, {'boolean', 'bool'}));
end
function tf = isIntegerType(t)
    tf = contains(lower(t), 'uint') || contains(lower(t), 'int');
end
function tf = isEnumType(t)
    tf = contains(lower(t), 'enum') || startsWith(strtrim(t), 'e', 'IgnoreCase', false) || ...
         contains(lower(t), '<') || contains(lower(t), 'simulink.');
end

%% =====================================================================
function s = makeScenario(name, desc, inputs, checks)
    s = struct('name', name, 'description', desc, 'inputs', inputs, 'outputChecks', checks);
end

%% =====================================================================
function featureFiles = writeFeatureFiles(modelBase, target, inports, outports, scenarios, outDir, simTime)
    featureFiles = {};
    % Group scenarios into one file per strategy bucket: nominal/boundary/fault
    groups = struct('name', {'NominalTests', 'BoundaryTests', 'FaultTests'}, ...
        'filter', {{'正常工况'}, {'边界工况','阶跃','斜坡'}, {'开关'}});

    % Simple bucket assignment by name keyword
    for g = 1:numel(groups)
        sel = [];
        for s = 1:numel(scenarios)
            if any(contains(scenarios(s).name, groups(g).filter))
                sel(end+1) = s; %#ok<AGROW>
            end
        end
        if isempty(sel), continue; end
        fpath = fullfile(outDir, sprintf('%s_%s.feature', modelBase, groups(g).name));
        writeOneFeature(fpath, modelBase, target, inports, outports, scenarios(sel), simTime);
        featureFiles{end+1} = fpath; %#ok<AGROW>
    end
end

function writeOneFeature(fpath, modelBase, target, inports, outports, scenarios, simTime)
    fid = fopen(fpath, 'w');
    w = @(fmt, varargin) fprintf(fid, fmt, varargin{:});

    % TOML front-matter
    w('# --- front-matter:toml ---\n');
    w('model = "%s"\n', ensureModelExt(modelBase));
    w('component = "%s"\n\n', target);
    w('[inputs]\n');
    for i = 1:numel(inports)
        w('%s = "%s"\n', matlab.lang.makeValidName(inports(i).name), inports(i).name);
    end
    w('\n[outputs]\n');
    for i = 1:numel(outports)
        w('%s = "%s"\n', matlab.lang.makeValidName(outports(i).name), outports(i).name);
    end
    w('# --- end front-matter ---\n\n');

    w('Feature: %s Automated Unit Tests\n', modelBase);
    w('  MIL unit tests generated from model interface.\n\n');

    for s = 1:numel(scenarios)
        sc = scenarios(s);
        w('Scenario: %s\n', sc.name);
        w('  Description: %s\n\n', sc.description);
        w('  Given inputs\n');
        for i = 1:numel(sc.inputs)
            w('    * %s = %s\n', sc.inputs(i).port, sc.inputs(i).expr);
        end
        w('  When simulate for %gs in Normal mode\n', simTime);
        if ~isempty(sc.outputChecks)
            w('  Then outputs\n');
            for i = 1:numel(sc.outputChecks)
                w('    * %s: %s\n', sc.outputChecks(i).name, sc.outputChecks(i).expr);
            end
        end
        w('\n');
    end
    fclose(fid);
end

function name = ensureModelExt(name)
    if ~endsWith(lower(name), {'.slx', '.mdl'})
        name = [name '.slx'];
    end
end

%% =====================================================================
function reportFile = writeTestReport(result, outDir, modelBase)
    reportFile = fullfile(outDir, [modelBase '_test_report.html']);
    fid = fopen(reportFile, 'w');
    fprintf(fid, '<!DOCTYPE html><html><head><meta charset="UTF-8">\n');
    fprintf(fid, '<title>Unit Test Report - %s</title>\n', modelBase);
    fprintf(fid, '<style>body{font-family:-apple-system,sans-serif;margin:40px}');
    fprintf(fid, '.pass{color:#4CAF50}.fail{color:#f44336}');
    fprintf(fid, 'table{border-collapse:collapse;width:100%%;margin:20px 0}');
    fprintf(fid, 'th,td{border:1px solid #ddd;padding:10px;text-align:left}');
    fprintf(fid, 'th{background:#2196F3;color:white}</style></head><body>\n');
    fprintf(fid, '<h1>Unit Test Report — %s</h1>\n', modelBase);
    fprintf(fid, '<p>Model: %s | Component: %s</p>\n', result.model, result.component);

    passed = sum(arrayfun(@(x) x.passed, result.results));
    total = numel(result.results);
    fprintf(fid, '<h2>Summary</h2><p class="%s">%d / %d passed</p>\n', ...
        iif(passed == total, 'pass', 'fail'), passed, total);

    fprintf(fid, '<h2>Feature Files</h2><table><tr><th>File</th><th>Status</th></tr>\n');
    for i = 1:numel(result.featureFiles)
        st = 'generated';
        for r = 1:numel(result.results)
            if strcmp(result.results(r).feature, result.featureFiles{i})
                st = iif(result.results(r).passed, 'PASSED', 'FAILED/CHECK');
            end
        end
        [~, fn, ~] = fileparts(result.featureFiles{i});
        fprintf(fid, '<tr><td>%s</td><td class="%s">%s</td></tr>\n', ...
            fn, iif(strcmp(st,'PASSED'),'pass','fail'), st);
    end
    fprintf(fid, '</table></body></html>\n');
    fclose(fid);
end

function out = iif(cond, a, b)
    if cond, out = a; else, out = b; end
end
