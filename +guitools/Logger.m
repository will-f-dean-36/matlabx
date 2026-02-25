classdef Logger < handle
%LOGGER Simple structured logger with optional sinks (Command Window, UI, file).
%
%   L = Logger();
%   L.info("Calibration started", "Source","UICalibration");
%   L.warn("Something looks off", "Tag","ui");
%   L.error("Failed to load file", "Data",struct("file",fn));
%
% Features
% --------
% - In-memory structured entries (datetime, level, message, etc.)
% - Ring buffer (keeps last N entries) OR keep-all mode
% - Optional sinks:
%     * Command Window (fprintf)
%     * UI sink (function handle, e.g., append to uitextarea)
%     * File sink (append lines)
% - Throttled UI/file flushing to avoid lag while spamming messages

    properties
        % Memory behavior
        KeepAll (1,1) logical = false
        MaxEntries (1,1) double {mustBePositive, mustBeInteger} = 5000

        % Output formatting
        TimestampFormat (1,:) char = 'yyyy-MM-dd HH:mm:ss.SSS'
        IncludeLevel (1,1) logical = true
        IncludeSource (1,1) logical = true
        IncludeTag (1,1) logical = false

        % Sinks toggles
        PrintToCommandWindow (1,1) logical = true
        EnableUISink (1,1) logical = false
        EnableFileSink (1,1) logical = false

        % Throttling / batching
        FlushEveryN (1,1) double {mustBePositive, mustBeInteger} = 1
        FlushMinIntervalSec (1,1) double {mustBeNonnegative} = 0.05
    end

    properties (SetAccess=private)
        % Struct array of entries
        Entries struct = struct( ...
            't', datetime.empty(0,1), ...
            'level', strings(0,1), ...
            'msg', strings(0,1), ...
            'source', strings(0,1), ...
            'tag', strings(0,1), ...
            'data', cell(0,1))


        % Stats
        TotalCount (1,1) double = 0
        StartTime (1,1) datetime = datetime('now')
    end

    properties (Access=private)
        UISinkFcn (1,1) function_handle = @(lines) []
        FilePath (1,:) char = ''
        FileFID (1,1) double = -1

        PendingLines (1,1) string = ""   % batched lines waiting to flush
        PendingCount (1,1) double = 0
        LastFlushTic (1,1) uint64 = uint64(0)
    end

    methods
        function self = Logger(opts)
            arguments
                opts.KeepAll (1,1) logical = false
                opts.MaxEntries (1,1) double {mustBePositive, mustBeInteger} = 5000
                opts.PrintToCommandWindow (1,1) logical = true
                opts.FlushEveryN (1,1) double {mustBePositive, mustBeInteger} = 1
                opts.FlushMinIntervalSec (1,1) double {mustBeNonnegative} = 0.05
            end

            self.KeepAll = opts.KeepAll;
            self.MaxEntries = opts.MaxEntries;
            self.PrintToCommandWindow = opts.PrintToCommandWindow;
            self.FlushEveryN = opts.FlushEveryN;
            self.FlushMinIntervalSec = opts.FlushMinIntervalSec;

            self.StartTime = datetime('now');
            self.LastFlushTic = tic;
        end

        function delete(self)
            % Ensure file is closed
            self.closeFile();
        end

        % ---- Convenience levels ----
        function info(self, msg, varargin),  self.log("INFO",  msg, varargin{:}); end
        function debug(self, msg, varargin), self.log("DEBUG", msg, varargin{:}); end
        function warn(self, msg, varargin),  self.log("WARN",  msg, varargin{:}); end
        function error(self, msg, varargin), self.log("ERROR", msg, varargin{:}); end

        % ---- Main log entry point ----
        function log(self, level, msg, opts)
            arguments
                self (1,1) guitools.Logger
                level (1,1) string
                msg (1,1)       % string, char, MException
                opts.Source (1,1) string = ""
                opts.Tag (1,1) string = ""
                opts.Data = []
                opts.Timestamp datetime = datetime('now')
                opts.AlsoPrint (1,1) logical = false  % force print even if PrintToCommandWindow=false
            end

            % if msg is an MException
            if isa(msg,'MException')
                ME = msg;
                msg = string(ME.message);
            
                if isempty(opts.Source)
                    opts.Source = string(ME.stack(1).name);
                end
            
                if isempty(opts.Data)
                    opts.Data = struct( ...
                        "identifier", ME.identifier, ...
                        "stack", ME.stack);
                end
            elseif isa(msg,'char')
                msg = string(msg);
            end

            if ~isa(msg,'string')
                error('Logger:incorrectType','msg must be a string, char, or MException, not a %s',class(msg))
            end

            e = struct( ...
                't', opts.Timestamp, ...
                'level', level, ...
                'msg', msg, ...
                'source', opts.Source, ...
                'tag', opts.Tag, ...
                'data', {opts.Data} );

            self.appendEntry_(e);

            line = self.formatEntry_(e);

            % Immediate command window output (optionally)
            if self.PrintToCommandWindow || opts.AlsoPrint
                % Use fprintf to preserve formatting and avoid string display quirks
                fprintf('%s\n', line);
            end

            % Batch for UI/file sinks
            if self.EnableUISink || self.EnableFileSink
                self.queueLine_(line);
                self.maybeFlush_();
            end
        end

        % ---- Sinks configuration ----
        function setUISink(self, fcn, enable)
            arguments
                self (1,1) guitools.Logger
                fcn (1,1) function_handle
                enable (1,1) logical = true
            end
            self.UISinkFcn = fcn;
            self.EnableUISink = enable;
        end

        function setFileSink(self, filePath, enable)
            arguments
                self (1,1) guitools.Logger
                filePath (1,:) char
                enable (1,1) logical = true
            end
            self.openFile_(filePath);
            self.EnableFileSink = enable;
        end

        function closeFile(self)
            if self.FileFID > 0
                try fclose(self.FileFID); catch, end
            end
            self.FileFID = -1;
            self.FilePath = '';
            self.EnableFileSink = false;
        end

        % ---- Retrieval / export ----
        function T = asTable(self)
            %ASTABLE Convert log to a table (easy filtering/sorting).
            n = numel(self.Entries);
            if n == 0
                T = table( ...
                    datetime.empty(0,1), ...
                    strings(0,1), ...
                    strings(0,1), ...
                    strings(0,1), ...
                    strings(0,1), ...
                    cell(0,1), ...
                    'VariableNames', {'t','level','msg','source','tag','data'});
                return
            end

            t      = vertcat(self.Entries.t);
            level  = vertcat(self.Entries.level);
            msg    = vertcat(self.Entries.msg);
            source = vertcat(self.Entries.source);
            tag    = vertcat(self.Entries.tag);
            data   = {self.Entries.data}.';
            T = table(t, level, msg, source, tag, data, ...
                'VariableNames', {'t','level','msg','source','tag','data'});
        end

        function lines = exportText(self)
            %EXPORTTEXT Render all stored entries as lines.
            n = numel(self.Entries);
            lines = strings(n,1);
            for i = 1:n
                lines(i) = self.formatEntry_(self.Entries(i));
            end
        end

        function clear(self)
            self.Entries = struct( ...
            't', datetime.empty(0,1), ...
            'level', strings(0,1), ...
            'msg', strings(0,1), ...
            'source', strings(0,1), ...
            'tag', strings(0,1), ...
            'data', cell(0,1));

            self.TotalCount = 0;
            self.PendingLines = "";
            self.PendingCount = 0;
            self.LastFlushTic = tic;
        end

        function flush(self)
            %FLUSH Force flushing batched lines to UI/file.
            self.flush_();
        end
    end

    methods (Access=private)
        function appendEntry_(self, e)
            self.TotalCount = self.TotalCount + 1;

            self.Entries(end+1) = e;

            if ~self.KeepAll
                n = numel(self.Entries);
                if n > self.MaxEntries
                    self.Entries = self.Entries(end-self.MaxEntries+1:end);
                end
            end
        end

        function s = formatEntry_(self, e)
            % Build: [timestamp] [LEVEL] [Source] message  (configurable)
            parts = strings(0,1);

            ts = string(datetime(e.t, 'Format', self.TimestampFormat));
            parts(end+1,1) = "[" + ts + "]";

            if self.IncludeLevel
                parts(end+1,1) = "[" + upper(e.level) + "]";
            end

            if self.IncludeSource && strlength(e.source) > 0
                parts(end+1,1) = "[" + e.source + "]";
            end

            if self.IncludeTag && strlength(e.tag) > 0
                parts(end+1,1) = "[" + e.tag + "]";
            end

            parts(end+1,1) = e.msg;

            s = strjoin(parts, " ");
        end

        function queueLine_(self, line)
            if self.PendingCount == 0
                self.PendingLines = line;
            else
                self.PendingLines(end+1,1) = line;
            end
            self.PendingCount = self.PendingCount + 1;
        end

        function maybeFlush_(self)
            if self.PendingCount < self.FlushEveryN
                return
            end
        
            % If timer handle isn't initialized yet, initialize it
            if self.LastFlushTic == uint64(0)
                self.LastFlushTic = tic;
                return
            end
        
            if toc(self.LastFlushTic) < self.FlushMinIntervalSec
                return
            end
        
            self.flush_();
        end

        function flush_(self)
            if self.PendingCount == 0
                return
            end

            lines = self.PendingLines;
            self.PendingLines = "";
            self.PendingCount = 0;
            self.LastFlushTic = tic;

            % UI sink
            if self.EnableUISink
                try
                    self.UISinkFcn(lines);
                catch ME
                    % If UI sink fails, disable it but keep running
                    self.EnableUISink = false;
                    fprintf('[Logger] UI sink disabled due to error: %s\n', ME.message);
                end
            end

            % File sink
            if self.EnableFileSink && self.FileFID > 0
                try
                    for i = 1:numel(lines)
                        fprintf(self.FileFID, '%s\n', lines(i));
                    end
                    % optional flush to disk; can be expensive on network drives
                    % fflush(self.FileFID);
                catch ME
                    self.EnableFileSink = false;
                    fprintf('[Logger] File sink disabled due to error: %s\n', ME.message);
                end
            end
        end

        function openFile_(self, filePath)
            % Ensure any previous file is closed
            self.closeFile();

            % Create folder if needed
            [folder,~,~] = fileparts(filePath);
            if ~isempty(folder) && ~exist(folder,'dir')
                mkdir(folder);
            end

            % Open in append mode
            fid = fopen(filePath, 'a');
            if fid < 0
                error("Logger:FileOpenFailed", "Could not open log file: %s", filePath);
            end
            self.FileFID = fid;
            self.FilePath = filePath;
        end
    end
end