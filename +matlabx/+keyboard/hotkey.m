function hk = hotkey(key, opts)
%HOTKEY Build a normalized hotkey string for declarations.
%
%   hk = matlabx.keyboard.hotkey("z", "Modifiers", ["shift","meta"])
%   returns "shift+meta+z". Use this helper when declaring tool hotkeys so
%   callers do not need to remember the exact normalized string format.

    arguments
        key (1,1) string
        opts.Modifiers (1,:) string = string.empty(1,0)
    end

    hk = matlabx.keyboard.normalize(key, "", opts.Modifiers);
end
