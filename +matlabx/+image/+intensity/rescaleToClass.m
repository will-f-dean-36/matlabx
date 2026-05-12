function J = rescaleToClass(I)
%RESCALETOCLASS Rescale image intensities to the native range of its class.
%
%   J = RESCALETOCLASS(I) rescales the intensity values in I such that the
%   minimum value maps to the bottom of the output range and the maximum
%   value maps to the top of the output range.
%
%   For integer inputs, J is returned in the same class as I and spans the
%   native range of that class:
%
%       uint8   -> [0, 255]
%       uint16  -> [0, 65535]
%       uint32  -> [0, intmax('uint32')]
%
%   For floating-point inputs, J is returned in the same class as I and
%   spans [0, 1].
%
%   Example
%       I = uint16([100 200 300]);
%       J = rescaleToClass(I);
%
%       % J is uint16, with values mapped from [100, 300] to [0, 65535].
%
%   Notes
%       This function uses the actual minimum and maximum values in I.
%       The input image I is not modified.
%
%   See also MAT2GRAY, IM2UINT8, IM2UINT16, RESCALE

    J0 = mat2gray(I);

    switch class(I)
        case 'uint8'
            J = im2uint8(J0);
        case 'uint16'
            J = im2uint16(J0);
        case 'uint32'
            J = uint32(J0 * double(intmax('uint32')));
        case {'single','double'}
            J = cast(J0, class(I));
        otherwise
            error('matlabx:image:intensity:UnsupportedClass','Unsupported image class: %s', class(I));
    end
end