function cal = getCalibration(opts)

    arguments
        opts.ForceRecalibrate   (1,1) logical = false
        opts.uipanel            (1,1) logical = true
        opts.uifigure           (1,1) logical = true
    end
    
    persistent cachedCal
    
    if ~opts.ForceRecalibrate && ~isempty(cachedCal)
        cal = cachedCal;
        return
    end
    
    cached = matlabx.config.MachineState.get('UICalibration', []);
    
    if ~opts.ForceRecalibrate && ~isempty(cached) ...
            && matlabx.ui.calibration.UICalibration.isStructValid(cached)
    
        cal = matlabx.ui.calibration.UICalibration.fromStruct(cached);
        cachedCal = cal;
        return
    end
    
    cal = matlabx.ui.calibration.UICalibration();
    cal.calibrate( ...
        uipanel=opts.uipanel, ...
        uifigure=opts.uifigure ...
        );
    
    matlabx.config.MachineState.set('UICalibration', cal.toStruct());
    cachedCal = cal;
    
end