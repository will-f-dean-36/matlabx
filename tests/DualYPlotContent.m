classdef DualYPlotContent < matlabx.ui.axes.PlotContent
%DUALYPLOTCONTENT Fixture for transferable lines on two native Y rulers.

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

    properties
        % Multiplier used to test an automatic right-hand range.
        RightScale = 1
    end

    properties (SetAccess=private)
        % Line handles owned by the left and right rulers, respectively.
        Lines = gobjects(1,2)
    end

    methods
        function colors = yAxisDefaultColors(~)
        %YAXISDEFAULTCOLORS Provide distinct renderer colors for the fixture.
            colors = [0.1 0.2 0.3; 0.4 0.5 0.6];
        end
    end

    methods (Access=protected)
        function refreshGraphics(obj)
        %REFRESHGRAPHICS Render or update both series and restore their labels.
            ax = obj.Host.Axes;
            for side = 1:2
                names = {'left','right'};
                yyaxis(ax,names{side});
                if ~isgraphics(obj.Lines(side))
                    obj.Lines(side) = line(ax,[1 2 3],nan(1,3));
                end
                ax.YLabel.String = [names{side} ' specimen'];
                ax.YLimMode = 'auto';
            end
            obj.Lines(1).YData = [1 2 3];
            obj.Lines(2).YData = [10 20 30] .* obj.RightScale;
        end

        function attachGraphics(obj,ax)
        %ATTACHGRAPHICS Reparent each surviving line on its own Y side.
            names = {'left','right'};
            for side = 1:2
                if ~isgraphics(obj.Lines(side)), continue; end
                if ~isempty(ax), yyaxis(ax,names{side}); end
                obj.Lines(side).Parent = ax;
            end
        end
    end

    methods
        function delete(obj)
        %DELETE Detach and delete both owned lines.
            obj.detach();
            delete(obj.Lines(isgraphics(obj.Lines)));
        end
    end
end
