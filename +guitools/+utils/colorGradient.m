function RGB = colorGradient(C1,C2,N)
%COLORGRADIENT  Create a linear RGB gradient between two colors
%
%   RGB = COLORGRADIENT(C1, C2, N) returns an Nx3 array of RGB values that
%   linearly interpolate from color C1 to color C2. Each row of RGB is a
%   color in the gradient, with the first row equal to C1 and the last
%   equal to C2.
%
%   Inputs
%     C1 : 1x3 RGB vector specifying the start color (values in [0,1])
%     C2 : 1x3 RGB vector specifying the end color   (values in [0,1])
%     N  : number of colors to generate
%
%   Output
%     RGB : Nx3 array of RGB values forming the gradient
%
%   Example
%     % Create a red-to-blue colormap with 256 entries
%     cmap = colorGradient([1 0 0], [0 0 1], 256);
%     colormap(cmap)
%
%   See also LINSPACE, COLORMAP

    R = linspace(C1(1),C2(1),N);
    G = linspace(C1(2),C2(2),N);
    B = linspace(C1(3),C2(3),N);
    RGB = [R', G', B'];
end