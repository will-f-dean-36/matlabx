function Iout = suppressHotPuncta(I, PercentileThreshold, DilateRadius)
%SUPPRESSHOTPUNCTA Mask extreme bright puncta and replace locally.
% PercentileThreshold: percentile defining "hot" (e.g. 99.95)
% DilateRadius: in pixels (e.g. 2 to 4)

    arguments
        I
        PercentileThreshold = 99.99
        DilateRadius = 3
    end

    % convert to double
    I = im2double(I);

    % find pixels above specified threshold
    hi = prctile(I(:), PercentileThreshold);
    mask = I >= hi;

    % opening to remove very small objects
    mask = imopen(mask,strel('disk',1,0));

    % Dilate to cover the full bright blob
    se = strel('disk', DilateRadius, 0);
    mask = imdilate(mask, se);

    % fill regions specified by mask
    Iout = inpaintCoherent(I,mask,...
        "SmoothingFactor",2,...
        "Radius",3);

    % create mask of dilated border around each region
    borderMask = imdilate(mask,strel('disk',1,0)) & ~imerode(mask,strel('disk',1,0));

    % median filter to smooth border
    Imed = medfilt2(Iout,[3 3]);

    % fill the border pixels
    Iout(borderMask) = Imed(borderMask);

    % rescale output
    Iout = rescale(Iout);

end