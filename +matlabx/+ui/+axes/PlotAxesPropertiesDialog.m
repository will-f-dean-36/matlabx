classdef PlotAxesPropertiesDialog
%PLOTAXESPROPERTIESDIALOG Edit shared appearance and view for a PlotAxes.

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

    methods (Static)
        function fig = open(host)
        %OPEN Show the controls supported by the mounted chart.
            capabilities = host.getAxesCapabilities();
            fig = [];
            if isempty(capabilities), return; end
            % Renderer that owns the settings available while this dialog is open.
            content = host.Content;
            % Live axes that receive the preview changes.
            ax = host.Axes;
            % Opening host settings, including inherited values.
            originalSettings = host.getAxesSettings();
            % Native appearance properties restored on cancellation.
            appearanceNames = {'Color','FontName','FontUnits','FontSize', ...
                'LabelFontSizeMultiplier','TitleFontSizeMultiplier','XColor','ZColor', ...
                'XGrid','YGrid','Box','TickLength','TickDir','LineWidth'};
            % Opening values of the native appearance properties.
            originalAppearance = get(ax,appearanceNames);
            % Text objects whose formatting is restored separately from the axes.
            labels = [ax.Title,ax.Subtitle,ax.XLabel,ax.YAxis.Label,ax.ZLabel];
            % Opening colors of the axes decorations.
            originalLabelColors = {labels.Color};
            % Opening font units of the axes decorations.
            originalLabelUnits = {labels.FontUnits};
            % Opening visibility of the native title.
            originalTitleVisible = ax.Title.Visible;
            % Opening legend visibility, or empty when there is no legend.
            originalLegendVisible = "";
            if ~isempty(ax.Legend), originalLegendVisible = string(ax.Legend.Visible); end
            % Native limits and tick properties affected by live editing.
            originalViewNames = {'XLim','XTick','XTickLabel'};
            % Actual opening view, which can differ from the stored host settings.
            originalNativeView = get(ax,originalViewNames);
            % Opening automatic or manual mode of each native view property.
            originalNativeModes = get(ax,strcat(originalViewNames,'Mode'));
            % Preserve each ruler independently from the active yyaxis side.
            yNames = {'Limits','TickValues','TickLabels','Color'};
            yModes = {'LimitsMode','TickValuesMode','TickLabelsMode'};
            originalYValues = get(ax.YAxis,yNames);
            originalYModes = get(ax.YAxis,yModes);
            % Whether live settings have been applied and may need rollback.
            changed = false;
            fig = uifigure(Name="Axes Properties",Visible="off", ...
                Position=[100 100 470 420],Color=[.12 .12 .12], ...
                CloseRequestFcn=@(~,~) cancelChanges());
            root = uigridlayout(fig,[2 1],RowHeight={'1x','fit'},Padding=[10 10 10 10], ...
                RowSpacing=10,BackgroundColor=[.12 .12 .12]);
            tabs = uitabgroup(root);
            buttons = uigridlayout(root,[1 5],Padding=0, ...
                ColumnWidth={105,105,'1x',70,70},RowHeight={'fit'}, ...
                ColumnSpacing=5,BackgroundColor=[.12 .12 .12]);
            restoreButton = uibutton(buttons,Text="Restore defaults", ...
                BackgroundColor=[.3 .3 .3],FontColor=[.9 .9 .9], ...
                ButtonPushedFcn=@(~,~) restorePlotDefaults());
            restoreButton.Layout.Column = 1;
            revertButton = uibutton(buttons,Text="Revert changes", ...
                BackgroundColor=[.3 .3 .3],FontColor=[.9 .9 .9], ...
                ButtonPushedFcn=@(~,~) revertChanges());
            revertButton.Layout.Column = 2;
            cancel = uibutton(buttons,Text="Cancel",BackgroundColor=[.3 .3 .3], ...
                FontColor=[.9 .9 .9],ButtonPushedFcn=@(~,~) cancelChanges());
            cancel.Layout.Column = 4;
            apply = uibutton(buttons,Text="Apply",BackgroundColor=[.18 .42 .68], ...
                FontColor=[1 1 1],ButtonPushedFcn=@(~,~) applyChanges(true));
            apply.Layout.Column = 5;

            [read,refreshLimits,restoreDefaults,revert] = matlabx.ui.axes.internal.plotAxesControlTabs( ...
                tabs,host,@() applyChanges(false),false);
            refreshLimits(ax);

            % A dialog belongs to the chart that supplied its controls.
            listeners = [addlistener(host,'ContentChanged',@(~,~) delete(fig)), ...
                addlistener(ax,'XLim','PostSet',@(~,~) refreshLimits(ax)), ...
                addlistener(ax,'YLim','PostSet',@(~,~) refreshLimits(ax))];
            fig.DeleteFcn = @(~,~) delete(listeners);
            movegui(fig,"center");
            fig.Visible = "on";

            function applyChanges(commit)
            %APPLYCHANGES Apply valid edits to the live axes and close when requested.
                if ~isequal(content,host.Content), delete(fig); return; end
                [style,view,message] = read();
                if strlength(message) > 0
                    if commit, uialert(fig,message,"Invalid Axes Properties"); end
                    return;
                end
                try
                    % Whether live settings have been applied and may need rollback.
                    changed = true;
                    % Merge the supported dialog fields into a complete snapshot.
                    settings = host.getAxesSettings();
                    for property = reshape(string(fieldnames(style)),1,[])
                        settings.(property) = style.(property);
                    end
                    for property = reshape(string(fieldnames(view)),1,[])
                        settings.AxesView.(property) = view.(property);
                    end
                    host.applyAxesSettings_(settings);
                catch exception
                    if commit, uialert(fig,exception.message,"Invalid Axes Properties"); end
                    return;
                end
                drawnow nocallbacks;
                refreshLimits(ax);
                if commit
                    host.commitAxesProperties_();
                    if isgraphics(fig), delete(fig); end
                end
            end

            function restorePlotDefaults()
            %RESTOREPLOTDEFAULTS Apply renderer and host defaults to the live axes.
                restoreDefaults();
                applyChanges(false);
                % Inherited settings can already be stored as defaults while the
                % user has panned the native axes. Restore the displayed view too.
                defaults = host.getAxesViewDefaults();
                if isvalid(ax)
                    capabilities = host.getAxesCapabilities();
                    for axisName = ["X","Y","RightY"]
                        property = axisName + "Lim";
                        if isfield(defaults,property) && any(capabilities == property)
                            limits = defaults.(property);
                            if isequal(string(limits),"auto")
                                limits = [];
                                if ~isempty(content), limits = content.automaticAxesLimits(axisName); end
                            end
                            if axisName == "X"
                                if isempty(limits), ax.XLimMode = 'auto'; else, ax.XLim = limits; end
                            else
                                ruler = ax.YAxis(1 + (axisName == "RightY"));
                                if isempty(limits), ruler.LimitsMode = 'auto'; else, ruler.Limits = limits; end
                            end
                        end
                        property = axisName + "TickInterval";
                        if isfield(defaults,property) && any(capabilities == property) ...
                                && isequal(string(defaults.(property)),"auto")
                            if axisName == "Y"
                                ax.YAxis(1).TickValuesMode = 'auto';
                            else
                                ax.XTickMode = 'auto';
                            end
                        end
                    end
                    if any(capabilities == "Legend") && isfield(defaults,"LegendVisible") ...
                            && ~isempty(ax.Legend)
                        ax.Legend.Visible = defaults.LegendVisible;
                    end
                end
                drawnow nocallbacks;
                refreshLimits(ax);
            end

            function revertChanges()
            %REVERTCHANGES Restore the opening controls and their associated plot state.
                revert();
                restoreOpeningState();
                refreshLimits(ax);
            end

            function cancelChanges()
            %CANCELCHANGES Restore the opening state and close the dialog.
                restoreOpeningState();
                delete(fig);
            end

            function restoreOpeningState()
            %RESTOREOPENINGSTATE Restore the host settings and the opening native axes view.
                if changed && isvalid(host) && isequal(content,host.Content) ...
                        && isvalid(ax) && ax.BeingDeleted == "off"
                    host.applyAxesSettings_(originalSettings);
                    drawnow nocallbacks;
                    set(ax,appearanceNames,originalAppearance);
                    set(labels(:),{'Color','FontUnits'}, ...
                        [originalLabelColors(:),originalLabelUnits(:)]);
                    ax.Title.Visible = originalTitleVisible;
                    for k = 1:numel(originalViewNames)
                        name = originalViewNames{k};
                        if strcmp(originalNativeModes{k},'manual')
                            ax.(name) = originalNativeView{k};
                        else
                            ax.([name 'Mode']) = originalNativeModes{k};
                        end
                    end
                    for side = 1:numel(ax.YAxis)
                        ruler = ax.YAxis(side);
                        ruler.Color = originalYValues{side,4};
                        for k = 1:numel(yModes)
                            if strcmp(originalYModes{side,k},'manual')
                                ruler.(yNames{k}) = originalYValues{side,k};
                            else
                                ruler.(yModes{k}) = originalYModes{side,k};
                            end
                        end
                    end
                    if ~isempty(ax.Legend) && strlength(originalLegendVisible) > 0
                        ax.Legend.Visible = originalLegendVisible;
                    end
                end
                % Whether live settings have been applied and may need rollback.
                changed = false;
            end
        end
    end
end
