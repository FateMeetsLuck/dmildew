module mildew.types.object;

/**
 * General Object class. Unlike JavaScript, the \_\_proto\_\_ property only shows up when asked for. This allows
 * allows objects to be used as dictionaries without extraneous values showing up in the for-of loop. Also,
 * objects' default \_\_proto\_\_ value is null unless native code creates an object with a specific prototype
 * object during construction.
 */
class ScriptObject
{
    import mildew.types.any: ScriptAny;
public:
    /**
     * Constructs a new ScriptObject that can be stored inside ScriptValue.
     * Params:
     *  typename = This does not have to be set to a meaningful value but constructors (calling script functions
     *             with the new keyword) set this value to the name of the function.
     *  proto = The object's \_\_proto\_\_ property. If a value is not found inside the current object's table, a chain
     *          of prototypes is searched until reaching a null prototype. This can be null.
     *  native = A ScriptObject can contain a native D object that can be accessed later. This is used for binding
     *           D classes.
     */
    this(in string typename, ScriptObject proto, Object native = null)
    {
        import mildew.types.prototypes: getObjectPrototype;
        _name = typename;
        if(proto !is null)
            _prototype = proto;
        else
            _prototype = getObjectPrototype;
        _nativeObject = native;
    }

    /**
     * Empty constructor that leaves prototype, and nativeObject as null.
     */
    this(in string typename)
    {
        _name = typename;
    }

    /// name property
    string name() const { return _name; }

    /// prototype property
    auto prototype() { return _prototype; }

    /// prototype property (setter)
    auto prototype(ScriptObject proto) { return _prototype = proto; }

    /// This property provides direct access to the dictionary
    auto dictionary() { return _dictionary; }

    /**
     * Looks up a property or pseudoproperty through the prototype chain
     */
    ScriptAny lookupProperty(in string name)
    {
        if(name == "__proto__")
            return ScriptAny(_prototype);
        if(name in _dictionary)
            return _dictionary[name];
        if(_prototype !is null)
            return _prototype.lookupProperty(name);
        return ScriptAny.UNDEFINED;
    }

    /**
     * Shorthand for lookupProperty
     */
    ScriptAny opIndex(in string index)
    {
        return lookupProperty(index);
    }

    /**
     * Assigns a value to the current object
     */
    ScriptAny assignProperty(in string name, ScriptAny value)
    {
        if(name == "__proto__")
        {
            _prototype = value.toValue!ScriptObject;
        }
        else
        {
            _dictionary[name] = value;
        }
        return value;
    }

    /**
     * Shorthand for assignProperty
     */
    ScriptAny opIndexAssign(T)(T value, in string index)
    {
        static if(is(T==ScriptAny))
            return assignProperty(index, value);
        else
        {
            ScriptAny any = value;
            return assignProperty(index, any);
        }
    }

    /**
     * If a native object was stored inside this ScriptObject, it can be retrieved with this function.
     * Note that one must always check that the return value isn't null because all functions can be
     * called with invalid "this" objects using functionName.call.
     */
    T nativeObject(T)() const
    {
        static if(is(T == class) || is(T == interface))
            return cast(T)_nativeObject;
        else
            static assert(false, "This method can only be used with D classes and interfaces");
    }

    /**
     * Native object can also be written in case of inheritance by script
     */
    T nativeObject(T)(T obj)
    {
        static if(is(T == class) || is(T == interface))
            return cast(T)(_nativeObject = obj);
        else
            static assert(false, "This method can only be used with D classes and interfaces");
    }

    /**
     * Returns a string with JSON like formatting representing the object's key-value pairs as well as
     * any nested objects.
     */
    override string toString() const
    {
        return _name ~ " " ~ formattedString();
    }
protected:

    /// The dictionary of key-value pairs
    ScriptAny[string] _dictionary;

private:

    string formattedString(int indent = 0) const
    {
        immutable indentation = "    ";
        auto result = "{";
        foreach(k, v ; _dictionary)
        {
            for(int i = 0; i < indent; ++i)
                result ~= indentation;
            result ~= k ~ ": ";
            if(v.type == ScriptAny.Type.OBJECT)
            {
                if(!v.isNull)
                    result ~= v.toValue!ScriptObject().formattedString(indent+1);
                else
                    result ~= "<null object>";
            }
            else
                result ~= v.toString();
            result ~= "\n";
        }
        for(int i = 0; i < indent; ++i)
            result ~= indentation;
        result ~= "}";
        return result;
    }

    /// type name (Function or whatever)
    string _name;
    /// it can also hold a native object
    Object _nativeObject;
    /// prototype 
    ScriptObject _prototype = null;
}
