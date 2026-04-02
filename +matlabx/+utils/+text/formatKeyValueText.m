function txt = formatKeyValueText(keys, values)
%FORMATKEYVALUETEXT Formats two cell arrays of char vectors as a text table for display
    % maximum length of the left column of text
    maxLen = max(cellfun(@numel, keys));
    % add each line of the table to separate cell
    lines = cellfun(@(k,v) ...
        sprintf('%-*s  %s', maxLen, k, v), ...
        keys, values, 'UniformOutput', false);
    % join all lines with newline
    txt = strjoin(lines, newline);
end