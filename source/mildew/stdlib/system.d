/**
This module implements functions in the System namespace such as currentTimeMillis.
Most applications wanting to embed DMildew probably do not want to load this library.
This can be achieved by loading each individual desired library or using the
standard load libraries method and setting System to ScriptAny.UNDEFINED.
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
 * Initializes the System namespace, which contains the following items:
 * - currentTimeMillis():integer—returns the current time as milliseconds.
 * - gc()—attempt to run a D garbage collection cycle.
 * - getenv():object—returns a hash map of all shell environment variables such as HOME.
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

