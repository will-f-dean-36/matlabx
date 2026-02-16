function rgb = getColor(name)
%GETCOLOR  Converts a color name to an RGB triplet
%
%   rgb = GETCOLOR(name) returns the 1x3 RGB vector (values in [0,1])
%   corresponding to the specified color name. The lookup is case-
%   insensitive.
%
%   Supported colors:
%     'red', 'green', 'blue', 'cyan', 'magenta', 'yellow', 'white', 'black'
%
%   Input
%     name : character vector or string scalar specifying the color name
%
%   Output
%     rgb  : 1x3 RGB triplet in [0,1]
%
%   Example
%     rgb = colorName('magenta');   % returns [1 0 1]
%
%   See also COLORGRADIENT

    name = lower(string(name));

    switch name
        case "red"
            rgb = [1 0 0];
        case "green"
            rgb = [0 1 0];
        case "blue"
            rgb = [0 0 1];
        case "cyan"
            rgb = [0 1 1];
        case "magenta"
            rgb = [1 0 1];
        case "yellow"
            rgb = [1 1 0];
        case "white"
            rgb = [1 1 1];
        case "black"
            rgb = [0 0 0];
        otherwise
            error('getColor:UnknownColor', ...
                  'Unknown color "%s". Supported colors: red, green, blue, cyan, magenta, yellow, white, black.', name);
    end
end