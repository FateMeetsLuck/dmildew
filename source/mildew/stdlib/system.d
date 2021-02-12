/**
 * This module implements functions in the System namespace such as getCurrentMillis.
 */
module mildew.stdlib.system;

import std.datetime.systime;

import mildew.environment;
import mildew.interpreter;
import mildew.types;

/// initialize System namespace
void initializeSystemLib(Interpreter interpreter)
{
    auto systemNamespace = new ScriptObject("System", null, null);
    systemNamespace["getCurrentMillis"] = new ScriptFunction("System.getCurrentMillis",
            &native_System_getCurrentMillis);
    interpreter.forceSetGlobal("System", systemNamespace);
}

private ScriptAny native_System_getCurrentMillis(Environment environment,
        ScriptAny* thisObj,
        ScriptAny[] args,
        ref NativeFunctionError nfe)
{
    return ScriptAny(Clock.currStdTime() / 10_000);
}

