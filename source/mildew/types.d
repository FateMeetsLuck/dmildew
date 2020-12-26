module mildew.types;

import std.conv: to;
import std.traits;

import mildew.context: Context;

/// When a native function or delegate encounters an error with the arguments sent,
/// the last reference parameter should be set to the appropriate enum value.
enum NativeFunctionError 
{
    NO_ERROR = 0,
    WRONG_NUMBER_OF_ARGS,
    WRONG_TYPE_OF_ARG,
    RETURN_VALUE_IS_EXCEPTION
}

/// native function signature to be usable by scripting language
alias NativeFunction = ScriptValue function(Context, ScriptValue* thisObj, ScriptValue[] args, ref NativeFunctionError);
/// native delegate signature to be usable by scripting language
alias NativeDelegate = ScriptValue delegate(Context, ScriptValue* thisObj, ScriptValue[] args, ref NativeFunctionError);

/// runtime polymorphic value type to hold anything usable in Mildew
/// TODO Arrays should be a subclass of ScriptObject to reflect JS semantics
struct ScriptValue
{
public:
    /// What type is currently being held
    enum Type 
    {
        NULL=0, UNDEFINED, BOOLEAN, INTEGER, DOUBLE, STRING, ARRAY, // add more later
        FUNCTION, OBJECT,
    }

    /// constructor
    this(T)(T value)
    {
        setValue!T(value);
    }

    /// opCast will be the error throwing checks for now
    T opCast(T)() const
    {
        return checkValue!T();
    }

    /// opAssign
    auto opAssign(T)(T value)
    {
        setValue(value);
        return this;
    }

    /// binary operations are only defined between ScriptValues. One must wrap a value in ScriptValue
    auto opBinary(string op)(auto ref const ScriptValue rhs) const
    {
        // if either value is undefined return undefined
        if(_type == Type.UNDEFINED || rhs._type == Type.UNDEFINED)
            return ScriptValue();
        
        static if(op == "+")
        {
            // if both are arrays concatenante
            if(_type == Type.ARRAY && rhs._type == Type.ARRAY)
            {
                auto concat = _asArray ~ rhs._asArray;
                return ScriptValue(cast(ScriptValue[])concat);
            }

            // if first is array and second isn't, concat second to first
            if(_type == Type.ARRAY && rhs._type != Type.ARRAY)
            {
                auto concat = _asArray ~ rhs;
                return ScriptValue(cast(ScriptValue[])concat);
            }

            // if either is string convert both to string and concatenate
            if(_type == Type.STRING || rhs._type == Type.STRING)
            {
                return ScriptValue(toString() ~ rhs.toString());
            }
            
            // if they are both numerical
            if(this.isNumber && rhs.isNumber)
            {
                // if either is floating point convert both to floating point and add
                if(_type == Type.DOUBLE || rhs._type == Type.DOUBLE)
                    return ScriptValue(toValue!double + rhs.toValue!double);
                // else an integer addition is fine
                else
                    return ScriptValue(toValue!long + rhs.toValue!long);
            }
            // else this makes no sense so return undefined
            else return UNDEFINED;
        }
        else static if(op == "-" || op == "*" || op == "%") // values can stay int here as well
        {
            // only makes sense for numbers
            if(!(this.isNumber && rhs.isNumber))
                return UNDEFINED;
            // if either is floating point convert both to float
            if(_type == Type.DOUBLE || rhs._type == Type.DOUBLE)
                mixin("return ScriptValue(toValue!double" ~ op ~ "rhs.toValue!double);");
            else // int is fine
                mixin("return ScriptValue(toValue!long" ~ op ~ "rhs.toValue!long);");
        }
        else static if(op == "/" || op == "^^") // must be doubles
        {
            // both must be casted to double
            if(!(this.isNumber && rhs.isNumber))
                return UNDEFINED;
            mixin("return ScriptValue(toValue!double" ~ op ~ "rhs.toValue!double);");
        }
        // for the bitwise operations the values MUST be cast to long
        else static if(op == "&" || op == "|" || op == "^" || op == "<<" || op == ">>" || op == ">>>")
        {
            if(!(this.isNumber && rhs.isNumber))
                return UNDEFINED;
            mixin("return ScriptValue(toValue!long" ~ op ~ "rhs.toValue!long);");
        }
        else
            static assert(false, "The binary operation " ~ op ~ " is not supported for this type");
    }

    /// unary ops. They must return a ScriptValue as well
    auto opUnary(string op)()
    {
        // any unary operation on undefined is undefined. Any of these on non-numbers is also undefined
        if(_type == Type.UNDEFINED || !this.isNumber)
            return UNDEFINED;
        // plus and minus can work on doubles or longs
        static if(op == "+" || op == "-")
        {
            if(_type == Type.DOUBLE)
                mixin("return ScriptValue(" ~ op ~ " toValue!double);");
            else
                mixin("return ScriptValue(" ~ op ~ " toValue!long);");
        }
        // bit not only works on integers
        else static if(op == "~")
        {
            return ScriptValue(~toValue!long);
        }
        else // increment and decrement have to be handled by the scripting environment
            static assert(false, "Unary operator " ~ op ~ " is not implemented for this type");
    }

    bool opEquals(const ScriptValue other) const
    {
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
            return _asArray == other._asArray;

        // if both are functions or objects, compare for exactness
        if((_type == Type.FUNCTION && other._type == Type.FUNCTION) ||
            (_type == Type.OBJECT && other._type == Type.OBJECT))
            return _asObjectOrFunction is other._asObjectOrFunction;

        // if we get to this point the objects are not equal
        return false;
    }

    int opCmp(const ScriptValue other) const
    {
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

        // for now, an array is always greater than a non array
        if(_type != Type.ARRAY && other._type == Type.ARRAY)
            return -1;
        else if(_type == Type.ARRAY && other._type != Type.ARRAY)
            return 1;
        else if(_type == Type.ARRAY && other._type == Type.ARRAY)
        {
            if(_asArray < other._asArray)
                return -1;
            else if(_asArray > other._asArray)
                return 1;
            else
                return 0;
        }

        // TODO handle object and functions

        // TODO handle native functions and delegates. Not sure how that comparison should work
        // throw new ScriptValueException("Unable to compare " ~ this.toString ~ " to " ~ other.toString, other);
        return -1; // for now
    }

    size_t toHash() const nothrow
    {
        final switch(_type)
        {
            case Type.UNDEFINED:
            case Type.NULL:
                return 0; // i don't know what to do for those
            case Type.BOOLEAN:
                return typeid(_asBoolean).getHash(&_asBoolean);
            case Type.INTEGER:
                return typeid(_asInteger).getHash(&_asInteger);
            case Type.DOUBLE:
                return typeid(_asDouble).getHash(&_asDouble);
            case Type.STRING:
                return typeid(_asString).getHash(&_asString);
            case Type.ARRAY:
                return typeid(_asArray).getHash(&_asArray);
            case Type.FUNCTION: case Type.OBJECT:
                return typeid(_asObjectOrFunction).getHash(&_asObjectOrFunction);
        }    
    }

    /// for primitives must be same exact type and value
    bool strictEquals(const ScriptValue other)
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
                return _asString == other._asString;
            case Type.ARRAY:
                return _asArray == other._asArray;
            case Type.FUNCTION: case Type.OBJECT:
                return _asObjectOrFunction is other._asObjectOrFunction;
        }
    }

    /// type property
    auto type() const nothrow @nogc { return _type; }

    /// undefined property
    auto isUndefined() const nothrow @nogc { return _type == Type.UNDEFINED; }

    /// null property
    auto isNull() const nothrow @nogc 
    { 
        if(_type == Type.NULL)
            return true;
        if(_type == Type.FUNCTION || _type == Type.OBJECT)
            return _asObjectOrFunction is null;
        return false;
    }

    /// isNumber property
    auto isNumber() const nothrow @nogc
    {
        return _type == Type.NULL || _type == Type.BOOLEAN || _type == Type.INTEGER || _type == Type.DOUBLE;
    }

    /// isInteger property
    auto isInteger() const nothrow @nogc
    {
        return _type == Type.NULL || _type == Type.BOOLEAN || _type == Type.INTEGER;
    }

    /// whether it is a ScriptObject or subtype thereof
    auto isObject() const nothrow @nogc
    {
        return _type == Type.OBJECT || _type == Type.FUNCTION;
    }

    /// attempts to convert to respective values with exception throwing
    T checkValue(T)() const
    {
        return convertValue!T(true);
    }

    /// attempts to convert to respective sane value with no exception throwing
    T toValue(T)() const
    {
        return convertValue!T(false);    
    }

    /// for use with typeof operator
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
            case Type.ARRAY: return "array"; // add more later
            case Type.FUNCTION: return "function";
            case Type.OBJECT: return "object";
        }
    }

    /// toString
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
                return _asDouble.to!string;
            case Type.STRING:
                return _asString;
            case Type.ARRAY:
            {
                auto str = "[";
                for(size_t i = 0; i < _asArray.length ; ++i)
                {
                    str ~= _asArray[i].toString();
                    if(i < _asArray.length - 1) // @suppress(dscanner.suspicious.length_subtraction)
                        str ~= ", ";
                }
                str ~= "]";
                return str;
            }
            case Type.FUNCTION: case Type.OBJECT:
            {
                if(_asObjectOrFunction !is null)
                    return _asObjectOrFunction.toString;
                return "null";
            }
        }
    }

    /// represents null (probably will be replaced by DObject with null value)
    static immutable NULL = ScriptValue(null);
    /// represents undefined results
    static immutable UNDEFINED = ScriptValue();

private:

    void setValue(T)(T value)
    {
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
            _asString = to!string(value);
        }
        else static if(isArray!T)
        {
            _type = Type.ARRAY;
            _asArray = [];
            foreach(item; value)
            {
                _asArray ~= ScriptValue(item);
            }
        }
        else static if(is(T == ScriptFunction)) // only accept pointers
        {
            _type = Type.FUNCTION;
            _asObjectOrFunction = value;
        }
        else static if(is(T == ScriptObject))
        {
            _type = Type.OBJECT;
            _asObjectOrFunction = value;
        }
        else static if(is(T == ScriptValue) || is(T == immutable(ScriptValue)))
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
                    this._asString = value._asString;
                    break;
                case Type.ARRAY:
                    this._asArray = cast(ScriptValue[])(value._asArray);
                    break;
                case Type.FUNCTION: case Type.OBJECT:
                    this._asObjectOrFunction = cast(ScriptObject)(value._asObjectOrFunction);
                    break;
            }
        }
        else static if(is(T == typeof(null)))
        {
            _type = Type.NULL;
            _asObjectOrFunction = null;
        }
        else
            static assert(false, "This type is not supported: " ~ T.stringof);
    }

    T convertValue(T)(bool throwing) const
    {
        static if(isBoolean!T)
        {
            // for now until we get objects and C-pointers
            if (_type == Type.BOOLEAN)
                return _asBoolean;
            else if (this.isNumber())
                return convertValue!double(throwing) != 0.0;
            else if(_type == Type.STRING)
                return _asString != null;
            else if(_type == Type.ARRAY)
                return _asArray != null;
            else
                return _type != Type.NULL && _type != Type.UNDEFINED;
        }
        else static if(isIntegral!T || isFloatingPoint!T)
        {
            if(!this.isNumber())
            {
                if(throwing)
                    throw new ScriptValueException("Unable to convert value " ~ toString ~ " to number", this);
                else
                    return cast(T)0;
            }
            else if(_type == Type.BOOLEAN)
                return cast(T)_asBoolean;
            else if(_type == Type.INTEGER)
                return cast(T)_asInteger;
            else if(_type == Type.DOUBLE)
                return cast(T)_asDouble;
            else // if null or whatever
                return 0;
        }
        else static if(isSomeString!T)
        {
            return to!T(toString());
        }
        else static if(is(T == ScriptValue[]))
        {
            if(_type != Type.ARRAY)
            {
                if(throwing)
                    throw new ScriptValueException("ScriptValue " ~ toString ~ " is not an array", this);
                else
                    return cast(T)null;
            }
            else
                return cast(ScriptValue[])_asArray;
        }
        else static if(is(T : E[], E))
        {
            if(_type != Type.ARRAY)
            {
                if(throwing)
                    throw new ScriptValueException("ScriptValue " ~ toString ~ " is not an array", this);
                else
                    return cast(T)null;
            }
            else
            {
                T arrayToFill = [];
                foreach(item ; _asArray)
                {
                    arrayToFill ~= item.convertValue!E(throwing);
                }
                return arrayToFill;
            }          
        }
        else static if(is(T == ScriptFunction))
        {
            if(_type != Type.FUNCTION)
            {
                if(throwing)
                    throw new ScriptValueException("ScriptValue " ~ toString ~ " is not a function", this);
                else
                    return cast(T)null;
            }
            else
            {
                return cast(T)_asObjectOrFunction;
            }
        }
        else static if(is(T == ScriptObject))
        {
            if(_type != Type.OBJECT && _type != Type.FUNCTION)
            {
                if(throwing)
                    throw new ScriptValueException("ScriptValue " ~ toString ~ " is not an object", this);
                else
                    return cast(T)null;
            }
            else
            {
                return cast(T)_asObjectOrFunction;
            }
        }
        // else TODO cast NativeObjects from the stored in ScriptObject
    }

    Type _type = Type.UNDEFINED;

    union
    {
        bool _asBoolean;
        long _asInteger;
        double _asDouble;
        string _asString;
        ScriptValue[] _asArray;
        NativeFunction _asNativeFunction;
        NativeDelegate _asNativeDelegate;
        ScriptObject _asObjectOrFunction;
    }
}

/// Object class
class ScriptObject
{
public:
    /// constructor
    this(in string typename, ScriptObject proto, Object native = null)
    {
        _name = typename;
        _prototype = proto;
        _nativeObject = native;
        _members["__proto__"] = ScriptValue(proto);
    }

    /// empty constructor
    this()
    {

    }

    ScriptValue opIndex(in string index)
    {
        // first handle special property __proto__
        if(index == "__proto__")
        {
            auto proto = ScriptValue(_prototype);
            return proto;
        }

        auto objectToSearch = this;
        while(objectToSearch !is null)
        {
            if(index in objectToSearch._members)
                return objectToSearch._members[index];
            objectToSearch = objectToSearch._prototype;
        }
        return ScriptValue.UNDEFINED;
    }

    ScriptValue opIndexAssign(ScriptValue value, in string index)
    {
        if(index == "__proto__")
            _prototype = value.toValue!ScriptObject; // can be null if not object
        _members[index] = value;
        return _members[index];
    }

    /// name property
    string name() const { return _name; }

    /// prototype property
    auto prototype() { return _prototype; }

    /// property set prototype
    auto prototype(ScriptObject proto) { return _prototype = proto; }

    /// members
    auto members() { return _members; }

    /// to native object
    T nativeObject(T)()
    {
        static if(is(T == class) || is(T == interface))
            return cast(T)nativeObject;
        else
            static assert(false, "This method can only be used with D classes and interfaces");
    }

    /// as string
    override string toString() const
    {
        return _name ~ formattedString();
    }

private:

    string formattedString(int indent = 0) const
    {
        auto result = "{";
        foreach(k, v ; _members)
        {
            for(int i = 0; i < indent; ++i)
                result ~= "    ";
            result ~= k ~ " : ";
            if(v.type == ScriptValue.Type.OBJECT)
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
            result ~= "    ";
        result ~= "}\n";
        return result;
    }

    /// type name (Function or whatever)
    string _name;
    /// members
    ScriptValue[string] _members;
    /// it can also hold a native object
    Object _nativeObject;
    /// prototype 
    ScriptObject _prototype;
}

/// A function defined with the scripting language
class ScriptFunction : ScriptObject
{
    import mildew.nodes: StatementNode;
public:
    enum Type { SCRIPT_FUNCTION, NATIVE_FUNCTION, NATIVE_DELEGATE }

    this(string fnname, string[] args, StatementNode[] statementNodes)
    {
        super("Function", new ScriptObject(), null);
        _functionName = fnname;
        _argNames = args;
        _statementNodes = statementNodes;
        _members["prototype"] = _prototype;
        _type = Type.SCRIPT_FUNCTION;
    }

    this(string fname, NativeFunction nfunc)
    {
        super("Function", new ScriptObject(), null);
        _functionName = fname;
        _members["prototype"] = _prototype;
        _type = Type.NATIVE_FUNCTION;
        _nativeFunction = nfunc;
    }

    this(string fname, NativeDelegate ndele)
    {
        super("Function", new ScriptObject(), null);
        _functionName = fname;
        _members["prototype"] = _prototype;
        _type = Type.NATIVE_DELEGATE;
        _nativeDelegate = ndele;
    }

    override string toString() const
    {
        return "Function " ~ _functionName;
    }

    // TODO opIndex and __proto__ handling

    override ScriptValue opIndexAssign(ScriptValue value, in string index)
    {
        // __proto__ should be a function but IDK what
        if(index == "prototype")
        {
            if(value.isObject)
            {
                _members[index] = value;
                _prototype = value.toValue!ScriptObject;
                return value;
            }
            return ScriptValue.UNDEFINED;
        }
        else
        {
            _members[index] = value;
        }
        return value;
    }

    auto type() const { return _type; }
    auto functionName() const { return _functionName; }
    auto functionName(in string fnName) { return _functionName = fnName; }
    auto argNames() { return _argNames; }
    auto statementNodes() { return _statementNodes; }

    // must check type before using these properties or one gets an exception

    /// get the native function ONLY if it is one
    auto nativeFunction()
    {
        if(_type == Type.NATIVE_FUNCTION)
            return _nativeFunction;
        else
            throw new Exception("This is not a native function");
    }

    /// get the delegate only if it is one
    auto nativeDelegate()
    {
        if(_type == Type.NATIVE_DELEGATE)
            return _nativeDelegate;
        else
            throw new Exception("This is not a native delegate");
    }

private:
    Type _type;
    string _functionName;
    string[] _argNames;
    StatementNode[] _statementNodes;
    union {
        NativeFunction _nativeFunction;
        NativeDelegate _nativeDelegate;
    }
}

/// exception thrown on failed conversions
class ScriptValueException : Exception
{
    /// ctor
    this(string msg, ScriptValue val, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
        value = val;
    }
    /// the offending value
    ScriptValue value;
}

unittest // TODO organize this
{
    import std.exception: assertThrown, assertNotThrown;
    import std.stdio: writeln;
    auto foo = ScriptValue(100);
    assert(foo.toValue!double == 100.0);
    assert(foo.checkValue!uint == 100);
    foo = "99.7"d;
    assertThrown(foo.checkValue!double, "Strings are not supposed to convert to numbers with this function");
    assert(foo.checkValue!string == "99.7");
    foo = true;
    assert(foo.toValue!long == 1L);
    foo = [1, 2, 3];
    writeln(foo);
    assert(foo.checkValue!bool);
    auto myIntArray = foo.checkValue!(int[])();
    assert(myIntArray[0] == 1);
    assertThrown(foo.checkValue!int);
    foo = "";
    assert(!foo.toValue!bool);
    foo = null;
    writeln(foo.type.to!string);
    foo = ["first", "second", "third"];
    assert(foo.checkValue!(string[])[1]=="second");
    assert((cast(string[])foo)[1] == "second");
    assertThrown(foo.checkValue!(int[]));
    foo = "foo";
    assertThrown(cast(int)foo);
    assertNotThrown(cast(dstring)foo);
    assert(ScriptValue() == ScriptValue.UNDEFINED);
    assert((ScriptValue(5.5) + ScriptValue(7)).toValue!double == 12.5);
    assert((ScriptValue(false) + ScriptValue(true)).toValue!long == 1L);
    foo = 25;
    auto bar = ScriptValue(25);
    assert(cast(int)(foo % bar) == 0);
    bar = 11;
    foo = 2;
    assert(cast(double)(bar / foo) == 5.5);
    bar = null;
    foo = true;
    assert(cast(long)(bar - foo) == -1);
    assert(cast(float)(bar & foo) == 0.0);
    assert(!bar);
    assert(cast(long)(~foo) == -2);
    assert(cast(double)(-foo) == -1.0);
    foo = 69.9;
    bar = 69;
    assert(foo > bar);
    assert(bar < foo);
    foo = [5, 6, 7, 8, 20];
    assert(foo > bar);
    assert(bar <= foo);
    ScriptValue rightSig(Context c, ScriptValue* thisObj, ScriptValue[] args, ref NativeFunctionError nfe) 
    { 
        return ScriptValue.UNDEFINED; 
    }
    foo = cast(NativeDelegate)&rightSig;
    assertNotThrown(cast(NativeDelegate)foo);
    auto func = cast(NativeDelegate)foo;
    NativeFunctionError nfe;
    assert(func(null, null, nfe) == ScriptValue.UNDEFINED);
}