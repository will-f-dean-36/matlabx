classdef DisplayLimits < matlabx.ui.axes.AxesTool
%DISPLAYLIMITS Open the ImageAxes display-limits adjustment window.
%
%   DisplayLimits is a push-style toolbar tool. It does not own the slider
%   dialog or display-limit state; it simply asks its ImageAxes host to open
%   the host-owned display-limits window.

    methods
        function obj = DisplayLimits(host)
        %DISPLAYLIMITS Create the DisplayLimits tool for one ImageAxes host.
            obj@matlabx.ui.axes.AxesTool(host, "DisplayLimits", ...
                'Tooltip', 'Adjust display limits', ...
                'AxesType', "image", ...
                'Icon', matlabx.internal.Paths.icons('Slider.png'), ...
                'Style', 'push', ...
                'Priority', 1);
        end

        function onPush(obj)
        %ONPUSH Ask the host to open its display-limits adjustment window.
            obj.Host.openDisplayLimitsWindow();
        end
    end
end
