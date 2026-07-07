function tf = isEnabled()
%ISENABLED  Returns true if the matlabx shortcuts folder is on the search path.

    shortcutDir = matlabx.internal.Paths.shortcuts();
    pathEntries = strsplit(path, pathsep);

    tf = any(strcmp(pathEntries, shortcutDir));
end