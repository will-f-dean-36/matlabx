classdef ImageAxesResizeLayout
%IMAGEAXESRESIZELAYOUT Aspect-fit sizing helper for ImageAxes.
%
%   ImageAxes displays image content inside a titled uipanel. The panel title
%   area consumes a calibrated number of pixels at the top, so the actual image
%   area is smaller than the component height. This helper computes the 3-by-3
%   sizing grid used to center the panel and preserve the source image aspect
%   ratio.
%
%   The important policy here is integer layout. MATLAB UI containers ultimately
%   realize sizes on screen pixels, so this class rounds the target panel size
%   and then splits any leftover padding between the two sides. Some component
%   sizes cannot represent the image aspect ratio perfectly; diagnostic fields
%   expose the resulting sub-pixel/integer roundoff.
%
%   ImageAxes remains responsible for deciding when a resize should happen and
%   for remembering the last layout key. This class only computes, applies, and
%   explains a layout.

    methods (Static)
        function S = compute(component, imageHeightPx, imageWidthPx, panelTopChromePx)
        %COMPUTE Return integer layout values for the current component size.

            % getpixelposition avoids temporarily changing ImageAxes.Units. Width
            % and height are enough for layout; absolute position is diagnostic-only.
            compPos = getpixelposition(component);

            % Work in nonnegative integer pixels. The image dimensions should already
            % be integer, but rounding keeps this function robust to caller input.
            componentW = max(0, round(compPos(3)));
            componentH = max(0, round(compPos(4)));
            panelTop = max(0, round(panelTopChromePx));
            imgH = max(0, round(imageHeightPx));
            imgW = max(0, round(imageWidthPx));

            % The struct doubles as the normal layout payload and diagnostic record.
            % Initialize all fields so invalid layouts are still printable.
            S = struct( ...
                'IsValid', false, ...
                'ComponentPositionPx', compPos, ...
                'ComponentWidthPx', componentW, ...
                'ComponentHeightPx', componentH, ...
                'PanelTopChromePx', panelTop, ...
                'AvailableImageHeightPx', componentH - panelTop, ...
                'ImageWidthPx', imgW, ...
                'ImageHeightPx', imgH, ...
                'ImageAspectRatioHW', NaN, ...
                'AvailableAspectRatioHW', NaN, ...
                'FitLimitedBy', "", ...
                'IdealPanelWidthPx', NaN, ...
                'IdealPanelImageAreaHeightPx', NaN, ...
                'PanelWidthPx', NaN, ...
                'PanelHeightPx', NaN, ...
                'PanelImageAreaHeightPx', NaN, ...
                'PanelWidthRoundoffPx', NaN, ...
                'PanelImageAreaHeightRoundoffPx', NaN, ...
                'PanelImageAspectRatioHW', NaN, ...
                'PanelImageAspectRatioError', NaN, ...
                'LeftPadPx', NaN, ...
                'RightPadPx', NaN, ...
                'TopPadPx', NaN, ...
                'BottomPadPx', NaN, ...
                'HorizontalPadSymmetric', false, ...
                'VerticalPadSymmetric', false, ...
                'LayoutKey', [componentW, componentH, imgW, imgH, panelTop]);

            % Invalid or not-yet-realized UI sizes are common during construction.
            % Return IsValid=false so callers can simply skip applying the layout.
            if componentW <= 0 || componentH <= panelTop || imgH <= 0 || imgW <= 0
                return
            end

            % Aspect ratios are expressed as height/width because MATLAB image data
            % size is naturally [rows columns] == [height width].
            imageAreaH = componentH - panelTop;
            targetRatio = imgH / imgW;
            currentRatio = imageAreaH / componentW;

            % If the available area is taller than the image, width limits the fit;
            % otherwise height limits the fit. The limiting dimension remains exact
            % and the other dimension is rounded to the nearest screen pixel.
            if currentRatio > targetRatio
                fitLimitedBy = "width";
                panelW = componentW;
                idealPanelW = componentW;
                idealImageH = componentW * targetRatio;
                imageH = round(idealImageH);
            else
                fitLimitedBy = "height";
                imageH = imageAreaH;
                idealImageH = imageAreaH;
                idealPanelW = imageAreaH / targetRatio;
                panelW = round(idealPanelW);
            end

            % Clamp after rounding so pathological tiny component sizes never produce
            % a panel outside the component bounds.
            panelW = min(componentW, max(1, panelW));
            panelH = min(componentH, max(1, imageH) + panelTop);

            % Split leftover pixels explicitly. When there is an odd leftover pixel,
            % the right/bottom side gets the extra pixel; this avoids fractional grid
            % tracks and prevents one-sided drift over repeated resizes.
            leftPad = floor((componentW - panelW)/2);
            rightPad = componentW - panelW - leftPad;
            topPad = floor((componentH - panelH)/2);
            bottomPad = componentH - panelH - topPad;

            S.IsValid = true;
            S.ImageAspectRatioHW = targetRatio;
            S.AvailableAspectRatioHW = currentRatio;
            S.FitLimitedBy = fitLimitedBy;
            S.IdealPanelWidthPx = idealPanelW;
            S.IdealPanelImageAreaHeightPx = idealImageH;
            S.PanelWidthPx = panelW;
            S.PanelHeightPx = panelH;
            S.PanelImageAreaHeightPx = panelH - panelTop;
            S.PanelWidthRoundoffPx = S.PanelWidthPx - S.IdealPanelWidthPx;
            S.PanelImageAreaHeightRoundoffPx = ...
                S.PanelImageAreaHeightPx - S.IdealPanelImageAreaHeightPx;
            S.PanelImageAspectRatioHW = S.PanelImageAreaHeightPx / S.PanelWidthPx;
            S.PanelImageAspectRatioError = S.PanelImageAspectRatioHW - S.ImageAspectRatioHW;
            S.LeftPadPx = leftPad;
            S.RightPadPx = rightPad;
            S.TopPadPx = topPad;
            S.BottomPadPx = bottomPad;
            S.HorizontalPadSymmetric = leftPad == rightPad;
            S.VerticalPadSymmetric = topPad == bottomPad;
        end

        function apply(sizingGrid, S)
        %APPLY Set the sizing grid from a valid resize-layout struct.

            % The center cell contains the uipanel. Surrounding tracks are padding.
            set(sizingGrid, ...
                'ColumnWidth',{S.LeftPadPx,S.PanelWidthPx,S.RightPadPx}, ...
                'RowHeight',{S.TopPadPx,S.PanelHeightPx,S.BottomPadPx});
        end

        function S = addDiagnostics(S, component, grid, sizingGrid, panel, mainAxes, staticAxes, opts)
        %ADDDIAGNOSTICS Add realized UI geometry fields to a layout struct.
        %
        %   "Calculated" fields come from compute(). "Actual" fields come from
        %   MATLAB after layout has been realized. Comparing them helps distinguish
        %   layout math issues from UIAxes/uipanel rendering behavior.

            arguments
                S struct
                component
                grid
                sizingGrid
                panel
                mainAxes
                staticAxes
                opts.LastResizeLayoutKey (1,5) double = NaN(1,5)
                opts.PendingSizeUpdate (1,1) logical = false
            end

            % Absolute positions help diagnose parent/layout-manager quirks. They are
            % intentionally excluded from compute() to keep resize work lean.
            S.ComponentAbsolutePositionPx = getpixelposition(component,true);
            S.LastResizeLayoutKey = opts.LastResizeLayoutKey;
            S.PendingSizeUpdate = opts.PendingSizeUpdate;

            % Local and absolute positions are both useful when ImageAxes is nested
            % inside app layouts. Width/height deltas should agree; origins may not.
            S.GridPositionPx = getpixelposition(grid);
            S.GridAbsolutePositionPx = getpixelposition(grid,true);
            S.SizingGridPositionPx = getpixelposition(sizingGrid);
            S.SizingGridAbsolutePositionPx = getpixelposition(sizingGrid,true);
            S.PanelOuterPositionPx = getpixelposition(panel);
            S.PanelAbsoluteOuterPositionPx = getpixelposition(panel,true);
            S.PanelInnerPositionPx = panel.InnerPosition;
            S.MainAxesOuterPositionPx = getpixelposition(mainAxes);
            S.MainAxesAbsoluteOuterPositionPx = getpixelposition(mainAxes,true);
            S.MainAxesInnerPositionPx = mainAxes.InnerPosition;
            S.StaticAxesOuterPositionPx = getpixelposition(staticAxes);
            S.StaticAxesAbsoluteOuterPositionPx = getpixelposition(staticAxes,true);
            S.StaticAxesInnerPositionPx = staticAxes.InnerPosition;

            S.SizingGridColumnWidth = sizingGrid.ColumnWidth;
            S.SizingGridRowHeight = sizingGrid.RowHeight;
            S.PanelFontSize = panel.FontSize;
            S.PanelFontUnits = panel.FontUnits;
            S.PanelTitle = string(panel.Title);

            % Delta fields compare realized UI sizes against the requested layout.
            % Nonzero values here point to MATLAB container/axes realization rather
            % than the aspect-fit arithmetic.
            S.ActualPanelImageAreaHeightPx = S.PanelOuterPositionPx(4) - S.PanelTopChromePx;
            S.ActualPanelWidthDeltaPx = S.PanelOuterPositionPx(3) - S.PanelWidthPx;
            S.ActualPanelHeightDeltaPx = S.PanelOuterPositionPx(4) - S.PanelHeightPx;
            S.ActualPanelImageAreaHeightDeltaPx = ...
                S.ActualPanelImageAreaHeightPx - S.PanelImageAreaHeightPx;
            S.ActualInnerVsCalculatedImageWidthDeltaPx = ...
                S.PanelInnerPositionPx(3) - S.PanelWidthPx;
            S.ActualInnerVsCalculatedImageHeightDeltaPx = ...
                S.PanelInnerPositionPx(4) - S.PanelImageAreaHeightPx;
            S.ActualMainAxesVsImageWidthDeltaPx = ...
                S.MainAxesOuterPositionPx(3) - S.PanelWidthPx;
            S.ActualMainAxesVsImageHeightDeltaPx = ...
                S.MainAxesOuterPositionPx(4) - S.PanelImageAreaHeightPx;
        end
    end

end
