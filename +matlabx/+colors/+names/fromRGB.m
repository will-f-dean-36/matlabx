function name = fromRGB(rgb)
%FROMRGB  Converts an RGB triplet to a color name
%
%   name = FROMRGB(rgb) returns the color name corresponding 
%   to the specified 1x3 RGB vector (values in [0,1]).
%
%   Supported colors:
%     'red', 'green', 'blue', 'cyan', 'magenta', 'yellow', 'white', 'black'
%
%   Input
%     rgb  : 1x3 RGB triplet in [0,1]
%
%   Output
%     name : character vector or string scalar specifying the color name
%
%   Example
%     rgb = fromRGB([1 0 1]);   % returns "magenta"
%
%   See also COLORGRADIENT, TORGB

    rgb = double(rgb);

    if isequal(rgb, [1 0 0])
        name = "red";
    elseif isequal(rgb, [0 1 0])
        name = "green";
    elseif isequal(rgb, [0 0 1])
        name = "blue";
    elseif isequal(rgb, [0 1 1])
        name = "cyan";
    elseif isequal(rgb, [1 0 1])
        name = "magenta";
    elseif isequal(rgb, [1 1 0])
        name = "yellow";
    elseif isequal(rgb, [1 1 1])
        name = "white";
    elseif isequal(rgb, [0 0 0])
        name = "black";
    else
        error('matlabx:colors:names:fromRGB:UnknownRGBTriplet', ...
            'Unknown RGB triplet %s. Supported colors: red, green, blue, cyan, magenta, yellow, white, black.', mat2str(rgb));
    end

end