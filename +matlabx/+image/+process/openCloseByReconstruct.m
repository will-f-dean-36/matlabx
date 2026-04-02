function Iout = openCloseByReconstruct(I,se)

    Ie = imerode(I,se);
    Iobr = imreconstruct(Ie,I);
    Iobrd = imdilate(Iobr,se);
    Iobrcbr = imreconstruct(imcomplement(Iobrd),imcomplement(Iobr));
    Iout = imcomplement(Iobrcbr);

end