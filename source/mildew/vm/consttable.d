/** This module implements the ConstTable class

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
    
    // TODO option to finalize and destroy hash table when no more consts are to be added

    /// add a possibly new value to table and return its index.
    size_t addValue(ScriptAny value)
    {
        if(_isSealed)
            throw new Exception("Attempt to add to sealed const table");
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

    /**
     * Seal the const table so that no more constants can be added.
     */
    void seal() 
    {
        _isSealed = true;
        destroy(_lookup);
        _lookup = null;
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
        import mildew.types.func: ScriptFunction;
        auto ct = new ConstTable();
        ct._constants.length = decode!size_t(stream);
        stream = stream[size_t.sizeof..$];
        for(auto i = 0; i < ct._constants.length; ++i)
        {
            ct._constants[i] = ScriptAny.deserialize(stream);
            if(ct._constants[i].type == ScriptAny.Type.FUNCTION)
            {
                ct._constants[i].toValue!ScriptFunction().constTable = ct;
            }
        }
        return ct;
    }

private:
    ScriptAny[] _constants;
    size_t[ScriptAny] _lookup;
    bool _isSealed = false;
}