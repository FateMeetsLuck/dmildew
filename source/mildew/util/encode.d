module mildew.util.encode;

import core.stdc.string;
import std.range.primitives: ElementType;
import std.traits: isBasicType, isArray;

debug import std.stdio;

/// encodes a value as an ubyte array
ubyte[] encode(T)(T value)
{
	ubyte[] encoding;
	static if(isBasicType!T)
	{
		encoding ~= (cast(ubyte*)&value)[0..T.sizeof];
	}
	else static if(isArray!T)
	{
		size_t size = value.length;
		encoding ~= (cast(ubyte*)&size)[0..size.sizeof];
		encoding ~= (cast(ubyte*)value.ptr)[0 .. value.length * ElementType!(T).sizeof];
	}
	else
	{
		static assert(false, "Unable to encode type " ~ T.stringof);
	}
	return encoding;
}

/// decode a value from an ubyte pointer address
T decode(T)(in ubyte* ptr)
{
    static if(isBasicType!T)
    {
        return *cast(T*)ptr;
    }
    else static if(isArray!T)
    {
        static assert(isBasicType!(ElementType!T), "Only arrays of basic types are supported");
        size_t size = *cast(size_t*)ptr;
        T array;
        array.length = size;
        memcpy(array.ptr, ptr+size_t.sizeof, size * ElementType!(T).sizeof);
        return array;
    }
    else static assert(false, "Unable to decode type " ~ T.stringof);
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