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
    Object_ctor["entries"] = new ScriptFunction("Object.entries", &native_Object_s_entries);
    Object_ctor["getOwnPropertyDescriptor"] = new ScriptFunction("Object.getOwnPropertyDescriptor", 
            &native_Object_s_getOwnPropertyDescriptor);
    Object_ctor["keys"] = new ScriptFunction("Object.keys", &native_Object_s_keys);
    Object_ctor["values"] = new ScriptFunction("Object.values", &native_Object_s_values);
    interpreter.forceSetGlobal("Object", Object_ctor, false); // maybe should be const

    // Function.call and apply has to be set here. 
    getFunctionPrototype()["call"] = new ScriptFunction("Function.prototype.call", 
        delegate ScriptAny (Context c, ScriptAny* thisIsFn, ScriptAny[] args, ref NativeFunctionError nfe)
        {
            import mildew.exceptions: ScriptRuntimeException;
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
            try 
            {
                return interpreter.callFunction(fn, thisToUse, args);
            }
            catch(ScriptRuntimeException ex)
            {
                nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
                return ScriptAny(ex.msg);
            }
    });

    getFunctionPrototype()["apply"] = new ScriptFunction("Function.prototype.apply", 
        delegate ScriptAny (Context c, ScriptAny* thisIsFn, ScriptAny[] args, ref NativeFunctionError nfe)
        {
            import mildew.exceptions: ScriptRuntimeException;
            // minimum args is 2 because first arg is the this to use and the second is an array
            if(args.length < 2)
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
            // set up the arg array
            if(args[1].type != ScriptAny.Type.ARRAY)
            {
                nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
                return ScriptAny.UNDEFINED;
            }
            auto argList = args[1].toValue!(ScriptAny[]);
            try 
            {
                return interpreter.callFunction(fn, thisToUse, argList);
            }
            catch(ScriptRuntimeException ex)
            {
                nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
                return ScriptAny(ex.msg);
            }
    });
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
        _arrayPrototype["concat"] = new ScriptFunction("Array.prototype.concat", &native_Array_concat);
        _arrayPrototype["join"] = new ScriptFunction("Array.prototype.join", &native_Array_join);
        _arrayPrototype["pop"] = new ScriptFunction("Array.prototype.pop", &native_Array_pop);
        _arrayPrototype["push"] = new ScriptFunction("Array.prototype.push", &native_Array_push);
        _arrayPrototype["splice"] = new ScriptFunction("Array.prototype.splice", &native_Array_splice);
    }
    return _arrayPrototype;
}

ScriptObject getFunctionPrototype()
{
    import mildew.exceptions: ScriptRuntimeException;
    if(_functionPrototype is null)
    {
        _functionPrototype = new ScriptObject("function", null);
        // _functionPrototype["call"] = new ScriptFunction("Function.prototype.call", &native_Function_call);
        /**/
    }
    return _functionPrototype;
}

ScriptObject getStringPrototype()
{
    if(_stringPrototype is null)
    {
        _stringPrototype = new ScriptObject("string", null);
        _stringPrototype["charAt"] = new ScriptFunction("String.prototype.charAt", &native_String_charAt);
        _stringPrototype["charCodeAt"] = new ScriptFunction("String.prototype.charCodeAt", 
                &native_String_charCodeAt);
        _stringPrototype["split"] = new ScriptFunction("String.prototype.split", &native_String_split);
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

/// Returns an array of 2-element arrays representing the key and value of each dictionary entry
private ScriptAny native_Object_s_entries(Context context,
                                        ScriptAny* thisObj,
                                        ScriptAny[] args,
                                        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    
    if(!args[0].isObject)
        return ScriptAny.UNDEFINED;
    
    ScriptAny[][] entries;
    foreach(key, value ; args[0].toValue!ScriptObject.dictionary)
    {
        entries ~= [ScriptAny(key), value];
    }
    return ScriptAny(entries);
}

/// Returns a possible getter or setter for an object
private ScriptAny native_Object_s_getOwnPropertyDescriptor(Context context,
                                                        ScriptAny* thisObj,
                                                        ScriptAny[] args,
                                                        ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptAny.UNDEFINED;
    if(!args[0].isObject)
        return ScriptAny.UNDEFINED;
    auto propName = args[1].toString();
    return ScriptAny(args[0].toValue!ScriptObject.getOwnPropertyDescriptor(propName));
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

private ScriptAny native_Array_concat(Context c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    if(args.length < 1)
        return *thisObj;
    ScriptAny[] result = thisObj.toValue!ScriptArray.array;
    if(args[0].type != ScriptAny.Type.ARRAY)
    {
        result ~= args[0];
    }
    else
    {
        result ~= args[0].toValue!ScriptArray.array;
    }
    return ScriptAny(result);
}

private ScriptAny native_Array_join(Context c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto join = ",";
    if(args.length > 0)
        join = args[0].toString();
    auto arr = thisObj.toValue!(string[]);
    string result = "";
    for(size_t i = 0; i < arr.length; ++i)
    {
        result ~= arr[i];
        if(i < arr.length - 1)
            result ~= join;
    }
    return ScriptAny(result);
}

private ScriptAny native_Array_push(Context c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    if(args.length < 0)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    arr.array ~= args[0];
    return ScriptAny(arr.array.length);
}

private ScriptAny native_Array_pop(Context c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    if(arr.array.length < 1)
        return ScriptAny.UNDEFINED;
    auto result = arr.array[$-1];
    arr.array = arr.array[0..$-1];
    return result;
}

private ScriptAny native_Array_splice(Context c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.algorithm: min;
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    immutable start = min(args[0].toValue!size_t, arr.array.length - 1);
    if(start >= arr.array.length)
        return ScriptAny.UNDEFINED;
    immutable deleteCount = args.length > 1 ? min(args[1].toValue!size_t, arr.array.length) : arr.array.length - start;
    ScriptAny[] removed = [];
    if(args.length > 2)
        args = args[2 .. $];
    else
        args = [];
    // copy elements up to start
    ScriptAny[] result = arr.array[0 .. start];
    // add new elements supplied as args
    result ~= args;
    // copy removed items to removed array
    removed ~= arr.array[start .. start+deleteCount];
    // add those after start plus delete count
    result ~= arr.array[start+deleteCount .. $];
    // set the original array
    arr.array = result;
    // return the removed items
    return ScriptAny(removed);
}

//
// Function methods ///////////////////////////////////////////////////////////
//

/*private ScriptAny native_Function_call(Context c, ScriptAny* thisIsFn, ScriptAny[] args, 
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
}*/

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

private ScriptAny native_String_split(Context c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.array: split;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    auto splitter = ",";
    if(args.length > 0)
        splitter = args[0].toString();
    auto splitResult = thisObj.toString().split(splitter);
    return ScriptAny(splitResult);
}