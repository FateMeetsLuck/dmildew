/**
 * This module implements ScriptObject, the base class for builtin Mildew objects.
 */
module mildew.types.object;

/**
 * General Object class. Unlike JavaScript, the __proto__ property only shows up when asked for. This allows
 * allows objects to be used as dictionaries without extraneous values showing up in the for-of loop. Native D objects
 * can be stored in any ScriptObject or derived class by assigning it to its nativeObject field.
 */
class ScriptObject
{
    import mildew.types.any: ScriptAny;
    import mildew.types.func: ScriptFunction;
public:
    /**
     * Constructs a new ScriptObject that can be stored inside ScriptValue.
     * Params:
     *  typename = This does not have to be set to a meaningful value but constructors (calling script functions
     *             with the new keyword) set this value to the name of the function.
     *  proto = The object's __proto__ property. If a value is not found inside the current object's table, a chain
     *          of prototypes is searched until reaching a null prototype. If this parameter is null, the value is
     *          set to Object.prototype
     *  native = A ScriptObject can contain a native D object that can be accessed later. This is used for binding
     *           D classes.
     */
    this(in string typename, ScriptObject proto, Object native = null)
    {
        import mildew.types.bindings: getObjectPrototype;
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

	/// getters property
	auto getters() { return _getters; }
	/// setters property
	auto setters() { return _setters; }

    /// prototype property
    auto prototype() { return _prototype; }

    /// prototype property (setter)
    auto prototype(ScriptObject proto) { return _prototype = proto; }

    /// This property provides direct access to the dictionary
    auto dictionary() { return _dictionary; }

    /**
     * Add a getter. Getters should be added to a constructor function's "prototype" field
     */
    void addGetterProperty(in string propName, ScriptFunction getter)
    {
        _getters[propName] = getter;
    }

    /**
     * Add a setter. Setters should be added to a constructor function's "prototype" field
     */
    void addSetterProperty(in string propName, ScriptFunction setter)
    {
        _setters[propName] = setter;
    }

    /**
     * Looks up a field through the prototype chain. Note that this does not call any getters because
     * it is not possible to pass a Environment to opIndex.
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
     * Shorthand for lookupField.
     */
    ScriptAny opIndex(in string index)
    {
        return lookupField(index);
    }

    /**
     * Assigns a field to the current object. This does not call any setters.
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

    ScriptObject getOwnPropertyDescriptor(in string propName)
    {
        ScriptObject property = new ScriptObject("property", null);
        // find the getter
        auto objectToSearch = this;
        if(propName in objectToSearch._getters)
            property["get"] = objectToSearch._getters[propName];
        if(propName in objectToSearch._setters)
            property["set"] = objectToSearch._setters[propName];
        objectToSearch = objectToSearch._prototype;
        return property;
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
     * any nested objects. In the future this will be replaced and an explicit function call will be
     * required to print this detailed information.
     */
    override string toString() const
    {
        if(nativeObject!Object !is null)
            return nativeObject!Object.toString();
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

    // TODO complete rewrite
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
            result ~= ",";
        }
        // for(int i = 0; i < indent; ++i)
        //    result ~= indentation;
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
