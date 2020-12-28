module mildew.types.prototypes;

package:

import mildew.context;
import mildew.types.any;
import mildew.types.array;
import mildew.types.func;
import mildew.types.string;
import mildew.types.object;

ScriptObject getObjectPrototype()
{
    if(_objectPrototype is null)
    {
        _objectPrototype = new ScriptObject("object"); // this is the base prototype for all objects
    }
    return _objectPrototype;
}

ScriptObject getArrayPrototype()
{
    if(_arrayPrototype is null)
    {
        _arrayPrototype = new ScriptObject("array", null);
    }
    return _arrayPrototype;
}

ScriptObject getFunctionPrototype()
{
    if(_functionPrototype is null)
    {
        _functionPrototype = new ScriptObject("function()", null);
        _functionPrototype["call"] = new ScriptFunction("Function.call", &native_Function_call);
    }
    return _functionPrototype;
}

ScriptObject getStringPrototype()
{
    if(_stringPrototype is null)
    {
        _stringPrototype = new ScriptObject("string", null);
    }
    return _stringPrototype;
}

private ScriptObject _objectPrototype;
private ScriptObject _arrayPrototype;
private ScriptObject _functionPrototype;
private ScriptObject _stringPrototype;

//
// Function methods
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