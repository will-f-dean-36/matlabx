classdef DualYDemoContent < matlabx.ui.axes.PlotContent
%DUALYDEMOCONTENT Example renderer with one line per native Y ruler.

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

    properties (Access=private)
        % Data multipliers in left, right order.
        Multipliers = [1 1]

        % Renderer-owned lines in left, right order.
        Lines = gobjects(1,2)
    end

    properties (Constant, Access=private)
        % Shared palette for the lines and their default ruler colors.
        Colors = [0 0.447 0.741; 0.85 0.325 0.098]

        % MATLAB yyaxis side names in ruler order.
        Sides = {'left','right'}
    end

    methods
        function setMultipliers(obj,values)
        %SETMULTIPLIERS Update the data and reapply the host's view settings.
            obj.Multipliers = values;
            obj.refresh();
        end

        function colors = yAxisDefaultColors(obj)
        %YAXISDEFAULTCOLORS Match each ruler to its series by default.
            colors = obj.Colors;
        end

        function delete(obj)
        %DELETE Detach the renderer and release its owned lines.
            obj.detach();
            delete(obj.Lines(isgraphics(obj.Lines)));
        end
    end

    methods (Access=protected)
        function refreshGraphics(obj)
        %REFRESHGRAPHICS Update two sample series on different scales.
            % Use different units and shapes to make ruler assignment visible.
            ax = obj.Host.Axes;
            hours = linspace(0,24,145);
            temperature = 18 + 6*sin(2*pi*(hours-6)/24);
            power = 450 + 320*exp(-((hours-17)/3).^2);
            samples = [temperature;power];
            labels = ["Temperature (°C)","Power (W)"];

            % Keep the side active before refresh once both rulers exist.
            activeSide = ax.YAxisLocation;
            for side = 1:2
                yyaxis(ax,obj.Sides{side});
                if ~isgraphics(obj.Lines(side))
                    obj.Lines(side) = line(ax,hours,samples(side,:), ...
                        Color=obj.Colors(side,:),LineWidth=1.5);
                end
                obj.Lines(side).YData = samples(side,:) .* obj.Multipliers(side);
                ax.YLabel.String = labels(side);
                ax.YLimMode = 'auto';
            end
            yyaxis(ax,activeSide);
            ax.XLabel.String = "Time (hours)";
            ax.Title.String = "Temperature and power over one day";
        end

        function attachGraphics(obj,ax)
        %ATTACHGRAPHICS Reparent each existing line to its matching ruler.
            for side = 1:2
                if ~isgraphics(obj.Lines(side)), continue; end
                if ~isempty(ax), yyaxis(ax,obj.Sides{side}); end
                obj.Lines(side).Parent = ax;
            end
        end
    end
end
