classdef Image5D < handle
    %IMAGE5D General multi-component image container with pluggable source.
    %
    % First-pass design:
    %   - Public-facing image object
    %   - Backed by an ImageSource
    %   - Components are the primary abstraction
    %   - Channel-style wrappers are available when ComponentsAreChannels is true

    properties (Access = private)
        Source_
    end

    properties (Dependent, SetAccess = private)
        Source
        Components
        NumComponents
        IsLoaded
        IsFileBacked
        IsMemoryBacked
        MultiComponent
        MultiComponentKind
        ComponentsAreChannels
        CanMergeComponents

        Size
        SizeY
        SizeX
        SizeZ
        SizeT
        OriginalMetadata
        OMEMetadata
        CoreMetadata
        GraphicsFileMetadata

        AllMetadata
    end

    %% --- PUBLIC API ---

    % Constructor
    methods
        function obj = Image5D(source)
            arguments
                source (:,1) matlabx.image.ImageSource = matlabx.image.InMemoryImageSource.empty()
            end

            obj.Source_ = source;
        end
    end

    % Construct from different source types
    methods (Static)

        function obj = fromComponents(data, opts)
            arguments
                data
                opts.Names string = matlabx.string.empty()
                opts.Kinds string = matlabx.string.empty()
                opts.Source string = ""
            end

            if ~iscell(data)
                data = {data};
            end
    
            n = numel(data);
            if n == 0
                error('matlabx:image:Image5D:EmptyInput', 'At least one component is required.');
            end

            names = opts.Names;
            kinds = opts.Kinds;
    
            % Basic validation: numeric/logical arrays only, shared XY, shared ZT
            refSize = [];
            for k = 1:n
                A = data{k};
    
                if ~(isnumeric(A) || islogical(A))
                    error('matlabx:image:Image5D:InvalidComponentType', ...
                        'Component %d must be numeric or logical.', k);
                end
    
                stackSize = matlabx.image.Image5D.inferComponentSize_(A);
    
                if isempty(refSize)
                    refSize = stackSize;
                else
                    if ~isequal(stackSize([1,2,4,5]), refSize([1,2,4,5]))
                        error('matlabx:image:Image5D:InconsistentComponentSize', ...
                            ['All components must have matching Y, X, Z, and T size. ' ...
                             'Component 1 is [%d %d %d %d %d], component %d is [%d %d %d %d %d].'], ...
                            refSize, k, stackSize);
                    end
                end

                % populate default names and kinds if not provided
                % if numel(names) < k, names(k) = sprintf("Component %i",k); end
                if numel(names) < k, names(k) = ""; end
                if numel(kinds) < k, kinds(k) = matlabx.image.Image5D.inferComponentKind_(stackSize); end
            end

            % initialize components
            comps(1,n) = matlabx.image.ImageComponent();

            for k = 1:n
                
                stackSize = matlabx.image.Image5D.inferComponentSize_(data{k});

                nativeDisplayRange = getrangefromclass(data{k});
                dataRange = [double(min(data{k}(:))), double(max(data{k}(:)))];

                comps(k) = matlabx.image.ImageComponent( ...
                    data{k}, ...
                    Name=names(k), ...
                    Kind=kinds(k), ...
                    Class=string(class(data{k})), ...
                    Size=stackSize, ...
                    NativeDisplayRange=nativeDisplayRange, ...
                    DataRange=dataRange);
            end
    
            src = matlabx.image.InMemoryImageSource(comps, Source=opts.Source);
            obj = matlabx.image.Image5D(src);
        end

        function obj = fromFile(filePath, opts)
            arguments
                filePath {mustBeTextScalar}
                opts.SeriesIndex (1,1) double {mustBeInteger, mustBePositive} = 1
                opts.LoadOnCreate (1,1) logical = false
            end

            src = matlabx.image.BioFormatsImageSource(string(filePath), SeriesIndex=opts.SeriesIndex);

            if opts.LoadOnCreate
                src.load();
            end

            obj = matlabx.image.Image5D(src);
        end

        function obj = fromFileDialog(opts)
            arguments
                opts.SeriesIndex (1,1) double {mustBeInteger, mustBePositive} = 1
                opts.LoadOnCreate (1,1) logical = false
            end

            [file,location,~] = matlabx.image.io.uigetimagefile();
            filePath = fullfile(location,file);

            src = matlabx.image.BioFormatsImageSource(string(filePath), SeriesIndex=opts.SeriesIndex);

            if opts.LoadOnCreate
                src.load();
            end

            obj = matlabx.image.Image5D(src);
        end

    end

    % Derived getters
    methods

        function src = get.Source(obj), src = obj.Source_; end

        function comps = get.Components(obj), comps = obj.Source_.getComponents(); end

        function n = get.NumComponents(obj), n = numel(obj.Components); end

        function tf = get.IsLoaded(obj), tf = obj.Source_.isLoaded(); end

        function tf = get.IsFileBacked(obj), tf = obj.Source_.isFileBacked(); end

        function tf = get.IsMemoryBacked(obj), tf = ~obj.IsFileBacked; end

        function tf = get.ComponentsAreChannels(obj)
            tf = false;

            if obj.NumComponents == 0, return; end

            for cN = obj.Components
                if ~cN.IsScalar || ~isequal(cN.Size, obj.Components(1).Size) || ~strcmp(cN.Class, obj.Components(1).Class)
                    return
                end
            end
            tf = true;
        end

        function tf = get.MultiComponent(obj)
            tf = obj.NumComponents > 1;
        end

        function kind = get.MultiComponentKind(obj)
            if ~obj.MultiComponent
                kind = "none"; 
                return
            end
            if isequal(obj.Components(:).Kind)
                kind = obj.Components(1).Kind;
            else
                kind = "mixed";
            end
        end

        function tf = get.CanMergeComponents(obj)
            tf = obj.MultiComponent && obj.ComponentsAreChannels;
        end

        function  sz = get.Size(obj)
            s = obj.Components(1).Size;
            Y = s(1);
            X = s(2);
            C = obj.NumComponents;
            Z = s(4);
            T = s(5);
            sz = [Y X C Z T];
        end

        function y = get.SizeY(obj)
            [y, ~, ~, ~] = obj.getSharedSize_();
        end

        function x = get.SizeX(obj)
            [~, x, ~, ~] = obj.getSharedSize_();
        end

        function z = get.SizeZ(obj)
            [~, ~, z, ~] = obj.getSharedSize_();
        end

        function t = get.SizeT(obj)
            [~, ~, ~, t] = obj.getSharedSize_();
        end

        function md = get.OriginalMetadata(obj)
            md = obj.Source_.getOriginalMetadata();
        end
        
        function md = get.OMEMetadata(obj)
            md = obj.Source_.getOMEMetadata();
        end

        function md = get.CoreMetadata(obj)
            md = obj.Source_.getCoreMetadata();
        end
        
        function md = get.GraphicsFileMetadata(obj)
            md = obj.Source_.getGraphicsFileMetadata();
        end

        function md = get.AllMetadata(obj)
            md = struct(...
                'Original',[],...
                'OME',[],...
                'Core',[],...
                'GraphicsFile',[]);
            md.Original = obj.OriginalMetadata;
            md.OME = obj.OMEMetadata;
            md.Core = obj.CoreMetadata;
            md.GraphicsFile = obj.GraphicsFileMetadata;
        end


    end

    % Public API: Retrieve channel info
    methods

        function val = getComponentSize(obj,idx)
            val = obj.Components(idx).Size;
        end

        function val = getComponentKind(obj,idx)
            val = obj.Components(idx).Kind;
        end

        function val = getComponentClass(obj,idx)
            val = obj.Components(idx).Class;
        end

        function val = getComponentNativeDisplayRange(obj,idx)
            val = obj.Components(idx).NativeDisplayRange;
        end

        function val = getComponentDataRange(obj,idx)
            val = obj.Components(idx).DataRange;
        end

        function val = getComponentName(obj,idx)
            val = obj.Components(idx).Name;
        end

    end

    % Public API: load/unload, get plane, get components, set data
    methods

        function load(obj)
            obj.Source_.load();
        end

        function unload(obj)
            obj.Source_.unload();
        end

        function comp = getComponent(obj, idx)
            obj.validateComponentIndex_(idx);
            comp = obj.Components(idx);
        end

        function I = getPlane(obj, idx, z, t)
            arguments
                obj
                idx (1,1) double {mustBeInteger, mustBePositive}
                z   (1,1) double {mustBeInteger, mustBePositive} = 1
                t   (1,1) double {mustBeInteger, mustBePositive} = 1
            end

            obj.validateComponentIndex_(idx);
            I = obj.Source_.getPlane(idx, z, t);
        end

        function comp = getChannel(obj, idx)
            obj.mustHaveChannelComponents_();
            obj.validateComponentIndex_(idx);
            comp = obj.Components(idx);
        end

        function setChannelName(obj, idx, name)
            arguments
                obj
                idx (1,1) double {mustBeInteger, mustBePositive}
                name {mustBeTextScalar}
            end

            obj.mustHaveChannelComponents_();
            obj.validateComponentIndex_(idx);
            obj.Components(idx).Name = string(name);
        end

    end

    %% Public API: Other actions
    methods

        function view(obj)
            %matlabx.app.quickshow(obj);

            matlabx.app.Viewer5D(obj);
        end




    end

    %% --- PRIVATE API ---

    % Helpers
    methods (Access = private)
        function validateComponentIndex_(obj, idx)
            if idx > obj.NumComponents
                error('Image5D:IndexOutOfRange', ...
                    'Component index %d exceeds NumComponents (%d).', ...
                    idx, obj.NumComponents);
            end
        end

        function mustHaveChannelComponents_(obj)
            if ~obj.ComponentsAreChannels
                error('Image5D:NotChannelCompatible', ...
                    'This Image5D object does not contain channel-compatible components.');
            end
        end

        function [Y, X, Z, T] = getSharedSize_(obj)
            comps = obj.Components;

            if isempty(comps)
                Y = 0; X = 0; Z = 0; T = 0;
                return
            end

            s = comps(1).Size;
            Y = s(1);
            X = s(2);
            Z = s(4);
            T = s(5);
        end
    end

    % Static helpers
    methods (Static, Access = private)

        function out = inferComponentKind_(sz)
            if sz(3) == 1
                out = "scalar";
                return
            end
            if sz(3) == 3
                out = "rgb";
                return
            end
            error('matlabx:image:Image5D:InvalidComponentSize', ...
                'Component must have size [Y X 1 Z T] (scalar) or [Y X 3 Z T] (truecolor).');
        end

        function out = expandTextOpt_(value, n, defaultBase)
            if isempty(value)
                out = strings(1, n);
                for k = 1:n
                    out(k) = defaultBase + k;
                end
                return
            end

            if isstring(value) || ischar(value) || iscellstr(value)
                value = string(value);
            end

            if isscalar(value)
                out = repmat(value, 1, n);
                return
            end

            if isstring(value) && numel(value) == n
                out = reshape(value, 1, []);
                return
            end

            error('Image5D:InvalidOptionSize', ...
                'Option must be scalar text or have one entry per component.');

        end

        function sz = inferComponentSize_(A)
            sz = size(A, 1:5);
            % if numel(sz) < 5
            %     sz = [sz, ones(1, 5-numel(sz))];
            % end
        end

    end

end