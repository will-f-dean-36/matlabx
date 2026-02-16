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
    end

    properties (Access=private, Transient, NonCopyable)
        BoxPatch (1,1) matlab.graphics.primitive.Patch
        % listener handle(s)
        L
        % flag for coalescing updates
        pendingUpdate logical = false
        % dynamic properties
        P (:,1) matlab.metadata.DynamicProperty
    end

    % appearance properties
    properties (SetObservable, AbortSet)
        FaceColor = [1 1 1]

        LineWidth = 0.5
        HoverLineWidth = 2
        SelectionLineWidth = 1

        FaceAlpha = 0
        HoverFaceAlpha = 0.25
        SelectionFaceAlpha = 0.1
    end


    methods

        function obj = ROIBox(ax, opts)

            arguments
                ax (1,1) matlab.ui.control.UIAxes
                opts.Center   (1,2) double = [NaN NaN]
                opts.BoxSize  (1,1) double {mustBePositive} = 50
                opts.ButtonDownFcn = []
                opts.ID (1,1) string = ""
            end

            obj.BoxPatch = patch(ax, ...
                NaN, ...
                NaN, ...
                'w', ...
                'FaceColor',obj.FaceColor, ...
                'FaceAlpha',obj.FaceAlpha,...
                'HitTest','on', ...
                'PickableParts','all', ...
                'LineWidth', obj.LineWidth, ...
                'Tag','ROIBox');

            % add ID property to the BoxPatch for tracking ownership
            obj.P(1) = addprop(obj.BoxPatch,'ID');

            % apply inputs
            obj.Center        = opts.Center;
            obj.BoxSize       = opts.BoxSize;
            obj.ButtonDownFcn = opts.ButtonDownFcn;
            obj.ID = opts.ID;

            % set dynamic property (ID)
            obj.BoxPatch.ID = opts.ID;

            % one listener covers Center, BoxSize, and ButtonDownFcn
            obj.L = addlistener(obj, {'Center','BoxSize','ButtonDownFcn'}, ...
                'PostSet', @(~,~) obj.queueGeometryUpdate());

            % one listener covers HoverHighlight and SelectionHighlight
            obj.L(2) = addlistener(obj, {'HoverHighlight', 'SelectionHighlight', 'FaceColor'}, ...
                'PostSet', @(~,~) obj.updateAppearance());

            obj.updateGeometry();  % initial draw

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
            % geometry
            c = obj.Center; s = obj.BoxSize/2;
            X = [c(1)-s c(1)+s c(1)+s c(1)-s];
            Y = [c(2)-s c(2)-s c(2)+s c(2)+s];
            set(obj.BoxPatch, 'XData',X, 'YData',Y);

            % callback (forward as-is)
            if isempty(obj.ButtonDownFcn)
                set(obj.BoxPatch,'ButtonDownFcn',[]);
            else
                set(obj.BoxPatch,'ButtonDownFcn',obj.ButtonDownFcn);
            end
        end

        function updateAppearance(obj)

            obj.BoxPatch.FaceColor = obj.FaceColor;

            % set patch appearance properties based on status flags
            if obj.HoverHighlight
                obj.BoxPatch.LineWidth = obj.HoverLineWidth;
                obj.BoxPatch.FaceAlpha = obj.HoverFaceAlpha;
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

