module mildew.stdlib.console;

import mildew.context;
import mildew.interpreter;
import mildew.types;

/// initialize the console library
public void initializeConsoleLibrary(Interpreter interpreter)
{
    auto consoleNamespace = new ScriptObject("Console", null);
    consoleNamespace["log"] = ScriptValue(new ScriptFunction("console.log", &native_console_log));
    interpreter.forceSetGlobal("console", consoleNamespace, true);
}

private ScriptValue native_console_log(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    import std.stdio: writeln;
    if(args.length < 1)
        writeln();
    else
        writeln(args[0].toString());
    return ScriptValue.UNDEFINED;
}