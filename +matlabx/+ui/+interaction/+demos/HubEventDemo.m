classdef HubEventDemo < matlab.ui.componentcontainer.ComponentContainer
%HUBEVENTDEMO Small app for inspecting FigureEventHub event payloads.

    properties (Access=private)
        Grid matlab.ui.container.GridLayout
        Axes matlab.ui.control.UIAxes
        LogArea matlab.ui.control.TextArea

        Hub matlabx.ui.interaction.FigureEventHub
        RouterId double = NaN
    end

    methods (Static)
        function app = demo()
        %DEMO Open the interactive hub-event test app.
            fig = uifigure( ...
                "Name","FigureEventHub demo", ...
                "Position",[100 100 720 750]);

            app = matlabx.ui.interaction.demos.HubEventDemo(fig, ...
                "Units","normalized", ...
                "Position",[0 0 1 1]);

            menu = uimenu(fig, "Text","Test");
            uimenu(menu, ...
                "Text","Menu callback, accelerator A", ...
                "Accelerator","A", ...
                "MenuSelectedFcn",@(~,~) app.appendMenuEvent("Menu callback fired: Test > Menu callback, accelerator A"));
            uimenu(menu, ...
                "Text","Clear log", ...
                "MenuSelectedFcn",@(~,~) app.clearLog());
        end
    end

    methods (Access=protected)
        function setup(obj)
            obj.Grid = uigridlayout(obj, [2 1], ...
                "RowHeight",{300,'1x'}, ...
                "ColumnWidth",{'1x'}, ...
                "Padding",[8 8 8 8], ...
                "RowSpacing",8);

            obj.Axes = uiaxes(obj.Grid, ...
                "Tag","HubEventDemoAxes", ...
                "XLim",[0 1], ...
                "YLim",[0 1], ...
                "Box","on", ...
                "HitTest","on", ...
                "PickableParts","all");
            obj.Axes.Layout.Row = 1;
            obj.Axes.Layout.Column = 1;
            title(obj.Axes, "Click here, use shortcuts, and watch the event log");

            obj.LogArea = uitextarea(obj.Grid, ...
                "Editable","off", ...
                "FontName","Menlo", ...
                "FontSize",11, ...
                "Value",{'HubEvent demo ready.'});
            obj.LogArea.Layout.Row = 2;
            obj.LogArea.Layout.Column = 1;

            fig = ancestor(obj, 'Figure');
            obj.Hub = matlabx.ui.interaction.FigureEventHub.ensure(fig);
            obj.RouterId = obj.Hub.register(obj, ...
                "Priority",100, ...
                "CaptureDuringDrag",true);
        end

        function update(~)
        end
    end

    methods
        function delete(obj)
            if ~isnan(obj.RouterId) && ~isempty(obj.Hub) && isvalid(obj.Hub)
                obj.Hub.unregister(obj.RouterId);
            end
        end

        function tf = matches(obj, E)
        %MATCHES Claim axes-targeted mouse events and axes-focused key events.
            tf = false;

            if isempty(obj.Axes) || ~isvalid(obj.Axes)
                return
            end

            if isequal(E.Target, obj.Axes)
                tf = true;
                return
            end

            if E.isKeyEvent() && isequal(E.CurrentAxes, obj.Axes)
                tf = true;
            end
        end

        function appendMenuEvent(obj, msg)
            obj.appendBlock("MENU", string(msg));
        end

        function clearLog(obj)
            obj.LogArea.Value = {'HubEvent demo ready.'};
        end

        function onDown(obj, E), obj.appendHubEvent(E); end
        function onUp(obj, E), obj.appendHubEvent(E); end
        function onMove(obj, E), obj.appendHubEvent(E); end
        function onScroll(obj, E), obj.appendHubEvent(E); end
        function onKeyPress(obj, E), obj.appendHubEvent(E); end
        function onKeyRelease(obj, E), obj.appendHubEvent(E); end
        function onEnter(obj, E), obj.appendHubEvent(E); end
        function onLeave(obj, E), obj.appendHubEvent(E); end
    end

    methods (Access=private)
        function appendHubEvent(obj, E)
            obj.appendBlock("HUB", E.print());
        end

        function appendBlock(obj, source, txt)
            stamp = string(datetime("now", "Format","HH:mm:ss.SSS"));
            header = "----- " + source + " " + stamp + " -----";
            lines = splitlines(string(txt));
            lines(strlength(lines) == 0) = [];

            current = string(obj.LogArea.Value);
            updated = [current(:); header; lines(:)];

            maxLines = 300;
            if numel(updated) > maxLines
                updated = updated(end-maxLines+1:end);
            end

            obj.LogArea.Value = cellstr(updated);
            scroll(obj.LogArea, "bottom");
        end
    end
end
