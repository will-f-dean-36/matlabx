classdef Paths
%% Helper class for locating file paths

    methods(Static)
        function r = root()
            % This file lives in some_path/+guitools/Paths.m → go up once to +guitools
            r = fileparts(mfilename('fullpath'));
        end
        function p = assets(varargin)
            p = fullfile(guitools.Paths.root(), 'assets', varargin{:});
        end
        function p = icons(varargin)
            p = guitools.Paths.assets('icons', varargin{:});
        end
        function p = colormaps(varargin)
            p = guitools.Paths.assets('colormaps', varargin{:});
        end
    end

end