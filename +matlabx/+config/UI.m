classdef UI < handle
    properties
        DefaultFontSize (1,1) double = 14
        AutoLoadCalibration (1,1) logical = true
    end

    methods
        function S = toStruct(obj)
            S = struct( ...
                'DefaultFontSize', obj.DefaultFontSize, ...
                'AutoLoadCalibration', obj.AutoLoadCalibration);
        end

        function fromStruct(obj,S)
            if isfield(S,'DefaultFontSize')
                obj.DefaultFontSize = S.DefaultFontSize;
            end
            if isfield(S,'AutoLoadCalibration')
                obj.AutoLoadCalibration = S.AutoLoadCalibration;
            end
        end
    end
end