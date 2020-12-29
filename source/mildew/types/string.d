module mildew.types.string;

import mildew.types.object;

/**
 * Encapsulates a UTF-8 string.
 */
class ScriptString : ScriptObject
{
    import std.conv: to;
public:
    /**
     * Constructs a new ScriptString out of a UTF-8 D string
     */
    this(in string str)
    {
        import mildew.types.prototypes: getStringPrototype;
        super("string", getStringPrototype, null);
        _wstring = str.to!wstring;
    }

    /**
     * Returns the actual D string contained
     */
    override string toString() const
    {
        return _wstring.to!string;
    }

    /**
     * Gets the internally stored UTF-16 string
     */
    wstring getWString() const
    {
        return _wstring;
    }

    // methods to bind

package:
    wchar charAt(size_t index)
    {
        if(index >= _wstring.length)
            return '\0';
        return _wstring[index];
    }

    ushort charCodeAt(size_t index)
    {
        if(index >= _wstring.length)
            return 0;
        return cast(ushort)(_wstring[index]);
    }

private:
    wstring _wstring;
}