classdef InMemoryImageSource < matlabx.image.ImageSource
    properties (Access = private)
        Components_ (1,:) matlabx.image.ImageComponent = matlabx.image.ImageComponent.empty(1,0)
        Source_ string = ""
    end

    methods
        function obj = InMemoryImageSource(components, opts)
            arguments
                components (1,:) matlabx.image.ImageComponent
                opts.Source string = ""
            end

            obj.Components_ = components;
            obj.Source_ = opts.Source;
        end

        function comps = getComponents(obj)
            comps = obj.Components_;
        end

        function tf = isLoaded(~)
            tf = true;
        end

        function tf = isFileBacked(obj)
            tf = strlength(obj.Source_) > 0;
        end

        function load(~)
            % No-op for in-memory source.
        end

        function unload(~)
            % No-op for in-memory source.
        end

        function I = getPlane(obj, idx, z, t)
            I = obj.Components_(idx).getPlane(z, t);
        end

        function md = getOriginalMetadata(~)
            md = struct();
        end
        
        function md = getOMEMetadata(~)
            md = struct();
        end

        function md = getCoreMetadata(~)
            md = struct();
        end
        
        function md = getGraphicsFileMetadata(~)
            md = struct();
        end
    end

end