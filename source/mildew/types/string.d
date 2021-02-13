/**
This module implements ScriptString. However, host applications should work with D strings by converting
the ScriptAny directly to string with toString().
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
module mildew.types.string;

import mildew.types.object;

/**
 * Encapsulates a string. It is stored internally as UTF-8 but is cast to UTF-16 for the
 * methods that access individual array indices. TODO: code point iteration
 */
class ScriptString : ScriptObject
{
    import std.conv: to;
    import mildew.types.any: ScriptAny;
public:
    /**
     * Constructs a new ScriptString out of a UTF-8 D string
     */
    this(in string str)
    {
        import mildew.types.bindings: getStringPrototype;
        super("string", getStringPrototype, null);
        _string = str;
    }

    /**
     * Returns the actual D string contained
     */
    override string toString() const
    {
        return _string;
    }

    /**
     * Gets the wstring UTF-16 representation
     */
    wstring getWString() const
    {
        return _string.to!wstring;
    }

    /**
     * This override allows for the length field
     */
    override ScriptAny lookupField(in string name)
    {
        if(name == "length")
            return ScriptAny(getWString.length);
        else
            return super.lookupField(name);
    }

    // methods to bind

package:
    // TODO catch utf exceptions or process sequentially
    wchar charAt(size_t index)
    {
        if(index >= getWString.length)
            return '\0';
        return getWString[index];
    }

    ushort charCodeAt(size_t index)
    {
        if(index >= getWString.length)
            return 0;
        return cast(ushort)(getWString[index]);
    }

private:
    string _string;
}