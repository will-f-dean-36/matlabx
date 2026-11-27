classdef PlotAxes < matlab.ui.componentcontainer.ComponentContainer
%PLOTAXES Stable axes host for transferable plot-content renderers.
%
% PlotAxes mirrors the host/content boundary and pluggable-tool conventions
% used by ImageAxes while retaining plot-specific collaborators. The host owns
% the axes, layout, presentation, toolbar, and context menu. A PlotContent
% object owns plot primitives and can move between PlotAxes hosts without
% reparenting this container.
%
% PlotAxes registers once with FigureEventHub and forwards normalized events
% to its mounted content. Keeping the axes stable gives the hub one durable
% registrant per panel, independent of the currently mounted renderer.
%
% Create a host, prepare renderer data and style, then mount the renderer:
%
%   fig = uifigure;
%   host = matlabx.ui.axes.PlotAxes(fig);
%   renderer = matlabx.ui.axes.plot.ScatterRenderer;
%   data = matlabx.ui.axes.plot.ScatterData( ...
%       XData={[1 2 3]}, YData={[2 1 4]}, SeriesNames="Samples", ...
%       CData={[0.2 0.5 0.8]});
%   renderer.update(data,matlabx.ui.axes.plot.ScatterStyle(Title="Example"));
%   host.mount(renderer);
%
% Content remains application-owned and reusable. clear detaches it without
% deleting it, and mounting the same content in another PlotAxes transfers it.
%
% See also matlabx.ui.axes.PlotContent, matlabx.ui.axes.PlotAxesTool,
% matlabx.ui.axes.PlotAxesToolManager,
% matlabx.ui.axes.PlotAxesContextMenuManager,
% matlabx.ui.axes.plot.ScatterRenderer,
% matlabx.ui.axes.plot.ViolinRenderer

% matlabx - MATLAB utilities for app building, image display, and analysis.
% Copyright (C) 2026 William Dean
%
% This program is free software; you can redistribute it and/or modify it
% under the terms of the GNU General Public License as published by the Free
% Software Foundation; either version 2 of the License, or (at your option)
% any later version.
%
% This program is distributed in the hope that it will be useful, but WITHOUT
% ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
% FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
% details.
%
% You should have received a copy of the GNU General Public License along
% with this program; if not, see <https://www.gnu.org/licenses/>.

    % Public host identity and appearance applied to the stable UIAxes.
    properties (AbortSet)
        % Identifier assigned to the underlying axes Tag.
        Name (1,1) string = ""
        % Foreground color used for rulers, labels, title, and subtitle.
        ForegroundColor (1,3) double {mustBeBetween(ForegroundColor,0,1)} = [0 0 0]
        % Plotting-area color, or "none" for a transparent axes background.
        Color = [1 1 1]
        % Plot container fill override. [] uses the renderer or host color.
        BackgroundColorOverride double {mustBeOptionalRGB_} = []
        % Plotting-area fill override. [] uses the renderer or host color.
        AxesColorOverride {mustBeOptionalAxesColor_} = []
        % Ruler and label color override. [] uses the renderer or host color.
        ForegroundColorOverride double {mustBeOptionalRGB_} = []
        % Font family applied to axes text.
        FontName (1,1) string = "Helvetica"
        % Units used for tick-label, title, subtitle, and axes-label font sizes.
        FontUnits (1,1) string {mustBeMember(FontUnits,["points","pixels"])} = "points"
        % Base axes font size used by tick labels.
        FontSize (1,1) double {mustBePositive,mustBeFinite} = 9
        % Native multiplier used by MATLAB for axes-label font sizes.
        LabelFontSizeMultiplier (1,1) double {mustBePositive,mustBeFinite} = 1
        % Native multiplier used by MATLAB for title font size.
        TitleFontSizeMultiplier (1,1) double {mustBePositive,mustBeFinite} = 1
        % Axes frame and tick stroke width in points.
        AxisLineWidth (1,1) double {mustBePositive,mustBeFinite} = 0.5
        % Tick lengths as fractions of the longest axes dimension (2-D, 3-D).
        TickLength (1,2) double {mustBeNonnegative,mustBeFinite} = [0.01 0.025]
        % Direction of major and minor ticks.
        TickDirection (1,1) string {mustBeMember(TickDirection,["in","out","both","none"])} = "in"
    end

    % Configurable host UI and installed-tool state.
    properties (Dependent)
        % Installed PlotAxesTool objects; assignment replaces built-in tools.
        Tools
        % Built-in context-menu entries shown by the host.
        ContextMenuItems
        % Requested visibility of the axes toolbar.
        ToolbarVisible (1,1) matlab.lang.OnOffSwitchState
        % Expanded or collapsed state of the axes toolbar.
        ToolbarExpanded (1,1) matlab.lang.OnOffSwitchState
        % Visibility of the major Cartesian grid.
        GridVisible (1,1) matlab.lang.OnOffSwitchState
        % Visibility of the Cartesian axes box.
        BoxVisible (1,1) matlab.lang.OnOffSwitchState
        % Visibility of the axes title.
        TitleVisible (1,1) matlab.lang.OnOffSwitchState
    end

    % Read-only access to the mounted renderer and stable UIAxes.
    properties (Dependent, SetAccess=private)
        % Application-owned PlotContent currently mounted in this host.
        Content
        % Stable UIAxes used by renderers and future tools.
        Axes
    end

    properties (SetAccess=private)
        % Host view overrides. Empty fields inherit the plot defaults.
        AxesView struct = struct("XLim",[],"YLim",[], ...
            "XTickInterval",[],"YTickInterval",[],"LegendVisible","default", ...
            "RightYLim",[],"LeftYColor",[],"RightYColor",[])
    end

    % Graphics, listener, and content references owned by the host lifecycle.
    properties (Access={?matlabx.ui.axes.PlotAxesTool, ...
            ?matlabx.ui.axes.PlotAxesToolManager}, Transient, NonCopyable)
        % Grid containing the stable axes.
        Grid matlab.ui.container.GridLayout
        % UIAxes retained while renderer content changes.
        MainAxes matlab.ui.control.UIAxes
        % Listener that detaches content before axes graphics are destroyed.
        AxesLifetimeListener event.listener = event.listener.empty()
        % One-shot listener used when toolbar buttons are created while hidden.
        InitialToolbarFocusListener event.listener = event.listener.empty()
        % Backing reference for the currently mounted content.
        Content_ (:,1) matlabx.ui.axes.PlotContent = matlabx.ui.axes.PlotContent.empty(0,1)
        % Shared figure event router used by this stable host.
        Hub matlabx.ui.interaction.FigureEventHub
        % Registration identifier assigned by FigureEventHub.
        RouterId double = NaN
        % Tool lifecycle, toolbar, context-menu, and hotkey collaborators.
        ToolManager matlabx.ui.axes.PlotAxesToolManager
        HotkeyRegistry matlabx.ui.axes.PlotAxesHotkeyRegistry
        ContextMenuManager matlabx.ui.axes.PlotAxesContextMenuManager
        % Toolbar buttons keyed by installed tool name.
        ToolbarButtons struct = struct()
        % Currently enabled exclusive tool, when present.
        ActiveExclusiveTool = []
        % Status report window owned by this host.
        StatusWindow matlabx.app.TextWindow
    end

    properties (Access=private, AbortSet)
        % Backing built-in context-menu configuration.
        ContextMenuItems_ (1,:) string = ["Display","AxesProperties","ResetView","Status"]
        % Backing requested toolbar visibility.
        ToolbarVisible_ (1,1) matlab.lang.OnOffSwitchState = "on"
        % Backing expanded or collapsed toolbar state.
        ToolbarExpanded_ (1,1) matlab.lang.OnOffSwitchState = "on"
        % Backing major-grid visibility.
        GridVisible_ (1,1) matlab.lang.OnOffSwitchState = "off"
        % Backing axes-box visibility.
        BoxVisible_ (1,1) matlab.lang.OnOffSwitchState = "off"
        % Backing axes-title visibility.
        TitleVisible_ (1,1) matlab.lang.OnOffSwitchState = "off"
        % Shared axes properties dialog for this host.
        AxesPropertiesDialog = []
        % Whether the status report window is currently open.
        StatusWindowOpen_ (1,1) logical = false
        % Whether tool teardown has already run for this host.
        ToolsTornDown_ (1,1) logical = false
        % Whether the ComponentContainer still has its first update pending.
        FirstUpdatePending_ (1,1) logical = true
    end

    % Notifications emitted when the mounted content relationship changes.
    events
        % Emitted after content is mounted, transferred, or cleared.
        ContentChanged
    end

    events (NotifyAccess=private)
        % Emitted once after the native Axes Properties dialog accepts Apply.
        AxesPropertiesCommitted
    end

    methods

        function set.Color(obj,value)
        %SET.COLOR Validate and normalize the plotting-area color.
            obj.Color = normalizeAxesColor_(value,'Color');
        end

        function content = get.Content(obj)
        %GET.CONTENT Return the renderer currently mounted in this host.

            content = obj.Content_;
        end

        function axes = get.Axes(obj)
        %GET.AXES Expose the stable target axes to renderers and future tools.

            axes = obj.MainAxes;
        end

        function tools = get.Tools(obj)
        %GET.TOOLS Return installed PlotAxesTool objects keyed by name.
            tools = obj.ToolManager.Tools;
        end

        function set.Tools(obj,toolNames)
        %SET.TOOLS Replace the installed set of manager-owned built-in tools.
            obj.ToolManager.setInstalledNames(toolNames);
        end

        function items = get.ContextMenuItems(obj)
        %GET.CONTEXTMENUITEMS Return configured built-in menu tokens.
            items = obj.ContextMenuItems_;
        end

        function set.ContextMenuItems(obj,items)
        %SET.CONTEXTMENUITEMS Validate and rebuild the built-in context menu.
            items = matlabx.ui.axes.PlotAxesContextMenuManager.validateBuiltinItems(items);
            obj.ContextMenuItems_ = items;
            if ~isempty(obj.ContextMenuManager) && isvalid(obj.ContextMenuManager)
                obj.ContextMenuManager.setBuiltinItems(items);
            end
        end

        function value = get.ToolbarVisible(obj)
        %GET.TOOLBARVISIBLE Return requested toolbar visibility.
            value = obj.ToolbarVisible_;
        end

        function set.ToolbarVisible(obj,value)
        %SET.TOOLBARVISIBLE Show or hide the hosted axes toolbar.
            obj.ToolbarVisible_ = value;
            if ~isempty(obj.MainAxes) && isvalid(obj.MainAxes) && ...
                    ~isempty(obj.MainAxes.Toolbar) && isvalid(obj.MainAxes.Toolbar) && ...
                    ~obj.FirstUpdatePending_
                obj.MainAxes.Toolbar.Visible = value;
            end
            obj.refreshContextMenu();
        end

        function value = get.ToolbarExpanded(obj)
        %GET.TOOLBAREXPANDED Return the native toolbar expansion state.
            value = obj.ToolbarExpanded_;
            if ~isempty(obj.MainAxes) && isvalid(obj.MainAxes) && ...
                    ~isempty(obj.MainAxes.Toolbar) && isvalid(obj.MainAxes.Toolbar)
                value = obj.MainAxes.Toolbar.Expanded;
            end
        end

        function set.ToolbarExpanded(obj,value)
        %SET.TOOLBAREXPANDED Expand or collapse the hosted axes toolbar.
            obj.ToolbarExpanded_ = value;
            if ~isempty(obj.MainAxes) && isvalid(obj.MainAxes) && ...
                    ~isempty(obj.MainAxes.Toolbar) && isvalid(obj.MainAxes.Toolbar)
                obj.MainAxes.Toolbar.Expanded = value;
            end
        end

        function value = get.GridVisible(obj)
        %GET.GRIDVISIBLE Return major-grid visibility.
            value = obj.GridVisible_;
        end

        function set.GridVisible(obj,value)
        %SET.GRIDVISIBLE Show or hide both major Cartesian grid directions.
            obj.GridVisible_ = value;
            if ~isempty(obj.MainAxes) && isvalid(obj.MainAxes) ...
                    && any(obj.getAxesCapabilities() == "Grid")
                obj.MainAxes.XGrid = value;
                obj.MainAxes.YGrid = value;
            end
            obj.refreshContextMenu();
        end

        function value = get.BoxVisible(obj)
        %GET.BOXVISIBLE Return axes-box visibility.
            value = obj.BoxVisible_;
        end

        function set.BoxVisible(obj,value)
        %SET.BOXVISIBLE Show or hide the Cartesian axes box.
            obj.BoxVisible_ = value;
            if ~isempty(obj.MainAxes) && isvalid(obj.MainAxes) ...
                    && any(obj.getAxesCapabilities() == "Box")
                obj.MainAxes.Box = value;
            end
            obj.refreshContextMenu();
        end

        function value = get.TitleVisible(obj)
        %GET.TITLEVISIBLE Return requested axes-title visibility.
            value = obj.TitleVisible_;
        end

        function set.TitleVisible(obj,value)
        %SET.TITLEVISIBLE Show or hide the hosted axes title.
            obj.TitleVisible_ = value;
            if ~isempty(obj.MainAxes) && isvalid(obj.MainAxes) ...
                    && any(obj.getAxesCapabilities() == "Typography")
                obj.MainAxes.Title.Visible = value;
            end
            obj.refreshContextMenu();
        end

        function installTool(obj,toolOrName)
        %INSTALLTOOL Install a built-in name or application-owned PlotAxesTool.
            if ~(isa(toolOrName,'matlabx.ui.axes.PlotAxesTool'))
                name = string(toolOrName);
                if isempty(obj.ToolManager.getLoaded(name))
                    obj.ToolManager.load(name);
                end
            end
            obj.ToolManager.install(toolOrName);
        end

        function uninstallTool(obj,toolOrName)
        %UNINSTALLTOOL Remove tool contributions without deleting borrowed tools.
            obj.ToolManager.uninstall(toolOrName);
        end

        function tool = getInstalledTool(obj,name)
        %GETINSTALLEDTOOL Return an installed PlotAxesTool by name.
            tool = obj.ToolManager.getInstalled(name);
        end

        function registerTool(obj,tool)
        %REGISTERTOOL Register a PlotAxesTool and construct its contributions.
            obj.ToolManager.register(tool);
        end

        function unregisterTool(obj,tool)
        %UNREGISTERTOOL Remove one tool's host-owned contributions.
            obj.ToolManager.unregister(tool);
        end

        function registerToolHotkeys(obj,tool)
        %REGISTERTOOLHOTKEYS Register one tool's optional toggle hotkey.
            if strlength(tool.ToggleHotkey) == 0, return; end
            obj.HotkeyRegistry.add(tool.ToggleHotkey, ...
                @(E) obj.onToolToggleHotkey(tool.Name,E), ...
                Owner=tool,Description=tool.Name + " toggle", ...
                Priority=tool.Priority);
        end

        function disableActiveExclusive(obj)
        %DISABLEACTIVEEXCLUSIVE Disable the currently enabled exclusive tool.
            obj.ToolManager.disableActiveExclusive();
        end

        function onToolPush(obj,name)
        %ONTOOLPUSH Run the push tool associated with a toolbar button.
            obj.releaseToolbarFocus_();
            obj.ToolManager.push(name);
        end

        function onToolToggle(obj,value,name)
        %ONTOOLTOGGLE Apply a toolbar state-button change to its tool.
            obj.releaseToolbarFocus_();
            obj.ToolManager.toggle(logical(value),name);
        end

        function onToolToggleHotkey(obj,name,event)
        %ONTOOLTOGGLEHOTKEY Run or toggle a tool from its registered hotkey.
            tool = obj.getInstalledTool(name);
            if isempty(tool), return; end
            event.stop();
            if strcmp(tool.Style,'push')
                obj.ToolManager.run(name);
            elseif tool.Enabled
                obj.ToolManager.disable(name);
            else
                obj.ToolManager.enable(name);
            end
        end

        function resetView(obj)
        %RESETVIEW Restore the mounted renderer's intended presentation.
        %   The host baseline is restored first so presentation left by user
        %   navigation or axes interaction cannot leak into the refreshed
        %   renderer. The renderer then reapplies its stored data and style,
        %   including deliberate limits such as violin category margins.
            obj.resetAxes();
            if ~isempty(obj.Content_) && isvalid(obj.Content_)
                obj.Content_.refresh();
            end
            obj.applyAxesView();
        end

        function capabilities = getAxesCapabilities(obj)
        %GETAXESCAPABILITIES Return supported shared controls for the current plot.
            if isempty(obj.Content_)
                capabilities = obj.cartesianAxesCapabilities();
            else
                capabilities = string(obj.Content_.axesCapabilities());
            end
            if ~isempty(obj.MainAxes) && numel(obj.MainAxes.YAxis) == 2
                if any(capabilities == "YLim"), capabilities(end+1) = "RightYLim"; end
                if any(capabilities == "Colors")
                    capabilities = [reshape(capabilities,1,[]),"LeftYColor","RightYColor"];
                end
            end
        end

        function [defaults,declared] = getAxesViewDefaults(obj)
        %GETAXESVIEWDEFAULTS Resolve renderer defaults over the host defaults.
        %   DECLARED lists settings supplied by the renderer. A live reset
        %   can inherit those settings and explicitly apply the host fallback
        %   for properties the renderer leaves unspecified.
            defaults = struct("XLim","auto","YLim","auto", ...
                "XTickInterval","auto","YTickInterval","auto","LegendVisible","off", ...
                "RightYLim","auto","LeftYColor",[],"RightYColor",[]);
            declared = string.empty;
            if isempty(obj.Content_), return; end

            % Accept renderer values only for recognized, supplied settings.
            rendererDefaults = obj.Content_.axesViewDefaults();
            for name = reshape(string(fieldnames(defaults)),1,[])
                if isfield(rendererDefaults,name) && ~isempty(rendererDefaults.(name))
                    defaults.(name) = rendererDefaults.(name);
                    declared(end+1) = name; %#ok<AGROW>
                end
            end
        end

        function settings = getAxesSettings(obj)
        %GETAXESSETTINGS Snapshot the requested axes appearance and view.
        %   SETTINGS is a scalar struct of graphics-independent values for
        %   storage and later use with applyAxesSettings. The nested AxesView
        %   retains manual ranges, "auto", and inherited defaults ([]).
        %   Panning and zooming the native axes do not change this snapshot.
            settings = struct();
            % Read host requests directly instead of reading rendered graphics.
            groups = axesSettingsGroups_();
            for group = reshape(string(fieldnames(groups)),1,[])
                for name = groups.(group)
                    value = obj.(name);
                    if isa(value,'matlab.lang.OnOffSwitchState'), value = logical(value); end
                    if ischar(value), value = string(value); end
                    settings.(name) = value;
                end
            end
            settings.AxesView = obj.AxesView;
            for name = reshape(string(fieldnames(settings.AxesView)),1,[])
                value = settings.AxesView.(name);
                if ischar(value), settings.AxesView.(name) = string(value); end
            end
        end

        function applyAxesSettings(obj,settings)
        %APPLYAXESSETTINGS Replace the requested axes appearance and view.
        %   Restore a complete getAxesSettings snapshot after mounting the
        %   target renderer. Unsupported settings are cleared. This does not
        %   emit AxesPropertiesCommitted.
        %   Legacy snapshots without the dual-Y fields are accepted for now.
        %   Persist the full field set returned by getAxesSettings for
        %   compatibility with future exact-field validation.
            obj.applyAxesSettings_(settings);
            obj.applyAxesView();
        end

        function setAxesView(obj,opts)
        %SETAXESVIEW Override selected limits, tick intervals, or legend visibility.
        %   SETAXESVIEW(XLim=[min max]) holds that view across renderer updates.
        %   Use "auto" for automatic framing or [] to inherit the plot default.
        %   On dual-Y axes YLim addresses the left ruler and RightYLim the
        %   right ruler. LeftYColor and RightYColor accept RGB or [] to inherit.
        %   Tick intervals are positive distances in data units on linear axes.
        %   Use "auto" for automatic ticks or [] for plot-defined ticks. LegendVisible accepts "on", "off",
        %   or "default". Omitted options retain their values.
            arguments
                obj (1,1) matlabx.ui.axes.PlotAxes
                opts.XLim {mustBeViewLimits_}
                opts.YLim {mustBeViewLimits_}
                opts.RightYLim {mustBeViewLimits_}
                opts.LeftYColor double {mustBeOptionalRGB_}
                opts.RightYColor double {mustBeOptionalRGB_}
                opts.XTickInterval {mustBeTickInterval_}
                opts.YTickInterval {mustBeTickInterval_}
                opts.LegendVisible (1,1) string ...
                    {mustBeMember(opts.LegendVisible,["default","on","off"])}
            end

            names = string(fieldnames(opts));
            capabilities = obj.getAxesCapabilities();
            if any(capabilities == "Legend")
                capabilities(end+1) = "LegendVisible";
            end
            unsupported = setdiff(names,capabilities);
            for name = reshape(unsupported,1,[])
                if ~isempty(opts.(name)) && ~isequal(opts.(name),"default")
                    error('matlabx:ui:axes:UnsupportedAxesSetting', ...
                        'The current plot does not support %s.',name);
                end
            end

            oldView = obj.AxesView;
            view = oldView;
            for name = reshape(names,1,[])
                view.(name) = opts.(name);
            end
            if isequal(view,oldView), return; end
            ax = obj.MainAxes;
            obj.AxesView = view;
            for axisName = ["X","Y"]
                limits = axisName + "Lim";
                interval = axisName + "TickInterval";
                if any(capabilities == limits) && isempty(view.(limits)) && ~isempty(oldView.(limits))
                    setPlotLimit_(ax,limits,[]);
                end
                if any(capabilities == interval) && isempty(view.(interval)) && ~isempty(oldView.(interval))
                    setPlotTickMode_(ax,axisName);
                end
            end

            if any(capabilities == "RightYLim") && isempty(view.RightYLim) && ~isempty(oldView.RightYLim)
                setPlotLimit_(ax,"RightYLim",[]);
            end
            refresh = (isempty(view.RightYLim) && ~isempty(oldView.RightYLim)) ...
                || (isempty(view.XLim) && ~isempty(oldView.XLim)) ...
                || (isempty(view.YLim) && ~isempty(oldView.YLim)) ...
                || (isempty(view.XTickInterval) && ~isempty(oldView.XTickInterval)) ...
                || (isempty(view.YTickInterval) && ~isempty(oldView.YTickInterval)) ...
                || view.LegendVisible ~= oldView.LegendVisible;
            if refresh && ~isempty(obj.Content_) && isvalid(obj.Content_)
                % A renderer may visit both sides when restoring its defaults.
                if numel(ax.YAxis) == 2
                    activeSide = ax.YAxisLocation;
                    restoreSide = onCleanup(@() restorePlotYSide_(ax,activeSide));
                end
                obj.Content_.refresh();
            end
            obj.applyAxesView();
        end

        function applyAxesView(obj)
        %APPLYAXESVIEW Reapply host overrides after rendering chart defaults.
        %   PlotContent.refresh does this automatically for refreshGraphics
        %   implementations. Legacy refresh overrides can call it last.
            ax = obj.MainAxes;
            if isempty(ax) || ~isvalid(ax) || ax.BeingDeleted == "on", return; end
            capabilities = obj.getAxesCapabilities();
            for axisName = ["X","Y","RightY"]
                property = axisName + "Lim";
                limits = obj.AxesView.(property);
                if isempty(limits) || ~any(capabilities == property), continue; end
                if ischar(limits) || isstring(limits)
                    limits = [];
                    if ~isempty(obj.Content_)
                        limits = obj.Content_.automaticAxesLimits(axisName);
                    end
                end
                setPlotLimit_(ax,property,limits);
            end
            if numel(ax.YAxis) == 2 && any(capabilities == "LeftYColor")
                colors = obj.getYAxisDefaultColors();
                ax.YAxis(1).Color = colorOverride_(colors(1,:),obj.AxesView.LeftYColor);
                ax.YAxis(2).Color = colorOverride_(colors(2,:),obj.AxesView.RightYColor);
            end
            obj.applyTickInterval_("X");
            obj.applyTickInterval_("Y");
            obj.applyRulerStyle();
            if any(capabilities == "Legend") && obj.AxesView.LegendVisible ~= "default"
                if isempty(ax.Legend)
                    if obj.AxesView.LegendVisible == "on", legend(ax,'show'); end
                else
                    ax.Legend.Visible = obj.AxesView.LegendVisible;
                end
            end
        end

        function colors = getYAxisDefaultColors(obj)
        %GETYAXISDEFAULTCOLORS Resolve renderer defaults for left and right.
            % Use the same color-order entries as native yyaxis by default.
            order = obj.MainAxes.ColorOrder;
            colors = order([1,min(2,size(order,1))],:);
            if ~isempty(obj.Content_)
                rendererColors = obj.Content_.yAxisDefaultColors();
                if ~isempty(rendererColors)
                    validateattributes(rendererColors,{'double'}, ...
                        {'size',[2 3],'finite','real','>=',0,'<=',1});
                    colors = rendererColors;
                end
            end
        end

        function visible = resolveLegendVisibility(obj,default)
        %RESOLVELEGENDVISIBILITY Let renderers create their own legend entries.
            visible = default;
            setting = obj.AxesView.LegendVisible;
            if setting ~= "default" && any(obj.getAxesCapabilities() == "Legend")
                visible = setting == "on";
            end
        end

        function openAxesProperties(obj)
        %OPENAXESPROPERTIES Open shared appearance and view controls.
            if isgraphics(obj.AxesPropertiesDialog)
                figure(obj.AxesPropertiesDialog);
                return;
            end
            obj.AxesPropertiesDialog = matlabx.ui.axes.PlotAxesPropertiesDialog.open(obj);
        end

        function toggleToolbar(obj)
        %TOGGLETOOLBAR Toggle the requested toolbar visibility.
            obj.ToolbarVisible = ~logical(obj.ToolbarVisible);
        end

        function toggleGrid(obj)
        %TOGGLEGRID Toggle both major Cartesian grid directions.
            obj.GridVisible = ~logical(obj.GridVisible);
        end

        function toggleBox(obj)
        %TOGGLEBOX Toggle the axes box.
            obj.BoxVisible = ~logical(obj.BoxVisible);
        end

        function toggleTitle(obj)
        %TOGGLETITLE Toggle axes-title visibility.
            obj.TitleVisible = ~logical(obj.TitleVisible);
        end

        function S = getStatusSummary(obj)
        %GETSTATUSSUMMARY Return a compact host/content/tool status report.
            contentClass = "";
            if ~isempty(obj.Content_), contentClass = string(class(obj.Content_)); end
            S = struct( ...
                "Name",obj.Name, ...
                "ContentClass",contentClass, ...
                "XLim",obj.MainAxes.XLim, ...
                "YLim",obj.MainAxes.YLim, ...
                "XScale",string(obj.MainAxes.XScale), ...
                "YScale",string(obj.MainAxes.YScale), ...
                "Color",obj.Color, ...
                "FontName",obj.FontName, ...
                "FontUnits",obj.FontUnits, ...
                "FontSize",obj.FontSize, ...
                "LabelFontSizeMultiplier",obj.LabelFontSizeMultiplier, ...
                "TitleFontSizeMultiplier",obj.TitleFontSizeMultiplier, ...
                "TitleVisible",string(obj.TitleVisible), ...
                "ToolbarVisible",string(obj.ToolbarVisible), ...
                "ToolbarExpanded",string(obj.ToolbarExpanded), ...
                "GridVisible",string(obj.GridVisible), ...
                "BoxVisible",string(obj.BoxVisible), ...
                "Tools",string(fieldnames(obj.Tools)).');
            if numel(obj.MainAxes.YAxis) == 2
                S.YLim = obj.MainAxes.YAxis(1).Limits;
                S.YScale = string(obj.MainAxes.YAxis(1).Scale);
                S.RightYLim = obj.MainAxes.YAxis(2).Limits;
                S.RightYScale = string(obj.MainAxes.YAxis(2).Scale);
            end
        end

        function openStatusWindow(obj)
        %OPENSTATUSWINDOW Open the PlotAxes operational status report.
            if obj.StatusWindowOpen_ && ~isempty(obj.StatusWindow) && ...
                    isvalid(obj.StatusWindow)
                return
            end
            lines = cellstr(matlabx.struct.prettyPrint( ...
                obj.getStatusSummary(),StringArrayStyle="lines"));
            obj.StatusWindow = matlabx.app.TextWindow( ...
                Title="PlotAxes Status",Text=lines, ...
                ClosedFcn=@(~,~) obj.onStatusWindowClosed_());
            obj.StatusWindowOpen_ = true;
        end

        function exportPlot(obj,filename,opts)
        %EXPORTPLOT Export the assembled plot axes as vector or raster graphics.
        %   Units, dimensions, background, and aspect-ratio settings apply to
        %   both output types. Resolution controls raster output and embedded
        %   raster content in otherwise vector-capable formats. Set Width
        %   or Height to [] to derive it from the captured aspect ratio.
        %   StyleSizing="physical" approximately preserves physical sizes
        %   for host typography, ruler strokes, and participating content.
        %   It requires aspect preservation. "scale" retains ordinary sizing.
            arguments
                obj (1,1) matlabx.ui.axes.PlotAxes
                filename (1,1) string {mustBeNonzeroLengthText}
                opts.ContentType (1,1) string {mustBeMember(opts.ContentType, ...
                    ["auto","vector","image"])} = "auto"
                opts.Units (1,1) string {mustBeMember(opts.Units, ...
                    ["inches","centimeters","pixels","points"])} = "inches"
                opts.Width double {mustBeExportDimension_} = 7
                opts.Height double {mustBeExportDimension_} = 5
                opts.BackgroundColor {mustBeAxesColor_(opts.BackgroundColor)} = "none"
                opts.Color {mustBeAxesColor_(opts.Color)} = "none"
                opts.ForegroundColor (1,3) double ...
                    {mustBeBetween(opts.ForegroundColor,0,1)} = ...
                    colorOverride_(obj.ForegroundColor,obj.ForegroundColorOverride)
                opts.FontName (1,1) string = obj.FontName
                opts.FontUnits (1,1) string {mustBeMember(opts.FontUnits, ...
                    ["points","pixels"])} = obj.FontUnits
                opts.FontSize (1,1) double {mustBePositive,mustBeFinite} = obj.FontSize
                opts.LabelFontSizeMultiplier (1,1) double ...
                    {mustBePositive,mustBeFinite} = obj.LabelFontSizeMultiplier
                opts.TitleFontSizeMultiplier (1,1) double ...
                    {mustBePositive,mustBeFinite} = obj.TitleFontSizeMultiplier
                opts.GridVisible (1,1) matlab.lang.OnOffSwitchState = obj.GridVisible
                opts.BoxVisible (1,1) matlab.lang.OnOffSwitchState = obj.BoxVisible
                opts.TitleVisible (1,1) matlab.lang.OnOffSwitchState = obj.TitleVisible
                opts.StyleSizing (1,1) string {mustBeMember(opts.StyleSizing, ...
                    ["physical","scale"])} = "scale"
                opts.PreserveAspectRatio = []
                opts.Resolution (1,1) double {mustBePositive} = 300
                opts.HideToolbar (1,1) logical = true
            end

            dimensions = struct();
            outputSize = [NaN NaN];
            if ~isempty(opts.Width)
                dimensions.Width = opts.Width;
                outputSize(1) = opts.Width;
            end
            if ~isempty(opts.Height)
                dimensions.Height = opts.Height;
                outputSize(2) = opts.Height;
            end
            if isempty(fieldnames(dimensions))
                error('matlabx:ui:axes:PlotAxes:MissingExportSize', ...
                    'Specify at least one export dimension.');
            end

            preserveAspect = opts.PreserveAspectRatio;
            if isempty(preserveAspect)
                preserveAspect = opts.StyleSizing == "physical";
            end
            preserveAspect = matlab.lang.OnOffSwitchState(preserveAspect);
            validateattributes(preserveAspect,{'matlab.lang.OnOffSwitchState'},{'scalar'});
            preserveAspect = char(preserveAspect);
            if any(isnan(outputSize))
                preserveAspect = 'on';
            elseif opts.StyleSizing == "physical" && strcmp(preserveAspect,'off')
                error('matlabx:ui:axes:PlotAxes:PhysicalSizingRequiresAspect', ...
                    'Physical sizing requires preserving the aspect ratio.');
            end

            appearance = struct( ...
                "Color",obj.Color, ...
                "AxesColorOverride",obj.AxesColorOverride, ...
                "ForegroundColorOverride",obj.ForegroundColorOverride, ...
                "ForegroundColor",obj.ForegroundColor, ...
                "FontName",obj.FontName, ...
                "FontUnits",obj.FontUnits, ...
                "FontSize",obj.FontSize, ...
                "LabelFontSizeMultiplier",obj.LabelFontSizeMultiplier, ...
                "TitleFontSizeMultiplier",obj.TitleFontSizeMultiplier, ...
                "GridVisible",obj.GridVisible, ...
                "BoxVisible",obj.BoxVisible, ...
                "TitleVisible",obj.TitleVisible);
            appearanceCleanup = onCleanup( ...
                @() restorePlotAppearance_(obj,appearance));
            obj.AxesColorOverride = [];
            obj.ForegroundColorOverride = [];
            obj.Color = opts.Color;
            obj.ForegroundColor = opts.ForegroundColor;
            obj.FontName = opts.FontName;
            obj.FontUnits = opts.FontUnits;
            obj.FontSize = opts.FontSize;
            obj.LabelFontSizeMultiplier = opts.LabelFontSizeMultiplier;
            obj.TitleFontSizeMultiplier = opts.TitleFontSizeMultiplier;
            obj.GridVisible = opts.GridVisible;
            obj.BoxVisible = opts.BoxVisible;
            obj.TitleVisible = opts.TitleVisible;
            drawnow;

            toolbar = obj.MainAxes.Toolbar;
            if opts.HideToolbar && ~isempty(toolbar) && isvalid(toolbar)
                toolbarVisible = toolbar.Visible;
                toolbarCleanup = onCleanup( ...
                    @() restoreToolbar_(toolbar,toolbarVisible));
                toolbar.Visible = 'off';
            end
            dimensionArgs = namedargs2cell(dimensions);
            exportWithSizing();

            function exportWithSizing()
                ax = obj.MainAxes;
                if opts.StyleSizing == "physical"
                    innerSize = ax.InnerPosition(3:4);
                    inset = ax.TightInset;
                    capturedPixels = innerSize + inset(1:2) + inset(3:4);
                    sourceInches = capturedPixels ./ get(groot,'ScreenPixelsPerInch');
                    scale = matlabx.ui.axes.internal.exportStyleScale( ...
                        sourceInches,outputSize,opts.Units,opts.Resolution,preserveAspect);
                    % Automatic labels and titles follow the axes font size.
                    labels = [ax.XLabel,plotYLabels_(ax),ax.ZLabel,ax.Title,ax.Subtitle];
                    manual = strcmp({labels.FontSizeMode},'manual');
                    ownedGraphics = [{ax},arrayfun(@(h) h,labels(manual),UniformOutput=false)];
                    axesStyleCleanup = matlabx.ui.axes.internal.scaleExportGraphics( ...
                        ownedGraphics,scale,["FontSize","LineWidth"]);
                    if ~isempty(obj.Content_) && isvalid(obj.Content_)
                        contentCleanup = obj.Content_.beginExportStyleScale(scale);
                    end
                end

                writePlotExport_(ax,filename,opts,dimensionArgs,preserveAspect);
                clear contentCleanup axesStyleCleanup
            end
        end

        function filename = chooseExportPlot(obj)
        %CHOOSEEXPORTPLOT Choose plot export options and an output file.
        %   Returns the absolute filename, or an empty string when either
        %   dialog is cancelled. Interactive exports always omit the toolbar.
            filename = "";

            % Keep modal option/file dialogs in front of an always-on-top host.
            fig = ancestor(obj.Parent,'figure');
            previousWindowStyle = fig.WindowStyle;
            if strcmp(previousWindowStyle,'alwaysontop')
                fig.WindowStyle = 'normal';
            end
            windowStyleCleanup = onCleanup( ...
                @() restoreFigureWindowStyle_(fig,previousWindowStyle));

            drawnow;
            % Resolve automatic limits after the initial component update.
            drawnow;
            source = obj.MainAxes;
            inset = source.TightInset;
            capturedSize = source.InnerPosition(3:4) + inset(1:2) + inset(3:4);
            aspectRatio = capturedSize(1) / capturedSize(2);
            previewBackground = obj.Grid.BackgroundColor;
            exportFigure = uifigure(Visible="off",Name="Export Preview", ...
                Resize="off",CloseRequestFcn=@(~,~) [], ...
                InnerPosition=[100 100 capturedSize],Color=previewBackground);
            exportCleanup = onCleanup(@() delete(exportFigure));
            exportAxes = copyPlotAxes_(source,exportFigure);
            copyDefaults = snapshotPlotCopy_(exportAxes);
            if ~isempty(obj.Content_)
                copyDefaults.XAutoLim = obj.Content_.automaticAxesLimits("X");
                copyDefaults.YAutoLim = obj.Content_.automaticAxesLimits("Y");
                if numel(exportAxes.YAxis) == 2
                    copyDefaults.RightYAutoLim = obj.Content_.automaticAxesLimits("RightY");
                end
            end
            drawnow;

            options = matlabx.ui.axes.PlotAxesExportDialog.prompt(obj,@updatePreview,exportAxes);
            if isempty(options), return; end
            exportFigure.Visible = 'off';

            pattern = "*" + options.Extension;
            description = options.Format + " (" + pattern + ")";
            [file,path] = uiputfile( ...
                {char(pattern),char(description)}, ...
                'Export Plot',char("plot" + options.Extension));
            if isequal(file,0), return; end
            [~,~,extension] = fileparts(file);
            if isempty(extension)
                file = char(string(file) + options.Extension);
            elseif ~strcmpi(extension,options.Extension)
                [~,name] = fileparts(file);
                file = char(string(name) + options.Extension);
            end
            filename = string(fullfile(path,file));
            dimensions = applyPlotCopyOptions_(exportFigure,exportAxes,options,aspectRatio,copyDefaults);
            % A resized hidden figure can export using its old renderer bounds.
            % Start the export figure at the final dimensions.
            finalFigure = uifigure(Visible="off", ...
                InnerPosition=exportFigure.InnerPosition,Color=previewBackground);
            finalCleanup = onCleanup(@() delete(finalFigure));
            finalAxes = copyPlotAxes_(exportAxes,finalFigure);
            applyPlotCopyView_(finalAxes,options.AxesView,copyDefaults);
            drawnow;
            drawnow;
            % Explicit dimensions preserve the requested page bounds in vector files.
            writePlotExport_(finalAxes,filename,options,dimensions,'on');

            function updatePreview(previewOptions,visible)
                if ~isempty(previewOptions)
                    applyPlotCopyOptions_(exportFigure,exportAxes,previewOptions,aspectRatio,copyDefaults);
                    exportFigure.Color = previewBackground;
                    if isnumeric(previewOptions.BackgroundColor)
                        exportFigure.Color = previewOptions.BackgroundColor;
                    end
                end
                if visible && strcmp(exportFigure.Visible,'off')
                    movegui(exportFigure,"west");
                end
                exportFigure.Visible = matlab.lang.OnOffSwitchState(visible);
            end
        end

        function copyPlot(obj,opts)
        %COPYPLOT Copy the assembled plot to the system clipboard.
            arguments
                obj (1,1) matlabx.ui.axes.PlotAxes
                opts.ContentType (1,1) string {mustBeMember(opts.ContentType, ...
                    ["auto","vector","image"])} = "vector"
                opts.BackgroundColor = obj.BackgroundColor
            end
            copygraphics(obj.MainAxes,ContentType=opts.ContentType, ...
                BackgroundColor=opts.BackgroundColor);
        end

        function mount(obj,content)
        %MOUNT Transfer one renderer into this host and render its stored state.

            validateattributes(content,{'matlabx.ui.axes.PlotContent'},{'scalar'});

            if ~isempty(obj.Content_) && obj.Content_ == content
                content.refresh();
                obj.applyAxesView();
                return;
            end

            if isgraphics(obj.AxesPropertiesDialog), close(obj.AxesPropertiesDialog); end
            obj.clear();

            % Remove axes presentation left by the previous renderer. Graphics
            % primitives are preserved because their renderer may be mounted
            % in this or another host again later.
            obj.resetAxes();

            % A renderer has one host. Release the previous host before moving
            % primitives; neither ComponentContainer changes layout parents.
            if ~isempty(content.Host) && isvalid(content.Host)
                content.Host.clear(content);
            end

            obj.Content_ = content;

            try
                content.attach(obj);
                obj.applyAxesView();
                % Content-specific commands share the host menu but remain
                % scoped to the mounted content's lifecycle.
                content.contributeContextMenu(obj.ContextMenuManager);
            catch ME
                % A failed refresh must not leave a half-mounted host/content pair.
                obj.ContextMenuManager.removeOwner(content);
                obj.clear(content);
                rethrow(ME);
            end
            notify(obj,'ContentChanged');
        end

        function clear(obj,content)
        %CLEAR Detach mounted content, optionally only when it matches CONTENT.

            if isempty(obj.Content_)
                return;
            end

            if nargin > 1 && obj.Content_ ~= content
                return;
            end

            if isgraphics(obj.AxesPropertiesDialog), close(obj.AxesPropertiesDialog); end
            mounted = obj.Content_;
            obj.Content_ = matlabx.ui.axes.PlotContent.empty(0,1);
            % Remove callbacks which retain the content before detaching it.
            obj.ContextMenuManager.removeOwner(mounted);
            mounted.detach(obj);
            obj.resetAxes();
            obj.applyRulerStyle();
            notify(obj,'ContentChanged');
        end

        function routeEvent(obj,kind,event)
        %ROUTEEVENT Route tools first, then unconsumed events to content.
            kind = string(kind);
            if kind == "KeyPress"
                obj.HotkeyRegistry.dispatch(event);
                if event.StopPropagation, return; end
            end

            passive = obj.ToolManager.getPriorityPassiveInterceptors(kind);
            for i = 1:numel(passive)
                passive{i}.("onPassive" + kind)(event);
                if event.StopPropagation, return; end
            end

            tool = obj.ToolManager.getPriorityInterceptor(kind);
            if ~isempty(tool)
                tool.("on" + kind)(event);
                if event.StopPropagation, return; end
            end

            if ~isempty(obj.Content_) && isvalid(obj.Content_)
                obj.Content_.handleEvent(string(kind),event);
            end
        end

        function tf = matches(obj,event)
        %MATCHES Return whether a routed event belongs to the stable UIAxes.
            tf = false;
            target = event.Target;
            if isempty(target)
                return;
            end

            % Data-tip interaction can make hittest return internal opaque
            % graphics objects. They support neither isvalid nor every normal
            % handle operation, so keep the entire ancestry query guarded.
            try
                if isequal(target,obj.MainAxes)
                    tf = true;
                    return;
                end
                axes = ancestor(target,'matlab.ui.control.UIAxes');
                tf = ~isempty(axes) && isequal(axes,obj.MainAxes);
            catch
            end
        end

        function onDown(obj,event)
        %ONDOWN Route a pointer-down event and open an unclaimed host menu.
            obj.routeEvent("Down",event);
            if ~event.StopPropagation && event.MouseChord == "contextclick"
                obj.ContextMenuManager.openAt(event.CurrentPointFigure);
            end
        end

        function onMove(obj,event)
        %ONMOVE Forward a routed pointer-move event to mounted content.
            obj.routeEvent("Move",event);
        end

        function onUp(obj,event)
        %ONUP Forward a routed pointer-up event to mounted content.
            obj.routeEvent("Up",event);
        end

        function onScroll(obj,event)
        %ONSCROLL Forward a routed scroll event to mounted content.
            obj.routeEvent("Scroll",event);
        end

        function onKeyPress(obj,event)
        %ONKEYPRESS Forward a routed key-press event to mounted content.
            obj.routeEvent("KeyPress",event);
        end

        function onKeyRelease(obj,event)
        %ONKEYRELEASE Forward a routed key-release event to mounted content.
            obj.routeEvent("KeyRelease",event);
        end

        function onEnter(obj,event)
        %ONENTER Notify installed tools and mounted content.
            obj.ToolManager.notifyHostEnter(event);
            if ~isempty(obj.Content_) && isvalid(obj.Content_)
                obj.Content_.handleEvent("Enter",event);
            end
        end

        function onLeave(obj,event)
        %ONLEAVE Notify installed tools and mounted content.
            obj.ToolManager.notifyHostLeave(event);
            if ~isempty(obj.Content_) && isvalid(obj.Content_)
                obj.Content_.handleEvent("Leave",event);
            end
        end

        function resetAxes(obj)
        %RESETAXES Restore predictable presentation without deleting graphics.
        % Renderers own semantic axes presentation, including ticks, limits,
        % labels, scales, grids, and view. This neutral baseline prevents one
        % renderer's choices from leaking into the next renderer mounted here.

            axes = obj.MainAxes;

            if isempty(axes) || ~isvalid(axes) || axes.BeingDeleted == "on"
                return;
            end

            % Incoming renderers must start on a single ruler. At this point
            % outgoing content has detached its owned graphics.
            if numel(axes.YAxis) == 2 && isempty(obj.Content_)
                toolbar = axes.Toolbar;
                expanded = obj.ToolbarExpanded;
                cla(axes,'reset');
                if isempty(toolbar) || ~isvalid(toolbar) || ~isequal(axes.Toolbar,toolbar)
                    if ~isempty(axes.Toolbar), axes.Toolbar.Visible = 'off'; end
                    axes.Toolbar = axtoolbar(axes,{});
                    obj.ToolManager.rebuildToolbarButtons();
                end
                axes.Toolbar.Expanded = expanded;
                axes.Toolbar.Visible = obj.ToolbarVisible_;
                axes.ContextMenu = obj.ContextMenuManager.Menu;
                axes.Interactions = dataTipInteraction;
                axes.Tag = char(obj.Name);
            end

            % Remove annotations and axes-specific helpers created for the
            % outgoing presentation while retaining renderer-owned primitives.
            legend(axes,'off');
            colorbar(axes,'off');
            axes.Title.String = '';
            axes.Subtitle.String = '';
            axes.XLabel.String = '';
            for ruler = reshape(axes.YAxis,1,[]), ruler.Label.String = ''; end
            axes.ZLabel.String = '';

            % Restore automatic Cartesian dimensions and tick generation.
            axes.XScale = 'linear';
            axes.YScale = 'linear';
            axes.ZScale = 'linear';
            axes.XDir = 'normal';
            axes.YDir = 'normal';
            axes.ZDir = 'normal';
            axes.XLimMode = 'auto';
            set(axes.YAxis,'LimitsMode','auto');
            axes.ZLimMode = 'auto';
            axes.XTickMode = 'auto';
            set(axes.YAxis,'TickValuesMode','auto');
            axes.ZTickMode = 'auto';
            axes.XTickLabelMode = 'auto';
            set(axes.YAxis,'TickLabelsMode','auto');
            axes.ZTickLabelMode = 'auto';
            axes.XAxis.Visible = 'on';
            set(axes.YAxis,'Visible','on');
            axes.ZAxis.Visible = 'off';

            % Restore general layout properties that plot types commonly alter.
            axes.DataAspectRatioMode = 'auto';
            axes.PlotBoxAspectRatioMode = 'auto';
            axes.CLimMode = 'auto';
            axes.XGrid = obj.GridVisible_;
            axes.YGrid = obj.GridVisible_;
            axes.ZGrid = 'off';
            axes.XMinorGrid = 'off';
            axes.YMinorGrid = 'off';
            axes.ZMinorGrid = 'off';
            axes.XMinorTick = 'off';
            axes.YMinorTick = 'off';
            axes.ZMinorTick = 'off';
            axes.XAxisLocation = 'bottom';
            if numel(axes.YAxis) == 1, axes.YAxisLocation = 'left'; end
            axes.Box = obj.BoxVisible_;
            axes.TickDir = 'in';
            axes.TickLength = [0.01 0.025];
            axes.LineWidth = 0.5;
            axes.View = [0 90];
            axes.NextPlot = 'add';
            axes.ColorOrderIndex = 1;

            obj.applyHostAppearance(false);
        end

        function delete(obj)
        %DELETE Unregister event routing and detach content before teardown.

            for k = 1:numel(obj)

                if isgraphics(obj(k).AxesPropertiesDialog)
                    delete(obj(k).AxesPropertiesDialog);
                end
                obj(k).clearInitialToolbarFocusListener_();
                obj(k).teardownTools_();

                try
                    if ~isempty(obj(k).Hub) && isvalid(obj(k).Hub) && ...
                            ~isnan(obj(k).RouterId)
                        obj(k).Hub.unregister(obj(k).RouterId);
                    end
                catch
                end

                if ~isempty(obj(k).Content_)
                    obj(k).clear();
                end

            end
        end

    end

    methods (Static)

        function capabilities = cartesianAxesCapabilities()
        %CARTESIANAXESCAPABILITIES Shared controls for ordinary Cartesian plots.
            capabilities = ["Colors","Typography","Grid","Box","Rulers", ...
                "XLim","YLim","XTickInterval","YTickInterval"];
        end

        function names = getToolNames()
        %GETTOOLNAMES Return short names of built-in PlotAxes tools.
            namespace = matlab.metadata.Namespace.fromName( ...
                "matlabx.ui.axes.tools.plot");
            if isempty(namespace)
                names = {};
                return
            end
            classes = {namespace.ClassList.Name};
            names = cell(size(classes));
            for i = 1:numel(classes)
                parts = split(string(classes{i}),'.');
                names{i} = char(parts(end));
            end
        end

        function names = getDefaultTools()
        %GETDEFAULTTOOLS Return built-in tools installed on new PlotAxes hosts.
            names = {'Export','CopyGraphics'};
        end

        function [hosts,renderers,fig] = demo(opts)
        %DEMO Show transferable scatter and violin content in two stable hosts.
        %   hosts.Second.mount(renderers.Scatter) transfers the same renderer
        %   and primitive handles, leaving hosts.First empty. The displaced
        %   renderers.Violin remains available for mounting again.

            arguments
                opts.Visible (1,1) matlab.lang.OnOffSwitchState = "on"
            end

            fig = uifigure('Name','Transferable Plot Content','Visible','off');
            grid = uigridlayout(fig,[1 2]);
            hosts.First = matlabx.ui.axes.PlotAxes(grid);
            hosts.Second = matlabx.ui.axes.PlotAxes(grid);
            renderers.Scatter = matlabx.ui.axes.plot.ScatterRenderer();
            renderers.Violin = matlabx.ui.axes.plot.ViolinRenderer();
            x = linspace(0,2*pi,40);
            renderers.Scatter.update(matlabx.ui.axes.plot.ScatterData( ...
                XData={x},YData={sin(x)},SeriesNames="Sine",CData={[0.2 0.5 0.8]}), ...
                matlabx.ui.axes.plot.ScatterStyle(Title="Scatter",XLabel="x",YLabel="sin(x)"));
            renderers.Violin.update(matlabx.ui.axes.plot.ViolinData( ...
                Values={sin(x),cos(x)+1},SeriesNames=["A" "B"], ...
                CData={[0.2 0.5 0.8],[0.8 0.4 0.2]}), ...
                matlabx.ui.axes.plot.ViolinStyle(Title="Distributions",YLabel="Value"));
            hosts.First.mount(renderers.Scatter);
            hosts.Second.mount(renderers.Violin);
            movegui(fig,"center");
            fig.Visible = opts.Visible;
        end

    end

    methods (Access=protected)

        function setup(obj)
        %SETUP Create the stable layout and UIAxes owned by this host.

            obj.Grid = uigridlayout(obj,[1 1], ...
                'ColumnWidth',{'1x'},'RowHeight',{'1x'}, ...
                'Padding',0,'BackgroundColor',obj.BackgroundColor);

            obj.MainAxes = uiaxes(obj.Grid, ...
                'Box','off','NextPlot','add','TickDir','in', ...
                'Color',obj.Color);
            obj.MainAxes.Layout.Row = 1;
            obj.MainAxes.Layout.Column = 1;
            obj.MainAxes.Interactions = dataTipInteraction;
            obj.MainAxes.ToolbarLocation = 'inside';
            obj.MainAxes.Toolbar = axtoolbar(obj.MainAxes,{}, ...
                'Expanded',obj.ToolbarExpanded_);
            obj.MainAxes.Toolbar.Visible = 'off';
            obj.MainAxes.Tag = char(obj.Name);
            addlistener(obj.MainAxes,'XLim','PostSet',@(~,~) obj.applyTickInterval_("X"));
            addlistener(obj.MainAxes,'YLim','PostSet',@(~,~) obj.applyTickInterval_("Y"));
            % Apply point-based typography before the first deferred update.
            obj.applyHostAppearance();

            obj.ToolManager = matlabx.ui.axes.PlotAxesToolManager(obj);
            obj.HotkeyRegistry = matlabx.ui.axes.PlotAxesHotkeyRegistry();

            fig = ancestor(obj.Parent,'figure');
            obj.ContextMenuManager = ...
                matlabx.ui.axes.PlotAxesContextMenuManager(obj,fig);
            obj.ContextMenuManager.setBuiltinItems(obj.ContextMenuItems_);
            obj.MainAxes.ContextMenu = obj.ContextMenuManager.Menu;
            obj.ToolManager.setInstalledNames(obj.getDefaultTools());

            obj.Hub = matlabx.ui.interaction.FigureEventHub.ensure(fig);
            obj.RouterId = obj.Hub.register(obj,'Priority',10);

            % ComponentContainer can destroy children before the subclass delete
            % method runs. Detach at the axes destruction event while its owned
            % primitives can still be moved out of the graphics hierarchy.
            obj.AxesLifetimeListener = addlistener(obj.MainAxes, ...
                'ObjectBeingDestroyed', @(~,~) obj.teardownAxes_());
        end

        function update(obj)
        %UPDATE Apply host-owned presentation without touching renderer graphics.

            if isempty(obj.MainAxes) || ~isvalid(obj.MainAxes)
                return;
            end

            isFirstUpdate = obj.FirstUpdatePending_;
            obj.applyHostAppearance();
            obj.MainAxes.Tag = char(obj.Name);

            % Buttons created while a figure is hidden can retain the toolbar's
            % keyboard focus when the figure first appears. Keep the toolbar
            % hidden until that transition, reveal it, then focus the figure.
            if isFirstUpdate
                obj.FirstUpdatePending_ = false;
                if isempty(fieldnames(obj.ToolbarButtons))
                    obj.MainAxes.Toolbar.Visible = obj.ToolbarVisible_;
                else
                    obj.MainAxes.Toolbar.Visible = 'off';
                    obj.showInitialToolbar_();
                end
            end
        end

    end

    methods (Access=?matlabx.ui.axes.PlotAxesPropertiesDialog)
        function applyAxesSettings_(obj,settings)
        %APPLYAXESSETTINGS_ Validate and apply a full snapshot for either caller.
            % Require the complete shape so an incomplete restore cannot silently
            % retain settings from the previous plot.
            groups = axesSettingsGroups_();
            names = [groups.Colors,groups.Typography,groups.Grid,groups.Box,groups.Rulers];
            validateSettingsFields_(settings,[names,"AxesView"]);
            view = settings.AxesView;
            legacyViewNames = ["XLim","YLim","XTickInterval","YTickInterval","LegendVisible"];
            dualViewNames = ["RightYLim","LeftYColor","RightYColor"];
            if isstruct(view) && isscalar(view) ...
                    && isequal(sort(string(fieldnames(view))),sort(legacyViewNames(:)))
                % Older snapshots did not store the right range or ruler colors.
                for name = dualViewNames, view.(name) = []; end
            end
            viewNames = [legacyViewNames,dualViewNames];
            validateSettingsFields_(view,viewNames);

            % Drop unavailable settings before validation and restore host defaults
            % so a later chart cannot pick up an old override.
            capabilities = obj.getAxesCapabilities();
            for group = reshape(string(fieldnames(groups)),1,[])
                if any(capabilities == group), continue; end
                for name = groups.(group)
                    switch name
                        case {"TitleVisible","GridVisible","BoxVisible"}
                            settings.(name) = false;
                        otherwise
                            property = findprop(obj,name);
                            settings.(name) = property.DefaultValue;
                    end
                end
            end
            for name = [viewNames(1:4),dualViewNames]
                if ~any(capabilities == name), view.(name) = []; end
                value = view.(name);
                if isnumeric(value) && isvector(value), view.(name) = reshape(value,1,[]); end
            end
            if ~any(capabilities == "Legend"), view.LegendVisible = "default"; end

            % Validate all appearance values before setAxesView changes the chart.
            for name = [groups.Colors,"TickLength"]
                value = settings.(name);
                if isnumeric(value) && isvector(value), settings.(name) = reshape(value,1,[]); end
            end
            appearanceArgs = namedargs2cell(rmfield(settings,'AxesView'));
            appearance = validateAxesAppearance_(appearanceArgs{:});
            viewArgs = namedargs2cell(view);
            obj.setAxesView(viewArgs{:});
            for name = names
                obj.(name) = appearance.(name);
            end
            obj.applyHostAppearance();
        end

        function commitAxesProperties_(obj)
        %COMMITAXESPROPERTIES_ Notify listeners of an accepted native dialog.
            data = matlabx.ui.axes.events.AxesPropertiesCommittedEventData(obj.getAxesSettings());
            notify(obj,'AxesPropertiesCommitted',data);
        end
    end

    methods (Access=private)

        function showInitialToolbar_(obj)
        %SHOWINITIALTOOLBAR_ Reveal the constructed toolbar and release focus.
            fig = ancestor(obj.MainAxes,'figure');
            if isempty(fig) || ~isvalid(fig), return; end

            if strcmp(fig.Visible,'on')
                obj.clearInitialToolbarFocusListener_();
                obj.MainAxes.Toolbar.Visible = obj.ToolbarVisible_;
                if strcmp(obj.ToolbarVisible_,'on')
                    obj.releaseToolbarFocus_();
                end
            elseif isempty(obj.InitialToolbarFocusListener) || ...
                    ~isvalid(obj.InitialToolbarFocusListener)
                obj.InitialToolbarFocusListener = addlistener(fig, ...
                    'Visible','PostSet',@(~,~) obj.showInitialToolbar_());
            end
        end

        function releaseToolbarFocus_(obj)
        %RELEASETOOLBARFOCUS_ Return keyboard focus to the visible host figure.
            fig = ancestor(obj.MainAxes,'figure');
            if ~isempty(fig) && isvalid(fig) && strcmp(fig.Visible,'on')
                focus(fig);
            end
        end

        function clearInitialToolbarFocusListener_(obj)
        %CLEARINITIALTOOLBARFOCUSLISTENER_ Remove the pending visibility listener.
            if ~isempty(obj.InitialToolbarFocusListener)
                delete(obj.InitialToolbarFocusListener( ...
                    isvalid(obj.InitialToolbarFocusListener)));
            end
            obj.InitialToolbarFocusListener = event.listener.empty;
        end

        function applyHostAppearance(obj,applyRulers)
        %APPLYHOSTAPPEARANCE Restore colors and typography owned by PlotAxes.
            if nargin < 2, applyRulers = true; end
            if isempty(obj.MainAxes) || ~isvalid(obj.MainAxes) || ...
                    obj.MainAxes.BeingDeleted == "on"
                return;
            end

            capabilities = obj.getAxesCapabilities();
            if any(capabilities == "Colors")
                obj.Grid.BackgroundColor = colorOverride_(obj.BackgroundColor,obj.BackgroundColorOverride);
                obj.MainAxes.Color = colorOverride_(obj.Color,obj.AxesColorOverride);
                setAxesForeground_(obj.MainAxes,colorOverride_( ...
                    obj.ForegroundColor,obj.ForegroundColorOverride));
            else
                % The container follows the base color even for a renderer
                % that controls the native axes colors itself.
                obj.Grid.BackgroundColor = obj.BackgroundColor;
            end
            if any(capabilities == "Typography")
                obj.MainAxes.FontName = char(obj.FontName);
                obj.MainAxes.FontUnits = char(obj.FontUnits);
                textObjects = [obj.MainAxes.Title,obj.MainAxes.Subtitle, ...
                    obj.MainAxes.XLabel,plotYLabels_(obj.MainAxes),obj.MainAxes.ZLabel];
                set(textObjects,'FontUnits',char(obj.FontUnits));
                obj.MainAxes.FontSize = obj.FontSize;
                obj.MainAxes.LabelFontSizeMultiplier = obj.LabelFontSizeMultiplier;
                obj.MainAxes.TitleFontSizeMultiplier = obj.TitleFontSizeMultiplier;
                obj.MainAxes.Title.Visible = obj.TitleVisible_;
            end
            obj.MainAxes.ToolbarLocation = 'inside';
            if any(capabilities == "Grid")
                obj.MainAxes.XGrid = obj.GridVisible_;
                obj.MainAxes.YGrid = obj.GridVisible_;
            end
            if any(capabilities == "Box")
                obj.MainAxes.Box = obj.BoxVisible_;
            end
            if applyRulers, obj.applyRulerStyle(); end
            if ~isempty(obj.MainAxes.Toolbar) && isvalid(obj.MainAxes.Toolbar) && ...
                    ~obj.FirstUpdatePending_
                obj.MainAxes.Toolbar.Visible = obj.ToolbarVisible_;
            end
        end

        function applyRulerStyle(obj)
        %APPLYRULERSTYLE Apply host stroke and tick styling to supported axes.
            if any(obj.getAxesCapabilities() == "Rulers")
                obj.MainAxes.TickLength = obj.TickLength;
                obj.MainAxes.TickDir = obj.TickDirection;
                obj.MainAxes.LineWidth = obj.AxisLineWidth;
            end
        end

        function applyTickInterval_(obj,axisName)
        %APPLYTICKINTERVAL_ Refresh the configured tick interval after a limit change.
            intervalName = axisName + "TickInterval";
            interval = obj.AxesView.(intervalName);
            if isempty(interval) || ~any(obj.getAxesCapabilities() == intervalName)
                return;
            end
            ax = obj.MainAxes;
            if ax.BeingDeleted == "on", return; end
            setPlotTickInterval_(ax,axisName,interval);
        end

        function refreshContextMenu(obj)
        %REFRESHCONTEXTMENU Refresh dynamic menu state when available.
            if ~isempty(obj.ContextMenuManager) && isvalid(obj.ContextMenuManager)
                obj.ContextMenuManager.refresh();
            end
        end

        function onStatusWindowClosed_(obj)
        %ONSTATUSWINDOWCLOSED_ Clear status-window ownership state.
            obj.StatusWindowOpen_ = false;
        end

        function teardownAxes_(obj)
        %TEARDOWNAXES_ Detach content and tools before axes graphics disappear.
            if ~isempty(obj.Content_)
                obj.clear();
            end
            obj.teardownTools_();
        end

        function teardownTools_(obj)
        %TEARDOWNTOOLS_ Uninstall borrowed tools and delete manager-owned tools.
            if obj.ToolsTornDown_, return; end
            obj.ToolsTornDown_ = true;
            if isempty(obj.ToolManager) || ~isvalid(obj.ToolManager), return; end
            obj.ToolManager.uninstallAll();
            obj.ToolManager.unloadAll();
        end

    end

end

function restoreFigureWindowStyle_(fig,windowStyle)
%RESTOREFIGUREWINDOWSTYLE_ Restore a valid host figure after modal dialogs.
    if ~isempty(fig) && isvalid(fig)
        fig.WindowStyle = windowStyle;
    end
end

function restoreToolbar_(toolbar,visible)
%RESTORETOOLBAR_ Restore toolbar visibility after scoped plot export.
    if ~isempty(toolbar) && isvalid(toolbar)
        toolbar.Visible = visible;
    end
end

function restorePlotAppearance_(host,appearance)
%RESTOREPLOTAPPEARANCE_ Restore host styling after scoped plot export.
    if isempty(host) || ~isvalid(host), return; end
    host.Color = appearance.Color;
    host.AxesColorOverride = appearance.AxesColorOverride;
    host.ForegroundColorOverride = appearance.ForegroundColorOverride;
    host.ForegroundColor = appearance.ForegroundColor;
    host.FontName = appearance.FontName;
    host.FontUnits = appearance.FontUnits;
    host.FontSize = appearance.FontSize;
    host.LabelFontSizeMultiplier = appearance.LabelFontSizeMultiplier;
    host.TitleFontSizeMultiplier = appearance.TitleFontSizeMultiplier;
    host.GridVisible = appearance.GridVisible;
    host.BoxVisible = appearance.BoxVisible;
    host.TitleVisible = appearance.TitleVisible;
    drawnow;
end

function mustBeAxesColor_(value)
%MUSTBEAXESCOLOR_ Require an RGB triplet or the string "none".
    normalizeAxesColor_(value,'color');
end

function value = normalizeAxesColor_(value,name)
%NORMALIZEAXESCOLOR_ Normalize an RGB triplet or transparent color token.
    if (ischar(value) || (isstring(value) && isscalar(value))) && ...
            strcmpi(string(value),"none")
        value = "none";
        return;
    end
    validateattributes(value,{'numeric'}, ...
        {'real','finite','size',[1 3],'>=',0,'<=',1},mfilename,name);
    value = double(value);
end

function mustBeExportDimension_(value)
%MUSTBEEXPORTDIMENSION_ Allow [] to derive this dimension at export time.
    if ~isempty(value)
        validateattributes(value,{'double'},{'real','scalar','positive','finite'});
    end
end

function ax = copyPlotAxes_(source,fig)
%COPYPLOTAXES_ Copy the axes and its linked legend and colorbar together.
    if numel(source.YAxis) == 2
        ax = copyDualPlotAxes_(source,fig);
    else
        objects = copyobj([source,source.Legend,source.Colorbar],fig);
        ax = objects(1);
        set(ax,XLim=source.XLim,YLim=source.YLim,ZLim=source.ZLim);
    end
    if ~isempty(ax.Toolbar)
        ax.Toolbar.Visible = 'off';
    end
    ax.Units = 'normalized';
    ax.OuterPosition = [0 0 1 1];
end

function ax = copyDualPlotAxes_(source,fig)
%COPYDUALPLOTAXES_ Recreate a dual-Y chart by copying each side's primitives.
    % MATLAB cannot copy a yyaxis axes object as a whole.
    side = source.YAxisLocation;
    restoreSide = onCleanup(@() yyaxis(source,side));
    ax = uiaxes(fig,NextPlot="add");
    properties = {'Color','ColorOrder','FontName','FontUnits','FontSize', ...
        'LabelFontSizeMultiplier','TitleFontSizeMultiplier','LineWidth','TickLength', ...
        'TickDir','Box','XColor','XGrid','YGrid','XMinorGrid','YMinorGrid', ...
        'GridColor','GridAlpha','GridLineStyle','XScale','XDir','XLim', ...
        'XTick','XTickMode','XTickLabel','XTickLabelMode','XAxisLocation','CLim'};
    set(ax,properties,get(source,properties));
    colormap(ax,colormap(source));
    copyPlotLabel_(source.Title,ax.Title);
    copyPlotLabel_(source.Subtitle,ax.Subtitle);
    copyPlotLabel_(source.XLabel,ax.XLabel);
    for name = ["left","right"]
        yyaxis(source,char(name));
        yyaxis(ax,char(name));
        % Only the active side's children appear in this property.
        children = source.Children;
        if ~isempty(children)
            copies = copyobj(children,ax);
            % The new axes' color and line style cycles can restyle auto lines.
            % Keep the source appearance on the export copy.
            for k = reshape(find(isgraphics(children,'line')),1,[])
                copies(k).Color = children(k).Color;
                copies(k).LineStyle = children(k).LineStyle;
            end
        end
        properties = {'YScale','YDir','YLim','YColor','YTick','YTickMode', ...
            'YTickLabel','YTickLabelMode','YMinorTick'};
        set(ax,properties,get(source,properties));
        copyPlotLabel_(source.YLabel,ax.YLabel);
    end
    yyaxis(ax,side);
end

function copyPlotLabel_(source,target)
%COPYPLOTLABEL_ Copy text styling while retaining the target ruler association.
    properties = {'String','Interpreter','FontName','FontUnits','FontSize', ...
        'FontSizeMode','FontWeight','FontAngle','Color','Visible'};
    set(target,properties,get(source,properties));
end

function dimensions = applyPlotCopyOptions_(fig,ax,opts,aspectRatio,defaults)
%APPLYPLOTCOPYOPTIONS_ Lay out the temporary copy for preview or export.
    width = opts.Width;
    height = opts.Height;
    if isempty(width), width = height * aspectRatio; end
    if isempty(height), height = width / aspectRatio; end

    pixelsPerInch = get(groot,'ScreenPixelsPerInch');
    scale = pixelsPerInch / matlabx.ui.axes.internal.exportUnitsPerInch(opts.Units,opts.Resolution);
    fig.InnerPosition(3:4) = max(1,round([width height] * scale));

    style = opts.AxesAppearance;
    if isfield(style,"AxesColorOverride")
        ax.Color = colorOverride_(defaults.Color,style.AxesColorOverride);
        setAxesForeground_(ax,colorOverride_(defaults.ForegroundColor,style.ForegroundColorOverride));
    end
    if isfield(style,"FontName")
        ax.FontUnits = style.FontUnits;
        labels = [ax.Title,ax.Subtitle,ax.XLabel,plotYLabels_(ax),ax.ZLabel];
        set(labels,FontUnits=style.FontUnits);
        set(ax,FontName=style.FontName,FontSize=style.FontSize, ...
            LabelFontSizeMultiplier=style.LabelFontSizeMultiplier, ...
            TitleFontSizeMultiplier=style.TitleFontSizeMultiplier);
        ax.Title.Visible = style.TitleVisible;
    end
    if isfield(style,"GridVisible")
        set(ax,XGrid=style.GridVisible,YGrid=style.GridVisible);
    end
    if isfield(style,"BoxVisible"), ax.Box = style.BoxVisible; end
    if isfield(style,"AxisLineWidth")
        set(ax,LineWidth=style.AxisLineWidth,TickLength=style.TickLength,TickDir=style.TickDirection);
    end
    applyPlotCopyView_(ax,opts.AxesView,defaults);
    dimensions = {'Width',width,'Height',height};
end

function writePlotExport_(ax,filename,opts,dimensions,preserveAspect)
%WRITEPLOTEXPORT_ Write a native axes with the requested canvas options.
    exportgraphics(ax,filename,dimensions{:}, ...
        ContentType=opts.ContentType,Units=opts.Units, ...
        Colorspace="rgb",Padding=0,PreserveAspectRatio=preserveAspect, ...
        BackgroundColor=opts.BackgroundColor,Resolution=opts.Resolution);
end

function mustBeViewLimits_(value)
%MUSTBEVIEWLIMITS_ Accept inherited, automatic, or finite increasing view limits.
    if isempty(value) || isequal(value,"auto") || isequal(value,'auto'), return; end
    validateattributes(value,{'numeric'},{'real','finite','size',[1 2],'increasing'});
end

function mustBeTickInterval_(value)
%MUSTBETICKINTERVAL_ Accept an inherited, automatic, or positive manual interval.
    if isequal(value,"auto") || isequal(value,'auto'), return; end
    if ~isempty(value)
        validateattributes(value,{'double'},{'real','finite','scalar','positive'});
    end
end

function defaults = snapshotPlotCopy_(ax)
%SNAPSHOTPLOTCOPY_ Retain the source view for reversible preview edits.
    defaults = struct("XLim",ax.XLim,"YLim",ax.YAxis(1).Limits, ...
        "XTick",ax.XTick,"YTick",ax.YAxis(1).TickValues, ...
        "XTickMode",ax.XTickMode,"YTickMode",ax.YAxis(1).TickValuesMode, ...
        "Color",stringOrRGB_(ax.Color),"ForegroundColor",ax.XColor, ...
        "XAutoLim",[],"YAutoLim",[],"LegendVisible","off");
    if numel(ax.YAxis) == 2
        defaults.RightYLim = ax.YAxis(2).Limits;
        defaults.LeftYColor = ax.YAxis(1).Color;
        defaults.RightYColor = ax.YAxis(2).Color;
        defaults.RightYAutoLim = [];
    end
    if ~isempty(ax.Legend), defaults.LegendVisible = string(ax.Legend.Visible); end
end

function value = stringOrRGB_(value)
%STRINGORRGB_ Normalize a text color token while preserving numeric RGB.
    if ischar(value), value = string(value); end
end

function applyPlotCopyView_(ax,view,defaults)
%APPLYPLOTCOPYVIEW_ Apply export-only view overrides against the source snapshot.
    for axisName = ["X","Y","RightY"]
        property = axisName + "Lim";
        if ~isfield(view,property) || ~isfield(defaults,property), continue; end
        limits = view.(property);
        if isempty(limits)
            limits = defaults.(property);
        elseif isstring(limits)
            limits = defaults.(axisName + "AutoLim");
        end
        setPlotLimit_(ax,property,limits);
    end
    for axisName = ["X","Y"]
        intervalName = axisName + "TickInterval";
        if ~isfield(view,intervalName), continue; end
        interval = view.(intervalName);
        tick = axisName + "Tick";
        if isempty(interval)
            if axisName == "Y"
                ruler = ax.YAxis(1);
                if strcmp(defaults.YTickMode,'manual'), ruler.TickValues = defaults.YTick; end
                ruler.TickValuesMode = defaults.YTickMode;
            else
                if strcmp(defaults.XTickMode,'manual'), ax.XTick = defaults.XTick; end
                ax.XTickMode = defaults.XTickMode;
            end
        else
            setPlotTickInterval_(ax,axisName,interval);
        end
    end
    if numel(ax.YAxis) == 2
        for name = ["LeftYColor","RightYColor"]
            if ~isfield(view,name), continue; end
            color = view.(name);
            ax.YAxis(1 + (name == "RightYColor")).Color = colorOverride_(defaults.(name),color);
        end
    end
    if isfield(view,"LegendVisible")
        visibility = view.LegendVisible;
        if visibility == "default", visibility = defaults.LegendVisible; end
        if isempty(ax.Legend)
            if visibility == "on"
                points = flipud(findobj(ax,'Type','scatter'));
                if isempty(points), legend(ax,'show'); else, legend(ax,points); end
            end
        else
            ax.Legend.Visible = visibility;
        end
    end
end

function setPlotTickInterval_(ax,axisName,interval)
%SETPLOTTICKINTERVAL_ Place ticks at fixed intervals on linear axes.
    if axisName == "Y"
        ruler = ax.YAxis(1);
    else
        ruler = ax.XAxis;
    end
    if ischar(interval) || isstring(interval) || strcmp(ruler.Scale,'log')
        ruler.TickValuesMode = 'auto';
        return;
    end
    bounds = ruler.Limits ./ interval;
    tolerance = min(1e-8,4*eps(max(abs(bounds))));
    endpoints = [ceil(bounds(1)-tolerance),floor(bounds(2)+tolerance)];
    % Retain readable ticks when a zoom-out would create a huge list.
    if any(~isfinite(endpoints)) || diff(endpoints) >= 1000
        ruler.TickValuesMode = 'auto';
    else
        ruler.TickValues = (endpoints(1):endpoints(2)) .* interval;
    end
end

function setAxesForeground_(ax,color)
%SETAXESFOREGROUND_ Apply a foreground color to the rulers and axes labels.
    set(ax,XColor=color,ZColor=color);
    set([ax.Title,ax.Subtitle,ax.XLabel,ax.ZLabel],Color=color);
    if numel(ax.YAxis) == 1
        ax.YColor = color;
        ax.YLabel.Color = color;
    end
end

function color = colorOverride_(default,override)
%COLOROVERRIDE_ Resolve a base color and optional explicit override.
    color = default;
    if ~isempty(override), color = override; end
end

function mustBeOptionalRGB_(value)
%MUSTBEOPTIONALRGB_ Validate an RGB override when supplied.
    if ~isempty(value)
        validateattributes(value,{'double'},{'real','finite','size',[1 3],'>=',0,'<=',1});
    end
end

function mustBeOptionalAxesColor_(value)
%MUSTBEOPTIONALAXESCOLOR_ Validate an optional fill override or transparency token.
    if ~isempty(value), mustBeAxesColor_(value); end
end

function groups = axesSettingsGroups_()
%AXESSETTINGSGROUPS Map snapshot appearance fields to chart capabilities.
    groups = struct( ...
        "Colors",["BackgroundColorOverride","AxesColorOverride","ForegroundColorOverride"], ...
        "Typography",["FontName","FontUnits","FontSize","LabelFontSizeMultiplier", ...
            "TitleFontSizeMultiplier","TitleVisible"], ...
        "Grid","GridVisible","Box","BoxVisible", ...
        "Rulers",["AxisLineWidth","TickLength","TickDirection"]);
end

function validateSettingsFields_(settings,expected)
%VALIDATESETTINGSFIELDS_ Require the fields in a complete settings snapshot.
    if ~isstruct(settings) || ~isscalar(settings) ...
            || ~isequal(sort(string(fieldnames(settings))),sort(expected(:)))
        error('matlabx:ui:axes:InvalidAxesSettings', ...
            'Supply a complete snapshot from PlotAxes.getAxesSettings.');
    end
end

function opts = validateAxesAppearance_(opts)
%VALIDATEAXESAPPEARANCE_ Validate and normalize snapshot appearance values.
    arguments
        opts.BackgroundColorOverride double {mustBeOptionalRGB_}
        opts.AxesColorOverride {mustBeOptionalAxesColor_}
        opts.ForegroundColorOverride double {mustBeOptionalRGB_}
        opts.FontName (1,1) string
        opts.FontUnits (1,1) string {mustBeMember(opts.FontUnits,["points","pixels"])}
        opts.FontSize (1,1) double {mustBePositive,mustBeFinite}
        opts.LabelFontSizeMultiplier (1,1) double {mustBePositive,mustBeFinite}
        opts.TitleFontSizeMultiplier (1,1) double {mustBePositive,mustBeFinite}
        opts.TitleVisible (1,1) matlab.lang.OnOffSwitchState
        opts.GridVisible (1,1) matlab.lang.OnOffSwitchState
        opts.BoxVisible (1,1) matlab.lang.OnOffSwitchState
        opts.AxisLineWidth (1,1) double {mustBePositive,mustBeFinite}
        opts.TickLength (1,2) double {mustBeNonnegative,mustBeFinite}
        opts.TickDirection (1,1) string {mustBeMember(opts.TickDirection,["in","out","both","none"])}
    end
end

function labels = plotYLabels_(ax)
%PLOTYLABELS_ Return both native label handles on a dual-Y chart.
    labels = [ax.YAxis.Label];
end

function restorePlotYSide_(ax,side)
%RESTOREPLOTYSIDE_ Restore the previous side if both rulers still exist.
    if isgraphics(ax) && numel(ax.YAxis) == 2 && ~strcmp(ax.YAxisLocation,side)
        yyaxis(ax,side);
    end
end

function setPlotLimit_(ax,property,limits)
%SETPLOTLIMIT_ Apply a range without switching the active Y side.
    if property == "XLim"
        if isempty(limits), ax.XLimMode = 'auto'; else, ax.XLim = limits; end
    else
        ruler = ax.YAxis(1 + (property == "RightYLim"));
        if isempty(limits), ruler.LimitsMode = 'auto'; else, ruler.Limits = limits; end
    end
end

function setPlotTickMode_(ax,axisName)
%SETPLOTTICKMODE_ Restore native automatic ticks for the requested ruler.
    if axisName == "Y", ax.YAxis(1).TickValuesMode = 'auto'; else, ax.XTickMode = 'auto'; end
end
