/**
 * This module implements the ScriptAny struct, which can hold any value type usable in the scripting language.
 */
module mildew.types.any;

import std.conv: to;
import std.traits;

/**
 * This variant holds primitive values as well as ScriptObject types.
 */
struct ScriptAny
{
    import mildew.types.object: ScriptObject;
    import mildew.types.func: ScriptFunction;

public:
    /**
     * Enumeration of what type is held by a ScriptAny. Note that a function, array, or string can be used
     * as an object.
     */
    enum Type 
    {
        /// primitives
        NULL=0, UNDEFINED, BOOLEAN, INTEGER, DOUBLE, 
        /// objects
        OBJECT, ARRAY, FUNCTION, STRING
    }

    /**
     * Constructs a new ScriptAny based on the value given.
     * Params:
     *  value = This can be any valid type such as null, bool, signed or unsigned ints or longs, floats,
     *          or doubles, strings, even primitive D arrays, as well as ScriptObject or ScriptFunction
     */
    this(T)(T value)
    {
        setValue!T(value);
    }

    /**
     * opCast will now use toValue
     */
    T opCast(T)() const
    {
        return toValue!T();
    }

    /**
     * Assigns a value.
     */
    auto opAssign(T)(T value)
    {
        setValue(value);
        return this;
    }

    /**
     * Implements binary math operations between two ScriptAnys and returns a ScriptAny. For
     * certain operations that make no sense the result will be NaN or UNDEFINED
     */
    auto opBinary(string op)(auto ref const ScriptAny rhs) const
    {
        // if either value is undefined return undefined
        if(_type == Type.UNDEFINED || rhs._type == Type.UNDEFINED)
            return UNDEFINED;
        
        static if(op == "+")
        {
            // if either is string convert both to string and concatenate
            if(_type == Type.STRING || rhs._type == Type.STRING)
            {
                return ScriptAny(toString() ~ rhs.toString());
            }
            
            // if they are both numerical
            if(this.isNumber && rhs.isNumber)
            {
                // if either is floating point convert both to floating point and add
                if(_type == Type.DOUBLE || rhs._type == Type.DOUBLE)
                    return ScriptAny(toValue!double + rhs.toValue!double);
                // else an integer addition is fine
                else
                    return ScriptAny(toValue!long + rhs.toValue!long);
            }
            // else this makes no sense so concatenate strings
            else return ScriptAny(toString() ~ rhs.toString());
        }
        else static if(op == "-" || op == "*" || op == "%") // values can stay int here as well
        {
            // only makes sense for numbers
            if(!(this.isNumber && rhs.isNumber))
                return ScriptAny(double.nan);
            // if either is floating point convert both to float
            if(_type == Type.DOUBLE || rhs._type == Type.DOUBLE)
                mixin("return ScriptAny(toValue!double" ~ op ~ "rhs.toValue!double);");
            else // int is fine
                mixin("return ScriptAny(toValue!long" ~ op ~ "rhs.toValue!long);");
        }
        else static if(op == "/" || op == "^^") // must be doubles
        {
            // both must be casted to double
            if(!(this.isNumber && rhs.isNumber))
                return ScriptAny(double.nan);
            mixin("return ScriptAny(toValue!double" ~ op ~ "rhs.toValue!double);");
        }
        // for the bitwise operations the values MUST be cast to long
        else static if(op == "&" || op == "|" || op == "^" || op == "<<" || op == ">>" || op == ">>>")
        {
            if(!(this.isNumber && rhs.isNumber))
                return ScriptAny(0);
            mixin("return ScriptAny(toValue!long" ~ op ~ "rhs.toValue!long);");
        }
        else
            static assert(false, "The binary operation " ~ op ~ " is not supported for this type");
    }

    /**
     * A method so that (undefined || 22) results in 22.
     */
    ScriptAny orOp(ScriptAny other)
    {
        if(!cast(bool)this)
            return other;
        else
            return this;
    }

    /**
     * Depending on the type of index, if it is a string it accesses a field of the object, otherwise
     * if it is numerical, attempts to access an index of an array object.
     */
    ScriptAny lookupField(T)(T index, out bool success)
    {
        import mildew.types.string: ScriptString;
        import mildew.types.array: ScriptArray;

        success = false;

        // number index only makes sense for strings and arrays
        static if(isIntegral!T)
        {
            if(!(_type == Type.ARRAY || _type == Type.STRING))
            {
                return UNDEFINED;
            }
            else if(_type == Type.ARRAY)
            {
                auto arr = cast(ScriptArray)_asObject;
                auto found = arr[index];
                if(found == null)
                    return UNDEFINED;
                success = true;
                return *found;
            }
            else if(_type == Type.STRING)
            {
                auto str = (cast(ScriptString)_asObject).toString();
                if(index < 0 || index >= str.length)
                    return UNDEFINED;
                success = true;
                return ScriptAny([str[index]]);
            }
            return ScriptAny.UNDEFINED;
        }
        // else it is a string so we are accessing an object property
        else static if(isSomeString!T)
        {
            if(!isObject)
                return UNDEFINED;
            success = true;
            return _asObject.lookupField(index.to!string);
        }
        else
            static assert(false, "Invalid index type");
    }

    /**
     * Overload to ignore the bool
     */
    ScriptAny lookupField(T)(T index)
    {
        bool ignore; // @suppress(dscanner.suspicious.unmodified)
        return lookupField(index, ignore);
    }

    /**
     * Attempt to assign a field of a complex object. This can be used to assign array indexes if
     * the index is a number.
     */
    ScriptAny assignField(T)(T index, ScriptAny value, out bool success)
    {
        import mildew.types.string: ScriptString;
        import mildew.types.array: ScriptArray;

        success = false;

        // number index only makes sense for arrays
        static if(isIntegral!T)
        {
            if(_type != Type.ARRAY)
            {
                return UNDEFINED;
            }
            else
            {
                auto arr = cast(ScriptArray)_asObject;
                auto found = (arr[index] = value);
                if(found == null)
                    return UNDEFINED;
                success = true;
                return *found;
            }
        }
        // else it is a string so we are accessing an object property
        else static if(isSomeString!T)
        {
            if(!isObject)
                return UNDEFINED;
            success = true;
            return _asObject.assignField(index.to!string, value);
        }
        else
            static assert(false, "Invalid index type");
    }

    /**
     * Overload to ignore the bool
     */
    ScriptAny assignField(T)(T index, ScriptAny value)
    {
        bool ignore; // @suppress(dscanner.suspicious.unmodified)
        return assignField(index, ignore);
    }

    /**
     * Add a get method to an object
     */
    void addGetterProperty(in string name, ScriptFunction func)
    {
        if(!isObject)
            return;
        _asObject.addGetterProperty(name, func);
    }

    /**
     * Add a set method to an object
     */
    void addSetterProperty(in string name, ScriptFunction func)
    {
        if(!isObject)
            return;
        _asObject.addSetterProperty(name, func);
    }

    /**
     * Defines unary math operations for a ScriptAny.
     */
    auto opUnary(string op)()
    {
        // plus and minus can work on doubles or longs
        static if(op == "-")
        {
            if(!isNumber)
                return ScriptAny(-double.nan);
            
            if(_type == Type.DOUBLE)
                mixin("return ScriptAny(" ~ op ~ " toValue!double);");
            else
                mixin("return ScriptAny(" ~ op ~ " toValue!long);");
        }
        else static if(op == "+")
        {
            return this; // no effect
        }
        // bit not only works on integers
        else static if(op == "~")
        {
            return ScriptAny(~toValue!long);
        }
        else // increment and decrement have to be handled by the scripting environment
            static assert(false, "Unary operator " ~ op ~ " is not implemented for this type");
    }

    /**
     * Tests for equality by casting similar types to the same type and comparing values. If the types
     * are too different to do this, the result is false.
     */
    bool opEquals(const ScriptAny other) const
    {
        import mildew.types.array : ScriptArray;

        // if both are undefined then return true
        if(_type == Type.UNDEFINED && other._type == Type.UNDEFINED)
            return true;
        // but if only one is undefined return false
        else if(_type == Type.UNDEFINED || other._type == Type.UNDEFINED)
            return false;
        
        // if either are strings, convert to string and compare
        if(_type == Type.STRING || other._type == Type.STRING)
            return toString() == other.toString();

        // if either is numeric
        if(this.isNumber() && other.isNumber())
        {
            // if one is double convert both to double and compare
            if(_type == Type.DOUBLE || other._type == Type.DOUBLE)
                return toValue!double == other.toValue!double;
            // otherwise return the integer comparison
            return toValue!long == other.toValue!long;
        }

        // if both are arrays do an array comparison which should recursively call opEquals on each item
        if(_type == Type.ARRAY && other._type == Type.ARRAY)
        {
            auto arr1 = cast(ScriptArray)_asObject;
            auto arr2 = cast(ScriptArray)(other._asObject);
            return arr1.array == arr2.array;
        }

        if(_type == Type.FUNCTION && other._type == Type.FUNCTION)
        {
            return (cast(ScriptFunction)_asObject).opEquals(cast(ScriptFunction)other._asObject);
        }

        // else compare the objects for now
        return _asObject == other._asObject;
    }

    /**
     * The comparison operations. Note that this only returns a meaningful, usable value if the values
     * are similar enough in type to be compared. For the purpose of the scripting language, invalid
     * comparisons do not throw an exception but they return a meaningless incorrect result.
     */
    int opCmp(const ScriptAny other) const
    {
        import mildew.types.array: ScriptArray;

        // undefined is always less than any defined value
        if(_type == Type.UNDEFINED && !other._type == Type.UNDEFINED)
            return -1;
        else if(_type != Type.UNDEFINED && other._type == Type.UNDEFINED)
            return 1;
        else if(_type == Type.UNDEFINED && other._type == Type.UNDEFINED)
            return 0;
        
        // if either are strings, convert and compare
        if(_type == Type.STRING || other._type == Type.STRING)
        {
            immutable str1 = toString();
            immutable str2 = other.toString();
            if(str1 < str2)
                return -1;
            else if(str1 > str2)
                return 1;
            else
                return 0;   
        }

        // if both are numeric convert to double or long as needed and compare
        if(this.isNumber && other.isNumber)
        {
            if(_type == Type.DOUBLE || other._type == Type.DOUBLE)
            {
                immutable num1 = toValue!double, num2 = other.toValue!double;
                if(num1 < num2)
                    return -1;
                else if(num1 > num2)
                    return 1;
                else
                    return 0;
            }
            else
            {
                immutable num1 = toValue!long, num2 = other.toValue!long;
                if(num1 < num2)
                    return -1;
                else if(num1 > num2)
                    return 1;
                else
                    return 0;                
            }
        }

        // if both are arrays they can be compared
        if(_type == Type.ARRAY && other._type == Type.ARRAY)
        {
            auto arr1 = cast(ScriptArray)_asObject;
            auto arr2 = cast(ScriptArray)(other._asObject);
            if(arr1 < arr2)
                return -1;
            else if(arr1 > arr2)
                return 1;
            else
                return 0;
        }

        // if both are functions they can be compared
        if(_type == Type.FUNCTION && other._type == Type.FUNCTION)
        {
            return (cast(ScriptFunction)_asObject).opCmp(cast(ScriptFunction)other._asObject);
        }

        // TODO write opCmp for object
        if(_asObject == other._asObject)
            return 0;

        return -1; // for now
    }

    /**
     * This allows ScriptAny to be used as a key index in a table, however the scripting language currently
     * only uses strings.
     */
    size_t toHash() const nothrow
    {
        import mildew.types.array: ScriptArray;
        final switch(_type)
        {
            case Type.UNDEFINED:
                return -1; // not sure what else to do
            case Type.NULL:
                return 0; // i don't know what to do for those
            case Type.BOOLEAN:
                return typeid(_asBoolean).getHash(&_asBoolean);
            case Type.INTEGER:
                return typeid(_asInteger).getHash(&_asInteger);
            case Type.DOUBLE:
                return typeid(_asDouble).getHash(&_asDouble);
            case Type.STRING:
            {
                try
                {
                    auto str = _asObject.toString();
                    return typeid(str).getHash(&str);
                }
                catch(Exception ex)
                {
                    return 0; // IDK
                }
            }
            case Type.ARRAY:
            {
                try 
                {
                    auto arr = (cast(ScriptArray)_asObject).array;
                    return typeid(arr).getHash(&arr);
                }
                catch(Exception ex)
                {
                    return 0; // IDK
                }
            }
            case Type.FUNCTION: 
            case Type.OBJECT:
                return typeid(_asObject).getHash(&_asObject);
        }
    }

    /**
     * This implements the '===' and '!==' operators. Objects must be exactly the same in type and value.
     * This operator should not be used on numerical primitives because true === 1 will return false.
     */
    bool strictEquals(const ScriptAny other)
    {
        if(_type != other._type)
            return false;
        
        final switch(_type)
        {
            case Type.UNDEFINED:
            case Type.NULL:
                return true;
            case Type.BOOLEAN:
                return _asBoolean == other._asBoolean;
            case Type.INTEGER:
                return _asInteger == other._asInteger;
            case Type.DOUBLE:
                return _asDouble == other._asDouble;
            case Type.STRING:
            case Type.ARRAY:
            case Type.FUNCTION: 
            case Type.OBJECT:
                return _asObject == other._asObject;
        }
    }

    /**
     * Returns the read-only type property. This should always be checked before using the
     * toValue or checkValue template to retrieve the stored D value.
     */
    auto type() const nothrow @nogc { return _type; }

    /**
     * Returns true if the type is UNDEFINED.
     */
    auto isUndefined() const nothrow @nogc { return _type == Type.UNDEFINED; }

    /**
     * Returns true if the type is NULL or if it an object or function whose stored value is null
     */
    auto isNull() const nothrow @nogc 
    { 
        if(_type == Type.NULL)
            return true;
        if(isObject)
            return _asObject is null;
        return false;
    }

    /**
     * Returns true if the value stored is a numerical type or anything that can be converted into a
     * valid number such as boolean, or even null, which gets converted to 0.
     */
    auto isNumber() const nothrow @nogc
    {
        return _type == Type.NULL || _type == Type.BOOLEAN || _type == Type.INTEGER || _type == Type.DOUBLE;
    }

    /**
     * Returns true if the value stored is a valid integer, but not a floating point number.
     */
    auto isInteger() const nothrow @nogc
    {
        return _type == Type.NULL || _type == Type.BOOLEAN || _type == Type.INTEGER;
    }

    /**
     * This should always be used instead of checking type==OBJECT because ScriptFunction, ScriptArray,
     * and ScriptString are valid subclasses of ScriptObject.
     */
    auto isObject() const nothrow @nogc
    {
        return _type == Type.ARRAY || _type == Type.STRING || _type == Type.OBJECT || _type == Type.FUNCTION;
    }

    /**
     * Converts a stored value back into a D value if it is valid, otherwise throws an exception.
     */
    T checkValue(T)() const
    {
        return convertValue!T(true);
    }

    /**
     * Similar to checkValue except if the type is invalid and doesn't match the template type, a sane
     * default value such as 0 or null is returned instead of throwing an exception.
     */
    T toValue(T)() const
    {
        return convertValue!T(false);    
    }

    /**
     * Shorthand for returning nativeObject from casting this to ScriptObject
     */
    T toNativeObject(T)() const
    {
        if(!isObject)
            return cast(T)null;
        return _asObject.nativeObject!T;
    }

    /// For use with the scripting language's typeof operator
    string typeToString() const
    {
        final switch(_type)
        {
            case Type.NULL: return "null";
            case Type.UNDEFINED: return "undefined";
            case Type.BOOLEAN: return "boolean";
            case Type.INTEGER: return "integer";
            case Type.DOUBLE: return "double";
            case Type.STRING: return "string";
            case Type.ARRAY: return "array";
            case Type.FUNCTION: return "function";
            case Type.OBJECT: return "object";
        }
    }

    /**
     * Shorthand to access fields of the complex object types
     */
    ScriptAny opIndex(in string index)
    {
        if(!isObject)
            return UNDEFINED;
        return _asObject.lookupField(index);
    }

    /**
     * Shorthand to assign fields of the complex object types
     */
    ScriptAny opIndexAssign(T)(T value, string index)
    {
        if(!isObject)
            return UNDEFINED;
        auto any = ScriptAny(value);
        _asObject.assignField(index, any);
        return any;
    }

    /// Returns a string representation of the stored value
    auto toString() const
    {
        import std.format: format;

        final switch(_type)
        {
            case Type.NULL:
                return "null";
            case Type.UNDEFINED:
                return "undefined";
            case Type.BOOLEAN:
                return _asBoolean.to!string;
            case Type.INTEGER:
                return _asInteger.to!string;
            case Type.DOUBLE:
                return format("%.15g", _asDouble);
            case Type.STRING:
            case Type.ARRAY:
            case Type.FUNCTION: 
            case Type.OBJECT:
                if(_asObject !is null)
                    return _asObject.toString();
                return "null";   
        }
    }

    /**
     * This should always be used to return an undefined value.
     */
    static immutable UNDEFINED = ScriptAny();

private:

    void setValue(T)(T value)
    {
        import mildew.types.array: ScriptArray;
        import mildew.types.func: ScriptFunction;
        import mildew.types.object: ScriptObject;
        import mildew.types.string: ScriptString;

        static if(isBoolean!T)
        {
            _type = Type.BOOLEAN;
            _asBoolean = value;
        }
        else static if(isIntegral!T)
        {
            _type = Type.INTEGER;
            _asInteger = cast(long)value;
        }
        else static if(isFloatingPoint!T)
        {
            _type = Type.DOUBLE;
            _asDouble = cast(double)value;
        }
        else static if(isSomeString!T)
        {
            _type = Type.STRING;
            _asObject = new ScriptString(value.to!string);
        }
        else static if(is(T == ScriptAny[]))
        {
            _type = Type.ARRAY;
            _asObject = new ScriptArray(value);
        }
        else static if(isArray!T)
        {
            _type = Type.ARRAY;
            ScriptAny[] arr;
            foreach(item; value)
            {
                arr ~= ScriptAny(item);
            }
            _asObject = new ScriptArray(arr);
        }
        else static if(is(T == ScriptFunction))
        {
            _type = Type.FUNCTION;
            _asObject = value;
            if(_asObject is null)
                _type = Type.NULL;
        }
        else static if(is(T == ScriptObject))
        {
            _type = Type.OBJECT;
            _asObject = value;
            if(_asObject is null)
                _type = Type.NULL;
        }
        else static if(is(T == ScriptAny) || is(T == immutable(ScriptAny)))
        {
            this._type = value._type;
            final switch(value._type)
            {
                case Type.UNDEFINED:
                case Type.NULL:
                    break;
                case Type.BOOLEAN:
                    this._asBoolean = value._asBoolean;
                    break;
                case Type.INTEGER:
                    this._asInteger = value._asInteger;
                    break;
                case Type.DOUBLE:
                    this._asDouble = value._asDouble;
                    break;
                case Type.STRING:
                case Type.ARRAY:
                case Type.FUNCTION:
                case Type.OBJECT:
                    this._asObject = cast(ScriptObject)(value._asObject);
                    break;
            }
        }
        else static if(is(T == typeof(null)))
        {
            _type = Type.NULL;
            _asObject = null;
        }
        else // can't directly set D objects because ScriptAny must be verified as a ScriptObject first!
            static assert(false, "This type is not supported: " ~ T.stringof);
    }

    T convertValue(T)(bool throwing) const
    {
        import mildew.types.string: ScriptString;
        import mildew.types.array: ScriptArray;
        import mildew.types.func: ScriptFunction;

        static if(isBoolean!T)
        {
            if(_type == Type.NULL || _type == Type.UNDEFINED)
                return false;
            else if (_type == Type.BOOLEAN)
                return _asBoolean;
            else if (this.isNumber())
                return convertValue!double(throwing) != 0.0;
            else if(_type == Type.STRING)
            {
                auto s = cast(ScriptString)_asObject;
                return s.toString() != "";
            }
            else if(_type == Type.ARRAY)
            {
                auto arr = cast(ScriptArray)_asObject;
                return arr.array.length != 0;
            }
            else
                return _asObject !is null;
        }
        else static if(isIntegral!T || isFloatingPoint!T)
        {
            if(!this.isNumber())
            {
                if(throwing)
                    throw new ScriptAnyException("Unable to convert value " ~ toString ~ " to number", this);
                else
                    return cast(T)0;
            }
            else if(_type == Type.BOOLEAN)
                return cast(T)_asBoolean;
            else if(_type == Type.INTEGER)
                return cast(T)_asInteger;
            else if(_type == Type.DOUBLE)
                return cast(T)_asDouble;
            else // if null
                return 0;
        }
        else static if(isSomeString!T)
        {
            return to!T(toString());
        }
        else static if(is(T == ScriptAny[]))
        {
            if(_type != Type.ARRAY)
            {
                if(throwing)
                    throw new ScriptAnyException("ScriptAny " ~ toString ~ " is not an array", this);
                else
                    return cast(T)null;
            }
            else
            {
                auto arr = cast(ScriptArray)_asObject;
                return cast(ScriptAny[])arr.array;
            }
        }
        else static if(is(T : E[], E))
        {
            if(_type != Type.ARRAY)
            {
                if(throwing)
                    throw new ScriptAnyException("ScriptAny " ~ toString ~ " is not an array", this);
                else
                    return cast(T)null;
            }
            T arrayToFill = [];
            auto scriptArray = cast(ScriptArray)_asObject;
            foreach(item ; scriptArray.array)
            {
                arrayToFill ~= item.convertValue!E(throwing);
            }
            return arrayToFill;
        }
        else static if(is(T == ScriptArray))
        {
            if(_type != Type.ARRAY)
            {
                if(throwing)
                    throw new ScriptAnyException("ScriptAny " ~ toString ~ " is not a ScriptArray", this);
                else
                    return cast(T)null;
            }
            return cast(T)_asObject;
        }
        else static if(is(T == ScriptString))
        {
            if(_type != Type.STRING)
            {
                if(throwing)
                    throw new ScriptAnyException("ScriptAny " ~ toString ~ " is not a ScriptString", this);
                else
                    return cast(T)null;
            }
            return cast(T)_asObject;
        }
        else static if(is(T == ScriptFunction))
        {
            if(_type != Type.FUNCTION)
            {
                if(throwing)
                    throw new ScriptAnyException("ScriptAny " ~ toString ~ " is not a ScriptFunction", this);
                else
                    return cast(T)null;
            }
            else
            {
                return cast(T)_asObject;
            }
        }
        else static if(is(T == ScriptObject))
        {
            if(!isObject)
            {
                if(throwing)
                    throw new ScriptAnyException("ScriptAny " ~ toString ~ " is not an object", this);
                else
                    return cast(T)null;
            }
            else
            {
                return cast(T)_asObject;
            }
        }
        else static if(is(T == class) || is(T == interface))
        {
            if(!isObject)
            {
                if(throwing)
                    throw new ScriptAnyException("ScriptAny " ~ toString ~ " cannot store a D object", this);
                else
                    return cast(T)null;
            }
            else
            {
                return _asObject.nativeObject!T;
            }
        }
        else
            static assert(false, "This type is not supported: " ~ T.stringof);
    }

    Type _type = Type.UNDEFINED;

    union
    {
        bool _asBoolean;
        long _asInteger;
        double _asDouble;
        /// this includes array, string, function, or object
        ScriptObject _asObject;
    }
}

/**
 * This exception is only thrown when using ScriptAny.checkValue. If checkValue is used to check arguments, the host
 * application running a script should catch this exception in addition to catching ScriptRuntimeException and
 * ScriptCompileException. Otherwise it makes sense to just use toValue after checking the type field of the ScriptAny
 * and setting the NativeFunctionError flag appropriately then returning ScriptAny.UNDEFINED.
 */
class ScriptAnyException : Exception
{
    /// ctor
    this(string msg, ScriptAny val, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
        value = val;
    }
    /// the offending value
    ScriptAny value;
}