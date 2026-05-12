classdef (Abstract) ImageSource < handle
    %IMAGESOURCE Abstract backing source for Image5D.

    methods (Abstract)
        comps = getComponents(obj)
        tf = isLoaded(obj)
        tf = isFileBacked(obj)
        load(obj)
        unload(obj)
        I = getPlane(obj, idx, z, t)
        md = getOriginalMetadata(obj)
        md = getOMEMetadata(obj)
        md = getCoreMetadata(obj)
        md = getGraphicsFileMetadata(obj)
    end
end