classdef (ConstructOnLoad) CDataChangedEventData < event.EventData
    % event.EventData subclass used by guitools.widgets.ImageAxes to 
    % deliver CDataChanged event payload to guitools.widgets.tools objects

    properties
        oldCData
        newCData
    end

    methods
        function data = CDataChangedEventData(oldCData,newCData)
            data.oldCData = oldCData;
            data.newCData = newCData;
        end
    end

end