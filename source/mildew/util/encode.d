/**
This module implements functions for encoding various D types into ubyte arrays. Note that the encoding is not
cross platform and results will be different across platforms depending on CPU architecture.

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
module mildew.util.encode;

import std.traits: isBasicType;

debug import std.stdio;

/** 
 * Encodes a value as an ubyte array. Note that only simple types, and arrays of simple types can be encoded.
 * Params:
 *  value = The value to be encoded.
 * Returns:
 *  The value stored as an ubyte[]
 */
ubyte[] encode(T)(T value)
{
	ubyte[] encoding;
	static if(isBasicType!T)
	{
		encoding ~= (cast(ubyte*)&value)[0..T.sizeof];
	}
	else static if(is(T == E[], E))
	{
        static assert(isBasicType!E, "Only arrays of basic types are supported");
		size_t size = value.length;
		encoding ~= (cast(ubyte*)&size)[0..size.sizeof];
        foreach(item ; value)
            encoding ~= encode(item);
	}
	else
	{
		static assert(false, "Unable to encode type " ~ T.stringof);
	}
	return encoding;
}

/** 
 * decode a value from an ubyte range.
 * Params:
 *  data = An ubyte[] that should be large enough to contain T.sizeof otherwise an exception is thrown.
 * Returns:
 *  The decoded piece of data described by type T.
 */
T decode(T)(const ubyte[] data)
{
    static if(isBasicType!T)
    {
        if(data.length < T.sizeof)
            throw new EncodeException("Data length is too short for type " ~ T.stringof);
        return *cast(T*)(data.ptr);
    }
    else static if(is(T==E[], E))
    {
        static assert(isBasicType!E, "Only arrays of basic types are supported");
        if(data.length < size_t.sizeof)
            throw new EncodeException("Data length is shorter than size_t for " ~ T.stringof);
        size_t size = *cast(size_t*)(data.ptr);
        if(data.length < size_t.sizeof + E.sizeof * size)
            throw new EncodeException("Data length is too short for array elements " ~ E.stringof);
        T array = new T(size);
        static if(is(E==ubyte))
        {
            for(size_t i = 0; i < size; ++i)
                array[i] = cast(E)data[size_t.sizeof + i];
        }
        else
        {
            for(size_t i = 0; i < size; ++i)
                array[i] = cast(E)decode!E(data[size_t.sizeof + i * E.sizeof..$]);
        }
        return array;
    }
    else static assert(false, "Unable to decode type " ~ T.stringof);
}

/// Thrown when decoding
class EncodeException : Exception
{
    /// ctor
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

unittest
{
    import std.format: format;
    auto testInts = [1, 5, 9];
    auto encoded = encode(testInts);
    auto decoded = decode!(int[])(encoded[0..$]);
    assert(decoded.length == 3);
    assert(decoded[0] == 1, "Value is actually " ~ format("%x", decoded[0]));
    assert(decoded[1] == 5);
    assert(decoded[2] == 9);
}