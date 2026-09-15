classdef HubEventDemo < matlab.ui.componentcontainer.ComponentContainer
%HUBEVENTDEMO Small app for inspecting FigureEventHub event payloads.

    properties (Access=private)
        Grid matlab.ui.container.GridLayout
        MainPane matlab.ui.container.GridLayout
        SettingsAccordion matlabx.ui.container.Accordion
        ImageAxes matlabx.ui.axes.ImageAxes
        LogArea matlab.ui.control.TextArea
        EventTypeCheckboxes struct = struct()

        Hub matlabx.ui.interaction.FigureEventHub
        ListenerIds struct = struct()
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
        %SETUP Build the controls, axes, log area, and hub registration.
            obj.Grid = uigridlayout(obj, [1 2], ...
                "RowHeight",{'1x'}, ...
                "ColumnWidth",{190,'1x'}, ...
                "Padding",[8 8 8 8], ...
                "ColumnSpacing",8);

            obj.setupEventTypeControls();

            obj.MainPane = uigridlayout(obj.Grid, [2 1], ...
                "RowHeight",{500,'1x'}, ...
                "ColumnWidth",{'1x'}, ...
                "Padding",[0 0 0 0], ...
                "RowSpacing",8);
            obj.MainPane.Layout.Row = 1;
            obj.MainPane.Layout.Column = 2;

            obj.ImageAxes = matlabx.ui.axes.ImageAxes(obj.MainPane, ...
                "Name","HubEventDemoImageAxes", ...
                "CData",obj.demoImage(), ...
                "Tools",{'Zoom','Colorbar','Box'}, ...
                "Colormap",turbo, ...
                "CLim",[0 1], ...
                "ContextMenuItems",["Status","ResetView","Image","Overlays"]);
            obj.ImageAxes.Layout.Row = 1;
            obj.ImageAxes.Layout.Column = 1;

            obj.LogArea = uitextarea(obj.MainPane, ...
                "Editable","off", ...
                "FontName","Menlo", ...
                "FontSize",11, ...
                "Value",{'HubEvent demo ready.'});
            obj.LogArea.Layout.Row = 2;
            obj.LogArea.Layout.Column = 1;

            fig = ancestor(obj, 'Figure');
            obj.Hub = matlabx.ui.interaction.FigureEventHub.ensure(fig);
            obj.addHubListeners();
        end

        function update(~)
        %UPDATE ComponentContainer update hook; demo layout is callback-driven.
        end
    end

    methods
        function delete(obj)
        %DELETE Remove demo listeners from its FigureEventHub.
            if isempty(obj.Hub) || ~isvalid(obj.Hub)
                return
            end

            kinds = string(fieldnames(obj.ListenerIds));
            for i = 1:numel(kinds)
                kind = kinds(i);
                obj.Hub.removeListener(char(kind), obj.ListenerIds.(kind));
            end
        end

        function tf = matches(obj, E)
        %MATCHES True when the event belongs to the embedded ImageAxes.
            tf = obj.imageAxesMatches(E);
        end

        function appendMenuEvent(obj, msg)
        %APPENDMENUEVENT Append a menubar callback event if visible.
            if ~obj.shouldShowEvent("Menu")
                return
            end

            obj.appendBlock("MENU", string(msg));
        end

        function clearLog(obj)
        %CLEARLOG Reset the text-area contents.
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
        function addHubListeners(obj)
        %ADDHUBLISTENERS Attach passive listeners for hub-supported events.
            kinds = ["Down","Move","Up","Scroll", ...
                "KeyPress","KeyRelease","Enter","Leave"];
            for i = 1:numel(kinds)
                kind = kinds(i);
                obj.ListenerIds.(kind) = obj.Hub.addListener(char(kind), ...
                    @(E) obj.appendHubEvent(E), ...
                    "Priority",100);
            end
        end

        function setupEventTypeControls(obj)
        %SETUPEVENTTYPECONTROLS Create the left-side event filter accordion.
            obj.SettingsAccordion = matlabx.ui.container.Accordion(obj.Grid, ...
                "ItemSpacing",5, ...
                "BorderWidth",0, ...
                "BorderColor",[0.18 0.18 0.18], ...
                "Padding",0, ...
                "BackgroundColor",[0.12 0.12 0.12]);
            obj.SettingsAccordion.Layout.Row = 1;
            obj.SettingsAccordion.Layout.Column = 1;

            obj.SettingsAccordion.addItem( ...
                "Title","Event types", ...
                "BorderColor",[0.49 0.49 0.49], ...
                "TitleBackgroundColor",[0.12 0.12 0.12], ...
                "HoverTitleBackgroundColor",[0.30 0.30 0.30], ...
                "PaneBackgroundColor",[0.18 0.18 0.18], ...
                "FontColor",[0.85 0.85 0.85], ...
                "BorderWidth",1, ...
                "ExpandedBorderWidth",1, ...
                "TitlePadding",1);

            item = obj.SettingsAccordion.getItem("Event types");
            item.expand();

            eventTypes = ["Down","Up","Move","Scroll", ...
                "KeyPress","KeyRelease","Enter","Leave","Menu"];
            set(item.Pane, ...
                "RowHeight",repmat({'fit'},1,numel(eventTypes)), ...
                "ColumnWidth",{'1x'}, ...
                "RowSpacing",5, ...
                "ColumnSpacing",0, ...
                "Padding",[5 5 5 5]);

            for i = 1:numel(eventTypes)
                eventType = eventTypes(i);
                fieldName = matlab.lang.makeValidName(eventType);
                obj.EventTypeCheckboxes.(fieldName) = uicheckbox(item.Pane, ...
                    "Text",char(eventType), ...
                    "Value",true, ...
                    "FontColor",[0.85 0.85 0.85]);
                obj.EventTypeCheckboxes.(fieldName).Layout.Row = i;
                obj.EventTypeCheckboxes.(fieldName).Layout.Column = 1;
            end
        end

        function appendHubEvent(obj, E)
        %APPENDHUBEVENT Append a HubEvent if its event kind is visible.
            if ~obj.imageAxesMatches(E)
                return
            end

            if ~obj.shouldShowEvent(E.Kind)
                return
            end

            obj.appendBlock("HUB", E.print());
        end

        function tf = imageAxesMatches(obj, E)
        %IMAGEAXESMATCHES Ask the embedded ImageAxes if this event belongs to it.
            tf = false;
            if isempty(obj.ImageAxes) || ~isvalid(obj.ImageAxes)
                return
            end

            if E.isHoverEvent() && ~isempty(E.Claimant)
                % For Leave events, the hittest target is often already
                % outside the ImageAxes. The synthetic claimant identifies
                % which registrant actually entered or left hover.
                tf = isequal(E.Claimant, obj.ImageAxes);
            else
                tf = obj.ImageAxes.matches(E);
            end
        end

        function appendBlock(obj, source, txt)
        %APPENDBLOCK Append a timestamped block of text to the log area.
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

        function tf = shouldShowEvent(obj, eventType)
        %SHOULDSHOWEVENT True when the event type checkbox is enabled.
            fieldName = matlab.lang.makeValidName(string(eventType));
            if ~isfield(obj.EventTypeCheckboxes, fieldName)
                tf = true;
                return
            end

            checkbox = obj.EventTypeCheckboxes.(fieldName);
            tf = ~isempty(checkbox) && isvalid(checkbox) && checkbox.Value;
        end
    end

    methods (Static, Access=private)
        function I = demoImage()
        %DEMOIMAGE Return a small image with visible structure for interaction.
            [X,Y] = meshgrid(linspace(-2,2,256), linspace(-2,2,256));
            I = exp(-((X+0.55).^2 + (Y-0.35).^2) .* 3) ...
                + 0.75*exp(-((X-0.75).^2 + (Y+0.45).^2) .* 7) ...
                + 0.15*sin(8*X).*cos(6*Y);
            I = rescale(I);
        end
    end
end
