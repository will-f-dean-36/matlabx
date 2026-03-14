classdef CommandRouter < matlab.ui.componentcontainer.ComponentContainer
%COMMANDROUTER  Non-UI FigureEventHub registrant for hotkeys/commands.

    properties
        Enabled (1,1) logical = true
        HotkeyFcnDict dictionary = dictionary(string.empty(1,0), function_handle.empty(1,0))
    end

    properties (Access=private)
        Hub matlabx.ui.control.FigureEventHub
        RouterId double = NaN
    end

    methods (Access=protected)

        function setup(obj)
            % Hide -> this component will run in the background
            obj.Visible = 'off';

            % Get ancestor figure
            fig = ancestor(obj, 'Figure');

            % Register with FigureEventHub
            obj.Hub = matlabx.ui.control.FigureEventHub.ensure(fig);
            obj.RouterId = obj.Hub.register(obj, ...
                'Priority', 100, ...
                'CaptureDuringDrag', false);
        end

        function update(~)
        end

    end

    methods

        function delete(obj)
            if ~isnan(obj.RouterId) && ~isempty(obj.Hub) && isvalid(obj.Hub)
                obj.Hub.unregister(obj.RouterId);
            end
        end

        % FigureEventHub hook: decide if we claim this event
        function tf = matches(obj, ~, ~, evt)
            tf = obj.Enabled && ...
                 isa(evt, 'matlab.ui.eventdata.KeyData') && ...
                 isKey(obj.HotkeyFcnDict, lower(string(evt.Key)));
        end

        % FigureEventHub hook: handle claimed event
        function onKeyPress(obj, evt, ~)
            key = lower(string(evt.Key));

            if isKey(obj.HotkeyFcnDict, key)
                func = obj.HotkeyFcnDict(key);
                func(obj, key);
            end
        end

        % No-ops so FigureEventHub doesn't error
        function onDown(~, ~, ~), end
        function onUp(~, ~, ~), end
        function onMove(~, ~, ~), end
        function onScroll(~, ~, ~), end
        function onEnter(~, ~, ~), end
        function onLeave(~, ~, ~), end

    end

    methods

        function addHotkey(obj, key, fun)
            key = lower(string(key));

            if ~(isscalar(key) && strlength(key) > 0)
                error('Hotkey must be a nonempty string scalar.');
            end

            if ~(isa(fun, 'function_handle') && isscalar(fun))
                error('Hotkey callback must be a scalar function handle.');
            end

            obj.HotkeyFcnDict(key) = fun;
        end

        function removeHotkey(obj, key)
            key = lower(string(key));

            if ~(isscalar(key) && strlength(key) > 0)
                error('Hotkey must be a nonempty string scalar.');
            end

            if isKey(obj.HotkeyFcnDict, key)
                remove(obj.HotkeyFcnDict, key);
            end
        end

    end

end