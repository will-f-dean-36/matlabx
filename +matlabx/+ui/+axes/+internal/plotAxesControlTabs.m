function [read,refreshLimits] = plotAxesControlTabs(tabs,host,onChanged,forExport)
%PLOTAXESCONTROLTABS Build the shared axes settings tabs and return a reader.
    capabilities = host.getAxesCapabilities();
    ax = host.Axes;
    initialView = host.AxesView;
    defaultLabel = "Plot default";
    backgroundOverride = host.BackgroundColorOverride;
    axesColorOverride = host.AxesColorOverride;
    if forExport
        % Retain the transparent default unless the user set a color.
        if isempty(backgroundOverride), backgroundOverride = "none"; end
        if isempty(axesColorOverride), axesColorOverride = "none"; end
        defaultLabel = "Current plot";
        initialView.XLim = [];
        initialView.YLim = [];
        initialView.LegendVisible = "default";
    end
    paneColor = [.18 .18 .18];
    controlColor = [.3 .3 .3];
    fontColor = [.85 .85 .85];
    controlFontColor = [.9 .9 .9];

    appearance = struct();
    if any(ismember(["Colors","Typography","Grid","Box","Legend"],capabilities))
        pane = addTab("Appearance");
        if supports("Colors")
            backgroundControl = addColor(pane,"Background color", ...
                backgroundOverride,host.BackgroundColor,forExport);
            axesColorControl = addColor(pane,"Axes color", ...
                axesColorOverride,host.Color,true);
            foregroundControl = addColor(pane,"Foreground", ...
                host.ForegroundColorOverride,host.ForegroundColor,false);
        end
        if supports("Typography")
            fonts = string(listfonts());
            fonts = unique([host.FontName;fonts(:)]);
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
            legendMode = addDropDown(pane,"Legend", ...
                {char(defaultLabel),'Show','Hide'},initialView.LegendVisible, ...
                {'default','on','off'});
        end
    end

    intervalControls = struct();
    if any(ismember(["Rulers","XTickInterval","YTickInterval"],capabilities))
        pane = addTab("Ticks and Lines");
        if supports("Rulers")
            appearance.AxisLineWidth = addNumber(pane,"Axes line width (pt)",host.AxisLineWidth,[eps Inf]);
            tickLength = addNumber(pane,"Tick length (fraction of axes size)",host.TickLength(1),[0 Inf]);
            appearance.TickDirection = addDropDown(pane,"Tick direction", ...
                {'In','Out','Both','None'},host.TickDirection,{'in','out','both','none'});
        end
        for axisName = ["X","Y"]
            property = axisName + "TickInterval";
            if supports(property)
                value = initialView.(property);
                intervalControls.(property) = addText(pane,axisName+" tick interval",value,defaultLabel);
            end
        end
    end

    limitControls = struct();
    if any(ismember(["XLim","YLim"],capabilities))
        pane = addTab("Limits");
        for axisName = ["X","Y"]
            property = axisName + "Lim";
            if supports(property), limitControls.(property) = addLimits(pane,axisName); end
        end
    end

    read = @readSettings;
    refreshLimits = @showEffectiveLimits;

    function tf = supports(property)
        tf = any(capabilities == property);
    end

    function value = points(value)
        if host.FontUnits == "pixels"
            value = value * 72 / get(groot,'ScreenPixelsPerInch');
        end
    end

    function pane = addTab(name)
        tab = uitab(tabs,Title=name,BackgroundColor=paneColor,ForegroundColor=fontColor);
        pane = uigridlayout(tab,[1 2],ColumnWidth={'fit','1x'}, ...
            Padding=[5 5 5 5],ColumnSpacing=5,RowSpacing=5, ...
            BackgroundColor=paneColor,RowHeight={'1x'},Scrollable="on");
    end

    function row = addRow(pane,label)
        rows = pane.RowHeight;
        row = numel(rows);
        pane.RowHeight = [rows(1:end-1),{'fit','1x'}];
        caption = uilabel(pane,Text=label,FontColor=fontColor);
        caption.Layout.Row = row;
        caption.Layout.Column = 1;
    end

    function control = addDropDown(pane,label,items,value,itemsData)
        row = addRow(pane,label);
        control = uidropdown(pane,Items=items,BackgroundColor=controlColor,FontColor=controlFontColor);
        if nargin == 5, control.ItemsData = itemsData; end
        control.Value = char(value);
        control.Layout.Row = row;
        control.Layout.Column = 2;
        control.ValueChangedFcn = @(~,~) onChanged();
    end

    function control = addNumber(pane,label,value,bounds)
        row = addRow(pane,label);
        control = uieditfield(pane,"numeric",Limits=bounds,Value=value, ...
            BackgroundColor=controlColor,FontColor=controlFontColor);
        control.Layout.Row = row;
        control.Layout.Column = 2;
        control.ValueChangedFcn = @(~,~) onChanged();
    end

    function control = addText(pane,label,value,placeholder)
        row = addRow(pane,label);
        text = "";
        if ~isempty(value), text = string(value); end
        control = uieditfield(pane,"text",Value=text,Placeholder=placeholder, ...
            BackgroundColor=controlColor,FontColor=controlFontColor);
        control.Layout.Row = row;
        control.Layout.Column = 2;
        control.ValueChangedFcn = @(~,~) onChanged();
    end

    function control = addCheck(pane,label,value)
        row = addRow(pane,label);
        control = uicheckbox(pane,Text="",Value=logical(value),FontColor=controlFontColor);
        control.Layout.Row = row;
        control.Layout.Column = 2;
        control.ValueChangedFcn = @(~,~) onChanged();
    end

    function controls = addLimits(pane,axisName)
        property = axisName + "Lim";
        limits = initialView.(property);
        shown = ax.(property);
        mode = "default";
        if ischar(limits) || isstring(limits)
            mode = "auto";
        elseif ~isempty(limits)
            mode = "manual";
            shown = limits;
        end
        controls.Mode = addDropDown(pane,axisName+" limits", ...
            {char(defaultLabel),'Auto','Manual'},mode,{'default','auto','manual'});
        controls.Minimum = addNumber(pane,axisName+" minimum",shown(1),[-Inf Inf]);
        controls.Maximum = addNumber(pane,axisName+" maximum",shown(2),[-Inf Inf]);
        controls.Mode.ValueChangedFcn = @(~,~) limitsModeChanged(controls);
        updateLimitFields(controls);
    end

    function updateLimitFields(controls)
        enabled = matlab.lang.OnOffSwitchState(strcmp(controls.Mode.Value,'manual'));
        controls.Minimum.Enable = enabled;
        controls.Maximum.Enable = enabled;
    end

    function showEffectiveLimits(ax)
        for property = reshape(string(fieldnames(limitControls)),1,[])
            controls = limitControls.(property);
            if strcmp(controls.Mode.Value,'manual'), continue; end
            limits = ax.(property);
            if isfinite(limits(1)), controls.Minimum.Value = limits(1); end
            if isfinite(limits(2)), controls.Maximum.Value = limits(2); end
        end
    end

    function limitsModeChanged(controls)
        updateLimitFields(controls);
        onChanged();
    end

    function controls = addColor(pane,label,override,fallback,allowNone)
        row = addRow(pane,label);
        grid = uigridlayout(pane,[1 2],Padding=0,ColumnSpacing=5, ...
            ColumnWidth={'1x','fit'},RowHeight={'fit'},BackgroundColor=paneColor);
        grid.Layout.Row = row;
        grid.Layout.Column = 2;
        items = {char(defaultLabel),'Custom'};
        values = {'default','custom'};
        if allowNone
            items{end+1} = 'Transparent';
            values{end+1} = 'none';
        end
        mode = 'default';
        if isnumeric(override) && ~isempty(override)
            mode = 'custom';
            fallback = override;
        elseif ~isempty(override)
            mode = 'none';
        end
        if ~isnumeric(fallback), fallback = host.BackgroundColor; end
        controls.Mode = uidropdown(grid,Items=items, ...
            BackgroundColor=controlColor,FontColor=controlFontColor);
        controls.Mode.ItemsData = values;
        controls.Mode.Value = mode;
        controls.Picker = uicolorpicker(grid,Value=fallback);
        controls.Picker.Enable = matlab.lang.OnOffSwitchState(strcmp(mode,'custom'));
        controls.Mode.ValueChangedFcn = @(~,~) colorModeChanged(controls);
        controls.Picker.ValueChangedFcn = @(~,~) onChanged();
    end

    function colorModeChanged(controls)
        controls.Picker.Enable = matlab.lang.OnOffSwitchState(strcmp(controls.Mode.Value,'custom'));
        onChanged();
    end

    function value = readColor(controls)
        value = [];
        switch string(controls.Mode.Value)
            case "custom"
                value = controls.Picker.Value;
            case "none"
                value = "none";
        end
    end

    function [style,view,message] = readSettings()
        style = struct();
        view = struct();
        message = "";
        for property = reshape(string(fieldnames(appearance)),1,[])
            style.(property) = appearance.(property).Value;
        end
        if supports("Typography"), style.FontUnits = "points"; end
        if supports("Rulers"), style.TickLength = [tickLength.Value host.TickLength(2)]; end
        if supports("Colors")
            style.BackgroundColorOverride = readColor(backgroundControl);
            style.AxesColorOverride = readColor(axesColorControl);
            style.ForegroundColorOverride = readColor(foregroundControl);
        end
        for property = reshape(string(fieldnames(limitControls)),1,[])
            controls = limitControls.(property);
            switch string(controls.Mode.Value)
                case "default"
                    view.(property) = [];
                case "auto"
                    view.(property) = "auto";
                case "manual"
                    limits = [controls.Minimum.Value controls.Maximum.Value];
                    if any(~isfinite(limits)) || limits(1) >= limits(2)
                        message = "Axis limits must be finite and increasing.";
                        return;
                    end
                    view.(property) = limits;
            end
        end
        for property = reshape(string(fieldnames(intervalControls)),1,[])
            value = strtrim(intervalControls.(property).Value);
            view.(property) = [];
            if isempty(value), continue; end
            interval = str2double(value);
            if ~isreal(interval) || ~isfinite(interval) || interval <= 0
                message = "Tick intervals must be positive finite values.";
                return;
            end
            view.(property) = interval;
        end
        if supports("Legend"), view.LegendVisible = string(legendMode.Value); end
    end
end
