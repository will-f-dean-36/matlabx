function UUID = uniqueID(ID_class)
%%UNIQUEID  Returns a unique UUID ('string' or 'char')
arguments
    ID_class (1,:) char {mustBeMember(ID_class,{'string','char'})} = 'string'
end

switch ID_class
    case 'string'
        UUID = string(java.util.UUID.randomUUID());
    case 'char'
        UUID = char(java.util.UUID.randomUUID());
end

end