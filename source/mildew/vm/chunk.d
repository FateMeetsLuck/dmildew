/** 
This module implements the Chunk class.

────────────────────────────────────────────────────────────────────────────────

Copyright (C) 2021 pillager86.rf.gd

This program is free software: you can redistribute it and/or modify it under 
the terms of the GNU General Public License as published by the Free Software 
Foundation, either version 3 of the License, or (at your option) any later 
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with 
this program.  If not, see <https://www.gnu.org/licenses/>.
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
        immutable magic = decode!uint(stream);
        stream = stream[uint.sizeof..$];
        if(magic != MAGIC)
        {
            if(magic == MAGIC_REVERSE)
                throw new ChunkDecodeException("This chunk was compiled on a machine with different CPU " 
                    ~ "architecture. You must recompile the script for this machine.");
            else
                throw new ChunkDecodeException("This is not a chunk file");
        }
        immutable version_ = decode!ubyte(stream);
        stream = stream[1..$];
        if(version_ != VERSION)
            throw new ChunkDecodeException("The version of the file is incompatible");
        immutable sizeOfSizeT = decode!ubyte(stream);
        stream = stream[1..$];
        if(sizeOfSizeT != size_t.sizeof)
            throw new ChunkDecodeException("Different CPU width, must recompile script for this machine");
        immutable sizeOfMD = decode!size_t(stream);
        stream = stream[size_t.sizeof..$];

        Chunk chunk = new Chunk();
        chunk.constTable = ConstTable.deserialize(stream);
        chunk.bytecode = decode!(ubyte[])(stream);
        stream = stream[size_t.sizeof..$];
        stream = stream[chunk.bytecode.length * ubyte.sizeof .. $];
        chunk.constTable.seal(); // there is no hashmap so it's not possible to add anymore values
        return chunk;
    }

    /// enums used when serializing to and from file in the future
    static const uint MAGIC = 0xB00BA911;
    /// see above
    static const uint MAGIC_REVERSE = 0x11A90BB0;
    /// binary file format version
    static const ubyte VERSION = 0x01; // file format version
}

/// Thrown when decoding binary chunk fails
class ChunkDecodeException : Exception
{
    /// ctor
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}