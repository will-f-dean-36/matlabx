classdef Logging < handle
    properties
        Level (1,:) char = 'info'
        ShowDebugOutput (1,1) logical = false
    end

    methods
        function S = toStruct(obj)
            S = struct( ...
                'Level', obj.Level, ...
                'ShowDebugOutput', obj.ShowDebugOutput);
        end

        function fromStruct(obj,S)
            if isfield(S,'Level')
                obj.Level = S.Level;
            end
            if isfield(S,'ShowDebugOutput')
                obj.ShowDebugOutput = S.ShowDebugOutput;
            end
        end
    end
end
