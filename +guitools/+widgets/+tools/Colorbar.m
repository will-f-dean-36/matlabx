classdef Colorbar < guitools.widgets.ImageAxesTool
% widgets.tools.Colorbar
% when Enabled: 
%   Colorbar is Visible

    methods

        function obj = Colorbar(host)
            obj@guitools.widgets.ImageAxesTool(host, "Colorbar", ...
                'Tooltip','Show/Hide Colorbar', ...
                'Icon',guitools.Paths.icons('ColorbarIcon.png'), ...
                'Priority',1);
        end

        % Toggled Enabled=true via toolbar button
        function onEnabled(obj)
            obj.Host.ColorbarVisible = 'on';
        end

        % Toggled Enabled=false via toolbar button
        function onDisabled(obj)
            if isvalid(obj.Host)
                obj.Host.ColorbarVisible = 'off';
            end
        end

        % Called AFTER installed from Host, use for any extra required startup actions
        function onInstall(obj)
            obj.Host.ToolbarButtons.Colorbar.Value = obj.Host.ColorbarVisible;
            obj.Enabled = obj.Host.ColorbarVisible;
        end

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