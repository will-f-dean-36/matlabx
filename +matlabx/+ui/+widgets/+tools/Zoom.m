classdef Zoom < matlabx.ui.widgets.ImageAxesTool
% matlabx.ui.widgets.tools.Zoom
% when Enabled: 
%   left-click      increase zoom 
%   right-click     decrease zoom
%   view box follows cursor when Pan Mode is on (on by default)
%   shift-click to enable/disable Pan
%   can also increase/decrease zoom with scroll wheel

    %% Constructor / onEnabled / onDisabled / onInstall / onUninstall
    methods

        function obj = Zoom(host)
            obj@matlabx.ui.widgets.ImageAxesTool(host,"Zoom", ...
                'Tooltip',          'Zoom/Pan', ...
                'Icon',             matlabx.internal.Paths.icons('ZoomIcon.png'), ...
                'Priority',         1, ...
                'ToggleHotkey',     matlabx.keyboard.normalize('z','',{'shift','meta'}), ...
                'IsExclusive',      false, ...
                'CapturesMove',     false, ...
                'CapturesDown',     true, ...
                'CapturesScroll',   true, ...
                'CapturesKey',      true, ...
                'DistractsKey',     true);
        end

        function onEnabled(obj)
        %ONENABLED  Enable Zoom when toolbar button enabled
            obj.Host.setMode('Zoom', true);
            obj.Host.enableZoom();
        end

        function onDisabled(obj)
        %ONDISABLED  Disable Zoom when toolbar button disabled    
            if isvalid(obj.Host)
                obj.Host.setMode('Zoom', false);
                obj.Host.disableZoom();
            end
        end

        function onInstall(obj)
        %ONINSTALL  Called AFTER installed from Host, use for any extra required startup actions
            obj.Host.addMode('Zoom');
            %obj.Host.addMode('Pan');
            %obj.Host.setMode('Pan', true); % Pan Mode is On by default
        end

        function onUninstall(obj)
        %ONUNINSTALL  Called AFTER uninstalled from Host, use for any extra required cleanup actions
            obj.Host.removeMode('Zoom');
            %obj.Host.removeMode('Pan');
        end

    end

    %% Active event hooks (only when Enabled==true && IsInterceptor==true)
    methods

        function onDown(obj, E)

            obj.printStatus(sprintf('%s.onDown()\n',obj.Name));

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
                    %obj.Host.setMode('Pan', ~obj.Host.Mode.Pan);
                    obj.Host.togglePanEnabled();
            end

        end

        function onScroll(obj, E)
            % keep track of calls to control how many calls = one zoom increment
            persistent callCount

            obj.printStatus(sprintf('%s.onScroll()\n',obj.Name));

            H = obj.Host;
            if isempty(H.cursorPositionStatic)
                return
            end

            callCount = callCount+1;
            if callCount < 5
                return
            end

            callCount = 0;

            % Adjust zoom level based on scroll direction
            if E.VerticalScrollCount < 0
                H.increaseZoom();
            elseif E.VerticalScrollCount > 0
                H.decreaseZoom();
            end
        end

        function onKey(obj, E)
            obj.printStatus(sprintf('%s.onKey()\n',obj.Name));

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

    %% Passive event hooks (only when Installed==true && IsDistractor==true)
    methods

        function onDistractKey(obj,E)
            if obj.ToggleHotkey == E.Hotkey
                E.stop();
            else
                return
            end

            switch obj.Enabled
                case false
                    obj.enable();
                case true
                    obj.disable();
            end
        end

    end

    %% Host update helpers
    methods

        function pointer = getPreferredPointer(obj)
            if obj.Host.Mode.Zoom
                pointer = 'crosshair';
            else
                pointer = '';
            end
        end

        function str = getLabelString(obj)
            % return char vector with info on zoom level
            switch obj.Host.Mode.Zoom
                case true
                    str = 'Zoom: on';
                case false
                    str = 'Zoom: off';
            end
        end

    end



    %% Teardown
    methods (Access = protected)

        % called at the beginning of superclass delete()
        function teardown(obj)
            % extra required cleanup on teardown
        end

    end

end