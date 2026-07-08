function pathOut = canonicalPath(pathIn)
%CANONICALPATH  Return the canonical absolute form of a path
%
%   pathOut = matlabx.files.canonicalPath(pathIn) returns the canonical
%   absolute representation of the specified file or folder path.
%
%   Symbolic links, relative path components, and redundant separators are
%   resolved where supported by the operating system.
%
%   Input
%       pathIn  - File or folder path, specified as a string scalar or
%                 character vector
%
%   Output
%       pathOut - Canonical absolute path, returned as a string scalar

    arguments
        pathIn {mustBeTextScalar}
    end

    file = java.io.File(char(pathIn));
    pathOut = string(file.getCanonicalPath());
end