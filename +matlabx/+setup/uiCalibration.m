function uiCalibration()
%UICALIBRATION  Performs UI calibration needed for matlabx and stores results

% run UI calibration
cal = matlabx.ui.calibration.UICalibration();
cal.calibrate();
    
% store UI calibration results in MachineState file
matlabx.config.MachineState.set('UICalibration', cal.toStruct());

end