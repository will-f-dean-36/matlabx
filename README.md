# matlabx

matlabx is a MATLAB framework for building richer apps, image viewers, and analysis tools. It is being developed primarily to extend MATLAB's app-building and graphics ecosystem with better image display, more flexible interaction, reusable UI components, and small complete apps built from those pieces.

The project is under active development. APIs may still move as the package gets sharper.

> Note: matlabx is an independent project and is not affiliated with or endorsed by MathWorks.

## What It Offers

- `matlabx.ui.axes.ImageAxes`, an `Image5D`-backed image display component for MATLAB apps
- Multi-component, Z-stack, and time-series image handling through `matlabx.image.Image5D`
- Bio-Formats-backed image loading for many microscopy and proprietary image formats
- Pluggable axes tools such as zoom, colorbar, colormap selection, box regions, and rectangle drawing
- Figure-level event routing with normalized mouse, scroll, key, drag, hover, modifier, and hotkey state
- First-pass overlay system for image-space graphics such as boxes, lines, point sets, and cluster visualizations
- Point detection, point clustering, and an early tuning app for puncta/feature clustering workflows
- Custom UI containers and controls not currently available as MATLAB built-ins
- Small apps and dialogs including `matlabx.app.Viewer5D`, `matlabx.app.PointClusterTuner`, `matlabx.app.ParamsDialog`, `matlabx.app.TextWindow`, and quick image viewers
- Logging, settings, machine-state persistence, UI calibration, colors, file/path helpers, keyboard helpers, and general utilities

## Package Map

- `matlabx.ui.axes`: axes-backed visual components, tools, context-menu helpers, and display collaborators
- `matlabx.ui.container`: custom container-style components
- `matlabx.ui.control`: custom value/input controls
- `matlabx.ui.interaction`: event hubs, command routing, and interaction plumbing
- `matlabx.ui.calibration`: screen and UI measurement helpers
- `matlabx.app`: complete apps and dialogs
- `matlabx.analysis.cluster`: point-clustering models, refinement helpers, and cluster metrics
- `matlabx.image`: image data models, IO, processing, masks, ROIs, and measurement helpers
- `matlabx.config`: user settings and machine-local state
- `matlabx.logging`: structured logging
- `matlabx.colors`, `matlabx.files`, `matlabx.keyboard`, `matlabx.struct`, `matlabx.string`, `matlabx.utils`: supporting utilities

## Installation And Setup

Clone or place this repository somewhere stable, then add the repository root to the MATLAB path:

```matlab
addpath('/path/to/matlabx')
```

For a new install, run:

```matlab
matlabx.setup.run()
```

That setup routine:

- adds the matlabx root and bundled external libraries to the MATLAB path
- configures the bundled Bio-Formats dependency
- runs UI calibration
- saves the MATLAB path

For a lighter manual setup, run pieces individually:

```matlab
matlabx.setup.searchPath()
matlabx.setup.bioFormats()
matlabx.setup.uiCalibration()
```

The setup and settings files use MATLAB's `prefdir` under a `matlabx` folder.

## Quick Usage

Show an image quickly:

```matlab
I = imread("rice.png");
[ax, fig] = matlabx.app.quickshow(I);
```

Open the 5D image viewer:

```matlab
I = matlabx.image.Image5D.fromComponents({imread("rice.png")});
viewer = matlabx.app.Viewer5D(I);
```

Open the point-clustering tuning app:

```matlab
app = matlabx.app.PointClusterTuner();
```

Use `ImageAxes` directly in a UI:

```matlab
fig = uifigure;
ax = matlabx.ui.axes.ImageAxes(fig, ...
    "CData", imread("rice.png"), ...
    "Tools", {'Zoom', 'Colorbar', 'ChooseColormap'});
```

Create a demo multi-component image:

```matlab
I = matlabx.image.Image5D.demo(256, 256, 3, 10, 10, 'uint16');
[ax, fig] = matlabx.app.quickshow(I, "ComponentColorMode", "colors");
```

## Image5D

`matlabx.image.Image5D` is the image-data normalization layer used by `ImageAxes` and `Viewer5D`. It gives apps a common way to work with images that may come from ordinary MATLAB arrays, component arrays, or file-backed sources.

Create an in-memory image from one or more components:

```matlab
I1 = imread("channel1.tif");
I2 = imread("channel2.tif");
I = matlabx.image.Image5D.fromComponents({I1, I2}, ...
    "Names", ["DAPI", "Actin"]);
```

Load a file through Bio-Formats:

```matlab
I = matlabx.image.Image5D.fromFile("experiment.czi", ...
    "SeriesIndex", 1, ...
    "LoadOnCreate", true);
```

Use a file picker for Bio-Formats-supported images:

```matlab
I = matlabx.image.Image5D.fromFileDialog("LoadOnCreate", true);
```

Useful image metadata and shape properties include:

```matlab
I.Size
I.NumComponents
I.SizeZ
I.SizeT
I.Components
I.AllMetadata
```

`Image5D` uses components as the primary abstraction. When the components are compatible scalar channels, `ImageAxes` can display individual components or a merged color composite.

## ImageAxes

`matlabx.ui.axes.ImageAxes` is the main reusable image-display component. It is a `matlab.ui.componentcontainer.ComponentContainer` that displays the selected `C/Z/T` plane or composite from an `Image5D` object, manages contrast and component display state, hosts tools, and routes normalized figure events to those tools.

Basic construction:

```matlab
fig = uifigure;
I = matlabx.image.Image5D.demo();

ax = matlabx.ui.axes.ImageAxes(fig, ...
    "ImageData", I, ...
    "Tools", {'Zoom', 'Colorbar', 'ChooseColormap'}, ...
    "Units", "normalized", ...
    "Position", [0 0 1 1]);
```

Navigate through dimensions:

```matlab
ax.C = 2;
ax.Z = 5;
ax.T = 3;
ax.ShowComposite = "on";
```

Set current-component display properties:

```matlab
ax.C = 1;
ax.CLim = [100 2000];
ax.Colormap = gray(256);
```

For targeted per-component edits, prefer the helper methods:

```matlab
ax.setComponentCLim([100 2000]);          % current component
ax.setComponentCLim([100 2000], [1 3]);   % components 1 and 3
ax.setComponentColor("cyan", 1);
ax.setComponentColormap(hot(256), 2);
```

The full-state properties are useful for restoring saved display state or synchronizing axes. They update stored values without automatically changing `ComponentColorMode`:

```matlab
ax.ComponentCLims = {[0 500], [0 800], [0 1200]};
ax.ComponentColors = {'cyan', 'magenta', 'yellow'};
ax.ComponentColormaps{2} = hot(256);
ax.ComponentColorMode = 'colors';  % or 'luts'
```

Viewport/navigation API:

```matlab
S = ax.getViewport();
ax.setViewportCenter([128 256]);
ax.setViewportSize([128 256]);
ax.setZoomFactor(0.5);
ax.resetViewport();
```

`ImageAxes` maintains the image aspect ratio when setting viewport size or limits. The visible viewport and zoom factor are two views of the same underlying navigation state: changing one updates the other. Programmatic viewport changes are center-anchored; interactive zoom gestures are cursor-anchored when possible.

Useful status and diagnostics:

```matlab
ax.openStatusWindow()
status = ax.getStatusSummary();
ax.debug("IncludeSizeDiagnostics", true)
```

## ImageAxes Tools

Tools are installed by assigning names to `ax.Tools`. Reading `ax.Tools` returns the installed tool objects:

```matlab
ax.Tools = ["Zoom", "Box", "DrawRectangle"];
ax.Tools.Box.BoxSize = 40;
```

Available tool names can be queried:

```matlab
matlabx.ui.axes.ImageAxes.getToolNames()
matlabx.ui.axes.ImageAxes.getDefaultTools()
```

Current first-party tools include:

- `Zoom`: zooming, cursor-follow navigation, zoom-level menu, and viewport-box display while active
- `Colorbar`: colorbar display support
- `ChooseColormap`: colormap selection
- `Box`: square box region creation, activation, selection, movement, and deletion
- `Line`: line drawing, endpoint editing, midpoint translation, selection, and deletion
- `DrawRectangle`: one-shot rotated rectangle drawing and measurement annotations

Tool subclasses inherit from `matlabx.ui.axes.AxesTool`. A custom tool usually:

- calls the `AxesTool` constructor with a name, style, icon, hotkey, and routing flags
- overrides lifecycle hooks such as `onInstall`, `onEnabled`, `onDisabled`, or `onPush`
- implements event hooks such as `onDown`, `onMove`, `onScroll`, or passive variants
- optionally contributes context-menu items with `contributeContextMenu`
- optionally contributes help text with `getHelpSummary`, `getUsageHelp`, `getBindingHelp`, and `getNotesHelp`

Minimal custom tool sketch:

```matlab
classdef MyTool < matlabx.ui.axes.AxesTool
    methods
        function obj = MyTool(host)
            obj@matlabx.ui.axes.AxesTool(host, "MyTool", ...
                "Style", "state", ...
                "AxesType", "image", ...
                "ToggleHotkey", matlabx.keyboard.hotkey("m"), ...
                "InterceptsDown", true);
        end

        function onDown(obj, E)
            if E.MouseChord == "click"
                xy = obj.Host.mainAxes.CurrentPoint(1, 1:2);
                disp(xy)
                E.stop()
            end
        end
    end
end
```

Tool hotkeys should be declared with `matlabx.keyboard.hotkey` so tool authors do not need to memorize normalized hotkey string syntax:

```matlab
matlabx.keyboard.hotkey("z", "Modifiers", ["shift", "meta"])
```

## ImageAxes Context Menus

`ImageAxes` owns a context-menu manager that builds a small set of built-in menus and lets tools contribute their own commands. The default menu includes:

- `Status...`
- `Reset View`
- `Image > Properties...`
- `Image > Metadata...`
- `Image > Color Mode`
- `Image > Component Color`
- `Overlays > Viewport Box`
- tool menus such as `Zoom > Level` and `Box > Select All`

Choose which built-ins are available with `ContextMenuItems`:

```matlab
ax.ContextMenuItems = ["Status", "ResetView", "Image", "Overlays"];
matlabx.ui.axes.ImageAxes.getContextMenuItemNames()
```

You can also expose individual built-ins without their parent group:

```matlab
ax.ContextMenuItems = ["ResetView", "ComponentColor", "ViewportBox"];
```

## ImageAxes Overlays

`ImageAxes` owns an overlay manager available as `ax.Overlays`. Overlays are graphics objects tied to image coordinates and C/Z/T applicability. The manager owns overlay lifetime and shared state such as active, hovered, and selected IDs; tools and apps decide what user interactions mean.

Add a point overlay:

```matlab
points = matlabx.image.measure.detectPoints(I, "Method", "log");

ov = ax.Overlays.add("PointSet", ...
    "Points", points, ...
    "Marker", "o", ...
    "MarkerEdgeColor", [0 0 0], ...
    "MarkerFaceColor", [1 1 1]);
```

Add a box or line overlay:

```matlab
box = ax.Overlays.add("Box", ...
    "Center", [128 128], ...
    "BoxSize", 40, ...
    "Label", "ROI 1");

ln = ax.Overlays.add("Line", ...
    "Endpoints", [50 50; 200 120], ...
    "LineColor", [1 1 0]);
```

Visualize cluster-analysis output:

```matlab
C = matlabx.analysis.cluster.PointClusters(points, ...
    "MinPointsPerCluster", 5);

clusterOverlay = ax.Overlays.add("PointClusters", ...
    "ClusterData", C, ...
    "ShowHulls", "on", ...
    "ShowCentroids", "on");
```

Overlay IDs are string identifiers. If the caller does not provide one, overlays generate their own ID:

```matlab
ids = ax.Overlays.ids();
ax.Overlays.setActive(ids(1));
ax.Overlays.setSelected(ids(1:3));
ax.Overlays.remove(ids(1));
```

First-party overlays currently include:

- `matlabx.ui.axes.overlays.Box`
- `matlabx.ui.axes.overlays.Line`
- `matlabx.ui.axes.overlays.PointSet`
- `matlabx.ui.axes.overlays.PointClusters`

The overlay base class is intentionally small. Custom overlays inherit from `matlabx.ui.axes.ImageAxesOverlay`, own their own graphics handles, implement `updateGeometry` and `updateAppearance`, and call `registerGraphics` for hit-test ownership and manager lookup.

## Point Detection And Clustering

`matlabx.image.measure.detectPoints` is a common dispatcher for candidate point detection. It returns an `N x 2` `[x y]` coordinate array and an `info` struct with method-specific diagnostics.

```matlab
[points, info] = matlabx.image.measure.detectPoints(I, ...
    "Method", "log", ...
    "Sigma", 1.5, ...
    "MinDistance", 3);
```

Supported methods include:

- `"regionalMaxima"`: reconstruction/open-close puncta detector implemented by `detectPuncta`
- `"extendedMaxima"`: `imextendedmax`-based detector with an `H` prominence threshold
- `"surf"`: SURF feature detector wrapper around `detectSURFFeatures`
- `"log"`: Laplacian-of-Gaussian blob response plus local maxima
- `"dog"`: Difference-of-Gaussians blob response plus local maxima

Method-specific helpers are available when a direct call is clearer:

```matlab
points = matlabx.image.measure.detectPuncta(I, "DiskRadius", 2);
points = matlabx.image.measure.detectLogPuncta(I, "Sigma", 1.5);
points = matlabx.image.measure.detectDogPuncta(I, "Sigma1", 1, "Sigma2", 2);
points = matlabx.image.measure.detectExtendedMaximaPuncta(I, "H", 0.05);
points = matlabx.image.measure.detectSurfPoints(I, "MetricThreshold", 50);
```

Lower-level processing helpers include:

```matlab
Rlog = matlabx.image.process.laplacianOfGaussian(I, "Sigma", 1.5);
Rdog = matlabx.image.process.differenceOfGaussians(I, "Sigma1", 1, "Sigma2", 2);
[points, mask, values] = matlabx.image.measure.findLocalMaxima(Rlog);
```

Cluster detected points with `matlabx.analysis.cluster.PointClusters`:

```matlab
C = matlabx.analysis.cluster.PointClusters(points, ...
    "ClusterMethod", "dbscan", ...
    "MinPointsPerCluster", 5);

metrics = C.exportClusterMetrics();
```

The constructor performs initial clustering only. Later cleanup is explicit:

```matlab
removedPoints = C.refinePoints("Method", 'nnDistance', "SigmaFactor", 2.5);
C.recluster("ClusterMethod", 'dbscan');
removedClusters = C.filterByProperty('Eccentricity', [0 0.9]);
```

Useful outputs include:

```matlab
C.Summary
C.StageNames
C.getStageSnapshot("Initial")
C.getHistoryTable()
C.RemovedPointLog
C.RemovedClusterLog
```

The early tuning app wires the detector, clustering model, overlays, and metrics table together:

```matlab
app = matlabx.app.PointClusterTuner(I);
```

## Custom Event Routing

MATLAB figure callbacks are powerful, but a growing app can quickly run into conflicts when several components and tools all want mouse, scroll, key, and drag behavior. `matlabx.ui.interaction.FigureEventHub` installs one set of figure-level callbacks and routes normalized `HubEvent` objects to registered components.

The hub handles:

- mouse down, move, up, scroll, key press, and key release events
- priority-based claiming when multiple components match the same event
- optional drag capture so a component keeps receiving move/up events during a drag
- preserved pre-existing callbacks as low-priority listeners
- modifier-state tracking for mouse gestures
- shortcut-style modifier cleanup to avoid stale keys after menu accelerators, dialogs, or interrupted UI interaction

`HubEvent` centralizes event normalization. Useful fields include:

- `Kind`: `"Down"`, `"Move"`, `"Up"`, `"Scroll"`, `"KeyPress"`, or `"KeyRelease"`
- `Target`, `CurrentAxes`, `CurrentObject`, and `CurrentPointFigure`
- `SelectionType`: raw MATLAB click type
- `MouseAction`: normalized action such as `"click"`, `"contextclick"`, `"extendclick"`, `"move"`, `"up"`, or `"scroll"`
- `MouseChord`: modifiers plus action, such as `"meta+click"` or `"shift+extendclick"`
- `Key`, `Character`, `Modifier`, `ModifierState`, and normalized `Hotkey`
- `LastKey`, `LastHotkey`, and `LastKeyTimestamp`
- `VerticalScrollCount`
- `Handled` and `StopPropagation`

Print an event for debugging:

```matlab
E.print()
S = E.toStruct();
```

Registering a component directly:

```matlab
hub = matlabx.ui.interaction.FigureEventHub.ensure(fig);
id = hub.register(myComponent, ...
    "Priority", 10, ...
    "CaptureDuringDrag", true);
```

The registered object implements `matches` and event hooks. `ImageAxes` uses this pattern internally, then routes claimed events to installed tools.

```matlab
function tf = matches(obj, target, kind, E)
    tf = isequal(ancestor(target, "axes"), obj.Axes);
end

function onDown(obj, E)
    if E.MouseChord == "control+contextclick"
        obj.deleteThingUnderCursor(E)
        E.stop()
    end
end
```

This makes interactions possible that are awkward with raw MATLAB figure callbacks, such as simultaneous support for normal click, context click, shift-click selection, control-context-click deletion, modifier-click zoom, scroll zoom, drag capture, and tool-specific hotkeys.

## UI Controls

`matlabx.ui.control.Slider` supports both range and scalar slider behavior. It can show or hide edit fields at construction time.

Create a range slider:

```matlab
fig = uifigure;
g = uigridlayout(fig, [1 1]);

s = matlabx.ui.control.Slider(g, ...
    "Title", "Intensity", ...
    "Limits", [0 255], ...
    "Value", [20 180], ...
    "ShowFill", "on");
```

Create a simple one-thumb slider without edit fields:

```matlab
s = matlabx.ui.control.Slider(g, ...
    "ValueMode", "scalar", ...
    "ShowEditFields", "off", ...
    "ShowFill", "on", ...
    "Limits", [0 100], ...
    "Value", 40);
```

## UI Calibration

Some MATLAB UI measurements vary by platform, display scaling, and release. matlabx stores machine-local calibration data so app sizing and placement can be more predictable.

Run calibration manually with:

```matlab
matlabx.setup.uiCalibration()
```

Load the active calibration object with:

```matlab
cal = matlabx.UICal.get();
```

For common values and measurements, use the `matlabx.UICal` facade:

```matlab
ppi = matlabx.UICal.pixelsPerInch();
px = matlabx.UICal.pt2px(12);
h = matlabx.UICal.panelChromeHeight(14, "FontUnits", "pixels");

matlabx.UICal.print()
```

Cached calibration is checked against the current MATLAB version, display scale, and monitor geometry. If the display setup changes, matlabx will recalibrate automatically when needed. You can force it with:

```matlab
matlabx.UICal.recalibrate()
```

Calibration is stored in machine state, not ordinary user settings, because it describes the current computer/display environment.

## Logging

Use the static logging facade for simple app and library messages:

```matlab
matlabx.Log.INFO("Opening viewer")
matlabx.Log.WARN("Using fallback colormap")
```

The logger stores structured entries in memory and can export them:

```matlab
T = matlabx.Log.asTable();
lines = matlabx.Log.exportText();
```

For more control, get the underlying logger:

```matlab
log = matlabx.Log.get();
log.setFileSink(fullfile(tempdir, "matlabx.log"), true);
log.PrintToCommandWindow = false;
```

Logging policy lives in `matlabx.config.Logging` and can be applied through the facade:

```matlab
matlabx.Log.configure("Level", "INFO", "Detail", "normal")
matlabx.Log.configure("CommandWindowLevel", "INFO", "FileLevel", "DEBUG", "FileDetail", "debug")
matlabx.Log.configure("SourceDetail", "full")
```

`Level` is the minimum emitted level: `DEBUG`, `INFO`, `WARN`, or `ERROR`. `Detail` controls formatted output only; structured entries still retain full data. `SourceDetail` controls compact versus full auto-detected source names. `ShowDebugOutput` is kept for older settings, but new code should use `Level="DEBUG"`.

## Settings And Machine State

User settings are managed by `matlabx.config.Settings` and saved as JSON:

```matlab
settings = matlabx.config.Settings.get();
settings.UI.DefaultFontSize = 14;
settings.Images.DefaultColormap = 'gray';
matlabx.config.Settings.saveActive();
```

For everyday use, the `matlabx.Settings` facade provides one-line get/set helpers:

```matlab
settings = matlabx.Settings.get();

level = matlabx.Settings.Logging("Level");
matlabx.Settings.Logging("Level", "DEBUG");
matlabx.Settings.Logging("Detail", "verbose");

fontSize = matlabx.Settings.UI("DefaultFontSize");
matlabx.Settings.Images("DefaultColormap", 'gray');

matlabx.Settings.save();
```

Print current settings:

```matlab
matlabx.Settings.print()
matlabx.Settings.print("Logging")
```

Reset settings to defaults:

```matlab
matlabx.config.Settings.restore()
```

Machine-local state is for computer-specific values such as calibration:

```matlab
matlabx.config.MachineState.set('LastDataFolder', pwd)
folder = matlabx.config.MachineState.get('LastDataFolder', pwd);
```

Print current machine-local state:

```matlab
matlabx.config.MachineState.print()
matlabx.config.MachineState.print('UICalibration')
```

Useful path helpers:

```matlab
root = matlabx.internal.Paths.root();
settingsFile = matlabx.internal.Paths.settingsFile();
machineStateFile = matlabx.internal.Paths.machineStateFile();
```

## Tips

- Prefer package-qualified names in library code, for example `matlabx.ui.axes.ImageAxes`.
- Prefer `ImageData` over `CData` in new `ImageAxes` code. `CData` remains a convenience/compatibility input for raw MATLAB image arrays.
- Use `matlabx.app.quickshow` for fast inspection and `matlabx.app.Viewer5D` when working with `Image5D`.
- Use `matlabx.keyboard.hotkey` for tool hotkey declarations and compare against normalized `HubEvent.Hotkey` or `HubEvent.MouseChord`.
- Use `matlabx.ui.interaction.FigureEventHub` and `CommandRouter` when an app needs coordinated figure-level mouse/key behavior.
- Use `matlabx.config.Settings` for user preferences and `matlabx.config.MachineState` for machine-specific cached state.
- Use `matlabx.struct.prettyPrint(S, "StringArrayStyle", "lines")` for readable status/help structs that contain string arrays.

## Roadmap

Near-term directions include:

- Continued maturation of the ImageAxes overlay system, including more default overlay types such as polygon/patch overlays
- A clearer public pattern and examples for custom overlay subclasses
- Tool-contributed context menus and help docs with less hardcoding over time
- More custom UI containers, controls, and layout managers
- A customizable data-plotting axes component with the same pluggable tool model as `ImageAxes`
- More example apps built from the reusable UI pieces, including continued refinement of `PointClusterTuner`
- More image-analysis functions for processing, measurement, masks, ROIs, and workflows around `Image5D`
- More point-detection, clustering, and post-clustering cleanup workflows once the tuning model settles
- Serialization/restoration of ImageAxes view and display state
- More polish around setup, documentation, demos, and compatibility checks
