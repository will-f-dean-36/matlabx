classdef Pick < matlabx.ui.axes.AxesTool
% matlabx.ui.axes.tools.Pick - optimistic box creation on click

    %% Draggable box management

    %% Private UI/Graphics
    properties (Access = private, Transient, NonCopyable)
        BoxROI (:,1) matlabx.ui.axes.overlays.ROIBox
    end

    % Callbacks
    properties
        % Optimistic, widget-first events (controller may ignore them):
        % BoxCreatedFcn:            data.ID, data.CenterPx, data.BoxSize
        % BoxMoveStartedFcn:        data.ID
        % BoxPreviewMovedFcn:       data.ID, data.CenterPx
        % BoxMoveCommittedFcn:      data.ID, data.CenterPx
        % BoxDeletedFcn:            data.ID
        % BoxActivatedFcn:          data.ID
        % BoxSelectionChangedFcn:   data.IDs
        BoxCreatedFcn
        BoxMoveStartedFcn
        BoxPreviewMovedFcn
        BoxMoveCommittedFcn
        BoxDeletedFcn
        BoxActivatedFcn
        BoxSelectionChangedFcn
    end

    % Identity
    properties (Access=private)
        % track box IDs in parallel with ROI handles
        BoxIds (1,:) string = string.empty(1,0)
        ActiveBoxId (1,1) string = ""
        ActiveHoverId (1,1) string = ""
        SelectedBoxIds (1,:) string = string.empty(1,0)
    end

    % Box Settings/Info
    properties
        BoxSize (1,1) double = 50
        BoxCenters (:,2) double = []
    end

    properties (SetAccess=private, Dependent)
        nBoxes
    end

    %% Lifecycle toggles
    methods
        function obj = Pick(host)
            obj@matlabx.ui.axes.AxesTool(host, "Pick",...
                'Tooltip','Pick regions',...
                'AxesType',"image",...
                'Icon',matlabx.internal.Paths.icons('AddRectangleIcon.png'),...
                'Priority',10,...
                'IsExclusive',true,...
                'InterceptsDown',true,...
                'PassivelyInterceptsDown',true,...
                'PassivelyInterceptsMove',true,...
                'PassivelyInterceptsUp',true);

            % ROIBox array (empty to start)
            obj.BoxROI = matlabx.ui.axes.overlays.ROIBox.empty();

        end
        % Called AFTER installed from Host, use for any extra required startup actions
        function onInstall(obj)
            obj.addMode('PrimedForDrag');
            obj.addMode('DragBox');
            obj.addMode('HoverBox');
        end

        % Called AFTER uninstalled from Host, use for any extra required cleanup actions
        function onUninstall(obj)
            obj.removeMode('PrimedForDrag');
            obj.removeMode('DragBox');
            obj.removeMode('HoverBox');
            obj.clearBoxes();
        end

    end

    %% Active event hooks (only when Enabled==true && IsInterceptor==true)
    methods

        function onDown(obj, E)

            if E.MouseChord ~= "click"
                return
            end

            H = obj.Host;
            XY = H.cursorPosition;

            if isempty(XY)
                return
            end

            s = obj.BoxSize;
            [cx,cy] = obj.clampCenter(XY, s);
            ID = matlabx.utils.text.uniqueID();

            % Draw now; notify controller (optimistic)
            obj.addBox(ID, [cx cy], s);      

            if ~isempty(obj.BoxCreatedFcn)
                obj.BoxCreatedFcn(H, struct('ID', ID, 'CenterPx', [cx cy], 'BoxSize', s));
            end

            obj.setActive(ID);
        end

    end

    %% Passive event hooks (only when Installed==true && IsPassiveInterceptor==true)
    methods

        function onPassiveDown(obj,E)
            obj.printStatus(sprintf('%s.onPassiveDown()', obj.Name));

            % ROIBox clicks handled by patch (drag/delete)
            if isprop(E.Target,'ID') && obj.hasBox(E.Target.ID)
                obj.boxClickedById(E.Target.ID,E);
                E.stop();
            end
        end

        function onPassiveMove(obj,E)

            % if we are primed for drag (button down on box with no cursor movement)
            if obj.Mode.PrimedForDrag
                % start dragging
                obj.startDraggingBox(obj.activeBoxIdx());
                return
            end

            % if we are in the middle of dragging a box
            if obj.Mode.DragBox
                % keep dragging and return
                obj.dragBox(obj.activeBoxIdx());
                return
            end

            % cursor target is ROIBox patch
            if isa(E.Target,'matlab.graphics.primitive.Patch') && strcmp(get(E.Target,'Tag'),'ROIBox')
                % turn HoverHighlight mode 'on' on the box (get idx from custom patch property, ID)
                obj.startHoverById(E.Target.ID);
            else % cursor target is anything else
                % turn off HoverHighlight mode for box corresponding to ActiveHoverId, if it exists
                obj.stopHover();
            end

        end

        function onPassiveUp(obj,~)

            if obj.Mode.PrimedForDrag
                % no longer primed for drag
                obj.setMode('PrimedForDrag',false);
                return
            end

            if obj.Mode.DragBox
                obj.stopDraggingBox(obj.activeBoxIdx());
            end
        end

    end

    %% Derived getters
    methods

        function n = get.nBoxes(obj)
            if isempty(obj.BoxROI), n = 0; else, n = sum(isvalid(obj.BoxROI)); end
        end

    end


    %% Private Helpers (Pick)
    methods (Access=private)

        function id = normalizeId_(~, id)
            id = string(id);

            if isempty(id)
                id = "";
            else
                id = id(1);
            end
        end

        function idx = idxOfId(obj, id)
            id = obj.normalizeId_(id);
            if strlength(id) == 0
                idx = [];
                return
            end

            idx = find(obj.BoxIds == id, 1, 'first');
        end

        function idx = activeBoxIdx(obj)
            idx = obj.idxOfId(obj.ActiveBoxId);
        end

        function idx = activeHoverIdx(obj)
            idx = obj.idxOfId(obj.ActiveHoverId);
        end

        function TF = isValidBoxIdx(obj, idx)
            TF = ~isempty(idx) ...
                && isscalar(idx) ...
                && idx>=1 ...
                && idx<=numel(obj.BoxROI) ...
                && isvalid(obj.BoxROI(idx));
        end

        % check if this tool owns box indicated by id
        function TF = hasBox(obj,id)
            id = obj.normalizeId_(id);
            TF = strlength(id) > 0 && ismember(id,obj.BoxIds);
        end

        function deleteBoxById(obj, id)
            id = obj.normalizeId_(id);
            idx = obj.idxOfId(id);
            if ~obj.isValidBoxIdx(idx), return; end

            obj.deleteBoxByIdx(idx);

            if ~isempty(obj.BoxDeletedFcn)
                obj.BoxDeletedFcn(obj, struct('ID', id));
            end
        end

        function deleteBoxByIdx(obj, idx)
            if ~obj.isValidBoxIdx(idx)
                return
            end

            id = obj.BoxIds(idx);

            % reset ActiveHoverId if necessary
            if obj.ActiveHoverId == id
                obj.setMode('HoverBox',false);
                obj.ActiveHoverId = "";
            end

            % remove from selection first
            obj.SelectedBoxIds(obj.SelectedBoxIds == id) = [];


            % reset ActiveBoxId if necessary
            if obj.ActiveBoxId == id
                obj.ActiveBoxId = "";
                obj.emitActiveChanged("");
            end

            % delete
            delete(obj.BoxROI(idx));
            obj.BoxROI(idx) = [];
            obj.BoxCenters(idx,:) = [];
            obj.BoxIds(idx) = [];

            %obj.applySelectionHighlights();

            % notify
            obj.emitSelectionChanged();

        end

        function boxClickedById(obj, id, E)
            id = obj.normalizeId_(id);
            if ~obj.hasBox(id), return; end

            switch E.MouseChord
                case "control+contextclick"
                    obj.deleteBoxById(id);
                    return

                case "alt+click"
                    obj.deactivateActive();

                case "shift+extendclick"
                    obj.toggleSelection(id, 'Emit', true);

                case "click"
                    obj.setActive(id);
                    obj.primeDrag();
            end
        end

        function primeDrag(obj)
            if obj.Enabled && strlength(obj.ActiveBoxId) > 0
                obj.setMode('PrimedForDrag', true);
            end
        end


        function setActive(obj, id)
            id = obj.normalizeId_(id);
            if ~obj.isValidBoxIdx(obj.idxOfId(id)), return; end

            obj.ActiveBoxId = id;
        
            obj.applySelectionHighlights();
            obj.emitActiveChanged(id);

        end

        function deactivateActive(obj)
            if strlength(obj.ActiveBoxId) == 0
                return
            end

            obj.ActiveBoxId = "";
            obj.setMode('PrimedForDrag', false);
            obj.setMode('DragBox', false);
            obj.applySelectionHighlights();
            obj.emitActiveChanged("");
        end

        function emitActiveChanged(obj, id)
            if ~isempty(obj.BoxActivatedFcn)
                obj.BoxActivatedFcn(obj, struct('ID', obj.normalizeId_(id)));
            end
        end

        function setSelection(obj, id, opts)
            arguments
                obj
                id
                opts.Emit (1,1) logical = false
            end

            obj.SelectedBoxIds = id;

            obj.applySelectionHighlights();

            if opts.Emit
                obj.emitSelectionChanged();
            end
        end


        function addToSelection(obj, id, opts)
            arguments
                obj
                id
                opts.Emit (1,1) logical = false
            end

            if ~ismember(id, obj.SelectedBoxIds)
                obj.SelectedBoxIds(end+1) = id;
            end

            obj.applySelectionHighlights();

            if opts.Emit
                obj.emitSelectionChanged();
            end
        end

        function removeFromSelection(obj, id, opts)
            arguments
                obj
                id
                opts.Emit (1,1) logical = false
            end

            obj.SelectedBoxIds(obj.SelectedBoxIds == id) = [];
            obj.applySelectionHighlights();

            if opts.Emit
                obj.emitSelectionChanged();
            end
        end

        function toggleSelection(obj, id, opts)
            arguments
                obj
                id
                opts.Emit (1,1) logical = false
            end

            if ismember(id, obj.SelectedBoxIds)
                obj.removeFromSelection(id, 'Emit', opts.Emit);
            else
                obj.addToSelection(id, 'Emit', opts.Emit);
            end
        end

        function applySelectionHighlights(obj)
            % clear all selection and active highlights
            if isempty(obj.BoxROI), return; end
            for k = 1:numel(obj.BoxROI)
                if isvalid(obj.BoxROI(k))
                    set(obj.BoxROI(k),'SelectionHighlight','off','ActiveHighlight','off');
                end
            end

            % apply active highlight
            activeIdx = obj.activeBoxIdx();
            if obj.isValidBoxIdx(activeIdx)
                obj.BoxROI(activeIdx).ActiveHighlight = 'on';
            end

            % apply selected highlights
            if isempty(obj.SelectedBoxIds), return; end
            for i = 1:numel(obj.SelectedBoxIds)
                idx = obj.idxOfId(obj.SelectedBoxIds(i));
                if obj.isValidBoxIdx(idx)
                    obj.BoxROI(idx).SelectionHighlight = 'on';
                end
            end

        end

        function emitSelectionChanged(obj)
            if isempty(obj.BoxSelectionChangedFcn), return; end
            obj.BoxSelectionChangedFcn(obj, struct('IDs', obj.SelectedBoxIds));
        end

        % executes on mouse move when DragBox Mode is on
        function dragBox(obj, idx)
            XY = obj.Host.cursorPosition;
            % exit if pixel is empty or box idx is invalid
            if isempty(XY) || ~obj.isValidBoxIdx(idx), return; end
            % the size of the box being dragged
            s = obj.BoxROI(idx).BoxSize;
            % clamp so box edge does not exit image boundary
            [cx,cy] = obj.clampCenter(XY, s);
            % update center coordinates
            obj.BoxROI(idx).Center = [cx cy];
            obj.BoxCenters(idx,:)  = [cx cy];
            % emit high-frequency preview (controller may ignore)
            if ~isempty(obj.BoxPreviewMovedFcn)
                ID = obj.BoxIds(idx);
                obj.BoxPreviewMovedFcn(obj, struct('ID', ID, 'CenterPx', [cx cy]));
            end
        end

        % executes on mouse move when PrimedForDrag Mode is on
        function startDraggingBox(obj,idx)
            % we are no longer PrimedForDrag
            obj.setMode('PrimedForDrag',false);
            if ~obj.isValidBoxIdx(idx)
                return
            end
            % we are now dragging
            obj.setMode('DragBox',true);
            % fire BoxMoveStartedFcn
            if ~isempty(obj.BoxMoveStartedFcn)
                ID = obj.BoxIds(idx);
                obj.BoxMoveStartedFcn(obj, struct('ID', ID));
            end
            % request Host update
            obj.Host.updateFromTool();
        end

        % executes on mouse up when DragBox Mode is on
        function stopDraggingBox(obj, idx)
            if obj.isValidBoxIdx(idx)
                obj.dragBox(idx); % snap to final position before stopping drag
                if ~isempty(obj.BoxMoveCommittedFcn)
                    ID = obj.BoxIds(idx);
                    ctr  = obj.BoxCenters(idx,:);
                    obj.BoxMoveCommittedFcn(obj, struct('ID', ID, 'CenterPx', ctr));
                end
            end
            obj.setMode('DragBox',false);
            obj.Host.updateFromTool();
        end

        % set HoverHighlight mode to 'on' for box specified by id
        function startHoverById(obj, id)
            id = obj.normalizeId_(id);
            idx = obj.idxOfId(id);
            % idx is empty, return
            if ~obj.isValidBoxIdx(idx), return; end
            % we are already hovering on this box, return
            if id == obj.ActiveHoverId, return; end
            % if another box was being hovered on
            hoverIdx = obj.activeHoverIdx();
            if obj.isValidBoxIdx(hoverIdx)
                % turn its hover status off
                obj.BoxROI(hoverIdx).HoverHighlight = 'off';
            end
            % turn hover on for the box specified by idx
            obj.BoxROI(idx).HoverHighlight = 'on';
            % set that id as the ActiveHoverId
            obj.ActiveHoverId = id;
            % set Host HoverMox mode to true
            obj.setMode('HoverBox', true);
        end

        % set HoverHighlight mode to 'off' for box indicated by ActiveHoverId, if any
        function stopHover(obj)
            % if HoverBox Mode is already off, return
            if ~obj.Mode.HoverBox, return; end
            % if ActiveHoverId is empty, return
            if strlength(obj.ActiveHoverId) == 0, return; end

            % set HoverHighlight off on current active box (if valid)
            hoverIdx = obj.activeHoverIdx();
            if obj.isValidBoxIdx(hoverIdx)
                obj.BoxROI(hoverIdx).HoverHighlight = 'off';
            end

            % set ActiveHoverId as empty
            obj.ActiveHoverId = "";
            % set HoverBox Mode to off
            obj.setMode('HoverBox', false);
        end

    end

    methods (Hidden=true)

        function [cX,cY] = clampCenter(obj, C, boxSize)
            W = obj.Host.ImageWidth;
            H = obj.Host.ImageHeight;
            C = matlabx.image.roi.clampBoxToImage(C,boxSize,[W, H]);
            cX = C(1);
            cY = C(2);
        end

    end


    %% Host-facing methods

    methods

        function addBox(obj, id, center_px, boxSize, opts)
            arguments
                obj
                id
                center_px
                boxSize = []
                opts.EdgeColor = [1 1 1]
                opts.FaceColor = [1 1 1]
                opts.Label (1,1) string =  ""
            end

            if isempty(boxSize)
                boxSize = obj.BoxSize;
            end

            [cx,cy] = obj.clampCenter(center_px, boxSize);
            next = obj.nBoxes + 1;

            hostAxes = obj.Host.getAxes();

            obj.BoxROI(next) = matlabx.ui.axes.overlays.ROIBox(hostAxes, ...
                "Center",[cx cy], ...
                "BoxSize", boxSize, ...
                "ID", string(id), ...
                "Label", opts.Label, ...
                "EdgeColor", opts.EdgeColor, ...
                "FaceColor", opts.FaceColor);


            obj.BoxCenters(end+1,:) = [cx cy];
            obj.BoxIds(end+1)       = string(id);
        end

        function removeBox(obj, id)
            idx = obj.idxOfId(id); if isempty(idx), return; end
            obj.deleteBoxByIdx(idx);
        end

        function clearBoxes(obj)
            if ~isempty(obj.BoxROI)
                bx = obj.BoxROI(isvalid(obj.BoxROI)); if ~isempty(bx), delete(bx); end
            end
            obj.BoxROI = matlabx.ui.axes.overlays.ROIBox.empty();
            obj.BoxCenters = zeros(0,2);
            obj.BoxIds = string.empty(1,0);
            obj.ActiveBoxId = "";
            obj.ActiveHoverId = "";
            obj.SelectedBoxIds = string.empty(1,0);
        end

        function setSelectedBoxIDs(obj, ids, opts)
            arguments
                obj
                ids
                opts.Emit (1,1) logical = false
            end

            ids = string(ids);
            ids = ids(ismember(ids, obj.BoxIds));
            obj.SelectedBoxIds = ids(:).';

            obj.applySelectionHighlights();
        
            if opts.Emit
                obj.emitSelectionChanged();
            end
        end

        function ids = getSelectedBoxIDs(obj)
            ids = obj.SelectedBoxIds;
        end

        function clearBoxSelection(obj)
            obj.SelectedBoxIds = string.empty(1,0);
            obj.applySelectionHighlights();
        end

        function setActiveBoxID(obj,id)
            id = obj.normalizeId_(id);
            if strlength(id) == 0
                obj.deactivateActive();
            else
                obj.setActive(id);
            end
        end

        function setBoxLabelByID(obj, id, label)
            idx = obj.idxOfId(id);
            if isempty(idx), return; end
            if idx>=1 && idx<=numel(obj.BoxROI) && isvalid(obj.BoxROI(idx))
                set(obj.BoxROI(idx),'Label',label);
            end
        end

        function setBoxColorByID(obj, id, color)
            idx = obj.idxOfId(id);
            if isempty(idx), return; end
            if idx>=1 && idx<=numel(obj.BoxROI) && isvalid(obj.BoxROI(idx))
                set(obj.BoxROI(idx),'EdgeColor',color,'FaceColor',color);
            end
        end

        function setBoxesColorByIDs(obj, ids, color)
            ids = string(ids);
            for i = 1:numel(ids)
                obj.setBoxColorByID(ids(i), color);
            end
        end

    end

    %% Host update helpers
    methods

        function pointer = getPreferredPointer(obj)
            if obj.Mode.DragBox
                pointer = 'fleur';
            elseif obj.Mode.HoverBox
                pointer = 'hand';
            elseif obj.Enabled
                pointer = 'crosshair';
            else
                pointer = '';
            end
        end

    end

    %% Teardown
    methods (Access=protected)

        % called at the beginning of superclass delete()
        function teardown(obj)
            % Delete ROIBox objects (if any)
            try
                if ~isempty(obj.BoxROI)
                    bx = obj.BoxROI(isvalid(obj.BoxROI));
                    if ~isempty(bx), delete(bx); end
                end
            catch
            end
        end

    end

end
