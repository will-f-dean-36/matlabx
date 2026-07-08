function paths = dynamicClassPath()
%DYNAMICCLASSPATH  Return the dynamic Java class path
%
%   paths = matlabx.java.dynamicClassPath() returns the dynamic Java class
%   path as a canonicalized string array.

    paths = string(javaclasspath("-dynamic"));
    paths = paths(:);

    paths = matlabx.files.canonicalizePaths(paths);
end