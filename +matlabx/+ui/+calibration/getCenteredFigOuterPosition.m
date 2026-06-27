function pos = getCenteredFigOuterPosition(W,H)
%GETCENTEREDFIGOUTERPOSITION Returns the OuterPosition of a WxH figure positioned at screen center
screenCenter = matlabx.ui.calibration.getScreenCenter();
pos = [screenCenter(1) - W/2, screenCenter(2) - H/2, W, H];
end