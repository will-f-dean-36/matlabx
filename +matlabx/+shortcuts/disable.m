function disable()
%DISABLE  Disables the matlabx shortcut functions.

    if matlabx.shortcuts.isEnabled()
        rmpath(getDirectory());
    end
end