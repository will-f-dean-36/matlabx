classdef TextWindow < handle

    properties
        Title       (:,1) char   = 'Untitled'
        Text        (:,1) cell   = {}
        FontName    (1,:) char   = 'Courier New'
        Position    (1,:) double = []
        ClosedFcn   (:,1) function_handle = function_handle.empty
    end

    properties (Access=private,Transient,NonCopyable)
        Fig matlab.ui.Figure
        Grid matlab.ui.container.GridLayout
        TextArea matlab.ui.control.TextArea
    end

    properties (Access=private)
        ClosedNotified (1,1) logical = false
    end

    methods

        function obj = TextWindow(opts)
            arguments
                opts.Title      (:,1) char = 'Untitled'
                opts.Text       (:,1) cell = {}
                opts.FontName   (1,:) = 'Courier New'
                opts.Position   (1,:) double = []
                opts.ClosedFcn  (:,1) function_handle = function_handle.empty
            end

            % apply inputs
            obj.Title = opts.Title;
            obj.Text = opts.Text;
            obj.FontName = opts.FontName;
            obj.ClosedFcn = opts.ClosedFcn;

            if ~isempty(opts.Position)
                obj.Position = opts.Position; 
            else
                obj.Position = [0 0 300 600];
            end

            % Figure window
            obj.Fig = uifigure("WindowStyle","alwaysontop",...
                "Name",obj.Title,...
                "Position",obj.Position,...
                "AutoResizeChildren","off",...
                "CloseRequestFcn",@(~,~) obj.onCloseFigure(),...
                "DeleteFcn",@(~,~) obj.delete(),...
                "Visible","off");

            % Main Grid
            obj.Grid = uigridlayout(obj.Fig,[1 1], ...
                'ColumnWidth',{'1x'}, ...
                'RowHeight',{'1x'}, ...
                'ColumnSpacing',5, ...
                'RowSpacing',5, ...
                'Padding',[0 0 0 0],...
                'BackgroundColor',[0.12 0.12 0.12]);

            % TextArea
            obj.TextArea = uitextarea(obj.Grid, ...
                "Value",obj.Text, ...
                "FontName",obj.FontName, ...
                "WordWrap","off");

            % Center the figure
            movegui(obj.Fig, "center");

            % show it
            obj.Fig.Visible = "on";

        end

    end

    methods (Access=private)

        function onCloseFigure(obj)
            obj.notifyClosed();
            % delete self
            delete(obj.Fig);
        end

        function notifyClosed(obj)
            %NOTIFYCLOSED Fire ClosedFcn once, regardless of close/delete path.
            if obj.ClosedNotified
                return
            end

            obj.ClosedNotified = true;

            if isempty(obj.ClosedFcn)
                return
            end

            n = nargin(obj.ClosedFcn);
            if n == 0
                obj.ClosedFcn();
            elseif n == 1
                obj.ClosedFcn(obj);
            else
                obj.ClosedFcn(obj, []);
            end
        end

    end

    methods

        function delete(obj)
            obj.notifyClosed();
            % delete components and figure
            if ~isempty(obj.TextArea), delete(obj.TextArea(isvalid(obj.TextArea))); end
            if ~isempty(obj.Grid), delete(obj.Grid(isvalid(obj.Grid))); end
            if ~isempty(obj.Fig), delete(obj.Fig(isvalid(obj.Fig))); end
        end

    end

end
