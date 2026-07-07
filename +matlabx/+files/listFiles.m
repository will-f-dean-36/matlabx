function files = listFiles(location)
%LISTFILES  Lists files at a specified location
%
%   files = LISTFILES(location) returns the names of all files directly
%   contained within location.
%
%   Input
%     location : Path to an existing folder, specified as a string scalar
%                or character vector
%
%   Output
%     files    : Column string array containing file names
%
%   Example
%     files = matlabx.files.listFiles(pwd);

    files = matlabx.files.listContents(location);
end