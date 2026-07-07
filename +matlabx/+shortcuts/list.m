function names = list()
%LIST  Lists the available matlabx shortcut functions.
%
%   names = matlabx.shortcuts.list() returns the names of all MATLAB
%   function files in the matlabx shortcuts directory.
%
%   Output
%     names : Column string array containing shortcut function names
%
%   Example
%     names = matlabx.shortcuts.list();

    files = matlabx.files.listFiles(matlabx.internal.Paths.shortcuts());

    isFunction = endsWith(files,".m",IgnoreCase=true);
    names = erase(files(isFunction),".m");

    names = sort(names);
end