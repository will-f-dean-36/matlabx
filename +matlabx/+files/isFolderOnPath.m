function tf = isFolderOnPath(folder)
%ISFOLDERONPATH  Determine whether a folder is on the MATLAB search path
%
%   tf = matlabx.files.isFolderOnPath(folder) returns true when the
%   specified folder is present on the MATLAB search path.
%
%   Input
%       folder - Folder path
%
%   Output
%       tf     - True when the folder is on the MATLAB search path

    arguments
        folder {mustBeTextScalar}
    end

    pathFolders = string(strsplit(path,pathsep));
    pathFolders = pathFolders(strlength(pathFolders) > 0);

    tf = any(matlabx.files.isSamePath(pathFolders,folder));
end