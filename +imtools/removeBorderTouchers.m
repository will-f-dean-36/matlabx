function BWout = removeBorderTouchers(BW, N)
% Remove 4-connected components that touch N or more image borders
% BW : logical (binary mask)
% N  : scalar integer (e.g., 1 removes anything touching >=1 border)

BW = logical(BW);
[h,w] = size(BW);

% get connected components
CC = bwconncomp(BW, 4);
if CC.NumObjects == 0
    BWout = BW;
    return
end

% get label matrix from components
L = labelmatrix(CC);

% helper: given a vector of labels (may include 0), return logical flag per label
edgeAny = @(lbls) accumarray(lbls(lbls>0), true, [CC.NumObjects 1], @any, false);

t = edgeAny(L(1,:).');   % top
b = edgeAny(L(h,:).');   % bottom
l = edgeAny(L(:,1));     % left
r = edgeAny(L(:,w));     % right

borderCount = t + b + l + r;          % 0..4 per component
removeLbl   = find(borderCount >= N);

BWout = BW;
BWout(ismember(L, removeLbl)) = false;
end