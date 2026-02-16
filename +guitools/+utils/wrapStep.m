function x = wrapStep(x, step, lo, hi)
%WRAPSTEP  Step a value through a bounded integer range with wraparound
%
%   x = WRAPSTEP(x, step, lo, hi) advances x by the signed integer STEP
%   within the inclusive range [lo, hi]. When x exceeds the bounds,
%   it wraps around cyclically.
%
%   Inputs
%     x    : current value (scalar)
%     step : signed integer step (+1, -1, etc.)
%     lo   : lower bound of the range (inclusive)
%     hi   : upper bound of the range (inclusive)
%
%   Output
%     x    : updated value after stepping and wraparound
%
%   Example
%     x = 1;
%     x = wrapStep(x,  1, 1, 3);   % -> 2
%     x = wrapStep(x, -1, 1, 3);   % -> 3
%
%   See also MOD

    N = hi - lo + 1;
    x = lo + mod((x - lo) + step, N);
end