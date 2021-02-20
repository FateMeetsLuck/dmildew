/**
This module implements the ScriptFiber class, used internally by VirtualMachine
to schedule asynchronous calls to ScriptFunctions.
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
module mildew.vm.fiber;

import core.thread.fiber;

import mildew.types;
import mildew.vm.virtualmachine;

/**
 * This is ultimately the return value of setTimeout
 */
class ScriptFiber : Fiber
{
    /// Constructor
    package this(string name, VirtualMachine vm, ScriptFunction func, ScriptAny thisToUse, ScriptAny[] args)
    {
        _name = name;
        super({
            this._result = vm.runFunction(func, thisToUse, args);
        });
    }

    /// result property
    ScriptAny result() { return _result; }

    /// This is the whole point of this class: to avoid seeing core.thread.fiber.Fiber
    override string toString() const 
    {
        return _name;
    }

private:
    string _name;
    ScriptAny _result;
}