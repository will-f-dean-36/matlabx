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
        CanMergeComponents  (1,1) logical
    
        CData               {mustBeA(CData,{'double','single','uint8','uint16','logical','cell'})}
        CLimMode            (1,:) char
        ShowComposite       (1,1) matlab.lang.OnOffSwitchState
        ComponentColors     (1,:) cell
        ComponentColormaps  (1,:) cell
        ComponentColorMode  (1,:) char {mustBeMember(ComponentColorMode,{'colors','luts'})}

        ComponentIdx        (1,1) double
        Z                   (1,1) double
        T                   (1,1) double
    end

    properties (Dependent)
        ImageData
    end

    % read-only
    properties (Dependent, SetAccess=private)
        DisplayCData
        CDataKind       (1,:) char {mustBeMember(CDataKind,{'scalar','rgb'})}
        CDataSize       (1,:) double
        CDataClass      (1,:) char {mustBeMember(CDataClass,{'double','single','uint8','uint16','logical',''})}
        
        NumComponents         (1,1) double
        MultiComponent        (1,1) matlab.lang.OnOffSwitchState
        MultiComponentKind    (1,:) {mustBeMember(MultiComponentKind,{'scalar','rgb','mixed','none'})}
    end

    properties (Access=private)
        % small internal view state
        ViewState_ struct = struct( ...
            'C', 1, ...
            'Z', 1, ...
            'T', 1, ...
            'ShowComposite', false, ...
            'CLimMode', 'auto', ...
            'ComponentColorMode', 'colors');
        % image data structure
        ImageData_ (1,1) matlabx.image.Image5D = matlabx.image.Image5D.fromComponents(zeros(256,256,3))
        % currently rendered source image (active component plane or computed composite)
        RenderSource_ (:,:,:) = matlabx.ui.widgets.ImageAxes.placeholderImage
        % per-component display state
        ComponentDisplay_ (1,:) struct = struct( ...
            'CLim', {}, ...
            'ColorName', {}, ...
            'Color', {}, ...
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
        %TopLabel (1,1) matlab.graphics.primitive.Text
        BottomLabel (1,1) matlab.graphics.primitive.Text
        Colorbar matlab.graphics.illustration.ColorBar

        sizingGrid matlab.ui.container.GridLayout

        ContextMenuUI struct
    end

    % tool-accessible
    properties (Access=?matlabx.ui.widgets.ImageAxesTool)
        mainAxes matlab.ui.control.UIAxes
    end

    properties (Access=private)
        % uipanelOverheadPx_ (1,1) double = NaN
        UICal matlabx.ui.calibration.UICalibration
    end

    properties (Dependent, AbortSet)
        FontSize (1,1) double
    end

    properties (Access=private, AbortSet)
        FontSize_ (1,1) double = 12
        uipanelOverheadPx_ (1,1) double = 19
    end


    properties (Access=private)
        % flags to help coalesce/manage updates
        pendingSizeUpdate (1,1) logical = false
        inStartup (1,1) logical = true
    end

    %% Popup/temporary UI management

    % popup windows
    properties (Access=private, Transient, NonCopyable)
        contrastTool (:,1) matlabx.app.SliderGroupDialog
        metadataWindow matlabx.app.TextWindow
    end

    properties
        contrastToolOpen (1,1) logical = false
        metadataWindowOpen (1,1) logical = false
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

            % perform/retrieve calibration first
            obj.UICal = matlabx.ui.calibration.getCalibration();

            obj.Interruptible = 'off';
            obj.BusyAction = 'cancel';

            % Main grid
            obj.Grid = uigridlayout(obj,[1,1], ...
                'RowHeight',{'fit'},...
                'ColumnWidth',{'fit'},...
                'RowSpacing',0,...
                'ColumnSpacing',0,...
                'Padding',[0 0 0 0], ...
                'BackgroundColor',[1 1 1]);

            obj.sizingGrid = uigridlayout(obj.Grid,[3,3],...
                'RowHeight',{0,300,0},...
                'ColumnWidth',{0,300,0},...
                'ColumnSpacing',0,...
                'RowSpacing',0,...
                'Padding',[0 0 0 0],...
                'BackgroundColor',[1 0 0]);

            % Panel to hold the axes
            obj.Panel = uipanel(obj.sizingGrid, ...
                'BackgroundColor',[0 0 0],...
                'AutoResizeChildren','off',...
                'BorderWidth',0,...
                'FontSize',obj.FontSize_,...
                'FontUnits','pixels');
            obj.Panel.Layout.Row = 2;
            obj.Panel.Layout.Column = 2;

            obj.Panel.Title = "TEST TITLE";

            % Main axes
            obj.mainAxes = uiaxes(obj.Panel, ...
                'Units','normalized', ...
                'InnerPosition',[0 0 1 1], ...
                'YDir','reverse', ...
                'YLim',[0 1], ...
                'XLim',[0 1], ...
                'XTick',[], ...
                'YTick',[], ...
                'Color',[0 0 0], ...
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
                'Color',[0 0 0], ...
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
            obj.Colorbar = colorbar(obj.mainAxes,"east","Visible","off","PickableParts","none","HitTest","off");

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
                'FontSize',obj.FontSize_,...
                'Clipping','on',...
                'Margin',3,...
                'HorizontalAlignment','left',...
                'VerticalAlignment','bottom');

            % set up ContextMenu
            obj.setupContextMenu();

            % set default colormap
            obj.Colormap = gray;

            % initialize display state from ImageData
            obj.syncViewStateToImageData();
            
            % initial render
            obj.syncRenderSourceToView();
        end

        function update(obj)
            if obj.inStartup
                obj.FontSize_ = obj.FontSize;
                obj.uipanelOverheadPx_ = obj.UICal.uipanelTopChromeHeightPx(obj.FontSize_);
                obj.inStartup = false;
                % obj.updateOnResize();
            end

            % set the Tag property of the mainAxes
            obj.mainAxes.Tag = obj.Name;

            % set BackgroundColor
            obj.Grid.BackgroundColor = obj.BackgroundColor;
            % obj.Panel.BackgroundColor = obj.BackgroundColor;

            obj.sizingGrid.BackgroundColor = obj.BackgroundColor;

            % % set FontSize and update calibrated values
            % obj.FontSize_ = obj.FontSize;

            obj.updateOnResize();
        end


        function setupContextMenu(obj)

            obj.ContextMenu = uicontextmenu(obj.ParentFig);

            S = struct();

            S.ColorMode = uimenu(obj.ContextMenu,"Text","Color Mode...");

            S.ColorMode_colors = uimenu(S.ColorMode,"Text","colors",...
                "MenuSelectedFcn",@(o,e) obj.setComponentColorMode("colors"),"Checked","on");
            S.ColorMode_luts = uimenu(S.ColorMode,"Text","luts",...
                "MenuSelectedFcn",@(o,e) obj.setComponentColorMode("luts"),"Checked","off");

            S.Info = uimenu(obj.ContextMenu,"Text","Info...", ...
                "MenuSelectedFcn",@(~,~) obj.openMetadataWindow());


            obj.ContextMenuUI = S;

        end


    end

    %% UI helpers
    methods (Access=private)
        %% --- UI refresh helpers ---

        function updateOnResize(obj)
            if ~isvalid(obj); return; end

            if obj.pendingSizeUpdate
                return
            else
                obj.pendingSizeUpdate = true;
            end

            oldPosUnits = obj.Units;

            obj.Units = "pixels";
            compPos = obj.Position;

            obj.Units = oldPosUnits;
            panelTop = obj.uipanelOverheadPx_;


            W = compPos(3);
            H = compPos(4);
            trueH = H - panelTop;


            imgH = obj.ImageData_.SizeY;
            imgW = obj.ImageData_.SizeX;

            targetRatio = imgH / imgW;          % height / width
            currentRatio = trueH / W;

            if currentRatio > targetRatio
                % Figure is too tall for the image
                newW = W;
                newH = W * targetRatio;
            else
                % Figure is too wide for the image
                newH = trueH;
                newW = trueH / targetRatio;
            end

            newH = newH + panelTop;

            wPad = (W-newW)/2;
            hPad = (H-newH)/2;

            set(obj.sizingGrid,'ColumnWidth',{wPad,newW,wPad},'RowHeight',{hPad,newH,hPad});
            drawnow;

            obj.pendingSizeUpdate = false;
        end

        function updateBottomLabelText(obj)
        
            px = obj.activePixel;
        
            if isempty(px), obj.BottomLabel.String ='Hover over image to interact'; return; end
        
            posStr = sprintf('Pixel: (%0.f,%0.f)',px(1),px(2));
        
            if obj.ViewState_.ShowComposite
                activeData = obj.ImageData_.getPlane(obj.ViewState_.C,obj.ViewState_.Z,obj.ViewState_.T);
                activeKind = obj.ImageData_.getComponentKind(obj.ViewState_.C);
                activeClass = obj.ImageData_.getComponentClass(obj.ViewState_.C);
            else
                activeData = obj.CData;
                activeKind = obj.CDataKind;
                activeClass = obj.CDataClass;
            end
        
            switch activeKind
                case 'scalar'
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
            sizeStr = obj.getImageSizeString();
            bitDepthStr = obj.getImageBitDepthString();
            compStr = obj.getComponentInfoString();
            zStr = obj.getZInfoString();
            tStr = obj.getTInfoString();

            txt = {sizeStr,bitDepthStr,compStr,zStr,tStr};
            % remove empty entries
            txt(ismember(txt,'')) = [];
            % join each fragment with spaced pipe
            txt = strjoin(txt,' | ');
            %obj.TopLabel.String = [' ',txt];

            obj.Panel.Title = txt;
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

            idx = obj.ViewState_.C;
            comp = obj.ImageData_.Components(idx);
            clim = obj.ComponentDisplay_(idx).CLim;

            if strcmp(comp.Kind, 'scalar') && ~strcmp(comp.Class,'logical') && ~isempty(clim)
                [ticks, labels] = matlabx.ui.widgets.ImageAxes.getColorbarTickLabels(comp.Class, clim);
            end

            obj.Colorbar.Ticks = ticks;
            obj.Colorbar.TickLabels = labels;
        end

        function updateAxesColormap(obj)
            obj.mainAxes.Colormap = obj.ComponentDisplay_(obj.ViewState_.C).DisplayMap;
        end

        function updateFontSizes(obj)
            fprintf('updateFontSizes() FontSize_: %i\n',obj.FontSize_)
            obj.Panel.FontSize = obj.FontSize_;
            obj.BottomLabel.FontSize = obj.FontSize_;
            obj.uipanelOverheadPx_ = obj.UICal.uipanelTopChromeHeightPx(obj.FontSize_);
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
            % update ContextMenu
            obj.refreshContextMenu();
        end

        function refreshContextMenu(obj)
            % ComponentColorMode
            val = obj.ComponentColorMode;
            obj.ContextMenuUI.ColorMode_colors.Checked = strcmp(val,"colors");
            obj.ContextMenuUI.ColorMode_luts.Checked = strcmp(val,"luts");



        end


        %% --- UI text helpers ---

        function s = getImageInfoString(obj)
            s1 = sprintf(strjoin(repmat({'%i'},1,numel(obj.CDataSize)),'x'),obj.CDataSize);
            s2 = sprintf('%s (%s)',obj.CDataClass,obj.CDataKind);
            s = [s1,' ',s2];
        end

        function s = getComponentInfoString(obj)
            C = obj.ViewState_.C;
            nm = obj.ImageData_.getComponentName(C);
        
            if strlength(nm) > 0
                base = sprintf('C: %i/%i (%s)', C, obj.NumComponents, char(nm));
            else
                base = sprintf('C: %i/%i', C, obj.NumComponents);
            end
        
            if obj.ViewState_.ShowComposite
                s = [base, ' (composite)'];
            else
                s = base;
            end
        end

        function s = getZInfoString(obj)
            if obj.ImageData_.SizeZ > 1
                s = sprintf('Z: %i/%i', obj.ViewState_.Z, obj.ImageData_.SizeZ);
            else
                s = '';
            end
        end

        function s = getTInfoString(obj)
            if obj.ImageData_.SizeT > 1
                s = sprintf('T: %i/%i', obj.ViewState_.T, obj.ImageData_.SizeT);
            else
                s = '';
            end
        end

        function s = getImageSizeString(obj)
            sz = obj.CDataSize;
            % list size up to but not including the first singleton dimension
            idx = find(sz==1,1,"first");
            if ~isempty(idx) && idx>2
                idx = idx-1;
                sz = sz(1:idx);
            end
            s = sprintf(strjoin(repmat({'%i'},1,numel(sz)),'x'),sz);
        end

        function s = getImageBitDepthString(obj)

            if strcmpi(obj.CDataKind,'rgb')
                s = '';
                return
            end

            switch obj.CDataClass
                case 'uint8'
                    s = '8-bit';
                case 'uint16'
                    s = '16-bit';
                case 'single'
                    s = '32-bit float';
                case 'double'
                    s = '64-bit float';
                case 'logical'
                    s = 'binary';
            end
        end

    end

    %% Public API: ImageData/DisplayState/ViewState
    methods
    
        % --- ImageData ---
        function v = get.ImageData(obj), v = obj.ImageData_; end
    
        function set.ImageData(obj, val)
            arguments
                obj
                val (1,1) matlabx.image.Image5D
            end

            obj.ImageData_ = val;
            obj.syncViewStateToImageData();
            obj.syncRenderSourceToView();
        end
    
        % --- CData ---
        function v = get.CData(obj), v = obj.RenderSource_; end
    
        function set.CData(obj, cdata)
            if isempty(cdata)
                cdata = matlabx.ui.widgets.ImageAxes.placeholderImage();
            end

            obj.ImageData_ = matlabx.image.Image5D.fromComponents(cdata);

            obj.syncViewStateToImageData();
            obj.syncRenderSourceToView();
        end

        % --- CDataSize ---
        function v = get.CDataSize(obj)
            if obj.ViewState_.ShowComposite
                v = size(obj.RenderSource_);
            else
                v = obj.ImageData_.getComponentSize(obj.ViewState_.C);
            end
        end
    
        % --- CDataKind ---
        function v = get.CDataKind(obj)
            if obj.ViewState_.ShowComposite
                v = 'rgb';
            else
                v = obj.ImageData_.getComponentKind(obj.ViewState_.C);
            end
        end
    
        % --- CDataClass ---
        function v = get.CDataClass(obj)
            if obj.ViewState_.ShowComposite
                v = class(obj.RenderSource_);
            else
                v = obj.ImageData_.getComponentClass(obj.ViewState_.C);
            end
        end

        % --- DisplayCData ---
        function v = get.DisplayCData(obj)
            if obj.ViewState_.ShowComposite
                v = obj.RenderSource_;
                return
            end

            clim = obj.ComponentDisplay_(obj.ViewState_.C).CLim;
            comp = obj.ImageData_.Components(obj.ViewState_.C);

            I = obj.ImageData_.getPlane(obj.ViewState_.C,obj.ViewState_.Z,obj.ViewState_.T);

            switch comp.Kind
                case 'scalar'
                    if strcmp(comp.Class,'logical') || isempty(clim)
                        v = I;
                    else
                        v = matlabx.image.process.rescaleLinear(I, clim);
                    end
                case 'rgb'
                    v = I;
            end
        end

        % --- CLim ---
        function v = get.CLim(obj)
            idx = obj.ViewState_.C;
            clim = obj.ComponentDisplay_(idx).CLim;
    
            if isempty(clim)
                v = [0 1];
            else
                v = clim;
            end
        end
    
        function set.CLim(obj, val)
            idx = obj.ViewState_.C;
            comp = obj.ImageData_.getComponent(idx);


            % meaningless for rgb/logical
            if strcmp(comp.Kind, 'rgb') || strcmp(comp.Class, 'logical')
                return
            end
    
            obj.ComponentDisplay_(idx).CLim = double(val);
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
                for i = 1:obj.NumComponents
                    obj.ComponentDisplay_(i).CLim = obj.ImageData_.getComponentDataRange(i);
                end
            end
    
            if obj.ViewState_.ShowComposite
                obj.RenderSource_ = obj.getCompositeImage();
            end
    
            obj.refreshView();
        end
    
        % --- NumComponents ---
        function v = get.NumComponents(obj), v = obj.ImageData_.NumComponents; end

        % --- MultiComponent ---
        function v = get.MultiComponent(obj), v = obj.ImageData_.MultiComponent; end

        % --- MultiComponentKind ---
        function v = get.MultiComponentKind(obj), v = obj.ImageData_.MultiComponentKind; end

        % --- CanMergeComponents ---
        function tf = get.CanMergeComponents(obj), tf = obj.ImageData_.CanMergeComponents; end


        % --- ShowComposite ---
        function v = get.ShowComposite(obj), v = matlab.lang.OnOffSwitchState(obj.ViewState_.ShowComposite); end
    
        function set.ShowComposite(obj, val)
            obj.ViewState_.ShowComposite = logical(val) && obj.CanMergeComponents;
            obj.syncRenderSourceToView();
        end
    
        % --- toggleComposite ---
        function toggleComposite(obj), obj.ShowComposite = ~obj.ViewState_.ShowComposite; end




        %% C/Z/T control

        % --- nextComponent ---
        function nextComponent(obj), obj.ComponentIdx = matlabx.utils.math.wrapStep(obj.ComponentIdx,1,1,obj.NumComponents); end
    
        % --- previousComponent ---
        function previousComponent(obj), obj.ComponentIdx = matlabx.utils.math.wrapStep(obj.ComponentIdx,-1,1,obj.NumComponents); end
    
        % --- ComponentIdx ---
        function v = get.ComponentIdx(obj), v = obj.ViewState_.C; end
    
        function set.ComponentIdx(obj, val)
            obj.ViewState_.C = clip(val, 1, obj.NumComponents);
            obj.syncRenderSourceToView();
        end


        % --- nextZ ---
        function nextZ(obj), obj.Z = matlabx.utils.math.wrapStep(obj.Z,1,1,obj.ImageData_.SizeZ); end
    
        % --- previousZ ---
        function previousZ(obj), obj.Z = matlabx.utils.math.wrapStep(obj.Z,-1,1,obj.ImageData_.SizeZ); end
    
        % --- Z ---
        function v = get.Z(obj), v = obj.ViewState_.Z; end
    
        function set.Z(obj, val)
            obj.ViewState_.Z = clip(val, 1, obj.ImageData_.SizeZ);
            obj.syncRenderSourceToView();
        end

        % --- nextT ---
        function nextT(obj), obj.T = matlabx.utils.math.wrapStep(obj.T,1,1,obj.ImageData_.SizeT); end
    
        % --- previousT ---
        function previousT(obj), obj.T = matlabx.utils.math.wrapStep(obj.T,-1,1,obj.ImageData_.SizeT); end
    
        % --- T ---
        function v = get.T(obj), v = obj.ViewState_.T; end
    
        function set.T(obj, val)
            obj.ViewState_.T = clip(val, 1, obj.ImageData_.SizeT);
            obj.syncRenderSourceToView();
        end



        % --- ComponentColors ---
        function val = get.ComponentColors(obj)
            val = cell(1, obj.NumComponents);
            for i = 1:obj.NumComponents
                val{i} = char(obj.ComponentDisplay_(i).ColorName);
            end
        end
    
        function set.ComponentColors(obj, val)
            if isempty(val)
                return
            end
    
            n = min(numel(val), obj.NumComponents);
            for i = 1:n
                obj.ComponentDisplay_(i).ColorName = string(val{i});
            end
    
            obj.updateAllDisplayMaps();
            obj.syncRenderSourceToView();
        end
    
        % --- ComponentColormaps ---
        function val = get.ComponentColormaps(obj)
            val = cell(1, obj.NumComponents);
            for i = 1:obj.NumComponents
                val{i} = obj.ComponentDisplay_(i).Colormap;
            end
        end
    
        function set.ComponentColormaps(obj, val)
            if isempty(val)
                return
            end
    
            n = min(numel(val), obj.NumComponents);
            for i = 1:n
                obj.ComponentDisplay_(i).Colormap = val{i};
            end
    
            obj.updateAllDisplayMaps();
            obj.syncRenderSourceToView();
        end
    
        % --- Colormap ---
        function v = get.Colormap(obj), v = obj.ComponentDisplay_(obj.ViewState_.C).DisplayMap; end
    
        % function set.Colormap(obj, val)
        %     idx = obj.ViewState_.C;
        %     obj.ComponentDisplay_(idx).Colormap = double(val);
        % 
        %     % setting Colormap switches mode to LUTs
        %     obj.ViewState_.ComponentColorMode = 'luts';
        % 
        %     obj.updateAllDisplayMaps();
        % 
        %     if obj.ViewState_.ShowComposite
        %         obj.RenderSource_ = obj.getCompositeImage();
        %         obj.refreshView();
        %     else
        %         obj.updateAxesColormap();
        %     end
        % end

        function set.Colormap(obj, val)
            idx = obj.ViewState_.C;
            obj.ComponentDisplay_(idx).Colormap = double(val);
            obj.ComponentColorMode = "luts";


            obj.updateAllDisplayMaps();
            obj.syncRenderSourceToView();
        end

    
        % --- ComponentColorMode ---
        function v = get.ComponentColorMode(obj), v = obj.ViewState_.ComponentColorMode; end
    
        function set.ComponentColorMode(obj, val)
            obj.ViewState_.ComponentColorMode = val;
            obj.updateAllDisplayMaps();
            obj.syncRenderSourceToView();
        end
    
        % --- setCLim ---
        function setCLim(obj, clim, idx)
            arguments
                obj (1,1) matlabx.ui.widgets.ImageAxes
                clim (1,2) double
                idx (:,1) = []
            end
    
            if isempty(idx)
                idx = obj.ComponentIdx;
            end
    
            for k = 1:numel(idx)
                ii = idx(k);
    
                if ii < 1 || ii > obj.NumComponents
                    error('ImageAxes:InvalidComponentIndex', ...
                        'Index %i does not refer to an existing component', ii)
                end
    
                comp = obj.ImageData_.Components(ii);
    
                if strcmp(comp.Kind, 'rgb') || strcmp(comp.Class, 'logical')
                    continue
                end
    
                obj.ComponentDisplay_(ii).CLim = clim;
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


        % --- setColormap ---
        function setColormap(obj, cmap, idx)
            arguments
                obj (1,1) matlabx.ui.widgets.ImageAxes
                cmap (256,3) double
                idx (:,1) = []
            end

            if isempty(idx)
                idx = obj.ComponentIdx;
            end

            if idx < 1 || idx > obj.NumComponents
                error('ImageAxes:InvalidComponentIndex', ...
                    'Index %i does not refer to an existing component', ii)
            end

            obj.ComponentDisplay_(idx).Colormap = double(cmap);
            obj.ComponentColorMode = "luts";

            obj.updateAllDisplayMaps();
            obj.syncRenderSourceToView();

        end


    end

    %% Private helpers: ImageData/DisplayState/ViewState
    methods (Access=private)
    
        function syncViewStateToImageData(obj)
            n = obj.NumComponents;
    
            % clip C, Z, T to valid range
            obj.ViewState_.C = clip(obj.ViewState_.C, 1, n);
            obj.ViewState_.Z = clip(obj.ViewState_.Z, 1, obj.ImageData_.SizeZ);
            obj.ViewState_.T = clip(obj.ViewState_.T, 1, obj.ImageData_.SizeT);
    
            % resize per-component display state while preserving old values
            obj.ComponentDisplay_ = obj.initializeComponentDisplayState(n);
    
            % composite only allowed when mergeable
            if obj.ViewState_.ShowComposite && ~obj.ImageData_.CanMergeComponents
                obj.ViewState_.ShowComposite = false;
            end
        end
    
        function displayState = initializeComponentDisplayState(obj, n)
            old = obj.ComponentDisplay_;

            displayState = repmat(struct( ...
                'CLim', [], ...
                'ColorName', "", ...
                'Color', [], ...
                'Colormap', [], ...
                'DisplayMap', []), 1, n);

            defaultColors = matlabx.ui.widgets.ImageAxes.getColorNames();
    
            % initialize component display state using info from ImageData
            for i = 1:n
                % get next component
                comp = obj.ImageData_.Components(i);

                % flag indicating whether there is a previous display state entry for this component idx
                hasOldEntry = i <= numel(old);

                % CLim
                displayState(i).CLim = comp.DataRange;

                % Color/ColorName
                if ~isempty(comp.Color)
                    displayState(i).Color = comp.Color;
                    displayState(i).ColorName = matlabx.colors.names.fromRGB(comp.Color);
                elseif hasOldEntry && ~isempty(old(i).Color)
                    displayState(i).Color = old(i).Color;
                    displayState(i).ColorName = matlabx.colors.names.fromRGB(old(i).Color);
                else
                    displayState(i).ColorName = string(defaultColors{1 + mod(i-1, numel(defaultColors))});
                    displayState(i).Color = matlabx.colors.names.toRGB(displayState(i).ColorName);
                end

                % LUT/Colormap
                if ~isempty(comp.LUT)
                    % use Component LUT if it exists
                    displayState(i).Colormap = comp.LUT;
                elseif hasOldEntry && ~isempty(old(i).Colormap)
                    % if not, use prior display state, if valid
                    displayState(i).Colormap = old(i).Colormap;
                else
                    % default fallback
                    displayState(i).Colormap = gray(256);
                end

                displayState(i).DisplayMap = obj.getDisplayMap(displayState(i), obj.ViewState_.ComponentColorMode);
            end
        end
    
        function syncRenderSourceToView(obj)
            oldData = obj.RenderSource_;
    
            if obj.ViewState_.ShowComposite
                newData = obj.getCompositeImage();
            else
                newData = obj.ImageData_.getPlane(obj.ViewState_.C,obj.ViewState_.Z,obj.ViewState_.T);
            end
    
            obj.RenderSource_ = newData;
            obj.refreshView();
    
            evtData = matlabx.ui.widgets.events.CDataChangedEventData(oldData, newData);
            notify(obj, 'CDataChanged', evtData);
        end
    
        function updateAllDisplayMaps(obj)
            for i = 1:obj.NumComponents
                obj.ComponentDisplay_(i).DisplayMap = obj.getDisplayMap( ...
                    obj.ComponentDisplay_(i), obj.ViewState_.ComponentColorMode);
            end
        end
    
        function map = getDisplayMap(~, displayState, mode)
            switch mode
                case 'colors'
                    map = matlabx.colors.ops.colorGradient( ...
                        [0 0 0], ...
                        matlabx.colors.names.toRGB(char(displayState.ColorName)), ...
                        256);
                case 'luts'
                    map = displayState.Colormap;
            end
        end
    
        function I = getCompositeImage(obj)
            if ~obj.ImageData_.CanMergeComponents
                I = obj.ImageData_.getPlane(obj.ViewState_.C,obj.ViewState_.Z,obj.ViewState_.T);
                return
            end
    
            if ~strcmp(obj.ImageData_.MultiComponentKind, 'scalar')
                I = obj.ImageData_.getPlane(obj.ViewState_.C,obj.ViewState_.Z,obj.ViewState_.T);
                return
            end
    
            data = cell(1, obj.NumComponents);
            clims = zeros(obj.NumComponents, 2);
    
            for c = 1:obj.NumComponents
                data{c} = obj.ImageData_.getPlane(c,obj.ViewState_.Z,obj.ViewState_.T);
                clims(c,:) = obj.ComponentDisplay_(c).CLim;
            end
    
            switch obj.ViewState_.ComponentColorMode
                case 'colors'
                    colors = zeros(obj.NumComponents, 3);
                    for i = 1:obj.NumComponents
                        colors(i,:) = matlabx.colors.names.toRGB(char(obj.ComponentDisplay_(i).ColorName));
                    end
                    I = matlabx.image.compose.mergeChannelsRGB_add(data, clims, colors);
    
                case 'luts'
                    maps = {obj.ComponentDisplay_.DisplayMap};
                    I = matlabx.image.compose.mergeChannelsRGB_LUT(data, clims, maps);
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

        % FontSize
        function set.FontSize(obj,val)
            obj.FontSize_ = val;
            obj.updateFontSizes();
            obj.updateOnResize();
        end

        function v = get.FontSize(obj)
            v = obj.FontSize_;
        end

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

            if E.StopPropagation, return; end

            obj.onDown_(E);
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
                case 'shift+meta+m'
                    obj.toggleComposite();
                case 'shift+meta+c'
                    obj.openContrastTool();
                case 'rightarrow'
                    obj.nextComponent();
                case 'leftarrow'
                    obj.previousComponent();
                case 'uparrow'
                    obj.nextZ();
                case 'downarrow'
                    obj.previousZ();
                case 'shift+rightarrow'
                    obj.nextT();
                case 'shift+leftarrow'
                    obj.previousT();
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

    %% Internal behaviors
    methods (Access=private)

        % executes on mouse move after Distractors/Interceptors
        function onMouseMove(obj)
            obj.updateBottomLabelText();
            obj.updatePointer();
        end

        function onDown_(obj,E)
            if strcmp(E.SelectionType,'alt')
                XY = E.CurrentPointFigure;
                open(obj.ContextMenu,XY(1),XY(2));
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

    %% Tool event routing
    methods

        function routeEventToTools(obj,E)
            skipInterceptor = obj.routeToDistractors(E);
            if skipInterceptor
                E.StopPropagation = true;
                return; 
            end

            % get highest priority Interceptor for event kind
            t = obj.getPriorityInterceptor(E.Kind);
            % forward event to the tool
            if ~isempty(t)
                t.("on"+E.Kind)(E);
                E.StopPropagation = true;
            end
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

    %% Popup window management
    methods

        % --- ContrastTool ---

        function openContrastTool(obj)

            if obj.contrastToolOpen
                return
            end

            N = obj.NumComponents;

            sliderName = cell(1,N);
            sliderLimits = cell(1,N);
            sliderValue = cell(1,N);
            sliderRoundDigits = cell(1,N);
            sliderRoundValues = cell(1,N);
            sliderValueDisplayFormat = cell(1,N);
            sliderColormap = cell(1,N);

            for i = 1:obj.NumComponents

                comp = obj.ImageData_.Components(i);
                compDisplay = obj.ComponentDisplay_(i);

                switch comp.Kind
                    case 'scalar'
                        switch comp.Class
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

                sliderName{i} = comp.Name;
                sliderLimits{i} = comp.DataRange;
                sliderValue{i} = compDisplay.CLim;
                sliderRoundDigits{i} = 0;
                sliderRoundValues{i} = roundVals;
                sliderValueDisplayFormat{i} = dispFmt;
                sliderColormap{i} = compDisplay.DisplayMap;
            end

            obj.contrastTool = matlabx.app.SliderGroupDialog(...
                N,...
                "Title","Adjust display limits",...
                "Name",sliderName,...
                "Limits",sliderLimits,...
                "Value",sliderValue,...
                "RoundDigits",sliderRoundDigits,...
                "RoundValues",sliderRoundValues,...
                "ValueDisplayFormat",sliderValueDisplayFormat,...
                "Colormap",sliderColormap,...
                "ValueChangingFcn",@(o,e) obj.onContrastToolValueChanging(o,e),...
                "ValueChangedFcn",@(o,e) obj.onContrastToolValueChanged(o,e),...
                "ClosedFcn",@(~,~) obj.onContrastToolClosed());

            obj.contrastToolOpen = true;
        end

        function onContrastToolClosed(obj)
            obj.contrastToolOpen = false;
        end

        function onContrastToolValueChanged(obj,o,e)
            obj.setCLim(o.Value,e.ID);
        end

        function onContrastToolValueChanging(obj,o,e)
            obj.setCLim(o.Value,e.ID);
        end

        % --- MetadataWindow ---
        function openMetadataWindow(obj)
            if obj.metadataWindowOpen
                return
            end

            % metadata = obj.ImageData_.OriginalMetadata;
            % metadataLines = cellstr(matlabx.struct.prettyPrint(metadata));
            % 
            % obj.metadataWindow = matlabx.app.TextWindow( ...
            %     "Title","Metadata", ...
            %     "Text",metadataLines, ...
            %     "ClosedFcn",@(~,~) obj.onMetadataWindowClosed());

            metadata = obj.ImageData_.AllMetadata;
            metadataLines = cellstr(matlabx.struct.prettyPrint(metadata));

            obj.metadataWindow = matlabx.app.TextWindow( ...
                "Title","Metadata", ...
                "Text",metadataLines, ...
                "ClosedFcn",@(~,~) obj.onMetadataWindowClosed());

        end

        function onMetadataWindowClosed(obj)
            obj.metadataWindowOpen = false;
        end

    end


    %% Context menu callbacks
    methods

        function setComponentColorMode(obj,mode)
            obj.ComponentColorMode = mode;
        end






    end



    %% Hidden entrypoint for debugging
    methods (Hidden)
        function DEBUG_(obj)
            debug
        end
    end


    %% Private static helpers
    methods (Static, Access=private)

        function tf = isNonEmptyText(x)
            % check if text is non-empty
            tf = (ischar(x) || (isstring(x) && isscalar(x))) && strlength(string(x)) > 0;
        end

        function tf = isInLimits(XY,XLim,YLim)
            % check if the point, XY, is within limits, XLim and YLim
            x = XY(1); y = XY(2);
            tf = x >= XLim(1) && x <= XLim(2) && y >= YLim(1) && y <= YLim(2);
        end

        function I = placeholderImage()
            % return a placeholder image for startup
            I = zeros([256,256,3]); % all black truecolor array
        end

        function [ticks,labels] = getColorbarTickLabels(valClass,clim,N)
            % get colorbar ticks and labels based on CData class and display range
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

    %% Public static helpers
    methods (Static)

        function names = getToolClassNames()
            % get cell array of char vectors of tool class names in matlabx.ui.widgets.tools
            names = {matlab.metadata.Namespace.fromName("matlabx.ui.widgets.tools").ClassList.Name}';
        end

        function names = getToolNames()
            % return names of all tool classes (just the last part)

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

        function names = getColorNames()
            % return names of allowed component colors
            names = {'cyan','magenta','yellow','red','green','blue'};
        end


        function ax = demo(name)
            arguments
                name (1,:) char {mustBeMember(name,{'default','multicomponent','empty'})}
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
                case 'multicomponent'
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

            % metadata window
            if ~isempty(obj.metadataWindow), delete(obj.metadataWindow(isvalid(obj.metadataWindow))); end


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
