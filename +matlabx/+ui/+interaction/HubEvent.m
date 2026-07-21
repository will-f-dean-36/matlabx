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

        VerticalScrollCount double = NaN

        CurrentPointFigure double = [NaN NaN]

        CurrentAxes
        CurrentObject
    end

    properties
        Handled (1,1) logical = false
        StopPropagation (1,1) logical = false
    end

    methods
        function obj = HubEvent(fig, tgt, kind, rawEvt)
            obj.Figure = fig;
            obj.Target = tgt;
            obj.Kind = string(kind);
            obj.RawEvent = rawEvt;
            obj.Timestamp = datetime("now");

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
                    obj.Modifier = string(rawEvt.Modifier);
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
            tf = obj.Kind == "Key";
        end
    end

end