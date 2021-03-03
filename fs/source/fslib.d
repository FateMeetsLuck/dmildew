module fslib;

import core.sys.windows.windows;
import core.sys.windows.dll;
import std.stdio;

import mildew.interpreter;
import mildew.environment;
import mildew.exceptions;
import mildew.types;

mixin SimpleDllMain;

export extern(C) void initializeModule(Interpreter interpreter)
{
    auto fs = new ScriptObject("fs", null);
    fs["test"] = new ScriptFunction("fs.test", &native_fs_test);
    interpreter.forceSetGlobal("fs", ScriptAny(fs), false);
}

private ScriptAny native_fs_test(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    writeln("Test function called");
    return ScriptAny.UNDEFINED;
}

