function [ax,fig] = quickshow(I,opts)
%QUICKSHOW  Shortcut for matlabx.app.quickshow
%
%   See also MATLABX.APP.QUICKSHOW

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
    end

    keyValueCell = matlabx.struct.toKeyValueCell(opts);
    [ax,fig] = matlabx.app.quickshow(I,keyValueCell{:});

end