/**
This external module implements file system operations. It may only be loaded in non-Windows environments with the
--lib=fs option of the REPL.

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
module fslib;

version(Windows)
{
import core.sys.windows.windows;
import core.sys.windows.dll;
}
import std.file;
import std.stdio;

import mildew.interpreter;
import mildew.environment;
import mildew.exceptions;
import mildew.types;

version(Windows)
{
mixin SimpleDllMain;
}

export extern(C) void initializeModule(Interpreter interpreter)
{
    auto fs = new ScriptObject("fs", null);
    fs["readdirSync"] = new ScriptFunction("fs.readdirSync", &native_fs_readdirSync);
    fs["test"] = new ScriptFunction("fs.test", &native_fs_test);
    interpreter.forceSetGlobal("fs", ScriptAny(fs), false);
}

private ScriptAny native_fs_readdirSync(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto directory = args[0].toString();
    ScriptAny[] entries;
    foreach(entry ; dirEntries(directory, SpanMode.shallow))
        entries ~= ScriptAny(entry.name());
    return ScriptAny(entries);
}

private ScriptAny native_fs_test(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    writeln("Test function called");
    if(args.length < 1)
        throw new ScriptRuntimeException("Must provide one argument");
    auto num = args[0].toValue!double;
    return ScriptAny(num * 2.0);
}
