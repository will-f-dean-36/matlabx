classdef Colormap < handle
    % Represents a single colormap file with lazy-loaded data.
    properties (SetAccess=immutable)
        Name     string
        Category string
        Path     string
    end
    properties (Access=private)
        MapCache double = []
    end

    methods
        function this = Colormap(name, category, path)
            this.Name     = string(name);
            this.Category = string(category);
            this.Path     = string(path);
        end

        function M = getMap(this)
            % Lazy load Nx3 from .mat; cache after first load.
            if ~isempty(this.MapCache)
                M = this.MapCache;
                return
            end
            mf = matfile(this.Path);
            vars = who(mf);
            M = [];
            if any(strcmp(vars,'Cmap'))
                M = mf.Cmap;
            else
                % fallback: first numeric N-by-3 variable
                for i = 1:numel(vars)
                    tmp = mf.(vars{i});
                    if isnumeric(tmp) && ismatrix(tmp) && size(tmp,2) == 3
                        M = tmp; break
                    end
                end
            end
            validateattributes(M, {'double','single'}, {'2d','ncols',3}, mfilename, 'colormap');
            assert(all(isfinite(M(:))), 'Colormap contains NaN/Inf: %s', this.Path);
            this.MapCache = double(M);
            M = this.MapCache;
        end
    end
end