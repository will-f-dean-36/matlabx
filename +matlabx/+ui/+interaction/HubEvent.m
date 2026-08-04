classdef HubEvent < event.EventData

    properties (SetAccess=private)
        Kind (1,1) string
        Figure matlab.ui.Figure
        Target
        RawEvent

        Timestamp (1,1) datetime

        SelectionType string = string.empty(1,0)

        Key string = string.empty(1,0)
        Character string = string.empty(1,0)
        Modifier string = string.empty(1,0)
        Hotkey string = string.empty(1,0)

        ModifierState string = string.empty(1,0)
        LastKey (1,1) string = ""
        LastHotkey (1,1) string = ""
        LastKeyTimestamp datetime = NaT

        VerticalScrollCount double = NaN

        CurrentPointFigure double = [NaN NaN]

        CurrentAxes
        CurrentObject
    end

    properties
        Handled (1,1) logical = false
        StopPropagation (1,1) logical = false
    end

    properties (Dependent)
        MouseAction string
        MouseChord string
    end

    methods
        function obj = HubEvent(fig, tgt, kind, rawEvt, opts)
            arguments
                fig matlab.ui.Figure
                tgt
                kind
                rawEvt
                opts.ModifierState string = string.empty(1,0)
                opts.LastKey (1,1) string = ""
                opts.LastHotkey (1,1) string = ""
                opts.LastKeyTimestamp datetime = NaT
            end

            obj.Figure = fig;
            obj.Target = tgt;
            obj.Kind = string(kind);
            obj.RawEvent = rawEvt;
            obj.Timestamp = datetime("now");
            obj.ModifierState = matlabx.ui.interaction.HubEvent.canonicalModifiers_(opts.ModifierState);
            obj.LastKey = opts.LastKey;
            obj.LastHotkey = opts.LastHotkey;
            obj.LastKeyTimestamp = opts.LastKeyTimestamp;

            % handles to current axes and object at time of event
            obj.CurrentAxes = fig.CurrentAxes;
            obj.CurrentObject = fig.CurrentObject;

            % Mouse selection type
            try
                obj.SelectionType = string(fig.SelectionType);
            catch ME
                warning('HubEvent:ConstructError', 'Error constructing event payload: %s', ME.message);
            end

            % Figure current point
            try
                cp = fig.CurrentPoint;
                if isnumeric(cp) && numel(cp) >= 2
                    obj.CurrentPointFigure = cp(1,1:2);
                end
            catch ME
                warning('HubEvent:ConstructError', 'Error constructing event payload: %s', ME.message);
            end

            % Key event fields
            if isa(rawEvt, 'matlab.ui.eventdata.KeyData')
                try
                    obj.Key = lower(string(rawEvt.Key));
                    obj.Character = string(rawEvt.Character);
                    obj.Modifier = matlabx.ui.interaction.HubEvent.canonicalModifiers_(rawEvt.Modifier);
                    obj.Hotkey = matlabx.keyboard.normalize(obj.Key,obj.Character,obj.Modifier);
                catch ME
                    warning('HubEvent:ConstructError', 'Error constructing event payload: %s', ME.message);
                end
            end

            % Scroll event field
            if isa(rawEvt, 'matlab.ui.eventdata.ScrollWheelData')
                try
                    obj.VerticalScrollCount = rawEvt.VerticalScrollCount;
                catch ME
                    warning('HubEvent:ConstructError', 'Error constructing event payload: %s', ME.message);
                end
            end
        end

        function markHandled(obj)
            obj.Handled = true;
        end

        function stop(obj)
            obj.StopPropagation = true;
        end

        function tf = isMouseEvent(obj)
            tf = any(obj.Kind == ["Down","Move","Up","Scroll"]);
        end

        function tf = isKeyEvent(obj)
            tf = any(obj.Kind == ["KeyPress", "KeyRelease"]);
        end

        function tf = isKeyPressEvent(obj)
            tf = obj.Kind == "KeyPress";
        end

        function tf = isKeyReleaseEvent(obj)
            tf = obj.Kind == "KeyRelease";
        end

        function tf = hasModifier(obj, modifierName)
        %HASMODIFIER True if the modifier snapshot contains modifierName.
            modifierName = matlabx.ui.interaction.HubEvent.canonicalModifiers_(modifierName);
            tf = ~isempty(modifierName) && any(obj.ModifierState == modifierName(1));
        end

        function value = get.MouseAction(obj)
            switch obj.Kind
                case "Down"
                    value = matlabx.ui.interaction.HubEvent.selectionTypeToMouseAction_(obj.SelectionType);
                case "Move"
                    value = "move";
                case "Up"
                    value = "up";
                case "Scroll"
                    value = "scroll";
                otherwise
                    value = "";
            end
        end

        function value = get.MouseChord(obj)
            % MouseChord is the normalized, user-facing mouse gesture name.
            % It combines the current modifier snapshot with MouseAction, so
            % MATLAB-specific SelectionType values stay centralized here.
            parts = [obj.ModifierState, obj.MouseAction];
            parts(parts == "") = [];

            if isempty(parts)
                value = "";
            else
                value = strjoin(parts, "+");
            end
        end

        function S = toStruct(obj)
        %TOSTRUCT Return a readable struct summary of the event.
            S = struct( ...
                'Kind', obj.Kind, ...
                'Timestamp', obj.Timestamp, ...
                'SelectionType', obj.SelectionType, ...
                'Key', obj.Key, ...
                'Character', obj.Character, ...
                'Modifier', obj.Modifier, ...
                'ModifierState', obj.ModifierState, ...
                'Hotkey', obj.Hotkey, ...
                'LastKey', obj.LastKey, ...
                'LastHotkey', obj.LastHotkey, ...
                'LastKeyTimestamp', obj.LastKeyTimestamp, ...
                'MouseAction', obj.MouseAction, ...
                'MouseChord', obj.MouseChord, ...
                'VerticalScrollCount', obj.VerticalScrollCount, ...
                'CurrentPointFigure', obj.CurrentPointFigure, ...
                'Handled', obj.Handled, ...
                'StopPropagation', obj.StopPropagation, ...
                'Figure', matlabx.ui.interaction.HubEvent.summarizeObjectLine_(obj.Figure), ...
                'Target', matlabx.ui.interaction.HubEvent.summarizeObjectLine_(obj.Target), ...
                'CurrentAxes', matlabx.ui.interaction.HubEvent.summarizeObjectLine_(obj.CurrentAxes), ...
                'CurrentObject', matlabx.ui.interaction.HubEvent.summarizeObjectLine_(obj.CurrentObject), ...
                'RawEventClass', string(class(obj.RawEvent)));
        end

        function txt = print(obj)
        %PRINT Print a readable event summary for debugging.
        %
        %   E.print() prints the current HubEvent state.
        %   txt = E.print() returns the formatted text instead.

            S = obj.toStruct();

            if nargout == 0
                matlabx.struct.prettyPrint(S);
            else
                txt = matlabx.struct.prettyPrint(S);
            end
        end
    end

    methods (Static, Access=private)
        function S = summarizeObject_(h)
        %SUMMARIZEOBJECT_ Convert graphics/UI handles to a compact struct.
            S = struct( ...
                'Class', string(class(h)), ...
                'Valid', false, ...
                'Tag', "", ...
                'Type', "", ...
                'Text', "", ...
                'Name', "");

            if isempty(h)
                S.Class = "";
                return
            end

            try
                if isa(h, 'handle')
                    S.Valid = isvalid(h);
                else
                    S.Valid = true;
                end
            catch
                S.Valid = false;
            end

            if ~S.Valid
                return
            end

            S.Tag = matlabx.ui.interaction.HubEvent.getPropertyString_(h, "Tag");
            S.Type = matlabx.ui.interaction.HubEvent.getPropertyString_(h, "Type");
            S.Text = matlabx.ui.interaction.HubEvent.getPropertyString_(h, "Text");
            S.Name = matlabx.ui.interaction.HubEvent.getPropertyString_(h, "Name");
        end

        function line = summarizeObjectLine_(h)
        %SUMMARIZEOBJECTLINE_ Format a graphics/UI handle on one line.
            S = matlabx.ui.interaction.HubEvent.summarizeObject_(h);

            if strlength(S.Class) == 0
                line = "";
                return
            end

            if ~S.Valid
                line = "invalid (" + S.Class + ")";
                return
            end

            type = matlabx.ui.interaction.HubEvent.nonEmptyOr_(S.Type, "no Type");
            name = matlabx.ui.interaction.HubEvent.nonEmptyOr_(S.Name, "no Name");
            tag = matlabx.ui.interaction.HubEvent.nonEmptyOr_(S.Tag, "no Tag");

            parts = [type + " (" + S.Class + ")", name, tag];
            line = strjoin(parts, " | ");
        end

        function value = nonEmptyOr_(value, fallback)
        %NONEMPTYOR_ Return fallback when value is empty text.
            value = string(value);
            if ~isscalar(value) || strlength(value) == 0
                value = string(fallback);
            end
        end

        function value = getPropertyString_(h, propName)
        %GETPROPERTYSTRING_ Safely read a property as a string scalar.
            value = "";

            try
                if isprop(h, propName)
                    raw = h.(propName);
                    if ischar(raw) || (isstring(raw) && isscalar(raw)) || ...
                            (isnumeric(raw) && isscalar(raw)) || ...
                            (islogical(raw) && isscalar(raw))
                        value = string(raw);
                    end
                end
            catch
                value = "";
            end
        end

        function modifiers = canonicalModifiers_(modifiers)
            modifiers = lower(string(modifiers));
            modifiers(modifiers == "") = [];
            modifiers(modifiers == "command") = "meta";
            modifiers(modifiers == "option") = "alt";
            modifiers(modifiers == "ctrl") = "control";

            order = ["shift", "control", "alt", "meta"];
            modifiers = intersect(order, unique(modifiers, "stable"), "stable");
        end

        function action = selectionTypeToMouseAction_(selectionType)
        %SELECTIONTYPETOMOUSEACTION_ Normalize MATLAB SelectionType strings.
        %
        % MATLAB reports some modified clicks as distinct SelectionType
        % values. HubEvent preserves that by mapping them into mouse actions
        % and then prepending the tracked modifier state in MouseChord.
        %
        % Common Down-event mappings:
        %   SelectionType      MouseAction       Typical MouseChord
        %   "normal"           "click"           "click"
        %   "alt"              "contextclick"    "contextclick"
        %   "extend"           "extendclick"     "shift+extendclick"
        %   "open"             "doubleclick"     "doubleclick"
        %
        % Platform notes:
        %   - On macOS, control-click is usually reported by MATLAB as
        %     SelectionType="alt", so MouseChord becomes
        %     "control+contextclick".
        %   - Option-click is normalized as "alt+click".
        %   - Command is normalized as "meta" for cross-platform naming.
            selectionType = lower(string(selectionType));

            switch selectionType
                case "normal"
                    action = "click";
                case "alt"
                    action = "contextclick";
                case "extend"
                    action = "extendclick";
                case "open"
                    action = "doubleclick";
                otherwise
                    action = "";
            end
        end
    end

end
