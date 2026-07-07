function enable()
%ENABLE  Enables the matlabx shortcut functions.

    if ~matlabx.shortcuts.isEnabled()
        addpath(matlabx.internal.Paths.shortcuts());
    end
end