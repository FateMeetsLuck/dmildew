module mildew.types.func;

import mildew.context: Context;
import mildew.types.any: ScriptAny;
import mildew.types.object: ScriptObject;

/** When a native function or delegate encounters an error with the arguments sent,
 *  the last reference parameter should be set to the appropriate enum value.
 *  A specific exception can be thrown by setting the flag to RETURN_VALUE_IS_EXCEPTION and
 *  returning a string.
 */
enum NativeFunctionError 
{
    NO_ERROR = 0,
    WRONG_NUMBER_OF_ARGS,
    WRONG_TYPE_OF_ARG,
    RETURN_VALUE_IS_EXCEPTION
}

/// native function signature to be usable by scripting language
alias NativeFunction = ScriptAny function(Context, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError);
/// native delegate signature to be usable by scripting language
alias NativeDelegate = ScriptAny delegate(Context, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError);

/**
 * This class encapsulates all types of script functions including native D functions and delegates. A
 * native function must first be wrapped in this class before it can be given to a ScriptAny assignment.
 * When an object is created with "new FunctionName()" its __proto__ is assigned to the function's "prototype"
 * field. This allows OOP in the scripting language and is somewhat analogous to JavaScript.
 */
class ScriptFunction : ScriptObject
{
    import mildew.nodes: StatementNode;
public:
    /// The type of function held by the object
    enum Type { SCRIPT_FUNCTION, NATIVE_FUNCTION, NATIVE_DELEGATE }
    /// whether or not the function is to be used with UFCS
    enum PropertyFlag { NONE, GETTER, GETSET }

    /**
     * Constructs a new ScriptFunction out of a native D function.
     * Params:
     *  fname = The name of the function.
     *  nfunc = The address of the native function. See NativeFunction alias for correct signature
     */
    this(string fname, NativeFunction nfunc, bool isClass = false, PropertyFlag propFlag = PropertyFlag.NONE)
    {
        immutable tname = isClass? "class" : "function";
        import mildew.types.prototypes: getFunctionPrototype;
        super(tname, getFunctionPrototype, null);
        _functionName = fname;
        initializePrototypeProperty();
        _type = Type.NATIVE_FUNCTION;
        _propertyFlag = propFlag;
        _nativeFunction = nfunc;
    }

    /**
     * Constructs a new ScriptFunction out of a native D delegate.
     * Params:
     *  fname = The name of the function.
     *  nfunc = The address of the native delegate. See NativeDelegate alias for correct signature
     */
    this(string fname, NativeDelegate ndele, bool isClass = false, PropertyFlag propFlag = PropertyFlag.NONE)
    {
        immutable tname = isClass? "class" : "function";
        import mildew.types.prototypes: getFunctionPrototype;
        super(tname, getFunctionPrototype, null);
        _functionName = fname;
        initializePrototypeProperty();
        _type = Type.NATIVE_DELEGATE;
        _propertyFlag = propFlag;
        _nativeDelegate = ndele;
    }

    /// Returns a string representing the type and name.
    override string toString() const
    {
        return name ~ " " ~ _functionName;
    }

    /// Returns the type of function stored, such as native function, delegate, or script function
    auto type() const { return _type; }
    /// Returns the property flag
    auto propertyFlag() const { return _propertyFlag; }
    /// Returns the name of the function
    auto functionName() const { return _functionName; }
    /// Property argNames
    auto argNames() { return _argNames; }

package(mildew):

    /**
     * Constructor for creating script defined functions.
     */
    this(string fnname, string[] args, StatementNode[] statementNodes, bool isClass=false, 
         PropertyFlag propFlag = PropertyFlag.NONE)
    {
        immutable tname = isClass? "class" : "function";
        import mildew.types.prototypes: getFunctionPrototype;
        super(tname, getFunctionPrototype, null);
        _functionName = fnname;
        _argNames = args;
        _statementNodes = statementNodes;
        initializePrototypeProperty();
        _type = Type.SCRIPT_FUNCTION;
        _propertyFlag = propFlag;
    }

    /**
     * Calls a function with a specified "this" object. This can be used by the syntax tree system.
     */
    auto call(Context context, ScriptAny thisObj, ScriptAny[] args, bool returnThis = false)
    {
        import mildew.nodes: VisitResult, callFunction;
        return callFunction(context, this, thisObj, args, returnThis);
    }

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

    /// Sets the function name
    auto functionName(in string fnName) { return _functionName = fnName; }

    /// Property statementNodes
    auto statementNodes() { return _statementNodes; }

    /// used by the parser for missing constructors in classes that don't extend
    static ScriptFunction emptyFunction(in string name, bool isClass)
    {
        return new ScriptFunction(name, &native_EMPTY_FUNCTION, isClass);
    }

private:
    Type _type;
    PropertyFlag _propertyFlag;
    string _functionName;
    string[] _argNames;
    StatementNode[] _statementNodes;
    union {
        NativeFunction _nativeFunction;
        NativeDelegate _nativeDelegate;
    }

    void initializePrototypeProperty()
    {
        _dictionary["prototype"] = ScriptAny(new ScriptObject("Object", null));
        _dictionary["prototype"]["constructor"] = ScriptAny(this);
    }

}

private ScriptAny native_EMPTY_FUNCTION(Context c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    return ScriptAny.UNDEFINED;
}

