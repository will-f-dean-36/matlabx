function paths = staticClassPath()
%STATICCLASSPATH  Return the static Java class path
%
%   paths = matlabx.java.staticClassPath() returns the static Java class
%   path as a canonicalized string array.

    paths = string(javaclasspath("-static"));
    paths = paths(:);

    paths = matlabx.files.canonicalizePaths(paths);
end