classdef ExportSizeContent < matlabx.ui.axes.PlotContent
%EXPORTSIZECONTENT Draw known-size specimens for the export size demo.

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
        % Group that owns the lines, markers, and labels for calibration.
        Specimens = gobjects(0)
    end

    methods
        function refresh(obj)
        %REFRESH Create the calibration specimens or reveal the existing group.
            if isempty(obj.Host)
                return
            end
            if isgraphics(obj.Specimens)
                obj.Specimens.Visible = 'on';
                return
            end

            obj.Specimens = hggroup(Parent=obj.Host.Axes);
            % Parent for all specimens and their measurement labels.
            group = obj.Specimens;
            addLabel(group,0.6,6.4,"Line width (pt)",11);
            addLabel(group,4.5,6.4,"Marker diameter (pt)",11);
            addLabel(group,8.4,6.4,"Font size (pt)",11);

            % Target stroke widths in points.
            widths = [0.5 1 2 4];
            % Target marker diameters in points.
            diameters = [4 8 12 16];
            for row = 1:numel(widths)
                % Vertical position of the current specimen row.
                y = 6 - row;
                line(Parent=group,XData=[0.6 2.3],YData=[y y], ...
                    Color=[0 0 0],LineWidth=widths(row));
                addLabel(group,2.7,y,string(widths(row)),9);
                line(Parent=group,XData=5.1,YData=y,LineStyle="none", ...
                    Marker="o",MarkerSize=diameters(row), ...
                    MarkerFaceColor=[0 0 0],MarkerEdgeColor="none");
                addLabel(group,6.1,y,string(diameters(row)),9);
            end

            % Target font sizes in points.
            sizes = [6 8 10 12 16];
            for row = 1:numel(sizes)
                % Vertical position of the current specimen row.
                y = 6 - row;
                addLabel(group,8.4,y,"Sample Ag",sizes(row));
                addLabel(group,11,y,string(sizes(row)),9);
            end
        end

        function cleanup = beginExportStyleScale(obj,scale)
        %BEGINEXPORTSTYLESCALE Temporarily scale the owned calibration specimens.
            graphics = obj.Specimens.Children;
            cleanup = matlabx.ui.axes.internal.scaleExportGraphics( ...
                arrayfun(@(h) h,graphics,UniformOutput=false),scale);
        end

        function delete(obj)
        %DELETE Detach the content and release its owned graphics.
            obj.detach();
            if isgraphics(obj.Specimens)
                delete(obj.Specimens);
            end
        end
    end

    methods (Access=protected)
        function attachGraphics(obj,ax)
        %ATTACHGRAPHICS Move the existing specimen group to the target axes.
            if isgraphics(obj.Specimens)
                obj.Specimens.Parent = ax;
            end
        end

        function hideGraphics(obj)
        %HIDEGRAPHICS Hide the specimen group while the content is detached.
            if isgraphics(obj.Specimens)
                obj.Specimens.Visible = 'off';
            end
        end
    end
end

function addLabel(group,x,y,label,fontSize)
%ADDLABEL Draw a point-sized label beside its calibration specimen.
    text(Parent=group,Position=[x y 0],String=label, ...
        FontUnits="points",FontSize=fontSize,Interpreter="none", ...
        Color=[0 0 0],VerticalAlignment="middle");
end
