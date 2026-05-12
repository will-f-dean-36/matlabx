function mask = growSeedMask(I, bw, opts)
%GROWSEEDMASK Expand seed regions through pixels above threshold.
%
% mask = growSeedMask(I, bw)
% mask = growSeedMask(I, bw, Threshold=10)
%
% Inputs
%   I   - grayscale image
%   bw  - logical seed mask, same size as I
%
% Name-Value
%   Threshold - minimum pixel value to include, default 0
%
% Output
%   mask - logical mask containing all pixels connected to bw where I > Threshold

    arguments
        I (:,:) {mustBeNumeric}
        bw (:,:) logical
        opts.Threshold double = []
    end

    if ~isequal(size(I), size(bw))
        error("growSeedMask:SizeMismatch", ...
            "I and bw must have the same size.");
    end

    if isempty(opts.Threshold)
        thresh = graythresh(I);
        classRange = getrangefromclass(I);
        opts.Threshold = max(thresh * classRange(2), 0);
    end

    candidateMask = I > opts.Threshold;

    % Keep only candidate pixels connected to the seed mask.
    mask = imreconstruct(bw, candidateMask) > 0;
end