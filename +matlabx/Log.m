classdef Log
%MATLABX.LOG  Static facade and singleton accessor for the matlabx logger.
%
% Typical use
% -----------
%   matlabx.Log.INFO("Application started")
%   matlabx.Log.WARN("Something looks odd")
%
% Get underlying logger handle when needed
% ----------------------------------------
%   log = matlabx.Log.get();
%   log.setFileSink(logPath, true);
%   log.setUISink(@(lines) appendToTextArea(matlabx.LogTextArea, lines), true);
%
% Notes
% -----
% - Lazy-creates a single matlabx.logging.Logger for the current MATLAB session.
% - Public wrapper methods auto-populate Source based on the caller if not provided.
% - clear() removes the stored handle from the facade. If other references exist,
%   the logger object itself will remain alive until those references are released.

    methods (Static)

        function log = get()
        %GET Return the active logger, creating it if needed.
            log = matlabx.Log.peek_();
            if isempty(log) || ~isvalid(log)
                log = matlabx.logging.Logger();
                matlabx.Log.store_(log);
            end
        end

        function set(log)
        %SET Replace the active logger.
            arguments
                log (1,1) matlabx.logging.Logger
            end
            matlabx.Log.store_(log);
        end

        function clear()
        %CLEAR Clear the stored logger handle from the facade.
            matlabx.Log.store_([]);
        end

        function tf = exists()
        %EXISTS True if a valid logger is currently stored.
            log = matlabx.Log.peek_();
            tf = ~isempty(log) && isvalid(log);
        end

        function INFO(msg, varargin)
        %INFO Log an INFO message.
            [src, args] = matlabx.Log.resolveSource_(varargin{:});
            matlabx.Log.get().info(msg, "Source", src, args{:});
        end

        function DEBUG(msg, varargin)
        %DEBUG Log a DEBUG message.
            [src, args] = matlabx.Log.resolveSource_(varargin{:});
            matlabx.Log.get().debug(msg, "Source", src, args{:});
        end

        function WARN(msg, varargin)
        %WARN Log a WARN message.
            [src, args] = matlabx.Log.resolveSource_(varargin{:});
            matlabx.Log.get().warn(msg, "Source", src, args{:});
        end

        function ERROR(msg, varargin)
        %ERROR Log an ERROR message.
            [src, args] = matlabx.Log.resolveSource_(varargin{:});
            matlabx.Log.get().error(msg, "Source", src, args{:});
        end

        function EXCEPTION(ME, varargin)
        %EXCEPTION Log an MException as an error.
            [src, args] = matlabx.Log.resolveSource_(varargin{:});
            matlabx.Log.get().error(ME, "Source", src, args{:});
        end

        function LOG(level, msg, varargin)
        %LOG Generic logging entry point.
            [src, args] = matlabx.Log.resolveSource_(varargin{:});
            matlabx.Log.get().log(level, msg, "Source", src, args{:});
        end

        function flush()
        %FLUSH Flush pending UI/file sink output.
            matlabx.Log.get().flush();
        end

        function T = asTable()
        %ASTABLE Return stored log entries as a table.
            T = matlabx.Log.get().asTable();
        end

        function lines = exportText()
        %EXPORTTEXT Return formatted stored log lines.
            lines = matlabx.Log.get().exportText();
        end

    end

    methods (Static, Access=private)

        function log = peek_()
        %PEEK_ Return stored logger without creating one.
            log = matlabx.Log.store_();
        end

        function log = store_(newLog)
        %STORE_ Persistent storage owner for the logger handle.
            persistent L
            if nargin > 0
                L = newLog;
            end
            log = L;
        end

        function [src, args] = resolveSource_(varargin)
            %RESOLVESOURCE_ Use explicit Source if provided, else infer from caller.
            args = varargin;

            idx = matlabx.Log.findNameValue_(args, "Source");
            if ~isempty(idx)
                src = string(args{idx+1});
                args(idx:idx+1) = [];
                return
            end

            % Stack here is typically:
            % 1 resolveSource_
            % 2 matlabx.Log.INFO / DEBUG / ...
            % 3 actual caller
            st = dbstack(2, '-completenames');

            if isempty(st)
                src = "unknown";
                return
            end

            src = matlabx.logging.formatCallerName(st(1).name, Detail="short");
        end

        function idx = findNameValue_(args, name)
        %FINDNAMEVALUE_ Find a name-value pair position in varargin-like input.
            idx = [];
            for k = 1:2:(numel(args)-1)
                key = args{k};
                if (ischar(key) || isstring(key)) && strcmpi(string(key), string(name))
                    idx = k;
                    return
                end
            end
        end

    end

end