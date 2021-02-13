/**
This module implements functions in the System namespace such as getCurrentMillis.
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

