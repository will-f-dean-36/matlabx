classdef PlotAxesExportDialog
%PLOTAXESEXPORTDIALOG Collect PlotAxes file and host-style export options.
%
%   OPTIONS = matlabx.ui.axes.PlotAxesExportDialog.prompt(HOST) opens a
%   tabbed dialog. Vector and raster output types expose only
%   compatible formats, and raster resolution is enabled only for images.
%   The shared axes tabs return settings for the export copy.

% matlabx - MATLAB utilities for app building, image display, and analysis.
% Copyright (C) 2026 William Dean
%
% This program is free software; you can redistribute it and/or modify it
% under the terms of the GNU General Public License as published by the Free
% Software Foundation; either version 2 of the License, or (at your option)
% any later version.
%
% This program is distributed in the hope that it will be useful, but WITHOUT
% ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
% FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
% details.
%
% You should have received a copy of the GNU General Public License along
% with this program; if not, see <https://www.gnu.org/licenses/>.

    methods (Static)

        function options = prompt(host,previewFcn,previewAxes)
        %PROMPT Open the modal export dialog and return accepted options.
        %   A preview callback receives valid options and a visibility flag.
        %   An empty options value leaves the previous preview layout intact.

            arguments
                host (1,1) matlabx.ui.axes.PlotAxes
                previewFcn = []
                previewAxes = host.Axes
            end

            background = [.12 .12 .12];
            paneColor = [.18 .18 .18];
            controlColor = [.3 .3 .3];
            fontColor = [.85 .85 .85];
            controlFontColor = [.9 .9 .9];
            options = [];

            fig = uifigure(Visible="off",Name="Export Plot", ...
                InnerPosition=[0 0 520 600],Resize="off", ...
                WindowStyle="modal",Color=background, ...
                CloseRequestFcn=@(~,~) closeDialog());
            root = uigridlayout(fig,[2 1],Padding=[10 10 10 10], ...
                RowSpacing=10,ColumnSpacing=0,BackgroundColor=background, ...
                RowHeight={'1x','fit'},ColumnWidth={'1x'});

            tabs = uitabgroup(root);
            tab = uitab(tabs,Title="Export Options",BackgroundColor=paneColor, ...
                ForegroundColor=fontColor);
            filePane = uigridlayout(tab,[8 2],ColumnWidth={'fit','1x'}, ...
                RowHeight=[repmat({'fit'},1,7),{'1x'}],Padding=[5 5 5 5], ...
                ColumnSpacing=5,RowSpacing=5,BackgroundColor=paneColor,Scrollable="on");
            outputType = addDropDown(filePane,1,"Output type", ...
                {'Vector','Image'},'Vector');
            format = addDropDown(filePane,2,"Format",{'PDF','SVG'},'SVG');
            units = addDropDown(filePane,3,"Units", ...
                {'inches','centimeters','points'},'inches');
            width = addDimension(filePane,4,"Width","7");
            height = addDimension(filePane,5,"Height","");
            dimensionHint = addLabel(filePane,6, ...
                "Leave one dimension blank to preserve the plot’s shape.");
            dimensionHint.Layout.Column = [1 2];
            resolution = addNumeric(filePane,7,"Resolution (DPI)",300);
            [readAxes,refreshLimits,restoreDefaults,revert] = matlabx.ui.axes.internal.plotAxesControlTabs(tabs,host,@updatePreview,true,filePane);
            outputType.ValueChangedFcn = @(~,~) outputTypeChanged();
            % Units in which the existing dimension entries are expressed.
            currentUnits = string(units.Value);
            units.ValueChangedFcn = @(~,~) unitsChanged();
            updateOutputType();

            buttons = uigridlayout(root,[1 5],Padding=0,RowSpacing=0, ...
                ColumnSpacing=5,ColumnWidth={'1x',105,105,70,70},RowHeight={'fit'}, ...
                BackgroundColor=background);
            buttons.Layout.Row = 2;
            restoreButton = uibutton(buttons,Text="Restore defaults", ...
                BackgroundColor=controlColor,FontColor=controlFontColor, ...
                ButtonPushedFcn=@(~,~) restorePlotDefaults());
            restoreButton.Layout.Column = 2;
            revertButton = uibutton(buttons,Text="Revert changes", ...
                BackgroundColor=controlColor,FontColor=controlFontColor, ...
                ButtonPushedFcn=@(~,~) revertChanges());
            revertButton.Layout.Column = 3;
            cancel = uibutton(buttons,Text="Cancel", ...
                BackgroundColor=controlColor,FontColor=controlFontColor, ...
                ButtonPushedFcn=@(~,~) closeDialog());
            cancel.Layout.Column = 4;
            export = uibutton(buttons,Text="Continue", ...
                BackgroundColor=[.18 .42 .68],FontColor=[1 1 1], ...
                ButtonPushedFcn=@(~,~) acceptDialog());
            export.Layout.Column = 5;

            if ~isempty(previewFcn)
                showPreview = uicheckbox(buttons,Text="Show preview", ...
                    Value=false,FontColor=controlFontColor, ...
                    ValueChangedFcn=@(~,~) updatePreview());
                showPreview.Layout.Column = 1;
                controls = {format,width,height,resolution};
                for k = 1:numel(controls)
                    controls{k}.ValueChangedFcn = @(~,~) updatePreview();
                end
            end

            % File settings restored separately from the shared appearance and view tabs.
            fileControls = {outputType,format,units,width,height,resolution};
            % Initial export options before changing the format or dimensions.
            openingFileValues = cellfun(@(h) h.Value,fileControls,UniformOutput=false);

            movegui(fig,"center");
            fig.Visible = "on";
            updatePreview();
            uiwait(fig);
            if isgraphics(fig), delete(fig); end

            function label = addLabel(pane,row,text)
            %ADDLABEL Create a left-column caption for a settings row.
                label = uilabel(pane,Text=text,FontColor=fontColor);
                label.Layout.Row = row;
                label.Layout.Column = 1;
            end

            function control = addDropDown(pane,row,label,items,value)
            %ADDDROPDOWN Create a styled dropdown and bind its change callback.
                addLabel(pane,row,label);
                control = uidropdown(pane,Items=items,Value=value, ...
                    BackgroundColor=controlColor,FontColor=controlFontColor);
                control.Layout.Row = row;
                control.Layout.Column = 2;
            end

            function control = addNumeric(pane,row,label,value)
            %ADDNUMERIC Create a styled numeric field for an export setting.
                addLabel(pane,row,label);
                control = uieditfield(pane,"numeric",Value=value, ...
                    BackgroundColor=controlColor,FontColor=controlFontColor);
                control.Layout.Row = row;
                control.Layout.Column = 2;
            end

            function control = addDimension(pane,row,label,value)
            %ADDDIMENSION Create an optional dimension field with an Auto placeholder.
                addLabel(pane,row,label);
                control = uieditfield(pane,"text",Value=value,Placeholder="Auto", ...
                    BackgroundColor=controlColor,FontColor=controlFontColor);
                control.Layout.Row = row;
                control.Layout.Column = 2;
            end

            function control = addCheckBox(pane,row,label,value)
            %ADDCHECKBOX Create a checkbox and its settings caption.
                addLabel(pane,row,label);
                control = uicheckbox(pane,Text="",Value=value, ...
                    FontColor=controlFontColor);
                control.Layout.Row = row;
                control.Layout.Column = 2;
            end

            function updateOutputType()
            %UPDATEOUTPUTTYPE Select the formats and units supported by the output type.
                if string(outputType.Value) == "Vector"
                    units.Items = {'inches','centimeters','points'};
                    format.Items = {'PDF','SVG'};
                    format.Value = 'SVG';
                    resolution.Enable = 'off';
                else
                    units.Items = {'inches','centimeters','points','pixels'};
                    format.Items = {'PNG','TIFF'};
                    format.Value = 'PNG';
                    resolution.Enable = 'on';
                end
            end

            function value = readDimension(control)
            %READDIMENSION Read a dimension, using an empty value for automatic sizing.
                input = strip(string(control.Value));
                value = [];
                if strlength(input) > 0, value = str2double(input); end
            end

            function outputTypeChanged()
            %OUTPUTTYPECHANGED Preserve dimensions as available units and formats change.
                nextUnits = currentUnits;
                if string(outputType.Value) == "Vector" && currentUnits == "pixels"
                    % Units that remain valid for the newly selected output type.
                    nextUnits = "inches";
                end
                if ~convertDimensions(nextUnits)
                    outputType.Value = 'Image';
                    return;
                end
                updateOutputType();
                units.Value = char(currentUnits);
                updatePreview();
            end

            function unitsChanged()
            %UNITSCHANGED Convert entered dimensions to the newly selected units.
                if ~convertDimensions(string(units.Value))
                    units.Value = char(currentUnits);
                    return;
                end
                updatePreview();
            end

            function ok = convertDimensions(nextUnits)
            %CONVERTDIMENSIONS Convert explicit dimensions while leaving Auto fields blank.
                ok = true;
                if currentUnits == nextUnits, return; end
                % Resolution used only when converting to or from pixels.
                dpi = resolution.Value;
                if any([currentUnits,nextUnits] == "pixels") && (~isfinite(dpi) || dpi <= 0)
                    uialert(fig,"Enter a positive resolution before converting pixel dimensions.", ...
                        "Invalid Resolution");
                    ok = false;
                    return;
                end
                % Multiplier that preserves physical dimensions in the new units.
                factor = matlabx.ui.axes.internal.exportUnitsPerInch(nextUnits,dpi) / ...
                    matlabx.ui.axes.internal.exportUnitsPerInch(currentUnits,dpi);
                for field = [width,height]
                    value = readDimension(field);
                    if ~isempty(value) && isreal(value) && isfinite(value)
                        field.Value = sprintf('%.15g',value * factor);
                    end
                end
                % Units in which the existing dimension entries are expressed.
                currentUnits = nextUnits;
            end

            function restorePlotDefaults()
            %RESTOREPLOTDEFAULTS Restore plot settings while leaving file options in place.
                restoreDefaults();
                updatePreview();
            end

            function revertChanges()
            %REVERTCHANGES Restore the opening controls and their associated plot state.
                outputType.Value = openingFileValues{1};
                updateOutputType();
                for k = 2:numel(fileControls)
                    fileControls{k}.Value = openingFileValues{k};
                end
                % Units in which the existing dimension entries are expressed.
                currentUnits = string(units.Value);
                if ~isempty(previewFcn), showPreview.Value = false; end
                revert();
                updatePreview();
            end

            function updatePreview()
            %UPDATEPREVIEW Apply valid options to the preview and refresh its displayed limits.
                if ~isempty(previewFcn)
                    % Latest valid export and axes settings, or empty for invalid input.
                    previewOptions = readOptions();
                    previewFcn(previewOptions,showPreview.Value);
                    drawnow nocallbacks;
                end
                refreshLimits(previewAxes);
            end

            function acceptDialog()
            %ACCEPTDIALOG Validate and return the accepted export options.
                [accepted,message] = readOptions();
                if isempty(accepted)
                    uialert(fig,message,"Invalid Export Options");
                    return;
                end
                options = accepted;
                uiresume(fig);
            end

            function [selected,message] = readOptions()
            %READOPTIONS Read the export fields and shared axes controls without applying them.
                selected = [];
                message = "";
                outputWidth = readDimension(width);
                outputHeight = readDimension(height);
                if isempty(outputWidth) && isempty(outputHeight)
                    message = "Enter a width or height.";
                    return;
                end
                positive = [outputWidth,outputHeight];
                if ~isreal(positive) || any(~isfinite(positive)) || any(positive <= 0)
                    message = "Width and height must be positive finite values.";
                    return;
                end
                if string(outputType.Value) == "Image" && ...
                        (~isfinite(resolution.Value) || resolution.Value <= 0 || ...
                        resolution.Value ~= fix(resolution.Value))
                    message = "Resolution must be a positive whole number.";
                    return;
                end
                [style,view,message] = readAxes();
                if strlength(message) > 0, return; end
                [extension,contentType] = selectedFormat();
                exportBackground = host.BackgroundColor;
                if ~isempty(host.BackgroundColorOverride)
                    exportBackground = host.BackgroundColorOverride;
                end
                if isfield(style,"BackgroundColorOverride") && ~isempty(style.BackgroundColorOverride)
                    exportBackground = style.BackgroundColorOverride;
                end
                selected = struct( ...
                    "ContentType",contentType, ...
                    "Format",string(format.Value), ...
                    "Extension",extension, ...
                    "Units",string(units.Value), ...
                    "Width",outputWidth, ...
                    "Height",outputHeight, ...
                    "Resolution",resolution.Value, ...
                    "BackgroundColor",exportBackground, ...
                    "AxesAppearance",style,"AxesView",view);
            end

            function [extension,contentType] = selectedFormat()
            %SELECTEDFORMAT Map the displayed format to its extension and content type.
                switch string(format.Value)
                    case "PDF"
                        extension = ".pdf";
                        contentType = "vector";
                    case "SVG"
                        extension = ".svg";
                        contentType = "vector";
                    case "PNG"
                        extension = ".png";
                        contentType = "image";
                    case "TIFF"
                        extension = ".tif";
                        contentType = "image";
                end
            end

            function closeDialog()
            %CLOSEDIALOG Cancel the dialog and release its modal wait.
                options = [];
                if isgraphics(fig)
                    uiresume(fig);
                    delete(fig);
                end
            end
        end

    end

end
