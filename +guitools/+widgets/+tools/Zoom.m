classdef Zoom < guitools.widgets.ImageAxesTool
% guitools.widgets.tools.Zoom
% when Enabled: 
%   left-click      increase zoom 
%   right-click     decrease zoom
%   view box follows cursor when Pan Mode is on (on by default)
%   shift-click to enable/disable Pan
%   can also increase/decrease zoom with scroll wheel
%
%   command +

    % --- Zoom functionality ---
    properties
        ZoomLevelIdx (1,1) double = 1
        ZoomLevels (1,:) double = [1 1/2 1/3 1/4 1/5 1/10 1/15 1/20]
        ZoomPanLim (1,2) double = [0.25 0.75]
    end

    properties (SetAccess=private, Dependent)
        ZoomLevel
        ZoomFactor
    end

    % Private properties for internal behavior
    properties (Access=private)
        lastCursorPosition = []
    end

    % --- veiw box properties ---

    % Graphics objects
    properties (Access=private, Transient, NonCopyable)
        FullBox (1,1) matlab.graphics.primitive.Patch
        ZoomBox (1,1) matlab.graphics.primitive.Patch
    end

    % Appearance
    properties
        BoxSize = 0.1
        BoxEdgeColor = [0 0 0]
        BoxFaceColor = [1 1 1]
        BoxFaceAlpha = 0.25
        BoxLineWidth = 1

        BoxPositionTop = 0.05
        BoxPositionLeft = 0.01


        ImageHeight
        ImageWidth
        Top
        Left
        XBase
        YBase
        XFull
        YFull
        XZoomBase
        YZoomBase
    end


    %% Constructor / onEnabled / onDisabled / onInstall / onUninstall
    methods

        function obj = Zoom(host)
            obj@guitools.widgets.ImageAxesTool(host,"Zoom", ...
                'Tooltip',          'Zoom/Pan', ...
                'Icon',             guitools.Paths.icons('ZoomIcon.png'), ...
                'Priority',         1, ...
                'IsExclusive',      false, ...
                'CapturesMove',     true, ...
                'CapturesDown',     true, ...
                'CapturesScroll',   true, ...
                'CapturesKeyPress', true, ...
                'DistractsMove',    false, ...
                'DistractsDown',    true);
            % set up view box patches
            obj.FullBox = patch(host.getOverlayAxes(), ...
                'XData',NaN, ...
                'YData',NaN, ...
                'EdgeColor',obj.BoxEdgeColor, ...
                'FaceColor',obj.BoxFaceColor, ...
                'FaceAlpha',obj.BoxFaceAlpha, ...
                'HitTest','on', ...
                'PickableParts','all', ...
                'LineWidth', obj.BoxLineWidth, ...
                'Tag','ViewBoxFull');
            obj.ZoomBox = patch(host.getOverlayAxes(), ...
                'XData',NaN, ...
                'YData',NaN, ...
                'EdgeColor',obj.BoxEdgeColor, ...
                'FaceColor',obj.BoxFaceColor, ...
                'FaceAlpha',obj.BoxFaceAlpha, ...
                'HitTest','on', ...
                'PickableParts','all', ...
                'LineWidth', obj.BoxLineWidth, ...
                'Tag','ViewBoxZoom');
            % store image height
            obj.ImageHeight = obj.Host.ImageHeight;
            obj.ImageWidth = obj.Host.ImageWidth;
        end

        % Toggled Enabled=true via toolbar button
        function onEnabled(obj)
            obj.Host.setMode('Zoom', true);
            % update view box patch base coordinates
            obj.ImageHeight = obj.Host.ImageHeight;
            obj.ImageWidth = obj.Host.ImageWidth;
            obj.updateViewBoxBaseCoordinates();
            set([obj.FullBox,obj.ZoomBox],"Visible","on")
            % set view
            if ~obj.Host.Mode.Pan % Pan Mode is off -> use stored cursor position
                obj.updateLimits(obj.lastCursorPosition)
            else % otherwise -> use current cursor position
                obj.moveViewToCursor();
            end
        end

        % Toggled Enabled=false via toolbar button
        function onDisabled(obj)
            % clear and hide patches if they exist
            if isvalid(obj.FullBox)
                set([obj.FullBox],"XData",NaN,"YData",NaN,"Visible","off")
            end

            if isvalid(obj.ZoomBox)
                set([obj.ZoomBox],"XData",NaN,"YData",NaN,"Visible","off")
            end

            % restore Host limits and Zoom mode
            if isvalid(obj.Host)
                obj.Host.restoreDefaultLimits();
                obj.Host.setMode('Zoom', false);
            end
        end

        % Called AFTER installed from Host, use for any extra required startup actions
        function onInstall(obj)
            obj.Host.addMode('Zoom');
            obj.Host.addMode('Pan');
            obj.Host.setMode('Pan', true); % Pan Mode is On by default
        end

        % Called AFTER uninstalled from Host, use for any extra required cleanup actions
        function onUninstall(obj)
            obj.Host.removeMode('Zoom');
            obj.Host.removeMode('Pan');
        end

    end

    %% Active event hooks (only when Enabled==true && IsInterceptor==true)
    methods

        function onDown(obj, ~, ~)

            obj.printStatus(sprintf('%s.onDown()\n',obj.Name));

            if isempty(obj.Host.cursorPositionStatic)
                return
            end

            switch obj.Host.ParentFig.SelectionType
                case 'normal'
                    obj.increaseZoom();
                case 'alt'
                    obj.decreaseZoom();
                case 'extend'
                    obj.togglePan();
            end

        end

        function onScroll(obj, evt, ~)
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
            if evt.VerticalScrollCount < 0
                obj.increaseZoom();
            elseif evt.VerticalScrollCount > 0
                obj.decreaseZoom();
            end
        end

        function onMove(obj, ~, ~)
            obj.printStatus(sprintf('%s.onMove()\n',obj.Name));
            if obj.Host.Mode.Pan
                obj.moveViewToCursor();
            end
        end

        function onKeyPress(obj, evt, tgt)
            obj.printStatus(sprintf('%s.onKeyPress()\n',obj.Name));
            match = true;

            % parse event data
            % try modifier+character first
            keyStr = strip(strjoin([evt.Modifier,{evt.Character}],'|'),'|');
            % fprintf('Zoom: %s\n',keyStr)

            switch keyStr
                case {'command|=','control|='}  % command/control and +(=)   | increase zoom
                    obj.increaseZoom();
                case {'command|-','control|-'}  % command/control and -      | decrease zoom
                    obj.decreaseZoom();
                otherwise
                    match = false;
            end

            % no match found -> try modifier+key
            if ~match
                keyStr = strip(strjoin([evt.Modifier,{evt.Key}],'|'),'|');
                switch keyStr
                    case {'escape'} % escape | disable tool
                        obj.disable();
                    otherwise
                        % still no match -> return
                        return
                end
            end

        end

    end

    %% Passive event hooks (only when Installed==true && IsDistractor==true)
    methods

        function tf = onDistractDown(obj,~,~)
            obj.printStatus(sprintf('%s.onDistractDown()\n',obj.Name));
            tf = false;
        end

        % function tf = onDistractMove(obj,evt,tgt)
        %     obj.printStatus(sprintf('%s.onDistractMove()\n',obj.Name);
        %     tf = false;
        % end

    end

    %% Private helpers
    methods (Access=private)

        function moveViewToCursor(obj)
            XY = obj.Host.cursorPositionStatic;
            if ~isempty(XY)
                obj.updateLimits(XY);
            end
        end

        function increaseZoom(obj)
            obj.ZoomLevelIdx = min(obj.ZoomLevelIdx + 1, numel(obj.ZoomLevels));
            obj.updateViewBoxBaseCoordinates();
            obj.moveViewToCursor();
            obj.Host.updateFromTool();
        end

        function decreaseZoom(obj)
            obj.ZoomLevelIdx = max(obj.ZoomLevelIdx-1,1);
            obj.updateViewBoxBaseCoordinates();
            obj.moveViewToCursor();
            obj.Host.updateFromTool();
        end

        function togglePan(obj)
            obj.Host.setMode('Pan', ~obj.Host.Mode.Pan);
            obj.moveViewToCursor();
            obj.Host.updateFromTool();
        end

        function updateViewBoxBaseCoordinates(obj)
            H = obj.ImageHeight;
            W = obj.ImageWidth;
            obj.Top = (obj.BoxPositionTop*H) + 0.5;
            obj.Left = (obj.BoxPositionLeft*W) + 0.5;
            obj.XBase = [0 0 W W] .* obj.BoxSize;
            obj.YBase = [0 H H 0] .* obj.BoxSize;
            obj.XFull = obj.XBase + obj.Left;
            obj.YFull = obj.YBase + obj.Top;
            obj.XZoomBase = obj.XBase.*obj.ZoomLevel + obj.Left;
            obj.YZoomBase = obj.YBase.*obj.ZoomLevel + obj.Top;
            set(obj.FullBox,"XData",obj.XFull,"YData",obj.YFull);
        end


        function [XLim,YLim] = getZoomLims(obj,XY)
            % image dimensions
            W = obj.Host.ImageWidth;
            H = obj.Host.ImageHeight;
            % zoom level | e.g. 0.5 means 2X zoom
            z = obj.ZoomLevel;
            % pan limits in normalized coordinates
            a = obj.ZoomPanLim(1);
            b = obj.ZoomPanLim(2);
            % width of zoomed window
            WZ = z * W;
            % height of zoomed window
            HZ = z * H;
            % calculate limits
            XYL = repmat((((clip((XY-0.5)./[W,H],a,b)-a)/(b - a)).*[W-WZ,H-HZ])',1,2) + [0,WZ;0,HZ] + 0.5;
            XLim = XYL(1,:);
            YLim = XYL(2,:);

            % XYL = ((clip((XY-0.5)./[W,H], a, b) - a) / (b - a)) .* [W-WZ,H-HZ];
            % XLim = [XYL(1),XYL(1)+WZ] + 0.5;
            % YLim = [XYL(2),XYL(2)+HZ] + 0.5;
        end

    end


    %%
    methods

        function z = get.ZoomLevel(obj)
            z = obj.ZoomLevels(obj.ZoomLevelIdx);
        end

        function f = get.ZoomFactor(obj)
            f = 1/obj.ZoomLevel;
        end

    end

    %% Host-fired events

    methods

        function onHostCDataChanged(obj,evt)
            if ~obj.Enabled
                return
            end

            oldSize = size(evt.oldCData,[1 2]);
            newSize = size(evt.newCData,[1 2]);

            if isempty(obj.lastCursorPosition)
                return
            end

            oldX = obj.lastCursorPosition(1);
            oldY = obj.lastCursorPosition(2);

            % new image is same size as the previous image
            if isequal(oldSize,newSize)
                % set limits using prior cursor position
                obj.updateLimits([oldX,oldY]);
                return
            end

            % otherwise, re-map previous cursor position to hit the same relative spot in new image
            newY = oldY*(newSize(1)/oldSize(1));
            newX = oldX*(newSize(2)/oldSize(2));

            % update view box patch base coordinates before updating view box
            obj.ImageHeight = newSize(1);
            obj.ImageWidth = newSize(2);
            obj.updateViewBoxBaseCoordinates();

            % set new limits using new cursor position
            obj.updateLimits([newX,newY]);
            
            obj.printStatus(sprintf('Host CData changed\n'))
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
                    str = sprintf('Zoom: %iX',obj.ZoomFactor);
                case false
                    str = 'Zoom: off';
            end
        end

        function updateLimits(obj,XY)
            [XLim,YLim] = obj.getZoomLims(XY);
            set(obj.Host.mainAxes,'XLim',XLim,'YLim',YLim);

            % update inner view box
            set(obj.ZoomBox,...
                "XData",obj.XZoomBase+(XLim(1)-0.5)*obj.BoxSize,...
                "YData",obj.YZoomBase+(YLim(1)-0.5)*obj.BoxSize);


            % save last cursor position used to set limits
            obj.lastCursorPosition = XY;
        end

    end



    %% Teardown
    methods (Access = protected)

        % called at the beginning of superclass delete()
        function teardown(obj)
            % delete patches
            delete(obj.FullBox(isvalid(obj.FullBox)));
            delete(obj.ZoomBox(isvalid(obj.ZoomBox)));
        end

    end

end