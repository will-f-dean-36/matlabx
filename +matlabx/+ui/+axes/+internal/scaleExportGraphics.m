function cleanup = scaleExportGraphics(handles,scale,names)
%SCALEEXPORTGRAPHICS Temporarily scale size properties on owned primitives.
%   Pass each primitive once. Scatter SizeData is an area in points squared.
    if nargin < 3
        names = ["LineWidth","MarkerSize","FontSize","SizeData"];
    end
    state = struct('Handle',{},'Property',{},'Value',{});
    for i = 1:numel(handles)
        h = handles{i};
        if isempty(h) || ~isvalid(h), continue; end
        for j = 1:numel(names)
            name = names(j);
            if ~isprop(h,name), continue; end
            value = h.(name);
            if ~isnumeric(value) || isempty(value), continue; end
            state(end+1) = struct('Handle',h,'Property',name,'Value',value); %#ok<AGROW>
        end
    end

    applied = 0;
    cleanup = onCleanup(@restore);
    for i = 1:numel(state)
        item = state(i);
        power = 1 + (item.Property == "SizeData");
        applied = i;
        item.Handle.(item.Property) = item.Value .* scale.^power;
    end

    function restore()
        for k = applied:-1:1
            item = state(k);
            if isvalid(item.Handle)
                item.Handle.(item.Property) = item.Value;
            end
        end
    end
end
