function txt = prettyPrint(S, opts)
%PRETTYPRINT Format scalar struct contents as readable text.
%   txt = PRETTYPRINT(S) returns formatted text for scalar struct S.
%
%   PRETTYPRINT(S) with no output prints to the command window.
%
%   Options:
%       OutputType  - "char" (default) or "string"
%       NameAlign   - "left" (default) or "right"
%       IndentSize  - spaces per nesting level (default 4)

    arguments
        S (1,1) struct
        opts.OutputType (1,1) string {mustBeMember(opts.OutputType, ["char","string"])} = "char"
        opts.NameAlign  (1,1) string {mustBeMember(opts.NameAlign,  ["left","right"])} = "left"
        opts.IndentSize (1,1) double {mustBeInteger, mustBeNonnegative} = 4
    end

    lines = buildLines(S, opts.NameAlign, opts.IndentSize);
    txtChar = strjoin(lines, newline);

    if opts.OutputType == "string"
        txt = string(txtChar);
    else
        txt = txtChar;
    end

    if nargout == 0
        fprintf('%s\n', txtChar);
    end
end

function lines = buildLines(S, nameAlign, indentSize)

    fn = fieldnames(S);

    if isempty(fn)
        lines = {'[empty struct]'};
        return
    end

    isHeader = false(size(fn));
    for k = 1:numel(fn)
        v = S.(fn{k});
        isHeader(k) = isstruct(v) && isscalar(v);
    end

    leafNames = fn(~isHeader);
    headerNames = fn(isHeader);

    if isempty(leafNames)
        maxLen = 0;
    else
        maxLen = max(cellfun(@numel, leafNames));
    end

    lines = {};

    % First pass: non-header fields
    for k = 1:numel(leafNames)
        name = leafNames{k};
        value = S.(name);
        valStr = valueToChar(value);

        switch nameAlign
            case "left"
                nameFmt = sprintf('%-*s', maxLen, name);
            case "right"
                nameFmt = sprintf('%*s', maxLen, name);
        end

        lines{end+1} = sprintf('%s: %s', nameFmt, valStr);
    end

    % Second pass: nested structs
    for k = 1:numel(headerNames)
        name = headerNames{k};
        value = S.(name);

        lines{end+1} = name;

        subLines = buildLines(value, nameAlign, indentSize);
        pad = repmat(' ', 1, indentSize);
        subLines = cellfun(@(s) [pad s], subLines, 'UniformOutput', false);

        lines = [lines, subLines];
    end
end

function out = valueToChar(v)

    if isstring(v)
        if isscalar(v)
            out = char(v);
        else
            q = strcat('"', cellstr(v), '"');
            out = ['[' strjoin(q, ', ') ']'];
        end

    elseif ischar(v)
        out = v;

    elseif islogical(v)
        if isempty(v)
            out = '[]';
        elseif isscalar(v)
            out = lower(char(string(v)));
        elseif isvector(v)
            out = ['[' strjoin(cellstr(lower(string(v(:).'))), ', ') ']'];
        else
            out = sprintf('[logical %s]', strjoin(string(size(v)), 'x'));
            out = char(out);
        end

    elseif isnumeric(v)
        if isempty(v)
            out = '[]';
        elseif isscalar(v)
            out = num2str(v);
        elseif isvector(v)
            c = arrayfun(@num2str, v(:).', 'UniformOutput', false);
            out = ['[' strjoin(c, ',') ']'];
        else
            out = sprintf('[%s %s]', class(v), strjoin(string(size(v)), 'x'));
            out = char(out);
        end

    else
        out = sprintf('[%s]', class(v));
    end
end