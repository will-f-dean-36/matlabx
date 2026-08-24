classdef PointClusterTuner < handle
%POINTCLUSTERTUNER App for tuning puncta detection and point clustering.
%
%   app = matlabx.app.PointClusterTuner() opens a small interactive tuning
%   app with a demo puncta-like image.
%
%   app = matlabx.app.PointClusterTuner(I) opens the app with either a 2-D
%   numeric image or a matlabx.image.Image5D object. Image5D inputs are shown
%   as a single C/Z/T plane for this first tuning pass.
%
%   The app is intentionally lightweight. It wires together:
%       matlabx.image.measure.detectPoints
%       matlabx.analysis.cluster.PointClusters
%       matlabx.ui.axes.ImageAxes
%       matlabx.ui.axes.overlays.PointSet
%       matlabx.ui.axes.overlays.PointClusters
%
%   The goal is fast visual iteration: detect points, cluster them, refine or
%   filter clusters, and inspect metrics without committing to a final
%   app-level workflow too early.

    properties (Access=private, Transient, NonCopyable)
        Fig matlab.ui.Figure
        MainGrid matlab.ui.container.GridLayout
        LeftPane matlab.ui.container.GridLayout
        CenterGrid matlab.ui.container.GridLayout
        RightGrid matlab.ui.container.GridLayout

        SettingsAccordion matlabx.ui.container.Accordion

        ViewerPanel matlab.ui.container.Panel
        ViewerGrid matlab.ui.container.GridLayout
        Ax matlabx.ui.axes.ImageAxes

        SummaryPanel matlab.ui.container.Panel
        SummaryGrid matlab.ui.container.GridLayout
        ClusterTable matlab.ui.control.Table
        StatusText matlab.ui.control.TextArea

        UI struct
    end

    properties (Access=private)
        FontSize (1,1) double = 12
        Padding (1,1) double = 5
        ControlW (1,1) double = 320

        ImageData = []
        ImagePlane (:,:) double = zeros(0,0)
        ImageSourceDescription (1,1) string = "Demo image"

        DetectionPoints (:,2) double = zeros(0,2)
        DetectionInfo struct = struct()
        Clusters matlabx.analysis.cluster.PointClusters = matlabx.analysis.cluster.PointClusters.empty()

        DetectionOverlay matlabx.ui.axes.ImageAxesOverlay = matlabx.ui.axes.ImageAxesOverlay.empty()
        ClusterOverlay matlabx.ui.axes.ImageAxesOverlay = matlabx.ui.axes.ImageAxesOverlay.empty()

        IsRefreshingUI (1,1) logical = false
    end

    methods
        function obj = PointClusterTuner(imageData)
        %POINTCLUSTERTUNER Construct and show the tuning app.
            arguments
                imageData = []
            end

            obj.buildGUI();

            if isempty(imageData)
                obj.setImage(obj.makeDemoImage_(), "Demo puncta image");
            else
                obj.setImage(imageData, "Input image");
            end

            obj.Fig.Visible = "on";
        end

        function delete(obj)
        %DELETE Close the app figure and owned graphics.
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                delete(obj.Fig);
            end
        end

        function runCurrentPipeline(obj)
        %RUNCURRENTPIPELINE Run detection and clustering using current UI values.
            obj.runDetectionAndClustering();
        end
    end

    methods (Access=private)
        function buildGUI(obj)
        %BUILDGUI Create the figure, layout, controls, viewer, and table.
            obj.setupFigure();
            obj.setupGrids();
            obj.setupAccordion();
            obj.setupViewer();
            obj.setupSummary();
            obj.refreshMethodControls();
        end

        function setupFigure(obj)
        %SETUPFIGURE Create the app window.
            obj.Fig = uifigure( ...
                "Name", "Point Cluster Tuner", ...
                "Color", [0.12 0.12 0.12], ...
                "Position", [100 100 1350 820], ...
                "Visible", "off", ...
                "AutoResizeChildren", "off", ...
                "CloseRequestFcn", @(~,~) delete(obj));

            if isprop(obj.Fig, "Theme")
                obj.Fig.Theme = "dark";
            end
        end

        function setupGrids(obj)
        %SETUPGRIDS Create the top-level three-column layout.
            obj.MainGrid = uigridlayout(obj.Fig, [1 3], ...
                "ColumnWidth", {obj.ControlW, "1x", 380}, ...
                "RowHeight", {"1x"}, ...
                "ColumnSpacing", obj.Padding, ...
                "RowSpacing", 0, ...
                "Padding", [obj.Padding obj.Padding obj.Padding obj.Padding], ...
                "BackgroundColor", [0.12 0.12 0.12]);

            obj.LeftPane = uigridlayout(obj.MainGrid, [1 1], ...
                "ColumnWidth", {"1x"}, ...
                "RowHeight", {"fit"}, ...
                "Padding", [0 0 0 0], ...
                "BackgroundColor", [0.12 0.12 0.12], ...
                "Scrollable", "on");
            obj.LeftPane.Layout.Column = 1;

            obj.CenterGrid = uigridlayout(obj.MainGrid, [1 1], ...
                "ColumnWidth", {"1x"}, ...
                "RowHeight", {"1x"}, ...
                "Padding", [0 0 0 0], ...
                "BackgroundColor", [0.12 0.12 0.12]);
            obj.CenterGrid.Layout.Column = 2;

            obj.RightGrid = uigridlayout(obj.MainGrid, [2 1], ...
                "ColumnWidth", {"1x"}, ...
                "RowHeight", {"1x", 180}, ...
                "RowSpacing", obj.Padding, ...
                "Padding", [0 0 0 0], ...
                "BackgroundColor", [0.12 0.12 0.12]);
            obj.RightGrid.Layout.Column = 3;
        end

        function setupAccordion(obj)
        %SETUPACCORDION Create settings accordion and all control panes.
            obj.SettingsAccordion = matlabx.ui.container.Accordion(obj.LeftPane, ...
                "ItemSpacing", obj.Padding, ...
                "BorderWidth", 0, ...
                "BorderColor", [0.18 0.18 0.18], ...
                "Padding", 0, ...
                "BackgroundColor", [0.12 0.12 0.12]);

            titles = ["Input", "Detection", "Clustering", ...
                "Point Refinement", "Cluster Filtering", "Display", "Pipeline"];
            for i = 1:numel(titles)
                obj.SettingsAccordion.addItem( ...
                    "Title", titles(i), ...
                    "BorderColor", [0.49 0.49 0.49], ...
                    "TitleBackgroundColor", [0.12 0.12 0.12], ...
                    "HoverTitleBackgroundColor", [0.30 0.30 0.30], ...
                    "PaneBackgroundColor", [0.18 0.18 0.18], ...
                    "FontColor", [0.85 0.85 0.85], ...
                    "BorderWidth", 1, ...
                    "ExpandedBorderWidth", 1, ...
                    "TitlePadding", 1);
            end

            obj.UI = struct();
            obj.setupInputControls();
            obj.setupDetectionControls();
            obj.setupClusteringControls();
            obj.setupPointRefinementControls();
            obj.setupClusterFilteringControls();
            obj.setupDisplayControls();
            obj.setupPipelineControls();

            obj.SettingsAccordion.getItem("Input").expand();
            obj.SettingsAccordion.getItem("Detection").expand();
            obj.SettingsAccordion.getItem("Clustering").expand();
        end

        function setupInputControls(obj)
        %SETUPINPUTCONTROLS Create image loading and demo-image controls.
            item = obj.SettingsAccordion.getItem("Input");
            obj.configurePaneGrid(item.Pane, 4);

            obj.UI.Input.LoadButton = uibutton(item.Pane, ...
                "Text", "Load Image...", ...
                "ButtonPushedFcn", @(~,~) obj.onLoadImage());
            obj.UI.Input.LoadButton.Layout.Row = 1;
            obj.UI.Input.LoadButton.Layout.Column = [1 2];

            obj.UI.Input.DemoButton = uibutton(item.Pane, ...
                "Text", "Use Demo Image", ...
                "ButtonPushedFcn", @(~,~) obj.onUseDemoImage());
            obj.UI.Input.DemoButton.Layout.Row = 2;
            obj.UI.Input.DemoButton.Layout.Column = [1 2];

            obj.addLabel(item.Pane, "Image");
            obj.UI.Input.ImageLabel = uilabel(item.Pane, ...
                "Text", "none", ...
                "FontColor", [0.85 0.85 0.85]);
            matlabx.app.PointClusterTuner.placeInCurrentRow(item.Pane, obj.UI.Input.ImageLabel);

            obj.addLabel(item.Pane, "Plane");
            obj.UI.Input.PlaneLabel = uilabel(item.Pane, ...
                "Text", "C1 Z1 T1", ...
                "FontColor", [0.85 0.85 0.85]);
            matlabx.app.PointClusterTuner.placeInCurrentRow(item.Pane, obj.UI.Input.PlaneLabel);
        end

        function setupDetectionControls(obj)
        %SETUPDETECTIONCONTROLS Create puncta-detection controls.
            item = obj.SettingsAccordion.getItem("Detection");
            obj.configurePaneGrid(item.Pane, 13);

            obj.addLabel(item.Pane, "Method");
            obj.UI.Detection.MethodDropDown = uidropdown(item.Pane, ...
                "Items", {'regionalMaxima','extendedMaxima','surf','log','dog'}, ...
                "Value", "log", ...
                "ValueChangedFcn", @(~,~) obj.refreshMethodControls());
            matlabx.app.PointClusterTuner.placeInCurrentRow(item.Pane, obj.UI.Detection.MethodDropDown);

            obj.addLabel(item.Pane, "Disk Radius");
            obj.UI.Detection.DiskRadius = obj.numericField(item.Pane, 1);

            obj.addLabel(item.Pane, "H");
            obj.UI.Detection.H = obj.numericField(item.Pane, 0.05);

            obj.addLabel(item.Pane, "Sigma");
            obj.UI.Detection.Sigma = obj.numericField(item.Pane, 1.5);

            obj.addLabel(item.Pane, "Sigma 1");
            obj.UI.Detection.Sigma1 = obj.numericField(item.Pane, 1);

            obj.addLabel(item.Pane, "Sigma 2");
            obj.UI.Detection.Sigma2 = obj.numericField(item.Pane, 2);

            obj.addLabel(item.Pane, "Min Response");
            obj.UI.Detection.MinResponse = obj.numericField(item.Pane, 0);

            obj.addLabel(item.Pane, "Min Distance");
            obj.UI.Detection.MinDistance = obj.numericField(item.Pane, 3);

            obj.addLabel(item.Pane, "Max Points");
            obj.UI.Detection.MaxNumPoints = obj.numericField(item.Pane, Inf);

            obj.addLabel(item.Pane, "SURF Threshold");
            obj.UI.Detection.MetricThreshold = obj.numericField(item.Pane, 50);

            obj.addLabel(item.Pane, "SURF Octaves");
            obj.UI.Detection.NumOctaves = obj.numericField(item.Pane, 3);

            obj.addLabel(item.Pane, "SURF Scales");
            obj.UI.Detection.NumScaleLevels = obj.numericField(item.Pane, 3);

            obj.UI.Detection.RunButton = uibutton(item.Pane, ...
                "Text", "Run Detection", ...
                "ButtonPushedFcn", @(~,~) obj.runDetection());
            obj.UI.Detection.RunButton.Layout.Row = 13;
            obj.UI.Detection.RunButton.Layout.Column = [1 2];
        end

        function setupClusteringControls(obj)
        %SETUPCLUSTERINGCONTROLS Create initial clustering controls.
            item = obj.SettingsAccordion.getItem("Clustering");
            obj.configurePaneGrid(item.Pane, 5);

            obj.addLabel(item.Pane, "Method");
            obj.UI.Clustering.MethodDropDown = uidropdown(item.Pane, ...
                "Items", {'dbscan','kmeans'}, ...
                "Value", "dbscan");
            matlabx.app.PointClusterTuner.placeInCurrentRow(item.Pane, obj.UI.Clustering.MethodDropDown);

            obj.addLabel(item.Pane, "Min Points");
            obj.UI.Clustering.MinPoints = obj.numericField(item.Pane, 5);

            obj.addLabel(item.Pane, "K");
            obj.UI.Clustering.K = obj.numericField(item.Pane, 2);

            obj.addLabel(item.Pane, "Recluster");
            obj.UI.Clustering.Recluster = uidropdown(item.Pane, ...
                "Items", {'false','true'}, ...
                "ItemsData", {false,true}, ...
                "Value", false);
            matlabx.app.PointClusterTuner.placeInCurrentRow(item.Pane, obj.UI.Clustering.Recluster);

            obj.UI.Clustering.RunButton = uibutton(item.Pane, ...
                "Text", "Run Clustering", ...
                "ButtonPushedFcn", @(~,~) obj.runClustering());
            obj.UI.Clustering.RunButton.Layout.Row = 5;
            obj.UI.Clustering.RunButton.Layout.Column = [1 2];
        end

        function setupPointRefinementControls(obj)
        %SETUPPOINTREFINEMENTCONTROLS Create within-cluster refinement controls.
            item = obj.SettingsAccordion.getItem("Point Refinement");
            obj.configurePaneGrid(item.Pane, 7);

            obj.addLabel(item.Pane, "Method");
            obj.UI.RefinePoints.MethodDropDown = uidropdown(item.Pane, ...
                "Items", {'dbscan','nnDistance','nnSupport'}, ...
                "Value", "nnDistance");
            matlabx.app.PointClusterTuner.placeInCurrentRow(item.Pane, obj.UI.RefinePoints.MethodDropDown);

            obj.addLabel(item.Pane, "Min Points");
            obj.UI.RefinePoints.MinPoints = obj.numericField(item.Pane, 3);

            obj.addLabel(item.Pane, "Sigma Factor");
            obj.UI.RefinePoints.SigmaFactor = obj.numericField(item.Pane, 2.5);

            obj.addLabel(item.Pane, "Min Support");
            obj.UI.RefinePoints.MinSupport = obj.numericField(item.Pane, 4);

            obj.addLabel(item.Pane, "Radius Factor");
            obj.UI.RefinePoints.RadiusFactor = obj.numericField(item.Pane, 4);

            obj.addLabel(item.Pane, "Recluster After");
            obj.UI.RefinePoints.Recluster = uidropdown(item.Pane, ...
                "Items", {'false','true'}, ...
                "ItemsData", {false,true}, ...
                "Value", false);
            matlabx.app.PointClusterTuner.placeInCurrentRow(item.Pane, obj.UI.RefinePoints.Recluster);

            obj.UI.RefinePoints.RunButton = uibutton(item.Pane, ...
                "Text", "Refine Points", ...
                "ButtonPushedFcn", @(~,~) obj.runPointRefinement());
            obj.UI.RefinePoints.RunButton.Layout.Row = 7;
            obj.UI.RefinePoints.RunButton.Layout.Column = [1 2];
        end

        function setupClusterFilteringControls(obj)
        %SETUPCLUSTERFILTERINGCONTROLS Create one-property filtering controls.
            item = obj.SettingsAccordion.getItem("Cluster Filtering");
            obj.configurePaneGrid(item.Pane, 5);

            obj.addLabel(item.Pane, "Property");
            obj.UI.Filter.PropertyDropDown = uidropdown(item.Pane, ...
                "Items", {'nPoints','PointDensity','HullArea','Compactness', ...
                    'Eccentricity','NNMedian','NNDispersion','DistanceSD', ...
                    'DistTailRatio','Anisotropy'}, ...
                "Value", "Eccentricity");
            matlabx.app.PointClusterTuner.placeInCurrentRow(item.Pane, obj.UI.Filter.PropertyDropDown);

            obj.addLabel(item.Pane, "Min");
            obj.UI.Filter.MinValue = obj.numericField(item.Pane, -Inf);

            obj.addLabel(item.Pane, "Max");
            obj.UI.Filter.MaxValue = obj.numericField(item.Pane, 0.98);

            obj.UI.Filter.RunButton = uibutton(item.Pane, ...
                "Text", "Apply Filter", ...
                "ButtonPushedFcn", @(~,~) obj.runClusterFilter());
            obj.UI.Filter.RunButton.Layout.Row = 4;
            obj.UI.Filter.RunButton.Layout.Column = [1 2];

            obj.UI.Filter.RefineButton = uibutton(item.Pane, ...
                "Text", "Run Default Filters", ...
                "ButtonPushedFcn", @(~,~) obj.runDefaultClusterFilters());
            obj.UI.Filter.RefineButton.Layout.Row = 5;
            obj.UI.Filter.RefineButton.Layout.Column = [1 2];
        end

        function setupDisplayControls(obj)
        %SETUPDISPLAYCONTROLS Create overlay and stage display controls.
            item = obj.SettingsAccordion.getItem("Display");
            obj.configurePaneGrid(item.Pane, 10);

            obj.addLabel(item.Pane, "Stage");
            obj.UI.Display.StageDropDown = uidropdown(item.Pane, ...
                "Items", {'Live'}, ...
                "Value", "Live", ...
                "ValueChangedFcn", @(~,~) obj.refreshClusterOverlay());
            matlabx.app.PointClusterTuner.placeInCurrentRow(item.Pane, obj.UI.Display.StageDropDown);

            obj.addLabel(item.Pane, "Detections");
            obj.UI.Display.ShowDetections = obj.onOffDropDown(item.Pane, "on", @(~,~) obj.refreshDetectionOverlay());

            obj.addLabel(item.Pane, "Original Points");
            obj.UI.Display.ShowOriginalPoints = obj.onOffDropDown(item.Pane, "off", @(~,~) obj.refreshClusterOverlay());

            obj.addLabel(item.Pane, "Cluster Points");
            obj.UI.Display.ShowClusteredPoints = obj.onOffDropDown(item.Pane, "on", @(~,~) obj.refreshClusterOverlay());

            obj.addLabel(item.Pane, "Hulls");
            obj.UI.Display.ShowHulls = obj.onOffDropDown(item.Pane, "on", @(~,~) obj.refreshClusterOverlay());

            obj.addLabel(item.Pane, "Centroids");
            obj.UI.Display.ShowCentroids = obj.onOffDropDown(item.Pane, "on", @(~,~) obj.refreshClusterOverlay());

            obj.addLabel(item.Pane, "Labels");
            obj.UI.Display.ShowLabels = obj.onOffDropDown(item.Pane, "off", @(~,~) obj.refreshClusterOverlay());

            obj.addLabel(item.Pane, "Noise Points");
            obj.UI.Display.ShowNoisePoints = obj.onOffDropDown(item.Pane, "on", @(~,~) obj.refreshClusterOverlay());

            obj.addLabel(item.Pane, "Removed Points");
            obj.UI.Display.ShowRemovedPoints = obj.onOffDropDown(item.Pane, "on", @(~,~) obj.refreshClusterOverlay());

            obj.addLabel(item.Pane, "Removed Clusters");
            obj.UI.Display.ShowRemovedClusters = obj.onOffDropDown(item.Pane, "on", @(~,~) obj.refreshClusterOverlay());
        end

        function setupPipelineControls(obj)
        %SETUPPIPELINECONTROLS Create whole-pipeline action buttons.
            item = obj.SettingsAccordion.getItem("Pipeline");
            obj.configurePaneGrid(item.Pane, 5);

            obj.UI.Pipeline.RunAllButton = uibutton(item.Pane, ...
                "Text", "Run Detection + Clustering", ...
                "ButtonPushedFcn", @(~,~) obj.runDetectionAndClustering());
            obj.UI.Pipeline.RunAllButton.Layout.Row = 1;
            obj.UI.Pipeline.RunAllButton.Layout.Column = [1 2];

            obj.UI.Pipeline.ResetButton = uibutton(item.Pane, ...
                "Text", "Reset Analysis", ...
                "ButtonPushedFcn", @(~,~) obj.resetAnalysis());
            obj.UI.Pipeline.ResetButton.Layout.Row = 2;
            obj.UI.Pipeline.ResetButton.Layout.Column = [1 2];

            obj.UI.Pipeline.HistoryButton = uibutton(item.Pane, ...
                "Text", "Show History", ...
                "ButtonPushedFcn", @(~,~) obj.showHistory());
            obj.UI.Pipeline.HistoryButton.Layout.Row = 3;
            obj.UI.Pipeline.HistoryButton.Layout.Column = [1 2];
        end

        function setupViewer(obj)
        %SETUPVIEWER Create the ImageAxes preview panel.
            obj.ViewerPanel = uipanel(obj.CenterGrid, ...
                "Title", "Cluster Preview", ...
                "BackgroundColor", [0.12 0.12 0.12], ...
                "ForegroundColor", [0.85 0.85 0.85]);

            obj.ViewerGrid = uigridlayout(obj.ViewerPanel, [1 1], ...
                "ColumnWidth", {"1x"}, ...
                "RowHeight", {"1x"}, ...
                "Padding", [0 0 0 0]);

            obj.Ax = matlabx.ui.axes.ImageAxes(obj.ViewerGrid, ...
                "Name", "PointClusterTuner", ...
                "CData", [], ...
                "Tools", {'Zoom','Colorbar'}, ...
                "Colormap", turbo, ...
                "CLim", [0 1]);
        end

        function setupSummary(obj)
        %SETUPSUMMARY Create cluster metrics table and status output.
            obj.SummaryPanel = uipanel(obj.RightGrid, ...
                "Title", "Cluster Metrics", ...
                "BackgroundColor", [0.12 0.12 0.12], ...
                "ForegroundColor", [0.85 0.85 0.85]);
            obj.SummaryPanel.Layout.Row = 1;

            obj.SummaryGrid = uigridlayout(obj.SummaryPanel, [1 1], ...
                "ColumnWidth", {"1x"}, ...
                "RowHeight", {"1x"}, ...
                "Padding", [0 0 0 0]);

            obj.ClusterTable = uitable(obj.SummaryGrid, ...
                "Data", table(), ...
                "ColumnName", {});

            obj.StatusText = uitextarea(obj.RightGrid, ...
                "Editable", "off", ...
                "FontName", "Courier New", ...
                "Value", {'Ready.'});
            obj.StatusText.Layout.Row = 2;
        end
    end

    methods (Access=private)
        function onLoadImage(obj)
        %ONLOADIMAGE Load an image through Image5D file selection.
            try
                img = matlabx.image.Image5D.fromFileDialog("LoadOnCreate", true);
                obj.setImage(img, "Loaded image");
            catch ME
                obj.reportException(ME);
            end
        end

        function onUseDemoImage(obj)
        %ONUSEDEMOIMAGE Replace the current image with a synthetic demo image.
            obj.setImage(obj.makeDemoImage_(), "Demo puncta image");
        end

        function setImage(obj, imageData, description)
        %SETIMAGE Store image data, extract a display plane, and reset analysis.
            arguments
                obj
                imageData
                description (1,1) string
            end

            obj.ImageData = imageData;
            obj.ImageSourceDescription = description;
            obj.ImagePlane = obj.extractPlane(imageData);

            obj.Ax.CData = obj.ImagePlane;
            clim = obj.imageCLim(obj.ImagePlane);
            obj.Ax.CLim = clim;
            if diff(clim) == 0
                obj.Ax.CLim = [0 1];
            end

            obj.resetAnalysis();
            obj.UI.Input.ImageLabel.Text = sprintf("%s | %dx%d", ...
                description, size(obj.ImagePlane,2), size(obj.ImagePlane,1));
            obj.UI.Input.PlaneLabel.Text = obj.describePlane(imageData);
            obj.appendStatus("Loaded " + obj.UI.Input.ImageLabel.Text + ".");
        end

        function runDetectionAndClustering(obj)
        %RUNDETECTIONANDCLUSTERING Run the two most common first-pass stages.
            obj.runDetection();
            obj.runClustering();
        end

        function runDetection(obj)
        %RUNDETECTION Detect puncta and refresh the point overlay.
            try
                if isempty(obj.ImagePlane)
                    return
                end

                method = string(obj.UI.Detection.MethodDropDown.Value);
                [points,info] = matlabx.image.measure.detectPoints(obj.ImagePlane, ...
                    "Method", method, ...
                    "DiskRadius", obj.UI.Detection.DiskRadius.Value, ...
                    "H", obj.UI.Detection.H.Value, ...
                    "Sigma", obj.UI.Detection.Sigma.Value, ...
                    "Sigma1", obj.UI.Detection.Sigma1.Value, ...
                    "Sigma2", obj.UI.Detection.Sigma2.Value, ...
                    "MinResponse", obj.UI.Detection.MinResponse.Value, ...
                    "MinDistance", obj.UI.Detection.MinDistance.Value, ...
                    "MaxNumPoints", obj.UI.Detection.MaxNumPoints.Value, ...
                    "MetricThreshold", obj.UI.Detection.MetricThreshold.Value, ...
                    "NumOctaves", obj.UI.Detection.NumOctaves.Value, ...
                    "NumScaleLevels", obj.UI.Detection.NumScaleLevels.Value);

                obj.DetectionPoints = points;
                obj.DetectionInfo = info;
                obj.clearClusters();
                obj.refreshDetectionOverlay();
                obj.refreshClusterOverlay();
                obj.refreshTable();
                obj.appendStatus(sprintf("Detection: %s returned %d point(s).", ...
                    info.DisplayName, size(points,1)));
            catch ME
                obj.reportException(ME);
            end
        end

        function runClustering(obj)
        %RUNCLUSTERING Build initial clusters from detected points.
            try
                if isempty(obj.DetectionPoints)
                    obj.runDetection();
                end
                if isempty(obj.DetectionPoints)
                    return
                end

                method = char(obj.UI.Clustering.MethodDropDown.Value);
                obj.Clusters = matlabx.analysis.cluster.PointClusters( ...
                    obj.DetectionPoints, ...
                    "ClusterMethod", method, ...
                    "MinPointsPerCluster", obj.UI.Clustering.MinPoints.Value, ...
                    "k", obj.UI.Clustering.K.Value, ...
                    "Recluster", obj.UI.Clustering.Recluster.Value, ...
                    "RefinePoints", false, ...
                    "RefineClusters", false);

                obj.refreshStageDropDown();
                obj.refreshClusterOverlay();
                obj.refreshTable();
                obj.appendStatus(sprintf("Clustering: %d cluster(s), %d noise/unclustered point(s).", ...
                    obj.Clusters.nClusters, size(obj.Clusters.UnclusteredPoints,1)));
            catch ME
                obj.reportException(ME);
            end
        end

        function runPointRefinement(obj)
        %RUNPOINTREFINEMENT Remove suspect points within each live cluster.
            try
                if isempty(obj.Clusters) || ~isvalid(obj.Clusters)
                    obj.runClustering();
                end
                if isempty(obj.Clusters) || ~isvalid(obj.Clusters)
                    return
                end

                removed = obj.Clusters.refinePoints( ...
                    "Method", char(obj.UI.RefinePoints.MethodDropDown.Value), ...
                    "MinPoints", obj.UI.RefinePoints.MinPoints.Value, ...
                    "SigmaFactor", obj.UI.RefinePoints.SigmaFactor.Value, ...
                    "MinSupport", obj.UI.RefinePoints.MinSupport.Value, ...
                    "RadiusFactor", obj.UI.RefinePoints.RadiusFactor.Value);

                if obj.UI.RefinePoints.Recluster.Value
                    obj.Clusters.recluster("ClusterMethod", char(obj.UI.Clustering.MethodDropDown.Value));
                end

                obj.refreshStageDropDown();
                obj.refreshClusterOverlay();
                obj.refreshTable();
                obj.appendStatus(sprintf("Point refinement removed %d point(s).", height(removed)));
            catch ME
                obj.reportException(ME);
            end
        end

        function runClusterFilter(obj)
        %RUNCLUSTERFILTER Apply one property-threshold cluster filter.
            try
                if isempty(obj.Clusters) || ~isvalid(obj.Clusters)
                    return
                end

                prop = char(obj.UI.Filter.PropertyDropDown.Value);
                thresh = [obj.UI.Filter.MinValue.Value obj.UI.Filter.MaxValue.Value];
                removed = obj.Clusters.filterByProperty(prop, thresh, ...
                    "StageName", "FilteredClusters", ...
                    "Reason", "ManualFilter");

                obj.refreshStageDropDown();
                obj.refreshClusterOverlay();
                obj.refreshTable();
                obj.appendStatus(sprintf("Filter %s [%g %g] removed %d cluster(s).", ...
                    prop, thresh(1), thresh(2), height(removed)));
            catch ME
                obj.reportException(ME);
            end
        end

        function runDefaultClusterFilters(obj)
        %RUNDEFAULTCLUSTERFILTERS Apply PointClusters built-in quality filters.
            try
                if isempty(obj.Clusters) || ~isvalid(obj.Clusters)
                    return
                end

                obj.Clusters.MinPointsPerCluster = obj.UI.Clustering.MinPoints.Value;
                removed = obj.Clusters.refineClusters();
                obj.refreshStageDropDown();
                obj.refreshClusterOverlay();
                obj.refreshTable();
                obj.appendStatus(sprintf("Default cluster filters removed %d cluster(s).", height(removed)));
            catch ME
                obj.reportException(ME);
            end
        end

        function resetAnalysis(obj)
        %RESETANALYSIS Clear detections, clusters, overlays, and tables.
            obj.DetectionPoints = zeros(0,2);
            obj.DetectionInfo = struct();
            obj.clearClusters();
            obj.removeOverlay("DetectionOverlay");
            obj.removeOverlay("ClusterOverlay");
            obj.refreshStageDropDown();
            obj.refreshTable();
            obj.appendStatus("Analysis reset.");
        end

        function clearClusters(obj)
        %CLEARCLUSTERS Delete current cluster model.
            if ~isempty(obj.Clusters) && isvalid(obj.Clusters)
                delete(obj.Clusters);
            end
            obj.Clusters = matlabx.analysis.cluster.PointClusters.empty();
        end

        function showHistory(obj)
        %SHOWHISTORY Open a text window with model history and detector info.
            lines = strings(0,1);
            lines(end+1) = "Point Cluster Tuner";
            lines(end+1) = "";

            if isfield(obj.DetectionInfo, "Method")
                lines(end+1) = "Detection";
                lines(end+1) = matlabx.struct.prettyPrint(obj.DetectionInfo.Parameters);
                lines(end+1) = "";
            end

            if ~isempty(obj.Clusters) && isvalid(obj.Clusters)
                lines(end+1) = "History";
                lines(end+1) = evalc("disp(obj.Clusters.getHistoryTable())");
            else
                lines(end+1) = "No cluster history yet.";
            end

            matlabx.app.TextWindow( ...
                "Title", "Point Cluster Tuner History", ...
                "Text", cellstr(lines), ...
                "Position", [100 100 700 500]);
        end
    end

    methods (Access=private)
        function refreshDetectionOverlay(obj)
        %REFRESHDETECTIONOVERLAY Create/update the PointSet detection overlay.
            if isempty(obj.DetectionPoints)
                obj.removeOverlay("DetectionOverlay");
                return
            end

            show = obj.UI.Display.ShowDetections.Value;
            if isempty(obj.DetectionOverlay) || ~isvalid(obj.DetectionOverlay)
                obj.DetectionOverlay = obj.Ax.Overlays.add("PointSet", ...
                    "ID", "PointClusterTunerDetections", ...
                    "Label", "Detected puncta", ...
                    "Points", obj.DetectionPoints, ...
                    "Marker", "o", ...
                    "MarkerSize", 5, ...
                    "MarkerEdgeColor", [1 1 0], ...
                    "MarkerFaceColor", "none", ...
                    "Visible", show);
            else
                obj.DetectionOverlay.Points = obj.DetectionPoints;
                obj.DetectionOverlay.Visible = show;
            end
        end

        function refreshClusterOverlay(obj)
        %REFRESHCLUSTEROVERLAY Create/update the PointClusters overlay.
            if obj.IsRefreshingUI
                return
            end

            if isempty(obj.Clusters) || ~isvalid(obj.Clusters)
                obj.removeOverlay("ClusterOverlay");
                return
            end

            stageName = string(obj.UI.Display.StageDropDown.Value);
            if stageName == "Live"
                stageName = "";
            end

            if isempty(obj.ClusterOverlay) || ~isvalid(obj.ClusterOverlay)
                obj.ClusterOverlay = obj.Ax.Overlays.add("PointClusters", ...
                    "ID", "PointClusterTunerClusters", ...
                    "ClusterData", obj.Clusters);
            end

            obj.ClusterOverlay.StageName = stageName;
            obj.ClusterOverlay.ShowOriginalPoints = obj.UI.Display.ShowOriginalPoints.Value;
            obj.ClusterOverlay.ShowClusteredPoints = obj.UI.Display.ShowClusteredPoints.Value;
            obj.ClusterOverlay.ShowHulls = obj.UI.Display.ShowHulls.Value;
            obj.ClusterOverlay.ShowCentroids = obj.UI.Display.ShowCentroids.Value;
            obj.ClusterOverlay.ShowLabels = obj.UI.Display.ShowLabels.Value;
            obj.ClusterOverlay.ShowNoisePoints = obj.UI.Display.ShowNoisePoints.Value;
            obj.ClusterOverlay.ShowRemovedPoints = obj.UI.Display.ShowRemovedPoints.Value;
            obj.ClusterOverlay.ShowRemovedClusters = obj.UI.Display.ShowRemovedClusters.Value;
            obj.ClusterOverlay.refresh();
        end

        function refreshStageDropDown(obj)
        %REFRESHSTAGEDROPDOWN Rebuild stage list from current cluster snapshots.
            obj.IsRefreshingUI = true;

            items = "Live";
            if ~isempty(obj.Clusters) && isvalid(obj.Clusters)
                items = [items, obj.Clusters.StageNames];
            end

            obj.UI.Display.StageDropDown.Items = cellstr(items);
            if ~any(string(obj.UI.Display.StageDropDown.Value) == items)
                obj.UI.Display.StageDropDown.Value = "Live";
            end

            obj.IsRefreshingUI = false;
        end

        function refreshTable(obj)
        %REFRESHTABLE Update the metrics table from live clusters.
            if isempty(obj.Clusters) || ~isvalid(obj.Clusters)
                obj.ClusterTable.Data = table();
                obj.ClusterTable.ColumnName = {};
                return
            end

            T = obj.Clusters.Summary;
            obj.ClusterTable.Data = T;
            obj.ClusterTable.ColumnName = T.Properties.VariableNames;
        end

        function refreshMethodControls(obj)
        %REFRESHMETHODCONTROLS Enable the controls used by the active detector.
            if isempty(obj.UI) || ~isfield(obj.UI, "Detection")
                return
            end

            method = string(obj.UI.Detection.MethodDropDown.Value);
            fields = ["DiskRadius","H","Sigma","Sigma1","Sigma2", ...
                "MinResponse","MinDistance","MaxNumPoints", ...
                "MetricThreshold","NumOctaves","NumScaleLevels"];
            for f = fields
                obj.UI.Detection.(f).Enable = "off";
            end

            switch method
                case "regionalMaxima"
                    on = "DiskRadius";
                case "extendedMaxima"
                    on = ["H","Sigma","MinDistance","MaxNumPoints"];
                case "surf"
                    on = ["MetricThreshold","NumOctaves","NumScaleLevels"];
                case "log"
                    on = ["Sigma","MinResponse","MinDistance","MaxNumPoints"];
                case "dog"
                    on = ["Sigma1","Sigma2","MinResponse","MinDistance","MaxNumPoints"];
            end

            for f = on
                obj.UI.Detection.(f).Enable = "on";
            end
        end
    end

    methods (Access=private)
        function removeOverlay(obj, whichOverlay)
        %REMOVEOVERLAY Remove a stored overlay from the ImageAxes manager.
            overlay = obj.(whichOverlay);
            if isempty(overlay) || ~isvalid(overlay)
                obj.(whichOverlay) = matlabx.ui.axes.ImageAxesOverlay.empty();
                return
            end

            obj.Ax.Overlays.remove(overlay.ID);
            obj.(whichOverlay) = matlabx.ui.axes.ImageAxesOverlay.empty();
        end

        function appendStatus(obj, msg)
        %APPENDSTATUS Append one line to the status text area.
            if isempty(obj.StatusText) || ~isvalid(obj.StatusText)
                return
            end

            lines = string(obj.StatusText.Value);
            lines(end+1) = string(msg);
            maxLines = 80;
            if numel(lines) > maxLines
                lines = lines(end-maxLines+1:end);
            end
            obj.StatusText.Value = cellstr(lines);
        end

        function reportException(obj, ME)
        %REPORTEXCEPTION Log and display a concise error status.
            matlabx.Log.EXCEPTION(ME);
            obj.appendStatus("ERROR: " + string(ME.message));
        end

        function I = extractPlane(~, imageData)
        %EXTRACTPLANE Convert supported image input to one 2-D tuning plane.
            if isa(imageData, "matlabx.image.Image5D")
                I = imageData.getPlane(1, 1, 1);
            else
                I = imageData;
            end

            if ~ismatrix(I)
                I = I(:,:,1);
            end

            if ~isa(I, "double")
                I = im2double(I);
            end
            I = rescale(I);
        end

        function txt = describePlane(~, imageData)
        %DESCRIBEPLANE Return short text for the displayed C/Z/T plane.
            if isa(imageData, "matlabx.image.Image5D")
                txt = sprintf("C1 Z1 T1 | size [%d %d %d %d %d]", imageData.Size);
            else
                txt = "2-D image";
            end
        end

        function clim = imageCLim(~, I)
        %IMAGECLIM Return finite display limits for the current image plane.
            vals = I(isfinite(I));
            if isempty(vals)
                clim = [0 1];
            else
                clim = double([min(vals(:)) max(vals(:))]);
            end
        end
    end

    methods (Access=private)
        function configurePaneGrid(obj, pane, nRows)
        %CONFIGUREPANEGRID Apply the app's standard accordion pane layout.
            set(pane, ...
                "RowHeight", repmat({'fit'},1,nRows), ...
                "ColumnWidth", {'fit','1x'}, ...
                "RowSpacing", obj.Padding, ...
                "ColumnSpacing", obj.Padding);
        end

        function h = addLabel(obj, parent, text)
        %ADDLABEL Add a standard left-column settings label.
            row = obj.nextGridRow(parent);
            setappdata(parent, "matlabxPointClusterTunerCurrentRow", row);
            h = uilabel(parent, ...
                "Text", text, ...
                "FontColor", [0.85 0.85 0.85], ...
                "FontSize", obj.FontSize);
            h.Layout.Row = row;
            h.Layout.Column = 1;
        end

        function h = numericField(~, parent, value)
        %NUMERICFIELD Add a standard numeric edit field in the current row.
            h = uieditfield(parent, "numeric", "Value", value);
            matlabx.app.PointClusterTuner.placeInCurrentRow(parent, h);
        end

        function h = onOffDropDown(~, parent, value, callback)
        %ONOFFDROPDOWN Add a standard on/off dropdown in the current row.
            h = uidropdown(parent, ...
                "Items", {'on','off'}, ...
                "Value", char(value), ...
                "ValueChangedFcn", callback);
            matlabx.app.PointClusterTuner.placeInCurrentRow(parent, h);
        end

        function row = nextGridRow(~, parent)
        %NEXTGRIDROW Return the next one-based row for a pane child.
            if isempty(parent.Children)
                row = 1;
            else
                rows = arrayfun(@(h) h.Layout.Row, parent.Children);
                row = max(rows) + 1;
            end
        end
    end

    methods (Static, Access=private)
        function placeInCurrentRow(parent, h)
        %PLACEINCURRENTROW Put a control beside the most recently added label.
            row = getappdata(parent, "matlabxPointClusterTunerCurrentRow");
            if isempty(row)
                row = 1;
            end

            h.Layout.Row = row;
            h.Layout.Column = 2;
        end

        function I = makeDemoImage_()
        %MAKEDEMOIMAGE_ Generate a small synthetic puncta-like image.
            oldRng = rng(1);
            restoreRng = onCleanup(@() rng(oldRng));
            sz = [512 512];
            I = zeros(sz);
            nClusters = 16;

            [X,Y] = meshgrid(1:sz(2), 1:sz(1));
            for c = 1:nClusters
                center = [randi([60 452]) randi([60 452])];
                nPts = randi([8 24]);
                spread = 5 + 8*rand();

                for p = 1:nPts
                    xy = center + spread*randn(1,2);
                    amp = 0.6 + 0.5*rand();
                    sigma = 1.0 + 0.8*rand();
                    I = I + amp .* exp(-((X-xy(1)).^2 + (Y-xy(2)).^2) ./ (2*sigma.^2));
                end
            end

            % Add a handful of isolated detections and mild background noise so
            % detector/clustering parameters have something to negotiate.
            for k = 1:60
                xy = [randi(sz(2)) randi(sz(1))];
                I(xy(2),xy(1)) = I(xy(2),xy(1)) + 0.6*rand();
            end
            I = imgaussfilt(I, 0.7) + 0.04*randn(sz);
            I = rescale(I);
            delete(restoreRng);
        end
    end
end
