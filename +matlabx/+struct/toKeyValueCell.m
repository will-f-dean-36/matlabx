function kv = toKeyValueCell(S)
%MATLABX.STRUCT.TOKEYVALUECELL  Convert a scalar struct to key-value pairs.
%
%   kv = matlabx.struct.toKeyValueCell(S) returns a 1-by-(2N) cell array containing
%   alternating field names and values from the scalar struct S.

    arguments
        S (1,1) struct
    end

    keys = fieldnames(S);
    values = struct2cell(S);

    kv = reshape([keys.'; values.'], 1, []);
end