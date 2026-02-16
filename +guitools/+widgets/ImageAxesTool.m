classdef ImageAxesTool < handle
% widgets.ImageAxesTool - base class for pluggable tools hosted by widgets.ImageAxes
%
% Overview
%
%   Subclasses of ImageAxesTool can be used to create custom toolbar-controlled tools 
%   in an instance of widgets.ImageAxes (the Host). When a tool is registered with the Host,
%   it is added to the Host's ToolRegistry and a custom toolbar 'state' button will be created. 
%   Clicking the button will toggle the Enabled state of the tool. When Enabled or Disabled, 
%   tools set a 'Mode' in the Host. For example, when the 'Zoom' tool is Enabled, it will 
%   set Host.Mode.Zoom=true. Optionally, tools can also be defined to capture window-level 
%   mouse events (i.e. 'Down', 'Move', 'Up', and 'Scroll') from the Host. Tools that can capture
%   at least one of these events are called 'Interceptors' (i.e. IsInterceptor=true). The Host
%   will route each type of event to the correct tool based on a number of rules.
%
%   In general, the event-routing flow is as follows:
%       - An event is routed to the Host via FigureEventHub
%       - The Host finds all Enabled Interceptors that can capture that type of event
%       - The event is routed to the tool with the highest Priority
%
%   Thus, each event is routed only to the highest Priority Interceptor that claims it and 
%   is Enabled. There is also a way for tools to temporarily claim events before they are 
%   forwarded to the Interceptor, even if they are Disabled. These tools are called 
%   'Distractors' (i.e. IsDistractor=true). Before routing an event to the highest priority 
%   Interceptor, the Host will first route the event to EACH Distractor for the current event
%   type, in order of Priority, by calling the tool's onDistractX() method, where X is the type
%   of event. This is especially useful for when tools need to carry out functions even after 
%   being disabled. For example, if a tool draws interactable overlays (e.g. a draggable ROI)
%   in the axes that persist even when Enabled=false, it could still manage their behavior 
%   in the background. 


    properties (SetAccess=protected)
        Host                                                    % widgets.ImageAxes
        Name (1,1) string = ""                                  % name of the tool
        Tooltip (1,:) = ''                                      % tooltip for toolbar buttons
        Icon (1,:) char = guitools.Paths.icons('QuestionMark.png')   % icon for toolbar buttons, question mark by default

        Style (1,:) char {mustBeMember(Style,{'push','state'})} = 'state'

        Priority (1,1) double = 1               % priority for event routiang to tools, highest priority claims event
        IsExclusive (1,1) logical = false       % enabling tool will disable tools with Enabled=true && IsExclusive=true

        CapturesDown (1,1) logical = false      % this tool can capture 'Down' events when Enabled=true
        CapturesMove (1,1) logical = false      % this tool can capture 'Move' events when Enabled=true
        CapturesUp (1,1) logical = false        % this tool can capture 'Up' events when Enabled=true
        CapturesScroll (1,1) logical = false    % this tool can capture 'Scroll' events when Enabled=true
        CapturesKeyPress (1,1) logical = false  % this tool can capture 'KeyPress' events when Enabled=true

        DistractsDown (1,1) logical = false     % this tool will temporarily capture 'Down' events
        DistractsMove (1,1) logical = false     % this tool will temporarily capture 'Move' events
        DistractsUp (1,1) logical = false       % this tool will temporarily capture 'Up' events
        DistractsScroll (1,1) logical = false   % this tool will temporarily capture 'Scroll' events

        L event.listener                        % listens to host events
    end

    properties (Dependent)
        IsInterceptor (1,1) logical     % this tool can capture at least one type of event when Enabled=true
        IsDistractor (1,1) logical      % this tool will temporarily capture at least one type of event
    end

    properties (SetAccess=protected)
        Enabled (1,1) logical = false       % true/false (set by toggling toolbar buttons)
        Installed (1,1) logical = false     % true/false (whether the tool is installed in the Host)
    end

    % special properties for development/debugging purposes
    properties (Access=protected)
        PrintStatusUpdates (1,1) logical = false
    end

    methods
        function obj = ImageAxesTool(host, name, varargin)
            obj.Host = host;
            obj.Name = string(name);

            % print status update
            obj.printStatus(sprintf('Loading "%s" tool...\n',obj.Name));

            p = inputParser;
            p.addParameter('Tooltip', '', @(x)ischar(x));
            p.addParameter('Icon', 'QuestionMark.png', @(x)ischar(x));

            p.addParameter('Style', 'state', @(x)ischar(x));


            p.addParameter('Priority', 1, @(x)isnumeric(x)&&isscalar(x));
            p.addParameter('IsExclusive', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('CapturesDown', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('CapturesMove', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('CapturesUp', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('CapturesScroll', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('CapturesKeyPress', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('DistractsDown', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('DistractsMove', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('DistractsUp', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('DistractsScroll', false, @(x)islogical(x)&&isscalar(x));
            p.parse(varargin{:});
            obj.Tooltip = p.Results.Tooltip;
            obj.Icon = p.Results.Icon;

            obj.Style = p.Results.Style;



            obj.Priority = p.Results.Priority;
            obj.IsExclusive = p.Results.IsExclusive;
            obj.CapturesDown = p.Results.CapturesDown;
            obj.CapturesMove = p.Results.CapturesMove;
            obj.CapturesUp = p.Results.CapturesUp;
            obj.CapturesScroll = p.Results.CapturesScroll;
            obj.CapturesKeyPress = p.Results.CapturesKeyPress;
            obj.DistractsDown = p.Results.DistractsDown;
            obj.DistractsMove = p.Results.DistractsMove;
            obj.DistractsUp = p.Results.DistractsUp;
            obj.DistractsScroll = p.Results.DistractsScroll;

            % add listener for Host CDataChanged event
            obj.L(1) = addlistener(obj.Host,'CDataChanged',@(~,evt) obj.onHostCDataChanged(evt));

            obj.printStatus(sprintf('"%s" tool loaded\n',obj.Name));
        end

        % Lifecycle toggles (host calls these)
        function push(obj) % "push" tools only
            % forward to subclass hook
            obj.onPush();
        end

        function enable(obj) % "state" tools only
            % if already enabled, exit
            if obj.Enabled, return; end
            % if tool is exclusive
            if obj.IsExclusive
                % disable active exclusive tool
                obj.Host.disableActiveExclusive;
                % set this tool as the active exclusive tool
                obj.Host.ActiveExclusiveTool = obj;
            end
            % set Enabled status
            obj.Enabled = true;
            % ensure that toolbar button (if valid) reflects Enabled status correctly
            if isvalid(obj.Host.ToolbarButtons.(obj.Name))
                obj.Host.ToolbarButtons.(obj.Name).Value = obj.Enabled;
            end
            % forward to subclass hook
            obj.onEnabled();
        end

        function disable(obj) % "state" tools only
            % if already disabled, exit
            if ~obj.Enabled, return; end
            % if tool is exclusive
            if obj.IsExclusive
                % set the active exclusive tool to empty
                obj.Host.ActiveExclusiveTool = [];
            end
            % set Enabled status
            obj.Enabled = false;
            % ensure that toolbar button (if valid) reflects Enabled status correctly
            if isvalid(obj.Host.ToolbarButtons.(obj.Name))
                obj.Host.ToolbarButtons.(obj.Name).Value = obj.Enabled;
            end
            % forward to subclass hook
            obj.onDisabled();
        end

        function install(obj)
            % indicate status in command window
            obj.printStatus(sprintf('Installing "%s" tool...\n',obj.Name));

            % register with the Host
            obj.Host.registerTool(obj);

            % set Installed status
            obj.Installed = true;
            % forward to subclass hook
            obj.onInstall();

            % indicate status in command window
            obj.printStatus(sprintf('"%s" tool installed\n',obj.Name));
        end


        function uninstall(obj)
            % indicate status in command window
            obj.printStatus(sprintf('Uninstalling "%s" tool...\n',obj.Name));

            % make sure tool is disabled before uninstalling
            obj.disable();
            % remove self from Host registry
            obj.Host.unregisterTool(obj);

            % set Installed status
            obj.Installed = false;
            % forward to subclass hook
            obj.onUninstall();

            % indicate status in command window
            obj.printStatus(sprintf('"%s" tool uninstalled\n',obj.Name));
        end

        % Hooks for subclasses (no-ops by default)
        function onPush(~),       end
        function onEnabled(~),    end
        function onDisabled(~),   end
        function onInstall(~),    end
        function onUninstall(~),  end
        function onDelete(~),     end

        % Pointer routing (only Interceptors get these)
        function onDown(~,~,~),     end
        function onMove(~,~,~),     end
        function onUp(~,~,~),       end
        function onScroll(~,~,~),   end
        function onKeyPress(~,~,~), end

        % Pointer routing (only Distractors get these)
        function onDistractDown(~,~,~),   end
        function onDistractMove(~,~,~),   end
        function onDistractUp(~,~,~),     end
        function onDistractScroll(~,~,~), end

        % Adjust pointer shape (override in subclass to set pointer - if empty, Host will set)
        function pointer = getPreferredPointer(~), pointer = ''; end

        % Add to info label (override in subclass to include text in image info label)
        function str = getLabelString(~), str = ''; end

        % Passive hooks (broadcast to enabled tools if the host wants)
        function onHostAxesChanged(~,~),   end   % e.g., XLim/YLim/CLim changed
        function onHostCDataChanged(~,~),  end   % image replaced

    end

    %% derived getters
    methods

        function value = get.IsInterceptor(obj)
            value = obj.CapturesDown || obj.CapturesMove || obj.CapturesUp || obj.CapturesScroll || obj.CapturesKeyPress;
        end

        function value = get.IsDistractor(obj)
            value = obj.DistractsDown || obj.DistractsMove || obj.DistractsUp || obj.DistractsScroll;
        end

    end


    %% private helper methods

    methods(Access=protected)

        function printStatus(obj,status)
            % PrintStatusUpdates is true
            if obj.PrintStatusUpdates
                % print the (pre-formatted) text in status to the command window
                fprintf(['widgets.ImageAxes(%s): ',status],obj.Host.Name);
            end
        end

    end


    %% teardown

    methods (Access = {?guitools.widgets.ImageAxesTool, ?guitools.widgets.ImageAxes})

        % subclass delete() will be called before this runs
        function delete(obj)
            obj.printStatus(sprintf('Unloading "%s" tool...\n',obj.Name));

            % perform tool-specific teardown if needed (i.e. if subclass implements teardown())
            obj.teardown();

            % remove listeners first
            if ~isempty(obj.L), delete(obj.L(isvalid(obj.L))); end
            % replace listener property with empty array of event.listener
            obj.L = event.listener.empty;

            % if tool is installed
            if obj.Installed
                % uninstall before deletion
                obj.uninstall();
            end

            obj.printStatus(sprintf('"%s" tool unloaded\n',obj.Name));
        end

    end


    methods (Access = protected)

        % teardown hook for subclasses, implement to perform any needed cleanup before tool deletion
        function teardown(~),     end

    end





end