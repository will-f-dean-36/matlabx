classdef ChooseColormap < guitools.widgets.ImageAxesTool
% widgets.tools.ChooseColormap
% when button pushed: 
%   Open colormap selector and set colormap for current channel

    methods

        function obj = ChooseColormap(host)
            obj@guitools.widgets.ImageAxesTool(host, "ChooseColormap", ...
                'Tooltip','Choose colormap', ...
                'Icon',guitools.Paths.icons('ChooseColormapIcon.png'), ...
                'Style','push', ...
                'Priority',1);
        end

        % Called when button is pushed
        function onPush(obj)
            % open colormap selector
            cmap = guitools.ColormapSelector;
            % Set the colormap for the current channel
            obj.Host.Colormap = cmap;
        end

        % Called AFTER installed from Host, use for any extra required startup actions
        function onInstall(~), end

        % Called AFTER uninstalled from Host, use for any extra required cleanup actions
        function onUninstall(~), end

    end

    %% Teardown
    methods (Access = protected)

        % % called at the beginning of superclass delete()
        % function teardown(obj)
        %     % here is where you can perform any cleanup before object deletion
        % end

    end

end