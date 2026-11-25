function scale = exportStyleScale(sourceInches,outputSize,units,resolution,preserveAspect)
%EXPORTSTYLESCALE Estimate the inverse render scale for physical styling.

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

    outputInches = outputSize ./ matlabx.ui.axes.internal.exportUnitsPerInch(units,resolution);
    % Requested width and height divided by their realized source dimensions.
    ratios = outputInches ./ sourceInches;
    % Requested width and height divided by their realized source dimensions.
    ratios = ratios(~isnan(outputSize)); % Omitted dimensions follow the source aspect.
    validateattributes(ratios,{'double'},{'nonempty','finite','positive'});
    if preserveAspect == "on"
        scale = 1 / min(ratios);
    else
        % Retain the existing ImageAxes estimate for stretched exports.
        scale = 1 / sqrt(prod(ratios));
    end
end
