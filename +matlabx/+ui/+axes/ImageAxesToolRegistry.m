classdef ImageAxesToolRegistry
%IMAGEAXESTOOLREGISTRY Tool loading, installation, toolbar, and routing helpers.
%
%   ImageAxes keeps the public API for now: loadTool(), installTool(),
%   ToolBox, ToolBelt, enableTool(), and similar methods all delegate here.
%   This collaborator owns the mechanics of managing tool lifecycle and lookup.
%
%   Terminology:
%       Loaded tool
%           A tool object exists in memory and can be installed later. Loaded tools
%           live in host.ToolList but do not necessarily have toolbar buttons.
%       Installed tool
%           A loaded tool is active in the host's tool registry, has a toolbar
%           button if appropriate, can contribute hotkeys, and can receive routed
%           events. Installed tools live in host.ToolRegistry and host.Tools.
%       ToolBox
%           Public list of loaded tool names.
%       ToolBelt
%           Public list of installed tool names.
%
%   This class is intentionally mechanical. It preserves current ImageAxes API
%   behavior while moving the bookkeeping and toolbar wiring out of the host.

    methods (Static)
        function initialize(host)
            % Use containers.Map to preserve existing lookup behavior by tool name.
            host.ToolList = containers.Map('KeyType', 'char', 'ValueType', 'any');
            host.ToolRegistry = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        function register(host, tool)
        %REGISTER Add an installed tool to host state.
        %
        %   AxesTool.install() calls host.registerTool(), which delegates here.
            if ~isvalid(tool)
                warning('Failed to register tool. Invalid handle.')
                return
            end

            % Installation creates the user-facing affordances and registries:
            % toolbar button, Tools struct entry, installed-tool map, and hotkeys.
            matlabx.ui.axes.ImageAxesToolRegistry.addToolbarButton(host, tool);
            host.Tools.(tool.Name) = tool;
            host.ToolRegistry(char(tool.Name)) = tool;
            host.registerToolHotkeys(tool);
        end

        function unregister(host, tool)
        %UNREGISTER Remove an installed tool while keeping the loaded object.
            if ~host.ToolRegistry.isKey(char(tool.Name))
                warning('Failed to unregister tool. "%s" tool is not currently registered.', tool.Name)
                return
            end

            % Remove contributed host state in the reverse order of registration.
            host.HotkeyRegistry.removeOwner(tool);
            matlabx.ui.axes.ImageAxesToolRegistry.removeToolbarButton(host, tool);
            host.Tools = rmfield(host.Tools, tool.Name);
            host.ToolRegistry.remove(char(tool.Name));
        end

        function loadAll(host)
            % Load every concrete tool class in matlabx.ui.axes.tools.
            toolNames = host.getToolNames();
            matlabx.ui.axes.ImageAxesToolRegistry.loadMany(host, toolNames);
        end

        function unloadAll(host)
            % Copy names before unloading because unload mutates ToolList.
            if isempty(host.ToolList)
                return
            end

            toolNames = host.ToolList.keys;
            matlabx.ui.axes.ImageAxesToolRegistry.unloadMany(host, toolNames);
        end

        function loadMany(host, toolNames)
            % Bulk wrapper used by ToolBox setup and constructor initialization.
            if isempty(toolNames)
                return
            end

            for i = 1:numel(toolNames)
                matlabx.ui.axes.ImageAxesToolRegistry.load(host, toolNames{i});
            end
        end

        function unloadMany(host, toolNames)
            % Bulk wrapper used by ToolBox teardown and ImageAxes deletion.
            if isempty(toolNames)
                return
            end

            for i = 1:numel(toolNames)
                matlabx.ui.axes.ImageAxesToolRegistry.unload(host, toolNames{i});
            end
        end

        function load(host, name)
        %LOAD Construct a tool object and store it in ToolList.
            if host.ToolList.isKey(char(name))
                warning('Failed to load tool. "%s" tool already loaded.', name)
                return
            end

            % Tool classes are addressed by short name inside matlabx.ui.axes.tools.
            host.ToolList(char(name)) = matlabx.ui.axes.tools.(char(name))(host);
        end

        function unload(host, name)
        %UNLOAD Delete a loaded tool, uninstalling it first if needed.
            if ~host.ToolList.isKey(char(name))
                warning('Failed to unload tool. "%s" tool is not loaded.', name)
                return
            end

            tool = matlabx.ui.axes.ImageAxesToolRegistry.getLoaded(host, name);
            % Installed tools must release toolbar buttons, hotkeys, and registry
            % state before their object is deleted.
            if tool.Installed
                matlabx.ui.axes.ImageAxesToolRegistry.uninstall(host, tool.Name);
            end

            delete(tool)
            host.ToolList.remove(char(name));
        end

        function installMany(host, toolNames)
            % Bulk wrapper used by ToolBelt setup.
            if isempty(toolNames)
                return
            end

            for i = 1:numel(toolNames)
                matlabx.ui.axes.ImageAxesToolRegistry.install(host, toolNames{i});
            end
        end

        function install(host, name)
        %INSTALL Make a loaded tool active in the host.
            tool = matlabx.ui.axes.ImageAxesToolRegistry.getLoaded(host, name);

            if isempty(tool)
                warning('Failed to install tool. "%s" tool is not loaded.', name)
                return
            end

            if host.ToolRegistry.isKey(char(tool.Name))
                warning('Failed to install tool. "%s" tool is already installed.', name)
                return
            end

            % ImageAxes should only install tools that declare support for image axes.
            if ~ismember(tool.AxesType, ["image", "both"])
                warning('Failed to install tool. "%s" tool is for "%s" axes, not image axes.', ...
                    char(name), char(tool.AxesType))
                return
            end

            % AxesTool.install() calls back into register(), preserving the existing
            % tool-owned lifecycle hooks.
            tool.install();
        end

        function uninstall(host, name)
        %UNINSTALL Remove a tool from the active host registry.
            tool = matlabx.ui.axes.ImageAxesToolRegistry.getLoaded(host, name);

            if isempty(tool)
                warning('Failed to uninstall tool. "%s" tool is not loaded.', name)
                return
            end

            if ~host.ToolRegistry.isKey(char(tool.Name))
                warning('Failed to uninstall tool. "%s" tool is already uninstalled.', name)
                return
            end

            % AxesTool.uninstall() calls back into unregister(), preserving tool hooks.
            tool.uninstall();
        end

        function enable(host, name)
            % State tools own their Enabled flag and lifecycle hooks.
            tool = matlabx.ui.axes.ImageAxesToolRegistry.getInstalled(host, name);
            if isempty(tool)
                return
            end

            tool.enable();
        end

        function disable(host, name)
            % Disable is safe to call for missing/uninstalled tools.
            tool = matlabx.ui.axes.ImageAxesToolRegistry.getInstalled(host, name);
            if isempty(tool)
                return
            end

            tool.disable();
        end

        function tf = enabled(host, name)
            % Public query helper used by apps and smoke tests.
            tool = matlabx.ui.axes.ImageAxesToolRegistry.getInstalled(host, name);
            tf = ~isempty(tool) && isvalid(tool) && tool.Enabled;
        end

        function toggle(host, toolState, name)
            % Toolbar state buttons call this with their Value.
            switch toolState
                case true
                    matlabx.ui.axes.ImageAxesToolRegistry.enable(host, name);
                case false
                    matlabx.ui.axes.ImageAxesToolRegistry.disable(host, name);
            end
        end

        function push(host, name)
            % Toolbar push buttons call this; currently just a semantic alias to run.
            matlabx.ui.axes.ImageAxesToolRegistry.run(host, name);
        end

        function run(host, name)
            % Push-style tools execute onPush() through AxesTool.push().
            tool = matlabx.ui.axes.ImageAxesToolRegistry.getInstalled(host, name);
            if isempty(tool)
                return
            end

            tool.push();
        end

        function disableActiveExclusive(host)
            % Exclusive tools are coordinated by the host, but the actual disable
            % operation is still routed through the registry for consistency.
            existingExclusive = host.ActiveExclusiveTool;

            if isempty(existingExclusive)
                return
            end

            matlabx.ui.axes.ImageAxesToolRegistry.disable(host, existingExclusive.Name);
        end

        function tool = getInstalled(host, name)
            % Return [] instead of erroring to match existing ImageAxes behavior.
            tool = [];

            if ~isempty(host.ToolRegistry) && isKey(host.ToolRegistry, char(name))
                tool = host.ToolRegistry(char(name));
            end
        end

        function tool = getLoaded(host, name)
            % Return [] instead of erroring to match existing ImageAxes behavior.
            tool = [];

            if ~isempty(host.ToolList) && isKey(host.ToolList, char(name))
                tool = host.ToolList(char(name));
            end
        end

        function tool = getPriorityInterceptor(host, eventType)
        %GETPRIORITYINTERCEPTOR Highest-priority enabled active interceptor.
        %
        %   Active interceptors receive the event instead of the host/default path.
            toolsCell = matlabx.ui.axes.ImageAxesToolRegistry.installedToolValues(host);

            if isempty(toolsCell)
                tool = [];
                return
            end

            % Dynamic property access maps event kinds like "Down" to tool flags
            % such as InterceptsDown.
            idx = cellfun(@(t) t.Enabled & t.("Intercepts" + eventType), toolsCell, 'UniformOutput', true);

            if ~any(idx)
                tool = [];
                return
            end

            % Highest Priority wins; prioritySortCell sorts descending.
            tools = matlabx.ui.axes.ImageAxesToolRegistry.prioritySortCell(toolsCell(idx));
            tool = tools{1};
        end

        function toolsCell = getPriorityPassiveInterceptors(host, eventType)
        %GETPRIORITYPASSIVEINTERCEPTORS Installed passive interceptors for eventType.
        %
        %   Passive interceptors observe events before the active interceptor and do
        %   not require Enabled=true.
            toolsCell = matlabx.ui.axes.ImageAxesToolRegistry.installedToolValues(host);

            if isempty(toolsCell)
                return
            end

            % Dynamic property access maps event kinds like "Move" to tool flags
            % such as PassivelyInterceptsMove.
            idx = cellfun(@(t) t.("PassivelyIntercepts" + eventType), toolsCell, 'UniformOutput', true);

            if ~any(idx)
                toolsCell = {};
                return
            end

            toolsCell = matlabx.ui.axes.ImageAxesToolRegistry.prioritySortCell(toolsCell(idx));
        end

        function toolsCell = prioritySort(host)
            % Sorted installed tools are used for pointer and label contributions.
            toolsCell = matlabx.ui.axes.ImageAxesToolRegistry.prioritySortCell( ...
                matlabx.ui.axes.ImageAxesToolRegistry.installedToolValues(host));
        end

        function toolsCell = prioritySortCell(toolsCell)
            % Stable enough for current use: equal priorities preserve sort's normal
            % behavior for the input cell array.
            if isempty(toolsCell)
                return
            end

            priority = cellfun(@(t) t.Priority, toolsCell, 'UniformOutput', true);
            [~, sortIdx] = sort(priority, 'descend');
            toolsCell = toolsCell(sortIdx);
        end

        function names = getToolBox(host)
            % ToolBox is the public view of loaded tool names.
            names = host.ToolList.keys;
        end

        function setToolBox(host, newToolBox)
            % ToolBox changes construct/delete tool objects. Installing is handled by
            % ToolBelt, so removing a loaded installed tool first uninstalls it.
            oldToolBox = matlabx.ui.axes.ImageAxesToolRegistry.getToolBox(host);
            toolsToAdd = setdiff(newToolBox, oldToolBox, 'stable');
            toolsToRemove = setdiff(oldToolBox, newToolBox, 'stable');

            matlabx.ui.axes.ImageAxesToolRegistry.loadMany(host, toolsToAdd);
            matlabx.ui.axes.ImageAxesToolRegistry.unloadMany(host, toolsToRemove);
        end

        function names = getToolBelt(host)
            % ToolBelt is the public view of installed tool names.
            names = host.ToolRegistry.keys;
        end

        function setToolBelt(host, newToolBelt)
            % ToolBelt changes installation state. New tools are loaded on demand but
            % removed tools are only uninstalled, not unloaded.
            oldToolBelt = matlabx.ui.axes.ImageAxesToolRegistry.getToolBelt(host);
            toolsToAdd = setdiff(newToolBelt, oldToolBelt, 'stable');
            toolsToRemove = setdiff(oldToolBelt, newToolBelt, 'stable');

            for i = 1:numel(toolsToAdd)
                % Preserve existing behavior: installing a missing tool implicitly
                % loads it first.
                if ~host.ToolList.isKey(toolsToAdd{i})
                    matlabx.ui.axes.ImageAxesToolRegistry.load(host, toolsToAdd{i});
                end

                matlabx.ui.axes.ImageAxesToolRegistry.install(host, toolsToAdd{i});
            end

            matlabx.ui.axes.ImageAxesToolRegistry.uninstallMany(host, toolsToRemove);
        end

        function uninstallMany(host, toolNames)
            % Bulk wrapper used by ToolBelt removal.
            if isempty(toolNames)
                return
            end

            for i = 1:numel(toolNames)
                matlabx.ui.axes.ImageAxesToolRegistry.uninstall(host, toolNames{i});
            end
        end

        function addToolbarButton(host, tool)
        %ADDTOOLBARBUTTON Create a MATLAB axes toolbar button for an installed tool.
            switch tool.Style
                case 'push'
                    host.ToolbarButtons.(tool.Name) = axtoolbarbtn(host.mainAxes.Toolbar, 'push', ...
                        'Tooltip', tool.Tooltip, ...
                        'Icon', tool.Icon, ...
                        'ButtonPushedFcn', @(~,~) host.onToolPush(tool.Name));
                case 'state'
                    % State buttons mirror AxesTool.Enabled through enable/disable.
                    host.ToolbarButtons.(tool.Name) = axtoolbarbtn(host.mainAxes.Toolbar, 'state', ...
                        'Tooltip', tool.Tooltip, ...
                        'Icon', tool.Icon, ...
                        'ValueChangedFcn', @(btn,~) host.onToolToggle(btn.Value, tool.Name));
            end

            % MATLAB axes toolbars can fail to redraw newly added buttons until reset.
            host.mainAxes.Toolbar.reset;
        end

        function removeToolbarButton(host, tool)
        %REMOVETOOLBARBUTTON Delete the toolbar button associated with a tool.
            if ~isfield(host.ToolbarButtons, tool.Name)
                return
            end

            % A deleted/invalid toolbar button can happen during figure teardown.
            tbButton = host.ToolbarButtons.(tool.Name);

            if ~isvalid(tbButton)
                return
            end

            delete(tbButton)
            host.ToolbarButtons = rmfield(host.ToolbarButtons, tool.Name);
            host.mainAxes.Toolbar.reset;
        end
    end

    methods (Static, Access=private)
        function toolsCell = installedToolValues(host)
            % Normalize empty map state to an empty cell array for callers.
            if isempty(host.ToolRegistry)
                toolsCell = {};
            else
                toolsCell = host.ToolRegistry.values;
            end
        end
    end

end
