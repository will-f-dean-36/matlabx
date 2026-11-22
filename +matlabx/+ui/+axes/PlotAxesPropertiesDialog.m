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
            content = host.Content;
            ax = host.Axes;
            originalView = host.AxesView;
            appearanceNames = {'Color','FontName','FontUnits','FontSize', ...
                'LabelFontSizeMultiplier','TitleFontSizeMultiplier','XColor','YColor','ZColor', ...
                'XGrid','YGrid','Box','TickLength','TickDir','LineWidth'};
            originalAppearance = get(ax,appearanceNames);
            labels = [ax.Title,ax.Subtitle,ax.XLabel,ax.YLabel,ax.ZLabel];
            originalLabelColors = {labels.Color};
            originalLabelUnits = {labels.FontUnits};
            originalTitleVisible = ax.Title.Visible;
            originalLegendVisible = "";
            if ~isempty(ax.Legend), originalLegendVisible = string(ax.Legend.Visible); end
            originalViewNames = {'XLim','YLim','XTick','YTick','XTickLabel','YTickLabel'};
            originalNativeView = get(ax,originalViewNames);
            originalNativeModes = get(ax,strcat(originalViewNames,'Mode'));
            changed = false;
            fig = uifigure(Name="Axes Properties",Visible="off", ...
                Position=[100 100 470 420],Color=[.12 .12 .12], ...
                CloseRequestFcn=@(~,~) cancelChanges());
            root = uigridlayout(fig,[2 1],RowHeight={'1x','fit'},Padding=[10 10 10 10], ...
                RowSpacing=10,BackgroundColor=[.12 .12 .12]);
            tabs = uitabgroup(root);
            buttons = uigridlayout(root,[1 3],Padding=0, ...
                ColumnWidth={'1x',80,80},RowHeight={'fit'}, ...
                ColumnSpacing=5,BackgroundColor=[.12 .12 .12]);
            cancel = uibutton(buttons,Text="Cancel",BackgroundColor=[.3 .3 .3], ...
                FontColor=[.9 .9 .9],ButtonPushedFcn=@(~,~) cancelChanges());
            cancel.Layout.Column = 2;
            apply = uibutton(buttons,Text="Apply",BackgroundColor=[.18 .42 .68], ...
                FontColor=[1 1 1],ButtonPushedFcn=@(~,~) applyChanges(true));
            apply.Layout.Column = 3;

            [read,refreshLimits] = matlabx.ui.axes.internal.plotAxesControlTabs( ...
                tabs,host,@() applyChanges(false),false);
            [style,~] = read();
            styleNames = fieldnames(style);
            originalStyle = cellfun(@(name) host.(name),styleNames,UniformOutput=false);
            refreshLimits(ax);

            % A dialog belongs to the chart that supplied its controls.
            listeners = [addlistener(host,'ContentChanged',@(~,~) delete(fig)), ...
                addlistener(ax,'XLim','PostSet',@(~,~) refreshLimits(ax)), ...
                addlistener(ax,'YLim','PostSet',@(~,~) refreshLimits(ax))];
            fig.DeleteFcn = @(~,~) delete(listeners);
            movegui(fig,"center");
            fig.Visible = "on";

            function applyChanges(commit)
                if ~isequal(content,host.Content), delete(fig); return; end
                [style,view,message] = read();
                if strlength(message) > 0
                    if commit, uialert(fig,message,"Invalid Axes Properties"); end
                    return;
                end
                try
                    changed = true;
                    args = namedargs2cell(view);
                    host.setAxesView(args{:});
                    for property = reshape(string(fieldnames(style)),1,[])
                        host.(property) = style.(property);
                    end
                catch exception
                    if commit, uialert(fig,exception.message,"Invalid Axes Properties"); end
                    return;
                end
                drawnow nocallbacks;
                refreshLimits(ax);
                if commit, delete(fig); end
            end

            function cancelChanges()
                if changed && isvalid(host) && isequal(content,host.Content) ...
                        && isvalid(ax) && ax.BeingDeleted == "off"
                    for k = 1:numel(styleNames)
                        host.(styleNames{k}) = originalStyle{k};
                    end
                    capabilities = host.getAxesCapabilities();
                    if any(capabilities == "Legend"), capabilities(end+1) = "LegendVisible"; end
                    view = rmfield(originalView,setdiff(string(fieldnames(originalView)),capabilities));
                    args = namedargs2cell(view);
                    host.setAxesView(args{:});
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
                    if ~isempty(ax.Legend) && strlength(originalLegendVisible) > 0
                        ax.Legend.Visible = originalLegendVisible;
                    end
                end
                delete(fig);
            end
        end
    end
end
