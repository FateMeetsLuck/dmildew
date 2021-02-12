/** 
 * This module implements the Chunk class.
 */
module mildew.vm.chunk;

import std.typecons;

import mildew.util.stack;
import mildew.vm.consttable;
import mildew.vm.debuginfo;

/**
 * This is the compiled form of a program. It includes a table of constants that all functions under the
 * same compilation share.
 */
class Chunk
{
    /// const table
    ConstTable constTable = new ConstTable();
    /// raw byte code
    ubyte[] bytecode;
    /**
     * Optional debug map. Each function under the same chunk compilation can be added to this table.
     */
    DebugMap debugMap;

private:
    /// enums used when serializing to and from file in the future
    static const ubyte VERSION = 0x01;
    static const uint MAGIC = 0x001abe15; // TODO something more creative
}