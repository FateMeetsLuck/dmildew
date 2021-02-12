/// This module implements the ConstTable class
module mildew.vm.consttable;

import mildew.types.any;
import mildew.util.encode;

/**
 * This is a wrapper around a dynamic array. When a value is added, ConstTable determines if the value is
 * already in the entries or adds a new entry and returns the index. A ConstTable is shared among all
 * Chunks compiled under the same Compiler.compile call.
 */
class ConstTable
{
public:
    /// add a possibly new value to table and return its index.
    size_t addValue(ScriptAny value)
    {
        // already in table?
        if(value in _lookup)
        {
            return _lookup[value];
        }
        // have to add new one
        auto location = _constants.length;
        _lookup[value] = location;
        _constants ~= value;
        return location;
    }

    /// same as addValue but returns an uint for easy encoding
    uint addValueUint(ScriptAny value)
    {
        return cast(uint)addValue(value);
    }

    /// get a specific constant
    ScriptAny get(size_t index) const
    {
        import std.format: format;
        if(index >= _constants.length)
            throw new Exception(format("index %s is greater than %s", index, _constants.length));
        return cast(immutable)_constants[index];
    }

    /// foreach over const table
    int opApply(scope int delegate(size_t index, ScriptAny value) dg)
    {
        int result = 0;
        foreach (index, item; _constants)
        {
            result = dg(index, item);
            if (result)
                break;
        }
        return result;
    }

    /// convert const table to ubytes
    ubyte[] serialize()
    {
        ubyte[] data = encode!size_t(_constants.length);
        for(auto i = 0; i < _constants.length; ++i)
        {
            data ~= _constants[i].serialize();
        }
        return data;
    }

    /// reads a ConstTable from an ubyte stream
    static ConstTable deserialize(ref ubyte[] stream)
    {
        auto ct = new ConstTable();
        ct._constants.length = decode!size_t(stream.ptr);
        stream = stream[size_t.sizeof..$];
        for(auto i = 0; i < ct._constants.length; ++i)
            ct._constants[i] = ScriptAny.deserialize(stream);
        return ct;
    }

private:
    ScriptAny[] _constants;
    size_t[ScriptAny] _lookup;
}