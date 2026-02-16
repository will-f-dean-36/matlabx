function IRGB = vecind2rgb(I,cmap)
%%VECIND2RGB  Vectorized version of ind2rgb, faster when ind2rgb() is called frequently within a loop or callback
%
%   I must be uint8 in the range [0 255]
%   
%   cmap must by 256x3 array of RGB triplets
%
%   Steps
%       
%       I is converted to a column vector
%       Vectorized I is converted to double and incremented by 1 to act as an index into cmap
%       Output colors are then reshaped into a truecolor image array
%
%----------------------------------------------------------------------------------------------------------------------------

IRGB = reshape(cmap(double(I(:))+1,:),[size(I),3]);

end