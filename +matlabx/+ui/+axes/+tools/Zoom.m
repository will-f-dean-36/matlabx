classdef Zoom < matlabx.ui.axes.AxesTool
%ZOOM Zoom/cursor-follow navigation tool for matlabx.ui.axes.ImageAxes.
%
%   When enabled:
%       left-click      increase zoom
%       right-click     decrease zoom
%       shift-click     toggle cursor-follow navigation
%       scroll wheel    increase/decrease zoom
%
%   Zoom is intentionally non-exclusive so it can coexist with interaction
%   tools such as Pick or DrawRectangle. Its toggle hotkey is contributed to
%   the host hotkey registry when the tool is installed.

    properties
        ScrollEventsPerZoomStep (1,1) double {mustBeInteger, mustBePositive} = 5
    end

    properties (Access=private)
        ScrollEventCount (1,1) double {mustBeNonnegative, mustBeInteger} = 0
        LastScrollDirection (1,1) double {mustBeMember(LastScrollDirection,[-1,0,1])} = 0
    end

    %% Lifecycle
    methods

        function obj = Zoom(host)
            obj@matlabx.ui.axes.AxesTool(host,"Zoom", ...
                'Tooltip',          'Zoom/Follow Cursor', ...
                'AxesType',         "both", ...
                'Icon',             matlabx.internal.Paths.icons('ZoomIcon.png'), ...
                'Priority',         1, ...
                'ToggleHotkey',     matlabx.keyboard.hotkey("z", "Modifiers", ["shift","meta"]), ...
                'IsExclusive',      false, ...
                'InterceptsMove',   false, ...
                'InterceptsDown',   true, ...
                'InterceptsScroll', true, ...
                'InterceptsKeyPress',    true);
        end

        function onEnabled(obj)
        %ONENABLED  Enable Zoom when toolbar button is enabled.
            obj.ScrollEventCount = 0;
            obj.LastScrollDirection = 0;
            obj.Host.enableZoom();
        end

        function onDisabled(obj)
        %ONDISABLED  Disable Zoom when toolbar button is disabled.
            obj.ScrollEventCount = 0;
            obj.LastScrollDirection = 0;
            if isvalid(obj.Host)
                obj.Host.disableZoom();
            end
        end

    end

    %% Active event hooks (only when Enabled==true && IsInterceptor==true)
    methods

        function onDown(obj, E)

            obj.printStatus(sprintf('%s.onDown()', obj.Name));

            H = obj.Host;
            if isempty(H.cursorPositionStatic)
                return
            end

            switch E.SelectionType
                case 'normal'
                    H.increaseZoom();
                case 'alt'
                    H.decreaseZoom();
                case 'extend'
                    obj.Host.toggleFollowCursorEnabled();
            end

        end

        function onScroll(obj, E)
            obj.printStatus(sprintf('%s.onScroll()', obj.Name));

            H = obj.Host;
            if isempty(H.cursorPositionStatic)
                return
            end

            scrollDirection = sign(E.VerticalScrollCount);

            if scrollDirection == 0
                return
            end

            if scrollDirection ~= obj.LastScrollDirection
                obj.ScrollEventCount = 0;
                obj.LastScrollDirection = scrollDirection;
            end

            obj.ScrollEventCount = obj.ScrollEventCount + 1;
            if obj.ScrollEventCount < obj.ScrollEventsPerZoomStep
                return
            end

            obj.ScrollEventCount = 0;

            % Adjust zoom level based on scroll direction
            if scrollDirection < 0
                H.increaseZoom();
            elseif scrollDirection > 0
                H.decreaseZoom();
            end
        end

        function onKeyPress(obj, E)
            obj.printStatus(sprintf('%s.onKeyPress()', obj.Name));

            switch E.Hotkey
                case "meta+equal"
                    obj.Host.increaseZoom();
                case "meta+hyphen"
                    obj.Host.decreaseZoom();
                case "escape"
                    obj.disable();
            end

        end

    end

    %% Host display helpers
    methods

        function pointer = getPreferredPointer(obj)
            if obj.Enabled
                pointer = 'crosshair';
            else
                pointer = '';
            end
        end

        function str = getLabelString(obj)
            % Return char vector with info on zoom level.
            switch obj.Enabled
                case true
                    str = 'Zoom: on';
                case false
                    str = 'Zoom: off';
            end
        end

    end
end
