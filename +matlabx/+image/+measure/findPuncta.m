function [points,mask] = findPuncta(I,opts)
    arguments
        % image to process
        I (:,:)
        % radius of disk-shaped structuring element
        opts.DiskRadius (1,1) double = 1
        % whether to display output plots
        opts.ShowPlots (1,1) logical = false
    end

    % --- normalize input ---
    if ~isa(I, "double")
        I = im2double(I);
    end
    I = rescale(I);

    sz = size(I);

    % --- locate puncta ---

    % perform open-close by reconstruction
    SE = strel('disk',opts.DiskRadius,0);
    I_ocbr = matlabx.image.process.openCloseByReconstruct(I,SE);

    % find regional maxima
    I_reg_max = imregionalmax(I_ocbr,8);

    % extract centroids of regional maxima mask
    CC = bwconncomp(I_reg_max);
    props = regionprops(CC, I_reg_max, 'Centroid');
    points = cat(1, props.Centroid);


    % --- make puncta seed mask --- 

    % preallocate mask
    mask = false(sz);
    % convert points to linear px idxs
    idx = sub2ind(sz, round(points(:,2)), round(points(:,1)));
    % add to mask
    mask(idx) = true;


    % --- show plots ---

    if opts.ShowPlots
        ax = matlabx.app.quickshow(I,turbo);
        hAx = ax.getAxes();
        % Plot centroids on the original image if requested
        hold(hAx, 'on');
        plot(hAx, points(:,1), points(:,2), ...
            'MarkerSize', 10, ...
            'Marker', 'x', ...
            'Color', [1 1 1], ...
            'LineStyle', 'none', ...
            'LineWidth', 1);
        hold(hAx, 'off');

        matlabx.app.quickshow(I_ocbr,turbo);
    end

end