function jarFiles = findJarsContaining(paths,entryName)
%FINDJARSCONTAINING  Find JAR files containing a specified entry
%
%   jarFiles = matlabx.java.findJarsContaining(paths,entryName) searches
%   the supplied paths and returns JAR files containing the requested
%   archive entry.
%
%   Inputs
%       paths     - Collection of candidate file paths
%       entryName - Name of the JAR entry to locate
%
%   Output
%       jarFiles  - Matching JAR paths returned as a string array
%
%   See also matlabx.java.jarContainsEntry

    arguments
        paths
        entryName {mustBeTextScalar}
    end

    paths = string(paths);
    paths = paths(:);

    isJar = isfile(paths) & endsWith(paths,".jar",IgnoreCase=true);
    paths = paths(isJar);

    containsEntry = false(size(paths));

    for n = 1:numel(paths)
        containsEntry(n) = matlabx.java.jarContainsEntry( ...
            paths(n),entryName);
    end

    jarFiles = paths(containsEntry);
    jarFiles = matlabx.files.canonicalizePaths(jarFiles);
end