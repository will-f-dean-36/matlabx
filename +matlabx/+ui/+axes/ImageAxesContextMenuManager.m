classdef ImageAxesContextMenuManager < handle
%IMAGEAXESCONTEXTMENUMANAGER Context-menu helper for ImageAxes.
%
%   ImageAxes has a host-owned context menu for display and inspection actions.
%   This manager owns the uicontextmenu handle, builds the current built-in menu
%   entries, and provides a small flat-item API that tools or app code can use
%   later without pushing more menu bookkeeping into ImageAxes.
%
%   The built-in menu policy is intentionally modest:
%       * Status command for a compact operational report.
%       * Reset View command.
%       * Image submenu grouping image/data/display commands.
%       * Overlays submenu grouping visual aids drawn over/around the image.
%       * Image Properties and Metadata commands.
%       * Color Mode and Component Color submenus.
%       * addItem/removeItem helpers for future simple contributions.
%
%   "Context menu manager" here means a collaborator object scoped to one
%   ImageAxes host. It does not decide application policy; it only owns menu
%   graphics and callback wiring.

    properties (SetAccess=private)
        Host matlabx.ui.axes.ImageAxes
        Menu matlab.ui.container.ContextMenu
    end

    properties (Access=private)
        BuiltinUI struct = struct()
        Items struct = struct()
        BuiltinItems_ (1,:) string = ["Status","ResetView","Image","Overlays"]
    end

    methods
        function obj = ImageAxesContextMenuManager(host, parentFigure)
        %IMAGEAXESCONTEXTMENUMANAGER Create and build the host context menu.
            obj.Host = host;
            obj.Menu = uicontextmenu(parentFigure);
            obj.Menu.ContextMenuOpeningFcn = @(~,~) obj.refresh();
            obj.Host.ContextMenu = obj.Menu;
            obj.rebuild();
        end

        function rebuild(obj)
        %REBUILD Recreate the built-in context-menu contents.
            obj.clearBuiltins();

            S = struct();

            if obj.hasBuiltin("Status")
                S = obj.buildStatusMenu(S, obj.Menu);
            end

            if obj.hasBuiltin("ResetView")
                S = obj.buildResetViewMenu(S, obj.Menu);
            end

            if obj.hasBuiltin("Image")
                S = obj.buildImageMenu(S);
            end

            if obj.hasBuiltin("Overlays")
                S = obj.buildOverlaysMenu(S);
            end

            if obj.hasBuiltin("ImageProperties") && ~obj.hasBuiltin("Image")
                S = obj.buildImagePropertiesMenu(S, obj.Menu);
            end

            if obj.hasBuiltin("Metadata") && ~obj.hasBuiltin("Image")
                S = obj.buildMetadataMenu(S, obj.Menu);
            end

            if obj.hasBuiltin("ComponentColor") && ~obj.hasBuiltin("Image")
                S = obj.buildComponentColorMenu(S, obj.Menu);
            end

            if obj.hasBuiltin("ColorMode") && ~obj.hasBuiltin("Image")
                S = obj.buildColorModeMenu(S, obj.Menu);
            end

            if obj.hasBuiltin("ViewportBox") && ~obj.hasBuiltin("Overlays")
                S = obj.buildViewportBoxMenu(S, obj.Menu);
            end

            obj.BuiltinUI = S;
            obj.refresh();
        end

        function clear(obj)
        %CLEAR Delete all current menu children and forget item handles.
            if isvalid(obj.Menu)
                delete(obj.Menu.Children)
            end

            obj.BuiltinUI = struct();
            obj.Items = struct();
        end

        function refresh(obj)
        %REFRESH Update dynamic checked/enabled state for existing menu items.
            if isfield(obj.BuiltinUI, "ColorMode_colors")
                val = string(obj.Host.ComponentColorMode);
                obj.BuiltinUI.ColorMode_colors.Checked = ...
                    matlab.lang.OnOffSwitchState(val == "colors");
                obj.BuiltinUI.ColorMode_luts.Checked = ...
                    matlab.lang.OnOffSwitchState(val == "luts");
            end

            if isfield(obj.BuiltinUI, "ComponentColor")
                canHaveColor = obj.Host.currentComponentCanHaveColor();
                obj.BuiltinUI.ComponentColor.Enable = ...
                    matlab.lang.OnOffSwitchState(canHaveColor);

                currentName = string(obj.Host.currentComponentColorName());
                colorNames = string(matlabx.ui.axes.ImageAxes.getColorNames());

                for i = 1:numel(colorNames)
                    fieldName = obj.componentColorFieldName(colorNames(i));
                    if isfield(obj.BuiltinUI, fieldName)
                        obj.BuiltinUI.(fieldName).Checked = ...
                            matlab.lang.OnOffSwitchState(canHaveColor && currentName == colorNames(i));
                    end
                end
            end

            if isfield(obj.BuiltinUI, "ViewportBox")
                obj.BuiltinUI.ViewportBox.Checked = obj.Host.ViewportBoxVisible;
            end

            obj.refreshItems();
        end

        function openAt(obj, xy)
        %OPENAT Open the context menu at a figure-coordinate point.
            obj.refresh();
            open(obj.Menu, xy(1), xy(2));
        end

        function items = getBuiltinItems(obj)
        %GETBUILTINITEMS Return enabled built-in menu item names.
            items = obj.BuiltinItems_;
        end

        function setBuiltinItems(obj, items)
        %SETBUILTINITEMS Choose which ImageAxes built-in menu items to show.
            obj.BuiltinItems_ = obj.validateBuiltinItems(items);
            obj.rebuild();
        end

        function h = addSubmenu(obj, id, label, opts)
        %ADDSUBMENU Add or replace a contributed submenu.
            arguments
                obj
                id (1,1) string
                label (1,1) string
                opts.Parent = ""
                opts.Owner = []
                opts.Separator matlab.lang.OnOffSwitchState = "off"
                opts.Enabled matlab.lang.OnOffSwitchState = "on"
                opts.Visible matlab.lang.OnOffSwitchState = "on"
                opts.RefreshFcn = []
            end

            obj.removeItem(id);

            parent = obj.getParentMenu(opts.Parent);
            fieldName = obj.idToFieldName(id);
            h = uimenu(parent, ...
                "Text", label, ...
                "Separator", opts.Separator, ...
                "Enable", opts.Enabled, ...
                "Visible", opts.Visible);

            obj.Items.(fieldName) = obj.makeItemEntry(h, opts.Owner, opts.RefreshFcn);
        end

        function h = addItem(obj, id, label, callback, opts)
        %ADDITEM Add or replace a contributed context-menu item.
        %
        %   Parent can be empty for a top-level item or the id of another
        %   contributed item/submenu. Owner lets a tool remove all of its menu
        %   contributions during uninstall. RefreshFcn, when supplied, is called
        %   during refresh() with the menu handle so checked/enabled state can
        %   follow host/tool state.
            arguments
                obj
                id (1,1) string
                label (1,1) string
                callback (1,1) function_handle
                opts.Parent = ""
                opts.Owner = []
                opts.Separator matlab.lang.OnOffSwitchState = "off"
                opts.Checked matlab.lang.OnOffSwitchState = "off"
                opts.Enabled matlab.lang.OnOffSwitchState = "on"
                opts.Visible matlab.lang.OnOffSwitchState = "on"
                opts.UserData = []
                opts.RefreshFcn = []
            end

            obj.removeItem(id);

            parent = obj.getParentMenu(opts.Parent);
            fieldName = obj.idToFieldName(id);
            h = uimenu(parent, ...
                "Text", label, ...
                "MenuSelectedFcn", callback, ...
                "Separator", opts.Separator, ...
                "Checked", opts.Checked, ...
                "Enable", opts.Enabled, ...
                "Visible", opts.Visible, ...
                "UserData", opts.UserData);

            obj.Items.(fieldName) = obj.makeItemEntry(h, opts.Owner, opts.RefreshFcn);
        end

        function removeItem(obj, id)
        %REMOVEITEM Delete a previously added contributed context-menu item.
            fieldName = obj.idToFieldName(id);
            if ~isfield(obj.Items, fieldName)
                return
            end

            h = obj.Items.(fieldName).Handle;
            if isvalid(h)
                delete(h)
            end

            obj.Items = rmfield(obj.Items, fieldName);
        end

        function removeOwner(obj, owner)
        %REMOVEOWNER Delete every contributed item associated with an owner.
            fieldNames = fieldnames(obj.Items);
            remove = false(size(fieldNames));

            for i = 1:numel(fieldNames)
                entry = obj.Items.(fieldNames{i});
                remove(i) = obj.ownersMatch(entry.Owner, owner);
            end

            for i = numel(fieldNames):-1:1
                if remove(i)
                    obj.removeItem(fieldNames{i});
                end
            end
        end

        function setItemEnabled(obj, id, enabled)
        %SETITEMENABLED Set the Enable state for a contributed item.
            obj.setItemProperty(id, "Enable", enabled);
        end

        function setItemVisible(obj, id, visible)
        %SETITEMVISIBLE Set the Visible state for a contributed item.
            obj.setItemProperty(id, "Visible", visible);
        end

        function setItemChecked(obj, id, checked)
        %SETITEMCHECKED Set the Checked state for a contributed item.
            obj.setItemProperty(id, "Checked", checked);
        end
    end

    methods (Access=private)
        function clearBuiltins(obj)
        %CLEARBUILTINS Delete built-in menu handles without touching contributions.
            handles = obj.collectHandles(obj.BuiltinUI);
            for i = 1:numel(handles)
                h = handles{i};
                if isvalid(h)
                    delete(h)
                end
            end

            obj.BuiltinUI = struct();
        end

        function tf = hasBuiltin(obj, name)
        %HASBUILTIN True when a named built-in item should be shown.
            tf = any(obj.BuiltinItems_ == name);
        end

        function S = buildResetViewMenu(obj, S, parent)
        %BUILDRESETVIEWMENU Add a top-level/default view reset command.
            S.ResetView = uimenu(parent, ...
                "Text", "Reset View", ...
                "MenuSelectedFcn", @(~,~) obj.Host.resetView());
        end

        function S = buildStatusMenu(obj, S, parent)
        %BUILDSTATUSMENU Add a compact ImageAxes status report command.
            S.Status = uimenu(parent, ...
                "Text", "Status...", ...
                "MenuSelectedFcn", @(~,~) obj.Host.openStatusWindow());
        end

        function S = buildImageMenu(obj, S)
        %BUILDIMAGEMENU Add grouped image/data/display commands.
            S.Image = uimenu(obj.Menu, "Text", "Image");
            S = obj.buildImagePropertiesMenu(S, S.Image);
            S = obj.buildMetadataMenu(S, S.Image);
            S = obj.buildComponentColorMenu(S, S.Image, "on");
            S = obj.buildColorModeMenu(S, S.Image);
        end

        function S = buildOverlaysMenu(obj, S)
        %BUILDOVERLAYSMENU Add grouped image overlay/display-aid commands.
            S.Overlays = uimenu(obj.Menu, "Text", "Overlays");
            S = obj.buildViewportBoxMenu(S, S.Overlays);
        end

        function S = buildImagePropertiesMenu(obj, S, parent)
        %BUILDIMAGEPROPERTIESMENU Add generated ImageData summary command.
            S.ImageProperties = uimenu(parent, ...
                "Text", "Properties...", ...
                "MenuSelectedFcn", @(~,~) obj.Host.openImagePropertiesWindow());
        end

        function S = buildMetadataMenu(obj, S, parent)
        %BUILDMETADATAMENU Add raw/source metadata display command.
            S.Metadata = uimenu(parent, ...
                "Text", "Metadata...", ...
                "MenuSelectedFcn", @(~,~) obj.Host.openMetadataWindow());
        end

        function S = buildColorModeMenu(obj, S, parent)
        %BUILDCOLORMODEMENU Add the ComponentColorMode submenu.
            S.ColorMode = uimenu(parent, "Text", "Color Mode...");
            S.ColorMode_colors = uimenu(S.ColorMode, ...
                "Text", "colors", ...
                "MenuSelectedFcn", @(~,~) obj.Host.setComponentColorMode("colors"), ...
                "Checked", "on");
            S.ColorMode_luts = uimenu(S.ColorMode, ...
                "Text", "luts", ...
                "MenuSelectedFcn", @(~,~) obj.Host.setComponentColorMode("luts"), ...
                "Checked", "off");
        end

        function S = buildViewportBoxMenu(obj, S, parent)
        %BUILDVIEWPORTBOXMENU Add a toggle for the persistent viewport overlay.
            S.ViewportBox = uimenu(parent, ...
                "Text", "Viewport Box", ...
                "MenuSelectedFcn", @(~,~) obj.Host.toggleViewportBoxVisible(), ...
                "Checked", obj.Host.ViewportBoxVisible);
        end

        function S = buildComponentColorMenu(obj, S, parent, separator)
        %BUILDCOMPONENTCOLORMENU Add current-component color choices.
            arguments
                obj
                S struct
                parent
                separator matlab.lang.OnOffSwitchState = "off"
            end

            S.ComponentColor = uimenu(parent, ...
                "Text", "Component Color...", ...
                "Separator", separator);

            colorNames = string(matlabx.ui.axes.ImageAxes.getColorNames());
            for i = 1:numel(colorNames)
                name = colorNames(i);
                fieldName = obj.componentColorFieldName(name);
                S.(fieldName) = uimenu(S.ComponentColor, ...
                    "Text", char(name), ...
                    "MenuSelectedFcn", @(~,~) obj.Host.setComponentColor(name), ...
                    "Checked", "off");
            end
        end

        function setItemProperty(obj, id, propertyName, value)
        %SETITEMPROPERTY Set one property on a contributed item if it exists.
            fieldName = obj.idToFieldName(id);
            if ~isfield(obj.Items, fieldName)
                return
            end

            h = obj.Items.(fieldName).Handle;
            if isvalid(h)
                h.(propertyName) = value;
            end
        end

        function refreshItems(obj)
        %REFRESHITEMS Run refresh callbacks for contributed menu items.
            fieldNames = fieldnames(obj.Items);
            for i = 1:numel(fieldNames)
                entry = obj.Items.(fieldNames{i});
                h = entry.Handle;
                if ~isvalid(h) || isempty(entry.RefreshFcn)
                    continue
                end

                entry.RefreshFcn(h);
            end
        end

        function parent = getParentMenu(obj, parentId)
        %GETPARENTMENU Return the root menu or a contributed parent item.
            if isempty(parentId) || strlength(string(parentId)) == 0
                parent = obj.Menu;
                return
            end

            fieldName = obj.idToFieldName(parentId);
            if ~isfield(obj.Items, fieldName)
                error('ImageAxesContextMenuManager:MissingParent', ...
                    'Context menu parent "%s" does not exist.', string(parentId))
            end

            parent = obj.Items.(fieldName).Handle;
        end
    end

    methods (Static)
        function items = availableBuiltinItems()
        %AVAILABLEBUILTINITEMS Return valid ImageAxes built-in context item names.
            items = ["Status","ResetView","Image","ImageProperties","Metadata", ...
                "ComponentColor","ColorMode","Overlays","ViewportBox"];
        end

        function items = validateBuiltinItems(items)
        %VALIDATEBUILTINITEMS Validate and canonicalize built-in item names.
            items = string(items);
            items = reshape(items, 1, []);

            available = matlabx.ui.axes.ImageAxesContextMenuManager.availableBuiltinItems();
            for i = 1:numel(items)
                match = strcmpi(items(i), available);
                if ~any(match)
                    error('ImageAxesContextMenuManager:InvalidBuiltinItem', ...
                        '"%s" is not a valid ImageAxes context menu item.', items(i))
                end

                items(i) = available(find(match, 1, 'first'));
            end

            items = unique(items, "stable");
        end
    end

    methods (Static, Access=private)
        function entry = makeItemEntry(handle, owner, refreshFcn)
        %MAKEITEMENTRY Package a contributed item handle and metadata.
            entry = struct( ...
                "Handle", handle, ...
                "Owner", owner, ...
                "RefreshFcn", refreshFcn);
        end

        function handles = collectHandles(S)
        %COLLECTHANDLES Return handle values stored inside a struct.
            handles = {};
            if isempty(S) || ~isstruct(S)
                return
            end

            values = struct2cell(S);
            for i = 1:numel(values)
                value = values{i};
                if isa(value, 'handle')
                    handles{end+1} = value; %#ok<AGROW>
                end
            end
        end

        function tf = ownersMatch(a, b)
        %OWNERSMATCH True when two owner tokens refer to the same contributor.
            if isempty(a) && isempty(b)
                tf = true;
                return
            end

            if isa(a, 'handle') || isa(b, 'handle')
                tf = isa(a, 'handle') && isa(b, 'handle') && isvalid(a) && ...
                    isvalid(b) && a == b;
                return
            end

            tf = isequal(a, b);
        end

        function fieldName = idToFieldName(id)
        %IDTOFIELDNAME Convert a stable string item id into a struct field name.
            fieldName = matlab.lang.makeValidName(char(id));
        end

        function fieldName = componentColorFieldName(name)
        %COMPONENTCOLORFIELDNAME Return the BuiltinUI field for a color item.
            fieldName = matlab.lang.makeValidName("ComponentColor_" + string(name));
        end
    end

end
