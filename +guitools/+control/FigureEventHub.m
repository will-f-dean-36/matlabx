classdef FigureEventHub < handle
% guitools.control.FigureEventHub - Per-figure event hub that routes window-level events
% to registered handlers with priority and optional capture.

%% Notes/Definitions
%
% Registrant: object registered with the hub (e.g., widgets.ImageAxes)
%   Each registrant registers itself with the hub at startuo and must implement 
%   matches(tgt, kind, evt), which returns true if registrant should claim the event
%
% Registry entry: stored info about a registrant (id, obj, priority, CaptureDuringDrag)
%   id (stable numeric ID), obj (the registrant handle), priority (bigger wins), CaptureDuringDrag (logical)
%
% Priority: resolves overlaps—higher priority registrants get first dibs when multiple "match"
%
% Claimant: the registrant that currently matches the pointer/target under hub evaluation 
%   (i.e. the registrant that "claims" ownership of the current event)
% 
% Capture: when active, all events go exclusively to one registrant (the captor) until mouse-up
%   CaptureId: the stable ID of the current captor (or NaN if none)
%
% Hover: the registrant that currently "claims" the pointer (according to matches)
%   HoverId: the stable ID of the current hover claimant (or NaN if none)
% 
% Captor: the registrant currently holding capture
% 
% tgt: graphics obj under cursor (hittest(Fig) result)
% 
% kind: the event kind string the hub uses to sort events: 'move'|'down'|'up'|'scroll'
%   Corresponds to: WindowButtonMotionFcn | WindowButtonDownFcn | WindowButtonUpFcn | WindowScrollWheelFcn
%
% evt: the MATLAB event struct passed from the figure callback (e.g., WindowButtonDownFcn arg, etc.)

    properties (Access=private)
        Fig matlab.ui.Figure

        % struct of registrant info (each registrant registers themselves during startup)
        % Registry entries: struct('obj',handle,'Priority',double,'CaptureDuringDrag',logical)
        Registry = struct('obj',{},'id',{},'Priority',{},'CaptureDuringDrag',{});

        % ID to add to the next registrant
        NextID double = 1


        HoverID double = NaN
        CaptureID double = NaN
    end

    methods (Static)

        function hub = ensure(fig)
            hub = getappdata(fig,'FigureEventHub');
            if isempty(hub) || ~isvalid(hub)
                hub = guitools.control.FigureEventHub(fig);
                setappdata(fig,'FigureEventHub',hub);
            end
        end

    end

    methods (Access=private)

        function obj = FigureEventHub(fig)
            obj.Fig = fig;
            fig.WindowButtonDownFcn   = @(~,evt) obj.route('down',evt);
            fig.WindowButtonMotionFcn = @(~,~)   obj.route('move',[]);
            fig.WindowButtonUpFcn     = @(~,evt) obj.route('up',evt);
            fig.WindowScrollWheelFcn  = @(~,evt) obj.route('scroll',evt);
            fig.KeyPressFcn           = @(~,evt) obj.route('key',evt);
        end

    end

    methods

        function id = register(obj, h, varargin)
            % REGISTER(H, 'Priority',P, 'CaptureDuringDrag',TF)

            % parse inputs
            p = inputParser;
            p.addParameter('Priority', 0, @(x)isnumeric(x)&&isscalar(x));
            p.addParameter('CaptureDuringDrag', false, @(x)islogical(x)&&isscalar(x));
            p.parse(varargin{:});

            % make sure registrants implement required methods
            requiredMethods = obj.getRequiredMethods();

            for i = numel(requiredMethods)
                if ~ismethod(h,requiredMethods{i})
                    error('Registrant missing required method: %s',requiredMethods{i});
                end
            end

            % new entry with stable ID
            % obj.NextID = obj.NextID + 1;
            entry.id = obj.NextID;
            entry.obj = h;
            entry.Priority = p.Results.Priority;
            entry.CaptureDuringDrag = p.Results.CaptureDuringDrag;

            obj.NextID = obj.NextID + 1;

            % add entry to the registry
            obj.Registry(end+1) = entry;

            % sort by priority (desc)
            [~,ord] = sort([obj.Registry.Priority],'descend');
            obj.Registry = obj.Registry(ord);

            % return id
            id = entry.id;
        end

        function unregister(obj, id)

            if nargin<2 || isempty(id) || ~isfinite(id)
                return
            end

            % get idx from id
            idx = obj.indexOfID(id);

            % return if empty
            if isempty(idx)
                return
            end

            % if current hover/capture belonged to this id, release + send leave
            if ~isnan(obj.CaptureID) && obj.CaptureID==id
                obj.CaptureID = NaN;
            end

            if ~isnan(obj.HoverID) && obj.HoverID==id
                % fire leave before removing
                obj.safeCall(obj.Registry(idx).obj, 'onLeave', [], hittest(obj.Fig));
                obj.HoverID = NaN;
            end

            obj.Registry(idx) = [];

        end

    end

    methods (Access=private)

        %% event router

        function route(obj, kind, evt)
            % route events exclusively to captor (if one exists)
            % otherwise, route event to the highest priority matcher

            tgt = hittest(obj.Fig);

            % If captured, route only to captor until mouse up
            if ~isnan(obj.CaptureID)
                idx = obj.indexOfID(obj.CaptureID);
                e = obj.Registry(idx);

                % e = obj.Registry(obj.CaptureID);
                obj.call(e.obj, kind, evt, tgt);

                if strcmp(kind,'up')
                    % Release capture and immediately recompute hover (in case mouse up occured outside the captor)
                    obj.CaptureID = NaN;
                    obj.updateHover(tgt, kind, evt);
                end

                % exit
                return
            end

            % If not captured, recompute hover for all event kinds (find new hover claimant)
            obj.updateHover(tgt, kind, evt);

            % Dispatch this event to the current hover claimant (if any)

            % if there is a claimant
            if ~isnan(obj.HoverID)
                % grab it
                idx = obj.indexOfID(obj.HoverID);
                e = obj.Registry(idx);
                % then dispatch event to claimant's handler for this event kind
                obj.call(e.obj, kind, evt, tgt);
                % if event kind == 'down' and claimant's CaptureDuringDrag == true
                if strcmp(kind,'down') && e.CaptureDuringDrag
                    % then give claimant control of hover until mouse up
                    obj.CaptureID = e.id;
                end
            end

        end

        function updateHover(obj, tgt, kind, evt)
            % Find first registrant that matches current pointer/target

            claimantID = NaN;
            % iterate Registry in priority order
            for k = 1:numel(obj.Registry)
                e = obj.Registry(k);
                try
                    % if matches() returns true, this registrant becomes the claimant
                    if obj.matches(e.obj, tgt, kind, evt)
                        claimantID = e.id;
                        break
                    end
                catch
                    % keep hub resilient to tool errors
                end
            end

            % if the claimant changed
            if ~isequal(obj.HoverID, claimantID)

                % fire onLeave() of previous claimant
                if ~isnan(obj.HoverID)
                    previousIdx = obj.indexOfID(obj.HoverID);
                    if ~isempty(previousIdx)
                        obj.safeCall(obj.Registry(previousIdx).obj, 'onLeave', evt, tgt);
                    end
                end

                % fire onEnter() of new claimant
                if ~isnan(claimantID)
                    newIdx = obj.indexOfID(claimantID);
                    if ~isempty(newIdx)
                        obj.safeCall(obj.Registry(newIdx).obj, 'onEnter', evt, tgt);
                    end
                end

                % hover ownership shifted to new claimant
                obj.HoverID = claimantID;

            end

        end



        % Helper: map ID -> current index
        function idx = indexOfID(obj, id)
            ids = [obj.Registry.id];
            idx = find(ids==id, 1, 'first');
        end



        function safeCall(~, h, methodName, evt, tgt)
            % if isvalid(h) && ismethod(h, methodName)
            %     try
            %         h.(methodName)(evt, tgt)
            %     catch err
            %         %disp('Error using safeCall()')
            %         warning('Hub safeCall() error in %s: %s', methodName, err.message);
            %     end
            % end

            if isvalid(h)
                try
                    h.(methodName)(evt, tgt)
                catch err
                    %disp('Error using safeCall()')
                    warning('Hub safeCall() error in %s: %s', methodName, err.message);
                end
            end

        end

        function tf = matches(~, h, tgt, kind, evt)
            % Expect registrant to implement "matches(tgt,kind,evt)"
            % tf = false;
            % if isvalid(h) && ismethod(h,'matches')
            %     tf = h.matches(tgt, kind, evt);
            % end

            tf = false;
            if isvalid(h)
                tf = h.matches(tgt, kind, evt);
            end


        end

        function call(~, h, kind, evt, tgt)
            % Call method if present; ignore if missing
            if ~isvalid(h), return; end
            % switch kind
            %     case 'down',   if ismethod(h,'onDown'),     h.onDown(evt,tgt);     end
            %     case 'move',   if ismethod(h,'onMove'),     h.onMove(evt,tgt);     end
            %     case 'up',     if ismethod(h,'onUp'),       h.onUp(evt,tgt);       end
            %     case 'scroll', if ismethod(h,'onScroll'),   h.onScroll(evt,tgt);   end
            %     case 'key',    if ismethod(h,'onKeyPress'), h.onKeyPress(evt,tgt); end
            % end

            switch kind
                case 'down',   h.onDown(evt,tgt);
                case 'move',   h.onMove(evt,tgt);
                case 'up',     h.onUp(evt,tgt);
                case 'scroll', h.onScroll(evt,tgt);
                case 'key',    h.onKeyPress(evt,tgt);
            end

        end

    end


    methods (Static)

        function requiredMethods = getRequiredMethods()
            requiredMethods = {...
                'matches',...
                'onDown',...
                'onUp',...
                'onMove',...
                'onScroll'...
                };
        end




    end




end
