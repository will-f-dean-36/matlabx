classdef (ConstructOnLoad) ImageDataChangedEventData < event.EventData
    %IMAGEDATACHANGEDEVENTDATA Payload for ImageAxes ImageData changes.
    %
    %   The payload is deliberately compact for now. It gives listeners a
    %   cheap way to detect image-shape/component-count changes while still
    %   leaving room for richer metadata later.

    properties
        PreviousNumComponents double = []
        CurrentNumComponents double = []
        PreviousSize double = []
        CurrentSize double = []
        Origin string = "ImageAxes"
    end

    methods
        function data = ImageDataChangedEventData(opts)
            %IMAGEDATACHANGEDEVENTDATA Construct image-data event data.
            arguments
                opts.PreviousNumComponents double = []
                opts.CurrentNumComponents double = []
                opts.PreviousSize double = []
                opts.CurrentSize double = []
                opts.Origin string = "ImageAxes"
            end

            data.PreviousNumComponents = opts.PreviousNumComponents;
            data.CurrentNumComponents = opts.CurrentNumComponents;
            data.PreviousSize = opts.PreviousSize;
            data.CurrentSize = opts.CurrentSize;
            data.Origin = opts.Origin;
        end
    end
end
