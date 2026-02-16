function RGB = mergeChannelsRGB_LUT(Icell, clim, cmaps)
%MERGECHANNELSRGB_ADDLUT  Additively merge grayscale channels using per-channel colormaps.
%
%   RGB = MERGECHANNELSRGB_ADDLUT(Icell, clim, cmaps) normalizes each
%   grayscale image using its display limits (CLIM), maps the normalized
%   values into the corresponding 256x3 colormap in CMAPS, then additively
%   sums the resulting RGB layers and clamps the result to [0,1].
%
%   Inputs
%     Icell : 1xN cell array of grayscale images (all same size/type)
%     clim  : Nx2 array of [low high] display limits per channel
%     cmaps : 1xN cell array of 256x3 colormaps (double/single in [0,1])
%             First row maps to clim(:,1), last row maps to clim(:,2).
%
%   Output
%     RGB   : MxNx3 double image in [0,1]
%
%   Example
%     RGB = mergeChannelsRGB_addLUT({ch1,ch2}, [100 800; 50 400], {hot(256), cool(256)});
%
%   See also VECIND2RGB, IM2UINT8, RESCALELINEAR, COLORMAP

    N = numel(Icell);
    assert(size(clim,1) == N && size(clim,2) == 2, 'clim must be Nx2.');
    assert(iscell(cmaps) && numel(cmaps) == N, 'cmaps must be a 1xN cell array.');

    % preallocate output RGB
    RGB = zeros([size(Icell{1}) 3], 'double');

    for k = 1:N
        cmap = cmaps{k};
        assert(ismatrix(cmap) && size(cmap,1) == 256 && size(cmap,2) == 3, ...
            'Each colormap must be 256x3.');

        % normalize to [0,1] using clim, convert to uint8, 
        % convert to RGB using LUT (cmap), add to cumulative result
        RGB = RGB + guitools.utils.vecind2rgb(im2uint8(guitools.utils.rescaleLinear(Icell{k},clim(k,:))),cmap);
    end

    RGB = min(RGB, 1);
end