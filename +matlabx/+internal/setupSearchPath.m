function setupSearchPath()
%SETUPSEARCHPATH Adds necessary folder to MATLAB search path

% add external libraries to MATLAB search path
addpath(genpath(matlabx.internal.Paths.external()));
savepath();

end