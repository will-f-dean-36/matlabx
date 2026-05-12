classdef Images < handle
    properties
        DefaultColormap (1,:) char = 'gray'
        Interpolation   (1,:) char = 'nearest'
        ShowPixelInfo   (1,1) logical = true
    end

    methods
        function S = toStruct(obj)
            S = struct( ...
                'DefaultColormap', obj.DefaultColormap, ...
                'Interpolation', obj.Interpolation, ...
                'ShowPixelInfo', obj.ShowPixelInfo);
        end

        function fromStruct(obj,S)
            if isfield(S,'DefaultColormap')
                obj.DefaultColormap = S.DefaultColormap;
            end
            if isfield(S,'Interpolation')
                obj.Interpolation = S.Interpolation;
            end
            if isfield(S,'ShowPixelInfo')
                obj.ShowPixelInfo = S.ShowPixelInfo;
            end
        end
    end
end