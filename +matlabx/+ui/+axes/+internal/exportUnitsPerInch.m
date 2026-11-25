function factor = exportUnitsPerInch(units,resolution)
%EXPORTUNITSPERINCH Number of the requested export units in one inch.

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

    switch string(units)
        case "pixels"
            factor = resolution;
        case "inches"
            factor = 1;
        case "centimeters"
            factor = 2.54;
        case "points"
            factor = 72;
        otherwise
            error('matlabx:ui:axes:InvalidExportUnits', ...
                'Unsupported export units "%s".',string(units));
    end
end
