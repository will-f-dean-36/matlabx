function snapRectangleROISize(roi, ds)
%snapRectangleROISize Snap roi width/height to multiples of ds (typically 1 px).

    p = roi.Position; % [x y w h]
    w0 = p(3); h0 = p(4);

    w1 = max(ds, round(w0/ds)*ds);
    h1 = max(ds, round(h0/ds)*ds);

    if w1 ~= w0 || h1 ~= h0
        p(3) = w1;
        p(4) = h1;
        roi.Position = p;
    end
end