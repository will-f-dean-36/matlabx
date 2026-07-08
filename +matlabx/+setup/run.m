function run()
%RUN  Performs setup actions for a new installation of matlabx

matlabx.Log.INFO("Setting up matlabx...");

% --- SEARCH PATH ---
matlabx.Log.INFO("Setting up matlabx search path...");
try matlabx.setup.searchPath(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

% --- BIO-FORMATS ---
matlabx.Log.INFO("Setting up Bio-Formats...");
try matlabx.setup.bioFormats(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

% --- UI CALIBRATION ---
matlabx.Log.INFO("Setting up UI calibration...");
try matlabx.setup.uiCalibration(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

% save path
savepath();

% indicate success
matlabx.Log.INFO("matlabx setup completed successfully.");

end