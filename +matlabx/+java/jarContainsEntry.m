function tf = jarContainsEntry(jarFile,entryName)
%JARCONTAINSENTRY  Determine whether a JAR contains a specified entry
%
%   tf = matlabx.java.jarContainsEntry(jarFile,entryName) returns true when
%   the specified JAR archive contains the requested file or class entry.
%
%   Entry names must use forward slashes, for example:
%
%       "loci/formats/IFormatReader.class"
%
%   Inputs
%       jarFile   - Path to a JAR file
%       entryName - Name of an entry within the JAR
%
%   Output
%       tf        - True when the entry exists

    arguments
        jarFile   {mustBeTextScalar}
        entryName {mustBeTextScalar}
    end

    jarFile = string(jarFile);
    entryName = string(entryName);

    tf = false;
    jar = [];

    if ~isfile(jarFile)
        return
    end

    try
        jar = java.util.jar.JarFile(char(jarFile));
        tf = ~isempty(jar.getJarEntry(char(entryName)));
    catch
        tf = false;
    end

    if ~isempty(jar)
        try
            jar.close();
        catch
        end
    end
end