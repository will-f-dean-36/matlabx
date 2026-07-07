function setupSearchPath()
%SETUPSEARCHPATH Adds necessary folder to MATLAB search path

% add root folder to MATLAB search path
addpath(matlabx.internal.Paths.root());

% add external libraries to MATLAB search path
addpath(genpath(matlabx.internal.Paths.external()));

% save path
savepath();

end