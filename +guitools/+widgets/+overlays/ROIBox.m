classdef ROIBox < handle & matlab.mixin.SetGetExactNames

    properties
        ID (1,1) string = ""    % widget-local id (opaque to the model)
    end

    properties (SetObservable, AbortSet)
        Center   (1,2) double = [NaN NaN]
        BoxSize  (1,1) double {mustBePositive} = 50
        ButtonDownFcn                    % use validator if you like
        HoverHighlight (1,1) matlab.lang.OnOffSwitchState = 'off'
        SelectionHighlight (1,1) matlab.lang.OnOffSwitchState = 'off'
        ActiveHighlight (1,1) matlab.lang.OnOffSwitchState = 'off'
        Label (1,1) string = ""
        FontSize (1,1) double = 10
    end

    properties (Access=private, Transient, NonCopyable)
        BoxPatch (1,1) matlab.graphics.primitive.Patch
        % listener handle(s)
        L
        % flag for coalescing updates
        pendingUpdate logical = false
        % dynamic properties
        P (:,1) matlab.metadata.DynamicProperty

        BoxLabel (1,1) matlab.graphics.primitive.Text
    end

    % appearance properties
    properties (SetObservable, AbortSet)
        FaceColor = [1 1 1]
        EdgeColor = [1 1 1]

        LineWidth = 0.5
        HoverLineWidth = 2
        SelectionLineWidth = 1
        ActiveLineWidth = 2

        FaceAlpha = 0
        HoverFaceAlpha = 0.5
        SelectionFaceAlpha = 0.1
        ActiveFaceAlpha = 0.1
    end


    methods

        function obj = ROIBox(ax, opts)

            arguments
                ax (1,1) matlab.ui.control.UIAxes
                opts.Center   (1,2) double = [NaN NaN]
                opts.BoxSize  (1,1) double {mustBePositive} = 50
                opts.ButtonDownFcn = []
                opts.ID (1,1) string = ""
                opts.Label (1,1) string = ""
                opts.EdgeColor = [1 1 1]
                opts.FaceColor = [1 1 1]
            end

            % patch object to form a square box
            obj.BoxPatch = patch(ax, ...
                'XData',NaN, ...
                'YData',NaN, ...
                'EdgeColor',obj.EdgeColor, ...
                'FaceColor',obj.FaceColor, ...
                'FaceAlpha',obj.FaceAlpha, ...
                'HitTest','on', ...
                'PickableParts','all', ...
                'LineWidth', obj.LineWidth, ...
                'Tag','ROIBox');

            % label in top-left corner of box
            obj.BoxLabel = text('Parent',ax,...
                'Units','data',...
                'Position',[NaN NaN],...
                'Color',[1 1 1],...
                'BackgroundColor','none',...
                'String','',...
                'FontSize',10,...
                'Clipping','off',...
                'Margin',3,...
                'HorizontalAlignment','left',...
                'VerticalAlignment','top',...
                'HitTest','off');

            % add ID property to the BoxPatch for tracking ownership
            obj.P(1) = addprop(obj.BoxPatch,'ID');

            % apply inputs
            obj.Center          = opts.Center;
            obj.BoxSize         = opts.BoxSize;
            obj.ButtonDownFcn   = opts.ButtonDownFcn;
            obj.ID              = opts.ID;
            obj.FaceColor       = opts.FaceColor;
            obj.EdgeColor       = opts.EdgeColor;

            % set dynamic property (ID)
            obj.BoxPatch.ID = opts.ID;

            % one listener covers geometry properties and ButtonDownFcn callback
            geomProps = {...
                'Center',...
                'BoxSize',...
                'ButtonDownFcn'...
                };
            obj.L = addlistener(obj, geomProps, 'PostSet', @(~,~) obj.queueGeometryUpdate());

            % one listener covers appearance properties
            appProps = {...
                'HoverHighlight',...
                'SelectionHighlight',...
                'ActiveHighlight',...
                'FaceColor',...
                'EdgeColor',...
                'Label',...
                'FontSize'...
                };
            obj.L(2) = addlistener(obj, appProps, 'PostSet', @(~,~) obj.updateAppearance());

            % initial draw
            obj.updateGeometry();
            obj.updateAppearance();

        end

        function delete(obj)
            % Array-safe destructor
            for k = 1:numel(obj)
                % Drop listeners first
                if ~isempty(obj(k).L) && all(isvalid(obj(k).L))
                    delete(obj(k).L);
                end

                % replace listener property with empty array of event.listener
                obj.L = event.listener.empty;

                % delete patch if it exists
                if ~isempty(obj(k).BoxPatch) && isgraphics(obj(k).BoxPatch)
                    delete(obj(k).BoxPatch);
                end

                % delete text if it exists
                if ~isempty(obj(k).BoxLabel) && isgraphics(obj(k).BoxLabel)
                    delete(obj(k).BoxLabel);
                end
            end
        end

    end

    methods (Access=private)
        
        function queueGeometryUpdate(obj)
            if obj.pendingUpdate
                return
            end
            obj.pendingUpdate = true;
            % coalesce updates
            drawnow limitrate nocallbacks
            obj.updateGeometry();
            obj.pendingUpdate = false;
        end

        function updateGeometry(obj)
            % box patch geometry
            c = obj.Center; s = obj.BoxSize/2;
            X = [c(1)-s c(1)+s c(1)+s c(1)-s];
            Y = [c(2)-s c(2)-s c(2)+s c(2)+s];
            set(obj.BoxPatch, 'XData', X, 'YData', Y);

            % label coordinates
            shift = 0.05*s; % amount to shift label
            set(obj.BoxLabel, 'Position', [X(1) Y(1)]);


            % callback (forward as-is)
            if isempty(obj.ButtonDownFcn)
                set(obj.BoxPatch,'ButtonDownFcn',[]);
            else
                set(obj.BoxPatch,'ButtonDownFcn',obj.ButtonDownFcn);
            end
        end

        function updateAppearance(obj)

            % update patch colors
            obj.BoxPatch.EdgeColor = obj.EdgeColor;
            obj.BoxPatch.FaceColor = obj.FaceColor;

            % update label
            obj.BoxLabel.String = obj.Label;
            obj.BoxLabel.FontSize = obj.FontSize;

            % update patch LineWidth and FaceAlpha based on highlight status
            if obj.HoverHighlight
                obj.BoxPatch.LineWidth = obj.HoverLineWidth;
                obj.BoxPatch.FaceAlpha = obj.HoverFaceAlpha;
            elseif obj.ActiveHighlight
                obj.BoxPatch.LineWidth = obj.ActiveLineWidth;
                obj.BoxPatch.FaceAlpha = obj.ActiveFaceAlpha;
            elseif obj.SelectionHighlight
                obj.BoxPatch.LineWidth = obj.SelectionLineWidth;
                obj.BoxPatch.FaceAlpha = obj.SelectionFaceAlpha;
            else
                obj.BoxPatch.LineWidth = obj.LineWidth;
                obj.BoxPatch.FaceAlpha = obj.FaceAlpha;
            end

        end

    end

end

