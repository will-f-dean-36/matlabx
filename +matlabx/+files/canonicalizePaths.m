function pathsOut = canonicalizePaths(pathsIn)
%CANONICALIZEPATHS  Convert multiple paths to canonical form
%
%   pathsOut = matlabx.files.canonicalizePaths(pathsIn) converts each
%   supplied file or folder path to its canonical absolute representation.
%
%   Input
%       pathsIn  - Collection of file or folder paths
%
%   Output
%       pathsOut - Canonical paths returned as a string array
%
%   See also matlabx.files.canonicalPath

    pathsOut = string(pathsIn);

    for n = 1:numel(pathsOut)
        if strlength(pathsOut(n)) > 0
            pathsOut(n) = matlabx.files.canonicalPath(pathsOut(n));
        end
    end
end