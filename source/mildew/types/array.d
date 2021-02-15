/**
This module implements how arrays are internally handled. There is no reason to use this instead of constructing a
ScriptAny with a D array or using toValue!(ScriptAny[]) on a ScriptAny that stores an array. 
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
module mildew.types.array;

import mildew.types.object: ScriptObject;

/**
 * Implements arrays of ScriptAny values
 */
class ScriptArray : ScriptObject
{
    import mildew.types.any: ScriptAny;
    import mildew.interpreter: Interpreter;
public:

    /**
     * Takes a D array of ScriptAnys
     */
    this(ScriptAny[] values)
    {
        import mildew.types.bindings: getArrayPrototype;
        super("array", getArrayPrototype, null);
        _array = values;
    }

    /**
     * Returns the length of the array
     */
    size_t length() const { return _array.length; }

    /**
     * Returns a string representation of the array, which is [] surrounding a comma separated
     * list of elements.
     */
    override string toString() const 
    {
        auto str = "[";
        for(size_t i = 0; i < _array.length; ++i)
        {
            str ~= _array[i].toString();
            if(i < _array.length - 1) // @suppress(dscanner.suspicious.length_subtraction)
                str ~= ", ";
        }
        str ~= "]";
        return str;
    }

    /// The actual array
    ref ScriptAny[] array() { return _array; }
    /// ditto
    ref ScriptAny[] array(ScriptAny[] ar) { return _array = ar; } 

private:

    ScriptAny[] _array;
}

