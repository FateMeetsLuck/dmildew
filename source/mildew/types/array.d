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
     * Takes a D array of ScriptAnys
     */
    this(ScriptAny[] values)
    {
        import mildew.types.prototypes: getArrayPrototype;
        super("array", getArrayPrototype, null);
        _array = values;
    }

    /**
     * Returns the length of the array
     */
    size_t length() const { return _array.length; }

    /**
     * This override allows for the length pseudoproperty
     */
    override ScriptAny lookupField(in string name)
    {
        if(name == "length")
            return ScriptAny(_array.length);
        else
            return super.lookupField(name);
    }

    /**
     * This override allows for the length to be reassigned
     */
    override ScriptAny assignField(in string name, ScriptAny value)
    {
        if(name == "length")
            return ScriptAny(_array.length = value.toValue!size_t);
        else
            return super.assignField(name, value);
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

