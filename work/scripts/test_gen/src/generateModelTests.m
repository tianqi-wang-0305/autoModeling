function result = generateModelTests(modelPath, varargin)
% generateModelTests  Compatibility wrapper around generateUnitTests.m
%   Backwards-compatible entry point referenced by run_generateModelTests.m,
%   run_generateSignalBuilderHarness.m, run_generateTestExecutionArtifacts.m,
%   and the /generateModelTests slash command.
%
%   This script combines legacy Gherkin .feature generation with the new
%   Agentic-Toolkit-driven workflow (generateUnitTests.m). All arguments are
%   forwarded.
%
%   Usage:
%       generateModelTests('path/to/Model.slx');
%       generateModelTests('path/to/Model.slx', 'Strategy', 'boundary');
%       generateModelTests('path/to/Model.slx', 'Component', 'Model/Sub', ...
%                          'RunTests', false);

    fprintf('=== generateModelTests (wrapper -> generateUnitTests) ===\n\n');

    % Ensure the implementation directory is on the path
    here = fileparts(mfilename('fullpath'));
    addpath(here);

    % Forward all arguments to the implementation
    result = generateUnitTests(modelPath, varargin{:});
end
