/**
 * This module implements the __proto__ field given to each special object such as ScriptObject, ScriptFunction,
 * ScriptArray, and ScriptString, as well as the static methods for Object, Array, Function, and String
 */
module mildew.types.bindings;

import mildew.context;
import mildew.interpreter;
import mildew.types.any;
import mildew.types.array;
import mildew.types.func;
import mildew.types.string;
import mildew.types.object;

package(mildew):

/**
 * Initializes the bindings of builtin types such as Object, Function, String, and Array. This function is not
 * required because these objects already have their __proto__ set correctly when constructed.
 */
void initializeTypesLibrary(Interpreter interpreter)
{
    ScriptAny Object_ctor = new ScriptFunction("Object", &native_Object_constructor, true);
    Object_ctor["prototype"] = getObjectPrototype();
    Object_ctor["prototype"]["constructor"] = Object_ctor;
    // static Object methods
    Object_ctor["create"] = new ScriptFunction("Object.create", &native_Object_s_create);
    Object_ctor["keys"] = new ScriptFunction("Object.keys", &native_Object_s_keys);
    Object_ctor["values"] = new ScriptFunction("Object.values", &native_Object_s_values);
    interpreter.forceSetGlobal("Object", Object_ctor, false); // maybe should be const
}

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
        _stringPrototype["charAt"] = new ScriptFunction("String.charAt", &native_String_charAt);
        _stringPrototype["charCodeAt"] = new ScriptFunction("String.charCodeAt", &native_String_charCodeAt);
    }
    return _stringPrototype;
}

private ScriptObject _objectPrototype;
private ScriptObject _arrayPrototype;
private ScriptObject _functionPrototype;
private ScriptObject _stringPrototype;

//
// Object methods /////////////////////////////////////////////////////////////
//

private ScriptAny native_Object_constructor(Context c, ScriptAny* thisObj, ScriptAny[] args, 
        ref NativeFunctionError nfe)
{
    if(args.length >= 1)
    {
        if(args[0].isObject)
            *thisObj = args[0];
    }
    return ScriptAny.UNDEFINED;
}

/**
 * Object.create: This can be called by the script to create a new object whose prototype is the
 * parameter.
 */
private ScriptAny native_Object_s_create(Context context,  // @suppress(dscanner.style.phobos_naming_convention)
        ScriptAny* thisObj, 
        ScriptAny[] args, 
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }

    if(!args[0].isObject)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }

    auto newObj = new ScriptObject("", args[0].toValue!ScriptObject);

    return ScriptAny(newObj);
}

/// returns an array of keys of an object (or function)
private ScriptAny native_Object_s_keys(Context context,
        ScriptAny* thisObj,
        ScriptAny[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    
    if(!args[0].isObject)
        return ScriptAny.UNDEFINED;

    auto sobj = args[0].toValue!ScriptObject;
    auto keys = ScriptAny(sobj.dictionary.keys);
    return keys;
}

/// returns an array of values of an object (or function)
private ScriptAny native_Object_s_values(Context context,
        ScriptAny* thisObj,
        ScriptAny[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    
    if(!args[0].isObject)
        return ScriptAny.UNDEFINED;

    auto sobj = args[0].toValue!ScriptObject;
    auto values = ScriptAny(sobj.dictionary.values);
    return values;
}

//
// Array methods //////////////////////////////////////////////////////////////
//


//
// Function methods ///////////////////////////////////////////////////////////
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

//
// String methods /////////////////////////////////////////////////////////////  
//

private ScriptAny native_String_charAt(Context c, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;

    auto ss = thisObj.toValue!ScriptString;
    auto index = args[0].toValue!size_t;

    if(index >= ss.getWString.length)
        return ScriptAny("");

    return ScriptAny([ss.charAt(index)]);
}

private ScriptAny native_String_charCodeAt(Context c, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;

    auto ss = thisObj.toValue!ScriptString;
    auto index = args[0].toValue!size_t;

    if(index >= ss.getWString.length)
        return ScriptAny(0);

    return ScriptAny(ss.charCodeAt(index));
}