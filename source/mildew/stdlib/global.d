/**
 * This module implements script functions that are stored in the global namespace such as parseInt and isdefined.
 * `isdefined` takes a string as an argument, and returns true if a variable with that name is defined anywhere on the stack.
 */
module mildew.stdlib.global;

import mildew.context;
import mildew.interpreter;
import mildew.types;

/**
 * This is called by the interpreter's initializeStdlib method to store functions in the global namespace
 */
void initializeGlobalLibrary(Interpreter interpreter)
{
    interpreter.forceSetGlobal("isdefined", new ScriptFunction("isdefined", &native_isdefined));
}

//
// Global method implementations
//

private ScriptAny native_isdefined(Context context, 
                                   ScriptAny* thisObj, 
                                   ScriptAny[] args, 
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(false);
    auto varToLookup = args[0].toString();
    return ScriptAny(context.variableOrConstExists(varToLookup));
}