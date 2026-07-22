classdef Slider < matlab.ui.componentcontainer.ComponentContainer

    %% Public API

    properties
        % value shape and behavior: scalar uses one thumb, range uses two
        ValueMode (1,1) string {mustBeMember(ValueMode, ["scalar", "range"])} = "range"
        % whether to show numeric edit fields next to the slider
        ShowEditFields (1,1) matlab.lang.OnOffSwitchState = "on"
        % whether to show the filled slider region
        ShowFill (1,1) matlab.lang.OnOffSwitchState = "on"
        % flag to determine whether values are rounded
        RoundValues (1,1) matlab.lang.OnOffSwitchState = 'off'
        % number of digits used for rounding 
        %   N > 0: round to N digits to the right of the decimal point.
        %   N = 0: round to the nearest integer.
        %   N < 0: round to N digits to the left of the decimal point.
        RoundDigits (1,1) double = 0
    end


    % dependent public properties with private backing
    properties(Dependent=true)
        % format specifier for numeric editfields
        ValueDisplayFormat (1,:) char
        % text displayed above the slider
        Title (1,:) char
        % size of the font
        FontSize (1,1) double
        % color of the font
        FontColor (1,3) double
    end

    % private backing for above
    properties(Access=private)
        ValueDisplayFormat_ (1,:) char = '%d'
        % text displayed above the slider
        Title_ (1,:) char = "Untitled slider"
        % size of the font
        FontSize_ (1,1) double = 12
        % color of the font
        FontColor_ (1,3) double = [0 0 0]
    end

    properties(SetObservable, Dependent, AbortSet)
        Value double
    end

    % properties we want property-based, minimal updates for
    properties(SetObservable, AbortSet)
        % % min and max of the slider track
        Limits double = [0,1]

        % color of the thumb faces
        ThumbFaceColor (1,3) double {mustBeInRange(ThumbFaceColor,0,1)} = [1 1 1]
        % color of the thumb edges
        ThumbEdgeColor (1,3) double {mustBeInRange(ThumbEdgeColor,0,1)} = [0 0 0]

        % overall height of the slider component (excluding labels)
        Height (1,1) double = 20

        % height of the track
        TrackHeight (1,1) double = 4
        % color of the track patch face
        TrackColor (1,3) double = [0 0 0]
        % color of the track patch edge
        TrackEdgeColor (1,3) double = [0 0 0]

        % height of the range
        RangeHeight (1,1) double = 4
        % colormap used to color range patch face
        Colormap (256,3) double = gray
        % color of the range patch edge
        RangeEdgeColor (1,3) double = [0 0 0]
    end

    properties(Dependent=true)
        ComponentHeight
    end


    %% Private helpers

    properties(Access=private)
        % true only on startup
        inStartup (1,1) logical = true
        % true if the slider is currently moving
        isSliding (1,1) logical = false
        % index of the active thumb (1 or 2, NaN if none)
        activeThumbIdx (1,1) double = NaN
        % index of thumb currently hovered (1 or 2, NaN if none)
        hoverThumbIdx double = NaN
        % flag to help coalesce updates
        pendingUpdate (1,1) logical = false
        % helpers for patch coordinates
        trackV = [0 0; 1 0; 1 1; 1 1]
        trackF = [1,2,3,4]

        % rangeVX = [1:256,256:-1:1]'
        rangeVX = [linspace(0,1,256),linspace(1,0,256)]'
        rangeVY = [ones(256,1)*-1;ones(256,1)]
        rangeF = 1:512
    end


    properties(Access=private,Dependent=true)
        % ancestor figure of the component
        parentFig
    end

    %% UI / graphics handles

    properties(Access = private,Transient,NonCopyable)
        % outermost grid for the entire component
        containerGrid (1,1) matlab.ui.container.GridLayout

        % uilabel for the Title
        titleLabel (1,1) matlab.ui.control.Label
        % uilabel for the minimum value editfield
        minLabel (1,1) matlab.ui.control.Label
        % uilabel for the maximum value editfield
        maxLabel (1,1) matlab.ui.control.Label

        % axes to hold slider thumbs and patches
        sliderThumbAxes (1,1) matlab.ui.control.UIAxes
        % patch object for slider track
        trackPatch (1,1) matlab.graphics.primitive.Patch
        % patch object for slider range
        rangePatch (1,1) matlab.graphics.primitive.Patch
        % the slider thumbs (lower=1, upper=2)
        sliderThumb (:,1) matlabx.ui.control.internal.SliderThumb

        % editfields for text control of slider values [low high]
        sliderValueEditField (:,1) matlab.ui.control.NumericEditField

        % listeners for property-based updates (ThumbFaceColor, etc.)
        L event.listener = event.listener.empty
    end

    %% Hub registration
    properties(Access=private)
        Hub matlabx.ui.interaction.FigureEventHub
        RouterId double = NaN
    end

    %% Events
    events(HasCallbackProperty, NotifyAccess = protected)
        ValueChanging   % ValueChangingFcn callback property will be generated
        ValueChanged    % ValueChangedFcn callback property will be generated
    end

    %% ComponentContainer lifecycle
    methods(Access=protected)

        function setup(obj)

            % grid layout manager to enclose all the components
            obj.containerGrid = uigridlayout(obj,...
                [1,3],...
                "ColumnWidth",{'1x',50,50},...
                "RowHeight",{obj.Height,obj.Height},...
                "BackgroundColor",[0 0 0],...
                "Padding",[5 5 5 5],...
                "Scrollable","on",...
                "RowSpacing",0);

            % uilabel to display the title text
            obj.titleLabel = uilabel(obj.containerGrid,...
                "Text",obj.Title,...
                "FontColor",obj.FontColor,...
                "FontSize",obj.FontSize);
            obj.titleLabel.Layout.Row    = 1;
            obj.titleLabel.Layout.Column = 1;

            % uilabel for the minimum value editfield
            obj.minLabel = uilabel(obj.containerGrid,...
                "Text","Min",...
                "FontColor",obj.FontColor,...
                "FontSize",obj.FontSize);
            obj.minLabel.Layout.Row    = 1;
            obj.minLabel.Layout.Column = 2;

            % uilabel for the maximum value editfield
            obj.maxLabel = uilabel(obj.containerGrid,...
                "Text","Max",...
                "FontColor",obj.FontColor,...
                "FontSize",obj.FontSize);
            obj.maxLabel.Layout.Row    = 1;
            obj.maxLabel.Layout.Column = 3;

            % axes to hold the slider thumbs and patches
            obj.sliderThumbAxes = uiaxes(obj.containerGrid,...
                'XTick',[],...
                'YTick',[],...
                'XLim',obj.Limits,...
                'YLim',[0 obj.Height],...
                'XColor','none',...
                'YColor','none',...
                'Color','none',...
                'Units','normalized',...
                'InnerPosition',[0 0 1 1],...
                'LineWidth',1,...
                'Box','off',...
                'HitTest','on',...
                'PickableParts','all',...
                'Visible','off');
            obj.sliderThumbAxes.Layout.Row    = 2;
            obj.sliderThumbAxes.Layout.Column = 1;
            obj.sliderThumbAxes.Toolbar.Visible = 'off';
            disableDefaultInteractivity(obj.sliderThumbAxes);
            obj.sliderThumbAxes.Interactions = [];

            % track patch (full Limits range)
            obj.trackPatch = patch(obj.sliderThumbAxes,...
                'Faces',[1,2,3,4],...
                'Vertices',[0,0;1,0;1,1;0,1],...
                'FaceVertexCData',obj.TrackColor,...
                'EdgeColor',obj.TrackEdgeColor,...
                'FaceColor','flat',...
                'PickableParts','visible',...
                'HitTest','on',...
                'LineWidth',0.5);

            % range patch (full Limits range)
            obj.rangePatch = patch(obj.sliderThumbAxes,...
                'Faces',[1,2,3,4],...
                'Vertices',[0,0;1,0;1,1;0,1],...
                'FaceVertexCData',obj.TrackColor,...
                'EdgeColor',obj.TrackEdgeColor,...
                'FaceColor','interp',...
                'PickableParts','visible',...
                'HitTest','on',...
                'LineWidth',0.5);


            % create lower and upper thumbs
            obj.sliderThumb(1) = matlabx.ui.control.internal.SliderThumb(obj.sliderThumbAxes,...
                "EdgeColor",obj.ThumbEdgeColor,...
                "FaceColor",obj.ThumbFaceColor,...
                "Value",obj.Limits(1),...
                "YPosition",0.5*obj.Height,...
                "ID",1,...
                "EdgeWidth",0.5);

            obj.sliderThumb(2) = matlabx.ui.control.internal.SliderThumb(obj.sliderThumbAxes,...
                "EdgeColor",obj.ThumbEdgeColor,...
                "FaceColor",obj.ThumbFaceColor,...
                "Value",obj.Limits(2),...
                "YPosition",0.5*obj.Height,...
                "ID",2,...
                "EdgeWidth",0.5);

            % editfields for numeric control
            obj.sliderValueEditField(1) = uieditfield(obj.containerGrid,"numeric",...
                'Limits',obj.Limits,...
                'Value',obj.Limits(1),...
                'ValueChangedFcn',@(o,e) obj.sliderEditfieldValueChanged(o,e),...
                'UserData',1,...
                'ValueDisplayFormat',obj.ValueDisplayFormat);
            obj.sliderValueEditField(1).Layout.Row    = 2;
            obj.sliderValueEditField(1).Layout.Column = 2;

            obj.sliderValueEditField(2) = uieditfield(obj.containerGrid,"numeric",...
                'Limits',obj.Limits,...
                'Value',obj.Limits(2),...
                'ValueChangedFcn',@(o,e) obj.sliderEditfieldValueChanged(o,e),...
                'UserData',2,...
                'ValueDisplayFormat',obj.ValueDisplayFormat);
            obj.sliderValueEditField(2).Layout.Row    = 2;
            obj.sliderValueEditField(2).Layout.Column = 3;

            % Register with FigureEventHub
            obj.Hub = matlabx.ui.interaction.FigureEventHub.ensure(obj.parentFig);
            obj.RouterId = obj.Hub.register(obj, ...
                'Priority', 10, ...
                'CaptureDuringDrag', true);

            obj.updateTrackPatch();
            obj.updateRangePatch();
            obj.onColorsChanged();
            obj.onDimensionsChanged();

            % set SizeChangedFcn so we can force visual update upon resizing (AutoResizeChildren of parent must be Off)
            obj.SizeChangedFcn = @(~,~) obj.queueSizeUpdate();

            % property-based listeners for granular updates
            obj.L(end+1) = addlistener(obj,{'TrackColor','TrackEdgeColor'},'PostSet',@(~,~)obj.updateTrackPatchColors());
            obj.L(end+1) = addlistener(obj,{'Colormap','RangeEdgeColor'},'PostSet',@(~,~)obj.updateRangePatchColors());
            obj.L(end+1) = addlistener(obj,{'BackgroundColor','ThumbFaceColor','ThumbEdgeColor'},'PostSet',@(~,~)obj.onColorsChanged());
            obj.L(end+1) = addlistener(obj,{'TrackHeight','RangeHeight','Height'},'PostSet',@(~,~)obj.onDimensionsChanged());
            obj.L(end+1) = addlistener(obj,'Limits','PostSet',@(~,~)obj.onLimitsChanged());

            obj.applyModeAppearance();
        end

        function update(obj)
            if obj.inStartup
                obj.updateEditfieldLimits();
                obj.inStartup = false;
            end
        end

    end

    %% Destructor
    methods

        function delete(obj)
            % remove listeners
            if ~isempty(obj.L)
                delete(obj.L(isvalid(obj.L)));
            end

            % unregister from hub
            try
                if ~isempty(obj.Hub) && isvalid(obj.Hub) && ~isnan(obj.RouterId)
                    obj.Hub.unregister(obj.RouterId);
                end
            catch
                % ignore if figure already gone
            end
        end

    end

    %% Update helpers
    methods(Access=private)

        function updateOnResize(obj)
            if ~isvalid(obj); return; end
            
            obj.onDimensionsChanged();
        end

        function queueSizeUpdate(obj)

            if obj.pendingUpdate
                return
            end
            obj.pendingUpdate = true;
            % coalesce updates
            drawnow limitrate nocallbacks
            obj.updateOnResize();
            obj.pendingUpdate = false;
        end

        function updateTrackPatch(obj)
            % full update of Vertices, Faces, and FaceVertexCData

            sliderLimits = obj.Limits;

            % x values
            lo  = sliderLimits(1);
            hi = sliderLimits(2);

            V = obj.trackV; % base track Vertices template
            % adjust X coordinates of Vertices
            V(:,1) = [lo; hi; hi; lo];
            % adjust Y coordinates of Vertices
            V(1:2,2) = 0.5*(obj.Height - obj.TrackHeight);
            V(3:end,2) = 0.5*(obj.Height + obj.TrackHeight);

            set(obj.trackPatch, ...
                "Vertices", V, ...
                "Faces",    [1,2,3,4], ...
                "FaceVertexCData", obj.TrackColor);
        end

        function updateTrackPatchVx(obj)
            % x values used to calculate track patch coordinates
            sliderLimits = obj.Limits;
            loLim  = sliderLimits(1);
            hiLim = sliderLimits(2);
            % update of Vertex X coordinates only
            obj.trackPatch.Vertices(:,1) = [loLim; hiLim; hiLim; loLim];
        end

        function updateTrackPatchColors(obj)
            obj.trackPatch.EdgeColor = obj.TrackEdgeColor;
            obj.trackPatch.FaceVertexCData = obj.TrackColor;
        end

        function updateRangePatch(obj)
            % full update of Vertices, Faces, and FaceVertexCData

            % x values
            [lo, hi] = obj.getFillLimits();

            % X and Y coordinates of each vertex, from bottom left, CCW to top left
            X = obj.rangeVX*(hi-lo)+lo;
            Y = 0.5*(obj.rangeVY*obj.RangeHeight + obj.Height);

            V = [X,Y];
            F = obj.rangeF;
            C = vertcat(obj.Colormap,flipud(obj.Colormap));

            set(obj.rangePatch, ...
                "Vertices", V, ...
                "Faces",    F, ...
                "FaceVertexCData", C);
        end

        function updateRangePatchColors(obj)
            obj.rangePatch.EdgeColor = obj.RangeEdgeColor;
            obj.rangePatch.FaceVertexCData = vertcat(obj.Colormap,flipud(obj.Colormap));
        end

        function updateRangePatchVx(obj)
            % x values used to calculate track patch coordinates
            [lo, hi] = obj.getFillLimits();
            % update of Vertex X coordinates only
            obj.rangePatch.Vertices(:,1) = obj.rangeVX*(hi-lo)+lo;
        end

        function [lo, hi] = getFillLimits(obj)
            switch obj.ValueMode
                case "scalar"
                    lo = obj.Limits(1);
                    hi = obj.sliderThumb(1).Value;
                case "range"
                    lo = obj.sliderThumb(1).Value;
                    hi = obj.sliderThumb(2).Value;
            end
        end

        function applyModeAppearance(obj)
            if isempty(obj.containerGrid) || isempty(obj.sliderThumb)
                return
            end

            isScalar = obj.ValueMode == "scalar";
            showEdits = strcmp(char(obj.ShowEditFields), 'on');

            obj.rangePatch.Visible = char(obj.ShowFill);

            if isScalar
                obj.sliderThumb(2).Visible = 'off';
                obj.minLabel.Text = "Value";
                obj.maxLabel.Visible = "off";
                obj.sliderValueEditField(2).Visible = "off";
            else
                obj.sliderThumb(2).Visible = 'on';
                obj.minLabel.Text = "Min";
                obj.maxLabel.Visible = onOffChar(showEdits);
                obj.sliderValueEditField(2).Visible = onOffChar(showEdits);
            end

            obj.minLabel.Visible = onOffChar(showEdits);
            obj.sliderValueEditField(1).Visible = onOffChar(showEdits);

            if ~showEdits
                obj.containerGrid.ColumnWidth = {'1x',0,0};
            elseif isScalar
                obj.containerGrid.ColumnWidth = {'1x',50,0};
            else
                obj.containerGrid.ColumnWidth = {'1x',50,50};
            end

            obj.updateEditfieldLimits();
            obj.updateRangePatch();
        end

        function onColorsChanged(obj)
            % Only update thumb colors when ThumbFaceColor/ThumbEdgeColor change
            obj.containerGrid.BackgroundColor = obj.BackgroundColor;
            obj.sliderThumb(1).FaceColor = obj.ThumbFaceColor;
            obj.sliderThumb(2).FaceColor = obj.ThumbFaceColor;
            obj.sliderThumb(1).EdgeColor = obj.ThumbEdgeColor;
            obj.sliderThumb(2).EdgeColor = obj.ThumbEdgeColor;
        end

        function onDimensionsChanged(obj)
            % Set row height for labels row
            obj.containerGrid.RowHeight{1} = obj.Height;

            % Set row height for slider row
            obj.containerGrid.RowHeight{2} = obj.Height;

            % Adjust axes YLim
            obj.sliderThumbAxes.YLim = [0 obj.Height];

            % Thumb Y position (centered vertically)
            obj.sliderThumb(1).YPosition = 0.5 * obj.Height;
            obj.sliderThumb(2).YPosition = 0.5 * obj.Height;

            % Full recompute of patches when heights change
            if isvalid(obj.trackPatch)
                obj.updateTrackPatch();
            end

            if isvalid(obj.rangePatch)
                obj.updateRangePatch();
            end

        end

        function onLimitsChanged(obj)
            % Adjust axes XLim
            obj.sliderThumbAxes.XLim = obj.Limits;
            % adjust track patch coordinates
            obj.updateTrackPatchVx();
            % Ensure thumbs are within Limits
            obj.sliderThumb(1).Value = clip(obj.sliderThumb(1).Value, obj.Limits(1), obj.Limits(2));
            obj.sliderThumb(2).Value = clip(obj.sliderThumb(2).Value, obj.Limits(1), obj.Limits(2));
            % Update editfield limits based on current thumbs
            obj.updateEditfieldLimits();
            obj.updateRangePatchVx();
        end

        function updateEditfieldLimits(obj)
            if obj.inStartup
                obj.sliderValueEditField(1).Limits = obj.Limits;
                obj.sliderValueEditField(2).Limits = obj.Limits;
                return
            end

            switch obj.ValueMode
                case "scalar"
                    obj.sliderValueEditField(1).Limits = obj.Limits;
                    obj.sliderValueEditField(2).Limits = obj.Limits;
                case "range"
                    obj.sliderValueEditField(1).Limits = [obj.Limits(1) obj.sliderThumb(2).Value];
                    obj.sliderValueEditField(2).Limits = [obj.sliderThumb(1).Value obj.Limits(2)];
            end
        end

    end

    %% Thumb management
    methods(Access=private)

        function selectThumb(obj, thumbIdx)
            % thumbIdx is not the active thumb -> deselect active
            if thumbIdx ~= obj.activeThumbIdx
                % deselect previously active thumb
                obj.deselectThumb(obj.activeThumbIdx);
            end
            % set new active
            obj.activeThumbIdx = thumbIdx;
            obj.sliderThumb(thumbIdx).select();
        end

        function deselectThumb(obj, thumbIdx)
            % NaN -> return
            if isnan(thumbIdx), return, end
            % deselect the thumb
            obj.sliderThumb(thumbIdx).deselect();
            % thumb was previously active -> clear active and hover idxs
            if thumbIdx==obj.activeThumbIdx
                obj.activeThumbIdx = NaN;
                obj.hoverThumbIdx = NaN;
            end
        end

        function clearHover(obj)
            % deselect hovered thumb
            obj.deselectThumb(obj.hoverThumbIdx);
        end

        function handleHover(obj, tgt)
            % we are already sliding -> return
            if obj.isSliding, return; end
            % hover target is not a thumb -> deselect previously hovered thumb
            if ~isprop(tgt, 'ID')
                obj.deselectThumb(obj.hoverThumbIdx);
                return
            end
            % get the new thumb idx
            idx = tgt.ID;
            if obj.ValueMode == "scalar" && idx ~= 1
                obj.deselectThumb(obj.hoverThumbIdx);
                return
            end
            % select the new thumb (any existing thumb will be deselected)
            obj.selectThumb(idx);
            % indicate it is the hovered thumb
            obj.hoverThumbIdx = idx;
        end

        function moveActiveThumbToCursor(obj)
            if isnan(obj.activeThumbIdx), return; end

            thumbIdx = obj.activeThumbIdx;
            thumbLims = obj.sliderValueEditField(obj.activeThumbIdx).Limits;
            newValue = clip(obj.sliderThumbAxes.CurrentPoint(1,1),thumbLims(1),thumbLims(2));

            if obj.RoundValues
                newValue = round(newValue,obj.RoundDigits);
            end

            if newValue == obj.sliderThumb(thumbIdx).Value
                return
            end

            obj.sliderThumb(thumbIdx).Value = newValue;
            obj.sliderValueEditField(thumbIdx).Value = newValue;
            obj.updateRangePatchVx();

            % emit ValueChanging event
            obj.onValueChanging();

        end

    end

    %% Dependent Set/Get
    methods

        function set.ValueMode(obj, val)
            obj.ValueMode = val;
            obj.applyModeAppearance();
        end

        function set.ShowEditFields(obj, val)
            obj.ShowEditFields = val;
            obj.applyModeAppearance();
        end

        function set.ShowFill(obj, val)
            obj.ShowFill = val;
            obj.applyModeAppearance();
        end

        function Value = get.Value(obj)
            switch obj.ValueMode
                case "scalar"
                    Value = obj.sliderThumb(1).Value;
                case "range"
                    Value = [obj.sliderThumb(1).Value, obj.sliderThumb(2).Value];
            end
        end

        function set.Value(obj, val)

            if obj.RoundValues
                val = round(val,obj.RoundDigits);
            end

            switch obj.ValueMode
                case "scalar"
                    if ~isscalar(val)
                        error('matlabx:ui:control:Slider:InvalidValue', ...
                            'Scalar sliders require Value to be a scalar.');
                    end

                    lims = obj.sliderValueEditField(1).Limits;
                    val = clip(val,lims(1),lims(2));

                    if isequal(val, obj.Value)
                        return
                    end

                    obj.sliderThumb(1).Value = val;
                    obj.sliderValueEditField(1).Value = val;

                case "range"
                    if numel(val) ~= 2
                        error('matlabx:ui:control:Slider:InvalidValue', ...
                            'Range sliders require Value to be a two-element vector.');
                    end

                    val = reshape(val, 1, 2);

                    lims1 = obj.sliderValueEditField(1).Limits;
                    lims2 = obj.sliderValueEditField(2).Limits;

                    val(1) = clip(val(1),lims1(1),lims1(2));
                    val(2) = clip(val(2),lims2(1),lims2(2));

                    if isequal(val, obj.Value)
                        return
                    end

                    % update thumbs
                    obj.sliderThumb(1).Value = val(1);
                    obj.sliderThumb(2).Value = val(2);

                    % update editfield values
                    obj.sliderValueEditField(1).Value  = val(1);
                    obj.sliderValueEditField(2).Value  = val(2);
            end

            % update x-coordinates of range patch vertices
            obj.updateRangePatchVx();

        end

        function parentFig = get.parentFig(obj)
            parentFig = ancestor(obj,'figure','toplevel');
        end

        function H = get.ComponentHeight(obj)
            % H = ceil(obj.Height + obj.titleLabel.Position(4) + 10);
            % H = ceil(obj.Height + obj.FontSize*1.4 + 10);

            H = obj.Height*2 + 10 + 1;
        end

        function val = get.ValueDisplayFormat(obj)
            val = obj.ValueDisplayFormat_;
        end

        function set.ValueDisplayFormat(obj,val)
            set(obj.sliderValueEditField,'ValueDisplayFormat',val);
            obj.ValueDisplayFormat_ = val;
        end

        function val = get.Title(obj)
            val = obj.Title_;
        end

        function set.Title(obj,val)
            obj.titleLabel.Text = val;
            obj.Title_ = val;
        end

        function val = get.FontSize(obj)
            val = obj.FontSize_;
        end

        function set.FontSize(obj,val)
            set([obj.titleLabel,obj.minLabel,obj.maxLabel,...
                obj.sliderValueEditField(1),obj.sliderValueEditField(2)],...
                "FontSize",val);
            obj.FontSize_ = val;
        end

        function val = get.FontColor(obj)
            val = obj.FontColor_;
        end

        function set.FontColor(obj,val)
            set([obj.titleLabel,obj.minLabel,obj.maxLabel],...
                "FontColor",val);
            obj.FontColor_ = val;
        end

    end

    %% Callbacks
    methods

        function sliderEditfieldValueChanged(obj, source, ~)
            obj.Value(source.UserData) = source.Value;
            obj.onValueChanged();
        end

        function onValueChanging(obj, ~, ~)
            notify(obj,'ValueChanging');
        end

        function onValueChanged(obj, ~, ~)
            notify(obj,'ValueChanged');
        end

    end

    %% Hub-facing event handlers
    methods

        function tf = matches(obj, E)

            tgtAncestor = ancestor(E.Target, 'matlab.ui.control.UIAxes');

            if isempty(tgtAncestor) || isa(E.Target,'matlab.ui.control.UIAxes')
                tf = false;
                return
            end

            % true if sliderThumbAxes is the ancestor of the tgt
            tf = obj.sliderThumbAxes == tgtAncestor;

        end

        function onDown(obj, E)

            if isprop(E.Target, 'ID')
                thumbIdx = E.Target.ID;
            else
                cursorX = obj.sliderThumbAxes.CurrentPoint(1,1);
                [~, thumbIdx] = min(abs(obj.Value - cursorX));
            end

            obj.selectThumb(thumbIdx);
            obj.isSliding = true;
            obj.moveActiveThumbToCursor();
        end

        function onMove(obj, E)
            if obj.isSliding
                obj.moveActiveThumbToCursor();
            else
                obj.handleHover(E.Target);
            end
        end

        function onUp(obj, ~)
            % Stop sliding and restore states
            obj.isSliding = false;
            % Deselect the active thumb (return to default size)
            obj.deselectThumb(obj.activeThumbIdx);
            % Clear hover so nothing stays enlarged after release
            obj.clearHover();
            % Update limits
            obj.updateEditfieldLimits();
            % emit ValueChanged
            obj.onValueChanged();
        end

        % No-ops so FigureEventHub doesn't error
        function onScroll(~, ~),    end
        function onKey(~, ~),       end

        function onEnter(obj,~)
            obj.parentFig.Pointer = 'hand';
        end

        function onLeave(obj,~)
            obj.clearHover();
            obj.parentFig.Pointer = 'arrow';
        end

    end

    methods (Static)

        function [s,ax] = demo()

            I = matlabx.image.Image5D.demo();
            N = I.NumComponents;
            fontSize = 12;
            viewerSize = 500;
            nNavigationSliders = 3;

            fig = uifigure(...
                "WindowStyle","alwaysontop",...
                "InnerPosition",[100,100,510,720],...
                "Color",[0 0 0],...
                "Visible","off",...
                "AutoResizeChildren","off");

            panelTopChrome = matlabx.UICal.panelChromeHeight(fontSize,"FontUnits","pixels");

            rowHeights = [{viewerSize + panelTopChrome}, repmat({'fit'}, 1, N + nNavigationSliders)];
            g = uigridlayout(fig,[N + nNavigationSliders + 1,1],...
                "BackgroundColor",[0 0 0],...
                "ColumnWidth",{500},...
                "RowHeight",rowHeights,...
                "Padding",[5 5 5 5],...
                "RowSpacing",5);

            ax = matlabx.ui.axes.ImageAxes(g,...
                "ImageData",I,...
                "FontSize",fontSize,...
                "ToolBelt",{'Zoom','Colorbar'});

            s = struct();
            s.C = matlabx.ui.control.Slider(g,...
                "Title",'C',...
                "ValueMode","scalar",...
                "FontColor",[1 1 1],...
                "Limits",[1 N],...
                "Value",ax.C,...
                "RoundValues","on",...
                "RoundDigits",0,...
                "ValueDisplayFormat",'%d',...
                "TrackColor",[0 0 0],...
                "ValueChangingFcn",@(o,~) setC(o),...
                "ValueChangedFcn",@(o,~) setC(o));

            s.Z = matlabx.ui.control.Slider(g,...
                "Title",'Z',...
                "ValueMode","scalar",...
                "FontColor",[1 1 1],...
                "Limits",[1 I.SizeZ],...
                "Value",ax.Z,...
                "RoundValues","on",...
                "RoundDigits",0,...
                "ValueDisplayFormat",'%d',...
                "TrackColor",[0 0 0],...
                "ValueChangingFcn",@(o,~) setZ(o),...
                "ValueChangedFcn",@(o,~) setZ(o));

            s.T = matlabx.ui.control.Slider(g,...
                "Title",'T',...
                "ValueMode","scalar",...
                "FontColor",[1 1 1],...
                "Limits",[1 I.SizeT],...
                "Value",ax.T,...
                "RoundValues","on",...
                "RoundDigits",0,...
                "ValueDisplayFormat",'%d',...
                "TrackColor",[0 0 0],...
                "ValueChangingFcn",@(o,~) setT(o),...
                "ValueChangedFcn",@(o,~) setT(o));

            s.CLim = matlabx.ui.control.Slider.empty(1,0);

            for c = 1:N
                comp = I.Components(c);
                compName = comp.Name;
                if strlength(compName) == 0
                    compName = "Component " + c;
                end

                switch comp.Class
                    case {'double','single'}
                        displayFmt = '%.2f';
                        roundDigits = 2;
                    case {'uint8','uint16'}
                        displayFmt = '%d';
                        roundDigits = 0;
                    otherwise
                        displayFmt = '%.2f';
                        roundDigits = 2;
                end

                s.CLim(c) = matlabx.ui.control.Slider(g,...
                    "Title",char(compName),...
                    "FontColor",[1 1 1],...
                    "Limits",comp.DataRange,...
                    "Value",comp.DataRange,...
                    "RoundValues","on",...
                    "RoundDigits",roundDigits,...
                    "ValueDisplayFormat",displayFmt,...
                    "TrackColor",[0 0 0],...
                    "ValueChangingFcn",@(o,~) setCLimDuringSlide(o,c),...
                    "ValueChangedFcn",@(o,~) setCLim(o,c));
            end

            sliderHeight = s.C.ComponentHeight;
            fig.InnerPosition(4) = viewerSize + panelTopChrome + ...
                (N + nNavigationSliders)*sliderHeight + ...
                (N + nNavigationSliders)*5 + 10;

            movegui(fig,'center')
            fig.Visible = "on";

            function setC(src)
                ax.C = src.Value;
            end

            function setZ(src)
                ax.Z = src.Value;
            end

            function setT(src)
                ax.T = src.Value;
            end

            function setCLimDuringSlide(src,channelIdx)
                ax.MaxRenderedResolution = 500;
                ax.setCLim(src.Value,channelIdx);
            end

            function setCLim(src,channelIdx)
                ax.setCLim(src.Value,channelIdx);
                ax.MaxRenderedResolution = 'none';
            end

        end

    end
    
end

function val = onOffChar(tf)
if tf
    val = 'on';
else
    val = 'off';
end
end
