function Iscaled = rescaleLinear(I, inRange)
%RESCALELINEAR  Linearly rescale values in I such that inRange maps to [0 1]
%   Maps values in I from inRange = [inLow inHigh] to [0 1] 
%   using linear scaling. Values outside inRange are clipped to [0 1]
%
%   SYNTAX:
%       Iscaled = utils.rescaleLinear(I, inRange)
%
%   INPUTS:
%       I        - numeric array (any shape)
%       inRange  - [low high] in input units
%
%   OUTPUT:
%       Iscaled  - double array, same size as I
%
%   See also: clip

    Iscaled = clip((double(I) - inRange(1)) / (inRange(2) - inRange(1)), 0, 1);
    
end