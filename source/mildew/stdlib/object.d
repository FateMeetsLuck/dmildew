/**
 * This module implements functions for the "Object" namespace in the scripting language
 */
module mildew.stdlib.object;

import mildew.context;
import mildew.interpreter;
import mildew.types;

// builtins for the Object namespace

/**
 * Initializes the Object library. Interpreter.initializeStdlib calls this function. Functions are
 * stored in the Object global and are accessed such as "Object.keys"
 */
public void initializeObjectLibrary(Interpreter interpreter)
{
    auto objNamespace = new ScriptObject("Object", null);
    objNamespace["create"] = ScriptAny(new ScriptFunction("Object.create", &native_Object_create));
    objNamespace["keys"] = ScriptAny(new ScriptFunction("Object.keys", &native_Object_keys));
    objNamespace["values"] = ScriptAny(new ScriptFunction("Object.values", &native_Object_values));
    interpreter.forceSetGlobal("Object", objNamespace);
}

/**
 * Object.create: This can be called by the script to create a new object whose prototype is the
 * parameter.
 */
private ScriptAny native_Object_create(Context context,  // @suppress(dscanner.style.phobos_naming_convention)
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
private ScriptAny native_Object_keys(Context context,
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
private ScriptAny native_Object_values(Context context,
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