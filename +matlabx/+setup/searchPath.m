function searchPath()
%SEARCHPATH  Adds necessary folders to MATLAB search path

% add root folder to MATLAB search path
addpath(matlabx.internal.Paths.root());

% add external libraries to MATLAB search path
addpath(matlabx.internal.Paths.external('bfmatlab'));
addpath(matlabx.internal.Paths.external('colornames'));

end