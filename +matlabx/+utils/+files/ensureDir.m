function ensureDir(folder)
    arguments
        folder {mustBeTextScalar}
    end
    
    folder = string(folder);
    if ~isfolder(folder)
        mkdir(folder);
    end
end