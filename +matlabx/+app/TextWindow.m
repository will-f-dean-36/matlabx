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
            % Trigger the closed callback if set
            if ~isempty(obj.ClosedFcn)
                obj.ClosedFcn();
            end
            % delete self
            delete(obj.Fig);
        end

    end

    methods

        function delete(obj)
            % delete components and figure
            if ~isempty(obj.TextArea), delete(obj.TextArea(isvalid(obj.TextArea))); end
            if ~isempty(obj.Grid), delete(obj.Grid(isvalid(obj.Grid))); end
            if ~isempty(obj.Fig), delete(obj.Fig(isvalid(obj.Fig))); end
        end

    end

end