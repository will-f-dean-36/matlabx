classdef (ConstructOnLoad) DisplayStateChangedEventData < event.EventData
    %DISPLAYSTATECHANGEDEVENTDATA Payload for ImageAxes display-state changes.
    %
    %   This event data is intentionally small. It identifies which
    %   display-facing property changed and, when known, which component
    %   indices were affected. Listeners that need complete current state
    %   should query the ImageAxes object when they receive the event.

    properties
        Property string = ""
        ComponentIdx double = []
        PreviousValue = []
        CurrentValue = []
        Origin string = "ImageAxes"
    end

    methods
        function data = DisplayStateChangedEventData(opts)
            %DISPLAYSTATECHANGEDEVENTDATA Construct display-state event data.
            arguments
                opts.Property string = ""
                opts.ComponentIdx double = []
                opts.PreviousValue = []
                opts.CurrentValue = []
                opts.Origin string = "ImageAxes"
            end

            data.Property = opts.Property;
            data.ComponentIdx = opts.ComponentIdx;
            data.PreviousValue = opts.PreviousValue;
            data.CurrentValue = opts.CurrentValue;
            data.Origin = opts.Origin;
        end
    end
end
