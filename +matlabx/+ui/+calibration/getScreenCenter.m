function sc = getScreenCenter(units)
%GETSCREENCENTER Returns center (x,y) of usable area of screen in pixels

    arguments
        units (1,:) char {mustBeMember(units,{'pixels','inches','points'})} = 'pixels'
    end

    UIcal = matlabx.UICal.get();
    
    left = UIcal.uifigureMaximizedOuterPositionLeftPx;
    bottom = UIcal.uifigureMaximizedOuterPositionBottomPx;
    width = UIcal.uifigureMaximizedOuterPositionWidthPx;
    height = UIcal.uifigureMaximizedOuterPositionHeightPx;
    
    sc = [left + width/2, bottom + height/2];
    
    switch units
        case 'pixels'
            return
        case 'inches'
            sc = sc / UIcal.PixelsPerInch;
        case 'points'
            sc = sc / UIcal.PixelsPerPoint;
    end

end