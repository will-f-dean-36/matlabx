function ax = quickshow(I,opts)
    arguments
        I
        opts.Colormap (256,3) double
        opts.Title (1,:) char = 'Viewer'
    end

    if ~isfield(opts,'Colormap') || isempty(opts.Colormap)
        opts.Colormap = gray(256);
    end

    f = uifigure(...
        "WindowStyle",          "alwaysontop",...
        "Position",             [0 0 500 500],...
        "Visible",              "off",...
        "AutoResizeChildren",   "off",...
        "Name",                 opts.Title);

    if isa(I,"matlabx.image.Image5D")
        ax = matlabx.ui.widgets.ImageAxes(f,...
            "ToolBelt",     {'Zoom', 'Colorbar', 'ChooseColormap', 'Pick'},...
            "ImageData",    I,...
            "Units",        "normalized",...
            "Position",     [0 0 1 1],...
            "Name",         "Viewer");
    else
        ax = matlabx.ui.widgets.ImageAxes(f,...
            "ToolBelt",     {'Zoom', 'Colorbar', 'ChooseColormap'},...
            "CData",        I,...
            "Units",        "normalized",...
            "Position",     [0 0 1 1],...
            "Colormap",     opts.Colormap,...
            "Name",         "Viewer");
    end

    cal = matlabx.ui.calibration.getCalibration();
    panelTopChromePx = cal.uipanelTopChromeHeightPx(ax.FontSize,"FontUnits","pixels");
    f.Position(3) = f.Position(4) - panelTopChromePx;


    movegui(f,"center")

    f.Visible = "on"; % Make the figure visible

end











% function ax = quickshow(I,opts)
%     arguments
%         I
%         opts.Colormap (256,3) double
%         opts.Title (1,:) char = 'Viewer'
%     end
% 
%     if ~isfield(opts,'Colormap') || isempty(opts.Colormap)
%         opts.Colormap = gray(256);
%     end
% 
%     f = uifigure(...
%         "WindowStyle",          "alwaysontop",...
%         "Position",             [0 0 500 500],...
%         "Visible",              "off",...
%         "AutoResizeChildren",   "off",...
%         "Name",                 opts.Title,...
%         "SizeChangedFcn",       @(o,e) updateOnResize());
% 
% 
%     mainGrid = uigridlayout(f,[1,1],...
%         "ColumnWidth",{'fit'},...
%         "RowHeight",{'fit'},...
%         "Padding",[0 0 0 0]);
% 
%     panelGrid = uigridlayout(mainGrid,[1,1],...
%         "RowHeight",{500},...
%         "ColumnWidth",{500},...
%         "Padding",[0 0 0 0]);
%     panelGrid.Layout.Row = 1;
%     panelGrid.Layout.Column = 1;
% 
%     p = uipanel("Parent",panelGrid,...
%         "Title","Test",...
%         "FontSize",10,...
%         "AutoResizeChildren","off");
% 
% 
%     aspectRatio = I.SizeX/I.SizeY;
%     cal = matlabx.ui.calibration.getCalibration();
%     panelTop = cal.uipanelTopChromeHeightPx(10);
% 
%     if isa(I,"matlabx.image.Image5D")
%         f.InnerPosition(4) = f.InnerPosition(3)/aspectRatio+panelTop;
% 
%         ax = matlabx.ui.widgets.ImageAxes(p,...
%             "ToolBelt",     {'Zoom', 'Colorbar', 'ChooseColormap', 'Pick'},...
%             "ImageData",    I,...
%             "Units",        "normalized",...
%             "Position",     [0 0 1 1],...
%             "Name",         "Viewer");
%     else
%         ax = matlabx.ui.widgets.ImageAxes(f,...
%             "ToolBelt",     {'Zoom', 'Colorbar', 'ChooseColormap'},...
%             "CData",        I,...
%             "Units",        "normalized",...
%             "Position",     [0 0 1 1],...
%             "Colormap",     opts.Colormap,...
%             "Name",         "Viewer");
%     end
% 
%     movegui(f,"center")
% 
%     f.Visible = "on"; % Make the figure visible
% 
% 
%     function updateOnResize()
% 
%         iPos = f.InnerPosition;
%         W = iPos(3);
%         H = iPos(4);
% 
%         if W > H
%             panelGrid.RowHeight{1} = H;
%             panelGrid.ColumnWidth{1} = H-panelTop;
%         elseif H > W
%             panelGrid.ColumnWidth{1} = W;
%             panelGrid.RowHeight{1} = W+panelTop;
%         end
% 
%     end
% 
% end


