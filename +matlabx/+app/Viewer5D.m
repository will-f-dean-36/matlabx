classdef Viewer5D < handle
% matlabx.app.Viewer5D - Image Visualizer App

    properties (Access=private,Transient,NonCopyable)
        % --- window and main grid ---
        Fig matlab.ui.Figure
        Grid matlab.ui.container.GridLayout
        % --- viewer ---
        Viewer matlabx.ui.widgets.ImageAxes
        % --- menubar UI handles ---
        MenubarUI struct
    end

    % Priavte UI helpers
    properties (Access=private)
        % status flag for SizeChangedFcn 
        isResizingFigure (1,1) logical = false
        % UI Calibration
        UICal matlabx.ui.calibration.UICalibration
        % hotkey management
        CommandRouter matlabx.ui.control.CommandRouter
    end

    % internal UI values
    properties (Access=private)
        uipanelTopChromePx_ = 19
        previousFigurePosition_ = []
    end

    %% Public properties

    % Image, UI, visualization options
    properties
        Image matlabx.image.Image5D
        Title (1,1) string = "Viewer"
        BackgroundColor (1,3) = [0 0 0]
    end

    properties (SetObservable,AbortSet)
        FontSize (1,1) double = 12
    end

    %% Public properties with private backing
    properties (Dependent,SetObservable,AbortSet)
        WindowStyle (1,:) char {mustBeMember(WindowStyle,{'normal','alwaysontop'})}
        WindowState (1,:) char {mustBeMember(WindowState,{'normal','maximized','minimized','fullscreen'})}
        WindowShape (1,:) char {mustBeMember(WindowShape,{'normal','tight','square'})}
    end

    properties (Access=private)
        WindowStyle_ (1,:) char {mustBeMember(WindowStyle_,{'normal','alwaysontop'})} = 'normal'
        WindowState_ (1,:) char {mustBeMember(WindowState_,{'normal','maximized','minimized','fullscreen'})} = 'normal'
        WindowShape_ (1,:) char {mustBeMember(WindowShape_,{'normal','tight','square'})} = 'normal'
    end



    %% Read-only properties
    properties (SetAccess=private)
        Tag (1,:) char = "Viewer5D";
    end

    %% listeners
    properties (Access=private)
        L event.listener
    end


    %% Constructor/Destructor/update
    methods

        function obj = Viewer5D(I,opts)
            arguments
                I matlabx.image.Image5D = matlabx.image.Image5D.empty()
                opts.Title (1,1) string = "Viewer"
                opts.FontSize (1,1) double = 12
                opts.BackgroundColor (1,3) double = [0 0 0]
                opts.WindowStyle (1,:) char {mustBeMember(opts.WindowStyle,{'normal','alwaysontop'})} = 'normal'
                opts.WindowState (1,:) char {mustBeMember(opts.WindowState,{'normal','maximized','minimized','fullscreen'})} = 'normal'
                opts.WindowShape (1,:) char {mustBeMember(opts.WindowShape,{'normal','tight','square'})} = 'square'
            end

            if isempty(I)
                I = matlabx.image.Image5D.fromComponents({imread("rice.png")});
            end

            % assign image data
            obj.Image = I;

            % assign property values
            obj.Title               = opts.Title;
            obj.FontSize            = opts.FontSize;
            obj.BackgroundColor     = opts.BackgroundColor;

            % assign private backings
            obj.WindowStyle_         = opts.WindowStyle;
            obj.WindowState_         = opts.WindowState;
            obj.WindowShape_         = opts.WindowShape;

            % --- Log ---
            % get or init the Log
            matlabx.Log.get();
            matlabx.Log.INFO("Starting Viewer5D...");

            % --- UICalibration ---
            matlabx.Log.INFO("Calibrating UI...");
            try obj.setupUICalibration(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

            % --- Build GUI ---
            matlabx.Log.INFO("Building GUI...");
            try obj.buildGUI(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

            % --- Initial UI sync ---
            matlabx.Log.INFO("Refreshing UI...");
            try obj.refreshUI(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

            % --- Show figure ---
            matlabx.Log.INFO("Opening...");
            obj.Fig.Visible = 'on';

            % attach listeners (only listening to FontSize for now)
            obj.L = addlistener(obj, 'FontSize', 'PostSet', @(~,~) obj.onFontSizeChanged());

            % initial UI sync
            obj.refreshWindowSize();

        end

        function delete(obj)
            % remove listeners first
            if ~isempty(obj.L), delete(obj.L(isvalid(obj.L))); end
            obj.L = event.listener.empty;
            % delete UI components
            if ~isempty(obj.Viewer) && isvalid(obj.Viewer), delete(obj.Viewer); end
            if ~isempty(obj.Grid)   && isvalid(obj.Grid), delete(obj.Grid); end
            if ~isempty(obj.Fig)    && isvalid(obj.Fig),  delete(obj.Fig);  end
        end

    end

    %% setup helpers
    methods (Access=protected)

        function setupUICalibration(obj)
            obj.UICal = matlabx.ui.calibration.getCalibration();
        end

        function buildGUI(obj)
            % --- Figure ---
            matlabx.Log.INFO("Setting up main figure window...");
            try obj.setupFigure(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

            % --- CommandRouter ---
            matlabx.Log.INFO("Setting up CommandRouter...");
            try obj.setupCommandRouter(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

            % --- Menubar ---
            matlabx.Log.INFO("Setting up Menubar...");
            try obj.setupMenubar(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

            % --- Grids ---
            matlabx.Log.INFO("Setting up Grid...");
            try obj.setupGrids(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

            % --- Viewer ---
            matlabx.Log.INFO("Setting up Viewer...");
            try obj.setupViewer(); catch ME, matlabx.Log.ERROR(ME); rethrow(ME); end

            % center the GUI after defining all graphics components
            movegui(obj.Fig,"center");
        end

        function setupFigure(obj)
            % create uifigure object
            obj.Fig = uifigure(...
                "WindowStyle",          obj.WindowStyle_,...
                "Position",             [0 0 500 500],...
                "Visible",              "off",...
                "AutoResizeChildren",   "off",...
                "Name",                 obj.Title,...
                "SizeChangedFcn",       @(~,~) obj.refreshWindowSize());
            obj.previousFigurePosition_ = [0 0 500 500];
        end

        function setupCommandRouter(obj)
            obj.CommandRouter = matlabx.ui.control.CommandRouter('Parent',obj.Fig);
        end

        function setupMenubar(obj)
            % Set up MenubarUI struct
            obj.MenubarUI = struct(...
                "File",struct(),...
                "Window",struct());

            % --- File ---
            obj.MenubarUI.File       = uimenu(obj.Fig,'Text','File');
            obj.MenubarUI.File_Load  = uimenu(obj.MenubarUI.File,'Text','Load...', 'MenuSelectedFcn',@(~,~) obj.onLoad(),'Accelerator','O');
            obj.MenubarUI.File_Close = uimenu(obj.MenubarUI.File,'Text','Close','MenuSelectedFcn',@(~,~) obj.onClose(),'Accelerator','X');

            % --- Window ---
            obj.MenubarUI.Window = uimenu(obj.Fig,'Text','Window');

            % WindowStyle
            S = struct("alwaysontop",[],"normal",[]);
            S.normal = uimenu(obj.MenubarUI.Window,'Text','normal','Tag','normal',...
                'MenuSelectedFcn',@(o,~) obj.onWindowStyleMenuSelected(o),'Checked','off');
            S.alwaysontop = uimenu(obj.MenubarUI.Window,'Text','always on top','Tag','alwaysontop',...
                'MenuSelectedFcn',@(o,~) obj.onWindowStyleMenuSelected(o),'Checked','off');
            obj.MenubarUI.Window_Style = S;

            % --- separator ---
            % WindowState
            S = struct("normal",[],"maximized",[],"minimized",[],"fullscreen",[]);
            S.normal = uimenu(obj.MenubarUI.Window,'Text','normal','Tag','normal',...
                'MenuSelectedFcn',@(o,~) obj.onWindowStateMenuSelected(o),'Checked','off','Separator','on');
            S.maximized = uimenu(obj.MenubarUI.Window,'Text','maximized','Tag','maximized',...
                'MenuSelectedFcn',@(o,~) obj.onWindowStateMenuSelected(o),'Checked','off');
            S.minimized = uimenu(obj.MenubarUI.Window,'Text','minimized','Tag','minimized',...
                'MenuSelectedFcn',@(o,~) obj.onWindowStateMenuSelected(o),'Checked','off');
            S.fullscreen = uimenu(obj.MenubarUI.Window,'Text','fullscreen','Tag','fullscreen',...
                'MenuSelectedFcn',@(o,~) obj.onWindowStateMenuSelected(o),'Checked','off');
            obj.MenubarUI.Window_State = S;

            % --- separator ---
            % WindowShape
            S = struct("normal",[],"tight",[],"square",[]);
            S.normal = uimenu(obj.MenubarUI.Window,'Text','normal','Tag','normal',...
                'MenuSelectedFcn',@(o,~) obj.onWindowShapeMenuSelected(o),'Checked','off','Separator','on');
            S.tight = uimenu(obj.MenubarUI.Window,'Text','tight','Tag','tight',...
                'MenuSelectedFcn',@(o,~) obj.onWindowShapeMenuSelected(o),'Checked','off');
            S.square = uimenu(obj.MenubarUI.Window,'Text','square','Tag','square',...
                'MenuSelectedFcn',@(o,~) obj.onWindowShapeMenuSelected(o),'Checked','off');
            obj.MenubarUI.Window_Shape = S;    

        end 

        function setupGrids(obj)
            % Main Grid
            obj.Grid = uigridlayout(obj.Fig,[1,1],...
                "ColumnWidth",{'1x'},...
                "RowHeight",{'1x'},...
                "Padding",[0 0 0 0],...
                "backgroundColor",obj.BackgroundColor);
        end

        function setupViewer(obj)
            % ImageAxes object for the viewer
            obj.Viewer = matlabx.ui.widgets.ImageAxes(obj.Grid,...
                "ToolBelt",     {'Zoom', 'Colorbar', 'ChooseColormap', 'Pick'},...
                "ImageData",    obj.Image,...
                "Name",         "Viewer",...
                "FontSize",     obj.FontSize);
        end

    end

    %% Global UI sync helpers
    methods (Access=private)

        function refreshUI(obj)
            % empty Image -> clear out UI
            if isempty(obj.Image)
                obj.clearUI();
                return
            end
            obj.refreshCalibration();
            obj.refreshMenubar();
            obj.Viewer.ImageData = obj.Image;
            obj.refreshWindowName();
            obj.refreshWindowSize();
        end

        function clearUI(obj)
            % menubar
            obj.refreshMenubar();
            % window name
            obj.Fig.Name = obj.Title;
            % ImageViewer
            obj.Viewer.ImageData = [];
        end

        function refreshWindowName(obj)
            obj.Fig.Name = obj.Title;
        end

        function refreshWindowSize(obj)
        %REFRESHWINDOWSIZE Control figure 

            % Prevent recursive SizeChangedFcn calls
            if obj.isResizingFigure, return; end

            % indicate that we are resizing figure
            obj.isResizingFigure = true; 
            % choose resize mode based on WindowShape
            switch obj.WindowShape
                case 'tight'
                    obj.fitWindowToImage();
                case 'square'
                    obj.fitWindowToSquare();
                case 'normal'
                    obj.previousFigurePosition_ = obj.Fig.Position;
            end
            % indicate that we are no longer resizing
            obj.isResizingFigure = false;
        end

        function refreshWindowState(obj)
            obj.Fig.WindowState = obj.WindowState_;
        end

        function refreshWindowStyle(obj)
            obj.Fig.WindowStyle = obj.WindowStyle_;
        end




        function refreshMenubar(obj)

            if isempty(obj.Image)
                % disable all menubar options
                names = fieldnames(obj.MenubarUI);
                for i = 1:numel(names)
                    obj.MenubarUI.(names{i}).Enable = "off";
                    obj.MenubarUI.(names{i}).Checked = "off";
                end
                % re-enable only File, and File->Load...
                set([obj.MenubarUI.File,obj.MenubarUI.File_Load],'Enable','on');
            else
                % enable all menubar options
                names = fieldnames(obj.MenubarUI);
                for i = 1:numel(names)
                    obj.MenubarUI.(names{i}).Enable = "on";
                end
            end

            % update WindowStyle menu options
            obj.MenubarUI.Window_Style.normal.Checked = strcmp(obj.WindowStyle,"normal");
            obj.MenubarUI.Window_Style.alwaysontop.Checked = strcmp(obj.WindowStyle,"alwaysontop");

            % update WindowState menu options
            obj.MenubarUI.Window_State.normal.Checked = strcmp(obj.WindowState,"normal");
            obj.MenubarUI.Window_State.maximized.Checked = strcmp(obj.WindowState,"maximized");
            obj.MenubarUI.Window_State.minimized.Checked = strcmp(obj.WindowState,"minimized");
            obj.MenubarUI.Window_State.fullscreen.Checked = strcmp(obj.WindowState,"fullscreen");

            % update WindowShape menu options
            obj.MenubarUI.Window_Shape.normal.Checked = strcmp(obj.WindowShape,"normal");
            obj.MenubarUI.Window_Shape.tight.Checked = strcmp(obj.WindowShape,"tight");
            obj.MenubarUI.Window_Shape.square.Checked = strcmp(obj.WindowShape,"square");
        end

        function refreshHotkeys(obj)
            % % add a hotkey for each action
            % Hotkey = matlabx.keyboard.normalize("d","d",["shift","meta"]);
            % HotkeyFcn = @(o,k) obj.actionOnHotkey(k);
        end

        function refreshCalibration(obj)
            obj.uipanelTopChromePx_ = obj.UICal.uipanelTopChromeHeightPx(obj.FontSize,"FontUnits","pixels");
        end


    end

    %% Dependent Set/Get
    methods

        % --- WindowState ---
        function set.WindowState(obj,val)
            obj.WindowState_ = val;
            obj.refreshWindowState();
            obj.refreshMenubar();
        end

        function val = get.WindowState(obj), val = obj.WindowState_; end

        % --- WindowStyle ---
        function set.WindowStyle(obj,val)
            obj.WindowStyle_ = val;
            obj.refreshWindowStyle();
            obj.refreshMenubar();
        end

        function val = get.WindowStyle(obj), val = obj.WindowStyle_; end

        % --- WindowShape ---
        function set.WindowShape(obj,val)
            disp('setting windowshape')
            obj.WindowShape_ = val;
            obj.refreshWindowSize();
            obj.refreshMenubar();
        end

        function val = get.WindowShape(obj), val = obj.WindowShape_; end

    end

    %% Window UI Helpers
    methods (Access=private)
        
        % function fitWindowToImage(obj)
        %     figPos = obj.Fig.Position;
        %     figX = figPos(1);
        %     figY = figPos(2);
        %     figW = figPos(3);
        %     figH = figPos(4);
        % 
        %     if figW <= 0 || figH <= 0, return; end
        % 
        %     % get height and width of actual image
        %     imgH = obj.Image.SizeY;
        %     imgW = obj.Image.SizeX;
        % 
        %     % height / width ratios
        %     targetRatio = imgH / imgW;
        %     currentRatio = figH / figW;
        % 
        %     % --- get new W and H for figure window ---
        %     if currentRatio > targetRatio
        %         % Figure is too tall for the image
        %         newFigW = figW;
        %         newFigH = figW * targetRatio;
        %     else
        %         % Figure is too wide for the image
        %         newFigH = figH;
        %         newFigW = figH / targetRatio;
        %     end
        % 
        %     newFigH = newFigH + obj.uipanelTopChromePx_;
        % 
        %     % --- adjust to maintain previous window center ---
        %     if ~isempty(obj.previousFigurePosition_)
        %         % p = obj.previousFigurePosition_;
        %         p = figPos;
        %         oldCenterX = p(1)+p(3)/2;
        %         oldCenterY = p(2)+p(4)/2;
        % 
        %         figX = oldCenterX-newFigW/2;
        %         figY = oldCenterY-newFigH/2;
        %     end
        % 
        %     % --- set position ---
        % 
        %     newPos = [figX, figY, newFigW, newFigH];
        % 
        %     % Avoid tiny floating-point resize loops
        %     if any(abs(newPos - figPos) > 0.5)
        %         obj.previousFigurePosition_ = newPos;
        %         obj.Fig.Position = newPos;
        %     end
        % end


        function fitWindowToImage(obj)
            figPos = obj.Fig.Position;
            figX = figPos(1);
            figY = figPos(2);
            figW = figPos(3);
            figH = figPos(4);

            if figW <= 0 || figH <= 0, return; end

            panelTop = obj.uipanelTopChromePx_;

            % axes height and width
            axH = figH-panelTop;
            axW = figW;

            % get height and width of actual image
            imgH = obj.Image.SizeY;
            imgW = obj.Image.SizeX;

            % height / width ratios
            targetRatio = imgH / imgW;
            currentRatio = axH / axW;

            % dimensions already correct -> return
            if targetRatio == currentRatio, return; end

            % determine whether H/W are increasing/decreasing
            lastW = obj.previousFigurePosition_(3);
            lastH = obj.previousFigurePosition_(4);

            W_decreasing = lastW > figW;
            W_increasing = lastW < figW;
            W_static = lastW == figW;

            H_decreasing = lastH > figH;
            H_increasing = lastH < figH;
            H_static = lastH == figH;

            % --- get new W and H for figure window ---
            if currentRatio > targetRatio
                % figure too tall for image
                if H_static && W_static
                    newFigH = (figW * targetRatio) + panelTop;
                    newFigW = figW;
                elseif W_decreasing
                    % decrease height
                    newFigH = (figW * targetRatio) + panelTop;
                    newFigW = figW;
                elseif H_increasing
                    % increase width
                    newFigW = axH / targetRatio;
                    newFigH = figH;
                else
                    obj.previousFigurePosition_ = figPos;
                    return
                end
            else
                % figure too wide for image
                if H_static && W_static % decrease width
                    newFigW = axH / targetRatio;
                    newFigH = figH;
                elseif H_decreasing % decrease width
                    newFigW = axH / targetRatio;
                    newFigH = figH;
                elseif W_increasing
                    % increase height
                    newFigH = (figW * targetRatio) + panelTop;
                    newFigW = figW;
                else
                    obj.previousFigurePosition_ = figPos;
                    return
                end
            end

            % H/W cannot be less than 0
            newFigH = max(newFigH, 0);
            newFigW = max(newFigW, 0);

            % Avoid tiny floating-point resize loops
            if any(abs([newFigW newFigH] - figPos(3:4)) > 0.5)
                obj.previousFigurePosition_ = [figX, figY, newFigW, newFigH];
                obj.Fig.Position(3:4) = [newFigW newFigH];
            end

        end

        function fitWindowToSquare(obj)
            figPos = obj.Fig.Position;
            figX = figPos(1);
            figY = figPos(2);
            figW = figPos(3);
            figH = figPos(4);

            if figW <= 0 || figH <= 0, return; end

            panelTop = obj.uipanelTopChromePx_;

            % axes height and width
            axH = figH-panelTop;
            axW = figW;

            % already square -> return
            if axH == axW, return; end

            % determine whether H/W are increasing/decreasing
            lastW = obj.previousFigurePosition_(3);
            lastH = obj.previousFigurePosition_(4);

            W_decreasing = lastW > figW;
            W_increasing = lastW < figW;
            W_static = lastW == figW;

            H_decreasing = lastH > figH;
            H_increasing = lastH < figH;
            H_static = lastH == figH;

            % --- get new W and H for figure window ---
            if axH > axW
                if H_static && W_static
                    newFigH = figW + panelTop;
                    newFigW = figW;
                elseif W_decreasing
                    newFigH = figW + panelTop;
                    newFigW = figW;
                elseif H_increasing
                    newFigW = axH;
                    newFigH = figH;
                else
                    obj.previousFigurePosition_ = figPos;
                    return
                end
            else
                if H_static && W_static
                    newFigW = axH;
                    newFigH = figH;
                elseif H_decreasing
                    newFigW = axH;
                    newFigH = figH;
                elseif W_increasing
                    newFigH = figW + panelTop;
                    newFigW = figW;
                else
                    obj.previousFigurePosition_ = figPos;
                    return
                end
            end


            % % --- get new W and H for figure window ---
            % if W_decreasing
            %     newFigH = figW + panelTop;
            %     newFigW = figW;
            % elseif H_increasing
            %     newFigW = axH;
            %     newFigH = figH;
            % elseif H_decreasing
            %     newFigW = axH;
            %     newFigH = figH;
            % elseif W_increasing
            %     newFigH = figW + panelTop;
            %     newFigW = figW;
            % else
            %     return
            % end

            % H/W cannot be less than 0
            newFigH = max(newFigH, 0);
            newFigW = max(newFigW, 0);

            % Avoid tiny floating-point resize loops
            if any(abs([newFigW newFigH] - figPos(3:4)) > 0.5)
                obj.previousFigurePosition_ = [figX, figY, newFigW, newFigH];
                obj.Fig.Position(3:4) = [newFigW newFigH];
            end

        end

    end

    %% Callbacks - hotkeys
    methods (Access=private)

        function actionOnHotkey(obj,key)
            if isempty(obj.Image), return; end
            matlabx.struct.prettyPrint(key);
        end

    end

    %% Callbacks - Listeners
    methods (Access=private)

        function onFontSizeChanged(obj)
            obj.refreshCalibration();
            obj.refreshWindowSize();
        end

    end

    %% Callbacks - Menubar
    methods (Access=private)

        % --- File ---

        function onLoad(obj)
        %ONLOAD Menubar callback for [File]->[Load...]
            % hide figure, show file selection dialog, show figure
            obj.Fig.Visible = 'off';
            % update log
            matlabx.Log.INFO("Selecting image file...");

            try
                % get Image5D using file dialog
                I = matlabx.image.Image5D.fromFileDialog(...
                    "LoadOnCreate",true);
                % set as image
                obj.Image = I;
            catch ME
                matlabx.Log.ERROR(ME);
                obj.guialert(ME);
            end

            obj.refreshUI();
            obj.Fig.Visible = 'on';
        end

        function onClose(obj)
        %ONCLOSE Menubar callback for [File]->[Close]    
            % no image -> return
            if isempty(obj.Image), return; end
            % --- delete project, detach listeners, refresh UI ---
            obj.Image.unload();
            obj.Image.delete();
            obj.Image = matlabx.app.Viewer5D.getDemoImage();
            obj.refreshUI();
        end


        % --- Window ---

        % WindowStyle
        function onWindowStyleMenuSelected(obj,src), obj.WindowStyle = src.Tag; end
        % WindowState
        function onWindowStateMenuSelected(obj,src), obj.WindowState = src.Tag; end
        % WindowShape
        function onWindowShapeMenuSelected(obj,src), obj.WindowShape = src.Tag; end

    end

    %% Other helpers
    methods (Access=private)

        function guialert(obj,opts)
            arguments
                obj (1,1) matlabx.app.Viewer5D
                opts.Message = ""
                opts.Title = "Untitled"
                opts.Icon (1,:) char {mustBeMember(opts.Icon,{'error','warning','info','message','success',''})} = ''
            end

            % uialert dialog, closing will resume interaction on main window
            uialert(obj.Fig,...
                opts.Message,...
                opts.Title,...
                'Icon',opts.Icon,...
                'CloseFcn',@(o,e) uiresume(obj.Fig));
            % prevent interaction with the main window until we finish
            uiwait(obj.Fig);
        end

    end

    %% Static
    methods (Static)

        function Image = getDemoImage()
            I = imread("rice.png");
            Image = matlabx.image.Image5D.fromComponents({I});
        end

    end

end