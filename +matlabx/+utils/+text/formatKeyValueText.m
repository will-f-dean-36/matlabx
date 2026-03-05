function txt = formatKeyValueText(keys, values)

    maxLen = max(cellfun(@numel, keys));

    lines = cellfun(@(k,v) ...
        sprintf('%-*s  %s', maxLen, k, v), ...
        keys, values, 'UniformOutput', false);

    txt = strjoin(lines, newline);
end