/** 
 * This module implements the Chunk class.
 */
module mildew.vm.chunk;

import std.typecons;

import mildew.util.encode;
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

    /// serialize to raw bytes that can be written and read to files
    ubyte[] serialize()
    {
        // write an indicator that the file is binary
        ubyte[] data = [0x01];
        data ~= encode(MAGIC);
        data ~= VERSION;
        data ~= encode!ubyte(size_t.sizeof);
        // length of meta-data, 0 for now
        data ~= encode!size_t(0);
        data ~= constTable.serialize();
        data ~= encode(bytecode);
        return data;
    }

    /// deserialize chunk from ubyte stream
    static Chunk deserialize(ref ubyte[] stream)
    {
        if(stream[0] != 0x01)
            throw new ChunkDecodeException("Invalid file format, not a chunk file");
        stream = stream[1..$];
        immutable magic = decode!uint(stream.ptr);
        stream = stream[uint.sizeof..$];
        if(magic != MAGIC)
        {
            if(magic == MAGIC_REVERSE)
                throw new ChunkDecodeException("This chunk was compiled on a machine with different CPU " 
                    ~ "architecture. You must recompile the script for this machine.");
            else
                throw new ChunkDecodeException("This is not a chunk file");
        }
        immutable version_ = stream[0];
        stream = stream[1..$];
        if(version_ != VERSION)
            throw new ChunkDecodeException("The version of the file is incompatible");
        immutable sizeOfSizeT = stream[0];
        stream = stream[1..$];
        if(sizeOfSizeT != size_t.sizeof)
            throw new ChunkDecodeException("Different CPU width, must recompile script for this machine");
        immutable sizeOfMD = decode!size_t(stream.ptr);
        stream = stream[size_t.sizeof..$];

        Chunk chunk = new Chunk();
        chunk.constTable = ConstTable.deserialize(stream);
        chunk.bytecode = decode!(ubyte[])(stream.ptr);
        stream = stream[size_t.sizeof..$];
        stream = stream[chunk.bytecode.length * ubyte.sizeof .. $];
        return chunk;
    }

private:
    /// enums used when serializing to and from file in the future
    static const uint MAGIC = 0xB00BA911;
    static const uint MAGIC_REVERSE = 0x11A90BB0;
    static const ubyte VERSION = 0x01; // file format version
}

class ChunkDecodeException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}