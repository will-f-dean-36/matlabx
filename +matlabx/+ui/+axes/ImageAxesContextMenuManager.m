classdef ImageAxesContextMenuManager < handle
%IMAGEAXESCONTEXTMENUMANAGER Context-menu helper for ImageAxes.
%
%   ImageAxes has a host-owned context menu for display and inspection actions.
%   This manager owns the uicontextmenu handle, builds the current built-in menu
%   entries, and provides a small flat-item API that tools or app code can use
%   later without pushing more menu bookkeeping into ImageAxes.
%
%   The built-in menu policy is intentionally modest:
%       * Reset View command.
%       * Image submenu grouping image/data/display commands.
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
        BuiltinItems_ (1,:) string = ["ResetView","Image"]
    end

    methods
        function obj = ImageAxesContextMenuManager(host, parentFigure)
        %IMAGEAXESCONTEXTMENUMANAGER Create and build the host context menu.
            obj.Host = host;
            obj.Menu = uicontextmenu(parentFigure);
            obj.Host.ContextMenu = obj.Menu;
            obj.rebuild();
        end

        function rebuild(obj)
        %REBUILD Recreate the built-in context-menu contents.
            obj.clear();

            S = struct();

            if obj.hasBuiltin("ResetView")
                S = obj.buildResetViewMenu(S, obj.Menu);
            end

            if obj.hasBuiltin("Image")
                S = obj.buildImageMenu(S);
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
        end

        function openAt(obj, xy)
        %OPENAT Open the context menu at a figure-coordinate point.
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

        function h = addItem(obj, id, label, callback, opts)
        %ADDITEM Add or replace a simple top-level context-menu item.
        %
        %   This helper is intentionally flat for now. More structured submenu and
        %   group support can layer on top once tool/app menu contributions become
        %   common enough to need it.
            arguments
                obj
                id (1,1) string
                label (1,1) string
                callback (1,1) function_handle
                opts.Separator matlab.lang.OnOffSwitchState = "off"
                opts.Checked matlab.lang.OnOffSwitchState = "off"
                opts.Enabled matlab.lang.OnOffSwitchState = "on"
                opts.Visible matlab.lang.OnOffSwitchState = "on"
            end

            obj.removeItem(id);

            fieldName = obj.idToFieldName(id);
            h = uimenu(obj.Menu, ...
                "Text", label, ...
                "MenuSelectedFcn", callback, ...
                "Separator", opts.Separator, ...
                "Checked", opts.Checked, ...
                "Enable", opts.Enabled, ...
                "Visible", opts.Visible);

            obj.Items.(fieldName) = h;
        end

        function removeItem(obj, id)
        %REMOVEITEM Delete a previously added top-level context-menu item.
            fieldName = obj.idToFieldName(id);
            if ~isfield(obj.Items, fieldName)
                return
            end

            h = obj.Items.(fieldName);
            if isvalid(h)
                delete(h)
            end

            obj.Items = rmfield(obj.Items, fieldName);
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

        function S = buildImageMenu(obj, S)
        %BUILDIMAGEMENU Add grouped image/data/display commands.
            S.Image = uimenu(obj.Menu, "Text", "Image");
            S = obj.buildImagePropertiesMenu(S, S.Image);
            S = obj.buildMetadataMenu(S, S.Image);
            S = obj.buildComponentColorMenu(S, S.Image, "on");
            S = obj.buildColorModeMenu(S, S.Image);
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

            h = obj.Items.(fieldName);
            if isvalid(h)
                h.(propertyName) = value;
            end
        end
    end

    methods (Static)
        function items = availableBuiltinItems()
        %AVAILABLEBUILTINITEMS Return valid ImageAxes built-in context item names.
            items = ["ResetView","Image","ImageProperties","Metadata","ComponentColor","ColorMode"];
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
