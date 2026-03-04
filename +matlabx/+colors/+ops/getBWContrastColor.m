function colorOut = getBWContrastColor(colorIn)
%%GETBWCONTRASTCOLOR  Given an RGB triplet, determine whether it contrasts more with black or white

    if mean(colorIn,"all") < 0.5 % dark color
        colorOut = [1 1 1]; % return white
    else % bright color
        colorOut = [0 0 0]; % return black
    end
    
end