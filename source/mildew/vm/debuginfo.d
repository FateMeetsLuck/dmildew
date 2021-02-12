/// This module implements the DebugInfo class
module mildew.vm.debuginfo;

import std.string;
import std.typecons;

/// Alias for a hash map that associates DebugInfos to specific blocks of raw bytecode.
alias DebugMap = DebugInfo[ubyte[]];

/**
 * Holds debug information to be associated with completed ubyte[] code.
 */
class DebugInfo
{
public:
    alias LineData = Tuple!(size_t, "ip", size_t, "lineNumber");

    /// constructor
    this(string src, string name = "")
    {
        _source = splitLines(src);
        _name = name;
    }

    /// Add an ip-lineNumber pair
    void addLine(size_t ip, size_t lineNumber)
    {
        _lines ~= tuple!(size_t, "ip", size_t, "lineNumber")(ip, lineNumber);
    }

    /// get line associated with ip
    size_t getLineNumber(size_t ip)
    {   
        long index = 0;
        while(index < cast(long)_lines.length - 1)
        {
            if(ip >= _lines[index].ip && ip < _lines[index+1].ip)
                return _lines[index].lineNumber;
            ++index;
        }
        // if we get to this point assume the error was on the last line if it exists
        if(_lines.length >= 1)
        {
            return _lines[$-1].lineNumber;
        }
        // else the line info is missing so just return 0
        return 0;
    }

    /// get a line of source starting at 1 if it exists
    string getSourceLine(size_t lineNum)
    {
        if(lineNum-1 >= _source.length)
            return "";
        return _source[lineNum-1];
    }

    /// name property
    string name() const { return _name; }

    override string toString() const 
    {
        import std.format: format;
        return format("#lines=%s, #source=%s, name=`%s`", _lines.length, _source.length, _name);
    }

private:
    /// represents the source code as lines for error reporting
    string[] _source;
    /// line data array
    LineData[] _lines;
    /// optional name
    string _name;
}