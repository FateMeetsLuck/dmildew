/**
This module implements script functions that are stored in the global namespace such as parseInt and isdefined.
`isdefined` takes a string as an argument, and returns true if a variable with that name is defined anywhere on the stack.
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
module mildew.stdlib.global;

import mildew.environment;
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

private ScriptAny native_isdefined(Environment env, 
                                   ScriptAny* thisObj, 
                                   ScriptAny[] args, 
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(false);
    auto varToLookup = args[0].toString();
    return ScriptAny(env.variableOrConstExists(varToLookup));
}