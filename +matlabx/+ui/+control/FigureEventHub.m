% matlabx.ui.control.FigureEventHub - Per-figure event hub that routes window-level events
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
% kind: the event kind string the hub uses to sort events: 'Move'|'Down'|'Up'|'Scroll'
%   Corresponds to: WindowButtonMotionFcn | WindowButtonDownFcn | WindowButtonUpFcn | WindowScrollWheelFcn
%
% evt: the MATLAB event struct passed from the figure callback (e.g., WindowButtonDownFcn arg, etc.)


classdef FigureEventHub < handle
% matlabx.ui.control.FigureEventHub
% Per-figure event hub that routes figure/window-level events to registered
% handlers with priority and optional capture. Also supports chained
% figure-level listeners without requiring direct mutation of figure
% callback properties after hub installation.

    properties (Access=private)
        Fig matlab.ui.Figure

        % Registrants, sorted by Priority descending
        Registry = struct( ...
            'obj', {}, ...
            'id', {}, ...
            'Priority', {}, ...
            'CaptureDuringDrag', {});

        NextID double = 1           % ID to assign to the next registrant
        HoverID double = NaN        % ID of the current hover claimant
        CaptureID double = NaN      % ID of the registrant holding capture

        % Extra listeners keyed by event kind:
        % 'Down'|'Move'|'Up'|'Scroll'|'Key'
        ListenerRegistry struct = struct( ...
            'Down',   struct('id', {}, 'Fcn', {}, 'Priority', {}), ...
            'Move',   struct('id', {}, 'Fcn', {}, 'Priority', {}), ...
            'Up',     struct('id', {}, 'Fcn', {}, 'Priority', {}), ...
            'Scroll', struct('id', {}, 'Fcn', {}, 'Priority', {}), ...
            'Key',    struct('id', {}, 'Fcn', {}, 'Priority', {}))

        NextListenerID double = 1
    end

    methods (Static)

        function hub = ensure(fig)
            hub = getappdata(fig, 'FigureEventHub');
            if isempty(hub) || ~isvalid(hub)
                hub = matlabx.ui.control.FigureEventHub(fig);
                setappdata(fig, 'FigureEventHub', hub);
            end
        end

    end

    methods (Access=private)

        function obj = FigureEventHub(fig)
            obj.Fig = fig;

            % Preserve any existing callbacks as listeners before installing hub
            obj.captureExistingCallback('WindowButtonDownFcn',   'Down');
            obj.captureExistingCallback('WindowButtonMotionFcn', 'Move');
            obj.captureExistingCallback('WindowButtonUpFcn',     'Up');
            obj.captureExistingCallback('WindowScrollWheelFcn',  'Scroll');
            obj.captureExistingCallback('KeyPressFcn',           'Key');

            % Install hub dispatchers
            fig.WindowButtonDownFcn   = @(~,evt) obj.route('Down', evt);
            fig.WindowButtonMotionFcn = @(~,evt) obj.route('Move', evt);
            fig.WindowButtonUpFcn     = @(~,evt) obj.route('Up', evt);
            fig.WindowScrollWheelFcn  = @(~,evt) obj.route('Scroll', evt);
            fig.KeyPressFcn           = @(~,evt) obj.route('Key', evt);
        end

        function captureExistingCallback(obj, propName, kind)
            existing = obj.Fig.(propName);
            if ~isempty(existing)
                obj.addListener(kind, existing, 'Priority', -inf);
            end
        end

    end

    methods

        function id = register(obj, h, varargin)
            % REGISTER(H, 'Priority', P, 'CaptureDuringDrag', TF)

            p = inputParser;
            p.addParameter('Priority', 0, @(x) isnumeric(x) && isscalar(x));
            p.addParameter('CaptureDuringDrag', false, @(x) islogical(x) && isscalar(x));
            p.parse(varargin{:});

            % ensure registrants implement required methods
            requiredMethods = obj.getRequiredMethods();
            for i = 1:numel(requiredMethods)
                if ~ismethod(h, requiredMethods{i})
                    error('FigureEventHub:MatchError', ...
                        'Registrant missing required method: %s', requiredMethods{i});
                end
            end

            % new entry struct
            entry.id = obj.NextID;
            entry.obj = h;
            entry.Priority = p.Results.Priority;
            entry.CaptureDuringDrag = p.Results.CaptureDuringDrag;

            % add to registry, sort by Priority descending
            obj.Registry(end+1) = entry;
            obj.sortRegistry();

            % ID to return to this registrant
            id = entry.id;

            % set ID for the next entry
            obj.NextID = obj.NextID + 1;
        end

        function unregister(obj, id)
            if nargin < 2 || isempty(id) || ~isfinite(id)
                return
            end

            idx = obj.indexOfID(id);
            if isempty(idx)
                return
            end

            % release capture if necessary
            if ~isnan(obj.CaptureID) && obj.CaptureID == id
                obj.CaptureID = NaN;
            end

            % release hover if necessary, then fire onLeave()
            if ~isnan(obj.HoverID) && obj.HoverID == id
                obj.safeCall(obj.Registry(idx).obj, 'onLeave', [], hittest(obj.Fig));
                obj.HoverID = NaN;
            end

            % remove from registry
            obj.Registry(idx) = [];
        end

        function id = addListener(obj, kind, fcn, varargin)
            % ADDLISTENER(KIND, FCN, 'Priority', P)

            kind = validatestring(kind, obj.supportedKinds());

            p = inputParser;
            p.addParameter('Priority', 0, @(x) isnumeric(x) && isscalar(x));
            p.parse(varargin{:});

            if ~isa(fcn, 'function_handle')
                error('Listener must be a function handle.');
            end

            % new listener entry struct
            entry.id = obj.NextListenerID;
            entry.Fcn = fcn;
            entry.Priority = p.Results.Priority;

            % add to registry for this event kind, sort by Priority descending
            obj.ListenerRegistry.(kind)(end+1) = entry;
            obj.sortListeners(kind);

            % ID to return
            id = entry.id;

            % set ID for the next listener
            obj.NextListenerID = obj.NextListenerID + 1;
        end

        function removeListener(obj, kind, id)
            kind = validatestring(kind, obj.supportedKinds());

            % get listener registry for this event kind
            L = obj.ListenerRegistry.(kind);
            if isempty(L)
                return
            end

            % find matching listener entry by ID
            idx = find([L.id] == id, 1, 'first');
            if isempty(idx)
                return
            end

            % remove entry, update registry
            L(idx) = [];
            obj.ListenerRegistry.(kind) = L;
        end

        function clearListeners(obj, kind)
            % reset listener registry for this event kind
            kind = validatestring(kind, obj.supportedKinds());
            obj.ListenerRegistry.(kind) = struct('id', {}, 'Fcn', {}, 'Priority', {});
        end

        function listRegistrants(obj)
            for i = 1:numel(obj.Registry)
                entry = obj.Registry(i);
                fprintf('Entry %d: %s (Priority=%g, ID=%d)\n', ...
                    i, class(entry.obj), entry.Priority, entry.id);
            end
            fprintf('\n');
        end

        function listListeners(obj, kind)
            kind = validatestring(kind, obj.supportedKinds());
            L = obj.ListenerRegistry.(kind);

            for i = 1:numel(L)
                fprintf('%s listener %d: Priority=%g, ID=%d\n', ...
                    kind, i, L(i).Priority, L(i).id);
            end
            fprintf('\n');
        end

    end

    methods (Access=private)

        function route(obj, kind, evt)
            % ensure valid registrants and listener entries
            obj.pruneInvalidRegistrants();
            obj.pruneInvalidListeners(kind);

            tgt = hittest(obj.Fig);
            E = matlabx.ui.control.HubEvent(obj.Fig, tgt, kind, evt);

            % If captured, route only to current captor until mouse up
            if ~isnan(obj.CaptureID)
                idx = obj.indexOfID(obj.CaptureID);

                if isempty(idx) 
                    obj.CaptureID = NaN;
                else % route to captor
                    e = obj.Registry(idx);
                    obj.call(e.obj, E);

                    if strcmp(kind, 'Up')
                        obj.CaptureID = NaN;   % release capture
                        obj.updateHover(E);    % recompute hover
                    end

                    obj.notifyListeners(E);
                    return
                end
            end

            obj.updateHover(E);

            % Dispatch to hover claimant
            if ~isnan(obj.HoverID)
                idx = obj.indexOfID(obj.HoverID);

                if ~isempty(idx)
                    % route to hover claimant
                    e = obj.Registry(idx);
                    obj.call(e.obj, E);
                    % hover claimaint claims capture on mouse down
                    if strcmp(kind, 'Down') && e.CaptureDuringDrag
                        obj.CaptureID = e.id;
                    end
                else
                    obj.HoverID = NaN;  % release hover
                end
            end
            % Notify chained listeners for this event kind
            obj.notifyListeners(E);
        end

        function updateHover(obj, E)
            claimantID = NaN;
            % iterate Registry in priority order
            for k = 1:numel(obj.Registry)
                e = obj.Registry(k);
                try
                    if obj.matches(e.obj, E)
                        claimantID = e.id;
                        break
                    end
                catch err
                    warning('FigureEventHub:MatchError', ...
                        'Error in matches() for %s: %s', class(e.obj), err.message);
                end
            end

            % if the claimant changed
            if ~isequaln(obj.HoverID, claimantID)

                % leave previous claimant
                if ~isnan(obj.HoverID)
                    previousIdx = obj.indexOfID(obj.HoverID);
                    if ~isempty(previousIdx)
                        obj.safeCall(obj.Registry(previousIdx).obj, 'onLeave', E);
                    end
                end

                % enter new claimant
                if ~isnan(claimantID)
                    newIdx = obj.indexOfID(claimantID);
                    if ~isempty(newIdx)
                        obj.safeCall(obj.Registry(newIdx).obj, 'onEnter', E);
                    end
                end

                % transfer hover to new claimant
                obj.HoverID = claimantID;
            end
        end

        function tf = matches(~, h, E)
            tf = false;
            if isvalid(h)
                tf = h.matches(E);
            end
        end

        function call(~, h, E)
            if ~isvalid(h), return; end

            switch E.Kind
                case 'Down',   h.onDown(E);
                case 'Move',   h.onMove(E);
                case 'Up',     h.onUp(E);
                case 'Scroll', h.onScroll(E);
                case 'Key',    h.onKey(E);
            end
        end

        function safeCall(~, h, methodName, E)
            if isvalid(h)
                try
                    h.(methodName)(E);
                catch err
                    warning('FigureEventHub:SafeCallError', ...
                        'Error in %s.%s: %s', class(h), methodName, err.message);
                end
            end
        end

        function notifyListeners(obj, E)
            L = obj.ListenerRegistry.(E.Kind);
            for i = 1:numel(L)
                try
                    L(i).Fcn(E);
                catch err
                    warning('FigureEventHub:ListenerError', ...
                        'Error in %s listener ID %d: %s', E.Kind, L(i).id, err.message);
                end
            end
        end

        function idx = indexOfID(obj, id)
            ids = [obj.Registry.id];
            idx = find(ids == id, 1, 'first');
        end

        function pruneInvalidRegistrants(obj)
            keep = false(1, numel(obj.Registry));
            for i = 1:numel(obj.Registry)
                keep(i) = isvalid(obj.Registry(i).obj);
            end

            removedIDs = [obj.Registry(~keep).id];
            obj.Registry = obj.Registry(keep);

            if ~isempty(removedIDs)
                if any(removedIDs == obj.HoverID)
                    obj.HoverID = NaN;
                end
                if any(removedIDs == obj.CaptureID)
                    obj.CaptureID = NaN;
                end
            end
        end

        function pruneInvalidListeners(obj, kind)
            L = obj.ListenerRegistry.(kind);
            keep = true(1, numel(L));

            for i = 1:numel(L)
                % function handles generally remain valid unless the target scope is gone;
                % we just leave them and let notifyListeners catch errors.
                keep(i) = true;
            end

            obj.ListenerRegistry.(kind) = L(keep);
        end

        function sortRegistry(obj)
            if isempty(obj.Registry)
                return
            end
            [~, ord] = sort([obj.Registry.Priority], 'descend');
            obj.Registry = obj.Registry(ord);
        end

        function sortListeners(obj, kind)
            L = obj.ListenerRegistry.(kind);
            if isempty(L)
                return
            end
            [~, ord] = sort([L.Priority], 'descend');
            obj.ListenerRegistry.(kind) = L(ord);
        end

    end

    methods (Static)

        function requiredMethods = getRequiredMethods()
            requiredMethods = { ...
                'matches', ...
                'onDown', ...
                'onUp', ...
                'onMove', ...
                'onScroll', ...
                'onKey', ...
                'onEnter', ...
                'onLeave'};
        end

        function kinds = supportedKinds()
            kinds = {'Down', 'Move', 'Up', 'Scroll', 'Key'};
        end

    end

end