/**
This module implements functions in the System namespace. See
https://pillager86.github.io/dmildew/System.html

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

import core.memory: GC;
import std.datetime.systime;
import std.process: environment;

import mildew.environment;
import mildew.interpreter;
import mildew.types;

/**
 * Initializes the System namespace. Documentation for this library can be found at
 * https://pillager86.github.io/dmildew/System.html
 * Params:
 *  interpreter = The Interpreter instance to load the System namespace into.
 */
void initializeSystemLib(Interpreter interpreter)
{
    auto systemNamespace = new ScriptObject("System", null, null);
    systemNamespace["currentTimeMillis"] = new ScriptFunction("System.currentTimeMillis",
            &native_System_currentTimeMillis);
    systemNamespace["gc"] = new ScriptFunction("System.gc", &native_System_gc);
    systemNamespace["getenv"] = new ScriptFunction("System.getenv", &native_System_getenv);
    interpreter.forceSetGlobal("System", systemNamespace);
}

private:

ScriptAny native_System_currentTimeMillis(Environment environment,
                                          ScriptAny* thisObj,
                                          ScriptAny[] args,
                                          ref NativeFunctionError nfe)
{
    return ScriptAny(Clock.currStdTime() / 10_000);
}

ScriptAny native_System_gc(Environment env,
                           ScriptAny* thisObj,
                           ScriptAny[] args,
                           ref NativeFunctionError nfe)
{
    GC.collect();
    return ScriptAny.UNDEFINED;
}

ScriptAny native_System_getenv(Environment env,
                               ScriptAny* thisObj,
                               ScriptAny[] args,
                               ref NativeFunctionError nfe)
{
    auto aa = environment.toAA();
    auto obj = new ScriptObject("env", null);
    foreach(k,v ; aa)
    {
        obj[k] = ScriptAny(v);
    }
    return ScriptAny(obj);
}

