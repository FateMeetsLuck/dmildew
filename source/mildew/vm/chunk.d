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
        foreach(pair ; lines)
        {
            if(ip >= pair.ip)
                return pair.lineNumber;
        }
        return 0;
    }

    /// get a line of source if it exists
    string getSourceLine(size_t lineNum)
    {
        if(lineNum >= source.length)
            return "";
        return source[lineNum];
    }
}