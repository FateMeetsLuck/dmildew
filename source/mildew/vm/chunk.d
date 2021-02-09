module mildew.vm.chunk;

import std.typecons;

import mildew.vm.consttable;

/// represents bytecode with a compilation state
class Chunk
{
    /// const table
    ConstTable constTable = new ConstTable();
    /// raw byte code
    ubyte[] bytecode;
    /// represents a ip,lineNumber pair so that ips can be mapped to line numbers
    Tuple!(size_t, "ip", size_t, "lineNumber")[] lines;
    /// represents the source code as lines for error reporting
    string[] source;

    /// convenience function for adding ip-lineNumber pair
    void addLine(size_t ip, size_t lineNumber)
    {
        lines ~= tuple!(size_t, "ip", size_t, "lineNumber")(ip, lineNumber);
    }

    /// get line associated with ip
    size_t getLineNumber(size_t ip)
    {
        long index = 0;
        while(index < cast(long)lines.length - 1)
        {
            if(ip >= lines[index].ip && ip < lines[index+1].ip)
                return lines[index].lineNumber;
            ++index;
        }
        // if we get to this point assume the error was on the last line if it exists
        if(lines.length > 1)
        {
            return lines[$-1].lineNumber;
        }
        // else the line info is missing so just return 0
        return 0;
    }

    /// get a line of source if it exists
    string getSourceLine(size_t lineNum)
    {
        if(lineNum-1 >= source.length)
            return "";
        return source[lineNum-1];
    }

private:
    /// enums used when serializing to and from file
    static const ubyte VERSION = 0x01;
    static const uint MAGIC = 0x001abe15;
}