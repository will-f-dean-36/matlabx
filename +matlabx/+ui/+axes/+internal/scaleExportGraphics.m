function cleanup = scaleExportGraphics(handles,scale,names)
%SCALEEXPORTGRAPHICS Temporarily scale size properties on owned primitives.
%   Pass each primitive once. Scatter SizeData is an area in points squared.

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

    if nargin < 3
        names = ["LineWidth","MarkerSize","FontSize","SizeData"];
    end
    % Original property values captured before the first mutation.
    state = struct('Handle',{},'Property',{},'Value',{});
    for i = 1:numel(handles)
        % Owned primitive whose style properties may need scaling.
        h = handles{i};
        if isempty(h) || ~isvalid(h), continue; end
        for j = 1:numel(names)
            % Candidate style property on the current primitive.
            name = names(j);
            if ~isprop(h,name), continue; end
            % Original graphics value to restore after export.
            value = h.(name);
            if ~isnumeric(value) || isempty(value), continue; end
            state(end+1) = struct('Handle',h,'Property',name,'Value',value); %#ok<AGROW>
        end
    end

    % Last property assignment attempted before cleanup.
    applied = 0;
    % Scope guard that restores styling after success or failure.
    cleanup = onCleanup(@restore);
    for i = 1:numel(state)
        % Snapshot entry for the property being scaled or restored.
        item = state(i);
        % Exponent that distinguishes marker area from linear size.
        power = 1 + (item.Property == "SizeData");
        % Last property assignment attempted before cleanup.
        applied = i;
        item.Handle.(item.Property) = item.Value .* scale.^power;
    end

    function restore()
    %RESTORE Restore surviving graphics in the reverse order of mutation.
        for k = applied:-1:1
            % Snapshot entry for the property being scaled or restored.
            item = state(k);
            if isvalid(item.Handle)
                item.Handle.(item.Property) = item.Value;
            end
        end
    end
end
