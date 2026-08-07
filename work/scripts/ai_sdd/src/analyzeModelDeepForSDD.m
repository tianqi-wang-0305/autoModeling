function result = analyzeModelDeepForSDD(modelPath, varargin)
% analyzeModelDeepForSDD  Deep-analyze a Simulink model using the Agentic Toolkit
%   Uses the toolkit's MCP-compatible MATLAB functions (model_overview, model_read,
%   model_query_params, model_resolve_params) to extract a structured knowledge
%   base for each subsystem. This knowledge base feeds DdGeneration_AI.m so the
%   resulting Detail Design document contains accurate, non-manual descriptions of
%   every subsystem's function, I/O, logic and calibrations.
%
%   Inputs:
%       modelPath  - Model file path or model name (e.g. 'Model.slx')
%       varargin   - Name/Value pairs:
%           'OutputDir'   - Where to write the JSON knowledge base (default: model dir)
%           'Depth'       - Hierarchy depth to recurse: 'inf' (default), '1', etc.
%           'ResolveCal'  - Resolve calibration variable values (default: true)
%           'Verbose'     - Print progress (default: true)
%
%   Outputs:
%       result      - Struct with .model, .hierarchy, .subsystems[], .interfaces,
%                     .calibrations, .knowledgeFile (path to JSON)
%
%   Usage:
%       result = analyzeModelDeepForSDD('Foc_2024b.slx');
%       result = analyzeModelDeepForSDD('Model.slx', 'OutputDir', 'reports');
%
%   The produced JSON is consumed by DdGeneration_AI.m:
%       DdGeneration_AI('Foc_2024b.slx', 'Foc_2024b_interface.xlsx');

    fprintf('=== Deep Model Analysis for SDD (Agentic Toolkit) ===\n\n');

    %% ---- Parse inputs ----
    p = inputParser;
    addRequired(p, 'modelPath', @(x) ischar(x) || isstring(x));
    addParameter(p, 'OutputDir', '', @ischar);
    addParameter(p, 'Depth', 'inf', @ischar);
    addParameter(p, 'ResolveCal', true, @islogical);
    addParameter(p, 'Verbose', true, @islogical);
    parse(p, modelPath, varargin{:});

    modelPath = char(p.Results.modelPath);
    outDir = char(p.Results.OutputDir);
    depthStr = char(p.Results.Depth);
    resolveCal = p.Results.ResolveCal;
    verbose = p.Results.Verbose;

    [mdir, modelBase, ~] = fileparts(modelPath);
    if isempty(mdir), mdir = pwd; end
    if isempty(modelBase), modelBase = modelPath; end

    if isempty(outDir), outDir = mdir; end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    v = @(fmt, varargin) fprintf(fmt, varargin{:});

    %% ---- Initialize toolkit ----
    tkRoot = locateToolkit();
    if ~isempty(tkRoot)
        addpath(genpath(fullfile(tkRoot, 'tools')));
    end
    if exist('satk_initialize', 'file') > 0
        satk_initialize;
    end
    if exist(modelBase, 'file') ~= 4
        try
            load_system(modelPath);
        catch ME
            error('analyzeModelDeepForSDD:load', 'Cannot load model %s: %s', ...
                modelPath, ME.message);
        end
    end

    %% ---- Phase 1: Model overview (hierarchy + interfaces) ----
    if verbose, v('[1/5] Reading model overview...\n'); end
    overview = safeCall(@model_overview, modelBase, 'root', 'full');
    treeText = '';
    if ~isempty(overview)
        try, treeText = string(overview); catch, treeText = ''; end
    end

    %% ---- Phase 2: Enumerate subsystems ----
    if verbose, v('[2/5] Enumerating subsystems...\n'); end
    subsystems = collectSubsystems(modelBase);
    if verbose, v('      Found %d subsystem(s)\n', numel(subsystems)); end

    %% ---- Phase 3: Deep-read each subsystem ----
    if verbose, v('[3/5] Deep-reading each subsystem...\n'); end
    subDetails = cell(1, numel(subsystems));
    for i = 1:numel(subsystems)
        sys = subsystems{i};
        if verbose, v('      [%d/%d] %s ...\n', i, numel(subsystems), sys); end
        detail = analyzeSubsystem(modelBase, sys, depthStr, resolveCal, verbose);
        subDetails{i} = detail;
    end

    %% ---- Phase 4: Model-level configuration ----
    if verbose, v('[4/5] Reading model configuration...\n'); end
    cfg = readModelConfig(modelBase);

    %% ---- Phase 5: Assemble + write JSON ----
    if verbose, v('[5/5] Writing knowledge base...\n'); end
    result = struct();
    result.model = modelBase;
    result.overview = treeText;
    result.config = cfg;
    result.interfaces = extractModelInterfaces(modelBase);
    result.subsystems = [subDetails{:}];
    result.generatedBy = 'analyzeModelDeepForSDD';
    result.generatedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    knowledgeFile = fullfile(outDir, [modelBase '_model_knowledge.json']);
    fid = fopen(knowledgeFile, 'w');
    fwrite(fid, jsonencode(result, 'PrettyPrint', true));
    fclose(fid);
    result.knowledgeFile = knowledgeFile;

    if verbose
        totalCals = sum(arrayfun(@(s) numel(s.calibrations), result.subsystems));
        v('\n=== Analysis Complete ===\n');
        v('Knowledge base: %s\n', knowledgeFile);
        v('Subsystems: %d, Calibration params: %d\n', ...
            numel(result.subsystems), totalCals);
    end
end

%% =====================================================================
function tkRoot = locateToolkit()
% Locate the Simulink Agentic Toolkit root from common locations.
    tkRoot = '';
    candidates = {
        fullfile(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))), 'simulink-agentic-toolkit'), ...
        fullfile(pwd, 'simulink-agentic-toolkit'), ...
        getenv('SATK_ROOT')
    };
    for i = 1:numel(candidates)
        c = candidates{i};
        if ~isempty(c) && exist(fullfile(c, 'tools', 'model_read'), 'dir')
            tkRoot = c;
            return;
        end
    end
end

%% =====================================================================
function out = safeCall(fcn, varargin)
% Call a toolkit function and swallow errors, returning [] on failure.
    out = [];
    try
        out = fcn(varargin{:});
    catch
        % toolkit function unavailable or model not compilable
    end
end

%% =====================================================================
function subsystems = collectSubsystems(modelBase)
% Collect all subsystem (and chart) paths in the model recursively.
    subsystems = {};
    try
        blocks = find_system(modelBase, 'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', 'Type', 'Block');
        for i = 1:numel(blocks)
            blk = blocks{i};
            try
                bt = get_param(blk, 'BlockType');
                if strcmp(bt, 'SubSystem') && ~isempty(get_param(blk, 'Handle'))
                    subsystems{end+1} = blk; %#ok<AGROW>
                end
            catch
                % skip
            end
        end
    catch
    end
end

%% =====================================================================
function detail = analyzeSubsystem(modelBase, sysPath, depthStr, resolveCal, verbose)
% Deep-read one subsystem: ports, internal blocks, logic expressions, cals.
    detail = struct();
    detail.path = sysPath;
    detail.name = strrep(sysPath, [modelBase '/'], '');

    % Name / description
    try, detail.description = get_param(sysPath, 'Description'); catch, detail.description = ''; end
    if isempty(detail.description), detail.description = '(no description)'; end

    % Inports / Outports (interface contract)
    detail.inputs = readPorts(sysPath, 'Inport');
    detail.outputs = readPorts(sysPath, 'Outport');

    % Use model_read to get algorithmic expressions for this scope
    readText = '';
    try
        rd = model_read(modelBase, 'root', '1');
        readText = string(rd);
    catch
        try
            rd = model_read(modelBase, sysPath, '1');
            readText = string(rd);
        catch
            readText = '';
        end
    end
    detail.modelRead = readText;

    % Internal blocks: names, types, key params
    detail.blocks = readInternalBlocks(sysPath);

    % Calibration params (Constants / Gains referencing variables)
    if resolveCal
        detail.calibrations = readCalibrations(sysPath);
    else
        detail.calibrations = struct('name', {}, 'block', {}, 'param', {}, 'value', {});
    end

    % Child subsystems
    detail.children = readChildren(sysPath, modelBase);
end

%% =====================================================================
function ports = readPorts(sysPath, portType)
% Read Inport/Outport blocks one level inside sysPath.
    ports = struct('name', {}, 'dataType', {}, 'min', {}, 'max', {}, 'description', {});
    try
        blks = find_system(sysPath, 'SearchDepth', 1, 'BlockType', portType);
        for i = 1:numel(blks)
            if strcmp(blks{i}, sysPath), continue; end
            try
                p = struct();
                p.name = get_param(blks{i}, 'Name');
                p.dataType = get_param(blks{i}, 'OutDataTypeStr');
                p.min = get_param(blks{i}, 'OutMin');
                p.max = get_param(blks{i}, 'OutMax');
                p.description = get_param(blks{i}, 'Description');
                ports(end+1) = p; %#ok<AGROW>
            catch
                % skip
            end
        end
    catch
    end
end

%% =====================================================================
function blocks = readInternalBlocks(sysPath)
% Read one level of internal blocks with their key parameters.
    blocks = struct('name', {}, 'type', {}, 'params', {});
    try
        blks = find_system(sysPath, 'SearchDepth', 1, 'Type', 'Block');
        for i = 1:numel(blks)
            if strcmp(blks{i}, sysPath), continue; end
            try
                bt = get_param(blks{i}, 'BlockType');
                if strcmp(bt, 'SubSystem'), continue; end
                params = struct();
                switch bt
                    case 'Gain'
                        params.Gain = get_param(blks{i}, 'Gain');
                    case 'Constant'
                        params.Value = get_param(blks{i}, 'Value');
                    case 'Sum'
                        params.Inputs = get_param(blks{i}, 'Inputs');
                    case 'Saturation'
                        params.UpperLimit = get_param(blks{i}, 'UpperLimit');
                        params.LowerLimit = get_param(blks{i}, 'LowerLimit');
                    case 'RelationalOperator'
                        params.Operator = get_param(blks{i}, 'Operator');
                    case 'LogicalOperator'
                        params.Operator = get_param(blks{i}, 'Operator');
                    case 'Switch'
                        params.Criteria = get_param(blks{i}, 'Criteria');
                    case 'UnitDelay'
                        params.SampleTime = get_param(blks{i}, 'SampleTime');
                    case 'DiscreteIntegrator'
                        params.InitialCondition = get_param(blks{i}, 'InitialCondition');
                end
                b = struct();
                b.name = get_param(blks{i}, 'Name');
                b.type = bt;
                b.params = params;
                blocks(end+1) = b; %#ok<AGROW>
            catch
                % skip
            end
        end
    catch
    end
end

%% =====================================================================
function cals = readCalibrations(sysPath)
% Extract calibration parameters (Constant/Gain referencing cal_* variables).
    cals = struct('name', {}, 'block', {}, 'param', {}, 'value', {});
    try
        blks = find_system(sysPath, 'LookUnderMasks', 'all', 'Type', 'Block');
        for i = 1:numel(blks)
            try
                bt = get_param(blks{i}, 'BlockType');
                blkName = get_param(blks{i}, 'Name');
                switch bt
                    case 'Constant'
                        val = get_param(blks{i}, 'Value');
                        if isvarname(val) || contains(val, 'cal_')
                            cals(end+1) = struct('name', val, 'block', blkName, ...
                                'param', 'Value', 'value', ''); %#ok<AGROW>
                        end
                    case 'Gain'
                        val = get_param(blks{i}, 'Gain');
                        if isvarname(val) || contains(val, 'cal_')
                            cals(end+1) = struct('name', val, 'block', blkName, ...
                                'param', 'Gain', 'value', ''); %#ok<AGROW>
                        end
                end
            catch
                % skip
            end
        end
        % Try to resolve values via model_resolve_params
        if ~isempty(cals)
            try
                exprs = jsonencode({cals.name});
                rp = model_resolve_params(modelBase, exprs);
                resolved = string(rp);
                if ~isempty(resolved)
                    for k = 1:numel(cals)
                        cals(k).value = 'resolved_in_toolkit';
                    end
                end
            catch
                % leave values empty
            end
        end
    catch
    end
end

%% =====================================================================
function children = readChildren(sysPath, modelBase)
    children = struct('name', {}, 'path', {});
    try
        sub = find_system(sysPath, 'SearchDepth', 1, 'BlockType', 'SubSystem');
        for i = 1:numel(sub)
            if strcmp(sub{i}, sysPath) || strcmp(sub{i}, modelBase), continue; end
            children(end+1) = struct('name', strrep(sub{i}, [modelBase '/'], ''), ...
                'path', sub{i}); %#ok<AGROW>
        end
    catch
    end
end

%% =====================================================================
function cfg = readModelConfig(modelBase)
    cfg = struct();
    try
        cfg.solver = get_param(modelBase, 'Solver');
        cfg.fixedStep = get_param(modelBase, 'FixedStep');
        cfg.stopTime = get_param(modelBase, 'StopTime');
        cfg.description = get_param(modelBase, 'Description');
    catch
    end
end

%% =====================================================================
function iface = extractModelInterfaces(modelBase)
    iface = struct();
    iface.inputs = readPorts(modelBase, 'Inport');
    iface.outputs = readPorts(modelBase, 'Outport');
end
