function [files,folders] = listContents(location)
%LISTCONTENTS  Lists files and folders at a specified location
%
%   [files,folders] = LISTCONTENTS(location) returns the names of all files
%   and folders directly contained within location. The special directory
%   entries "." and ".." are excluded.
%
%   Input
%     location : Path to an existing folder, specified as a string scalar
%                or character vector
%
%   Outputs
%     files    : Column string array containing file names
%     folders  : Column string array containing folder names
%
%   Example
%     [files,folders] = listContents(pwd);

    arguments
        location (1,1) string {mustBeFolder}
    end

    contents = dir(location);

    names = string({contents.name})';
    isFolder = [contents.isdir]';

    isSpecial = names == "." | names == "..";

    files = names(~isFolder);
    folders = names(isFolder & ~isSpecial);
end