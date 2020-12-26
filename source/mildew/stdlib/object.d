module mildew.stdlib.object;

import mildew.context;
import mildew.interpreter;
import mildew.types;

// builtins for the Object namespace

/// initializes the library
public void initializeObjectLibrary(Interpreter interpreter)
{
    auto objNamespace = new ScriptObject("Object", null);
    objNamespace["create"] = ScriptValue(new ScriptFunction("Object.create", &native_Object_create));
    interpreter.forceSetGlobal("Object", objNamespace);
}

/// creates an object whose prototype is the argument
private ScriptValue native_Object_create(Context context,  // @suppress(dscanner.style.phobos_naming_convention)
        ScriptValue* thisObj, 
        ScriptValue[] args, 
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptValue.UNDEFINED;
    }

    if(!args[0].isObject)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptValue.UNDEFINED;
    }

    auto newObj = new ScriptObject("", args[0].toValue!ScriptObject);

    return ScriptValue(newObj);
}
