function axes2image(ax,filename,opts)
%AXES2IMAGE  Export axes content to image
    arguments
        ax                          (1,1) matlab.ui.control.UIAxes
        filename                    (1,:) char
        opts.Units                  (1,:) char = 'inches'
        opts.Width                  (1,1) double = 3
        opts.Height                 (1,1) double = 3
        opts.BackgroundColor        (1,3) double = [0 0 0]
        opts.PreserveAspectRatio    (1,:) char = 'on'
        opts.Resolution             (1,1) double = 600
        opts.HideToolbar            (1,1) logical = true
    end

    toolbarVisible = ax.Toolbar.Visible; % store toolbar Visibility state
    if opts.HideToolbar
        ax.Toolbar.Visible = 'off'; % hide the toolbar if specified
    end

    % export axes content as an image
    exportgraphics(ax,filename, ...
        "ContentType","image", ...
        "Units",opts.Units, ...
        "Width",opts.Width, ...
        "Colorspace","rgb", ...
        "Padding",0, ...
        "PreserveAspectRatio",opts.PreserveAspectRatio, ...
        "BackgroundColor",opts.BackgroundColor, ...
        "Resolution",opts.Resolution);

    
    ax.Toolbar.Visible = toolbarVisible; % restore the toolbar visibility

end