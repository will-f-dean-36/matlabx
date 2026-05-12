% function idx = longestRunOfValue(x, value)
% %LONGESTRUNOFVALUE Find longest continuous stretch equal to value.
% %
% % idx = longestRunOfValue(x, value)
% %
% % Inputs
% %   x     - input vector
% %   value - scalar value to match
% %
% % Output
% %   idx   - indices of the longest continuous run where x == value
% %           returns [] if value is not found
% 
%     isMatch = x == value;
% 
%     if ~any(isMatch)
%         idx = [];
%         return
%     end
% 
%     d = diff([false, isMatch(:).', false]);
% 
%     runStarts = find(d == 1);
%     runEnds   = find(d == -1) - 1;
% 
%     [~, k] = max(runEnds - runStarts + 1);
% 
%     idx = runStarts(k):runEnds(k);
% end

function idx = longestRunOfValue(x, value, opts)
%LONGESTRUNOFVALUE Find longest continuous stretch equal to value.
%
% idx = longestRunOfValue(x, value)
% idx = longestRunOfValue(x, value, AllowWrap=true)
%
% Inputs
%   x           - input vector
%   value       - scalar value to match
%   AllowWrap   - whether runs may wrap around vector boundary
%
% Output
%   idx         - indices of longest run where x == value
%                 returns [] if value is not found

    arguments
        x {mustBeVector}
        value (1,1)
        opts.AllowWrap (1,1) logical = false
    end

    wasColumn = iscolumn(x);
    isMatch = x(:).';
    isMatch = isMatch == value;

    n = numel(isMatch);

    if ~any(isMatch)
        idx = [];
        return
    end

    if all(isMatch)
        idx = 1:n;
        if wasColumn
            idx = idx.';
        end
        return
    end

    if opts.AllowWrap
        mask = [isMatch isMatch];

        d = diff([false mask false]);

        runStarts = find(d == 1);
        runEnds   = find(d == -1) - 1;
        runLens   = runEnds - runStarts + 1;

        runLens = min(runLens, n);

        [~, k] = max(runLens);

        runIdx = runStarts(k):(runStarts(k) + runLens(k) - 1);
        idx = mod(runIdx - 1, n) + 1;
    else
        d = diff([false isMatch false]);

        runStarts = find(d == 1);
        runEnds   = find(d == -1) - 1;
        runLens   = runEnds - runStarts + 1;

        [~, k] = max(runLens);

        idx = runStarts(k):runEnds(k);
    end

    if wasColumn
        idx = idx.';
    end
    
end