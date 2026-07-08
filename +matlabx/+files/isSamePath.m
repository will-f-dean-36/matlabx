function tf = isSamePath(pathA, pathB)
%ISSAMEPATH  Determine whether two paths refer to the same location
%
%   tf = matlabx.files.isSamePath(pathA,pathB) compares canonical forms of
%   the supplied paths using platform-appropriate case sensitivity.
%
%   Either input may be a string array when the other input is scalar.
%
%   Inputs
%       pathA - First file or folder path
%       pathB - Second file or folder path
%
%   Output
%       tf    - Logical comparison result

    pathA = matlabx.files.canonicalizePaths(pathA);
    pathB = matlabx.files.canonicalizePaths(pathB);

    if ispc
        tf = strcmpi(pathA,pathB);
    else
        tf = strcmp(pathA,pathB);
    end
end