classdef Settings < handle
    properties
        UI      matlabx.config.UI
        Images  matlabx.config.Images
        Logging matlabx.config.Logging
    end

    methods
        function obj = Settings()
            obj.UI = matlabx.config.UI();
            obj.Images = matlabx.config.Images();
            obj.Logging = matlabx.config.Logging();
        end

        function S = toStruct(obj)
            S.Version = "0.1.0";
            S.UI = obj.UI.toStruct();
            S.Images = obj.Images.toStruct();
            S.Logging = obj.Logging.toStruct();
        end

        function fromStruct(obj,S)
            [S,~] = matlabx.config.Settings.migrate(S);

            if isfield(S,'UI'), obj.UI.fromStruct(S.UI); end
            if isfield(S,'Images'), obj.Images.fromStruct(S.Images); end
            if isfield(S,'Logging'), obj.Logging.fromStruct(S.Logging); end
        end

        function save(obj,file)
            if nargin < 2
                file = matlabx.internal.Paths.settingsFile();
            end

            folder = fileparts(file);
            if ~isfolder(folder)
                mkdir(folder);
            end

            txt = jsonencode(obj.toStruct(), PrettyPrint=true);
            fid = fopen(file,'w');
            assert(fid > 0, 'Could not open settings file for writing.');
            c = onCleanup(@() fclose(fid));
            fwrite(fid, txt, 'char');
        end
    end

    methods (Static)
        function obj = load(file)
            if nargin < 1
                file = matlabx.internal.Paths.settingsFile();
            end

            obj = matlabx.config.Settings();

            if isfile(file)
                S = jsondecode(fileread(file));
                if ~isfield(S,'Version')
                    S.Version = "0.0.0";
                end
                obj.fromStruct(S);
            else
                obj.save(file);
            end
        end

        function [S,migrated] = migrate(S)
            migrated = false;

            if ~isfield(S,'Version')
                S.Version = "0.0.0";
                migrated = true;
            end

            % future migrations go here
        end

        function restore(file)
            if nargin < 1
                file = matlabx.internal.Paths.settingsFile();
            end
            obj = matlabx.config.Settings();
            obj.save(file);
        end
    end
end