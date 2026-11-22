function [fig,host] = exportSizeTest()
%EXPORTSIZETEST Open a PlotAxes chart with known physical size targets.
%
%   [FIG,HOST] = matlabx.ui.axes.demo.exportSizeTest() opens the chart.
%   Use the native Export Plot dialog or call HOST.exportPlot directly.
%   Keep the figure size and typography settings fixed between exports:
%
%       [fig,host] = matlabx.ui.axes.demo.exportSizeTest();
%       host.exportPlot("size-large.pdf",ContentType="vector", ...
%           Width=8,Height=6,PreserveAspectRatio="on");
%       host.exportPlot("size-small.pdf",ContentType="vector", ...
%           Width=4,Height=3,PreserveAspectRatio="on");
%
%   The chart lists target sizes in points. Inspect the exported objects
%   to see whether MATLAB preserves those sizes.

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

    fig = uifigure(Name="PlotAxes export size test", ...
        Position=[100 100 820 560],Color=[1 1 1]);
    layout = uigridlayout(fig,[1 1],Padding=[0 0 0 0]);
    host = matlabx.ui.axes.PlotAxes(layout, ...
        BackgroundColor=[1 1 1],Color=[1 1 1], ...
        FontUnits="points",FontSize=10,LabelFontSizeMultiplier=1.2, ...
        TitleFontSizeMultiplier=1.4,TitleVisible="on");
    host.mount(matlabx.ui.axes.internal.ExportSizeContent());

    ax = host.Axes;
    ax.XLim = [0 12];
    ax.YLim = [0 7];
    ax.XTick = 0:2:12;
    ax.YTick = 0:7;
    drawnow;

    % Read realized sizes after the host applies its font multipliers.
    ax.Title.String = sprintf( ...
        'Export size test  |  Title target: %g pt',ax.Title.FontSize);
    ax.XLabel.String = sprintf( ...
        'X label target: %g pt  |  X and Y tick target: %g pt', ...
        ax.XLabel.FontSize,ax.FontSize);
    ax.YLabel.String = sprintf('Y label target: %g pt',ax.YLabel.FontSize);
end
