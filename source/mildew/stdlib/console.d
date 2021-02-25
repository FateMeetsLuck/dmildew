/**
This module implements functions for the "console" namespace in the scripting language.
See https://pillager86.github.io/dmildew/console.html for more details.

────────────────────────────────────────────────────────────────────────────────

Copyright (C) 2021 pillager86.rf.gd

This program is free software: you can redistribute it and/or modify it under 
the terms of the GNU General Public License as published by the Free Software 
Foundation, either version 3 of the License, or (at your option) any later 
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with 
this program.  If not, see <https://www.gnu.org/licenses/>.
*/
module mildew.stdlib.console;

import mildew.environment;
import mildew.interpreter;
import mildew.types;

/** 
 * Initializes the console library. This is called by Interpreter.initializeStdlib. The console
 * functions are stored in the "console" global variable and are accessed such as "console.log".
 * Documentation for these functions can be found at https://pillager86.github.io/dmildew/console.html
 * Params:
 *  interpreter = The Interpreter object for which to load the namespace and functions.
 */
public void initializeConsoleLibrary(Interpreter interpreter)
{
    auto consoleNamespace = new ScriptObject("Console", null);
    consoleNamespace["log"] = ScriptAny(new ScriptFunction("console.log", &native_console_log));
    consoleNamespace["put"] = ScriptAny(new ScriptFunction("console.put", &native_console_put));
    consoleNamespace["error"] = ScriptAny(new ScriptFunction("console.error", &native_console_error));
    interpreter.forceSetGlobal("console", consoleNamespace, true);
}

private ScriptAny native_console_log(Environment environment,
                                     ScriptAny* thisObj,
                                     ScriptAny[] args,
                                     ref NativeFunctionError nfe)
{
    import std.stdio: write, writeln;
    if(args.length > 0)
        write(args[0].toString());
    if(args.length > 1)
        foreach(arg ; args[1..$])
            write(" " ~ arg.toString);
    writeln();
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_console_put(Environment environment,
                                     ScriptAny* thisObj,
                                     ScriptAny[] args,
                                     ref NativeFunctionError nfe)
{
import std.stdio: write, writeln;
    if(args.length > 0)
        write(args[0].toString());
    if(args.length > 1)
        foreach(arg ; args[1..$])
            write(" " ~ arg.toString);
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_console_error(Environment environment,
                                       ScriptAny* thisObj,
                                       ScriptAny[] args,
                                       ref NativeFunctionError nfe)
{
    import std.stdio: stderr;
    foreach(arg ; args)
        stderr.write(arg.toString ~ " ");
    stderr.writeln();
    return ScriptAny.UNDEFINED;
}