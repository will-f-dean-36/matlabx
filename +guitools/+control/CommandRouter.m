classdef CommandRouter < matlab.ui.componentcontainer.ComponentContainer
%CommandRouter  Non-UI FigureEventHub registrant for hotkeys/commands.

    properties
        Enabled (1,1) logical = true
        HotkeyFcnDict = dictionary(string.empty(1,0),@(x) x) % hotkey -> ID
    end

    %% Hub registration
    properties (Access=private)
        Hub guitools.control.FigureEventHub
        RouterId double = NaN
    end

    methods (Access=protected)

        function setup(obj)
            % hide -> this component will run in the background
            obj.Visible = 'off';
            % get ancestor figure
            fig = ancestor(obj,'Figure');
            % register with FigureEventHub
            obj.Hub = guitools.control.FigureEventHub.ensure(fig);
            obj.RouterId = obj.Hub.register(obj,'Priority',100,'CaptureDuringDrag',false);
        end

        function update(~), end

    end

    methods

        % FigureEventHub hook: decide if we claim this event
        function tf = matches(obj, ~, ~, evt)
            tf = obj.Enabled && isa(evt,'matlab.ui.eventdata.KeyData') && isKey(obj.HotkeyFcnDict,evt.Key);
        end

        % FigureEventHub hook: handle claimed event
        function onKeyPress(obj, evt, ~)
            key = evt.Key;
            if isKey(obj.HotkeyFcnDict, key)
                func = obj.HotkeyFcnDict(key);
                func(obj,key);
            end
        end

        % --- no-ops so FigureEventHub doesn't error ---
        function onDown(~,~,~), end
        function onUp(~,~,~), end
        function onMove(~,~,~), end
        function onScroll(~,~,~), end
        function onEnter(~,~,~), end
        function onLeave(~,~,~), end

    end

    % Hotkey management
    methods

        function addHotkey(obj,key,fun)
            % validate key and value
            if isa(key,"string") && isa(fun,"function_handle")
                % if valid, add to registry
                obj.HotkeyFcnDict(key) = fun;
            end
        end

        function removeHotKey(obj,key)
            % remove key if it exists
            if isKey(obj.HotkeyFcnDict, key)
                remove(obj.HotkeyFcnDict, key);
            end
        end

    end

end