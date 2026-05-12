classdef MachineState
    methods (Static)

        function S = load()
            file = matlabx.internal.Paths.machineStateFile();

            if ~isfile(file)
                S = struct();
                return
            end

            txt = fileread(file);
            S = jsondecode(txt);
        end

        function save(S)
            folder = matlabx.internal.Paths.prefRoot();
            if ~isfolder(folder)
                mkdir(folder);
            end

            file = matlabx.internal.Paths.machineStateFile();
            txt = jsonencode(S, PrettyPrint=true);

            fid = fopen(file, 'w');
            cleaner = onCleanup(@() fclose(fid));
            fwrite(fid, txt, 'char');
        end

        function value = get(fieldName, defaultValue)
            arguments
                fieldName (1,:) char
                defaultValue = []
            end

            S = matlabx.config.MachineState.load();
            if isfield(S, fieldName)
                value = S.(fieldName);
            else
                value = defaultValue;
            end
        end

        function set(fieldName, value)
            arguments
                fieldName (1,:) char
                value
            end

            S = matlabx.config.MachineState.load();
            S.(fieldName) = value;
            matlabx.config.MachineState.save(S);
        end
    end
end