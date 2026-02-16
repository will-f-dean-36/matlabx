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
        % BoxCreatedFcn:        data.ID, data.CenterPx, data.BoxSize
        % BoxMoveStartedFcn:    data.ID
        % BoxPreviewMovedFcn:   data.ID, data.CenterPx
        % BoxMoveCommittedFcn:  data.ID, data.CenterPx
        % BoxDeletedFcn:        data.ID
        % BoxActivatedFcn:      data.ID
        BoxCreatedFcn
        BoxMoveStartedFcn
        BoxPreviewMovedFcn
        BoxMoveCommittedFcn
        BoxDeletedFcn
        BoxActivatedFcn
    end

    % Identity
    properties (Access=private)
        % track box IDs in parallel with ROI handles
        BoxIds (1,:) string = string.empty(1,0)
        ActiveBoxIdx = []
        ActiveHoverIdx = []
    end

    % Box Settings/Info
    properties
        BoxSize (1,1) double = 50
        BoxCenters (:,2) double = []
    end

    properties (SetAccess=private, Dependent)
        nBoxes
    end


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
            % ID = string(char(java.util.UUID.randomUUID()));
            ID = guitools.utils.uniqueID();

            % Draw now; notify controller (optimistic)
            obj.addBox(ID, [cx cy], s);

            if ~isempty(obj.BoxCreatedFcn)
                obj.BoxCreatedFcn(H, struct('ID', ID, 'CenterPx', [cx cy], 'BoxSize', s));
            end

        end

    end

    %% Passive event hooks (only when Installed==true && IsDistractor==true)
    methods

        function tf = onDistractDown(obj,~,tgt)
            % tf = onDistractDown(obj,evt,tgt)

            obj.printStatus(sprintf('%s.onDistractDown()\n',obj.Name));


            % % ROIBox clicks handled by patch (drag/delete)
            % if isa(tgt,'matlab.graphics.primitive.Patch') && strcmp(get(tgt,'Tag'),'ROIBox')
            %     tf = true;
            % else
            %     tf = false;
            % end


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

            % reset ActiveBoxIdx if necessary
            if ~isempty(obj.ActiveBoxIdx) && obj.ActiveBoxIdx == obj.nBoxes
                obj.setActiveBoxByIdx([]);
            end

            delete(obj.BoxROI(idx));
            obj.BoxROI(idx) = [];
            obj.BoxCenters(idx,:) = [];
            obj.BoxIds(idx) = [];

        end

        % executes on mouse down when the target is an ROIBox patch
        function boxClickedById(obj, id)

            idx = obj.idxOfId(id);

            if isempty(idx), return; end

            obj.setActiveBoxByIdx(idx);

            switch obj.Host.ParentFig.SelectionType
                case 'normal'
                    % indicate that we are primed for drag
                    obj.Host.setMode('PrimedForDrag',true);
                case 'alt'   % delete immediately (optimistic), then notify
                    obj.deleteBoxByIdx(idx);   % remove overlay now
                    % call BoxDeletedFcn if it exists, pass ID
                    if ~isempty(obj.BoxDeletedFcn)
                        obj.BoxDeletedFcn(obj, struct('ID', string(id)));
                    end
            end

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
            % obj.setActiveBoxByIdx([]);
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
            % try
            %     if isvalid(obj.BoxROI(obj.ActiveHoverIdx))
            %         obj.BoxROI(obj.ActiveHoverIdx).HoverHighlight = 'off';
            %     end
            % catch
            %     blah = 0;
            % end

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

        function [cX,cY] = clampCenter(obj, ctr, boxSize)

            % x and y coordinates of the center
            x = ctr(1); y = ctr(2);

            % snap center to pixel center if boxSize is odd, pixel edge if even
            if mod(boxSize,2)==1
                % Odd size: center must be at integer pixel centers
                cX = round(x);
                cY = round(y);
            else
                % Even size: center must be at half-integers (i.e. nearest .5)
                cX = floor(x) + 0.5;
                cY = floor(y) + 0.5;
            end

            % clamp the center coordinates so the box remains in the image bounds
            half = boxSize/2;
            cX = clip(cX, 0.5+half, obj.Host.ImageWidth +0.5-half);
            cY = clip(cY, 0.5+half, obj.Host.ImageHeight+0.5-half);

        end

    end


    %% Host-facing methods

    methods

        function addBox(obj, id, center_px, boxSize)
            if nargin<4 || isempty(boxSize)
                boxSize = obj.BoxSize;
            end

            [cx,cy] = obj.clampCenter(center_px, boxSize);
            next = obj.nBoxes + 1;

            hostAxes = obj.Host.getAxes();

            obj.BoxROI(next) = guitools.widgets.overlays.ROIBox(hostAxes, ...
                "Center",[cx cy], ...
                "BoxSize", boxSize, ...
                "ID", string(id), ...
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
            obj.setActiveBoxByIdx([]);
        end

        function setActiveBoxByID(obj, id)
            % get box idx from ID
            idx = obj.idxOfId(id); 
            % if empty, return
            if isempty(idx), return; end
            % set active box using its idx
            obj.setActiveBoxByIdx(idx);
        end

        function setActiveBoxByIdx(obj, idx)
            % if no boxes exist, set empty and return
            if obj.nBoxes == 0
                obj.ActiveBoxIdx = [];
                return
            end

            % deselect current active box
            if ~isempty(obj.ActiveBoxIdx)
                obj.BoxROI(obj.ActiveBoxIdx).SelectionHighlight = 'off';
                obj.ActiveBoxIdx = [];
            end

            % if empty, return
            if isempty(idx), return; end

            % set new ActiveBoxIdx
            obj.ActiveBoxIdx = idx;
            % and turn on the SelectionHighlight for that box
            obj.BoxROI(obj.ActiveBoxIdx).SelectionHighlight = 'on';

            % call BoxActivatedFcn if it exists
            if ~isempty(obj.BoxActivatedFcn)
                ID = obj.BoxIds(idx);
                obj.BoxActivatedFcn(obj, struct('ID', ID));
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