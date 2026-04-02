function S = fromFieldnames(fnames, vals)
%FROMFIELDNAMES Returns a struct with fields and values specified by cell arrays fnames and vals
    arguments
        fnames (1,:) cell
        vals   (:,:) cell = {}
    end
    % no vals provided, use empty cell
    if isempty(vals); vals = cell(size(fnames)); end
    % vals incorrect shape, error
    if ~isequal(size(fnames),size(vals))
        error('fromFieldnames:IncompatibleArraySizes', ...
            'Arrays must have the same size: fnames (%s) and vals (%s) have different sizes.',...
            matlabx.array.size2char(fnames),matlabx.array.size2char(vals));
    end
    % create one cell array with interleaved fieldnames and values
    field_value_cell = matlabx.array.interleave2D(fnames,vals);
    % create the struct
    S = struct(field_value_cell{:});
end