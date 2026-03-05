function T = rotate(T,opts)
%ROTATETABLE  rotates a table such that variables and rows are swapped
    
    arguments
        T (:,:) table
        opts.ColumnNames (:,1) cell = {} % optional
    end

    % swap rows and vars
    T = rows2vars(T,"VariableNamingRule","preserve");

    % set row names to original variable names
    T.Properties.RowNames = T.OriginalVariableNames;

    % remove the "OriginalVariableNames" column, as it contains the same content as the row names
    T = removevars(T,"OriginalVariableNames");

    % set VariableNames to opts.ColumnNames, if not empty
    if ~isempty(opts.ColumnNames)
        if ~isequal(length(T.Properties.VariableNames),length(opts.ColumnNames))
            error('Number of column names must match number of rows in the input table');
        end
        T.Properties.VariableNames = opts.ColumnNames; 
    end

end