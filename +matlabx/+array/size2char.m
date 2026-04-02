function szChar = size2char(A)
%SIZE2CHAR Return size of array as a character vector
%   szChar = SIZE2CHAR(A) returns a character vector like:
%       '5x7'
%       '5x7x3'
%       '5x7x1x4'
%
%   It always includes the first two dimensions, and includes any
%   additional dimensions up to the last dimension whose size is > 1.

    sz = size(A);

    % Always keep first two dimensions
    if isempty(A)
        lastDim = 2;
    else
        lastDim = max(2, find(sz > 1, 1, 'last'));
    end

    % add each dimension of the array to separate cell
    dims = arrayfun(@(s) sprintf('%d', s), sz(1:lastDim), 'UniformOutput', false);
    % join all dims with an 'x'
    szChar = strjoin(dims, 'x');

end