function results = runAIPipeline(modelPath, varargin)
% runAIPipeline  One-click automation pipeline for Simulink application-layer
%   software development:
%
%     [1] Analyze   -> analyzeModelDeepForSDD  (deep knowledge base JSON)
%     [2] SDD       -> DdGeneration_AI         (Detail Design doc, non-manual)
%     [3] Tests     -> generateUnitTests       (Simulink Test unit tests + report)
%
%   Inputs:
%       modelPath  - Model file path (e.g. 'Model.slx')
%       varargin   - Name/Value:
%           'ExcelFile'  - Interface/calibration Excel (optional)
%           'Strategy'   - Test strategy: 'basic'|'boundary'|'comprehensive' (default basic)
%           'RunTests'   - true (default) to execute tests via model_test
%           'Coverage'   - 'none' (default) | 'decision'
%           'OutputDir'  - Output directory (default: model dir)
%
%   Outputs:
%       results - Struct with .knowledgeFile, .sddFile, .testReport, .testResults
%
%   Usage:
%       results = runAIPipeline('Foc_2024b.slx');
%       results = runAIPipeline('Model.slx', 'ExcelFile', 'iface.xlsx', ...
%                               'Strategy', 'comprehensive', 'Coverage', 'decision');

    fprintf('\n============================================\n');
    fprintf('  AI Automation Pipeline for Simulink MBD\n');
    fprintf('============================================\n\n');

    %% ---- Parse ----
    p = inputParser;
    addRequired(p, 'modelPath', @(x) ischar(x) || isstring(x));
    addParameter(p, 'ExcelFile', '', @ischar);
    addParameter(p, 'Strategy', 'basic', @ischar);
    addParameter(p, 'RunTests', true, @islogical);
    addParameter(p, 'Coverage', 'none', @ischar);
    addParameter(p, 'OutputDir', '', @ischar);
    parse(p, modelPath, varargin{:});

    modelPath = char(p.Results.modelPath);
    excelFile = char(p.Results.ExcelFile);
    strategy  = char(p.Results.Strategy);
    runTests  = p.Results.RunTests;
    coverage  = char(p.Results.Coverage);
    outDir    = char(p.Results.OutputDir);

    [mdir, modelBase, ~] = fileparts(modelPath);
    if isempty(mdir), mdir = pwd; end
    if isempty(outDir), outDir = mdir; end

    % Paths
    here = fileparts(mfilename('fullpath'));
    aiSddSrc = fullfile(here, '..', 'ai_sdd', 'src');
    testSrc  = fullfile(here, '..', 'test_gen', 'src');
    addpath(aiSddSrc);
    addpath(testSrc);

    % Toolkit
    tk = locateToolkit();
    if ~isempty(tk), addpath(genpath(fullfile(tk, 'tools'))); end
    if exist('satk_initialize', 'file') > 0, satk_initialize; end

    results = struct();

    %% ---- Step 1: Deep analysis ----
    fprintf('\n--- [1/3] Deep Model Analysis ---\n');
    kb = analyzeModelDeepForSDD(modelPath, 'OutputDir', outDir, 'Verbose', true);
    results.knowledgeFile = kb.knowledgeFile;

    %% ---- Step 2: Detail Design document ----
    fprintf('\n--- [2/3] Detail Design Document (AI) ---\n');
    if ~isempty(excelFile)
        results.sddFile = DdGeneration_AI(modelPath, ...
            'KnowledgeFile', kb.knowledgeFile, ...
            'OutputDir', outDir, ...
            'ExcelFile', excelFile);
    else
        results.sddFile = DdGeneration_AI(modelPath, ...
            'KnowledgeFile', kb.knowledgeFile, ...
            'OutputDir', outDir);
    end

    %% ---- Step 3: Unit tests ----
    fprintf('\n--- [3/3] Unit Test Generation ---\n');
    tr = generateUnitTests(modelPath, 'Strategy', strategy, 'RunTests', runTests, ...
        'Coverage', coverage, 'OutputDir', fullfile(outDir, '_tests'));
    results.testReport = tr.reportFile;
    results.testResults = tr.results;

    %% ---- Summary ----
    fprintf('\n============================================\n');
    fprintf('  Pipeline Complete\n');
    fprintf('============================================\n');
    fprintf('  Knowledge base : %s\n', results.knowledgeFile);
    fprintf('  SDD document   : %s\n', results.sddFile);
    fprintf('  Test report    : %s\n', results.testReport);
    fprintf('============================================\n');
end

function tk = locateToolkit()
    tk = '';
    cand = {
        fullfile(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))), 'simulink-agentic-toolkit'), ...
        fullfile(pwd, 'simulink-agentic-toolkit'), ...
        getenv('SATK_ROOT')
    };
    for i = 1:numel(cand)
        c = cand{i};
        if ~isempty(c) && exist(fullfile(c, 'tools', 'model_read'), 'dir')
            tk = c; return;
        end
    end
end
