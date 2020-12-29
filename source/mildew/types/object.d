module mildew.types.object;

/**
 * General Object class. Unlike JavaScript, the \_\_proto\_\_ property only shows up when asked for. This allows
 * allows objects to be used as dictionaries without extraneous values showing up in the for-of loop. Also,
 * objects' default \_\_proto\_\_ value is null unless native code creates an object with a specific prototype
 * object during construction.
 */
class ScriptObject
{
    import mildew.context: Context;
    import mildew.types.any: ScriptAny;
    import mildew.types.func: ScriptFunction;
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
     * Add a getter
     */
    void addGetterProperty(in string propName, ScriptFunction getter)
    {
        _getters[propName] = getter;
    }

    /**
     * Add a setter
     */
    void addSetterProperty(in string propName, ScriptFunction setter)
    {
        _setters[propName] = setter;
    }

    /**
     * Looks up a property or pseudoproperty through the prototype chain
     */
    ScriptAny lookupField(in string name)
    {
        if(name == "__proto__")
            return ScriptAny(_prototype);
        if(name in _dictionary)
            return _dictionary[name];
        if(_prototype !is null)
            return _prototype.lookupField(name);
        return ScriptAny.UNDEFINED;
    }

    /**
     * Shorthand for lookupProperty
     */
    ScriptAny opIndex(in string index)
    {
        return lookupField(index);
    }

    /**
     * Assigns a value to the current object
     */
    ScriptAny assignField(in string name, ScriptAny value)
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
     * Look up a property, not a field, with a getter if it exists
     */
    auto lookupProperty(Context context, in string propName)
    {
        import mildew.nodes: VisitResult;
        VisitResult vr;
        auto thisObj = this;
        auto objectToSearch = thisObj;
        while(objectToSearch !is null)
        {
            if(propName in objectToSearch._getters)
            {
                vr = objectToSearch._getters[propName].call(context, ScriptAny(thisObj), [], false);
                return vr;
            }
            objectToSearch = objectToSearch._prototype;
        }
        return vr;
    }

    /**
     * Set and return a property, not a field, with a setter
     */
    auto assignProperty(Context context, in string propName, ScriptAny arg)
    {
        import mildew.nodes: VisitResult;
        VisitResult vr;
        auto thisObj = this;
        auto objectToSearch = thisObj;
        while(objectToSearch !is null)
        {
            if(propName in objectToSearch._setters)
            {
                vr = objectToSearch._setters[propName].call(context, ScriptAny(thisObj), [arg], false);
            }
            objectToSearch = objectToSearch._prototype;
        }
        return vr;
    }

    /**
     * Determines if there is a getter for a given property
     */
    bool hasGetter(in string propName)
    {
        auto objectToSearch = this;
        while(objectToSearch !is null)
        {
            if(propName in objectToSearch._getters)
                return true;
            objectToSearch = objectToSearch._prototype;
        }
        return false;
    }

    /**
     * Determines if there is a setter for a given property
     */
    bool hasSetter(in string propName)
    {
        auto objectToSearch = this;
        while(objectToSearch !is null)
        {
            if(propName in objectToSearch._setters)
                return true;
            objectToSearch = objectToSearch._prototype;
        }
        return false;
    }

    /**
     * Shorthand for assignField
     */
    ScriptAny opIndexAssign(T)(T value, in string index)
    {
        static if(is(T==ScriptAny))
            return assignField(index, value);
        else
        {
            ScriptAny any = value;
            return assignField(index, any);
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

    /// The lookup table for getters
    ScriptFunction[string] _getters;

    /// The lookup table for setters
    ScriptFunction[string] _setters;

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
