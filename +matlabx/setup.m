function setup()
%SETUP Performs setup actions for a new installation of matlabx

% add necessary folders to search path
matlabx.internal.setupSearchPath();

% run UI calibration
cal = matlabx.ui.calibration.UICalibration();
cal.calibrate();
    
% store UI calibration results in MachineState file
matlabx.config.MachineState.set('UICalibration', cal.toStruct());




end