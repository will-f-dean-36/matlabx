classdef ImageAxes < matlab.ui.componentcontainer.ComponentContainer
%IMAGEAXES Image5D-backed UI image display and interaction component.
%
%   matlabx.ui.widgets.ImageAxes displays a selected 2-D plane or RGB
%   composite from a matlabx.image.Image5D object. It also hosts
%   ImageAxesTool subclasses and receives figure-level mouse/key events
%   through matlabx.ui.control.FigureEventHub.
%
%   Data terminology
%   ----------------
%   ImageData      Canonical source image object. Prefer this for new code.
%   RenderSource   Current selected source plane or computed RGB composite.
%   DisplayCData   Graphics-ready data assigned to the MATLAB image object.
%                  Scalar RenderSource data are contrast-rescaled here.
%   CData          Compatibility alias for setting ImageData from raw MATLAB
%                  image arrays/cells. New code should prefer ImageData.
%
%   Notes
%   -----
%   If multiple ImageAxes instances share a figure, give each a unique Name
%   so figure-event hit testing can distinguish their axes/toolbars.


    %% Tools

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

    %% Public configuration
    properties (AbortSet)
        Name (1,1) string = ""
    end

    % Graphics passthroughs
    properties (Dependent)
        ImageVisible
        AxesVisible
        ColorbarVisible
        Colormap (256,3) double
        MaxRenderedResolution
    end

    %% Image model, render state, and display state

    % Canonical image data and compatibility input.
    properties (Dependent, AbortSet)
        ImageData           (1,1) matlabx.image.Image5D
        CData               {mustBeA(CData,{'double','single','uint8','uint16','logical','cell'})}
    end

    % Observable view/display controls.
    properties (Dependent, AbortSet, SetObservable)
        C (1,1) double
        Z (1,1) double
        T (1,1) double
        ShowComposite       (1,1) matlab.lang.OnOffSwitchState
        CLim                (1,2) double
        CLimMode            (1,:) char {mustBeMember(CLimMode,{'auto','manual'})}
        ComponentCLims      (1,:) cell
        ComponentColors     (1,:) cell
        ComponentColormaps  (1,:) cell
        ComponentColorMode  (1,:) char {mustBeMember(ComponentColorMode,{'colors','luts'})}
    end

    % Read-only render/display information.
    properties (Dependent, SetAccess=private)
        RenderSource
        RenderSourceKind       (1,:) char {mustBeMember(RenderSourceKind,{'scalar','rgb'})}
        RenderSourceSize       (1,:) double
        RenderSourceClass      (1,:) char {mustBeMember(RenderSourceClass,{'double','single','uint8','uint16','logical',''})}
        DisplayCData
        CanMergeComponents  (1,1) logical

        % Compatibility aliases for RenderSource* metadata.
        CDataKind       (1,:) char {mustBeMember(CDataKind,{'scalar','rgb'})}
        CDataSize       (1,:) double
        CDataClass      (1,:) char {mustBeMember(CDataClass,{'double','single','uint8','uint16','logical',''})}
        
        NumComponents         (1,1) double
        MultiComponent        (1,1) matlab.lang.OnOffSwitchState
        MultiComponentKind    (1,:) {mustBeMember(MultiComponentKind,{'scalar','rgb','mixed','none'})}
    end

    properties (Access=private)
        % Current view coordinates and display modes.
        ViewState_ struct = struct( ...
            'C', 1, ...
            'Z', 1, ...
            'T', 1, ...
            'ShowComposite', false, ...
            'CLimMode', 'auto', ...
            'ComponentColorMode', 'colors');

        % Canonical Image5D data model.
        ImageData_ (1,1) matlabx.image.Image5D = matlabx.image.Image5D.fromComponents(zeros(256,256,3))

        % Selected source plane or computed composite, before display scaling.
        RenderSource_ (:,:,:) = matlabx.ui.widgets.ImageAxes.placeholderImage

        % Per-component contrast/color/LUT display state.
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
        % UI components
        Grid matlab.ui.container.GridLayout
        Panel matlab.ui.container.Panel
        staticAxes matlab.ui.control.UIAxes
        hImage matlab.graphics.primitive.Image
        BottomLabel (1,1) matlab.graphics.primitive.Text
        Colorbar matlab.graphics.illustration.ColorBar
        sizingGrid matlab.ui.container.GridLayout
        ViewBoxFull (1,1) matlab.graphics.primitive.Patch
        ViewBoxZoom (1,1) matlab.graphics.primitive.Patch


        % listeners
        L event.listener

        % structs of extra UI handles that do not have a named property
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

    properties (Access=private)
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
        RenderSourceChanged
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

            obj.Panel.Title = "";

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

            % set up ViewBox patches
            obj.ViewBoxFull = patch(obj.staticAxes, ...
                'XData',NaN, ...
                'YData',NaN, ...
                'EdgeColor',obj.ViewBoxEdgeColor, ...
                'FaceColor',obj.ViewBoxFaceColor, ...
                'FaceAlpha',obj.ViewBoxFaceAlpha, ...
                'HitTest','on', ...
                'PickableParts','all', ...
                'LineWidth', obj.ViewBoxLineWidth, ...
                'Tag','ViewBoxFull');
            obj.ViewBoxZoom = patch(obj.staticAxes, ...
                'XData',NaN, ...
                'YData',NaN, ...
                'EdgeColor',obj.ViewBoxEdgeColor, ...
                'FaceColor',obj.ViewBoxFaceColor, ...
                'FaceAlpha',obj.ViewBoxFaceAlpha, ...
                'HitTest','on', ...
                'PickableParts','all', ...
                'LineWidth', obj.ViewBoxLineWidth, ...
                'Tag','ViewBoxZoom');           

            % set up ContextMenu
            obj.setupContextMenu();

            % initialize display state from ImageData
            obj.syncViewStateToImageData();
            
            % initial render
            obj.syncRenderSourceToView(ResetView=true);
        end

        function update(obj)
            if obj.inStartup
                obj.FontSize_ = obj.FontSize;
                obj.uipanelOverheadPx_ = obj.UICal.uipanelTopChromeHeightPx(obj.FontSize_);
                obj.inStartup = false;
                obj.updateOnResize();
            end

            % set the Tag property of the axes used for event routing
            obj.mainAxes.Tag = obj.Name;
            obj.staticAxes.Tag = obj.Name;

            % set BackgroundColor
            obj.Grid.BackgroundColor = obj.BackgroundColor;
            % obj.Panel.BackgroundColor = obj.BackgroundColor;

            obj.sizingGrid.BackgroundColor = obj.BackgroundColor;

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



    %% Zoom / cursor-follow navigation
    %
    % ImageAxes represents the visible zoomed region as ordinary image axes
    % limits on mainAxes:
    %
    %   XLim = [xLower, xLower + viewWidth]
    %   YLim = [yLower, yLower + viewHeight]
    %
    % A ZoomLevel is the fraction of the full image currently visible. Thus
    % ZoomLevel==1 displays the full image, while ZoomLevel==0.5 is a 2x zoom
    % showing half the image width and height.
    %
    % Cursor-follow navigation uses staticAxes, whose limits stay fixed to the
    % full image. The cursor position in staticAxes is normalized and mapped to
    % the available travel of the zoomed view box. FollowCursorLims define the
    % active normalized control interval. Positions outside that interval act as
    % dead zones and pin the view to the corresponding image edge.
    %
    % To avoid a jump when FollowCursor is re-enabled at a new cursor location,
    % the current cursor/view relationship is stored as a per-axis anchor. The
    % mapping then interpolates smoothly from that anchor to the reachable edges.
    % Once an axis reaches a follow bound, that axis releases its anchor and
    % returns to the ordinary absolute cursor-follow mapping.

    properties (Access=private)
        % Zoom_ stores the discrete zoom state. Levels are visible-image
        % fractions, not magnification factors. LastCursorXY is in mainAxes image
        % coordinates and is used as a fallback anchor when enabling zoom with no
        % active cursor over the image.
        Zoom_ = struct( ...
            'Idx', 1, ...
            'Levels', [1 1/2 1/3 1/4 1/5 1/10 1/15 1/20], ...
            'LastCursorXY', [], ...
            'Enabled', false)

        % FollowCursor_ stores cursor-follow state. Lims are normalized staticAxes
        % control bounds. AnchorNorm/AnchorLower are per-axis no-jump anchors;
        % NaN/empty means the axis uses absolute mapping. LastCursorXY is in
        % staticAxes full-image coordinates.
        FollowCursor_ = struct( ...
            'Lims', [0.10 0.90], ...
            'Enabled', true, ...
            'AnchorNorm', [], ...
            'AnchorLower', [], ...
            'LastCursorXY', [])

        % ViewBoxBase_ stores miniature overview geometry on staticAxes. XFull/YFull
        % draw the full-image box. XZoomBase/YZoomBase draw a zero-offset zoom box
        % sized for the current ZoomLevel; applyZoomLims shifts that base according
        % to the actual view lower limits.
        ViewBoxBase_ = struct( ...
            'Top', [], ...
            'Left', [], ...
            'XBase', [], ...
            'YBase', [], ...
            'XFull', [], ...
            'YFull', [], ...
            'XZoomBase', [], ...
            'YZoomBase', [])
    end

    properties (Dependent)
        ZoomEnabled
        ZoomLevel
        ZoomFactor

        FollowCursorEnabled
        FollowCursorLims
    end

    % ViewBox appearance
    properties
        ViewBoxSize = 0.1
        ViewBoxEdgeColor = [0 0 0]
        ViewBoxFaceColor = [1 1 1]
        ViewBoxFaceAlpha = 0.25
        ViewBoxLineWidth = 1

        ViewBoxTop = 0.05
        ViewBoxLeft = 0.01
    end

    % Private zoom / cursor-follow helpers
    methods
        function followCursor(obj)
            %FOLLOWCURSOR  Move the zoom view according to static-axes cursor position.

            XY = obj.cursorPositionStatic;

            if isempty(XY)
                return
            end

            obj.applyFollowCursorLims(XY);
        end

        function zoomViewToCursor(obj)
            %ZOOMVIEWTOCURSOR  Change zoom while preserving the pixel under the cursor

            XY = obj.cursorPosition;

            if isempty(XY)
                return
            end

            % These are still the limits from the previous zoom level because the
            % axes limits have not yet been updated.
            oldXLim = obj.mainAxes.XLim;
            oldYLim = obj.mainAxes.YLim;

            obj.applyCursorAnchoredZoomLims(XY,oldXLim,oldYLim);
        end

        function [XLim,YLim] = getFollowCursorLims(obj,XY)
            %GETFOLLOWCURSORLIMS  Calculate cursor-following zoom limits
            %
            %   [XLim,YLim] = getFollowCursorLims(obj,XY) maps XY from the
            %   full-sized static axes into the available cursor-follow range.
            %   FollowCursorLims define the active normalized cursor interval; values
            %   outside this interval form dead zones that pin the view to the image
            %   edges.
            %
            %   XY must be expressed in the coordinate system of the full-sized static
            %   axes.

            arguments
                obj
                XY (1,2) double
            end

            % Image dimensions
            sz = obj.RenderSourceSize;
            H = sz(1);
            W = sz(2);

            % Current zoomed-window dimensions
            viewWidth  = obj.ZoomLevel * W;
            viewHeight = obj.ZoomLevel * H;

            % Full image limits
            defXLim = [0.5, W + 0.5];
            defYLim = [0.5, H + 0.5];

            % Calculate the lower limits from the static cursor.
            lower = obj.getFollowCursorLowerLimit(XY);

            % Constrain the view to the full image
            lower(1) = min(max(lower(1),defXLim(1)), ...
                defXLim(2) - viewWidth);

            lower(2) = min(max(lower(2),defYLim(1)), ...
                defYLim(2) - viewHeight);

            % Construct limits
            XLim = lower(1) + [0,viewWidth];
            YLim = lower(2) + [0,viewHeight];
        end

        function [XLim,YLim] = getCursorAnchoredZoomLims(obj,XY,oldXLim,oldYLim)
            %GETCURSORANCHOREDZOOMLIMS  Calculate cursor-anchored zoom limits
            %
            %   [XLim,YLim] = getCursorAnchoredZoomLims(obj,XY,oldXLim,oldYLim)
            %   returns axes limits for the current ZoomLevel such that image
            %   coordinate XY remains under the same relative cursor position as it
            %   occupied in oldXLim/oldYLim. This is the click/scroll zoom behavior:
            %
            %       - clicking at the current view center keeps the view centered
            %       - clicking off-center shifts the view so the clicked pixel stays
            %         under the cursor as much as image bounds allow
            %       - bounds clamping necessarily breaks the invariant near edges
            %
            %   XY must be expressed in image/data coordinates.

            arguments
                obj
                XY (1,2) double
                oldXLim (1,2) double
                oldYLim (1,2) double
            end

            % Image dimensions
            sz = obj.RenderSourceSize;
            H = sz(1);
            W = sz(2);

            % Full image limits
            defXLim = [0.5, W + 0.5];
            defYLim = [0.5, H + 0.5];

            % New visible dimensions
            newWidth  = obj.ZoomLevel * W;
            newHeight = obj.ZoomLevel * H;

            % Cursor position within the current visible window
            xFrac = (XY(1) - oldXLim(1)) / diff(oldXLim);
            yFrac = (XY(2) - oldYLim(1)) / diff(oldYLim);

            % Guard against a cursor coordinate slightly outside the axes
            xFrac = min(max(xFrac,0),1);
            yFrac = min(max(yFrac,0),1);

            % Preserve the cursor's fractional position within the view
            xLower = XY(1) - xFrac * newWidth;
            yLower = XY(2) - yFrac * newHeight;

            % Constrain the view to the full image
            xLower = min(max(xLower,defXLim(1)), ...
                defXLim(2) - newWidth);

            yLower = min(max(yLower,defYLim(1)), ...
                defYLim(2) - newHeight);

            % Construct limits
            XLim = xLower + [0,newWidth];
            YLim = yLower + [0,newHeight];
        end

        function lower = getFollowCursorLowerLimit(obj,XY)
            %GETFOLLOWCURSORLOWERLIMIT  Map static cursor position to view lower limit
            %
            %   lower = getFollowCursorLowerLimit(obj,XY) returns the lower-left
            %   image coordinate of the zoomed view box implied by the current
            %   static-axes cursor coordinate XY.
            %
            %   Without an active anchor, this is the absolute mapping:
            %
            %       FollowCursorLims(1) -> image top/left edge
            %       FollowCursorLims(2) -> image bottom/right edge
            %
            %   With an active per-axis anchor, the function instead preserves the
            %   cursor/view relationship that existed when FollowCursor was enabled
            %   or recalibrated. Each axis interpolates from that anchor toward its
            %   reachable edges, then releases the anchor after it reaches a follow
            %   bound. Released axes use absolute mapping again.

            % Image dimensions
            sz = obj.RenderSourceSize;
            H = sz(1);
            W = sz(2);

            % Current zoomed-window dimensions
            viewWidth  = obj.ZoomLevel * W;
            viewHeight = obj.ZoomLevel * H;

            % Available travel of the zoomed view
            travel = [W - viewWidth, H - viewHeight];

            % Follow-cursor limits in normalized static-axes coordinates.
            % Values outside this interval form the cursor-follow dead zones.
            [XYNorm, followCursorLims] = obj.getFollowCursorNormalizedPosition(XY);
            a = followCursorLims(1);
            b = followCursorLims(2);

            if b <= a
                error('FollowCursorLims must contain two increasing values.')
            end

            lowerMin = [0.5,0.5];
            lowerMax = lowerMin + travel;

            [anchorNorm, anchorLower] = obj.getFollowCursorAnchor();

            % Anchored mapping: preserve the current cursor/view relationship when
            % follow-cursor is enabled, then interpolate smoothly from that anchor
            % to the reachable image edges. Each axis releases its anchor after it
            % reaches a follow bound, returning that axis to absolute mapping with no
            % position jump.
            XYNorm = min(max(XYNorm,0),1);

            lower = zeros(1,2);
            releasedAnchor = false(1,2);

            for k = 1:2
                if ~isfinite(anchorNorm(k)) || ~isfinite(anchorLower(k))
                    n = min(max(XYNorm(k),a),b);
                    followFrac = (n - a) / (b - a);
                    lower(k) = lowerMin(k) + followFrac * travel(k);
                    continue
                end

                leftNorm = a;
                rightNorm = b;

                if anchorNorm(k) < a
                    leftNorm = 0;
                elseif anchorNorm(k) > b
                    rightNorm = 1;
                end

                n = min(max(XYNorm(k),leftNorm),rightNorm);
                anchor = min(max(anchorNorm(k),leftNorm),rightNorm);
                anchorLower(k) = min(max(anchorLower(k),lowerMin(k)),lowerMax(k));

                if n <= anchor
                    denom = anchor - leftNorm;
                    if denom <= eps
                        lower(k) = anchorLower(k);
                    else
                        t = (n - leftNorm) / denom;
                        lower(k) = lowerMin(k) + t * (anchorLower(k) - lowerMin(k));
                    end
                else
                    denom = rightNorm - anchor;
                    if denom <= eps
                        lower(k) = anchorLower(k);
                    else
                        t = (n - anchor) / denom;
                        lower(k) = anchorLower(k) + t * (lowerMax(k) - anchorLower(k));
                    end
                end

                if n <= leftNorm + eps || n >= rightNorm - eps
                    releasedAnchor(k) = true;
                end
            end

            if any(releasedAnchor)
                anchorNorm(releasedAnchor) = NaN;
                anchorLower(releasedAnchor) = NaN;
                obj.FollowCursor_.AnchorNorm = anchorNorm;
                obj.FollowCursor_.AnchorLower = anchorLower;
            end
        end

        function [XYNorm, followCursorLims] = getFollowCursorNormalizedPosition(obj,XY)
            %GETFOLLOWCURSORNORMALIZEDPOSITION  Normalize static cursor for follow mode.

            sz = obj.RenderSourceSize;
            H = sz(1);
            W = sz(2);

            XYNorm = (XY - 0.5) ./ [W,H];
            followCursorLims = obj.FollowCursorLims;
        end

        function calibrateFollowCursorAnchor(obj,XYStatic)
            %CALIBRATEFOLLOWCURSORANCHOR  Anchor follow-cursor at current view
            %
            %   calibrateFollowCursorAnchor(obj,XYStatic) records a no-jump anchor
            %   that maps the current static-axes cursor location to the current
            %   mainAxes lower limits. This lets FollowCursor be disabled, the mouse
            %   moved elsewhere, and FollowCursor re-enabled without immediately
            %   snapping the view box to the absolute cursor-follow mapping.
            %
            %   The anchor is per-axis and may later release independently in
            %   getFollowCursorLowerLimit after reaching the corresponding follow
            %   bound.

            if isempty(XYStatic)
                obj.clearFollowCursorAnchor();
                return
            end

            [XYNorm, ~] = obj.getFollowCursorNormalizedPosition(XYStatic);
            currentLower = [obj.mainAxes.XLim(1), obj.mainAxes.YLim(1)];

            obj.FollowCursor_.AnchorNorm = XYNorm;
            obj.FollowCursor_.AnchorLower = currentLower;
            obj.FollowCursor_.LastCursorXY = XYStatic;
        end

        function [anchorNorm, anchorLower] = getFollowCursorAnchor(obj)
            %GETFOLLOWCURSORANCHOR  Return per-axis cursor-follow anchors.
            %
            %   anchorNorm is the normalized static-axes cursor position at which
            %   the anchor was created. anchorLower is the corresponding mainAxes
            %   lower limit. NaN means the axis has no active anchor and should use
            %   absolute cursor-follow mapping.

            anchorNorm = obj.FollowCursor_.AnchorNorm;
            anchorLower = obj.FollowCursor_.AnchorLower;

            if ~isnumeric(anchorNorm) || numel(anchorNorm) ~= 2
                anchorNorm = [NaN,NaN];
            end

            if ~isnumeric(anchorLower) || numel(anchorLower) ~= 2
                anchorLower = [NaN,NaN];
            end
        end

        function clearFollowCursorAnchor(obj)
            %CLEARFOLLOWCURSORANCHOR  Clear the no-jump cursor-follow anchor.

            obj.FollowCursor_.AnchorNorm = [NaN,NaN];
            obj.FollowCursor_.AnchorLower = [NaN,NaN];
            obj.FollowCursor_.LastCursorXY = [];
        end

        function applyFollowCursorLims(obj,XY)
            %APPLYFOLLOWCURSORLIMS  Apply cursor-following zoom limits
            %
            %   applyFollowCursorLims(obj,XY) computes the zoomed view-box limits
            %   implied by static-axes cursor coordinate XY, applies them to mainAxes,
            %   updates the miniature view box, and logs the mapping when debug output
            %   is enabled.
            %
            %   XY must be expressed in full-sized static-axes coordinates, not in
            %   the current zoomed mainAxes coordinate system.

            if nargin < 2 || isempty(XY)
                XY = obj.cursorPositionStatic;
            end

            if isempty(XY)
                return
            end

            [XZoomLim,YZoomLim] = obj.getFollowCursorLims(XY);
            obj.applyZoomLims(XZoomLim,YZoomLim);

            % This field now always contains static-axes coordinates
            obj.FollowCursor_.LastCursorXY = XY;
        end

        function applyCursorAnchoredZoomLims(obj,XY,oldXLim,oldYLim)
            %APPLYCURSORANCHOREDZOOMLIMS  Apply a zoom step around image coordinate XY
            %
            %   applyCursorAnchoredZoomLims(obj,XY,oldXLim,oldYLim) applies the
            %   current ZoomLevel using oldXLim/oldYLim as the pre-zoom visible view.
            %   It preserves XY at the same relative position inside the view where
            %   possible, then recalibrates the follow-cursor anchor so the next
            %   cursor-follow move does not jump.
            %
            %   XY must be expressed in image/data coordinates from mainAxes.

            if nargin < 2 || isempty(XY)
                XY = obj.cursorPosition;
            end

            if isempty(XY)
                return
            end

            if nargin < 3 || isempty(oldXLim)
                oldXLim = obj.mainAxes.XLim;
            end

            if nargin < 4 || isempty(oldYLim)
                oldYLim = obj.mainAxes.YLim;
            end

            [XZoomLim,YZoomLim] = ...
                obj.getCursorAnchoredZoomLims(XY,oldXLim,oldYLim);

            obj.applyZoomLims(XZoomLim,YZoomLim);

            % This field now always contains image/data coordinates
            obj.Zoom_.LastCursorXY = XY;

            if obj.ZoomEnabled && obj.FollowCursorEnabled
                obj.calibrateFollowCursorAnchor(obj.cursorPositionStatic);
            end
        end

        function applyZoomLims(obj,XLim,YLim)
            %APPLYZOOMLIMS  Apply axes limits and synchronize the zoom view box.
            %
            %   applyZoomLims(obj,XLim,YLim) is the final common sink for both
            %   cursor-anchored zoom and cursor-follow motion. It updates mainAxes
            %   limits, then shifts the miniature ViewBoxZoom patch so the overview
            %   reflects the same lower-left image coordinate.
            %
            %   XLim/YLim are pixel-centered image limits, where the full image is:
            %
            %       XLim = [0.5, W + 0.5]
            %       YLim = [0.5, H + 0.5]

            set(obj.mainAxes,...
                'XLim',XLim,...
                'YLim',YLim);

            % Update inner view box
            XZoomBase = obj.ViewBoxBase_.XZoomBase;
            YZoomBase = obj.ViewBoxBase_.YZoomBase;

            set(obj.ViewBoxZoom,...
                "XData",XZoomBase + (XLim(1) - 0.5)*obj.ViewBoxSize,...
                "YData",YZoomBase + (YLim(1) - 0.5)*obj.ViewBoxSize);
        end

        function updateViewBoxBaseCoordinates(obj)
            %UPDATEVIEWBOXBASECOORDINATES  Update miniature overview geometry.
            %
            %   Recomputes the staticAxes patch coordinates used for the full-image
            %   overview box and the current-size zoom box. The zoom box stored here
            %   is intentionally zero-offset relative to the image; applyZoomLims
            %   translates it based on XLim(1)/YLim(1).
            %
            %   This must be called when the rendered image size or ZoomLevel changes.

            sz = obj.RenderSourceSize;
            H = sz(1);
            W = sz(2);

            S = struct();

            S.Top  = (obj.ViewBoxTop  * H) + 0.5;
            S.Left = (obj.ViewBoxLeft * W) + 0.5;

            S.XBase = [0,0,W,W] .* obj.ViewBoxSize;
            S.YBase = [0,H,H,0] .* obj.ViewBoxSize;

            S.XFull = S.XBase + S.Left;
            S.YFull = S.YBase + S.Top;

            zoomLevel = obj.ZoomLevel;

            S.XZoomBase = S.XBase .* zoomLevel + S.Left;
            S.YZoomBase = S.YBase .* zoomLevel + S.Top;

            % Update coordinates struct
            obj.ViewBoxBase_ = S;

            % Always update full-size box when coordinates change
            set(obj.ViewBoxFull,...
                "XData",S.XFull,...
                "YData",S.YFull);
        end

    end

    % Public zoom / cursor-follow API
    methods

        function z = get.ZoomEnabled(obj)
            %ZOOMENABLED  True when mainAxes displays a zoomed view box.
            %
            %   Setting ZoomEnabled=true shows the miniature view boxes and applies
            %   the current ZoomLevel around the cursor when possible. Setting it
            %   false hides view boxes and restores full-image limits.

            z = obj.Zoom_.Enabled;
        end

        function set.ZoomEnabled(obj,tf)
            %ZOOMENABLED  Enable or disable zoom navigation.

            if tf
                obj.enableZoom();
            else
                obj.disableZoom();
            end
        end

        function p = get.FollowCursorEnabled(obj)
            %FOLLOWCURSORENABLED  True when the zoomed view follows cursor motion.
            %
            %   FollowCursor only affects motion while ZoomEnabled is true. When
            %   re-enabled, the current cursor/view relationship is anchored so the
            %   view does not jump to the absolute cursor-follow position.

            p = obj.FollowCursor_.Enabled;
        end

        function set.FollowCursorEnabled(obj,tf)
            %FOLLOWCURSORENABLED  Enable or disable cursor-follow navigation.

            if tf
                obj.enableFollowCursor();
            else
                obj.disableFollowCursor();
            end
        end

        function p = get.FollowCursorLims(obj)
            %FOLLOWCURSORLIMS  Normalized cursor-follow active interval.
            %
            %   FollowCursorLims is a two-element vector [a b] in normalized
            %   staticAxes coordinates. For each axis:
            %
            %       cursor norm <= a  -> view box pinned to top/left edge
            %       cursor norm >= b  -> view box pinned to bottom/right edge
            %       a < norm < b      -> view box interpolates through image travel
            %
            %   Wider intervals such as [0.10 0.90] produce a gentler control feel
            %   and make anchor release less noticeable. Narrower intervals make the
            %   view reach image edges with less cursor travel.

            p = obj.FollowCursor_.Lims;
        end

        function set.FollowCursorLims(obj,lims)
            %FOLLOWCURSORLIMS  Set cursor-follow active interval.
            %
            %   If zoom and cursor-follow are currently active, changing the limits
            %   recalibrates the anchor at the current cursor position so the view
            %   does not jump immediately after the setting changes.

            obj.FollowCursor_.Lims = lims;

            if obj.ZoomEnabled && obj.FollowCursorEnabled
                obj.calibrateFollowCursorAnchor(obj.cursorPositionStatic);
            end
        end

        function z = get.ZoomLevel(obj)
            %ZOOMLEVEL  Fraction of the full image visible in the zoomed view.
            %
            %   ZoomLevel==1 means the full image is visible. ZoomLevel==0.5 means
            %   the view box is half the image width and height, corresponding to a
            %   2x visual zoom.

            z = obj.Zoom_.Levels(obj.Zoom_.Idx);
        end

        function f = get.ZoomFactor(obj)
            %ZOOMFACTOR  Visual magnification factor, equal to 1/ZoomLevel.

            f = 1 / obj.ZoomLevel;
        end

        function enableZoom(obj)
            %ENABLEZOOM  Enable zoom navigation.
            %
            %   Shows the full-image and zoomed-view miniature boxes, then applies
            %   the current ZoomLevel around the best available anchor:
            %
            %       1. current image-space cursor position in mainAxes
            %       2. most recent image-space zoom anchor
            %       3. image center
            %
            %   If FollowCursor is already enabled, a follow-cursor anchor is
            %   calibrated afterward so the next mouse move does not jump.

            if obj.ZoomEnabled
                return
            end

            % Update view-box base coordinates for the current zoom level
            obj.updateViewBoxBaseCoordinates();

            % Show view boxes
            set([obj.ViewBoxFull,obj.ViewBoxZoom],...
                "Visible","on");

            oldXLim = obj.mainAxes.XLim;
            oldYLim = obj.mainAxes.YLim;

            % Prefer the current image coordinate under the cursor
            XY = obj.cursorPosition;

            % Fall back to the most recent image-space zoom anchor
            if isempty(XY) && isfield(obj.Zoom_,'LastCursorXY')
                XY = obj.Zoom_.LastCursorXY;
            end

            % Final fallback: center of the image
            if isempty(XY)
                sz = obj.RenderSourceSize;
                XY = [(sz(2) + 1)/2, (sz(1) + 1)/2];
            end

            obj.applyCursorAnchoredZoomLims(XY,oldXLim,oldYLim);

            obj.Zoom_.Enabled = true;

            if obj.FollowCursorEnabled
                obj.calibrateFollowCursorAnchor(obj.cursorPositionStatic);
            end
        end

        function disableZoom(obj)
            %DISABLEZOOM  Disable zoom navigation and restore full-image view.

            if ~obj.ZoomEnabled
                return
            end

            % Clear and hide patches
            if isvalid(obj.ViewBoxFull)
                set(obj.ViewBoxFull,...
                    "XData",NaN,...
                    "YData",NaN,...
                    "Visible","off");
            end

            if isvalid(obj.ViewBoxZoom)
                set(obj.ViewBoxZoom,...
                    "XData",NaN,...
                    "YData",NaN,...
                    "Visible","off");
            end

            % Restore limits
            obj.restoreDefaultLimits();

            obj.clearFollowCursorAnchor();

            obj.Zoom_.Enabled = false;
        end

        function toggleZoomEnabled(obj)
            %TOGGLEZOOMENABLED  Flip state of ZoomEnabled.

            obj.ZoomEnabled = ~obj.Zoom_.Enabled;
        end

        function increaseZoom(obj)
            %INCREASEZOOM  Step forward to the next ZoomLevel.
            %
            %   The new view is anchored around the current image-space cursor
            %   position so the pixel under the cursor remains under the cursor as
            %   much as image bounds allow.

            oldIdx = obj.Zoom_.Idx;

            obj.Zoom_.Idx = min(...
                obj.Zoom_.Idx + 1,...
                numel(obj.Zoom_.Levels));

            % Do nothing if already at the final zoom level
            if obj.Zoom_.Idx == oldIdx
                return
            end

            obj.updateViewBoxBaseCoordinates();
            obj.zoomViewToCursor();
        end

        function decreaseZoom(obj)
            %DECREASEZOOM  Step backward to the previous ZoomLevel.
            %
            %   The new view is anchored around the current image-space cursor
            %   position so the pixel under the cursor remains under the cursor as
            %   much as image bounds allow.

            oldIdx = obj.Zoom_.Idx;

            obj.Zoom_.Idx = max(obj.Zoom_.Idx - 1,1);

            % Do nothing if already at the first zoom level
            if obj.Zoom_.Idx == oldIdx
                return
            end

            obj.updateViewBoxBaseCoordinates();
            obj.zoomViewToCursor();
        end

        function enableFollowCursor(obj)
            %ENABLEFOLLOWCURSOR  Enable cursor-follow navigation.
            %
            %   If zoom is active, this records the current cursor/view relationship
            %   as a no-jump anchor. Subsequent mouse motion follows smoothly from
            %   that anchor toward the reachable image edges.

            if obj.FollowCursorEnabled
                return
            end

            obj.FollowCursor_.Enabled = true;

            if obj.ZoomEnabled
                obj.calibrateFollowCursorAnchor(obj.cursorPositionStatic);
            end
        end

        function disableFollowCursor(obj)
            %DISABLEFOLLOWCURSOR  Disable cursor-follow navigation.
            %
            %   The current zoomed view remains where it is. The cursor-follow anchor
            %   is cleared so the next enable creates a fresh no-jump anchor at the
            %   then-current cursor/view relationship.

            if ~obj.FollowCursorEnabled
                return
            end

            obj.FollowCursor_.Enabled = false;
            obj.clearFollowCursorAnchor();
        end

        function toggleFollowCursorEnabled(obj)
            %TOGGLEFOLLOWCURSORENABLED  Flip state of FollowCursorEnabled.

            obj.FollowCursorEnabled = ~obj.FollowCursor_.Enabled;
        end

    end






    %% Axes linking
    properties (SetAccess=private)
        hasLinks        (1,1) logical = false
    end

    properties (Access=private)
        linkedAxes      (1,:) = []
        linkedProps     (1,:) cell = {}
        LinkListener    event.listener
    end

    methods

        function addLink(obj,links,props)
            arguments
                obj     (1,1) matlabx.ui.widgets.ImageAxes
                links   (1,:) matlabx.ui.widgets.ImageAxes
                props   (1,:) cell = matlabx.ui.widgets.ImageAxes.getLinkableProperties()
            end

            if obj.hasLinks
                error("matlabx:ui:widgets:ImageAxes:UnableToLink","Axes is already linked");
            end

            if isempty(links) || isempty(props)
                return
            end

            obj.linkedAxes = links;
            obj.linkedProps = props;

            % listens to props for this object, updates links on change
            obj.LinkListener = addlistener(obj, props, 'PostSet', @(src,evt) obj.syncSlavesToSelf(src,evt));

            % indicate that this object has links
            obj.hasLinks = true;

            for i = 1:numel(links)
                if i==1
                    links(1).linkedAxes = [obj,links(2:end)];
                else
                    links(i).linkedAxes = [links(1:i-1),obj,links(i+1:end)];
                end
                links(i).linkedProps = props;
                links(i).LinkListener = addlistener(links(i), props, 'PostSet', @(src,evt) links(i).syncSlavesToSelf(src,evt));
                links(i).hasLinks = true;
            end

        end


        function removeLinks(obj)
            if ~obj.hasLinks, return; end
            for i = 1:numel(obj.linkedAxes)
                obj.linkedAxes(i).linkedAxes = [];
                obj.linkedAxes(i).linkedProps = {};
                delete(obj.linkedAxes(i).LinkListener(isvalid(obj.linkedAxes(i).LinkListener)));
                obj.linkedAxes(i).hasLinks = false;
            end
            obj.linkedAxes = [];
            obj.linkedProps = {};
            delete(obj.LinkListener(isvalid(obj.LinkListener)));
            obj.hasLinks = false;
        end

        function syncSlavesToSelf(obj,~,evt)
            % for each linked ImageAxes
            for i = 1:numel(obj.linkedAxes)
                % disable slave LinkListener while setting properties
                obj.linkedAxes(i).LinkListener.Enabled = false;
                % attempt to sync changed property value with each linked axes
                try
                    % name of the changed property
                    propName = evt.Source.Name;
                    % sync value of linked axes to value of this axes
                    obj.linkedAxes(i).(propName) = obj.(propName);
                catch
                    error('Failed to sync linked axes')
                end
                % re-enable slave LinkListener
                obj.linkedAxes(i).LinkListener.Enabled = true;
            end
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
                activeData = obj.RenderSource;
                activeKind = obj.RenderSourceKind;
                activeClass = obj.RenderSourceClass;
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
            obj.Panel.FontSize = obj.FontSize_;
            obj.BottomLabel.FontSize = obj.FontSize_;
            obj.uipanelOverheadPx_ = obj.UICal.uipanelTopChromeHeightPx(obj.FontSize_);
        end

        function refreshView(obj)
            %REFRESHVIEW Compatibility wrapper for a full view refresh.
            obj.refreshDisplay(ResetView=true);
        end

        function refreshDisplay(obj, opts)
            %REFRESHDISPLAY Update graphics that depend on current render/display state.
            arguments
                obj
                opts.ResetView (1,1) logical = false
                opts.UpdateImage (1,1) logical = true
                opts.UpdateColormap (1,1) logical = true
                opts.UpdateColorbar (1,1) logical = true
                opts.UpdateTopLabel (1,1) logical = true
                opts.UpdateContextMenu (1,1) logical = true
            end

            if opts.UpdateImage
                obj.updateImageCData();
            end

            if opts.UpdateColormap
                obj.updateAxesColormap();
            end

            if opts.UpdateColorbar
                obj.updateColorbar();
            end

            if opts.ResetView
                obj.restoreDefaultLimits();
            end

            if opts.UpdateTopLabel
                obj.updateTopLabelText();
            end

            if opts.UpdateContextMenu
                obj.refreshContextMenu();
            end
        end

        function refreshContextMenu(obj)
            % ComponentColorMode
            val = obj.ComponentColorMode;
            obj.ContextMenuUI.ColorMode_colors.Checked = strcmp(val,"colors");
            obj.ContextMenuUI.ColorMode_luts.Checked = strcmp(val,"luts");



        end


        %% --- UI text helpers ---

        function s = getImageInfoString(obj)
            s1 = sprintf(strjoin(repmat({'%i'},1,numel(obj.RenderSourceSize)),'x'),obj.RenderSourceSize);
            s2 = sprintf('%s (%s)',obj.RenderSourceClass,obj.RenderSourceKind);
            s = [s1,' ',s2];
        end

        function s = getComponentInfoString(obj)
            c = obj.ViewState_.C;
            nm = obj.ImageData_.getComponentName(c);
        
            if strlength(nm) > 0
                base = sprintf('C: %i/%i (%s)', c, obj.NumComponents, char(nm));
            else
                base = sprintf('C: %i/%i', c, obj.NumComponents);
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
            sz = obj.RenderSourceSize;
            % list size up to but not including the first singleton dimension
            idx = find(sz==1,1,"first");
            if ~isempty(idx) && idx>2
                idx = idx-1;
                sz = sz(1:idx);
            end
            s = sprintf(strjoin(repmat({'%i'},1,numel(sz)),'x'),sz);
        end

        function s = getImageBitDepthString(obj)

            if strcmpi(obj.RenderSourceKind,'rgb')
                s = '';
                return
            end

            switch obj.RenderSourceClass
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

    %% Public API: image model, render source, and display state
    methods
    
        % --- ImageData: canonical source image object ---
        function v = get.ImageData(obj), v = obj.ImageData_; end
    
        function set.ImageData(obj, val)
            arguments
                obj
                val (1,1) matlabx.image.Image5D
            end

            obj.ImageData_ = val;
            obj.syncViewStateToImageData();
            obj.syncRenderSourceToView(ResetView=true);
        end
    
        % --- CData: compatibility alias for raw image input/current source ---
        function v = get.CData(obj), v = obj.RenderSource; end
    
        function set.CData(obj, cdata)
            % Convenience wrapper to set ImageData without constructing an Image5D.
            if isempty(cdata)
                cdata = matlabx.ui.widgets.ImageAxes.placeholderImage();
            end

            obj.ImageData_ = matlabx.image.Image5D.fromComponents(cdata);

            obj.syncViewStateToImageData();
            obj.syncRenderSourceToView(ResetView=true);
        end

        % --- RenderSource: selected plane or computed composite ---
        function v = get.RenderSource(obj), v = obj.RenderSource_; end

        function v = get.RenderSourceSize(obj)
            if obj.ViewState_.ShowComposite
                v = size(obj.RenderSource_);
            else
                v = obj.ImageData_.getComponentSize(obj.ViewState_.C);
            end
        end
    
        function v = get.RenderSourceKind(obj)
            if obj.ViewState_.ShowComposite
                v = 'rgb';
            else
                v = obj.ImageData_.getComponentKind(obj.ViewState_.C);
            end
        end
    
        function v = get.RenderSourceClass(obj)
            if obj.ViewState_.ShowComposite
                v = class(obj.RenderSource_);
            else
                v = obj.ImageData_.getComponentClass(obj.ViewState_.C);
            end
        end

        % --- CData metadata compatibility aliases ---
        function v = get.CDataSize(obj),  v = obj.RenderSourceSize;  end
        function v = get.CDataKind(obj),  v = obj.RenderSourceKind;  end
        function v = get.CDataClass(obj), v = obj.RenderSourceClass; end

        % --- DisplayCData: graphics-ready image CData ---
        function v = get.DisplayCData(obj)
            if obj.ViewState_.ShowComposite
                v = obj.RenderSource_;
                return
            end

            clim = obj.ComponentDisplay_(obj.ViewState_.C).CLim;
            comp = obj.ImageData_.Components(obj.ViewState_.C);

            I = obj.RenderSource_;

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

            changed = obj.setComponentCLims_({double(val)}, idx);
            obj.ViewState_.CLimMode = 'manual';

            if changed
                obj.updateDisplayMapping();
            end
        end

        % --- CLimMode ---
        function v = get.CLimMode(obj)
            v = obj.ViewState_.CLimMode;
        end
    
        function set.CLimMode(obj, val)
            if strcmp(obj.ViewState_.CLimMode, val)
                return
            end

            obj.ViewState_.CLimMode = val;
            changed = true;
    
            if strcmp(val, 'auto')
                clims = cell(1, obj.NumComponents);
                for i = 1:obj.NumComponents
                    clims{i} = obj.ImageData_.getComponentDataRange(i);
                end
                changed = obj.setComponentCLims_(clims, 1:obj.NumComponents);
            end

            if changed
                obj.updateDisplayMapping();
            end
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
            newVal = logical(val) && obj.CanMergeComponents;

            if obj.ViewState_.ShowComposite == newVal
                return
            end

            obj.ViewState_.ShowComposite = newVal;
            obj.syncRenderSourceToView();
        end
    
        % --- toggleComposite ---
        function toggleComposite(obj), obj.ShowComposite = ~obj.ViewState_.ShowComposite; end


        %% C/Z/T control

        % --- nextComponent ---
        function nextComponent(obj), obj.C = matlabx.utils.math.wrapStep(obj.C,1,1,obj.NumComponents); end
    
        % --- previousComponent ---
        function previousComponent(obj), obj.C = matlabx.utils.math.wrapStep(obj.C,-1,1,obj.NumComponents); end
    
        % --- C ---
        function v = get.C(obj), v = obj.ViewState_.C; end
    
        function set.C(obj, val)
            newVal = clip(val, 1, obj.NumComponents);

            if obj.ViewState_.C == newVal
                return
            end

            obj.ViewState_.C = newVal;
            obj.syncRenderSourceToView();
        end


        % --- nextZ ---
        function nextZ(obj), obj.Z = matlabx.utils.math.wrapStep(obj.Z,1,1,obj.ImageData_.SizeZ); end
    
        % --- previousZ ---
        function previousZ(obj), obj.Z = matlabx.utils.math.wrapStep(obj.Z,-1,1,obj.ImageData_.SizeZ); end
    
        % --- Z ---
        function v = get.Z(obj), v = obj.ViewState_.Z; end
    
        function set.Z(obj, val)
            newVal = clip(val, 1, obj.ImageData_.SizeZ);

            if obj.ViewState_.Z == newVal
                return
            end

            obj.ViewState_.Z = newVal;
            obj.syncRenderSourceToView();
        end

        % --- nextT ---
        function nextT(obj), obj.T = matlabx.utils.math.wrapStep(obj.T,1,1,obj.ImageData_.SizeT); end
    
        % --- previousT ---
        function previousT(obj), obj.T = matlabx.utils.math.wrapStep(obj.T,-1,1,obj.ImageData_.SizeT); end
    
        % --- T ---
        function v = get.T(obj), v = obj.ViewState_.T; end
    
        function set.T(obj, val)
            newVal = clip(val, 1, obj.ImageData_.SizeT);

            if obj.ViewState_.T == newVal
                return
            end

            obj.ViewState_.T = newVal;
            obj.syncRenderSourceToView();
        end


        %% Component-specific set/get

        % --- Colormap ---
        function v = get.Colormap(obj), v = obj.ComponentDisplay_(obj.ViewState_.C).DisplayMap; end

        function set.Colormap(obj, val)
            idx = obj.ViewState_.C;
            obj.setColormap(double(val), idx);
        end


        % --- ComponentColors ---
        function val = get.ComponentColors(obj)
            val = cell(1, obj.NumComponents);
            for i = 1:obj.NumComponents
                val{i} = char(obj.ComponentDisplay_(i).ColorName);
            end
        end
    
        function set.ComponentColors(obj, val)
            obj.validateFullComponentCell(val, 'ComponentColors');

            changed = obj.setComponentColors_(val, 1:obj.NumComponents);

            if changed
                obj.updateAllDisplayMaps();
                obj.updateDisplayMapping();
            end
        end
    
        % --- ComponentColormaps ---
        function val = get.ComponentColormaps(obj)
            val = cell(1, obj.NumComponents);
            for i = 1:obj.NumComponents
                val{i} = obj.ComponentDisplay_(i).Colormap;
            end
        end
    
        function set.ComponentColormaps(obj, val)
            obj.validateFullComponentCell(val, 'ComponentColormaps');

            changed = obj.setComponentColormaps_(val, 1:obj.NumComponents);

            if changed
                obj.updateAllDisplayMaps();
                obj.updateDisplayMapping();
            end
        end

        % --- ComponentColorMode ---
        function v = get.ComponentColorMode(obj), v = obj.ViewState_.ComponentColorMode; end
    
        function set.ComponentColorMode(obj, val)
            if strcmp(obj.ViewState_.ComponentColorMode, val)
                return
            end

            obj.ViewState_.ComponentColorMode = val;
            obj.updateAllDisplayMaps();
            obj.updateDisplayMapping();
        end

        % --- ComponentCLims ---
        function val = get.ComponentCLims(obj)
            val = cell(1, obj.NumComponents);
            for i = 1:obj.NumComponents
                val{i} = obj.ComponentDisplay_(i).CLim;
            end
        end
    
        function set.ComponentCLims(obj, val)
            obj.validateFullComponentCell(val, 'ComponentCLims');

            changed = obj.setComponentCLims_(val, 1:obj.NumComponents);
            obj.ViewState_.CLimMode = 'manual';

            if changed
                obj.updateDisplayMapping();
            end
        end





    
        % --- setCLim ---
        function setCLim(obj, clim, idx)
            arguments
                obj (1,1) matlabx.ui.widgets.ImageAxes
                clim (1,2) double
                idx (:,1) = []
            end
    
            if isempty(idx)
                idx = obj.C;
            end
    
            idx = obj.validateComponentIndices(idx);
            clims = repmat({double(clim)}, 1, numel(idx));
            changed = obj.setComponentCLims_(clims, idx);
            obj.ViewState_.CLimMode = 'manual';

            if changed
                obj.updateDisplayMapping();
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
                idx = obj.C;
            end

            idx = obj.validateComponentIndices(idx);

            modeChanged = ~strcmp(obj.ViewState_.ComponentColorMode, 'luts');
            obj.ViewState_.ComponentColorMode = 'luts';

            cmaps = repmat({double(cmap)}, 1, numel(idx));
            changed = obj.setComponentColormaps_(cmaps, idx);

            if changed || modeChanged
                obj.updateAllDisplayMaps();
                obj.updateDisplayMapping();
            end

        end

        % --- setComponentColor ---
        function setComponentColor(obj, colorName, idx)
            arguments
                obj (1,1) matlabx.ui.widgets.ImageAxes
                colorName
                idx (:,1) = []
            end

            if isempty(idx)
                idx = obj.C;
            end

            idx = obj.validateComponentIndices(idx);
            colors = repmat({colorName}, 1, numel(idx));
            changed = obj.setComponentColors_(colors, idx);

            if changed
                obj.updateAllDisplayMaps();
                obj.updateDisplayMapping();
            end
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
                    displayState(i).ColorName = matlabx.colors.names.fromRGB(comp.Color,"Palette","MATLAB");
                elseif hasOldEntry && ~isempty(old(i).Color)
                    displayState(i).Color = old(i).Color;
                    displayState(i).ColorName = matlabx.colors.names.fromRGB(old(i).Color,"Palette","MATLAB");
                else
                    displayState(i).ColorName = string(defaultColors{1 + mod(i-1, numel(defaultColors))});
                    displayState(i).Color = matlabx.colors.names.toRGB(displayState(i).ColorName,"Palette","MATLAB");
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

        function validateFullComponentCell(obj, val, propertyName)
        %VALIDATEFULLCOMPONENTCELL Validate bulk per-component property input.
            if ~iscell(val) || numel(val) ~= obj.NumComponents
                error('ImageAxes:InvalidComponentPropertySize', ...
                    '%s must be a cell array with one entry per component (%d entries).', ...
                    propertyName, obj.NumComponents);
            end
        end

        function idx = validateComponentIndices(obj, idx)
        %VALIDATECOMPONENTINDICES Validate and row-vectorize component indices.
            idx = idx(:).';

            if isempty(idx)
                return
            end

            if any(idx < 1) || any(idx > obj.NumComponents) || any(mod(idx,1) ~= 0)
                error('ImageAxes:InvalidComponentIndex', ...
                    'Component indices must be positive integers between 1 and NumComponents (%d).', ...
                    obj.NumComponents);
            end
        end

        function changed = setComponentCLims_(obj, clims, idx)
        %SETCOMPONENTCLIMS_ Set CLim entries without refreshing.
            changed = false;

            for k = 1:numel(idx)
                ii = idx(k);
                comp = obj.ImageData_.Components(ii);

                % CLim is meaningless for RGB/logical components.
                if strcmp(comp.Kind, 'rgb') || strcmp(comp.Class, 'logical')
                    continue
                end

                newVal = double(clims{k});

                if ~isequal(size(newVal), [1 2])
                    error('ImageAxes:InvalidCLim', ...
                        'ComponentCLims{%d} must be a 1x2 numeric vector.', ii);
                end

                if isequaln(obj.ComponentDisplay_(ii).CLim, newVal)
                    continue
                end

                obj.ComponentDisplay_(ii).CLim = newVal;
                changed = true;
            end
        end

        function changed = setComponentColors_(obj, colors, idx)
        %SETCOMPONENTCOLORS_ Set component color names without refreshing.
            changed = false;

            for k = 1:numel(idx)
                ii = idx(k);
                newName = string(colors{k});

                if ~isscalar(newName)
                    error('ImageAxes:InvalidComponentColor', ...
                        'ComponentColors{%d} must be a text scalar.', ii);
                end

                if strcmp(obj.ComponentDisplay_(ii).ColorName, newName)
                    continue
                end

                obj.ComponentDisplay_(ii).ColorName = newName;
                obj.ComponentDisplay_(ii).Color = ...
                    matlabx.colors.names.toRGB(char(newName), "Palette", "MATLAB");
                changed = true;
            end
        end

        function changed = setComponentColormaps_(obj, cmaps, idx)
        %SETCOMPONENTCOLORMAPS_ Set component colormaps without refreshing.
            changed = false;

            for k = 1:numel(idx)
                ii = idx(k);
                newMap = double(cmaps{k});

                if size(newMap, 2) ~= 3
                    error('ImageAxes:InvalidComponentColormap', ...
                        'ComponentColormaps{%d} must be an N-by-3 numeric colormap.', ii);
                end

                if isequaln(obj.ComponentDisplay_(ii).Colormap, newMap)
                    continue
                end

                obj.ComponentDisplay_(ii).Colormap = newMap;
                changed = true;
            end
        end
    
        function syncRenderSourceToView(obj, opts)
        %SYNCRENDERSOURCETOVIEW  Synchronize RenderSource_ with current view.
            arguments
                obj
                opts.ResetView (1,1) logical = false
            end
        
            oldData = obj.RenderSource_;
        
            if obj.ViewState_.ShowComposite
                newData = obj.getCompositeImage();
            else
                newData = obj.ImageData_.getPlane(...
                    obj.ViewState_.C,...
                    obj.ViewState_.Z,...
                    obj.ViewState_.T);
            end
        
            oldSz = size(oldData,[1,2]);
            newSz = size(newData,[1,2]);
        
            sizeChanged = ~isequal(oldSz,newSz);
        
            % Preserve the current view in normalized image coordinates before
            % changing the render source. Pixel-centered image limits are assumed:
            %
            %   XLim = [0.5, W + 0.5]
            %   YLim = [0.5, H + 0.5]
            preserveView = sizeChanged && ...
                           all(oldSz > 0) && ...
                           obj.ZoomEnabled && ...
                           ~opts.ResetView;
        
            if preserveView
                oldXLim = obj.mainAxes.XLim;
                oldYLim = obj.mainAxes.YLim;
        
                normalizedXLim = (oldXLim - 0.5) ./ oldSz(2);
                normalizedYLim = (oldYLim - 0.5) ./ oldSz(1);
            end
        
            % Scale the stored image-space zoom anchor independently of the view
            % limits. Zoom_.LastCursorXY must always remain in image coordinates.
            lastZoomAnchor = obj.Zoom_.LastCursorXY;
        
            if sizeChanged && ~isempty(lastZoomAnchor) && all(oldSz > 0)
                anchorNorm = (lastZoomAnchor - 0.5) ./ [oldSz(2),oldSz(1)];
        
                obj.Zoom_.LastCursorXY = ...
                    0.5 + anchorNorm .* [newSz(2),newSz(1)];
            end
        
            % Update rendered data and perform the normal display refresh.
            obj.RenderSource_ = newData;
            obj.refreshDisplay(ResetView=opts.ResetView || (sizeChanged && ~preserveView));
        
            if preserveView
                % Reconstruct the same relative view for the new image dimensions
                newXLim = 0.5 + normalizedXLim .* newSz(2);
                newYLim = 0.5 + normalizedYLim .* newSz(1);
        
                % Guard against small floating-point excursions
                defXLim = [0.5, newSz(2) + 0.5];
                defYLim = [0.5, newSz(1) + 0.5];
        
                viewWidth  = min(diff(newXLim),diff(defXLim));
                viewHeight = min(diff(newYLim),diff(defYLim));
        
                xLower = min(max(newXLim(1),defXLim(1)), ...
                             defXLim(2) - viewWidth);
        
                yLower = min(max(newYLim(1),defYLim(1)), ...
                             defYLim(2) - viewHeight);
        
                newXLim = xLower + [0,viewWidth];
                newYLim = yLower + [0,viewHeight];
        
                % refreshView may have updated image-dependent geometry, so apply
                % the restored limits only after it completes.
                obj.updateViewBoxBaseCoordinates();
                obj.applyZoomLims(newXLim,newYLim);
        
            elseif sizeChanged
                % No active zoomed view to preserve. Keep the stored anchor valid,
                % defaulting to the center when no previous anchor exists.
                if isempty(obj.Zoom_.LastCursorXY)
                    obj.Zoom_.LastCursorXY = ...
                        [(newSz(2) + 1)/2, (newSz(1) + 1)/2];
                end
            end
        
            evtData = matlabx.ui.widgets.events.RenderSourceChangedEventData(...
                oldData,newData);
        
            notify(obj,'RenderSourceChanged',evtData);
        end

        function updateDisplayMapping(obj)
        %UPDATEDISPLAYMAPPING Refresh display after CLim/color/LUT changes.
            if obj.ViewState_.ShowComposite
                obj.syncRenderSourceToView();
                return
            end

            obj.refreshDisplay( ...
                ResetView=false, ...
                UpdateImage=true, ...
                UpdateColormap=true, ...
                UpdateColorbar=true, ...
                UpdateTopLabel=false, ...
                UpdateContextMenu=true);
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
                        matlabx.colors.names.toRGB(char(displayState.ColorName),"Palette","MATLAB"), ...
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
                        colors(i,:) = matlabx.colors.names.toRGB(char(obj.ComponentDisplay_(i).ColorName),"Palette","MATLAB");
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
        function s = get.ImageSize(obj),    s = obj.RenderSourceSize;    end
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

    %% Hub-facing event handlers (matches | onDown | onMove | onUp | onScroll | onKey | onEnter | onLeave)
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
            % get the ancestor toolbar button from event target, if it exists
            btn = obj.getToolbarButtonFromTarget(E.Target);

            % button exists
            if ~isempty(btn)
                % set image info label to display button tooltip, return
                obj.BottomLabel.String = sprintf(' %s',btn.Tooltip); return
            end


            % set axes limits and view box before routing to tools
            if obj.ZoomEnabled && obj.FollowCursorEnabled
                obj.followCursor();
            end

            obj.routeEventToTools(E);

            % Host maintenance (update label/pointer/etc. on move if desired)
            obj.onMove_();
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

        % executes on mouse move after PassiveInterceptors/Interceptors
        function onMove_(obj)
            obj.updateBottomLabelText();
            obj.updatePointer();
        end

        function onDown_(obj,E)

            if E.StopPropagation
                return
            end

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

        function btn = getToolbarButtonFromTarget(~,target)
            % get the ancestor toolbar button from event target, if it exists
            % look for "state" buttons first
            btn = ancestor(target,'matlab.ui.controls.ToolbarStateButton');
            % none found -> look for "push" buttons
            if isempty(btn)
                btn = ancestor(target,'matlab.ui.controls.ToolbarPushButton');
            end
        end

    end

    %% Tool event routing
    methods

        function routeEventToTools(obj,E)

            obj.routeToPassiveInterceptors(E);
            if E.StopPropagation, return; end

            % get highest priority Interceptor for event kind
            t = obj.getPriorityInterceptor(E.Kind);
            % forward event to the tool
            if ~isempty(t)
                t.("on"+E.Kind)(E);
                E.StopPropagation = true;
            end
        end

        function routeToPassiveInterceptors(obj,E)
            % cell array of PassiveInterceptors for this eventType, sorted by Priority
            passiveInterceptors = obj.getPriorityPassiveInterceptors(E.Kind);

            % no PassiveInterceptors for this eventType, return early
            if isempty(passiveInterceptors), return; end

            % pass event to each PassiveInterceptor
            for i = 1:numel(passiveInterceptors)
                passiveInterceptors{i}.("onPassive"+E.Kind)(E);
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
            idx = cellfun(@(t) t.Enabled & t.("Intercepts"+eventType) ,toolsCell,'UniformOutput',true);
            % no matching tools, exit early
            if ~any(idx), tool = []; return; end
            % sort the tools by priority (descending order)
            tools = obj.prioritySortToolsCell(toolsCell(idx));
            % return the first element (highest priority)
            tool = tools{1};
        end

        % get cell array of PassiveInterceptors for the specified eventType, sorted by descending Priority
        function toolsCell = getPriorityPassiveInterceptors(obj,eventType)
            % cell array of Installed tools
            toolsCell = obj.ToolRegistry.values;
            % no Installed tools, exit early
            if isempty(toolsCell), return; end
            % get logical idx of Installed tools that passively intercept the given eventType
            idx = cellfun(@(t) t.("PassivelyIntercepts"+eventType),toolsCell,'UniformOutput',true);
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
            obj.setCLim(o.Value, e.ID);
        end

        function onContrastToolValueChanging(obj,o,e)
            obj.setCLim(o.Value, e.ID);
        end

        % --- MetadataWindow ---
        function openMetadataWindow(obj)
            if obj.metadataWindowOpen
                return
            end

            metadata = obj.ImageData_.AllMetadata;
            metadataLines = cellstr(matlabx.struct.prettyPrint(metadata));

            obj.metadataWindow = matlabx.app.TextWindow( ...
                "Title","Metadata", ...
                "Text",metadataLines, ...
                "ClosedFcn",@(~,~) obj.onMetadataWindowClosed());

            obj.metadataWindowOpen = true;
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

        function names = getDefaultTools()
            names = {'Zoom','Colorbar','ChooseColormap'};
        end

        function props = getLinkableProperties()
            props = { ...
                'C', ...
                'Z', ...
                'T', ...
                'ComponentColorMode', ...
                'ComponentColormaps', ...
                'ComponentColors', ...
                'ShowComposite', ...
                'ComponentCLims'};
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

        function [viewer1,viewer2] = linkDemo()
            I = matlabx.image.Image5D.demo();

            [viewer1,~] = matlabx.app.quickshow(I,"Title","Viewer 1","Location","west");

            [viewer2,~] = matlabx.app.quickshow(I,"Title","Viewer 2","Location","east");

            viewer1.addLink(viewer2,{'C','Z','T',...
                'ShowComposite','ComponentColors',...
                'ComponentColormaps','ComponentCLims'});
        end

        function ax = demoImage5D()
            I = matlabx.image.Image5D.demo();
            ax = matlabx.app.quickshow(I,"Title","Example 5D Image");
        end


    end

    %% Teardown
    methods

        function delete(obj)

            % remove listeners first
            if ~isempty(obj.L), delete(obj.L(isvalid(obj.L))); end
            % replace listener property with empty array of event.listener
            obj.L = event.listener.empty;

            % contrastTool
            if ~isempty(obj.contrastTool), delete(obj.contrastTool(isvalid(obj.contrastTool))); end

            % metadataWindow
            if ~isempty(obj.metadataWindow), delete(obj.metadataWindow(isvalid(obj.metadataWindow))); end

            % ViewBox
            delete(obj.ViewBoxFull(isvalid(obj.ViewBoxFull)));
            delete(obj.ViewBoxZoom(isvalid(obj.ViewBoxZoom)));

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
