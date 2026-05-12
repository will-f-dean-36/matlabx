classdef Logging < handle
    properties
        Level (1,:) char = 'info'
    end

    methods
        function S = toStruct(obj)
            S = struct('Level', obj.Level);
        end

        function fromStruct(obj,S)
            if isfield(S,'Level')
                obj.Level = S.Level;
            end
        end
    end
end