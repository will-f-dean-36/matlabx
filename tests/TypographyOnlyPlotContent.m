classdef TypographyOnlyPlotContent < matlabx.ui.axes.PlotContent
%TYPOGRAPHYONLYPLOTCONTENT Fixture for a chart that owns its colors and view.

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

    methods
        function capabilities = axesCapabilities(~)
        %AXESCAPABILITIES Expose only typography to shared axes settings.
            capabilities = "Typography";
        end
    end

    methods (Access=protected)
        function refreshGraphics(obj)
        %REFRESHGRAPHICS Set chart-owned framing and color for the fixture.
            % Native axes controlled by the mounted test renderer.
            ax = obj.Host.Axes;
            set(ax,XLim=[-5 5],YLim=[-5 5],XTick=[], ...
                Color=[0.1 0.2 0.3],XColor='none',LineWidth=2);
        end
    end
end
