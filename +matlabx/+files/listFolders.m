function folders = listFolders(location)
%LISTFOLDERS  Lists folders at a specified location
%
%   folders = LISTFOLDERS(location) returns the names of all folders directly
%   contained within location. The special directory entries "." and ".."
%   are excluded.
%
%   Input
%     location : Path to an existing folder, specified as a string scalar
%                or character vector
%
%   Output
%     folders  : Column string array containing folder names
%
%   Example
%     folders = matlabx.files.listFolders(pwd);

    [~,folders] = matlabx.files.listContents(location);
end