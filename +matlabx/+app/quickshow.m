function [ax,fig] = quickshow(I,opts)
    arguments
        I
        opts.Colormap (256,3) double
        opts.Title (1,:) char = 'Viewer'
        opts.Tools (1,:) cell {mustBeMember(opts.Tools,{'Zoom','Colorbar','ChooseColormap','Box','DrawRectangle'})} ...
            = matlabx.ui.axes.ImageAxes.getDefaultTools()
        opts.WindowStyle (1,:) char {mustBeMember(opts.WindowStyle,{'normal','alwaysontop'})} = 'alwaysontop'
        opts.Visible (1,1) matlab.lang.OnOffSwitchState = "on"
        opts.Size (1,1) double = 500
        opts.Units (1,:) char = 'pixels'
        opts.Location (1,:) char {mustBeMember(opts.Location,...
            {'center','north','south','east','west','northeast','northwest','southeast','southwest'})} = 'center'
        opts.ComponentColorMode (1,:) char {mustBeMember(opts.ComponentColorMode,{'luts','colors'})} = 'luts'
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

    % convert size to pixels
    switch opts.Units
        case "inches"
            opts.Size = opts.Size * matlabx.UICal.pixelsPerInch();
        case "points"
            opts.Size = opts.Size * matlabx.UICal.pixelsPerPoint();
    end
    

    fig = uifigure(...
        "WindowStyle",          opts.WindowStyle,...
        "Position",             [0 0 opts.Size opts.Size],...
        "Units",                "pixels",...
        "Visible",              "off",...
        "AutoResizeChildren",   "off",...
        "Name",                 opts.Title);

    if isa(I,"matlabx.image.Image5D")
        ax = matlabx.ui.axes.ImageAxes(fig,...
            "Tools",             opts.Tools,...
            "ImageData",            I,...
            "ComponentColorMode",   opts.ComponentColorMode,...
            "Units",                "normalized",...
            "Position",             [0 0 1 1],...
            "Name",                 opts.Title);
    else
        ax = matlabx.ui.axes.ImageAxes(fig,...
            "Tools",             opts.Tools,...
            "CData",                I,...
            "ComponentColorMode",   opts.ComponentColorMode,...
            "Units",                "normalized",...
            "Position",             [0 0 1 1],...
            "Colormap",             opts.Colormap,...
            "Name",                 opts.Title);
    end

    panelTopChromePx = matlabx.UICal.panelChromeHeight(ax.FontSize,"FontUnits","pixels");
    fig.Position(4) = fig.Position(3) + panelTopChromePx;


    movegui(fig,opts.Location)

    drawnow

    fig.Visible = opts.Visible;

end
