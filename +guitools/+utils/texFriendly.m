function out = texFriendly(str)
%%TEXFRIENDLY  Converts underscore-containing strings to a format compatible with tex interpreter
    nameSplit = strsplit(str,'_');
    out = convertCharsToStrings(strjoin(nameSplit,"\_"));
end