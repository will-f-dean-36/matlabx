function scale = exportStyleScale(sourceInches,outputSize,units,resolution,preserveAspect)
%EXPORTSTYLESCALE Estimate the inverse render scale for physical styling.
    switch string(units)
        case "pixels"
            outputInches = outputSize ./ resolution;
        case "inches"
            outputInches = outputSize;
        case "centimeters"
            outputInches = outputSize ./ 2.54;
        case "points"
            outputInches = outputSize ./ 72;
        otherwise
            error('matlabx:ui:axes:InvalidExportUnits', ...
                'Unsupported export units "%s".',string(units));
    end
    ratios = outputInches ./ sourceInches;
    ratios = ratios(~isnan(outputSize)); % Omitted dimensions follow the source aspect.
    validateattributes(ratios,{'double'},{'nonempty','finite','positive'});
    if preserveAspect == "on"
        scale = 1 / min(ratios);
    else
        % Retain the existing ImageAxes estimate for stretched exports.
        scale = 1 / sqrt(prod(ratios));
    end
end
