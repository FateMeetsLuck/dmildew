module mildew.types.array;

import mildew.types.object: ScriptObject;

/**
 * Implements arrays of ScriptAny values
 */
class ScriptArray : ScriptObject
{
    import mildew.types.any: ScriptAny;
public:

    /**
     * Takes a primitive array.
     */
    this(ScriptAny[] values)
    {
        // TODO set up the prototype for all strings
        super("String", null, null);
        _array = values;
    }

    /**
     * Returns the length of the array
     */
    size_t length() const { return _array.length; }

    /**
     * This override allows for the length pseudoproperty
     */
    override ScriptAny lookupProperty(in string name)
    {
        if(name == "length")
            return ScriptAny(_array.length);
        else
            return super.lookupProperty(name);
    }

    /**
     * This override allows for the length to be reassigned
     */
    override ScriptAny assignProperty(in string name, ScriptAny value)
    {
        if(name == "length")
            return ScriptAny(_array.length = value.toValue!size_t);
        else
            return super.assignProperty(name, value);
    }

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

private:
    ScriptAny[] _array;
}