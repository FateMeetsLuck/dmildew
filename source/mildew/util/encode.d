/**
 * This module implements functions for encoding various D types into ubyte arrays. Note that the encoding is not
 * cross platform and results will be different across platforms depending on CPU architecture.
 */
module mildew.util.encode;

import std.traits: isBasicType;

debug import std.stdio;

/// encodes a value as an ubyte array
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

/// decode a value from an ubyte pointer address. TODO parameter should be ubyte[] range.
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
                array[i] = cast(T)decode!E(data[size_t.sizeof..$]);
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
    auto decoded = decode!(typeof(testInts))(encoded.ptr);
    assert(decoded.length == 3);
    assert(decoded[0] == 1, "Value is actually " ~ format("%x", decoded[0]));
    assert(decoded[1] == 5);
    assert(decoded[2] == 9);
}