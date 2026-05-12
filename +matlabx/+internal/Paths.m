classdef Paths
%% Helper class for locating file paths

    methods(Static)

        function r = root()
            % This file lives in some_path/+matlabx/+internal/Paths.m → go up 3 times to folder containing +matlabx
            r = mfilename('fullpath');
            for i = 1:3, r = fileparts(r); end
        end


        % --- assets ---

        function p = assets(varargin)
            p = fullfile(matlabx.internal.Paths.root(), 'assets', varargin{:});
        end

        function p = icons(varargin)
            p = matlabx.internal.Paths.assets('icons', varargin{:});
        end

        function p = colormaps(varargin)
            p = matlabx.internal.Paths.assets('colormaps', varargin{:});
        end


        % --- external ---

        function p = external(varargin)
            p = fullfile(matlabx.internal.Paths.root(), 'external', varargin{:});
        end



        % --- config, settings, user prefs ---

        function p = prefRoot(varargin)
            p = fullfile(prefdir, 'matlabx', varargin{:});
        end

        function p = settingsFile()
            p = matlabx.internal.Paths.prefRoot('settings.json');
        end

        function p = machineStateFile()
            p = matlabx.internal.Paths.prefRoot('machineState.json');
        end

    end

end