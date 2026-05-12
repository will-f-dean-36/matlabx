classdef SliderGroupDialog < handle

    properties
        Title                   (:,1) char = 'Slider group dialog'
        Name                    (1,:) cell = {'Slider'}
        Limits                  (1,:) cell = {[0 1]}
        Value                   (1,:) cell = {[0 1]}
        RoundValues             (1,:) cell = {"on"}
        RoundDigits             (1,:) cell = {0}
        ValueDisplayFormat      (1,:) cell = {'%d'}
        Colormap                (1,:) cell = {gray(256)}
        ValueChangedFcn         (:,1) function_handle = function_handle.empty
        ValueChangingFcn        (:,1) function_handle = function_handle.empty
        ClosedFcn               (:,1) function_handle = function_handle.empty
    end

    properties (Access=private,Transient,NonCopyable)
        Fig matlab.ui.Figure
        Grid matlab.ui.container.GridLayout
        Slider matlabx.ui.widgets.uirangeslidereditfield
    end

    methods

        function obj = SliderGroupDialog(N,opts)
            arguments
                N                            (1,1) double = 1
                opts.Title                   (:,1) char = 'Slider group dialog'
                opts.Name                    (1,:) cell = {'Slider'}
                opts.Limits                  (1,:) cell = {[0 1]}
                opts.Value                   (1,:) cell = {[0 1]}
                opts.RoundValues             (1,:) cell = {"on"}
                opts.RoundDigits             (1,:) cell = {0}
                opts.ValueDisplayFormat      (1,:) cell = {'%d'}
                opts.Colormap                (1,:) cell = {gray(256)}
                opts.ValueChangedFcn         (:,1) function_handle = function_handle.empty
                opts.ValueChangingFcn        (:,1) function_handle = function_handle.empty
                opts.ClosedFcn               (:,1) function_handle = function_handle.empty
            end

            % apply inputs
            fn = fieldnames(opts);
            for i = 1:numel(fn), obj.(fn{i}) = opts.(fn{i}); end

            % Figure window
            obj.Fig = uifigure("WindowStyle","alwaysontop",...
                "Name",obj.Title,...
                "Position",[0 0 300 50],...
                "AutoResizeChildren","off",...
                "CloseRequestFcn",@(~,~) obj.onCloseFigure(),...
                "DeleteFcn",@(~,~) obj.delete());

            % Main Grid
            obj.Grid = uigridlayout(obj.Fig,[N 1], ...
                'ColumnWidth',{'1x'}, ...
                'RowHeight',repmat({'fit'},N,1), ...
                'ColumnSpacing',5, ...
                'RowSpacing',5, ...
                'Padding',[5 5 5 5],...
                'BackgroundColor',[0.12 0.12 0.12]);

            % Sliders

            for i = 1:N
                obj.Slider(i) = matlabx.ui.widgets.uirangeslidereditfield(obj.Grid,...
                    "Title",obj.Name{i},...
                    "FontColor",[1 1 1],...
                    "BackgroundColor",[0.12 0.12 0.12],...
                    "Limits",obj.Limits{i},...
                    "Value",obj.Value{i},...
                    "RoundValues",obj.RoundValues{i},...
                    "RoundDigits",obj.RoundDigits{i},...
                    "ValueDisplayFormat",obj.ValueDisplayFormat{i},...
                    "Colormap",obj.Colormap{i},...
                    "ValueChangingFcn",@(src,~) obj.onSliderChanging(src,i),...
                    "ValueChangedFcn",@(src,~) obj.onSliderChanged(src,i));
            end

            obj.Fig.InnerPosition(4) = obj.Slider(i).ComponentHeight*N + 10 + N*5;

            % Center the figure
            movegui(obj.Fig, "center");

        end

    end





    %% Internal callbacks
    methods (Access=private)

        function onSliderChanging(obj, src, idx)
            % Trigger the value changed callback if set
            if ~isempty(obj.ValueChangingFcn)
                evt = obj.buildEventStruct(src,idx);
                obj.ValueChangingFcn(src, evt);
            end
        end

        function onSliderChanged(obj, src, idx)
            % Trigger the value changed callback if set
            if ~isempty(obj.ValueChangedFcn)
                evt = obj.buildEventStruct(src,idx);
                obj.ValueChangedFcn(src, evt);
            end
        end

        function onCloseFigure(obj)
            % Trigger the closed callback if set
            if ~isempty(obj.ClosedFcn)
                obj.ClosedFcn();
            end
            % delete self
            delete(obj.Fig);
        end

    end


    methods (Access=private)
        function S = buildEventStruct(~,src,idx)
            S = struct('Source',src,'ID',idx);
        end
    end


    methods

        function delete(obj)
            % delete components and figure
            if ~isempty(obj.Slider), delete(obj.Slider(isvalid(obj.Slider))); end
            if ~isempty(obj.Grid), delete(obj.Grid(isvalid(obj.Grid))); end
            if ~isempty(obj.Fig), delete(obj.Fig(isvalid(obj.Fig))); end
        end


    end


end