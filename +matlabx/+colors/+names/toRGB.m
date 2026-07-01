function rgb = toRGB(name, options)
%TORGB  Converts a color name to an RGB triplet
%
%   rgb = TORGB(name) returns the RGB triplet associated with the specified
%   color name in the CSS color palette. Color-name matching is
%   case-insensitive.
%
%   rgb = TORGB(name, Palette=palette) specifies the color-name palette
%   used for lookup. The default palette is "CSS".
%
%   Input
%     name      : Character vector or string scalar specifying a color name
%
%   Name-Value Input
%     Palette   : String scalar specifying a palette supported by
%                 COLORNAMES. The default is "CSS".
%
%   Output
%     rgb       : 1x3 RGB triplet with values in [0,1]
%
%   Example
%     rgb = toRGB("magenta")
%
%     rgb = toRGB("cyan", Palette="MATLAB")
%
%   See also COLORNAMES, FROMRGB

    arguments
        name (1,1) string
        options.Palette (1,1) string = "CSS"
    end

    try
        [~, rgb] = colornames(options.Palette, name);
    catch ME
        cause = MException( ...
            "matlabx:colors:names:toRGB:ColorLookupFailed", ...
            'Unable to find color name "%s" in the "%s" palette.', ...
            name, options.Palette);

        cause = addCause(cause, ME);
        throwAsCaller(cause);
    end

end