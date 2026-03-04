function Iout = robustClipRescale(I, pHigh)
%%ROBUSTCLIPRESCALE  Clip extreme highs then rescale to [0,1]
% pHigh: e.g. 99.9, 99.95, 99.99

    if nargin < 2 || isempty(pHigh), pHigh = 99.95; end

    I = im2single(I);
    hi = prctile(I(:), pHigh);

    Iclip = min(I, hi);
    Iout = rescale(Iclip);
end