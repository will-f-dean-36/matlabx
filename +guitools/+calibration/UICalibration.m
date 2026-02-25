classdef UICalibration < handle
%UICalibration  Small per-machine UI calibration cache for App Designer / uifigure UIs.
%
% Typical use:
%   UIcal = guitools.calibration.UICalibration();
%   UIcal.calibrate();  % call once on startup (after UI created is fine)
%
% Query:
%   dH = UIcal.uipanelTitleBarHeightPx(14); % innerW - innerH for a square, titled uipanel
%   px = UIcal.pt2px(12);
%   pt = UIcal.px2pt(16);
%
% Notes:
%   In active development, plan to add more calibrations

    properties (SetAccess=private)
        % Core display scaling
        PixelsPerInch (1,1) double = NaN
        PixelsPerPoint  (1,1) double = NaN  % PPI/72

        % Panel title/border overhead model:
        %   overheadPx ~= A * (FontSizePt * PixelsPerPoint) + B
        PanelOverheadA (1,1) double = NaN
        PanelOverheadB (1,1) double = NaN

        % Metadata / debug
        Timestamp datetime = datetime.empty
        Notes (1,:) char = ''

        % status flags
        uipanelCalibrated (1,1) logical = false
    end

    properties (SetAccess=private)

        Log (1,1) guitools.Logger

    end

    %% Constructor
    methods

        function obj = UICalibration(opts)
            arguments
                opts.uipanel (1,1) logical = true
            end

            % save timestamp
            obj.Timestamp = datetime('now');

            % set up logger
            obj.Log = guitools.Logger;

            obj.Log.info("Calibration starting...","Source","UICalibration");

            % set up conversion factors
            obj.PixelsPerInch = get(groot, 'ScreenPixelsPerInch');
            obj.PixelsPerPoint   = obj.PixelsPerInch / 72;

            if opts.uipanel
                obj.calibrate_uipanel();
            end

        end

    end

    %% Calibration methods and helpers
    methods
        function calibrate_uipanel(obj, opts)
            %CALIBRATE_UIPANEL Calibrate uipanel to estimate title bar height
            arguments
                obj (1,1) guitools.calibration.UICalibration
                opts.FontName (1,:) char = ''     % '' = default UI font
                opts.FontSizes (1,:) double = [10 12 14 16 18]  % pts
            end

            obj.Log.info("Calibrating uipanel...","Source","UICalibration");

            % Create a uifigure to measure platform-specific chrome
            f = uifigure('Position',[-500 100 200 200],'Visible','on');
            % cleanup upon function completion
            c = onCleanup(@() delete(f));

            % Create a test panel, measure overhead for several FontSizes
            n = numel(opts.FontSizes);
            x = zeros(n,1); % predictor: text height in px (approx)
            y = zeros(n,1); % response: overhead px (innerW - innerH)
            for i = 1:n
                fs = opts.FontSizes(i);

                p = uipanel(f, 'Title', 'Calibration', 'FontSize', fs, 'OuterPosition',[20 20 100 100]);
                if ~isempty(opts.FontName)
                    p.FontName = opts.FontName;
                end

                drawnow; % ensure InnerPosition is valid
                pause(2) % pause to draw

                % get offset caused by title bar
                y(i) = p.InnerPosition(3) - p.InnerPosition(4);
                x(i) = obj.pt2px(fs);   % pts -> px
                delete(p);
            end

            % Fit y = A*x + B. Use polyfit when n>=2.
            if n >= 2
                cfit = polyfit(x, y, 1);
                obj.PanelOverheadA = cfit(1);
                obj.PanelOverheadB = cfit(2);
            else
                % Fallback: assume overhead = x + constant padding
                obj.PanelOverheadA = 1;
                obj.PanelOverheadB = max(0, y(1) - x(1));
            end

            obj.uipanelCalibrated = true;
            obj.Log.info("Calibrated uipanel title bar height.","Source","UICalibration");
        end

        function px = pt2px(obj, pt)
            arguments
                obj (1,1) guitools.calibration.UICalibration
                pt (:,1) double
            end
            px = pt * obj.PixelsPerPoint;
        end

        function pt = px2pt(obj, px)
            arguments
                obj (1,1) guitools.calibration.UICalibration
                px (:,1) double
            end
            pt = px / obj.PixelsPerPoint;
        end

        function overheadPx = uipanelTitleBarHeightPx(obj, fontSizePt)
            %UIPANELTITLEBARHEIGHTPX Estimate height of uipanel title bar in px based on font size in pts
            arguments
                obj (1,1) guitools.calibration.UICalibration
                fontSizePt (1,1) double
            end
            % not calibrated -> do now
            if ~obj.uipanelCalibrated, obj.calibrate_uipanel(); end
            % convert FontSize from pts to px
            fontSizePx = obj.pt2px(fontSizePt);
            overheadPx = obj.PanelOverheadA * fontSizePx + obj.PanelOverheadB;
            % round to integer px
            overheadPx = round(overheadPx);
            % clamp to something sensible
            overheadPx = max(0, overheadPx);
        end

    end


end