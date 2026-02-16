function IOut = fillEdgeOpenHoles(I,opts)
    arguments
        I (:,:) logical
        opts.ShowResults (1,1) logical = false
    end

    % start with a normal fill
    I1 = imfill(I,"holes");

    % invert the image
    I2 = ~I1;

    % fill again
    I3 = imfill(I2, "holes");

    % remove connected components in I3 touching 3 or more borders
    I4 = imtools.removeBorderTouchers(I3,3);

    % final mask is the logical OR of I1 and I4
    IOut = I1 | I4; % Combine the filled images
    
    % display results if requested
    if opts.ShowResults
        quickshow({I,I1,I2,I3,I4,IOut});
    end

end