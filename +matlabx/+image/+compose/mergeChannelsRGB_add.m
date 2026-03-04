function RGB = mergeChannelsRGB_add(Icell, clim, colors)
%MERGECHANNELSRGB_ADD  Additive merge of grayscale channels into RGB using distinct colors per channel.

    N = numel(Icell);
    assert(size(clim,1) == N && size(clim,2) == 2, 'clim must be Nx2.');

    if nargin < 3 || isempty(colors)
        base = [1 0 0; 0 1 0; 0 0 1; 1 0 1];  % R,G,B,M
        colors = base(1:N, :);
    end
    assert(size(colors,1) == N && size(colors,2) == 3, 'colors must be Nx3.');

    sz = size(Icell{1});
    RGB = zeros([sz 3], 'double');

    for k = 1:N
        Ik = double(Icell{k});
        lo = clim(k,1); hi = clim(k,2);
        denom = hi - lo;

        if denom <= 0
            a = zeros(sz, 'double');
        else
            a = (Ik - lo) ./ denom;
            a = min(max(a, 0), 1);
        end

        RGB(:,:,1) = RGB(:,:,1) + a * colors(k,1);
        RGB(:,:,2) = RGB(:,:,2) + a * colors(k,2);
        RGB(:,:,3) = RGB(:,:,3) + a * colors(k,3);
    end

    RGB = min(RGB, 1);
end