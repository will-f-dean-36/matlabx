classdef Pick < guitools.widgets.ImageAxesTool
% guitools.widgets.tools.Pick - optimistic box creation on click

    %% Draggable box management

    %% Private UI/Graphics
    properties (Access = private, Transient, NonCopyable)
        BoxROI (:,1) guitools.widgets.overlays.ROIBox
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
        ActiveBoxIdx = []
        ActiveHoverIdx = []
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
            obj@guitools.widgets.ImageAxesTool(host, "Pick",...
                'Tooltip','Pick regions',...
                'Icon',guitools.Paths.icons('AddRectangleIcon.png'),...
                'Priority',10,...
                'IsExclusive',true,...
                'CapturesDown',true,...
                'DistractsDown',true,...
                'DistractsMove',true,...
                'DistractsUp',true);

            % ROIBox array (empty to start)
            obj.BoxROI = guitools.widgets.overlays.ROIBox.empty();

        end

        % Toggled Enabled=true via toolbar button
        function onEnabled(obj)
            obj.Host.setMode('Pick', true);
        end

        % Toggled Enabled=false via toolbar button
        function onDisabled(obj)
            obj.Host.setMode('Pick', false);
        end

        % Called AFTER installed from Host, use for any extra required startup actions
        function onInstall(obj)
            obj.Host.addMode('Pick');
            obj.Host.addMode('PrimedForDrag')
            obj.Host.addMode('DragBox');
            obj.Host.addMode('HoverBox');
        end

        % Called AFTER uninstalled from Host, use for any extra required cleanup actions
        function onUninstall(obj)
            obj.Host.removeMode('Pick');
            obj.Host.removeMode('PrimedForDrag')
            obj.Host.removeMode('DragBox');
            obj.Host.removeMode('HoverBox');
            obj.clearBoxes();
        end

    end

    %% Active event hooks (only when Enabled==true && IsInterceptor==true)
    methods

        function onDown(obj, ~, ~)

            H = obj.Host;
            XY = H.cursorPosition;

            if isempty(XY)
                return
            end

            s = obj.BoxSize;
            [cx,cy] = obj.clampCenter(XY, s);
            ID = guitools.utils.uniqueID();

            % Draw now; notify controller (optimistic)
            obj.addBox(ID, [cx cy], s);      

            if ~isempty(obj.BoxCreatedFcn)
                obj.BoxCreatedFcn(H, struct('ID', ID, 'CenterPx', [cx cy], 'BoxSize', s));
            end

            % selection behavior: normal replaces, extend adds
            switch obj.Host.ParentFig.SelectionType
                case 'extend'
                    obj.addToSelection(ID, 'Emit', true);
                otherwise
                    obj.setSelection(ID, 'Emit', true);
            end    
        end

    end

    %% Passive event hooks (only when Installed==true && IsDistractor==true)
    methods

        function tf = onDistractDown(obj,~,tgt)
            obj.printStatus(sprintf('%s.onDistractDown()\n',obj.Name));

            % ROIBox clicks handled by patch (drag/delete)
            if isprop(tgt,'ID') && obj.hasBox(tgt.ID)
                tf = true;
            else
                tf = false;
            end
        end


        function tf = onDistractMove(obj,~,tgt)
            tf = false;

            % if we are primed for drag (button down on box with no cursor movement)
            if obj.Host.Mode.PrimedForDrag
                % start dragging
                obj.startDraggingBox(obj.ActiveBoxIdx);
                return
            end

            % if we are in the middle of dragging a box
            if obj.Host.Mode.DragBox
                % keep dragging and return
                obj.dragBox(obj.ActiveBoxIdx);
                return
            end

            % cursor target is ROIBox patch
            if isa(tgt,'matlab.graphics.primitive.Patch') && strcmp(get(tgt,'Tag'),'ROIBox')
                % turn HoverHighlight mode 'on' on the box (get idx from custom patch property, ID)
                obj.startHoverByIdx(obj.idxOfId(tgt.ID));
            else % cursor target is anything else
                % turn off HoverHighlight mode for box corresponding to ActiveHoverIdx, if it exists
                obj.stopHover();
            end

        end

        function tf = onDistractUp(obj,~,~)
            tf = false;

            if obj.Host.Mode.PrimedForDrag
                % un-prime
                obj.Host.setMode('PrimedForDrag',false);
                return
            end

            if obj.Host.Mode.DragBox
                obj.stopDraggingBox(obj.ActiveBoxIdx);
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

        function idx = idxOfId(obj, id)
            idx = find(obj.BoxIds == string(id), 1, 'first');
        end

        % check if this tool owns box indicated by id
        function TF = hasBox(obj,id)
            TF = ismember(id,obj.BoxIds);
        end

        function deleteBoxByIdx(obj, idx)

            % reset ActiveHoverIdx if necessary
            if ~isempty(obj.ActiveHoverIdx) && obj.ActiveHoverIdx == idx
                obj.Host.setMode('HoverBox',false);
                obj.ActiveHoverIdx = [];
            end

            % remove from selection first
            id = obj.BoxIds(idx);
            obj.SelectedBoxIds(obj.SelectedBoxIds == id) = [];

            % reset ActiveBoxIdx if necessary
            if ~isempty(obj.ActiveBoxIdx) && obj.ActiveBoxIdx == obj.nBoxes
                obj.ActiveBoxIdx = [];
            end

            delete(obj.BoxROI(idx));
            obj.BoxROI(idx) = [];
            obj.BoxCenters(idx,:) = [];
            obj.BoxIds(idx) = [];

            % repair active idx if needed (best-effort)
            if ~isempty(obj.SelectedBoxIds)
                obj.ActiveBoxIdx = obj.idxOfId(obj.SelectedBoxIds(1));
            end

            obj.applySelectionHighlights();
            obj.emitSelectionChanged();

        end

        function boxClickedById(obj, id)
            id = string(id);
            idx = obj.idxOfId(id);
            if isempty(idx), return; end
        
            switch obj.Host.ParentFig.SelectionType
                case 'alt'   % delete immediately (optimistic), then notify
                    obj.deleteBoxByIdx(idx);   % remove overlay now
                    if ~isempty(obj.BoxDeletedFcn)
                        obj.BoxDeletedFcn(obj, struct('ID', id));
                    end
                    return
        
                case 'extend' % shift-click toggles selection membership
                    if ismember(id, obj.SelectedBoxIds)
                        obj.removeFromSelection(id, 'Emit', true);
                    else
                        obj.addToSelection(id, 'Emit', true);
                    end
        
                otherwise
                    obj.setSelection(id, 'Emit', true);
            end
        
            % prime drag only for normal click (single select)
            if obj.Host.ParentFig.SelectionType == "normal"
                obj.Host.setMode('PrimedForDrag', true);
            end
        end


        function setSelection(obj, id, opts)
            arguments
                obj
                id
                opts.Emit (1,1) logical = false
            end

            id = string(id);
            obj.SelectedBoxIds = id;
            obj.ActiveBoxIdx = obj.idxOfId(id);
        
            obj.applySelectionHighlights();


            % testing below
            if ~isempty(obj.BoxActivatedFcn)
                obj.BoxActivatedFcn(obj, struct('ID', id));
            end
            % end testing

        
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

            % id = string(id);
            if ~ismember(id, obj.SelectedBoxIds)
                obj.SelectedBoxIds(end+1) = id;
            end
            obj.ActiveBoxIdx = obj.idxOfId(id);
            obj.applySelectionHighlights();

            % testing below
            if ~isempty(obj.BoxActivatedFcn)
                obj.BoxActivatedFcn(obj, struct('ID', id));
            end
            % end testing

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

            % id = string(id);
            obj.SelectedBoxIds(obj.SelectedBoxIds == id) = [];


            % active box was deselected
            if obj.idxOfId(id) == obj.ActiveBoxIdx
                % some boxes are still selected
                if ~isempty(obj.SelectedBoxIds)
                    % make the last one active
                    newID = obj.SelectedBoxIds(end);
                    obj.ActiveBoxIdx = obj.idxOfId(newID);
                else
                    % no selection -> no active box
                    newID = [];
                    obj.ActiveBoxIdx = [];
                end

                % testing below
                if ~isempty(obj.BoxActivatedFcn)
                    obj.BoxActivatedFcn(obj, struct('ID', newID));
                end
                % end testing

            end

            obj.applySelectionHighlights();

            if opts.Emit
                obj.emitSelectionChanged();
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

            % apply selected highlights
            if isempty(obj.SelectedBoxIds), return; end
            for i = 1:numel(obj.SelectedBoxIds)
                idx = obj.idxOfId(obj.SelectedBoxIds(i));
                if ~isempty(idx) && idx>=1 && idx<=numel(obj.BoxROI) && isvalid(obj.BoxROI(idx))
                    obj.BoxROI(idx).SelectionHighlight = 'on';
                end
            end

            % apply active highlight
            if ~isempty(obj.ActiveBoxIdx)
                obj.BoxROI(obj.ActiveBoxIdx).ActiveHighlight = 'on';
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
            if isempty(XY) || idx<1 || idx>obj.nBoxes || ~isvalid(obj.BoxROI(idx)), return; end
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
            obj.Host.setMode('PrimedForDrag',false);
            % we are now dragging
            obj.Host.setMode('DragBox',true);
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
            if ~isempty(idx) && isscalar(idx) && idx>=1 && idx<=obj.nBoxes && isvalid(obj.BoxROI(idx))
                obj.dragBox(idx); % snap to final position before stopping drag
                if ~isempty(obj.BoxMoveCommittedFcn)
                    ID = obj.BoxIds(idx);
                    ctr  = obj.BoxCenters(idx,:);
                    obj.BoxMoveCommittedFcn(obj, struct('ID', ID, 'CenterPx', ctr));
                end
            end
            obj.Host.setMode('DragBox',false);
            obj.Host.updateFromTool();
        end

        % set HoverHighlight mode to 'on' for box specified by idx
        function startHoverByIdx(obj, idx)
            % idx is empty, return
            if isempty(idx), return; end
            % we are already hovering on this box, return
            if idx == obj.ActiveHoverIdx, return; end
            % if another box was being hovered on
            if ~isempty(obj.ActiveHoverIdx)
                % turn its hover status off
                obj.BoxROI(obj.ActiveHoverIdx).HoverHighlight = 'off';
            end
            % turn hover on for the box specified by idx
            obj.BoxROI(idx).HoverHighlight = 'on';
            % set that idx as the ActiveHoverIdx
            obj.ActiveHoverIdx = idx;
            % set Host HoverMox mode to true
            obj.Host.setMode('HoverBox', true);
        end

        % set HoverHighlight mode to 'off' for box indicated by ActiveHoverIdx, if any
        function stopHover(obj)
            % if HoverBox Mode is already off, return
            if ~obj.Host.Mode.HoverBox, return; end
            % if ActiveHoverIdx is empty, return
            if isempty(obj.ActiveHoverIdx), return; end

            % set HoverHighlight off on current active box (if valid)
            if isvalid(obj.BoxROI(obj.ActiveHoverIdx))
                obj.BoxROI(obj.ActiveHoverIdx).HoverHighlight = 'off';
            end

            % set ActiveHoverIdx as empty
            obj.ActiveHoverIdx = [];
            % set HoverBox Mode to off
            obj.Host.setMode('HoverBox', false);
        end


    end

    methods (Hidden=true)

        function [cX,cY] = clampCenter(obj, C, boxSize)
            W = obj.Host.ImageWidth;
            H = obj.Host.ImageHeight;
            C = imtools.clampBoxToImage(C,boxSize,[W, H]);
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

            obj.BoxROI(next) = guitools.widgets.overlays.ROIBox(hostAxes, ...
                "Center",[cx cy], ...
                "BoxSize", boxSize, ...
                "ID", string(id), ...
                "Label", opts.Label, ...
                "EdgeColor", opts.EdgeColor, ...
                "FaceColor", opts.FaceColor, ...
                "ButtonDownFcn", @(~,~) obj.boxClickedById(string(id)));

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
            obj.BoxROI = guitools.widgets.overlays.ROIBox.empty();
            obj.BoxCenters = zeros(0,2);
            obj.BoxIds = string.empty(1,0);
            obj.ActiveBoxIdx = [];
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
            if ~isempty(obj.SelectedBoxIds)
                obj.ActiveBoxIdx = obj.idxOfId(obj.SelectedBoxIds(1));
            else
                obj.ActiveBoxIdx = [];
            end
        
            obj.applySelectionHighlights();
        
            if opts.Emit
                obj.emitSelectionChanged();
            end
        end


        function ids = getSelectedBoxIDs(obj)
            ids = obj.SelectedBoxIds;
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
            if obj.Host.Mode.DragBox
                pointer = 'fleur';
            elseif obj.Host.Mode.HoverBox
                pointer = 'hand';
            elseif obj.Host.Mode.Pick
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