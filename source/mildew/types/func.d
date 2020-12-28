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
 * When an object is created with "new FunctionName()" its prototype is assigned to the function's prototype.
 * This allows OOP in the scripting language and is somewhat analogous to JavaScript. A function's prototype
 * object is never null unless set to null, unlike ScriptObject.
 */
class ScriptFunction : ScriptObject
{
    import mildew.nodes: StatementNode;
public:
    /// The type of function held by the object
    enum Type { SCRIPT_FUNCTION, NATIVE_FUNCTION, NATIVE_DELEGATE }

    /**
     * Constructs a new ScriptFunction out of a native D function.
     * Params:
     *  fname = The name of the function.
     *  nfunc = The address of the native function. See NativeFunction alias for correct signature
     */
    this(string fname, NativeFunction nfunc)
    {
        super("Function", s_functionPrototypeObject, null);
        _functionName = fname;
        initializePrototypeProperty();
        _type = Type.NATIVE_FUNCTION;
        _nativeFunction = nfunc;
    }

    /**
     * Constructs a new ScriptFunction out of a native D delegate.
     * Params:
     *  fname = The name of the function.
     *  nfunc = The address of the native delegate. See NativeDelegate alias for correct signature
     */
    this(string fname, NativeDelegate ndele)
    {
        super("Function", s_functionPrototypeObject, null);
        _functionName = fname;
        initializePrototypeProperty();
        _type = Type.NATIVE_DELEGATE;
        _nativeDelegate = ndele;
    }

    /**
     * Constructor for creating script defined functions.
     */
    this(string fnname, string[] args, StatementNode[] statementNodes)
    {
        super("Function", s_functionPrototypeObject, null);
        _functionName = fnname;
        _argNames = args;
        _statementNodes = statementNodes;
        initializePrototypeProperty();
        _type = Type.SCRIPT_FUNCTION;
    }

    /// Returns a string representing the type and name.
    override string toString() const
    {
        return "Function " ~ _functionName;
    }

    /// Returns the type of function stored, such as native function, delegate, or script function
    auto type() const { return _type; }
    /// Returns the name of the function
    auto functionName() const { return _functionName; }
    /// Sets the function name
    auto functionName(in string fnName) { return _functionName = fnName; }
    /// Property argNames
    auto argNames() { return _argNames; }
    /// Property statementNodes
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

    void initializePrototypeProperty()
    {
        _dictionary["prototype"] = ScriptAny(new ScriptObject("Object", null));
        _dictionary["prototype"]["constructor"] = ScriptAny(this);
    }

    static ScriptObject s_functionPrototypeObject;

    static this()
    {
        s_functionPrototypeObject = new ScriptObject("function()");
        s_functionPrototypeObject.assignProperty("call", 
            ScriptAny(new ScriptFunction("Function.call", &native_Function_call)));
    }
}

//
// Methods in the prototype ///////////////////////////////////////////////////
//

private ScriptAny native_Function_call(Context c, ScriptAny* thisIsFn, ScriptAny[] args, 
                                        ref NativeFunctionError nfe)
{
    import mildew.nodes: callFunction, VisitResult;

    // minimum args is 1 because first arg is the this to use
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    // get the function
    if(thisIsFn.type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto fn = thisIsFn.toValue!ScriptFunction;
    // set up the "this" to use
    auto thisToUse = args[0];
    // now send the remainder of the args to a called function with this setup
    args = args[1..$];
    auto vr = callFunction(c, fn, thisToUse, args, false);
    if(vr.exception !is null)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(vr.exception.message);
    }

    return vr.result;
}

