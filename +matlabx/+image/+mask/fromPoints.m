function mask = fromPoints(points,sz)
%FROMPOINTS Generate binary mask with size, sz, using the coordinates in points
%
% mask = matlabx.image.mask.fromPoints(points, sz)
%
% Inputs
%   points  : Nx2 array of (x,y) coordinates
%   sz      : size of the output
%
% Output
%   mask    : logical mask containing pixels closest to pts

% preallocate mask
mask = false(sz);
% convert points to linear px idxs
idx = sub2ind(sz, round(points(:,2)), round(points(:,1)));
% add to mask
mask(idx) = true;

end