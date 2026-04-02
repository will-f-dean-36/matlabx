classdef ImageAxes < matlab.ui.componentcontainer.ComponentContainer
%%IMAGEAXES  Dedicated image viewer with custom tool hosting and figure-level event routing via FigureEventHub
%
%
%
%   Notes:
%
%   Make sure CData argument comes before CLim when calling the constructor
%
%   If you use multiple instances of ImageAxes in the same figure window, 
%   make sure the Name property of each is unique
%
%



    %% Tool Management

    properties (SetAccess=?matlabx.ui.widgets.ImageAxesTool)
        % struct() of installed tools, fieldnames match tool Name
        Tools struct = struct()
    end

    properties (Dependent)
        % the set of tools to INSTALL (tools which are listed in the toolbar)
        ToolBelt
        % the set of tools to LOAD (tools which are available for install)
        ToolBox
    end

    properties (Access=private)
        % registry of loaded tools
        ToolList        % containers.Map name->tool
        % registry of installed tools
        ToolRegistry    % containers.Map name->tool
    end

    properties (Access=?matlabx.ui.widgets.ImageAxesTool)
        % the currently enabled tool with IsExclusive=true (if it exists)
        ActiveExclusiveTool
        % struct() of ToolbarButtons, fieldnames match tool Name
        ToolbarButtons struct = struct()
    end

    %% Public Parameters
    properties (AbortSet)
        Name (1,1) string = ""
    end

    % Passthroughs
    properties (Dependent)
        ImageVisible
        AxesVisible
        ColorbarVisible
        Colormap (256,3) double
        MaxRenderedResolution
    end

    %% CData management

    properties (Dependent, AbortSet)
        CLim                (1,2) double
        CanMerge            (1,1) logical
    
        CData               {mustBeA(CData,{'double','single','uint8','uint16','logical','cell'})}
        CLimMode            (1,:) char
        ChannelIdx          (1,1) double
        ShowComposite       (1,1) matlab.lang.OnOffSwitchState
        ChannelColors       (1,:) cell
        ChannelColormaps    (1,:) cell
        ChannelColorMode    (1,:) char {mustBeMember(ChannelColorMode,{'colors','luts'})}
    end

    properties (Dependent)
        ImageData
    end

    % read-only
    properties (Dependent, SetAccess=private)
        DisplayCData
        CDataType       (1,:) char {mustBeMember(CDataType,{'grayscale','rgb'})}
        CDataSize       (1,:) double
        CDataClass      (1,:) char {mustBeMember(CDataClass,{'double','single','uint8','uint16','logical',''})}
        
        nChannels           (1,1) double
        MultiChannel        (1,1) matlab.lang.OnOffSwitchState
        MultiChannelType    (1,:) {mustBeMember(MultiChannelType,{'grayscale','rgb','mixed','none'})}
    end

    properties (Access=private)
        % small internal view state
        ViewState_ struct = struct( ...
            'ChannelIdx', 1, ...
            'ShowComposite', false, ...
            'CLimMode', 'auto', ...
            'ChannelColorMode', 'colors');
        % image data structure
        ImageData_ (1,1) matlabx.image.ImageData = matlabx.image.ImageData(zeros(256,256,3))
        % currently rendered source image (active channel or computed composite)
        RenderSource_ (:,:,:) = matlabx.ui.widgets.ImageAxes.placeholderImage
        % per-channel display state
        ChannelDisplay_ (1,:) struct = struct( ...
            'CLim', {}, ...
            'ColorName', {}, ...
            'Colormap', {}, ...
            'DisplayMap', {})
    end

    %% UI/Graphics

    % private
    properties (Access=private, Transient, NonCopyable)
        Grid matlab.ui.container.GridLayout
        Panel matlab.ui.container.Panel
        staticAxes matlab.ui.control.UIAxes
        hImage matlab.graphics.primitive.Image
        L event.listener
        TopLabel (1,1) matlab.graphics.primitive.Text
        BottomLabel (1,1) matlab.graphics.primitive.Text
        Colorbar matlab.graphics.illustration.ColorBar
    end

    % tool-accessible
    properties (Access=?matlabx.ui.widgets.ImageAxesTool)
        mainAxes matlab.ui.control.UIAxes
    end

    %% Popup/temporary UI management

    % popup windows
    properties (Access=private, Transient, NonCopyable)
        contrastTool (:,1) matlabx.app.SliderDialog
    end

    properties
        contrastToolOpen (1,1) logical = false
    end

    %% Derived properties (accessible to tools)
    properties (Access=?matlabx.ui.widgets.ImageAxesTool, Dependent)
        ParentFig
        ImageSize
        ImageWidth
        ImageHeight
        defaultXLim
        defaultYLim
        cursorPosition
        cursorPositionStatic
        activePixel
    end

    %% Tool helper variables
    properties (Access=?matlabx.ui.widgets.ImageAxesTool)
        % control XLim and YLim of axes holding the image (if empty, lims will be set to default)
        XLim = []
        YLim = []
    end

    %% Modes for routing
    properties (SetAccess=private)
        Mode struct = struct()
    end

    %% Hub registration
    properties (Access=private)
        Hub matlabx.ui.control.FigureEventHub
        RouterId double = NaN
    end

    %% Events
    events (NotifyAccess=protected)
        CDataChanged
    end

    %% ComponentContainer lifecycle (setup/update)
    methods (Access=protected)

        function setup(obj)

            obj.Interruptible = 'off';
            obj.BusyAction = 'cancel';

            % Main grid
            obj.Grid = uigridlayout(obj,[1,1], ...
                'RowHeight',{'1x'},...
                'ColumnWidth',{'1x'},...
                'RowSpacing',0,...
                'ColumnSpacing',0,...
                'Padding',[0 0 0 0], ...
                'BackgroundColor',[1 1 1]);

            % Panel to hold the axes
            obj.Panel = uipanel(obj.Grid, ...
                'BackgroundColor',[0 0 0],...
                'AutoResizeChildren','off',...
                'BorderWidth',0);

            % Main axes
            obj.mainAxes = uiaxes(obj.Panel, ...
                'Units','normalized', ...
                'InnerPosition',[0 0 1 1], ...
                'YDir','reverse', ...
                'YLim',[0 1], ...
                'XLim',[0 1], ...
                'XTick',[], ...
                'YTick',[], ...
                'Color',[0 0 1], ...
                'XColor','none', ...
                'YColor','none', ...
                'Visible','off', ...
                'PositionConstraint','innerposition', ...
                'NextPlot','add', ...
                'HitTest','on', ...
                'PickableParts','all');
            obj.mainAxes.Toolbar = axtoolbar(obj.mainAxes,{});
            obj.mainAxes.Interactions = [];
            disableDefaultInteractivity(obj.mainAxes);

            % Static axes (used for cursor-follow zoom math)
            obj.staticAxes = uiaxes(obj.Panel, ...
                'Units','normalized', ...
                'InnerPosition',[0 0 1 1], ...
                'YDir','reverse', ...
                'YLim',[0 1], ...
                'XLim',[0 1], ...
                'XTick',[], ...
                'YTick',[], ...
                'Color',[0 0 1], ...
                'XColor','none', ...
                'YColor','none', ...
                'Visible','off', ...
                'PositionConstraint','innerposition', ...
                'HitTest','off', ...
                'PickableParts','none');
            obj.staticAxes.Toolbar = axtoolbar(obj.staticAxes,{});
            obj.staticAxes.Interactions = [];
            disableDefaultInteractivity(obj.staticAxes);
            obj.staticAxes.PlotBoxAspectRatio = [1 1 1];
            obj.staticAxes.DataAspectRatio = [1 1 1];

            % setup and store colorbar
            obj.Colorbar = colorbar(obj.mainAxes,"east","Visible","off");

            % initialize registries for loaded and installed tools
            obj.ToolList = containers.Map('KeyType','char','ValueType','any');
            obj.ToolRegistry = containers.Map('KeyType','char','ValueType','any');

            % load all tools in obj.ToolBox
            obj.loadTools(obj.ToolBox);
            % install all tools in obj.ToolBelt
            obj.installTools(obj.ToolBelt);

            % Hub registration (one hub per figure; this instance registers itself)
            obj.Hub = matlabx.ui.control.FigureEventHub.ensure(obj.ParentFig);
            obj.RouterId = obj.Hub.register(obj,'Priority',10,'CaptureDuringDrag',true);

            % Image
            obj.hImage = image(obj.mainAxes,[],...
                'CDataMapping','scaled',...
                'HitTest','off',...
                'PickableParts','none');

            % Update CLim, PlotBoxAspectRatio, and DataAspectRatio *after* creating image object
            obj.mainAxes.CLim               = [0 1];
            obj.mainAxes.PlotBoxAspectRatio = [1 1 1];
            obj.mainAxes.DataAspectRatio    = [1 1 1];

            % set SizeChangedFcn so we can force visual update upon resizing (AutoResizeChildren of parent must be Off)
            obj.SizeChangedFcn = @(~,~) obj.updateOnResize();

            % label in bottom-left corner
            obj.BottomLabel = text('Parent',obj.staticAxes,...
                'Units','normalized',...
                'Position',[0.005 0.005],...
                'Color',[1 1 1],...
                'BackgroundColor',[0 0 0 0.5],...
                'String','',...
                'Clipping','on',...
                'Margin',3,...
                'HorizontalAlignment','left',...
                'VerticalAlignment','bottom');

            % label in top-left corner
            obj.TopLabel = text('Parent',obj.staticAxes,...
                'Units','normalized',...
                'Position',[0.005 0.995],...
                'Color',[1 1 1],...
                'BackgroundColor',[0 0 0 0.5],...
                'String','',...
                'Clipping','on',...
                'Margin',3,...
                'HorizontalAlignment','left',...
                'VerticalAlignment','top');

            % set default colormap
            obj.Colormap = gray;

            % initialize display state from ImageData
            obj.syncViewStateToImageData();
            
            % initial render
            obj.syncRenderSourceToView();
        end

        function update(obj)
            % set the Tag property of the mainAxes
            obj.mainAxes.Tag = obj.Name;

            % set BackgroundColor
            obj.Grid.BackgroundColor = obj.BackgroundColor;
            obj.Panel.BackgroundColor = obj.BackgroundColor;
        end

    end

    methods (Access=private)
        function tf = isNonEmptyText(~, x)
            tf = (ischar(x) || (isstring(x) && isscalar(x))) && strlength(string(x)) > 0;
        end
    end


    %% Internal update helpers
    methods (Access=private)

        function updateOnResize(obj)
            if ~isvalid(obj); return; end
            drawnow;  % keep label positioning accurate during live resizes
            obj.update();
        end

        function updateBottomLabelText(obj)
        
            px = obj.activePixel;
        
            if isempty(px), obj.BottomLabel.String ='Hover over image to interact'; return; end
        
            posStr = sprintf('Pixel: (%0.f,%0.f)',px(1),px(2));
        
            if obj.ViewState_.ShowComposite
                activeData = obj.ImageData_.getChannelData(obj.ViewState_.ChannelIdx);
                activeType = obj.ImageData_.getChannelType(obj.ViewState_.ChannelIdx);
                activeClass = obj.ImageData_.getChannelClass(obj.ViewState_.ChannelIdx);
            else
                activeData = obj.CData;
                activeType = obj.CDataType;
                activeClass = obj.CDataClass;
            end
        
            switch activeType
                case 'grayscale'
                    switch activeClass
                        case {'double','single'}
                            valStr = sprintf('Intensity: %0.2f', activeData(px(2),px(1)));
                        case {'uint8','uint16'}
                            valStr = sprintf('Intensity: %i', activeData(px(2),px(1)));
                        case 'logical'
                            valStr = sprintf('Value: %i', activeData(px(2),px(1)));
                        otherwise
                            valStr = '';
                    end
                case 'rgb'
                    switch activeClass
                        case {'double','single'}
                            valStr = sprintf('RGB: [%0.2f, %0.2f, %0.2f]', activeData(px(2),px(1),1:3));
                        case {'uint8','uint16'}
                            valStr = sprintf('RGB: [%i, %i, %i]', activeData(px(2),px(1),1:3));
                        otherwise
                            valStr = '';
                    end
                otherwise
                    valStr = '';
            end
        
            tools = obj.prioritySortTools(obj.ToolRegistry);
            txt = cell(1,numel(tools));
        
            for i = 1:numel(tools)
                txt{i} = tools{i}.getLabelString();
            end
        
            txt = [posStr, valStr, txt];
            txt(ismember(txt,'')) = [];
            txt = strjoin(txt,' | ');
        
            obj.BottomLabel.String = [' ',txt];
        end


        function updateTopLabelText(obj)

            %infoStr = obj.getImageInfoString();

            sizeStr = obj.getImageSizeString();
            bitDepthStr = obj.getImageBitDepthString();
            channelStr = obj.getChannelInfoStr();

            txt = {sizeStr,bitDepthStr,channelStr};

            % join each fragment with spaced pipe
            txt = strjoin(txt,' | ');

            obj.TopLabel.String = [' ',txt];
        end

        function updatePointer(obj)

            % invalid pixel, set pointer to 'arrow'
            if isempty(obj.activePixel), obj.ParentFig.Pointer = 'arrow'; return; end

            % get cell array of installed tools, sorted by priority
            tools = obj.prioritySortTools(obj.ToolRegistry);

            % no tools found, set pointer to 'arrow'
            if isempty(tools), obj.ParentFig.Pointer = 'arrow'; return; end

            for i = 1:numel(tools)
                pointer = tools{i}.getPreferredPointer();

                if isempty(pointer)
                    continue
                end

                switch pointer
                    case 'default'
                        % do nothing (let the pointer be set normally)
                        return
                    otherwise
                        % a valid pointer is returned, set it and return
                        obj.ParentFig.Pointer = pointer;
                        return
                end

            end

            % no valid pointer was returned, set pointer to 'arrow'
            obj.ParentFig.Pointer = 'arrow';

        end

        function updateImageCData(obj)
            obj.hImage.CData = obj.DisplayCData;
        end

        function updateColorbar(obj)
            ticks = {};
            labels = {};

            idx = obj.ViewState_.ChannelIdx;
            ch = obj.ImageData_.getChannel(idx);
            clim = obj.ChannelDisplay_(idx).CLim;

            if strcmp(ch.Type, 'grayscale') && ~islogical(ch.Data) && ~isempty(clim)
                [ticks, labels] = matlabx.ui.widgets.ImageAxes.getColorbarTickLabels( ...
                    ch.Class, clim);
            end

            obj.Colorbar.Ticks = ticks;
            obj.Colorbar.TickLabels = labels;
        end

        function updateAxesColormap(obj)
            obj.mainAxes.Colormap = obj.ChannelDisplay_(obj.ViewState_.ChannelIdx).DisplayMap;
        end

        function refreshView(obj)
            % update the CData of the Image
            obj.updateImageCData();
            % update the Colormap of the Axes
            obj.updateAxesColormap();
            % update the Colorbar
            obj.updateColorbar();
            % update axes limits
            obj.restoreDefaultLimits();
            % update image info label
            obj.updateTopLabelText();
        end

    end

    %% Internal display helpers
    methods (Access=private)

        function s = getImageInfoString(obj)

            s1 = sprintf(strjoin(repmat({'%i'},1,numel(obj.CDataSize)),'x'),obj.CDataSize);
            s2 = sprintf('%s (%s)',obj.CDataClass,obj.CDataType);

            s = [s1,' ',s2];
        end

        function s = getChannelInfoStr(obj)
            idx = obj.ViewState_.ChannelIdx;
            nm = obj.ImageData_.getChannelName(idx);
        
            if strlength(nm) > 0
                base = sprintf('C: %i/%i (%s)', idx, obj.nChannels, char(nm));
            else
                base = sprintf('C: %i/%i', idx, obj.nChannels);
            end
        
            if obj.ViewState_.ShowComposite
                s = [base, ' (composite)'];
            else
                s = base;
            end
        end

        function s = getImageSizeString(obj)
            s = sprintf(strjoin(repmat({'%i'},1,numel(obj.CDataSize)),'x'),obj.CDataSize);
        end

        function s = getImageBitDepthString(obj)
            switch obj.CDataClass
                case {'uint8','logical'}
                    s = '8-bit';
                case 'uint16'
                    s = '16-bit';
                case 'single'
                    s = '32-bit';
                case 'double'
                    s = '64-bit';
            end
        end


    end

    %% Tool-accessible helpers
    methods (Access=?matlabx.ui.widgets.ImageAxesTool, Hidden=true)
        
        function setMode(obj, modeName, modeState)
            % if mode does not exist
            if ~isfield(obj.Mode,modeName)
                % warn and return
                warning('Could not set mode state. "%s" mode does not exist.',modeName)
                return
            end
            % set the mode state
            obj.Mode.(modeName) = logical(modeState);
        end

        function addMode(obj, modeName)
            % if mode already exists
            if isfield(obj.Mode,modeName)
                % warn and return
                warning('Could not add mode. "%s" mode already exists',modeName)
                return
            end
            % add the mode (false by default)
            obj.Mode.(modeName) = false;
        end

        function removeMode(obj, modeName)
            % if mode does not exist
            if ~isfield(obj.Mode,modeName)
                % warn and return
                warning('Could not remove mode. "%s" mode does not exist.',modeName)
                return
            end
            % remove the mode
            obj.Mode = rmfield(obj.Mode,modeName);
        end

        function updateFromTool(obj)
            obj.updateBottomLabelText();
            obj.updatePointer();
        end

        function restoreDefaultLimits(obj)
            obj.staticAxes.XLim = obj.defaultXLim;  
            obj.staticAxes.YLim = obj.defaultYLim;
            obj.mainAxes.XLim = obj.defaultXLim;  
            obj.mainAxes.YLim = obj.defaultYLim;
        end

    end

    %% Derived getters and setters
    methods

        % cursor position in axes/image
        function cursorPosition = get.cursorPosition(obj)
            cursorPosition = obj.mainAxes.CurrentPoint(1,[1,2]);
            % return empty if outside limits
            if ~obj.isInLimits(cursorPosition,obj.mainAxes.XLim,obj.mainAxes.YLim)
                cursorPosition = [];
            end
        end

        function cursorPositionStatic = get.cursorPositionStatic(obj)
            cursorPositionStatic = obj.staticAxes.CurrentPoint(1,[1,2]);
            % return empty if outside limits
            if ~obj.isInLimits(cursorPositionStatic,obj.staticAxes.XLim,obj.staticAxes.YLim)
                cursorPositionStatic = [];
            end
        end

        function px = get.activePixel(obj)
            % cursor position in axes
            XY = obj.cursorPosition;
            % empty -> return
            if isempty(XY), px = []; return, end
            % round to integer px indices, clip to image dimensions
            px = [clip(round(XY(1)),1,obj.ImageWidth), clip(round(XY(2)),1,obj.ImageHeight)];
        end

        % image dimensions
        function s = get.ImageSize(obj),    s = obj.CDataSize;    end
        function h = get.ImageHeight(obj),  h = obj.ImageSize(1); end
        function w = get.ImageWidth(obj),   w = obj.ImageSize(2); end


        
        % default axes limits (set to prefectly enclose image)
        function x = get.defaultXLim(obj),  x = [0 obj.ImageWidth] + 0.5; end
        function y = get.defaultYLim(obj),  y = [0 obj.ImageHeight] + 0.5; end

        % retrieve fig/axes handles
        function f = get.ParentFig(obj),    f = ancestor(obj,'Figure'); end
        function ax = getAxes(obj),         ax = obj.mainAxes; end
        function ax = getOverlayAxes(obj),  ax = obj.staticAxes; end

        % axes/image passthroughs (Set/Get)

        % ImageVisible
        function v = get.ImageVisible(obj),v = obj.hImage.Visible; end
        function set.ImageVisible(obj,val),obj.hImage.Visible = val; end
        % AxesVisible
        function v = get.AxesVisible(obj), v = obj.mainAxes.Visible; end
        function set.AxesVisible(obj,val), obj.mainAxes.Visible = val; end
        % ColorbarVisible
        function v = get.ColorbarVisible(obj), v = obj.Colorbar.Visible; end
        function set.ColorbarVisible(obj,val), obj.Colorbar.Visible = val; end
        % MaxRenderedResolution
        function v = get.MaxRenderedResolution(obj), v = obj.hImage.MaxRenderedResolution; end
        function set.MaxRenderedResolution(obj,val), obj.hImage.MaxRenderedResolution = val; end


    end

    %% Hub-facing event handlers (matches | onDown | onMove | onUp | onScroll | onKeyPress | onEnter | onLeave)
    methods

        % determine whether this instance should claim event from FigureEventHub
        function tf = matches(obj, E)
            % E.Target: hittest result from FigureEventHub that we are checking for a match to this component
            % E.Kind: the specific kind of mouse event (i.e. 'Move', 'Down', 'Up', 'Scroll', or 'Key')
            % E.RawEvent: event data associated with the event

            % true if child of UIAxes in this ImageAxes
            tf = obj.isChild(E.Target) && obj.isAxesChild(E.Target);

            if tf && obj.isToolbarButtonChild(E.Target)
                tf = strcmp(E.Kind,'Move');
            end
        end

        function onDown(obj, E)
            obj.routeEventToTools(E);
        end

        function onMove(obj, E)
            % get the ancestor toolbar button clicked, if it exists
            % look for "state" buttons first
            btn = ancestor(E.Target,'matlab.ui.controls.ToolbarStateButton');
            % none found -> look for "push" buttons
            if isempty(btn)
                btn = ancestor(E.Target,'matlab.ui.controls.ToolbarPushButton');
            end

            % button exists
            if ~isempty(btn)
                % set image info label to display button tooltip, return
                obj.BottomLabel.String = sprintf(' %s',btn.Tooltip); return
            end

            obj.routeEventToTools(E);

            % Host maintenance (update label/pointer/etc. on move if desired)
            obj.onMouseMove();
        end

        function onUp(obj, E)
            obj.routeEventToTools(E);
        end

        function onScroll(obj, E)
            obj.routeEventToTools(E);
        end

        function onKey(obj, E)
            obj.routeEventToTools(E);

            switch E.Hotkey
                case 'shift+meta+c'
                    obj.openContrastTool();
                case 'rightarrow'
                    obj.nextChannel();
                case 'leftarrow'
                    obj.previousChannel();
                case {'uparrow','downarrow'}
                    obj.toggleComposite();
            end
        end

        function onEnter(obj,~)
            obj.BottomLabel.Visible = "on";
            % no-op to tools by default
        end

        function onLeave(obj,~)
            % hide label
            obj.BottomLabel.Visible = "off";
            % reset pointer to arrow
            if isvalid(obj.ParentFig)
                obj.ParentFig.Pointer = 'arrow';
            end
        end

    end

    %% Private Hub helpers
    methods (Access=private)

        function tf = isChild(obj,h)
            % true if h is child of this ImageAxes
            ia = ancestor(h,'matlabx.ui.widgets.ImageAxes');

            if isempty(ia)
                tf = false;
            else
                tf = ia == obj;
            end
        end

        function tf = isAxesChild(obj,h)
            % true if h is child of UIAxes belonging to this ImageAxes
            ax = ancestor(h,'matlab.ui.control.UIAxes');
            tf = ~isempty(ax) && strcmp(ax.Tag,obj.Name);
        end

        function tf = isToolbarButtonChild(~,h)
            % true if h is child of ToolbarStateButton or ToolbarPushButton (in any axes)
            % btn = ancestor(h,'matlab.ui.controls.ToolbarStateButton');
            % if isempty(btn)
            %     btn = ancestor(h,'matlab.ui.controls.ToolbarPushButton');
            % end

            tf = ~isempty(ancestor(h,'matlab.ui.controls.ToolbarStateButton')) || ...
                ~isempty(ancestor(h,'matlab.ui.controls.ToolbarPushButton'));
        end


    end

    %% Internal behaviors
    methods (Access=private)

        % executes on mouse move after Distractors/Interceptors
        function onMouseMove(obj)
            obj.updateBottomLabelText();
            obj.updatePointer();
        end

    end

    %% Tool event routing
    methods

        function routeEventToTools(obj,E)
            skipInterceptor = obj.routeToDistractors(E);
            if skipInterceptor, return; end

            % get highest priority Interceptor for event kind
            t = obj.getPriorityInterceptor(E.Kind);
            % forward event to the tool
            if ~isempty(t), t.("on"+E.Kind)(E); end
        end

        function tf = routeToDistractors(obj,E)
            % cell array of Distractors for this eventType, sorted by Priority
            distractors = obj.getPriorityDistractors(E.Kind);

            % whether to bypass the active Interceptor after Distraction event
            tf = false;

            % no Distractors for this eventType, return early
            if isempty(distractors), return; end

            for i = 1:numel(distractors)
                tf = distractors{i}.("onDistract"+E.Kind)(E) | tf;
            end

        end

    end

    %% Tool management (register/unregister, load/unload, install/uninstall)
    methods

        % register a tool (add it to the installed tool registry) - tools call this themselves
        function registerTool(obj, tool)
            if ~isvalid(tool)
                warning('Failed to register tool. Invalid handle.')
                return
            end

            % add toolbar button
            obj.addToolbarButton(tool);
            % add to installed tools struct
            obj.Tools.(tool.Name) = tool;

            % add to registry
            obj.ToolRegistry(char(tool.Name)) = tool;
        end

        % remove tool from installed tool registry - it remains loaded
        function unregisterTool(obj, tool)
            % if tool is not registered
            if ~obj.ToolRegistry.isKey(char(tool.Name))
                warning('Failed to unregister tool. "%s" tool is not currently registered.',tool.Name)
                return
            end

            % remove toolbar button
            obj.removeToolbarButton(tool);
            % remove from installed tools struct
            obj.Tools = rmfield(obj.Tools,tool.Name);

            % remove from registry
            obj.ToolRegistry.remove(char(tool.Name));
        end

        % load all tools in matlabx.ui.widgets.tools
        function loadAllTools(obj)
            % cell array of tool names
            toolNames = obj.getToolNames();
            % return if no tools found
            if isempty(toolNames), return; end
            % load each tool
            for i = 1:numel(toolNames), obj.loadTool(toolNames{i}); end
        end

        % unload all currently loaded tools
        function unloadAllTools(obj)
            % cell array of tool names
            toolNames = obj.ToolList.keys;
            % return if no tools are currently loaded
            if isempty(toolNames), return; end
            % unload each tool
            for i = 1:numel(toolNames), obj.unloadTool(toolNames{i}); end
        end

        % load tools specified by toolNames (cell array of char vectors)
        function loadTools(obj,toolNames)
            % return if no tools found
            if isempty(toolNames), return; end
            % load each tool
            for i = 1:numel(toolNames), obj.loadTool(toolNames{i}); end
        end

        % load tool specified by name
        function loadTool(obj, name)
            if obj.ToolList.isKey(char(name))
                warning('Failed to load tool. "%s" tool already loaded.',name)
                return
            end
            % add to loaded Tools registry
            obj.ToolList(char(name)) = matlabx.ui.widgets.tools.(char(name))(obj);
        end

        % unload tool specified by name
        function unloadTool(obj, name)
            if ~obj.ToolList.isKey(char(name))
                warning('Failed to unload tool. "%s" tool is not loaded.',name)
                return
            end
            % get from loaded tools registry
            tool = obj.getLoadedTool(name);
            % if tool is installed, uninstall before unloading
            if tool.Installed, obj.uninstallTool(tool.Name); end

            % delete the tool (it will perform teardown tasks)
            delete(tool)
            % remove from loaded Tools registry
            obj.ToolList.remove(char(name));
        end

        % install tools specified by toolNames (cell array of char vectors)
        function installTools(obj,toolNames)
            % return if empty
            if isempty(toolNames), return; end
            % install each tool
            for i = 1:numel(toolNames), obj.installTool(toolNames{i}); end
        end

        % install tool specified by name
        function installTool(obj,name)
            thisTool = obj.getLoadedTool(name);
            % if no tool with this name found in tool list
            if isempty(thisTool)
                warning('Failed to install tool. "%s" tool is not loaded.',name)
                return
            end
            % check if tool is already registered
            if obj.ToolRegistry.isKey(char(thisTool.Name))
                warning('Failed to install tool. "%s" tool is already installed.',name)
                return
            end
            % call the tool's install() method, it will register itself and perform startup tasks
            thisTool.install();
        end

        % uninstall tool specified by name
        function uninstallTool(obj,name)
            thisTool = obj.getLoadedTool(name);
            % if no tool with this name found in tool list
            if isempty(thisTool)
                warning('Failed to uninstall tool. "%s" tool is not loaded.',name)
                return
            end
            % if no tool with this name is currently installed
            if ~obj.ToolRegistry.isKey(char(thisTool.Name))
                warning('Failed to uninstall tool. "%s" tool is already uninstalled.',name)
                return
            end
            % call the tool's uninstall() method, it will remove itself from the registry and perform cleanup tasks
            thisTool.uninstall();
        end

    end

    %% Toolbar management (add, remove, reorder toolbar buttons)
    methods

        % add a toolbar button for the tool (tool calls this on install)
        function addToolbarButton(obj, tool)
            % obj.ToolbarButtons.(tool.Name) = axtoolbarbtn(obj.mainAxes.Toolbar,'state',...
            %     'Tooltip',tool.Tooltip,...
            %     'Icon',tool.Icon,...
            %     'ValueChangedFcn',@(btn,~) onToolToggle(obj, btn.Value, tool.Name));

            switch tool.Style
                case 'push'
                    obj.ToolbarButtons.(tool.Name) = axtoolbarbtn(obj.mainAxes.Toolbar,'push',...
                        'Tooltip',tool.Tooltip,...
                        'Icon',tool.Icon,...
                        'ButtonPushedFcn',@(btn,~) onToolPush(obj, tool.Name));
                case 'state'
                    obj.ToolbarButtons.(tool.Name) = axtoolbarbtn(obj.mainAxes.Toolbar,'state',...
                        'Tooltip',tool.Tooltip,...
                        'Icon',tool.Icon,...
                        'ValueChangedFcn',@(btn,~) onToolToggle(obj, btn.Value, tool.Name));
            end

            % reset the toolbar (it will disappear on hover otherwise)
            obj.mainAxes.Toolbar.reset;
        end

        % add a toolbar button for the tool (tool calls this on uninstall)
        function removeToolbarButton(obj, tool)
            % tool name not found in obj.ToolbarButtons struct, exit early
            if ~isfield(obj.ToolbarButtons,tool.Name), return; end
            % toolbar button linked to this tool
            tbButton = obj.ToolbarButtons.(tool.Name);
            % button is not valid, exit early
            if ~isvalid(tbButton), return; end
            % delete the toolbar button
            delete(tbButton)
            % delete the corresponding field in obj.ToolbarButtons struct
            obj.ToolbarButtons = rmfield(obj.ToolbarButtons,tool.Name);
            % reset the toolbar (it will disappear on hover otherwise)
            obj.mainAxes.Toolbar.reset;
        end

    end

    %% Toggle/query tool state
    methods

        % enable installed tool specified by name
        function enableTool(obj, name)
            t = obj.getInstalledTool(name); 
            if isempty(t), return; end
            t.enable();
        end

        % disable installed tool specified by name
        function disableTool(obj, name)
            t = obj.getInstalledTool(name);
            if isempty(t), return; end
            t.disable();
        end

        % query Enabled state of tool specified by name
        function tf = toolEnabled(obj, name)
            t = obj.getInstalledTool(name);
            tf = ~isempty(t) && isvalid(t) && t.Enabled;
        end

        % toggle Enabled state of "state" tool specified by name (toolbar button ValueChangedFcn)
        function onToolToggle(obj,toolState,name)
            switch toolState
                case true
                    obj.enableTool(name);
                case false
                    obj.disableTool(name);
            end
        end

        % run "push" tool specified by name (toolbar button ButtonPushedFcn)
        function onToolPush(obj,name)
            obj.runTool(name);
        end

        % run installed tool specified by name
        function runTool(obj, name)
            t = obj.getInstalledTool(name); 
            if isempty(t), return; end
            t.push();
        end


        % disable ActiveExclusiveTool if it exists
        function disableActiveExclusive(obj)
            % get the existing exclusive tool
            existingExclusive = obj.ActiveExclusiveTool;
            % exit if none found
            if isempty(existingExclusive), return; end
            % otherwise disable it
            obj.disableTool(existingExclusive.Name);
        end

    end

    %% Retrieve/sort tools
    methods

        % get installed tool specified by name
        function t = getInstalledTool(obj, name)
            t = [];
            if ~isempty(obj.ToolRegistry) && isKey(obj.ToolRegistry, char(name))
                t = obj.ToolRegistry(char(name));
            end
        end

        % get loaded tool specified by name
        function t = getLoadedTool(obj, name)
            t = [];
            if ~isempty(obj.ToolList) && isKey(obj.ToolList, char(name))
                t = obj.ToolList(char(name));
            end
        end

        % get the highest Priority Interceptor for the specified eventType
        function tool = getPriorityInterceptor(obj,eventType)
            % cell array of Installed tools
            toolsCell = obj.ToolRegistry.values;
            % no Installed tools, exit early
            if isempty(toolsCell), tool = []; return; end
            % get logical idx of Installed, Enabled tools that can Intercept the given eventType
            idx = cellfun(@(t) t.Enabled & t.("Captures"+eventType) ,toolsCell,'UniformOutput',true);
            % no matching tools, exit early
            if ~any(idx), tool = []; return; end
            % sort the tools by priority (descending order)
            tools = obj.prioritySortToolsCell(toolsCell(idx));
            % return the first element (highest priority)
            tool = tools{1};
        end

        % get cell array of Distractors for the specified eventType, sorted by descending Priority
        function toolsCell = getPriorityDistractors(obj,eventType)
            % cell array of Installed tools
            toolsCell = obj.ToolRegistry.values;
            % no Installed tools, exit early
            if isempty(toolsCell), return; end
            % get logical idx of Installed tools that can Distract the given eventType
            idx = cellfun(@(t) t.("Distracts"+eventType),toolsCell,'UniformOutput',true);
            % no matching tools, exit early
            if ~any(idx), toolsCell = {}; return; end
            % sort the tools by priority (descending order)
            toolsCell = obj.prioritySortToolsCell(toolsCell(idx));
        end

        % given a containers.Map of tools, return cell array of tools sorted by descending Priority
        function toolsCell = prioritySortTools(obj,toolsMap)
            % sort toolsMap.values by priority in descending order
            toolsCell = obj.prioritySortToolsCell(toolsMap.values);
        end

        % given a cell array of tools, return the same cell array sorted by descending Priority
        function toolsCell = prioritySortToolsCell(~,toolsCell)
            % empty cell, exit early
            if isempty(toolsCell), return; end
            % array of (sorted) Priority values for each tool
            priority = cellfun(@(t) t.Priority,toolsCell,'UniformOutput',true);
            [~,sortIdx] = sort(priority,'descend');
            % sort using the idxs returned by sort
            toolsCell = toolsCell(sortIdx);
        end

    end

    %% User-facing tool management (Set/Get to change loaded/installed tools)
    methods

        % get loaded tool names
        function ToolBox = get.ToolBox(obj)
            ToolBox = obj.ToolList.keys;
        end

        % set loaded tools
        function set.ToolBox(obj,newToolBox)
            % cell array of currently loaded tool names
            oldToolBox = obj.ToolBox;
            % tools in newToolBox that are not in oldToolBox (need to load them)
            toolsToAdd = setdiff(newToolBox,oldToolBox,'stable');
            % tools in oldToolBox that are not in newToolBox (need to unload them)
            toolsToRemove = setdiff(oldToolBox,newToolBox,'stable');
            % load all new tools in newToolBox
            if ~isempty(toolsToAdd)
                for i = 1:numel(toolsToAdd)
                    % load the tool
                    obj.loadTool(toolsToAdd{i});
                end
            end
            % unload any loaded tools not in newToolBox
            if ~isempty(toolsToRemove)
                for i = 1:numel(toolsToRemove)
                    % unload the tool
                    obj.unloadTool(toolsToRemove{i});
                end
            end
        end

        % get installed tool names
        function ToolBelt = get.ToolBelt(obj)
            ToolBelt = obj.ToolRegistry.keys;
        end

        % set installed tools (load first if necessary)
        function set.ToolBelt(obj,newToolBelt)
            % cell array of currently installed tool names
            oldToolBelt = obj.ToolBelt;
            % tools in newToolBelt that are not in oldToolBelt (need to install them)
            toolsToAdd = setdiff(newToolBelt,oldToolBelt,'stable');
            % tools in oldToolBelt that are not in newToolBelt (need to uninstall them)
            toolsToRemove = setdiff(oldToolBelt,newToolBelt,'stable');
            % install all uninstalled tools in newToolBelt (load first if necessary)
            if ~isempty(toolsToAdd)
                for i = 1:numel(toolsToAdd)
                    % tool is not already loaded, load it before installing
                    if ~obj.ToolList.isKey(toolsToAdd{i})
                        obj.loadTool(toolsToAdd{i});
                    end
                    % install the tool
                    obj.installTool(toolsToAdd{i});
                end
            end
            % uninstall any installed tools not in newToolBelt (do not unload)
            if ~isempty(toolsToRemove)
                for i = 1:numel(toolsToRemove)
                    % uninstall the tool
                    obj.uninstallTool(toolsToRemove{i});
                end
            end
        end

    end

    %% Active CData / CLim / ImageData management
    methods
    
        % --- ImageData ---
        function v = get.ImageData(obj)
            v = obj.ImageData_;
        end
    
        function set.ImageData(obj, val)
            arguments
                obj
                val (1,1) matlabx.image.ImageData
            end
    
            obj.ImageData_ = val;
            obj.syncViewStateToImageData();
            obj.syncRenderSourceToView();
        end
    
        % --- CData ---
        function v = get.CData(obj)
            v = obj.RenderSource_;
        end
    
        function set.CData(obj, cdata)
            if isempty(cdata)
                cdata = matlabx.ui.widgets.ImageAxes.placeholderImage();
            end
    
            obj.ImageData_ = matlabx.image.ImageData(cdata);
            obj.syncViewStateToImageData();
            obj.syncRenderSourceToView();
        end
    
        % --- CLim ---
        function v = get.CLim(obj)
            idx = obj.ViewState_.ChannelIdx;
            clim = obj.ChannelDisplay_(idx).CLim;
    
            if isempty(clim)
                v = [0 1];
            else
                v = clim;
            end
        end
    
        function set.CLim(obj, val)
            idx = obj.ViewState_.ChannelIdx;
            ch = obj.ImageData_.getChannel(idx);
    
            % meaningless for rgb/logical
            if strcmp(ch.Type, 'rgb') || islogical(ch.Data)
                return
            end
    
            obj.ChannelDisplay_(idx).CLim = double(val);
            obj.ViewState_.CLimMode = 'manual';
    
            if obj.ViewState_.ShowComposite
                obj.RenderSource_ = obj.getCompositeImage();
                obj.refreshView();
            else
                obj.updateImageCData();
                obj.updateColorbar();
            end
        end
    
        % --- CLimMode ---
        function v = get.CLimMode(obj)
            v = obj.ViewState_.CLimMode;
        end
    
        function set.CLimMode(obj, val)
            obj.ViewState_.CLimMode = val;
    
            if strcmp(val, 'auto')
                for i = 1:obj.nChannels
                    obj.ChannelDisplay_(i).CLim = obj.ImageData_.getDefaultCLim(i);
                end
            end
    
            if obj.ViewState_.ShowComposite
                obj.RenderSource_ = obj.getCompositeImage();
            end
    
            obj.refreshView();
        end
    
        % --- CDataSize ---
        function v = get.CDataSize(obj)
            if obj.ViewState_.ShowComposite
                v = size(obj.RenderSource_);
            else
                v = obj.ImageData_.getChannelSize(obj.ViewState_.ChannelIdx);
            end
        end
    
        % --- CDataType ---
        function v = get.CDataType(obj)
            if obj.ViewState_.ShowComposite
                v = 'rgb';
            else
                v = obj.ImageData_.getChannelType(obj.ViewState_.ChannelIdx);
            end
        end
    
        % --- CDataClass ---
        function v = get.CDataClass(obj)
            if obj.ViewState_.ShowComposite
                v = class(obj.RenderSource_);
            else
                v = obj.ImageData_.getChannelClass(obj.ViewState_.ChannelIdx);
            end
        end

    
        % --- DisplayCData ---
        function v = get.DisplayCData(obj)
            if obj.ViewState_.ShowComposite
                v = obj.RenderSource_;
                return
            end
    
            ch = obj.ImageData_.getChannel(obj.ViewState_.ChannelIdx);
            clim = obj.ChannelDisplay_(obj.ViewState_.ChannelIdx).CLim;
    
            switch ch.Type
                case 'grayscale'
                    if islogical(ch.Data) || isempty(clim)
                        v = ch.Data;
                    else
                        v = matlabx.image.process.rescaleLinear(ch.Data, clim);
                    end
                case 'rgb'
                    v = ch.Data;
            end
        end
    
        % --- nChannels ---
        function v = get.nChannels(obj), v = obj.ImageData_.nChannels; end

        % --- MultiChannel ---
        function v = get.MultiChannel(obj), v = obj.ImageData_.MultiChannel; end

        % --- MultiChannelType ---
        function v = get.MultiChannelType(obj), v = obj.ImageData_.MultiChannelType; end

    end

    %% ImageData + display/view-state management
    methods (Access=private)
    
        function syncViewStateToImageData(obj)
            n = obj.nChannels;
    
            % clip active channel to valid range
            obj.ViewState_.ChannelIdx = clip(obj.ViewState_.ChannelIdx, 1, n);
    
            % resize per-channel display state while preserving old values
            obj.ChannelDisplay_ = obj.mergeChannelDisplayState(n);
    
            % composite only allowed when mergeable
            if obj.ViewState_.ShowComposite && ~obj.ImageData_.CanMerge
                obj.ViewState_.ShowComposite = false;
            end
        end
    
        function displayState = mergeChannelDisplayState(obj, n)
            old = obj.ChannelDisplay_;
    
            displayState = repmat(struct( ...
                'CLim', [], ...
                'ColorName', "", ...
                'Colormap', gray(256), ...
                'DisplayMap', gray(256)), 1, n);
    
            defaultColors = matlabx.ui.widgets.ImageAxes.getColorNames();
    
            for i = 1:n
                % defaults from ImageData
                displayState(i).CLim = obj.ImageData_.getDefaultCLim(i);
                displayState(i).ColorName = string(defaultColors{1 + mod(i-1, numel(defaultColors))});
                displayState(i).Colormap = gray(256);
    
                % preserve prior display state when valid
                if i <= numel(old)
                    if ~isempty(old(i).CLim) && strcmp(obj.ViewState_.CLimMode, 'manual')
                        displayState(i).CLim = old(i).CLim;
                    end
    
                    if obj.isNonEmptyText(old(i).ColorName)
                        displayState(i).ColorName = string(old(i).ColorName);
                    end
    
                    if ~isempty(old(i).Colormap)
                        displayState(i).Colormap = old(i).Colormap;
                    end
                end
    
                displayState(i).DisplayMap = obj.getDisplayMap( ...
                    displayState(i), obj.ViewState_.ChannelColorMode);
            end
        end
    
        function syncRenderSourceToView(obj)
            oldData = obj.RenderSource_;
    
            if obj.ViewState_.ShowComposite
                newData = obj.getCompositeImage();
            else
                newData = obj.ImageData_.getChannelData(obj.ViewState_.ChannelIdx);
            end
    
            obj.RenderSource_ = newData;
            obj.refreshView();
    
            evtData = matlabx.ui.widgets.events.CDataChangedEventData(oldData, newData);
            notify(obj, 'CDataChanged', evtData);
        end
    
        function updateAllDisplayMaps(obj)
            for i = 1:obj.nChannels
                obj.ChannelDisplay_(i).DisplayMap = obj.getDisplayMap( ...
                    obj.ChannelDisplay_(i), obj.ViewState_.ChannelColorMode);
            end
        end
    
        function map = getDisplayMap(~, displayState, mode)
            switch mode
                case 'colors'
                    map = matlabx.colors.ops.colorGradient( ...
                        [0 0 0], ...
                        matlabx.colors.names.getColor(char(displayState.ColorName)), ...
                        256);
                case 'luts'
                    map = displayState.Colormap;
            end
        end
    
        function I = getCompositeImage(obj)
            if ~obj.ImageData_.CanMerge
                I = obj.ImageData_.getChannelData(obj.ViewState_.ChannelIdx);
                return
            end
    
            if ~strcmp(obj.ImageData_.MultiChannelType, 'grayscale')
                I = obj.ImageData_.getChannelData(obj.ViewState_.ChannelIdx);
                return
            end
    
            data = cell(1, obj.nChannels);
            clims = zeros(obj.nChannels, 2);
    
            for i = 1:obj.nChannels
                data{i} = obj.ImageData_.getChannelData(i);
                clims(i,:) = obj.ChannelDisplay_(i).CLim;
            end
    
            switch obj.ViewState_.ChannelColorMode
                case 'colors'
                    colors = zeros(obj.nChannels, 3);
                    for i = 1:obj.nChannels
                        colors(i,:) = matlabx.colors.names.getColor( ...
                            char(obj.ChannelDisplay_(i).ColorName));
                    end
                    I = matlabx.image.compose.mergeChannelsRGB_add(data, clims, colors);
    
                case 'luts'
                    maps = {obj.ChannelDisplay_.DisplayMap};
                    I = matlabx.image.compose.mergeChannelsRGB_LUT(data, clims, maps);
            end
        end
    
    end

    %% Channel switching / Channel view state
    methods
    
        % --- channel switching ---
        function nextChannel(obj)
            obj.ChannelIdx = matlabx.utils.math.wrapStep(obj.ChannelIdx, 1, 1, obj.nChannels);
        end
    
        function previousChannel(obj)
            obj.ChannelIdx = matlabx.utils.math.wrapStep(obj.ChannelIdx, -1, 1, obj.nChannels);
        end
    
        % --- ChannelIdx ---
        function v = get.ChannelIdx(obj)
            v = obj.ViewState_.ChannelIdx;
        end
    
        function set.ChannelIdx(obj, val)
            obj.ViewState_.ChannelIdx = clip(val, 1, obj.nChannels);
            obj.syncRenderSourceToView();
        end
    
        % --- ChannelColors ---
        function val = get.ChannelColors(obj)
            val = cell(1, obj.nChannels);
            for i = 1:obj.nChannels
                val{i} = char(obj.ChannelDisplay_(i).ColorName);
            end
        end
    
        function set.ChannelColors(obj, val)
            if isempty(val)
                return
            end
    
            n = min(numel(val), obj.nChannels);
            for i = 1:n
                obj.ChannelDisplay_(i).ColorName = string(val{i});
            end
    
            obj.updateAllDisplayMaps();
            obj.syncRenderSourceToView();
        end
    
        % --- ChannelColormaps ---
        function val = get.ChannelColormaps(obj)
            val = cell(1, obj.nChannels);
            for i = 1:obj.nChannels
                val{i} = obj.ChannelDisplay_(i).Colormap;
            end
        end
    
        function set.ChannelColormaps(obj, val)
            if isempty(val)
                return
            end
    
            n = min(numel(val), obj.nChannels);
            for i = 1:n
                obj.ChannelDisplay_(i).Colormap = val{i};
            end
    
            obj.updateAllDisplayMaps();
            obj.syncRenderSourceToView();
        end
    
        % --- Colormap ---
        function v = get.Colormap(obj)
            v = obj.ChannelDisplay_(obj.ViewState_.ChannelIdx).DisplayMap;
        end
    
        function set.Colormap(obj, val)
            idx = obj.ViewState_.ChannelIdx;
            obj.ChannelDisplay_(idx).Colormap = double(val);
    
            % setting Colormap switches mode to LUTs
            obj.ViewState_.ChannelColorMode = 'luts';
    
            obj.updateAllDisplayMaps();
    
            if obj.ViewState_.ShowComposite
                obj.RenderSource_ = obj.getCompositeImage();
                obj.refreshView();
            else
                obj.updateAxesColormap();
            end
        end
    
        % --- ChannelColorMode ---
        function v = get.ChannelColorMode(obj)
            v = obj.ViewState_.ChannelColorMode;
        end
    
        function set.ChannelColorMode(obj, val)
            obj.ViewState_.ChannelColorMode = val;
            obj.updateAllDisplayMaps();
            obj.syncRenderSourceToView();
        end
    
        % --- ShowComposite ---
        function v = get.ShowComposite(obj)
            v = matlab.lang.OnOffSwitchState(obj.ViewState_.ShowComposite);
        end
    
        function set.ShowComposite(obj, val)
            obj.ViewState_.ShowComposite = logical(val) && obj.CanMerge;
            obj.syncRenderSourceToView();
        end
    
        function toggleComposite(obj)
            obj.ShowComposite = ~obj.ViewState_.ShowComposite;
        end
    
        % --- CanMerge ---
        function tf = get.CanMerge(obj)
            tf = obj.ImageData_.CanMerge;
        end
    
        % --- ChannelCLim ---
        function setCLim(obj, clim, idx)
            arguments
                obj (1,1) matlabx.ui.widgets.ImageAxes
                clim (1,2) double
                idx (:,1) = []
            end
    
            if isempty(idx)
                idx = obj.ChannelIdx;
            end
    
            for k = 1:numel(idx)
                ii = idx(k);
    
                if ii < 1 || ii > obj.nChannels
                    error('ImageAxes:InvalidChannelIndex', ...
                        'Index %i does not refer to an existing channel', ii)
                end
    
                ch = obj.ImageData_.getChannel(ii);
    
                if strcmp(ch.Type, 'rgb') || islogical(ch.Data)
                    continue
                end
    
                obj.ChannelDisplay_(ii).CLim = clim;
            end
    
            obj.ViewState_.CLimMode = 'manual';
    
            if obj.ViewState_.ShowComposite
                obj.RenderSource_ = obj.getCompositeImage();
                obj.refreshView();
            else
                obj.updateImageCData();
                obj.updateColorbar();
            end
        end
    
    end


    %% CLim slider dialog management
    methods

        function openContrastTool(obj)

            if obj.contrastToolOpen
                return
            end

            idx = obj.ViewState_.ChannelIdx;
            channel = obj.ImageData_.getChannel(idx);
            channelDisplay = obj.ChannelDisplay_(idx);

            switch channel.Type
                case 'grayscale'
                    switch channel.Class
                        case {'double','single'}
                            dispFmt = '%0.2f'; roundVals = "off";
                        case {'uint8','uint16'}
                            dispFmt = '%i'; roundVals = "on";
                        otherwise
                            return
                    end
                otherwise
                    return
            end

            obj.contrastTool = matlabx.app.SliderDialog(...
                "Title","Adjust display limits",...
                "Name",channel.ChannelName,...
                "Limits",channel.DefaultCLim,...
                "Value",channelDisplay.CLim,...
                "RoundDigits",0,...
                "RoundValues",roundVals,...
                "ValueDisplayFormat",dispFmt,...
                "ValueChangingFcn",@(o,~) obj.onContrastToolValueChanging(o),...
                "ValueChangedFcn",@(o,~) obj.onContrastToolValueChanged(o),...
                "ClosedFcn",@(~,~) obj.onContrastToolClosed());

            obj.contrastToolOpen = true;

        end

        function onContrastToolClosed(obj)
            obj.contrastToolOpen = false;
        end

        function onContrastToolValueChanged(obj,o)
            obj.CLim = o.Value;
        end

        function onContrastToolValueChanging(obj,o)
            obj.CLim = o.Value;
        end

    end






    %% Hidden entrypoint for debugging
    methods (Hidden)
        function DEBUG_(obj)
            debug
        end
    end


    %% Utils
    methods (Static, Access=private)

        %function y = clip(x,a,b), y = max(a, min(b, x)); end

        % check if the point, XY, is within limits, XLim and YLim
        function tf = isInLimits(XY,XLim,YLim)
            x = XY(1); y = XY(2);
            tf = x >= XLim(1) && x <= XLim(2) && y >= YLim(1) && y <= YLim(2);
        end

        % return a placeholder image for startup
        function I = placeholderImage()
            % all black truecolor array
            I = zeros([256,256,3]);
        end

        % get colorbar ticks and labels based on CData class
        function [ticks,labels] = getColorbarTickLabels(valClass,clim,N)
            arguments
                valClass (1,:) char {mustBeMember(valClass,{'logical','double','single','uint16','uint8'})}
                clim (1,2) double
                N (:,1) = []
            end
        
            if isempty(N)
                if strcmp(valClass,'logical'); N = 2; else, N = 11; end
            end
        
            ticks = linspace(0,1,N);

            switch valClass
                case 'logical'
                    labels = arrayfun(@(v) sprintf('%i',v),ticks,'UniformOutput',false);
                case {'double','single'}
                    labels = arrayfun(@(v) sprintf('%.2f',v),linspace(clim(1),clim(2),N),'UniformOutput',false);
                case {'uint16','uint8'}
                    labels = arrayfun(@(v) sprintf('%i',v),round(linspace(clim(1),clim(2),N)),'UniformOutput',false);
            end
        end

    end

    methods (Static)

        % return names of all classes in matlabx.ui.widgets.tools
        function names = getToolClassNames()
            % get list of tool class names in matlabx.ui.widgets.tools using matlab.metadata.Namespace

            % cell array of char vectors
            names = {matlab.metadata.Namespace.fromName("matlabx.ui.widgets.tools").ClassList.Name}';
        end

        % return names of all tool classes (just the last part)
        function names = getToolNames()

            classNames = matlabx.ui.widgets.ImageAxes.getToolClassNames();
            if numel(classNames)==0
                names = {};
                return
            else
                names = cell(1,numel(classNames));
                for i = 1:numel(classNames)
                    % split name with '.' delimeter
                    temp = strsplit(classNames{i},'.');
                    % tool name is after the final '.'
                    names(i) = temp(end);
                end
            end

        end

        % return names of allowed channel colors
        function names = getColorNames()
            names = {'cyan','magenta','yellow','red','green','blue'};
        end


        function ax = demo(name)
            arguments
                name (1,:) char {mustBeMember(name,{'default','multichannel','empty'})}
            end

            fig = uifigure("WindowStyle","alwaysontop",...
                "Position",[0 0 500 500],...
                "Visible","off");

            switch name
                case 'default'
                    ax = matlabx.ui.widgets.ImageAxes(fig,...
                        "ToolBelt",{'Zoom','Colorbar'},...
                        "Units","normalized",...
                        "Position",[0 0 1 1],...
                        "CData",imread("rice.png"),...
                        "CLim",[0 1],...
                        "Colormap",gray);
                case 'empty'
                    ax = matlabx.ui.widgets.ImageAxes(fig,...
                        "CData",[],...
                        "ToolBelt",{'Zoom','Colorbar'},...
                        "Units","normalized",...
                        "Position",[0 0 1 1],...
                        "CLim",[0 1]);
                case 'multichannel'
                    I1 = imread("rice.png");
                    I2 = imgaussfilt(I1);
                    cdata = {I1,I2};
                    ax = matlabx.ui.widgets.ImageAxes(fig,...
                        "CData",cdata,...
                        "ToolBelt",{'Zoom','Colorbar'},...
                        "Units","normalized",...
                        "Position",[0 0 1 1]);
            end

            movegui(fig,"center")

            fig.Visible = "on";

        end


    end

    %% Teardown
    methods

        function delete(obj)

            % remove listeners first
            if ~isempty(obj.L), delete(obj.L(isvalid(obj.L))); end
            % replace listener property with empty array of event.listener
            obj.L = event.listener.empty;

            % contrast tool
            if ~isempty(obj.contrastTool), delete(obj.contrastTool(isvalid(obj.contrastTool))); end

            % Unregister from hub (safe if figure already gone)
            try
                if ~isempty(obj.Hub) && isvalid(obj.Hub) && ~isnan(obj.RouterId)
                    obj.Hub.unregister(obj.RouterId);
                end
            catch
            end

            % unload (delete) all tools before deleting ImageAxes
            obj.unloadAllTools();

        end

    end

end
