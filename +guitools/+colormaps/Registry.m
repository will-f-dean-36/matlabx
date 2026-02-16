classdef Registry
    % Directory-based colormap registry (assets/colormaps/<Category>/*.mat)
    % Values are guitools.colormaps.Colormap objects.

    methods (Static)
        function refresh()
            S = struct();
            S.BYKEY         = containers.Map('KeyType','char','ValueType','any');   % "cat|name" -> Colormap
            S.BYCAT         = containers.Map('KeyType','char','ValueType','any');   % cat(lower) -> {Colormap,...}
            S.BYNAME_UNIQUE = containers.Map('KeyType','char','ValueType','any');   % name(lower) -> Colormap (if unique)
            nameCount       = containers.Map('KeyType','char','ValueType','double');

            root = guitools.colormaps.Registry.rootDir();
            if ~isfolder(root)
                guitools.colormaps.Registry.state('set', S);
                return
            end

            % get colormap categories (names of folders in assets/colormaps)
            cats = guitools.utils.getFolderNames(root);

            for i = 1:numel(cats)
                % get the name of the category folder
                category = string(cats{i});
                % get the full path to the category folder
                folder   = fullfile(root, category);
                % get the mat files in the category folder
                mats = dir(fullfile(folder,'*.mat'));

                % number of colormaps in this category
                nMaps = numel(mats);

                % category key used to index BYCAT map
                catKey = char(category);

                % preallocate the cell array used to hold Colormap objects for this category
                mapCell = cell(nMaps,1);

                for k = 1:numel(mats)
                    % get colormap name (filename without extension)
                    [~, base] = fileparts(mats(k).name);
                    name = string(base);
                    % full path to the colormap
                    path = fullfile(folder, name);

                    % create Colormap object
                    obj  = guitools.colormaps.Colormap(name, category, path);

                    % build a new key using the colormap name and category
                    key  = guitools.colormaps.Registry.mkKey(name, category);

                    % add Colormap object to BYKEY map
                    S.BYKEY(key) = obj;

                    % add Colormap obj to Colormap cell
                    mapCell{k} = obj;

                    % nameCount (case-sensitive)
                    nameKey = char(name);

                    if ~isKey(nameCount, nameKey)
                        nameCount(nameKey) = 1;
                    else
                        nameCount(nameKey) = nameCount(nameKey)+1;
                    end

                    % add Colormap object to BYNAME_UNIQUE
                    S.BYNAME_UNIQUE(nameKey) = obj;

                end

                % add Colormap cell to BYCAT map
                S.BYCAT(catKey) = mapCell;

            end

            nameKeys = keys(nameCount);
            for t = 1:numel(nameKeys)
                if nameCount(nameKeys{t}) > 1
                    warning('Duplicate colormap name found: %s',nameKeys{t})
                    % remove from unique map
                    S.BYNAME_UNIQUE.remove(nameKeys{t});
                end
            end

            guitools.colormaps.Registry.state('set', S);
        end

        function cats = categories()
            S = guitools.colormaps.Registry.getOrInit();
            if isempty(S) || ~isfield(S,'BYCAT') || isempty(S.BYCAT)
                cats = string.empty(0,1); return
            end
            cats = string(keys(S.BYCAT));
            cats = sort(cats);
        end

        function list = names(category)
            S = guitools.colormaps.Registry.getOrInit();
            if nargin==0 || strlength(category)==0
                list = string.empty(0,1); return
            end

            key = char(category);

            if isempty(S) || ~isfield(S,'BYCAT') || ~isKey(S.BYCAT, key)
                list = string.empty(0,1); return
            end
            arr = S.BYCAT(key);                       % cell array of Colormap
            list = string(cellfun(@(o)o.Name, arr, 'UniformOutput', false));
            list = sort(list);
        end

        function tf = has(name, category)
            S = guitools.colormaps.Registry.getOrInit();
            if nargin == 1
                tf = ~isempty(S) && isfield(S,'BYNAME_UNIQUE') && isKey(S.BYNAME_UNIQUE, name);
            else
                tf = ~isempty(S) && isfield(S,'BYKEY') && isKey(S.BYKEY, guitools.colormaps.Registry.mkKey(name, category));
            end
        end

        function obj = get(name, category)
            S = guitools.colormaps.Registry.getOrInit();
            if nargin == 1
                % get key to look up colormap in BYNAME_UNIQUE
                key = name;
                % make sure S is non-empty and the key exists
                assert(~isempty(S) && isKey(S.BYNAME_UNIQUE, key), ...
                    ['Colormap "%s" not found or is not unique. ' ...
                    'If there are multiple colormaps named "%s", ' ...
                    'try specifying a category.'], name, name);
                % get the Colormap object
                obj = S.BYNAME_UNIQUE(key);
            else
                k = guitools.colormaps.Registry.mkKey(name, category);
                assert(~isempty(S) && isKey(S.BYKEY, k), 'Colormap not found: %s (%s)', name, category);
                obj = S.BYKEY(k);
            end
        end

        function p = fileFor(name, category)
            obj = guitools.colormaps.Registry.get(name, category);
            p = obj.Path;
        end

        function cat = categoryOf(name)
            obj = guitools.colormaps.Registry.get(name); % must be unique
            cat = obj.Category;
        end

        function M = map(name, category)
            if nargin == 1
                obj = guitools.colormaps.Registry.get(name);
            else
                obj = guitools.colormaps.Registry.get(name, category);
            end
            M = obj.getMap();
        end
    end

    methods (Static, Access=public)
        function root = rootDir()
            root = guitools.Paths.assets('colormaps');
        end
        function key = mkKey(name, category)
            key = char(category + "|" + name);
        end

        % ---- single persistent store for the whole class ----
        function S = state(op, val)
            persistent STATE
            if nargin==0 || (nargin==1 && strcmp(op,'get'))
                S = STATE; return
            elseif nargin==2 && strcmp(op,'set')
                STATE = val; S = STATE; return
            else
                S = STATE;  % no-op fallback
            end
        end

        function S = getOrInit()
            S = guitools.colormaps.Registry.state('get');
            if isempty(S)
                guitools.colormaps.Registry.refresh();
                S = guitools.colormaps.Registry.state('get');
            end
        end
    end
end