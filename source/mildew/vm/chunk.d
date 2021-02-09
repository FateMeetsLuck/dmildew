module mildew.vm.chunk;

import std.typecons;

import mildew.util.stack;
import mildew.vm.consttable;
import mildew.vm.debuginfo;

/// represents bytecode with a compilation state
class Chunk
{
    /// const table
    ConstTable constTable = new ConstTable();
    /// raw byte code
    ubyte[] bytecode;
    /// optional debug map
    DebugMap debugMap;

private:
    /// enums used when serializing to and from file
    static const ubyte VERSION = 0x01;
    static const uint MAGIC = 0x001abe15;
}