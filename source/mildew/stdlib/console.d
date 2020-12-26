module mildew.stdlib.console;

import mildew.context;
import mildew.interpreter;
import mildew.types;

/// initialize the console library
public void initializeConsoleLibrary(Interpreter interpreter)
{
    auto consoleNamespace = new ScriptObject("Console", null);
    consoleNamespace["log"] = ScriptValue(new ScriptFunction("console.log", &native_console_log));
    consoleNamespace["error"] = ScriptValue(new ScriptFunction("console.error", &native_console_error));
    interpreter.forceSetGlobal("console", consoleNamespace, true);
}

private ScriptValue native_console_log(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    import std.stdio: write, writeln;
    foreach(arg ; args)
        write(arg.toString ~ " ");
    writeln();
    return ScriptValue.UNDEFINED;
}

private ScriptValue native_console_error(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    import std.stdio: stderr;
    foreach(arg ; args)
        stderr.write(arg.toString ~ " ");
    stderr.writeln();
    return ScriptValue.UNDEFINED;
}