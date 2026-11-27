function [read,refreshLimits,restoreDefaults,revert] = plotAxesControlTabs(tabs,host,onChanged,forExport,exportPane)
%PLOTAXESCONTROLTABS Build the shared axes settings tabs.
%   READ validates and returns appearance and view settings. REFRESHLIMITS
%   displays effective bounds from the supplied axes. RESTOREDEFAULTS and
%   REVERT update the controls. The caller applies the settings to live
%   axes or to an export copy.

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

    capabilities = host.getAxesCapabilities();
    % Native axes that provide the effective opening values.
    ax = host.Axes;
    % Host overrides before any controls have been edited.
    initialView = host.AxesView;
    % Resolved defaults include host fallbacks for undeclared renderer settings.
    [viewDefaults,declaredDefaults] = host.getAxesViewDefaults();
    % Opening override for the plot container or export canvas.
    backgroundOverride = host.BackgroundColorOverride;
    % Opening override for the plotting area.
    axesColorOverride = host.AxesColorOverride;
    % Effective plot container color used to initialize the picker.
    currentBackground = effectiveColor(host.BackgroundColor,backgroundOverride);
    if forExport
        if isempty(backgroundOverride), backgroundOverride = "none"; end
        if isempty(axesColorOverride), axesColorOverride = "none"; end
    end
    % Tab panel background from the export dialog palette.
    paneColor = [.18 .18 .18];
    % Editable control background from the shared palette.
    controlColor = [.3 .3 .3];
    % Caption color for text on the tab panel.
    fontColor = [.85 .85 .85];
    % Text color for values and selections in editable controls.
    controlFontColor = [.9 .9 .9];

    % Appearance controls keyed by their PlotAxes property names.
    appearance = struct();
    % View settings explicitly changed since opening or restoring defaults.
    edited = struct();
    % Values to use for untouched controls, including inherited settings.
    viewState = initialView;
    % Controls whose values and auxiliary state must be reverted together.
    settingsControls = {};
    if any(ismember(["Colors","Typography","Grid","Box","Legend"],capabilities))
        pane = addTab("Appearance");
        if supports("Colors")
            if forExport
                backgroundControl = addColor(exportPane,"Canvas background", ...
                    backgroundOverride,host.BackgroundColor,currentBackground,true);
            else
                backgroundControl = addColor(pane,"Background color", ...
                    backgroundOverride,host.BackgroundColor,currentBackground,false);
                backgroundControl.Mode.Tooltip = ...
                    "Use Axes color for a transparent plotting area.";
            end
            axesColorControl = addColor(pane,"Axes color", ...
                axesColorOverride,host.Color,ax.Color,true);
            foregroundOverride = host.ForegroundColorOverride;
            if forExport && isnumeric(ax.XColor) && ~isequal(ax.XColor,host.ForegroundColor)
                foregroundOverride = ax.XColor;
            end
            foregroundControl = addColor(pane,"Foreground", ...
                foregroundOverride,host.ForegroundColor,ax.XColor,false);
        end
        if supports("Typography")
            % Include the host font choices even when they are unavailable locally.
            fonts = string(listfonts());
            % Metadata for the host's default font.
            fontProperty = findprop(host,"FontName");
            fonts = unique([host.FontName;string(fontProperty.DefaultValue);fonts(:)]);
            appearance.FontName = addDropDown(pane,"Font",cellstr(fonts),host.FontName);
            appearance.FontSize = addNumber(pane,"Tick-label size (pt)",points(host.FontSize),[eps Inf]);
            appearance.LabelFontSizeMultiplier = addNumber(pane,"Axis-label size multiplier", ...
                host.LabelFontSizeMultiplier,[eps Inf]);
            appearance.TitleFontSizeMultiplier = addNumber(pane,"Title size multiplier", ...
                host.TitleFontSizeMultiplier,[eps Inf]);
            appearance.TitleVisible = addCheck(pane,"Show title",host.TitleVisible);
        end
        if supports("Grid")
            appearance.GridVisible = addCheck(pane,"Show grid",host.GridVisible);
        end
        if supports("Box")
            appearance.BoxVisible = addCheck(pane,"Show box",host.BoxVisible);
        end
        if supports("Legend")
            legendMode = addLegend(pane);
        end
    end

    % Tick spacing mode and value controls keyed by view property.
    intervalControls = struct();
    if any(ismember(["Rulers","XTickInterval","YTickInterval"],capabilities))
        pane = addTab("Ticks and Lines");
        if supports("Rulers")
            appearance.AxisLineWidth = addNumber(pane,"Axes line width (pt)",host.AxisLineWidth,[eps Inf]);
            % The UI edits the 2-D tick length and carries the 3-D value with it.
            tickLength = addNumber(pane,"Tick length (fraction of axes size)",host.TickLength(1),[0 Inf]);
            tickLength.UserData = host.TickLength(2);
            appearance.TickDirection = addDropDown(pane,"Tick direction", ...
                {'In','Out','Both','None'},host.TickDirection,{'in','out','both','none'});
        end
        for axisName = ["X","Y"]
            property = axisName + "TickInterval";
            if supports(property)
                intervalControls.(property) = addInterval(pane,axisName);
            end
        end
    end

    % Limit mode and bound controls keyed by axis limit property.
    limitControls = struct();
    rulerColors = struct();
    if any(ismember(["XLim","YLim","RightYLim","LeftYColor","RightYColor"],capabilities))
        pane = addTab("Limits");
        if supports("XLim"), limitControls.XLim = addLimits(pane,"XLim","X"); end
        if numel(ax.YAxis) == 1
            if supports("YLim"), limitControls.YLim = addLimits(pane,"YLim","Y"); end
        else
            colors = host.getYAxisDefaultColors();
            for side = 1:2
                labels = ["Left Y axis","Right Y axis"];
                names = ["YLim","RightYLim"];
                colorNames = ["LeftYColor","RightYColor"];
                name = names(side);
                colorName = colorNames(side);
                if supports(name)
                    limitControls.(name) = addLimits(pane,name,labels(side));
                end
                if supports(colorName)
                    override = initialView.(colorName);
                    if forExport && ~isequal(ax.YAxis(side).Color,colors(side,:))
                        override = ax.YAxis(side).Color;
                    end
                    rulerColors.(colorName) = addColor(pane,labels(side)+" color", ...
                        override,colors(side,:),ax.YAxis(side).Color,false);
                    rulerColors.(colorName).Mode.Items = {'Auto','Custom'};
                end
            end
        end
    end

    read = @readSettings;
    refreshLimits = @showEffectiveLimits;
    restoreDefaults = @restoreViewDefaults;
    revert = @revertControls;
    % Opening view settings, including their inheritance state.
    openingView = viewState;
    % Opening values for all controls shared by the two dialogs.
    openingValues = cellfun(@(h) h.Value,settingsControls,UniformOutput=false);
    % Opening custom colors and interval values stored on the controls.
    openingData = cellfun(@(h) h.UserData,settingsControls,UniformOutput=false);

    function tf = supports(property)
    %SUPPORTS Return whether the mounted plot exposes a shared setting.
        tf = any(capabilities == property);
    end

    function value = points(value)
    %POINTS Convert a host font size to the units displayed in the dialog.
        if host.FontUnits == "pixels"
            value = value * 72 / get(groot,'ScreenPixelsPerInch');
        end
    end

    function pane = addTab(name)
    %ADDTAB Create a scrollable settings grid on a themed tab.
        tab = uitab(tabs,Title=name,BackgroundColor=paneColor,ForegroundColor=fontColor);
        pane = uigridlayout(tab,[1 2],ColumnWidth={'fit','1x'}, ...
            Padding=[5 5 5 5],ColumnSpacing=5,RowSpacing=5, ...
            BackgroundColor=paneColor,RowHeight={'1x'},Scrollable="on");
    end

    function row = addRow(pane,label)
    %ADDROW Insert a labeled settings row before the flexible spacer.
        rows = pane.RowHeight;
        % Settings row inserted immediately before the flexible spacer.
        row = numel(rows);
        pane.RowHeight = [rows(1:end-1),{'fit','1x'}];
        % Label belonging to the new settings row.
        caption = uilabel(pane,Text=label,FontColor=fontColor);
        caption.Layout.Row = row;
        caption.Layout.Column = 1;
    end

    function control = addDropDown(pane,label,items,value,itemsData)
    %ADDDROPDOWN Create a styled dropdown and bind its change callback.
        row = addRow(pane,label);
        control = uidropdown(pane,Items=items,BackgroundColor=controlColor,FontColor=controlFontColor);
        if nargin == 5, control.ItemsData = itemsData; end
        control.Value = char(value);
        control.Layout.Row = row;
        control.Layout.Column = 2;
        control.ValueChangedFcn = @(~,~) onChanged();
        settingsControls{end+1} = control;
    end

    function control = addNumber(pane,label,value,bounds)
    %ADDNUMBER Create a numeric field with the supplied limits.
        row = addRow(pane,label);
        control = uieditfield(pane,"numeric",Limits=bounds,Value=value, ...
            BackgroundColor=controlColor,FontColor=controlFontColor);
        control.Layout.Row = row;
        control.Layout.Column = 2;
        control.ValueChangedFcn = @(~,~) onChanged();
        settingsControls{end+1} = control;
    end

    function control = addText(pane,label,value,placeholder)
    %ADDTEXT Create a text field with an optional placeholder.
        row = addRow(pane,label);
        text = "";
        if ~isempty(value), text = string(value); end
        control = uieditfield(pane,"text",Value=text,Placeholder=placeholder, ...
            BackgroundColor=controlColor,FontColor=controlFontColor);
        control.Layout.Row = row;
        control.Layout.Column = 2;
        control.ValueChangedFcn = @(~,~) onChanged();
        settingsControls{end+1} = control;
    end

    function control = addCheck(pane,label,value)
    %ADDCHECK Create a styled checkbox for a boolean setting.
        row = addRow(pane,label);
        control = uicheckbox(pane,Text="",Value=logical(value),FontColor=controlFontColor);
        control.Layout.Row = row;
        control.Layout.Column = 2;
        control.ValueChangedFcn = @(~,~) onChanged();
        settingsControls{end+1} = control;
    end

    function controls = addLimits(pane,property,label)
    %ADDLIMITS Create the mode and bounds controls for an axis.
        % Bounds and mode come from the explicit ruler, independently of yyaxis.
        [shown,mode] = readLimits(ax,property);
        controls.Mode = addMode(pane,label+" limits",mode);
        controls.Minimum = addNumber(pane,label+" minimum",shown(1),[-Inf Inf]);
        controls.Maximum = addNumber(pane,label+" maximum",shown(2),[-Inf Inf]);
        controls.Mode.ValueChangedFcn = @(~,~) limitsModeChanged(controls,property);
        controls.Minimum.ValueChangedFcn = @(~,~) viewEdited(property);
        controls.Maximum.ValueChangedFcn = @(~,~) viewEdited(property);
        updateLimitFields(controls);
        if forExport, viewState.(property) = []; end
    end

    function control = addMode(pane,label,mode)
    %ADDMODE Create the shared Auto and Manual selector.
        control = addDropDown(pane,label,{'Auto','Manual'},mode,{'auto','manual'});
    end

    function control = addLegend(pane)
    %ADDLEGEND Create a checkbox reflecting the displayed legend.
        visible = ~isempty(ax.Legend) && strcmp(ax.Legend.Visible,'on');
        control = addCheck(pane,"Show legend",visible);
        control.ValueChangedFcn = @(~,~) viewEdited("LegendVisible");
        if forExport, viewState.LegendVisible = "default"; end
    end

    function controls = addInterval(pane,axisName)
    %ADDINTERVAL Create the mode and interval controls for linear ticks.
        property = axisName + "TickInterval";
        % Stored tick interval, when the host has an explicit override.
        configured = initialView.(property);
        controls.Mode = addMode(pane,axisName+" tick spacing",ax.(axisName+"TickMode"));
        controls.Interval = addText(pane,axisName+" tick interval",[],"");
        controls.Interval.UserData = "";
        if isnumeric(configured) && ~isempty(configured)
            controls.Interval.UserData = string(configured);
        end
        controls.Interval.ValueChangedFcn = @(~,~) intervalEdited(controls.Interval,property);
        controls.Mode.ValueChangedFcn = @(~,~) intervalModeChanged(controls,property);
        updateIntervalField(controls);
    end

    function intervalEdited(field,property)
    %INTERVALEDITED Remember the entered interval and mark it as an override.
        field.UserData = string(field.Value);
        viewEdited(property);
    end

    function intervalModeChanged(controls,property)
    %INTERVALMODECHANGED Update the interval field and apply the new mode.
        updateIntervalField(controls);
        viewEdited(property);
    end

    function updateIntervalField(controls)
    %UPDATEINTERVALFIELD Enable manual interval entry and retain its previous value.
        manual = strcmp(controls.Mode.Value,'manual');
        % Text field that displays or edits the tick interval.
        field = controls.Interval;
        field.Enable = matlab.lang.OnOffSwitchState(manual);
        field.Value = "";
        field.Placeholder = "Auto";
        if manual
            field.Value = field.UserData;
            field.Placeholder = "Enter interval";
        end
    end

    function viewEdited(property)
    %VIEWEDITED Mark a setting as explicit before notifying the dialog.
        edited.(property) = true;
        onChanged();
    end

    function updateLimitFields(controls)
    %UPDATELIMITFIELDS Enable the bounds fields only for manual limits.
        enabled = matlab.lang.OnOffSwitchState(strcmp(controls.Mode.Value,'manual'));
        controls.Minimum.Enable = enabled;
        controls.Maximum.Enable = enabled;
    end

    function showEffectiveLimits(ax)
    %SHOWEFFECTIVELIMITS Display realized bounds in disabled limits fields.
        for property = reshape(string(fieldnames(limitControls)),1,[])
            controls = limitControls.(property);
            if strcmp(controls.Mode.Value,'manual'), continue; end
            limits = readLimits(ax,property);
            if isfinite(limits(1)), controls.Minimum.Value = limits(1); end
            if isfinite(limits(2)), controls.Maximum.Value = limits(2); end
        end
    end

    function [limits,mode] = readLimits(nativeAxes,property)
    %READLIMITS Return the requested side's realized bounds and mode.
        if property == "XLim"
            limits = nativeAxes.XLim;
            mode = nativeAxes.XLimMode;
        else
            ruler = nativeAxes.YAxis(1 + (property == "RightYLim"));
            limits = ruler.Limits;
            mode = ruler.LimitsMode;
        end
    end

    function limitsModeChanged(controls,property)
    %LIMITSMODECHANGED Update field availability and apply the selected limit mode.
        updateLimitFields(controls);
        viewEdited(property);
    end

    function controls = addColor(pane,label,override,default,current,allowNone)
    %ADDCOLOR Create a color mode selector and a custom RGB picker.
        row = addRow(pane,label);
        grid = uigridlayout(pane,[1 2],Padding=0,ColumnSpacing=5, ...
            ColumnWidth={'1x','fit'},RowHeight={'fit'},BackgroundColor=paneColor);
        grid.Layout.Row = row;
        grid.Layout.Column = 2;
        items = {'Default','Custom'};
        values = {'default','custom'};
        if allowNone
            items{end+1} = 'Transparent';
            values{end+1} = 'none';
        end
        mode = 'default';
        % Whether an explicit RGB override already exists.
        custom = isnumeric(override) && ~isempty(override);
        if custom
            mode = 'custom';
        elseif ~isempty(override)
            mode = 'none';
        end
        % Initial picker color used before the user chooses a custom color.
        seed = current;
        if custom, seed = override; end
        if ~isnumeric(seed), seed = host.BackgroundColor; end
        controls.Mode = uidropdown(grid,Items=items, ...
            BackgroundColor=controlColor,FontColor=controlFontColor);
        controls.Mode.ItemsData = values;
        controls.Mode.Value = mode;
        controls.Default = default;
        controls.Picker = uicolorpicker(grid,Value=seed);
        controls.Picker.UserData = custom;
        controls.Picker.Enable = matlab.lang.OnOffSwitchState(strcmp(mode,'custom'));
        controls.Mode.ValueChangedFcn = @(~,~) colorModeChanged(controls);
        controls.Picker.ValueChangedFcn = @(~,~) colorPicked(controls);
        settingsControls(end+1:end+2) = {controls.Mode,controls.Picker};
        updateSwatches(controls);
    end

    function colorPicked(controls)
    %COLORPICKED Refresh the custom icon and apply the selected color.
        controls.Picker.UserData = true;
        updateSwatches(controls);
        onChanged();
    end

    function updateSwatches(controls)
    %UPDATESWATCHES Replace the color menu icons from the current choices.
        removeStyle(controls.Mode);
        swatch("default",controls.Default);
        if controls.Picker.UserData, swatch("custom",controls.Picker.Value); end

        function swatch(name,color)
        %SWATCH Attach a circular color icon to an item with a known RGB value.
            index = find(strcmp(controls.Mode.ItemsData,name),1);
            if isempty(index) || ~isnumeric(color), return; end
            % Cached circle artwork for the item’s resolved RGB color.
            icon = matlabx.ui.icon.get(Shape="circle",Color=color,Size=16);
            addStyle(controls.Mode,uistyle(Icon=icon),"item",index);
        end
    end

    function colorModeChanged(controls)
    %COLORMODECHANGED Enable the picker only for a custom color and apply the mode.
        controls.Picker.Enable = matlab.lang.OnOffSwitchState(strcmp(controls.Mode.Value,'custom'));
        onChanged();
    end

    function value = readColor(controls)
    %READCOLOR Resolve the selected mode to an inherited or explicit color.
        value = [];
        switch string(controls.Mode.Value)
            case "default"
                if forExport, value = controls.Default; end
            case "custom"
                value = controls.Picker.Value;
            case "none"
                value = "none";
        end
    end

    function color = effectiveColor(base,override)
    %EFFECTIVECOLOR Return the override when the user supplied one.
        color = base;
        if ~isempty(override), color = override; end
    end

    function [style,view,message] = readSettings()
    %READSETTINGS Read validated appearance and view settings from the controls.
        style = struct();
        % View values that preserve inherited settings until the user edits them.
        view = struct();
        % Validation message returned when a field is invalid.
        message = "";
        for property = reshape(string(fieldnames(appearance)),1,[])
            style.(property) = appearance.(property).Value;
        end
        if supports("Typography"), style.FontUnits = "points"; end
        if supports("Rulers"), style.TickLength = [tickLength.Value tickLength.UserData]; end
        if supports("Colors")
            style.BackgroundColorOverride = readColor(backgroundControl);
            style.AxesColorOverride = readColor(axesColorControl);
            style.ForegroundColorOverride = readColor(foregroundControl);
        end
        for property = reshape(string(fieldnames(limitControls)),1,[])
            view.(property) = viewState.(property);
            if ~isfield(edited,property), continue; end
            controls = limitControls.(property);
            if strcmp(controls.Mode.Value,'auto')
                view.(property) = "auto";
            else
                limits = [controls.Minimum.Value controls.Maximum.Value];
                if any(~isfinite(limits)) || limits(1) >= limits(2)
                    % Validation message returned when a field is invalid.
                    message = "Axis limits must be finite and increasing.";
                    return;
                end
                view.(property) = limits;
            end
        end
        for property = reshape(string(fieldnames(intervalControls)),1,[])
            view.(property) = viewState.(property);
            if ~isfield(edited,property), continue; end
            controls = intervalControls.(property);
            if strcmp(controls.Mode.Value,'auto')
                view.(property) = "auto";
            else
                % Explicit tick distance parsed from the manual field.
                interval = str2double(controls.Interval.Value);
                if ~isreal(interval) || ~isfinite(interval) || interval <= 0
                    % Validation message returned when a field is invalid.
                    message = "Tick intervals must be positive finite values.";
                    return;
                end
                view.(property) = interval;
            end
        end
        for name = reshape(string(fieldnames(rulerColors)),1,[])
            controls = rulerColors.(name);
            view.(name) = [];
            if strcmp(controls.Mode.Value,'custom')
                view.(name) = controls.Picker.Value;
            elseif forExport
                % Encode Auto explicitly for the export copy's ruler.
                view.(name) = controls.Default;
            end
        end
        if supports("Legend")
            view.LegendVisible = viewState.LegendVisible;
            if isfield(edited,"LegendVisible")
                view.LegendVisible = string(matlab.lang.OnOffSwitchState(legendMode.Value));
            end
        end
    end

    function restoreViewDefaults()
        % Reset only controls the mounted renderer exposes.
        for property = reshape(string(fieldnames(viewDefaults)),1,[])
            value = viewDefaults.(property);
            if isfield(limitControls,property)
                controls = limitControls.(property);
                controls.Mode.Value = "auto";
                if isnumeric(value) && ~isempty(value)
                    controls.Mode.Value = "manual";
                    controls.Minimum.Value = value(1);
                    controls.Maximum.Value = value(2);
                end
                updateLimitFields(controls);
            elseif isfield(intervalControls,property)
                controls = intervalControls.(property);
                controls.Mode.Value = "auto";
                controls.Interval.UserData = "";
                if isnumeric(value) && ~isempty(value)
                    controls.Mode.Value = "manual";
                    controls.Interval.UserData = string(value);
                end
                updateIntervalField(controls);
            elseif property == "LegendVisible" && supports("Legend")
                legendMode.Value = value == "on";
            else
                continue;
            end
            if forExport || ~any(declaredDefaults == property)
                viewState.(property) = value;
            elseif property == "LegendVisible"
                viewState.LegendVisible = "default";
            else
                viewState.(property) = [];
            end
            if isfield(edited,property), edited = rmfield(edited,property); end
        end
        for name = reshape(string(fieldnames(rulerColors)),1,[])
            controls = rulerColors.(name);
            controls.Mode.Value = 'default';
            controls.Picker.Enable = 'off';
        end
        % Read appearance defaults from the class so constructor defaults
        % and the reset button stay in sync.
        for property = reshape(string(fieldnames(appearance)),1,[])
            control = appearance.(property);
            switch property
                case {"GridVisible","BoxVisible","TitleVisible"}
                    defaultValue = false;
                otherwise
                    % Class metadata containing the constructor default.
                    propertyInfo = findprop(host,property);
                    defaultValue = propertyInfo.DefaultValue;
            end
            control.Value = defaultValue;
        end
        if supports("Rulers")
            % Restore both native tick lengths, including the hidden 3-D value.
            propertyInfo = findprop(host,"TickLength");
            % Default tick lengths for both 2-D and 3-D axes.
            lengths = propertyInfo.DefaultValue;
            tickLength.Value = lengths(1);
            tickLength.UserData = lengths(2);
        end

        if supports("Colors")
            for controls = [backgroundControl,axesColorControl,foregroundControl]
                controls.Mode.Value = "default";
                controls.Picker.Enable = 'off';
            end
        end
    end

    function revertControls()
    %REVERTCONTROLS Restore control values and inheritance from the opening snapshot.
        viewState = openingView;
        % View settings explicitly changed since opening or restoring defaults.
        edited = struct();
        for k = 1:numel(settingsControls)
            settingsControls{k}.Value = openingValues{k};
            settingsControls{k}.UserData = openingData{k};
        end
        for property = reshape(string(fieldnames(limitControls)),1,[])
            updateLimitFields(limitControls.(property));
        end
        for property = reshape(string(fieldnames(intervalControls)),1,[])
            updateIntervalField(intervalControls.(property));
        end
        for name = reshape(string(fieldnames(rulerColors)),1,[])
            controls = rulerColors.(name);
            controls.Picker.Enable = matlab.lang.OnOffSwitchState(strcmp(controls.Mode.Value,'custom'));
            updateSwatches(controls);
        end
        if supports("Colors")
            for controls = [backgroundControl,axesColorControl,foregroundControl]
                controls.Picker.Enable = matlab.lang.OnOffSwitchState(strcmp(controls.Mode.Value,'custom'));
                updateSwatches(controls);
            end
        end
    end
end
