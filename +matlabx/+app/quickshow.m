function [ax,fig] = quickshow(I,opts)
    arguments
        I
        opts.Colormap (256,3) double
        opts.Title (1,:) char = 'Viewer'
        opts.Tools (1,:) cell {mustBeMember(opts.Tools,{'Zoom','Colorbar','ChooseColormap','Pick','DrawRectangle'})} ...
            = matlabx.ui.widgets.ImageAxes.getDefaultTools()
        opts.WindowStyle (1,:) char {mustBeMember(opts.WindowStyle,{'normal','alwaysontop'})} = 'alwaysontop'
        opts.Visible (1,1) matlab.lang.OnOffSwitchState = "on"
        opts.Size (1,1) double = 500
        opts.Units (1,:) char = 'pixels'
        opts.Location (1,:) char {mustBeMember(opts.Location,...
            {'center','north','south','east','west','northeast','northwest','southeast','southwest'})} = 'center'
    end

    if ~isfield(opts,'Colormap') || isempty(opts.Colormap)
        opts.Colormap = gray(256);
    end

    if isnan(opts.Size) && isempty(opts.Units)
        opts.Size = 500;
        opts.Units = 'pixels';
    elseif isnan(opts.Size) || isempty(opts.Units)
        error('matlabx:app:quickshow:InvalidSizeOrUnits',...
            'To set figure Size or Units, you must provide both as input arguments');
    end

    % get ui calibration helper
    cal = matlabx.ui.calibration.getCalibration();

    % convert size to pixels
    switch opts.Units
        case "inches"
            opts.Size = opts.Size * cal.PixelsPerInch;
        case "points"
            opts.Size = opts.Size * cal.PixelsPerPoint;
    end
    

    fig = uifigure(...
        "WindowStyle",          opts.WindowStyle,...
        "Position",             [0 0 opts.Size opts.Size],...
        "Units",                "pixels",...
        "Visible",              "off",...
        "AutoResizeChildren",   "off",...
        "Name",                 opts.Title);

    if isa(I,"matlabx.image.Image5D")
        ax = matlabx.ui.widgets.ImageAxes(fig,...
            "ToolBelt",     opts.Tools,...
            "ImageData",    I,...
            "Units",        "normalized",...
            "Position",     [0 0 1 1],...
            "Name",         opts.Title);
    else
        ax = matlabx.ui.widgets.ImageAxes(fig,...
            "ToolBelt",     opts.Tools,...
            "CData",        I,...
            "Units",        "normalized",...
            "Position",     [0 0 1 1],...
            "Colormap",     opts.Colormap,...
            "Name",         opts.Title);
    end

    % cal = matlabx.ui.calibration.getCalibration();
    panelTopChromePx = cal.uipanelTopChromeHeightPx(ax.FontSize,"FontUnits","pixels");
    fig.Position(4) = fig.Position(3) + panelTopChromePx;


    movegui(fig,opts.Location)

    fig.Visible = opts.Visible;

end