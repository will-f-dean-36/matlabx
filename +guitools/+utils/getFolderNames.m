function folderNames = getFolderNames(queryPath)
%%GETFOLDERNAMES  Returns cell array of folder names at the specified path

% make sure the queryPath points to a valid directory
if ~isfolder(queryPath)
    folderNames = {};
    return
end
% get the contents of the queryPath
fList = dir(queryPath);
% extract list of non-hidden folder names (those that do not start with '.')
folderNames = {fList([fList.isdir] & ~cellfun(@(x) strcmp('.',x(1)),{fList.name},'UniformOutput',true)).name};

end