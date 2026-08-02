# matlabx

matlabx is a MATLAB framework for building richer apps and analysis tools. It is being developed primarily to extend MATLAB's app-building and graphics ecosystem with better, more flexible image display and interaction, while also collecting reusable utilities, custom UI components, configuration helpers, and complete apps built on top of those pieces.

The project is under active development. APIs may move as the package gets sharper.

> Note: matlabx is an independent project and is not affiliated with or endorsed by MathWorks.

## What It Offers

- Interactive image display components, centered around `matlabx.ui.axes.ImageAxes`
- Pluggable axes tools such as zoom, colorbar, colormap selection, region picking, and rectangle drawing
- Custom UI containers and controls not currently available as MATLAB built-ins
- Figure-level event routing for custom mouse, scroll, key, drag, and hover interactions
- Small apps built from these components, including `matlabx.app.Viewer5D`, `matlabx.app.ParamsDialog`, slider dialogs, and quick image viewing helpers
- Image data abstractions such as `matlabx.image.Image5D`
- Logging, settings, machine-state persistence, colors, file/path helpers, keyboard helpers, and other general utilities

## Package Map

The package is organized around public roles:

- `matlabx.ui.axes`: axes-backed visual components, axes tools, overlays, and events
- `matlabx.ui.container`: custom container-style components
- `matlabx.ui.control`: custom value/input controls
- `matlabx.ui.interaction`: event hubs, command routing, and interaction plumbing
- `matlabx.ui.calibration`: screen and UI measurement helpers
- `matlabx.app`: complete apps and dialogs
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

If you want a lighter manual setup, you can run pieces individually:

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

Use `ImageAxes` directly in a UI:

```matlab
fig = uifigure;
ax = matlabx.ui.axes.ImageAxes(fig, ...
    "CData", imread("rice.png"), ...
    "ToolBelt", {'Zoom', 'Colorbar', 'ChooseColormap'});
```

Create a range slider control:

```matlab
fig = uifigure;
g = uigridlayout(fig, [1 1]);
s = matlabx.ui.control.Slider(g, ...
    "Title", "Intensity", ...
    "Limits", [0 255], ...
    "Value", [20 180]);
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

Logging policy lives in `matlabx.config.Logging` and can be applied through
the facade:

```matlab
matlabx.Log.configure("Level", "INFO", "Detail", "normal")
matlabx.Log.configure("CommandWindowLevel", "INFO", "FileLevel", "DEBUG", "FileDetail", "debug")
matlabx.Log.configure("SourceDetail", "full")
```

`Level` is the minimum emitted level: `DEBUG`, `INFO`, `WARN`, or `ERROR`.
`Detail` controls formatted output only; structured entries still retain full
data. `SourceDetail` controls compact versus full auto-detected source names.
`ShowDebugOutput` is kept for older settings, but new code should use
`Level="DEBUG"`.

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
- Use `matlabx.app.quickshow` for fast inspection and `matlabx.app.Viewer5D` when working with `Image5D`.
- `ImageAxes` tools live under `matlabx.ui.axes.tools`; tools declare `AxesType` as `"image"`, `"plot"`, or `"both"`.
- Use `matlabx.ui.interaction.FigureEventHub` and `CommandRouter` when an app needs coordinated figure-level mouse/key behavior.
- Use `matlabx.config.Settings` for user preferences and `matlabx.config.MachineState` for machine-specific cached state.

## Roadmap

Near-term directions include:

- More custom UI containers, controls, and layout managers
- A customizable data-plotting axes component with the same pluggable tool model as `ImageAxes`
- More example apps built from the reusable UI pieces
- More image-analysis functions for processing, measurement, masks, ROIs, and workflows around `Image5D`
- More polish around setup, documentation, demos, and compatibility checks
