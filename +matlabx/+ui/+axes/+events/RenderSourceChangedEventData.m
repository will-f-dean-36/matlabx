classdef (ConstructOnLoad) RenderSourceChangedEventData < event.EventData
    %RENDERSOURCECHANGEDEVENTDATA Payload for ImageAxes RenderSource changes.

    properties
        OldRenderSource
        NewRenderSource
    end

    methods
        function data = RenderSourceChangedEventData(oldRenderSource,newRenderSource)
            data.OldRenderSource = oldRenderSource;
            data.NewRenderSource = newRenderSource;
        end
    end

end
