function snapAndRefresh(roi, ds)
%%SNAPANDREFRESH  Adjusts the Position of an images.roi.Rectangle such that width and height are multiples of ds

    % Current geometry
    pos   = roi.Position;               % [x y w h] in *unrotated* frame

    % Center is invariant for rotation
    cx = pos(1) + pos(3)/2;
    cy = pos(2) + pos(4)/2;

    % Snap width/height to multiples of ds
    wEff = max(ds, round(pos(3)/ds) * ds);
    hEff = max(ds, round(pos(4)/ds) * ds);

    % Rebuild Position as the axis-aligned box around the same center
    newPos = [cx - wEff/2, cy - hEff/2, wEff, hEff];

    % Update Position
    roi.Position      = newPos;

end